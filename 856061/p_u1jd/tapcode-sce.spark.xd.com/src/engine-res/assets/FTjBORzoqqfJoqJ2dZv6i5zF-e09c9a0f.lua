-- ============================================================================
-- VideoScreen3D - 3D 世界中的视频屏幕组件
-- ============================================================================
-- 用途: 在 3D 场景中创建 IMAX 风格的视频屏幕
--
-- 解决的问题:
--   1. 屏幕不可见 - 自动计算合适的距离和高度
--   2. 视频画面偏黑 - 使用无光照材质，MatDiffColor 设为白色
--   3. 视频无法全屏 - 纹理尺寸与视频分辨率匹配
--   4. UV 映射混乱 - 使用 CustomGeometry 精确控制 UV
--   5. 画面上下颠倒 - 正确翻转 UV Y 坐标
--   6. 画面左右镜像 - 正确翻转 UV X 坐标
--
-- ⚠️ 重要: videoWidth/videoHeight 必须指定实际视频分辨率！
--    Load(url, 0, 0) 不支持自动检测，会导致纹理初始化失败！
--
-- 常见视频分辨率:
--   720p  = 1280 × 720
--   1080p = 1920 × 1080
--   4K    = 3840 × 2160
--
-- 用法:
--   local VideoScreen3D = require("urhox-libs/Video/VideoScreen3D")
--
--   -- 创建视频屏幕
--   local screen = VideoScreen3D.Create(scene, {
--       videoUrl = "https://example.com/video.mp4",
--       position = Vector3(0, 5, 20),  -- 可选，默认在玩家前方
--       width = 16,                     -- 屏幕宽度（米）
--       height = 9,                     -- 屏幕高度（米）
--       videoWidth = 1280,              -- ⚠️ 必须指定视频分辨率！
--       videoHeight = 720,              -- ⚠️ 必须指定视频分辨率！
--       autoPlay = true,
--       loop = true,
--   })
--
--   -- 控制播放
--   screen:Play()
--   screen:Pause()
--   screen:Stop()
--   screen:SetVolume(0.8)
--
--   -- 每帧更新（必须调用！）
--   screen:Update()
--
--   -- 销毁
--   screen:Destroy()
-- ============================================================================

local VideoScreen3D = {}
VideoScreen3D.__index = VideoScreen3D

-- ============================================================================
-- 默认配置
-- ============================================================================

local DEFAULT_CONFIG = {
    -- 屏幕尺寸（米）- 16:9 比例
    width = 16,
    height = 9,

    -- ⚠️ 视频分辨率（必须指定！不支持自动检测）
    -- 常见分辨率: 720p=1280×720, 1080p=1920×1080, 4K=3840×2160
    -- 默认 1280×720 (720p)，如果视频是其他分辨率请修改！
    videoWidth = 1280,
    videoHeight = 720,

    -- 默认位置（玩家前方 20 米，高度 5 米）
    position = nil,  -- 如果为 nil，使用 defaultDistance 和 defaultHeight
    defaultDistance = 20,
    defaultHeight = 5,

    -- 屏幕朝向（默认面向 -Z 方向，即面向原点）
    rotation = nil,  -- 如果为 nil，自动面向原点

    -- 播放设置
    autoPlay = false,
    loop = false,
    volume = 1.0,
    muted = false,

    -- 视频源
    videoUrl = nil,

    -- 是否添加边框
    showFrame = true,
    frameWidth = 0.3,  -- 边框宽度（米）
    frameColor = Color(0.1, 0.1, 0.1, 1.0),  -- 深灰色边框

    -- 自动调整屏幕大小以匹配视频宽高比
    autoResizeToVideo = false,

    -- 双面渲染（true = 正反面都显示视频，false = 只有正面）
    doubleSided = false,

    -- 调试模式
    debug = false,
}

-- ============================================================================
-- 创建视频屏幕
-- ============================================================================

