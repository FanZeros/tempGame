local ScreenColorPicker = require("urhox-libs.Paint.ScreenColorPicker")

---笔刷参数表。字段一律 camelCase。
---@class PaintBrushTable
---@field radiusPixels? number     屏幕像素半径，默认 24
---@field radiusWorld? number      可选：直接指定世界半径，覆盖由 radiusPixels 的换算
---@field strength? number         0..1 总强度，默认 1
---@field color? Color             画笔颜色
---@field colorOpacity? number     0..1，0 表示不刷颜色通道
---@field metallic? number         0..1 目标金属度
---@field metallicOpacity? number  0..1，0 表示不刷金属度通道
---@field roughness? number        0..1 目标粗糙度
---@field roughnessOpacity? number 0..1，0 表示不刷粗糙度通道
---@field blendMode? integer       PAINT_BLEND_REPLACE | PAINT_BLEND_ADD | PAINT_BLEND_ERASE

---ModelPainter.new 的构造参数。
---@class ModelPainterOptions
---@field camera? Camera            用于屏幕射线的相机；也可稍后通过 SetCamera 设置
---@field node? Node                绘制目标节点（也可传已有的 Paintable，见 SetTarget）
---@field maxDistance? number       射线最大距离，默认 250
---@field autoCreatePaintable? boolean 目标节点无 Paintable 时是否自动创建，默认 true
---@field paintResolution? integer  paint map 分辨率，缺省时用组件默认
---@field brush? PaintBrushTable    初始笔刷
---@field showBrushCursor? boolean  是否启用 3D 笔刷范围 HUD，默认 true
---@field brushCursorColor? Color   HUD 圆环颜色
---@field brushCursorSegments? integer 圆环分段数，默认 96
---@field brushCursorWidth? number  环宽占半径的比例，默认 0.05

---@class ModelPainter
local ModelPainter = {}
ModelPainter.__index = ModelPainter

-- 笔刷默认值。所有字段均为 camelCase，见 PaintBrushTable。
local DEFAULT_BRUSH = {
    radiusPixels = 24.0,
    radiusWorld = nil, -- 可选覆盖；nil 时按 radiusPixels 换算
    strength = 1.0,
    color = Color(1.0, 0.2, 0.1, 1.0),
    colorOpacity = 1.0,
    metallic = 0.0,
    roughness = 0.5,
    metallicOpacity = 0.0,
    roughnessOpacity = 0.0,
    blendMode = PAINT_BLEND_ADD, -- source-over：软笔刷默认，边缘会羽化进底下已有颜色
}

---从 options 表取值，缺省返回 default。
local function Option(options, key, default)
    if options == nil or options[key] == nil then
        return default
    end
    return options[key]
end

---复制笔刷表：以 DEFAULT_BRUSH 为底，用 source 覆盖。
local function CopyBrush(source)
    local brush = {}
    for key, value in pairs(DEFAULT_BRUSH) do
        brush[key] = value
    end

    if source then
        for key, value in pairs(source) do
            brush[key] = value
        end
    end

    return brush
end

local function Distance2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

---鸭子类型判断：传入的是否已经是一个 Paintable 组件。
local function IsPaintable(value)
    return value ~= nil and value.GetTargetDrawable ~= nil and value.PaintAtUV ~= nil
end

---构造一组与 normal 垂直的正交基（切线/副切线），用于在表面切平面内展开圆环。
local function OrthonormalBasis(normal)
    local n = normal:Normalized()
    local ref = (math.abs(n.y) > 0.9) and Vector3(1.0, 0.0, 0.0) or Vector3(0.0, 1.0, 0.0)
    local tangent = ref:CrossProduct(n):Normalized()
    local bitangent = n:CrossProduct(tangent):Normalized()
    return tangent, bitangent
end

