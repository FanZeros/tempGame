-- ============================================================================
-- 下雨天气效果测试 Demo
-- Rain Weather Effect Test Demo
-- 功能：3D粒子雨滴 + 雾效氛围 + 暗色光照 + NanoVG屏幕雨丝 + 地面飞溅
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 全局变量
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
local yaw_ = 0.0
local pitch_ = -15.0  -- 稍微低头看地面

-- 雨滴配置
local RAIN = {
    -- 粒子数量
    dropCount     = 800,
    -- 雨滴下落区域（以相机为中心的方形区域）
    areaWidth     = 30.0,    -- 水平范围 (X)
    areaDepth     = 30.0,    -- 水平范围 (Z)
    areaTop       = 20.0,    -- 顶部高度
    areaBottom    = -1.0,    -- 底部高度（地面以下回收）
    -- 雨滴速度
    fallSpeed     = 18.0,    -- 下落速度 (m/s)
    windSpeed     = 3.0,     -- 风速偏移 (m/s) 向X正方向
    -- 雨滴视觉
    dropWidth     = 0.02,    -- 雨滴宽度
    dropHeight    = 0.6,     -- 雨滴高度（拉长的线条状）
    dropColor     = {180, 200, 220, 120},  -- RGBA
}

-- 飞溅配置
local SPLASH = {
    maxCount   = 60,
    lifetime   = 0.3,
    size       = 0.15,
}

-- 相机配置
local CONFIG = {
    CameraSpeed = 10.0,
    MouseSensitivity = 0.1,
}

-- 雨滴数据
local rainDrops_ = {}    -- {x, y, z, speedVariation}
local splashes_ = {}     -- {x, y, z, life, maxLife}
local splashTimer_ = 0

-- NanoVG 屏幕雨丝
local screenRainLines_ = {}  -- {x, y, len, speed, alpha}
local SCREEN_RAIN_COUNT = 80

-- BillboardSet 组件
---@type BillboardSet
local rainBillboard_ = nil
---@type BillboardSet
local splashBillboard_ = nil

-- NanoVG 上下文
local nvgCtx_ = nil

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "Rain Weather Demo"

    -- 创建 NanoVG 上下文
    nvgCtx_ = nvgCreate(1)
    if not nvgCtx_ then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    InitUI()
    CreateScene()
    SetupCamera()
    CreateRainSystem()
    CreateUI()
    InitScreenRain()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleNanoVGRender")

    print("=== Rain Weather Demo Started ===")
end

function Stop()
    if nvgCtx_ then
        nvgDelete(nvgCtx_)
        nvgCtx_ = nil
    end
    UI.Shutdown()
end

-- ============================================================================
-- UI 初始化
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function CreateUI()
    local uiRoot = UI.Panel {
        id = "rainUI",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Label {
                text = "Rain Weather Demo | WASD: Move | Mouse Right: Look | Space: Up | C: Down",
                fontSize = 12,
                fontColor = { 200, 220, 255, 200 },
                position = "absolute",
                top = 10,
                left = 0,
                right = 0,
                textAlign = "center",
            },
        }
    }
    UI.SetRoot(uiRoot)
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- 使用 Night 光照预设（偏暗，模拟阴天雨天）
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Night.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    -- 添加额外的 Zone 覆盖雾效（灰蒙蒙的雨天感）
    local zoneNode = scene_:CreateChild("RainZone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-500, -500, -500), Vector3(500, 500, 500))
    zone.ambientColor = Color(0.15, 0.16, 0.18)
    zone.fogColor = Color(0.35, 0.38, 0.42)
    zone.fogStart = 20.0
    zone.fogEnd = 80.0
    zone.priority = 10  -- 高优先级覆盖 LightGroup 的 Zone

    -- 创建地面
    CreateGround()

    -- 创建一些场景物体供参照
    CreateSceneObjects()
end

function CreateGround()
    -- 大地面
    local floorNode = scene_:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.05, 0)
    floorNode.scale = Vector3(100, 0.1, 100)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))

    local floorMat = Material:new()
    floorMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    floorMat:SetShaderParameter("MatDiffColor", Variant(Color(0.15, 0.15, 0.17, 1.0)))
    floorMat:SetShaderParameter("Metallic", Variant(0.1))
    floorMat:SetShaderParameter("Roughness", Variant(0.4))  -- 湿润的地面偏光滑
    floorModel:SetMaterial(floorMat)
    floorModel.castShadows = false
end