---@param scene Scene 场景对象
---@param config table 配置表
---@return table VideoScreen3D 实例
function VideoScreen3D.Create(scene, config)
    config = config or {}

    -- 合并默认配置
    -- 注意：pairs() 不会遍历值为 nil 的键（如 videoUrl = nil）
    -- 所以必须分两步：先复制默认值，再覆盖用户配置
    local cfg = {}
    -- 第一步：复制所有有值的默认配置
    for k, v in pairs(DEFAULT_CONFIG) do
        cfg[k] = v
    end
    -- 第二步：覆盖用户配置（包括 videoUrl 等默认值为 nil 的字段）
    for k, v in pairs(config) do
        cfg[k] = v
    end

    local self = setmetatable({}, VideoScreen3D)

    self.scene_ = scene
    self.config_ = cfg
    self.player_ = nil
    self.material_ = nil
    self.screenNode_ = nil
    self.frameNode_ = nil
    self.customGeometry_ = nil
    self.isReady_ = false
    self.textureApplied_ = false  -- 纹理是否已应用（只设置一次）

    -- 创建节点结构
    self:CreateNodes()

    -- 创建视频播放器
    self:CreateVideoPlayer()

    -- 如果有视频 URL，加载视频
    if cfg.videoUrl then
        self:LoadVideo(cfg.videoUrl)
    end

    return self
end

-- ============================================================================
-- 内部方法：创建节点结构
-- ============================================================================

function VideoScreen3D:CreateNodes()
    local cfg = self.config_

    -- 创建根节点
    self.rootNode_ = self.scene_:CreateChild("VideoScreen3D")

    -- 计算位置
    local position = cfg.position
    if not position then
        -- 默认位置：前方 defaultDistance 米，高度 defaultHeight 米
        position = Vector3(0, cfg.defaultHeight, cfg.defaultDistance)
    end
    self.rootNode_.position = position

    -- 计算旋转（面向原点）
    if cfg.rotation then
        -- 用户指定了旋转，直接使用
        self.rootNode_.rotation = cfg.rotation
    else
        -- 默认面向原点（玩家位置）
        -- ⚠️ 使用 Node:LookAt() 而非 Quaternion(from, to)
        -- 因为 Quaternion(from, to) 在接近 180 度时旋转轴不确定，可能导致画面翻转
        local lookAtTarget = Vector3(0, position.y, 0)
        if (lookAtTarget - position):Length() > 0.001 then
            self.rootNode_:LookAt(lookAtTarget, Vector3.UP)
        end
    end

    -- 创建屏幕节点（使用 CustomGeometry）
    self:CreateScreenGeometry()

    -- 创建边框（可选）
    if cfg.showFrame then
        self:CreateFrame()
    end

    if cfg.debug then
        print("[VideoScreen3D] Created at " .. tostring(position))
        print("[VideoScreen3D] Screen size: " .. cfg.width .. "x" .. cfg.height .. " meters")
        print("[VideoScreen3D] Video resolution: " .. cfg.videoWidth .. "x" .. cfg.videoHeight)
    end
end

-- ============================================================================
-- 内部方法：创建屏幕几何体（CustomGeometry）
-- ============================================================================