---@param options ModelPainterOptions
---@return ModelPainter
function ModelPainter.new(options)
    options = options or {}

    local self = setmetatable({}, ModelPainter)
    self._camera = Option(options, "camera", nil)
    self._maxDistance = Option(options, "maxDistance", 250.0)
    self._autoCreatePaintable = Option(options, "autoCreatePaintable", true)
    self._paintResolution = Option(options, "paintResolution", nil)
    self._brush = CopyBrush(Option(options, "brush", nil))

    -- 笔刷范围 HUD：由本库用 CustomGeometry 画一个贴合表面法线的 3D 圆环，走渲染管线（享受 MSAA），
    -- 调用方只需每帧调 UpdateBrushCursor(x, y)，不接触任何几何/材质。
    self._cursorEnabled = Option(options, "showBrushCursor", true)
    self._cursorColor = Option(options, "brushCursorColor", Color(1.0, 0.9, 0.2, 0.9))
    self._cursorSegments = Option(options, "brushCursorSegments", 96)
    self._cursorWidthRatio = Option(options, "brushCursorWidth", 0.05) -- 环宽 / 半径
    self._cursorNode = nil
    self._cursorGeometry = nil

    self._lastScreen = nil
    self._strokeActive = false
    self._strokeId = 0
    self._sequence = 0
    self._stampCallback = nil
    self._strokeBeginCallback = nil
    self._strokeEndCallback = nil

    local target = Option(options, "node", nil)
    if target then
        self:SetTarget(target)
    end

    return self
end

function ModelPainter:SetCamera(camera)
    self._camera = camera
end

function ModelPainter:GetCamera()
    return self._camera
end

function ModelPainter:SetMaxDistance(maxDistance)
    self._maxDistance = maxDistance or self._maxDistance
end

function ModelPainter:GetMaxDistance()
    return self._maxDistance
end

---设置绘制目标：可传一个 Node（会取/建其上的 Paintable），或直接传一个 Paintable。
---@param target Node|Paintable|nil
---@return Paintable|nil
function ModelPainter:SetTarget(target)
    self._targetNode = nil
    self._paintable = nil

    if IsPaintable(target) then
        self._paintable = target
        if self._paintResolution then
            self._paintable.paintResolution = self._paintResolution
        end
        return self._paintable
    end

    self._targetNode = target
    if not target then
        return nil
    end

    local paintable = target:GetComponent("Paintable")
    if paintable == nil and self._autoCreatePaintable then
        paintable = target:CreateComponent("Paintable")
    end

    self._paintable = paintable
    if paintable and self._paintResolution then
        paintable.paintResolution = self._paintResolution
    end
    return self._paintable
end

function ModelPainter:GetTarget()
    return self._paintable
end

---@param brush PaintBrushTable
function ModelPainter:SetBrush(brush)
    self._brush = CopyBrush(brush)
end

---@return PaintBrushTable
function ModelPainter:GetBrush()
    return CopyBrush(self._brush)
end

function ModelPainter:SetStampCallback(callback)
    self._stampCallback = callback
end

function ModelPainter:SetStrokeBeginCallback(callback)
    self._strokeBeginCallback = callback
end

function ModelPainter:SetStrokeEndCallback(callback)
    self._strokeEndCallback = callback
end

---从屏幕像素坐标向目标模型投射，返回命中信息。
---@param x number 屏幕像素 X
---@param y number 屏幕像素 Y
---@return PaintRaycastHit|nil 命中返回 hit，未命中返回 nil
function ModelPainter:RaycastScreen(x, y)
    if not self._paintable or not self._camera or not graphics then
        return nil
    end

    local ray = self._camera:GetScreenRay(x / graphics.width, y / graphics.height)
    local hit = self._paintable:RaycastUV(ray, self._maxDistance)
    if hit and hit.hit then
        return hit
    end

    return nil
end