function CreateSceneObjects()
    -- 几个柱子做参照物
    for i = 1, 6 do
        local angle = (i - 1) * 60 * math.pi / 180
        local dist = 10.0
        local px = math.cos(angle) * dist
        local pz = math.sin(angle) * dist

        local pillarNode = scene_:CreateChild("Pillar" .. i)
        pillarNode.position = Vector3(px, 1.5, pz)
        pillarNode.scale = Vector3(0.6, 3.0, 0.6)
        local pillarModel = pillarNode:CreateComponent("StaticModel")
        pillarModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))

        local pillarMat = Material:new()
        pillarMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        pillarMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.28, 0.25, 1.0)))
        pillarMat:SetShaderParameter("Metallic", Variant(0.0))
        pillarMat:SetShaderParameter("Roughness", Variant(0.7))
        pillarModel:SetMaterial(pillarMat)
        pillarModel.castShadows = true
    end

    -- 一个金属球体
    local sphereNode = scene_:CreateChild("Sphere")
    sphereNode.position = Vector3(0, 1.0, 5)
    local sphereModel = sphereNode:CreateComponent("StaticModel")
    sphereModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))

    local sphereMat = Material:new()
    sphereMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    sphereMat:SetShaderParameter("MatDiffColor", Variant(Color(0.6, 0.62, 0.65, 1.0)))
    sphereMat:SetShaderParameter("Metallic", Variant(0.9))
    sphereMat:SetShaderParameter("Roughness", Variant(0.15))  -- 湿润金属
    sphereModel:SetMaterial(sphereMat)
    sphereModel.castShadows = true
end

-- ============================================================================
-- 雨滴粒子系统（BillboardSet 手动管理）
-- ============================================================================

function CreateRainSystem()
    -- ── 雨滴 Billboard ──
    local rainNode = scene_:CreateChild("RainDrops")
    rainBillboard_ = rainNode:CreateComponent("BillboardSet")
    rainBillboard_.numBillboards = RAIN.dropCount
    rainBillboard_.sorted = false
    rainBillboard_.relative = false  -- 使用世界坐标
    rainBillboard_.scaled = false
    rainBillboard_.faceCameraMode = FC_ROTATE_Y  -- 只绕Y旋转朝向相机

    -- 雨滴材质（半透明无纹理）
    local rainMat = Material:new()
    rainMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    rainMat:SetShaderParameter("MatDiffColor", Variant(Color(
        RAIN.dropColor[1] / 255,
        RAIN.dropColor[2] / 255,
        RAIN.dropColor[3] / 255,
        RAIN.dropColor[4] / 255
    )))
    rainMat:SetShaderParameter("Metallic", Variant(0.0))
    rainMat:SetShaderParameter("Roughness", Variant(0.3))
    rainBillboard_:SetMaterial(rainMat)

    -- 初始化雨滴位置
    local camPos = cameraNode_ and cameraNode_.worldPosition or Vector3(0, 5, 0)
    for i = 1, RAIN.dropCount do
        local x = camPos.x + (math.random() - 0.5) * RAIN.areaWidth
        local y = math.random() * (RAIN.areaTop - RAIN.areaBottom) + RAIN.areaBottom
        local z = camPos.z + (math.random() - 0.5) * RAIN.areaDepth
        local speedVar = 0.8 + math.random() * 0.4  -- 速度变化 0.8~1.2

        rainDrops_[i] = { x = x, y = y, z = z, speedVar = speedVar }

        local bb = rainBillboard_:GetBillboard(i - 1)
        bb.position = Vector3(x, y, z)
        bb.size = Vector2(RAIN.dropWidth, RAIN.dropHeight * speedVar)
        bb.color = Color(
            RAIN.dropColor[1] / 255,
            RAIN.dropColor[2] / 255,
            RAIN.dropColor[3] / 255,
            (RAIN.dropColor[4] / 255) * (0.5 + math.random() * 0.5)
        )
        bb.enabled = true
        bb.rotation = 0
    end
    rainBillboard_:Commit()

    -- ── 飞溅 Billboard ──
    local splashNode = scene_:CreateChild("RainSplash")
    splashBillboard_ = splashNode:CreateComponent("BillboardSet")
    splashBillboard_.numBillboards = SPLASH.maxCount
    splashBillboard_.sorted = false
    splashBillboard_.relative = false
    splashBillboard_.scaled = false
    splashBillboard_.faceCameraMode = FC_ROTATE_Y

    local splashMat = Material:new()
    splashMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    splashMat:SetShaderParameter("MatDiffColor", Variant(Color(0.7, 0.75, 0.8, 0.4)))
    splashMat:SetShaderParameter("Metallic", Variant(0.0))
    splashMat:SetShaderParameter("Roughness", Variant(0.5))
    splashBillboard_:SetMaterial(splashMat)

    -- 初始化飞溅为全部禁用
    for i = 1, SPLASH.maxCount do
        local bb = splashBillboard_:GetBillboard(i - 1)
        bb.enabled = false
        splashes_[i] = { x = 0, y = 0, z = 0, life = 0, maxLife = SPLASH.lifetime }
    end
    splashBillboard_:Commit()
