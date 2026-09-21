-- 现实灯光感知验证：真实 candela 值
require "LuaScripts/Utilities/Sample"

local yaw = 0
local pitch = -15

-- 存储每种灯的 Light 组件引用，用于开关
local lightRefs = {}
-- Zone 引用，用于切换 auto-exposure
local sceneZone = nil

function Start()
    SampleStart()
    CreateScene()
    SetupCamera()
    SetupViewport()
    SubscribeToEvents()
end

-- ── 材质工具 ──

local function MakeMat(r, g, b, rough, metal)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Vector4(r, g, b, 1)))
    mat:SetShaderParameter("Roughness", Variant(rough or 0.7))
    mat:SetShaderParameter("Metallic", Variant(metal or 0))
    return mat
end

local function MakeEmissive(r, g, b, i)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Vector4(r, g, b, 1)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Vector3(r * i, g * i, b * i)))
    mat:SetShaderParameter("Roughness", Variant(1))
    mat:SetShaderParameter("Metallic", Variant(0))
    return mat
end

local function Box(parent, pos, scale, mat)
    local n = parent:CreateChild("")
    n.position = pos; n.scale = scale
    local m = n:CreateComponent("StaticModel")
    m:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    m:SetMaterial(mat)
    return n
end

local function Sphere(parent, pos, scale, mat)
    local n = parent:CreateChild("")
    n.position = pos; n.scale = scale
    local m = n:CreateComponent("StaticModel")
    m:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    m:SetMaterial(mat)
    return n
end

-- ── 灯光配置 ──

-- maxCd / maxRange 是滑杆量程上限，按每种灯具的合理范围设置，便于精细调节
local lightDefs = {
    {
        label = "Candle",
        color = Color(1.0, 0.7, 0.3),
        cd    = 1,          -- 蜡烛 ~12 lm / 4π ≈ 1 cd
        range = 4,
        maxCd = 10, maxRange = 10,
        x = -24,
        defaultOn = true,
    },
    {
        label = "DeskLamp",
        color = Color(1.0, 0.95, 0.8),
        cd    = 30,         -- 实测对齐 UE 后的舒适值
        range = 10,
        maxCd = 300, maxRange = 25,
        x = -8,
        defaultOn = true,
    },
    {
        label = "Campfire",
        color = Color(1.0, 0.55, 0.15),
        cd    = 80,         -- 实测对齐 UE 后的舒适值
        range = 15,
        maxCd = 800, maxRange = 30,
        x = 10,
        defaultOn = true,
    },
    {
        label = "StreetLamp",
        color = Color(1.0, 0.9, 0.65),
        cd    = 500,        -- 实测对齐 UE 后的舒适值
        range = 25,
        maxCd = 5000, maxRange = 60,
        x = 30,
        defaultOn = true,
    },
    {
        label = "Headlight",
        color = Color(1.0, 1.0, 0.95),
        cd    = 25000,      -- 车大灯 ~20000-30000 cd
        range = 40,
        maxCd = 80000, maxRange = 100,
        x = 55,
        isSpot = true, fov = 40,
        defaultOn = false,
    },
}

-- ── 创建光源 ──

local function AttachLight(node, def, isSpot)
    local l = node:CreateComponent("Light")
    l.lightType = isSpot and LIGHT_SPOT or LIGHT_POINT
    l.color = def.color
    l.range = def.range
    if isSpot then l.fov = def.fov end
    l.castShadows = (isSpot == true)
    l.brightness = def.cd
    l.enabled = def.defaultOn
    return l
end

local woodMat, metalMat