---把屏幕像素半径解析换算成世界半径（供 PaintAtRay 使用）。
---用相机投影 + 命中距离换算，稳定且与命中表面其他部分无关；不要用往四周打探测射线取
---最大距离的做法——射线一旦脱离当前表面命中远处别的部位，半径会被离群命中撑爆。
---@param x number
---@param y number
---@param hit PaintRaycastHit
---@return number|nil
function ModelPainter:EstimateRadiusWorld(x, y, hit)
    local brush = self._brush
    if brush.radiusWorld then
        return brush.radiusWorld
    end

    local radiusPixels = brush.radiusPixels or DEFAULT_BRUSH.radiusPixels
    local camera = self._camera
    if camera and graphics and graphics.height > 0 and hit and hit.distance then
        local worldPerPixel
        if camera:IsOrthographic() then
            worldPerPixel = camera.orthoSize / graphics.height
        else
            worldPerPixel = 2.0 * math.tan(math.rad(camera.fov) * 0.5) * hit.distance / graphics.height
        end

        local radiusWorld = radiusPixels * worldPerPixel
        if radiusWorld > 0.0 then
            return radiusWorld
        end
    end

    return nil
end

---由内部笔刷表构造原生 PaintBrush（供 PaintAtRay 使用，走世界半径投影）。
---@param radiusWorld number
---@return PaintBrush
function ModelPainter:CreateNativeBrush(radiusWorld)
    local source = self._brush
    local brush = PaintBrush()
    brush.radiusWorld = radiusWorld or 0.0
    brush.strength = source.strength
    brush.paintColor = source.color
    brush.colorOpacity = source.colorOpacity
    brush.metallic = source.metallic
    brush.roughness = source.roughness
    brush.metallicOpacity = source.metallicOpacity
    brush.roughnessOpacity = source.roughnessOpacity
    brush.blendMode = source.blendMode
    return brush
end

---在屏幕坐标处落一次笔刷。
---@param x number
---@param y number
---@return table|nil 命中并写入返回 stamp 命令记录，否则 nil
function ModelPainter:PaintAtScreen(x, y)
    local hit = self:RaycastScreen(x, y)
    if not hit then
        return nil
    end

    local radiusWorld = self:EstimateRadiusWorld(x, y, hit)
    local brush = self:CreateNativeBrush(radiusWorld)
    local ray = self._camera:GetScreenRay(x / graphics.width, y / graphics.height)
    if not self._paintable:PaintAtRay(ray, brush, self._maxDistance) then
        return nil
    end

    local command = {
        surfaceIndex = hit.paintSurfaceIndex,
        uv = hit.uv,
        screen = Vector2(x, y),
        brush = CopyBrush(self._brush),
        radiusWorld = radiusWorld,
        strokeId = self._strokeId,
        sequence = self._sequence,
        hit = hit,
    }

    self._sequence = self._sequence + 1
    if self._stampCallback then
        self._stampCallback(command)
    end

    return command
end

---@param x number
---@param y number
function ModelPainter:BeginStroke(x, y)
    self._strokeActive = true
    self._strokeId = self._strokeId + 1
    self._sequence = 0
    self._lastScreen = Vector2(x, y)

    if self._strokeBeginCallback then
        self._strokeBeginCallback({ strokeId = self._strokeId, screen = self._lastScreen, brush = CopyBrush(self._brush) })
    end

    return self:PaintAtScreen(x, y)
end

---沿上一采样点到当前点按笔刷间距补点，保证拖动连续。
---@param x number
---@param y number
function ModelPainter:UpdateStroke(x, y)
    if not self._strokeActive then
        return self:PaintAtScreen(x, y)
    end

    local current = Vector2(x, y)
    local last = self._lastScreen or current
    local radiusPixels = self._brush.radiusPixels or DEFAULT_BRUSH.radiusPixels
    local spacing = math.max(1.0, radiusPixels * 0.35)
    local distance = Distance2D(last, current)
    local steps = math.max(1, math.ceil(distance / spacing))
    local result = nil

    for i = 1, steps do
        local t = i / steps
        local sx = last.x + (current.x - last.x) * t
        local sy = last.y + (current.y - last.y) * t
        result = self:PaintAtScreen(sx, sy) or result
    end

    self._lastScreen = current
    return result
end

function ModelPainter:EndStroke()
    if not self._strokeActive then
        return
    end

    self._strokeActive = false
    local command = { strokeId = self._strokeId, sequence = self._sequence }
    if self._strokeEndCallback then
        self._strokeEndCallback(command)
    end
end