function VideoScreen3D:CreateScreenGeometry()
    local cfg = self.config_

    self.screenNode_ = self.rootNode_:CreateChild("Screen")

    -- 创建 CustomGeometry
    local geometry = self.screenNode_:CreateComponent("CustomGeometry")
    geometry:SetNumGeometries(1)
    geometry:BeginGeometry(0, TRIANGLE_LIST)

    local halfW = cfg.width / 2
    local halfH = cfg.height / 2

    -- 定义 4 个顶点（形成一个面向 -Z 方向的平面）
    -- 顶点顺序：左下、右下、右上、左上
    --
    -- UV 坐标说明：
    -- - 视频纹理原点在左上角 (0,0)，右下角是 (1,1)
    -- - 屏幕旋转 180° 面向玩家后，需要翻转 X 和 Y
    -- - 最终 UV：左下 (1,1)，右下 (0,1)，右上 (0,0)，左上 (1,0)
    --
    -- 顶点位置（本地坐标，Y 向上，X 向右，Z 向前）：
    --   左下: (-halfW, -halfH, 0)
    --   右下: ( halfW, -halfH, 0)
    --   右上: ( halfW,  halfH, 0)
    --   左上: (-halfW,  halfH, 0)

    local normal = Vector3(0, 0, -1)  -- 法线朝向 -Z（面向观察者）

    -- 三角形 1: 左下 -> 右下 -> 右上
    geometry:DefineVertex(Vector3(-halfW, -halfH, 0))
    geometry:DefineNormal(normal)
    geometry:DefineTexCoord(Vector2(1, 1))  -- 左下 -> UV 右下

    geometry:DefineVertex(Vector3(halfW, -halfH, 0))
    geometry:DefineNormal(normal)
    geometry:DefineTexCoord(Vector2(0, 1))  -- 右下 -> UV 左下

    geometry:DefineVertex(Vector3(halfW, halfH, 0))
    geometry:DefineNormal(normal)
    geometry:DefineTexCoord(Vector2(0, 0))  -- 右上 -> UV 左上

    -- 三角形 2: 左下 -> 右上 -> 左上
    geometry:DefineVertex(Vector3(-halfW, -halfH, 0))
    geometry:DefineNormal(normal)
    geometry:DefineTexCoord(Vector2(1, 1))  -- 左下 -> UV 右下

    geometry:DefineVertex(Vector3(halfW, halfH, 0))
    geometry:DefineNormal(normal)
    geometry:DefineTexCoord(Vector2(0, 0))  -- 右上 -> UV 左上

    geometry:DefineVertex(Vector3(-halfW, halfH, 0))
    geometry:DefineNormal(normal)
    geometry:DefineTexCoord(Vector2(1, 0))  -- 左上 -> UV 右上

    geometry:Commit()

    -- 创建无光照材质
    self:CreateScreenMaterial()
    geometry:SetMaterial(self.material_)

    self.customGeometry_ = geometry
end

-- ============================================================================
-- 内部方法：创建屏幕材质（无光照 + 视频纹理）
-- ============================================================================

function VideoScreen3D:CreateScreenMaterial()
    self.material_ = Material:new()

    -- 使用无光照 + 纹理的 Technique
    -- DiffUnlit.xml: 支持 diffuse 纹理，无光照计算
    self.material_:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlit.xml"))

    -- 设置 MatDiffColor 为纯白色（1,1,1,1）
    -- 这确保视频颜色不会被乘以其他颜色导致变暗
    self.material_:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))

    -- 双面渲染设置
    -- CULL_NONE = 双面渲染（正反面都显示）
    -- CULL_CCW = 单面渲染（默认，只显示正面）
    if self.config_.doubleSided then
        self.material_:SetCullMode(CULL_NONE)
    end

    -- 初始显示黑色（视频加载前）
    -- 纹理会在 CreateVideoPlayer 中设置
end

-- ============================================================================
-- 内部方法：创建边框
-- ============================================================================