local function BuildCandle(root, def)
    Box(root, Vector3(0, 0.75, 0), Vector3(1.2, 0.05, 0.8), woodMat)
    Box(root, Vector3(-0.5, 0.375, -0.3), Vector3(0.07, 0.75, 0.07), woodMat)
    Box(root, Vector3(0.5, 0.375, -0.3), Vector3(0.07, 0.75, 0.07), woodMat)
    Box(root, Vector3(-0.5, 0.375, 0.3), Vector3(0.07, 0.75, 0.07), woodMat)
    Box(root, Vector3(0.5, 0.375, 0.3), Vector3(0.07, 0.75, 0.07), woodMat)
    Box(root, Vector3(0, 0.84, 0), Vector3(0.05, 0.12, 0.05), MakeMat(0.9, 0.88, 0.82, 0.6))
    Sphere(root, Vector3(0, 0.93, 0), Vector3(0.04, 0.06, 0.04), MakeEmissive(1, 0.7, 0.2, 5))
    Box(root, Vector3(0.4, 0.25, -0.7), Vector3(0.4, 0.5, 0.4), woodMat)
    local ln = root:CreateChild("light")
    ln.position = Vector3(0, 0.95, 0)
    return { AttachLight(ln, def, false) }
end

local function BuildDeskLamp(root, def)
    Box(root, Vector3(0, 0.75, 0), Vector3(1.4, 0.05, 0.7), MakeMat(0.45, 0.32, 0.18, 0.7))
    Box(root, Vector3(-0.6, 0.375, -0.25), Vector3(0.06, 0.75, 0.06), metalMat)
    Box(root, Vector3(0.6, 0.375, -0.25), Vector3(0.06, 0.75, 0.06), metalMat)
    Box(root, Vector3(-0.6, 0.375, 0.25), Vector3(0.06, 0.75, 0.06), metalMat)
    Box(root, Vector3(0.6, 0.375, 0.25), Vector3(0.06, 0.75, 0.06), metalMat)
    Box(root, Vector3(-0.4, 0.80, 0), Vector3(0.14, 0.04, 0.14), metalMat)
    Box(root, Vector3(-0.4, 0.95, 0), Vector3(0.03, 0.26, 0.03), metalMat)
    Sphere(root, Vector3(-0.4, 1.10, 0), Vector3(0.08, 0.08, 0.08), MakeEmissive(1, 0.95, 0.8, 4))
    Box(root, Vector3(0.2, 0.80, -0.05), Vector3(0.2, 0.03, 0.15), MakeMat(0.15, 0.25, 0.5, 0.8))
    Box(root, Vector3(0.25, 0.83, 0.12), Vector3(0.18, 0.03, 0.14), MakeMat(0.5, 0.15, 0.15, 0.8))
    local ln = root:CreateChild("light")
    ln.position = Vector3(-0.4, 1.08, 0)
    return { AttachLight(ln, def, false) }
end

local function BuildCampfire(root, def)
    local stoneMat = MakeMat(0.25, 0.23, 0.2, 0.9)
    for i = 0, 7 do
        local a = math.rad(i * 45)
        Box(root, Vector3(math.cos(a) * 0.6, 0.1, math.sin(a) * 0.6), Vector3(0.2, 0.2, 0.2), stoneMat)
    end
    Box(root, Vector3(-0.12, 0.14, 0), Vector3(0.07, 0.07, 0.55), woodMat)
    Box(root, Vector3(0.12, 0.14, 0), Vector3(0.07, 0.07, 0.55), woodMat)
    Box(root, Vector3(0, 0.2, -0.08), Vector3(0.45, 0.06, 0.06), woodMat)
    Sphere(root, Vector3(0, 0.35, 0), Vector3(0.25, 0.35, 0.25), MakeEmissive(1, 0.5, 0.1, 8))
    Sphere(root, Vector3(0, 0.52, 0), Vector3(0.1, 0.18, 0.1), MakeEmissive(1, 0.8, 0.2, 6))
    Box(root, Vector3(-1.2, 0.2, 0.9), Vector3(0.6, 0.4, 0.3), woodMat)
    Box(root, Vector3(1.0, 0.2, -0.8), Vector3(0.6, 0.4, 0.3), woodMat)
    local ln = root:CreateChild("light")
    ln.position = Vector3(0, 0.45, 0)
    return { AttachLight(ln, def, false) }