---清除 paint map。surfaceIndex 为 nil 时清全部。
---@param surfaceIndex integer|nil
---@return boolean
function ModelPainter:Clear(surfaceIndex)
    if not self._paintable then
        return false
    end
    if surfaceIndex == nil then
        return self._paintable:ClearPaint()
    end
    return self._paintable:ClearPaint(surfaceIndex)
end

---@param x number
---@param y number
---@param options table|nil
---@return Color|nil
function ModelPainter:PickScreenColor(x, y, options)
    return ScreenColorPicker.Pick(x, y, options)
end

---懒创建 HUD 圆环的 CustomGeometry 节点与 unlit 顶点色材质。
---@return CustomGeometry|nil
function ModelPainter:_EnsureBrushCursor()
    if self._cursorNode then
        return self._cursorGeometry
    end

    local cameraNode = self._camera and self._camera:GetNode()
    local scene = cameraNode and cameraNode:GetScene()
    if not scene then
        return nil
    end

    local node = scene:CreateChild("PaintBrushCursor")
    local geometry = node:CreateComponent("CustomGeometry")

    -- Unlit + 顶点色 + NOUV，且带 "alpha" pass：alpha pass 属于透明队列、在所有不透明模型之后渲染，
    -- 再把深度测试设为 always、关深度写 —— HUD 圆环始终画在所有模型之上，既不被遮挡也不嵌入表面。
    -- Clone 一份（不污染共享资源），并把混合从 addalpha 改成普通 alpha（否则是附加混合，会发光）。
    local technique = cache:GetResource("Technique", "Techniques/NoTextureVColAddAlpha.xml"):Clone("PaintBrushCursor")
    local pass = technique:GetPass("alpha")
    if pass then
        pass:SetBlendMode(BLEND_ALPHA)
        pass:SetDepthTestMode(CMP_ALWAYS)
        pass:SetDepthWrite(false)
    end

    local material = Material:new()
    material:SetTechnique(0, technique)
    material:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
    material.cullMode = CULL_NONE
    geometry:SetMaterial(material)

    self._cursorNode = node
    self._cursorGeometry = geometry
    return geometry
end

---隐藏 HUD 圆环。
function ModelPainter:HideBrushCursor()
    if self._cursorNode then
        self._cursorNode.enabled = false
    end
end

---更新并显示贴合表面的 3D 笔刷范围 HUD：从屏幕坐标投射，命中则在命中点、按表面法线
---铺一个半径=实际 radiusWorld 的圆环；未命中则隐藏。几何与材质全部由本库管理。
---@param x number
---@param y number
---@return boolean 是否可见
function ModelPainter:UpdateBrushCursor(x, y)
    if not self._cursorEnabled then
        self:HideBrushCursor()
        return false
    end

    local hit = self:RaycastScreen(x, y)
    if not hit then
        self:HideBrushCursor()
        return false
    end

    local radiusWorld = self:EstimateRadiusWorld(x, y, hit)
    if not radiusWorld or radiusWorld <= 0.0 then
        self:HideBrushCursor()
        return false
    end

    local geometry = self:_EnsureBrushCursor()
    if not geometry then
        return false
    end

    local tangent, bitangent = OrthonormalBasis(hit.normal)
    -- 深度测试已关（材质 CMP_ALWAYS），圆环始终盖在表面上，无需再抬离表面防 z-fight
    local center = hit.position
    local halfWidth = math.max(radiusWorld * self._cursorWidthRatio, 0.0005) * 0.5
    local outer = radiusWorld + halfWidth
    local inner = math.max(radiusWorld - halfWidth, 0.0)
    local color = self._cursorColor
    local segments = self._cursorSegments

    -- 用三角带铺一个环带（内外两圈顶点交替），真实几何体享受管线 AA。
    geometry:BeginGeometry(0, TRIANGLE_STRIP)
    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2.0
        local dir = tangent * math.cos(angle) + bitangent * math.sin(angle)
        geometry:DefineVertex(center + dir * outer)
        geometry:DefineColor(color)
        geometry:DefineVertex(center + dir * inner)
        geometry:DefineColor(color)
    end
    geometry:Commit()

    self._cursorNode.enabled = true
    return true
end

return ModelPainter