function VideoScreen3D:CreateFrame()
    local cfg = self.config_

    self.frameNode_ = self.rootNode_:CreateChild("Frame")

    -- 边框使用 4 个长方体
    local halfW = cfg.width / 2
    local halfH = cfg.height / 2
    local fw = cfg.frameWidth
    local depth = 0.1  -- 边框深度

    -- 创建边框材质（深色无光照）
    local frameMat = Material:new()
    frameMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    frameMat:SetShaderParameter("MatDiffColor", Variant(cfg.frameColor))

    -- 上边框
    local topNode = self.frameNode_:CreateChild("TopFrame")
    topNode.position = Vector3(0, halfH + fw/2, depth/2)
    topNode.scale = Vector3(cfg.width + fw*2, fw, depth)
    local topModel = topNode:CreateComponent("StaticModel")
    topModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    topModel:SetMaterial(frameMat)

    -- 下边框
    local bottomNode = self.frameNode_:CreateChild("BottomFrame")
    bottomNode.position = Vector3(0, -halfH - fw/2, depth/2)
    bottomNode.scale = Vector3(cfg.width + fw*2, fw, depth)
    local bottomModel = bottomNode:CreateComponent("StaticModel")
    bottomModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    bottomModel:SetMaterial(frameMat)

    -- 左边框
    local leftNode = self.frameNode_:CreateChild("LeftFrame")
    leftNode.position = Vector3(-halfW - fw/2, 0, depth/2)
    leftNode.scale = Vector3(fw, cfg.height, depth)
    local leftModel = leftNode:CreateComponent("StaticModel")
    leftModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    leftModel:SetMaterial(frameMat)

    -- 右边框
    local rightNode = self.frameNode_:CreateChild("RightFrame")
    rightNode.position = Vector3(halfW + fw/2, 0, depth/2)
    rightNode.scale = Vector3(fw, cfg.height, depth)
    local rightModel = rightNode:CreateComponent("StaticModel")
    rightModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    rightModel:SetMaterial(frameMat)
end

-- ============================================================================
-- 内部方法：创建视频播放器
-- ============================================================================

function VideoScreen3D:CreateVideoPlayer()
    -- 检查 VideoPlayer 类是否存在（仅 WASM 平台支持）
    if not VideoPlayer then
        print("[VideoScreen3D] Warning: VideoPlayer class not available (WASM only)")
        self.player_ = nil
        return
    end

    self.player_ = VideoPlayer:new()
    -- 注意：属性设置移到 LoadVideo 中，Load 成功后再设置
    -- 这与 VideoPlayer.lua 的行为保持一致
end

-- ============================================================================
-- 公共方法：加载视频
-- ============================================================================

---@param url string 视频 URL 或路径
---@return boolean 是否成功开始加载
function VideoScreen3D:LoadVideo(url)
    if not self.player_ then
        print("[VideoScreen3D] Error: Player not initialized")
        return false
    end

    local cfg = self.config_

    -- ⚠️ 重要：videoWidth/videoHeight 必须指定，不支持自动检测！
    -- Load(url, 0, 0) 会导致纹理初始化失败
    if cfg.videoWidth <= 0 or cfg.videoHeight <= 0 then
        print("[VideoScreen3D] ❌ ERROR: videoWidth and videoHeight MUST be specified!")
        print("[VideoScreen3D] Auto-detection is NOT supported. Video metadata is loaded async.")
        print("[VideoScreen3D] Common resolutions: 720p=1280x720, 1080p=1920x1080, 4K=3840x2160")
        print("[VideoScreen3D] Example: VideoScreen3D.Create(scene, { videoWidth=1280, videoHeight=720, ... })")
        return false
    end

    if cfg.debug then
        print("[VideoScreen3D] Loading video: " .. url)
        print("[VideoScreen3D] Video resolution: " .. cfg.videoWidth .. "x" .. cfg.videoHeight)
    end

    -- 加载视频（必须指定正确的分辨率）
    local success = self.player_:Load(url, cfg.videoWidth, cfg.videoHeight)

    if not success then
        print("[VideoScreen3D] ❌ ERROR: Failed to load video: " .. url)
        print("[VideoScreen3D] Check if videoWidth/videoHeight match the actual video resolution")
        return false
    end

    -- Load 成功后设置属性（与 VideoPlayer.lua 保持一致）
    -- 注意：必须在 Load 后设置，因为 Load 可能会重置状态
    self.player_:SetVolume(cfg.volume)
    self.player_:SetMuted(cfg.muted)
    self.player_:SetLoop(cfg.loop)

    if cfg.debug then
        print("[VideoScreen3D] Video loaded successfully")
    end

    -- 自动调整屏幕大小以匹配视频宽高比
    if cfg.autoResizeToVideo then
        local newWidth, newHeight = VideoScreen3D.CalculateScreenSize(
            cfg.width, cfg.videoWidth, cfg.videoHeight)
        if newHeight ~= cfg.height then
            self:SetSize(newWidth, newHeight)
            if cfg.debug then
                print("[VideoScreen3D] Auto-resized screen to " ..
                    newWidth .. "x" .. newHeight .. " meters")
            end
        end
    end

    -- ⚠️ 重要：视频加载是异步的！
    -- 不要在这里设置纹理，纹理会在 Update() 中检查 IsReady() 后设置
    -- 这样可以确保纹理内容已经准备好
    self.textureApplied_ = false  -- 重置标志，等待 Update() 中设置

    -- 自动播放
    if cfg.autoPlay then
        self.player_:Play()
    end

    if cfg.debug then
        print("[VideoScreen3D] Video loading started (texture will be applied when ready)")
    end

    return true