end

local function BuildStreetLamp(root, def)
    Box(root, Vector3(0, 2.25, 0), Vector3(0.1, 4.5, 0.1), metalMat)
    Box(root, Vector3(0, 4.55, 0), Vector3(0.5, 0.1, 0.3), metalMat)
    Sphere(root, Vector3(0, 4.42, 0), Vector3(0.2, 0.12, 0.2), MakeEmissive(1, 0.9, 0.65, 6))
    Box(root, Vector3(2.5, 0.25, 1), Vector3(1.5, 0.06, 0.35), woodMat)
    Box(root, Vector3(1.9, 0.125, 1), Vector3(0.06, 0.25, 0.3), metalMat)
    Box(root, Vector3(3.1, 0.125, 1), Vector3(0.06, 0.25, 0.3), metalMat)
    Box(root, Vector3(-1.5, 0.35, 0.4), Vector3(0.35, 0.7, 0.35), metalMat)
    local ln = root:CreateChild("light")
    ln.position = Vector3(0, 4.4, 0)
    return { AttachLight(ln, def, false) }
end

local function BuildHeadlight(root, def)
    local bodyMat = MakeMat(0.12, 0.12, 0.35, 0.3, 0.6)
    local wheelMat = MakeMat(0.05, 0.05, 0.05, 0.9)
    Box(root, Vector3(0, 0.4, 0), Vector3(1.8, 0.45, 3.8), MakeMat(0.1, 0.1, 0.1, 0.5, 0.3))
    Box(root, Vector3(0, 0.85, -0.3), Vector3(1.5, 0.45, 1.8), bodyMat)
    Box(root, Vector3(-0.85, 0.2, 1.1), Vector3(0.18, 0.4, 0.4), wheelMat)
    Box(root, Vector3(0.85, 0.2, 1.1), Vector3(0.18, 0.4, 0.4), wheelMat)
    Box(root, Vector3(-0.85, 0.2, -1.1), Vector3(0.18, 0.4, 0.4), wheelMat)
    Box(root, Vector3(0.85, 0.2, -1.1), Vector3(0.18, 0.4, 0.4), wheelMat)
    Sphere(root, Vector3(-0.55, 0.5, 1.9), Vector3(0.12, 0.08, 0.04), MakeEmissive(1, 1, 0.95, 5))
    Sphere(root, Vector3(0.55, 0.5, 1.9), Vector3(0.12, 0.08, 0.04), MakeEmissive(1, 1, 0.95, 5))
    Sphere(root, Vector3(-0.65, 0.5, -1.9), Vector3(0.08, 0.05, 0.03), MakeEmissive(1, 0.08, 0.03, 4))
    Sphere(root, Vector3(0.65, 0.5, -1.9), Vector3(0.08, 0.05, 0.03), MakeEmissive(1, 0.08, 0.03, 4))
    local hl1 = root:CreateChild("HL_L")
    hl1.position = Vector3(-0.55, 0.5, 1.9)
    hl1.direction = Vector3(0, -0.05, 1):Normalized()
    local hl2 = root:CreateChild("HL_R")
    hl2.position = Vector3(0.55, 0.5, 1.9)
    hl2.direction = Vector3(0, -0.05, 1):Normalized()
    return { AttachLight(hl1, def, true), AttachLight(hl2, def, true) }
end

local builders = {
    Candle     = BuildCandle,
    DeskLamp   = BuildDeskLamp,
    Campfire   = BuildCampfire,
    StreetLamp = BuildStreetLamp,
    Headlight  = BuildHeadlight,
}