end

-- ============================================================================
-- 屏幕雨丝（NanoVG 2D 叠加）
-- ============================================================================

function InitScreenRain()
    for i = 1, SCREEN_RAIN_COUNT do
        screenRainLines_[i] = {
            x     = math.random() * 2000,
            y     = math.random() * 1500,
            len   = 15 + math.random() * 35,
            speed = 600 + math.random() * 400,
            alpha = 20 + math.random() * 40,
        }
    end
end

-- ============================================================================
-- 相机设置
-- ============================================================================

function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_.position = Vector3(0, 3, -8)

    local camera = cameraNode_:CreateComponent("Camera")
    camera.nearClip = 0.1
    camera.farClip = 200.0
    camera.fov = 75.0

    cameraNode_.rotation = Quaternion(pitch_, yaw_, 0)

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    HandleCameraMovement(dt)
    UpdateRainDrops(dt)
    UpdateSplashes(dt)
    UpdateScreenRain(dt)
end

-- 更新雨滴下落
function UpdateRainDrops(dt)
    local camPos = cameraNode_.worldPosition
    local halfW = RAIN.areaWidth * 0.5
    local halfD = RAIN.areaDepth * 0.5
    local needCommit = false

    splashTimer_ = splashTimer_ + dt

    for i = 1, RAIN.dropCount do
        local drop = rainDrops_[i]

        -- 下落 + 风力
        drop.y = drop.y - RAIN.fallSpeed * drop.speedVar * dt
        drop.x = drop.x + RAIN.windSpeed * dt

        -- 到达底部：回收并生成飞溅
        if drop.y < RAIN.areaBottom then
            -- 触发飞溅效果
            if splashTimer_ > 0.005 then  -- 限制飞溅频率
                SpawnSplash(drop.x, 0.02, drop.z)
                splashTimer_ = 0
            end

            -- 重置到顶部（相对于相机位置）
            drop.x = camPos.x + (math.random() - 0.5) * RAIN.areaWidth
            drop.y = RAIN.areaTop + math.random() * 3
            drop.z = camPos.z + (math.random() - 0.5) * RAIN.areaDepth
            drop.speedVar = 0.8 + math.random() * 0.4
        end

        -- 超出相机范围也重置
        if math.abs(drop.x - camPos.x) > halfW + 5 or
           math.abs(drop.z - camPos.z) > halfD + 5 then
            drop.x = camPos.x + (math.random() - 0.5) * RAIN.areaWidth
            drop.y = math.random() * RAIN.areaTop
            drop.z = camPos.z + (math.random() - 0.5) * RAIN.areaDepth
        end

        -- 更新 billboard
        local bb = rainBillboard_:GetBillboard(i - 1)
        bb.position = Vector3(drop.x, drop.y, drop.z)
        bb.size = Vector2(RAIN.dropWidth, RAIN.dropHeight * drop.speedVar)
        needCommit = true
    end

    if needCommit then
        rainBillboard_:Commit()
    end
end

-- 生成飞溅
function SpawnSplash(x, y, z)
    -- 找一个空闲的飞溅槽位
    for i = 1, SPLASH.maxCount do
        local sp = splashes_[i]
        if sp.life <= 0 then
            sp.x = x + (math.random() - 0.5) * 0.3
            sp.y = y
            sp.z = z + (math.random() - 0.5) * 0.3
            sp.life = SPLASH.lifetime
            sp.maxLife = SPLASH.lifetime

            local bb = splashBillboard_:GetBillboard(i - 1)
            bb.position = Vector3(sp.x, sp.y, sp.z)
            bb.size = Vector2(SPLASH.size, SPLASH.size * 0.3)
            bb.color = Color(0.7, 0.75, 0.8, 0.5)
            bb.enabled = true
            return
        end
    end
end

-- 更新飞溅
function UpdateSplashes(dt)
    local needCommit = false
    for i = 1, SPLASH.maxCount do
        local sp = splashes_[i]
        if sp.life > 0 then
            sp.life = sp.life - dt
            local t = math.max(0, sp.life / sp.maxLife)  -- 1→0

            local bb = splashBillboard_:GetBillboard(i - 1)
            if sp.life <= 0 then
                bb.enabled = false
            else
                -- 扩大并淡出
                local scale = 1.0 + (1.0 - t) * 1.5
                bb.size = Vector2(SPLASH.size * scale, SPLASH.size * 0.3 * scale)
                bb.color = Color(0.7, 0.75, 0.8, 0.5 * t)
            end
            needCommit = true
        end
    end
    if needCommit then
        splashBillboard_:Commit()
    end