end

-- ============================================================================
-- 公共方法：播放控制
-- ============================================================================

function VideoScreen3D:Play()
    if self.player_ then
        self.player_:Play()
    end
end

function VideoScreen3D:Pause()
    if self.player_ then
        self.player_:Pause()
    end
end

function VideoScreen3D:Stop()
    if self.player_ then
        self.player_:Stop()
    end
end

function VideoScreen3D:Seek(time)
    if self.player_ then
        self.player_:Seek(time)
    end
end

function VideoScreen3D:SetVolume(volume)
    if self.player_ then
        self.player_:SetVolume(volume)
    end
end

function VideoScreen3D:SetMuted(muted)
    if self.player_ then
        self.player_:SetMuted(muted)
    end
end

function VideoScreen3D:SetLoop(loop)
    if self.player_ then
        self.player_:SetLoop(loop)
    end
end

-- ============================================================================
-- 公共方法：获取状态
-- ============================================================================

function VideoScreen3D:IsPlaying()
    return self.player_ and self.player_:IsPlaying()
end

function VideoScreen3D:IsReady()
    return self.player_ and self.player_:IsReady()
end

function VideoScreen3D:IsMuted()
    return self.player_ and self.player_:IsMuted() or false
end

function VideoScreen3D:GetCurrentTime()
    return self.player_ and self.player_:GetCurrentTime() or 0
end

function VideoScreen3D:GetDuration()
    return self.player_ and self.player_:GetDuration() or 0
end

function VideoScreen3D:GetVideoWidth()
    return self.player_ and self.player_:GetVideoWidth() or 0
end

function VideoScreen3D:GetVideoHeight()
    return self.player_ and self.player_:GetVideoHeight() or 0
end

-- ============================================================================
-- 公共方法：获取节点
-- ============================================================================

---@return Node 根节点
function VideoScreen3D:GetNode()
    return self.rootNode_
end

---@return Node 屏幕节点
function VideoScreen3D:GetScreenNode()
    return self.screenNode_
end

-- ============================================================================
-- 公共方法：每帧更新（必须调用！）
-- ============================================================================

function VideoScreen3D:Update()
    if self.player_ then
        -- 更新视频帧
        self.player_:Update()

        -- 检查视频是否准备好，准备好后应用纹理（只设置一次）
        -- ⚠️ 重要：视频加载是异步的，必须等 IsReady() 返回 true 后才能获取有效纹理
        if not self.textureApplied_ and self.player_:IsReady() then
            local texture = self.player_:GetTexture()
            if texture and self.material_ then
                self.material_:SetTexture(TU_DIFFUSE, texture)

                -- 确保 MatDiffColor 是白色（避免视频变暗）
                self.material_:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))

                self.textureApplied_ = true  -- 标记已设置，避免重复
                self.isReady_ = true

                if self.config_.debug then
                    print("[VideoScreen3D] Video ready! Texture applied.")
                    print("[VideoScreen3D] Video size: " ..
                        self.player_:GetVideoWidth() .. "x" .. self.player_:GetVideoHeight())
                end
            end
        end
    end
end

-- ============================================================================
-- 公共方法：设置位置和旋转
-- ============================================================================

function VideoScreen3D:SetPosition(position)
    if self.rootNode_ then
        self.rootNode_.position = position
    end
end