-- ── 场景 ──

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    local lgFile = cache:GetResource("XMLFile", "LightGroup/Night.xml")
    local lgNode = scene_:CreateChild("LightGroup")
    lgNode:LoadXML(lgFile:GetRoot())
    lgNode:GetComponent("Light", true).brightness = 0.0

    sceneZone = lgNode:GetComponent("Zone", true)
    sceneZone.fogStart = 80
    sceneZone.fogEnd = 250
    sceneZone.autoExposureEnabled = true

    local SkyUtils = require "urhox-libs.Rendering.SkyUtils"
    SkyUtils.CreateGradientSky(scene_, {
        zenith  = Color(0.01, 0.02, 0.06),
        horizon = Color(0.03, 0.04, 0.08),
        ground  = Color(0.02, 0.02, 0.03),
    })

    woodMat = MakeMat(0.35, 0.2, 0.1, 0.8)
    metalMat = MakeMat(0.2, 0.2, 0.2, 0.3, 0.7)

    Box(scene_, Vector3(0, -0.5, 0), Vector3(200, 1, 200), MakeMat(0.12, 0.12, 0.10, 0.9))

    local whiteMat = MakeMat(0.85, 0.85, 0.85, 0.4)

    for _, def in ipairs(lightDefs) do
        local root = scene_:CreateChild(def.label)
        root.position = Vector3(def.x, 0, 0)

        local builder = builders[def.label]
        if builder then
            lightRefs[def.label] = builder(root, def)
        end

        Box(root, Vector3(2, 0.5, 1), Vector3(1, 1, 1), whiteMat)
        Box(root, Vector3(-2, 0.5, -1), Vector3(1, 1, 1), whiteMat)
        Box(root, Vector3(1.5, 0.5, -2), Vector3(1, 1, 1), whiteMat)
    end
end

-- ── 相机 ──

function SetupCamera()
    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 4, -6)
    cameraNode.rotation = Quaternion(pitch, yaw, 0)
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 250
end

function SetupViewport()
    renderer:SetViewport(0, Viewport:new(scene_, cameraNode:GetComponent("Camera")))
end

-- ── 事件 ──

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    CreateHUD()
end

-- ── 灯光开关 ──

local function ToggleLight(label)
    local lights = lightRefs[label]
    if not lights then return end
    local newState = not lights[1].enabled
    for _, l in ipairs(lights) do
        l.enabled = newState
    end
    return newState
end

-- ── HUD ──

