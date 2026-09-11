--- 程序化天空工具
-- 运行时生成渐变 cubemap，配合 Box.mdl + DiffSkybox.xml 实现全方位无缝渐变天空。
--
-- 用法:
--   local SkyUtils = require "urhox-libs.Rendering.SkyUtils"
--   local skyNode = SkyUtils.CreateGradientSky(scene_, {
--       zenith  = Color(0.06, 0.18, 0.52),
--       horizon = Color(0.28, 0.52, 0.82),
--   })

local SkyUtils = {}

local MAX_CUBEMAP_SIZE = 256

-- 6 面方向映射（DX/GL cubemap 标准）
-- face 0 必须最先 SetData：引擎由 face 0 的 SetData 触发 TextureCube GPU 内存分配
local FACE_DIRS = {
    [0] = {{ 0,0,-1}, { 0,-1, 0}, { 1, 0, 0}},  -- +X
    [1] = {{ 0,0, 1}, { 0,-1, 0}, {-1, 0, 0}},  -- -X
    [2] = {{ 1,0, 0}, { 0, 0, 1}, { 0, 1, 0}},  -- +Y
    [3] = {{ 1,0, 0}, { 0, 0,-1}, { 0,-1, 0}},  -- -Y
    [4] = {{ 1,0, 0}, { 0,-1, 0}, { 0, 0, 1}},  -- +Z
    [5] = {{-1,0, 0}, { 0,-1, 0}, { 0, 0,-1}},  -- -Z
}

--- 生成程序化渐变 cubemap（全方位无缝，三色 + 指数衰减）
-- @param opts table 配置：
--   zenith      Color  天顶色（正上方）【必填】
--   horizon     Color  地平线色（建议 == fogColor）【必填】
--   ground      Color  地面色（正下方）默认 horizon × 0.7
--   skyExp      number 天空渐变指数（<1 渐变集中在地平线，>1 更平）默认 0.5
--   groundExp   number 地面渐变指数，默认 1.5
--   size        number 每面分辨率，默认 64
-- @return TextureCube
function SkyUtils.MakeGradientCubemap(opts)
    assert(opts and opts.zenith,  _tr("t_f8oe6rpGeiEmWavY"))
    assert(opts.horizon,          _tr("t_uA8Us03mteduNllE"))
    local zenith = opts.zenith
    local horizon = opts.horizon
    local ground = opts.ground or Color(horizon.r * 0.7, horizon.g * 0.7, horizon.b * 0.7, 1.0)
    local skyExp = opts.skyExp or 0.5
    local groundExp = opts.groundExp or 1.5
    local size = math.min(opts.size or 64, MAX_CUBEMAP_SIZE)

    local tex = TextureCube:new()
    tex:SetSRGB(true)
    for face = 0, 5 do
        local axes = FACE_DIRS[face]
        local img = Image()
        img:SetSize(size, size, 4)
        local right, up, fwd = axes[1], axes[2], axes[3]
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local uu = (x + 0.5) / size * 2 - 1
                local vv = (y + 0.5) / size * 2 - 1
                local dx = fwd[1] + uu * right[1] + vv * up[1]
                local dy = fwd[2] + uu * right[2] + vv * up[2]
                local dz = fwd[3] + uu * right[3] + vv * up[3]
                local len = math.sqrt(dx*dx + dy*dy + dz*dz)
                local elev = dy / len
                local cr, cg, cb
                if elev >= 0 then
                    local t = elev ^ skyExp
                    cr = horizon.r + (zenith.r - horizon.r) * t
                    cg = horizon.g + (zenith.g - horizon.g) * t
                    cb = horizon.b + (zenith.b - horizon.b) * t
                else
                    local t = (-elev) ^ groundExp
                    cr = horizon.r + (ground.r - horizon.r) * t
                    cg = horizon.g + (ground.g - horizon.g) * t
                    cb = horizon.b + (ground.b - horizon.b) * t
                end
                img:SetPixel(x, y, Color(cr, cg, cb, 1.0))
            end
        end
        tex:SetData(face, img, false)
    end
    return tex
end

--- 一步创建渐变天空 Skybox 节点
-- @param scene  Scene   场景
-- @param opts   table   配置（同 MakeGradientCubemap，额外支持 hdrBoost）
--   hdrBoost    number  HDR 曝光乘数（补偿 ACES 色调映射），默认 2.0
-- @return Node  创建的 Skybox 节点
function SkyUtils.CreateGradientSky(scene, opts)
    assert(opts and opts.zenith, _tr("t_8KGUjDdT8RUEm3uv"))
    local hdrBoost = opts.hdrBoost or 2.0

    local skyTex = SkyUtils.MakeGradientCubemap(opts)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffSkybox.xml"))
    mat:SetTexture(TU_DIFFUSE, skyTex)
    mat:SetShaderParameter("MatDiffColor", Variant(Vector4(hdrBoost, hdrBoost, hdrBoost, 1.0)))

    local skyNode = scene:CreateChild("Sky")
    local skybox = skyNode:CreateComponent("Skybox")
    skybox:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    skybox:SetMaterial(mat)
    return skyNode
end

--- 预设配色
SkyUtils.Presets = {
    Day = {
        zenith  = Color(0.06, 0.18, 0.52),
        horizon = Color(0.28, 0.52, 0.82),
        skyExp  = 0.5,
    },
    Sunset = {
        zenith  = Color(0.15, 0.10, 0.35),
        horizon = Color(0.85, 0.45, 0.25),
        ground  = Color(0.20, 0.12, 0.08),
        skyExp  = 0.4,
    },
}

return SkyUtils