end

-- 更新屏幕雨丝数据
function UpdateScreenRain(dt)
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = physW / dpr
    local logH = physH / dpr

    for i = 1, SCREEN_RAIN_COUNT do
        local line = screenRainLines_[i]
        line.y = line.y + line.speed * dt
        if line.y > logH + line.len then
            line.y = -line.len - math.random() * 100
            line.x = math.random() * logW
            line.len = 15 + math.random() * 35
            line.speed = 600 + math.random() * 400
            line.alpha = 20 + math.random() * 40
        end
    end
end

-- ============================================================================
-- NanoVG 渲染（屏幕雨丝叠加）
-- ============================================================================

local fontCreated_ = false

---@param eventType string
---@param eventData VariantMap
function HandleNanoVGRender(eventType, eventData)
    if not nvgCtx_ then return end

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = physW / dpr
    local logH = physH / dpr

    nvgBeginFrame(nvgCtx_, logW, logH, dpr)

    if not fontCreated_ then
        nvgCreateFont(nvgCtx_, "sans", "Fonts/MiSans-Regular.ttf")
        fontCreated_ = true
    end

    -- 屏幕雨丝效果
    local windAngle = math.atan(RAIN.windSpeed, RAIN.fallSpeed)  -- 风的倾斜角度

    for i = 1, SCREEN_RAIN_COUNT do
        local line = screenRainLines_[i]
        local endX = line.x + math.sin(windAngle) * line.len
        local endY = line.y + math.cos(windAngle) * line.len

        nvgBeginPath(nvgCtx_)
        nvgMoveTo(nvgCtx_, line.x, line.y)
        nvgLineTo(nvgCtx_, endX, endY)
        nvgStrokeColor(nvgCtx_, nvgRGBA(180, 200, 220, math.floor(line.alpha)))
        nvgStrokeWidth(nvgCtx_, 1.0)
        nvgStroke(nvgCtx_)
    end

    -- 底部轻微蓝灰色遮罩（模拟雨雾）
    local fogGrad = nvgLinearGradient(nvgCtx_, 0, logH * 0.7, 0, logH,
        nvgRGBA(100, 110, 125, 0),
        nvgRGBA(100, 110, 125, 30))
    nvgBeginPath(nvgCtx_)
    nvgRect(nvgCtx_, 0, logH * 0.7, logW, logH * 0.3)
    nvgFillPaint(nvgCtx_, fogGrad)
    nvgFill(nvgCtx_)

    -- 顶部轻微暗色遮罩（模拟乌云）
    local cloudGrad = nvgLinearGradient(nvgCtx_, 0, 0, 0, logH * 0.3,
        nvgRGBA(40, 45, 55, 50),
        nvgRGBA(40, 45, 55, 0))
    nvgBeginPath(nvgCtx_)
    nvgRect(nvgCtx_, 0, 0, logW, logH * 0.3)
    nvgFillPaint(nvgCtx_, cloudGrad)
    nvgFill(nvgCtx_)

    nvgEndFrame(nvgCtx_)
end

-- ============================================================================
-- 相机控制
-- ============================================================================

function HandleCameraMovement(dt)
    -- 鼠标右键控制视角
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local mx = input.mouseMoveX
        local my = input.mouseMoveY
        yaw_ = yaw_ + mx * CONFIG.MouseSensitivity
        pitch_ = pitch_ + my * CONFIG.MouseSensitivity
        pitch_ = Clamp(pitch_, -90.0, 90.0)
        cameraNode_.rotation = Quaternion(pitch_, yaw_, 0)
    end

    -- 键盘移动
    local speed = CONFIG.CameraSpeed
    if input:GetKeyDown(KEY_SHIFT) then
        speed = speed * 2.0
    end

    if input:GetKeyDown(KEY_W) then
        cameraNode_:Translate(Vector3(0, 0, 1) * dt * speed)
    end
    if input:GetKeyDown(KEY_S) then
        cameraNode_:Translate(Vector3(0, 0, -1) * dt * speed)
    end
    if input:GetKeyDown(KEY_A) then
        cameraNode_:Translate(Vector3(-1, 0, 0) * dt * speed)
    end
    if input:GetKeyDown(KEY_D) then
        cameraNode_:Translate(Vector3(1, 0, 0) * dt * speed)
    end
    if input:GetKeyDown(KEY_SPACE) then
        cameraNode_:Translate(Vector3(0, 1, 0) * dt * speed, TS_WORLD)
    end
    if input:GetKeyDown(KEY_C) then
        cameraNode_:Translate(Vector3(0, -1, 0) * dt * speed, TS_WORLD)
    end
end

function Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end