function VideoScreen3D:SetRotation(rotation)
    if self.rootNode_ then
        self.rootNode_.rotation = rotation
    end
end

---@param targetPos Vector3 屏幕面向的目标位置
function VideoScreen3D:LookAt(targetPos)
    if self.rootNode_ then
        -- ⚠️ 使用 Node:LookAt() 而非 Quaternion(from, to)
        -- 因为 Quaternion(from, to) 在接近 180 度时旋转轴不确定，可能导致画面翻转
        self.rootNode_:LookAt(targetPos, Vector3.UP)
    end
end

-- ============================================================================
-- 公共方法：调整屏幕大小
-- ============================================================================

---@param width number 宽度（米）
---@param height number 高度（米）
function VideoScreen3D:SetSize(width, height)
    self.config_.width = width
    self.config_.height = height

    -- 重新创建几何体
    if self.screenNode_ then
        self.screenNode_:Remove()
    end
    self:CreateScreenGeometry()

    -- 重新应用纹理（只有在视频已准备好的情况下）
    if self.textureApplied_ and self.player_ and self.player_:IsReady() then
        local texture = self.player_:GetTexture()
        if texture and self.material_ then
            self.material_:SetTexture(TU_DIFFUSE, texture)
            self.material_:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
        end
    end

    -- 重新创建边框
    if self.config_.showFrame then
        if self.frameNode_ then
            self.frameNode_:Remove()
        end
        self:CreateFrame()
    end
end

-- ============================================================================
-- 公共方法：销毁
-- ============================================================================

function VideoScreen3D:Destroy()
    if self.player_ then
        self.player_:Stop()
        self.player_ = nil
    end

    if self.rootNode_ then
        self.rootNode_:Remove()
        self.rootNode_ = nil
    end

    self.material_ = nil
    self.customGeometry_ = nil
    self.screenNode_ = nil
    self.frameNode_ = nil
end

-- ============================================================================
-- 工具方法：根据视频宽高比计算屏幕尺寸
-- ============================================================================

---@param targetWidth number 目标宽度（米）
---@param videoWidth number 视频宽度（像素）
---@param videoHeight number 视频高度（像素）
---@return number, number 屏幕宽度和高度（米）
function VideoScreen3D.CalculateScreenSize(targetWidth, videoWidth, videoHeight)
    local aspectRatio = videoWidth / videoHeight
    local height = targetWidth / aspectRatio
    return targetWidth, height
end

---@param targetHeight number 目标高度（米）
---@param videoWidth number 视频宽度（像素）
---@param videoHeight number 视频高度（像素）
---@return number, number 屏幕宽度和高度（米）
function VideoScreen3D.CalculateScreenSizeByHeight(targetHeight, videoWidth, videoHeight)
    local aspectRatio = videoWidth / videoHeight
    local width = targetHeight * aspectRatio
    return width, targetHeight
end

-- ============================================================================
-- 静态工具方法：创建视频材质
-- ============================================================================

--- 创建适合视频纹理的无光照材质
--- 自动设置：DiffUnlit Technique, MatDiffColor 白色, 双面渲染
---@param videoTexture Texture2D|nil 可选的视频纹理
---@return Material 配置好的视频材质
function VideoScreen3D.CreateVideoMaterial(videoTexture)
    local material = Material:new()

    -- 使用无光照 + 纹理的 Technique
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlit.xml"))

    -- 设置 MatDiffColor 为纯白色（确保视频颜色不变暗）
    material:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))

    -- 如果提供了纹理，设置它
    if videoTexture then
        material:SetTexture(TU_DIFFUSE, videoTexture)
    end

    return material
end

--- 创建无纹理的无光照纯色材质
---@param color Color 颜色
---@return Material 配置好的材质
function VideoScreen3D.CreateUnlitMaterial(color)
    local material = Material:new()

    -- 使用无光照无纹理的 Technique
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))

    -- 设置颜色
    material:SetShaderParameter("MatDiffColor", Variant(color))

    return material
end

return VideoScreen3D