function CreateHUD()
    local UI = require("urhox-libs/UI")
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    local buttons = {}

    local function MakeToggleRow(def)
        local lights = lightRefs[def.label] or {}
        local isOn = def.defaultOn
        local maxCd = def.maxCd or 5000
        local maxRange = def.maxRange or 60

        local statusLabel = UI.Label {
            text = isOn and "ON" or "OFF",
            fontSize = 13,
            color = isOn and "#4f4" or "#f44",
            width = 30,
        }
        local cdLabel = UI.Label { text = def.cd .. " cd", fontSize = 12, color = "#ccc", width = 70 }
        local rangeLabel = UI.Label { text = "r=" .. def.range .. "m", fontSize = 12, color = "#999", width = 55 }

        local btn = UI.Button {
            text = isOn and "Turn OFF" or "Turn ON",
            fontSize = 12,
            variant = isOn and "danger" or "primary",
            height = 26,
            width = 80,
            onClick = function(self)
                local nowOn = ToggleLight(def.label)
                statusLabel.text = nowOn and "ON" or "OFF"
                statusLabel.fontColor = nowOn and "#4f4" or "#f44"
                self.text = nowOn and "Turn OFF" or "Turn ON"
                self.variant = nowOn and "danger" or "primary"
            end
        }

        local cdSlider = UI.Slider {
            value = def.cd, min = 1, max = maxCd,
            width = 240, height = 20,
            onChange = function(_, v)
                local newCd = math.max(1, math.floor(v))
                cdLabel.text = newCd .. " cd"
                for _, l in ipairs(lights) do l.brightness = newCd end
            end
        }
        local rangeSlider = UI.Slider {
            value = def.range, min = 1, max = maxRange,
            width = 240, height = 20,
            onChange = function(_, v)
                local newRange = math.max(1, math.floor(v))
                rangeLabel.text = "r=" .. newRange .. "m"
                for _, l in ipairs(lights) do l.range = newRange end
            end
        }

        return UI.Panel {
            marginBottom = 6, padding = 4,
            backgroundColor = "rgba(255,255,255,0.03)", borderRadius = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, marginBottom = 2,
                    children = {
                        UI.Label { text = def.label, fontSize = 13, color = "#ffdc8a", width = 90 },
                        cdLabel,
                        rangeLabel,
                        statusLabel,
                        btn,
                    }
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label { text = "Brightness", fontSize = 11, color = "#888", width = 65 },
                        cdSlider,
                    }
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label { text = "Range", fontSize = 11, color = "#888", width = 65 },
                        rangeSlider,
                    }
                },
            }
        }
    end

    local rows = {}
    for _, def in ipairs(lightDefs) do
        rows[#rows + 1] = MakeToggleRow(def)
    end

    -- Auto-Exposure 开关
    local aeStatusLabel = UI.Label {
        text = "Auto-Exposure: ON",
        fontSize = 13, color = "#4f4",
    }
    local aeBtn = UI.Button {
        text = "Turn OFF", fontSize = 12, variant = "danger",
        height = 26, width = 90,
        onClick = function(self)
            local nowOn = not sceneZone.autoExposureEnabled
            sceneZone.autoExposureEnabled = nowOn
            aeStatusLabel.text = "Auto-Exposure: " .. (nowOn and "ON" or "OFF")
            aeStatusLabel.fontColor = nowOn and "#4f4" or "#f44"
            self.text = nowOn and "Turn OFF" or "Turn ON"
            self.variant = nowOn and "danger" or "primary"
        end
    }
    local autoExposureRow = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 10, marginBottom = 8,
        children = { aeStatusLabel, aeBtn }
    }

    -- 手动构建 children 避免 table.unpack 位置陷阱（Rule #4.5）
    local panelChildren = {
        UI.Label { text = "Real-World Lighting (True Candela)", fontSize = 18, color = "#fff", marginBottom = 4 },
        autoExposureRow,
        UI.Panel { height = 1, backgroundColor = "#333", marginBottom = 8 },
    }
    for _, row in ipairs(rows) do
        panelChildren[#panelChildren + 1] = row
    end
    panelChildren[#panelChildren + 1] = UI.Panel { height = 1, backgroundColor = "#333", marginTop = 6, marginBottom = 6 }
    panelChildren[#panelChildren + 1] = UI.Label { text = "WASD+QE move | Right-drag rotate", fontSize = 11, color = "#666" }

    local root = UI.Panel {
        width = "100%", height = "100%",
        children = {
            UI.Panel {
                position = "absolute", left = 10, top = 10,
                padding = 12, backgroundColor = "rgba(0,0,0,0.85)",
                borderRadius = 6, minWidth = 440,
                children = panelChildren,
            }
        }
    }
    UI.SetRoot(root)
end

-- ── 更新 ──

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local speed = 10.0

    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        yaw = yaw + input.mouseMove.x * 0.15
        pitch = pitch + input.mouseMove.y * 0.15
        pitch = math.max(-89, math.min(89, pitch))
        cameraNode.rotation = Quaternion(pitch, yaw, 0)
    end

    if input:GetKeyDown(KEY_W) then cameraNode:Translate(Vector3(0, 0, 1) * speed * dt) end
    if input:GetKeyDown(KEY_S) then cameraNode:Translate(Vector3(0, 0, -1) * speed * dt) end
    if input:GetKeyDown(KEY_A) then cameraNode:Translate(Vector3(-1, 0, 0) * speed * dt) end
    if input:GetKeyDown(KEY_D) then cameraNode:Translate(Vector3(1, 0, 0) * speed * dt) end
    if input:GetKeyDown(KEY_E) then cameraNode:Translate(Vector3(0, 1, 0) * speed * dt) end
    if input:GetKeyDown(KEY_Q) then cameraNode:Translate(Vector3(0, -1, 0) * speed * dt) end
end
