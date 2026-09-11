-- 弹射 4096 的世界/方块比例。
--
-- 参考来源：Cat & Farm Pals 当前安装包中的 Farm AnimalDatabase 顺序、
-- GameplayEnvironmentView/Boundary 与各动物凸 MeshCollider 的世界 AABB。
-- 方块必须保持正方体，因此用动物 XZ 占地 AABB 的等面积正方形边长：
--     cubeEdge = sqrt(meshWidthX * meshLengthZ)

local Proportions = {}

local REFERENCE_BLOCK_VALUE = 2048
local REFERENCE_BLOCK_EDGE = 3.0
local SOURCE_BOUNDARY_WIDTH = 8.689066886901855
local SOURCE_BOUNDARY_LENGTH = 9.553754806518555
local LEGACY_PLAY_BOUNDARY_LENGTH = 15.2
local LEGACY_LAUNCH_ZONE_LENGTH = 8.8

-- Farm 模式的正式合成顺序。x/z 是缩放后的凸 MeshCollider AABB。
local ANIMAL_REFERENCE = {
    [2] = { name = "Chick", x = 0.8479, z = 1.0463 },
    [4] = { name = "Rooster", x = 0.9766, z = 1.5443 },
    [8] = { name = "Goose", x = 0.9783, z = 1.7100 },
    [16] = { name = "Cat", x = 0.9342, z = 2.3288 },
    [32] = { name = "Dog", x = 1.1598, z = 2.7189 },
    [64] = { name = "Goat", x = 1.2625, z = 2.7352 },
    [128] = { name = "Pig", x = 1.5619, z = 2.7515 },
    [256] = { name = "Donkey", x = 1.1867, z = 3.0637 },
    [512] = { name = "Horse", x = 1.3305, z = 3.5488 },
    [1024] = { name = "Cow", x = 1.6869, z = 3.6533 },
    [2048] = { name = "Buffalo", x = 1.9388, z = 4.1778 },
}

local MERGE_VALUES = { 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 }
local buffalo = ANIMAL_REFERENCE[REFERENCE_BLOCK_VALUE]
local buffaloEquivalentEdge = math.sqrt(buffalo.x * buffalo.z)
local sourceToWorldScale = REFERENCE_BLOCK_EDGE / buffaloEquivalentEdge
local blockScaleByValue = {}

for _, value in ipairs(MERGE_VALUES) do
    local reference = ANIMAL_REFERENCE[value]
    blockScaleByValue[value] = math.sqrt(reference.x * reference.z) / buffaloEquivalentEdge
end

-- Pig 的占地 AABB 略大于 Donkey。真实动物可以出现这种倒序，但高等级方块
-- 变小会破坏合成反馈；在保持两者几何平均值的前提下只加入 4% 的最小增长。
local pigDonkeyCenter = math.sqrt(blockScaleByValue[128] * blockScaleByValue[256])
local minimumMergeGrowth = math.sqrt(1.04)
blockScaleByValue[128] = pigDonkeyCenter / minimumMergeGrowth
blockScaleByValue[256] = pigDonkeyCenter * minimumMergeGrowth

-- 相机从 +Z 朝 -Z 看：
--
--   -trayL/2  [ Cat & Farm Pals boundary ]  dangerZ/红线  [ 发射区 ]  +trayL/2
--
-- 参考游戏的 Boundary 只对应红线前方的可玩区；发射区额外接在红线后方，
-- 不再被错误计入动物/地图比例。发射区沿用旧版 15.2:8.8 的纵深关系。
local playBoundaryWidth = SOURCE_BOUNDARY_WIDTH * sourceToWorldScale
local playBoundaryLength = SOURCE_BOUNDARY_LENGTH * sourceToWorldScale
local launchZoneLength = playBoundaryLength * LEGACY_LAUNCH_ZONE_LENGTH / LEGACY_PLAY_BOUNDARY_LENGTH
local trayWidth = playBoundaryWidth
local trayLength = playBoundaryLength + launchZoneLength
local previousTrayLength = playBoundaryLength
local motionScale = playBoundaryLength / LEGACY_PLAY_BOUNDARY_LENGTH
local dangerZ = -trayLength * 0.5 + playBoundaryLength
local launchMinZ = dangerZ + 0.25
local largestSpawnHalf = REFERENCE_BLOCK_EDGE * blockScaleByValue[16] * 0.5
local launchMaxZ = trayLength * 0.5 - largestSpawnHalf - 0.15
local defaultLaunchZ = launchMinZ + (launchMaxZ - launchMinZ) * ((5.75 - 3.55) / (10.85 - 3.55))

Proportions.REFERENCE_BLOCK_VALUE = REFERENCE_BLOCK_VALUE
Proportions.REFERENCE_BLOCK_EDGE = REFERENCE_BLOCK_EDGE
Proportions.ANIMAL_REFERENCE = ANIMAL_REFERENCE
Proportions.BLOCK_SCALE_BY_VALUE = blockScaleByValue
Proportions.SOURCE_TO_WORLD_SCALE = sourceToWorldScale
Proportions.PREVIOUS_TRAY_LENGTH = previousTrayLength

Proportions.WORLD = {
    trayW = trayWidth,
    trayL = trayLength,
    playBoundaryW = playBoundaryWidth,
    playBoundaryL = playBoundaryLength,
    launchZoneL = launchZoneLength,
    wallH = 1.35,
    wallT = 0.58,
    cube = REFERENCE_BLOCK_EDGE,
    dangerZ = dangerZ,
    launchMinZ = launchMinZ,
    launchMaxZ = launchMaxZ,
    defaultLaunchZ = defaultLaunchZ,
    gravity = 18.5,
    -- 每个 60 Hz 物理步损失 0.8% 水平速度。
    slideFriction = 0.992,
    floorBounce = 0.24,
    -- 与微信版刚体参数保持一致：空中只施加轻微线性阻尼，地面再使用
    -- slideFriction，避免合成方块飞行距离被地面摩擦过早吃掉。
    airLinearDamping = 0.015,
    normalBlockMass = 1.0,
    launchedMassMultiplier = 1.0,
    attractionRange = 6.0 * motionScale,
    attractionStrength = 4.2 * motionScale,
    motionScale = motionScale,
    aimGuideBase = 3.7 * motionScale,
    aimGuideExtra = 5.8 * motionScale,
    aimDragMarginX = 1.6 * motionScale,
    aimDragMarginZ = 2.2 * motionScale,
    -- 保持最高力度速度不变，同时降低轻推速度，扩大力度档位差异。
    launchBaseSpeed = 8.0 * motionScale,
    launchPowerSpeed = 48.5 * motionScale,
    collisionSeparation = 0.10,
    -- 发射方块第一次正向撞击时保留部分自身速度，并把主要动量传给
    -- 被撞方块，保持“弹射”手感而不依赖临时增大质量。
    launchedImpactRetain = 0.55,
    launchedImpactTransfer = 0.72,
    -- 方块与方块普通碰撞的恢复系数：0=完全非弹性，1=完全弹性。
    blockRestitution = 0.7,
    -- 周边墙壁接近台球库边：法向速度反向并保留 90%，切向速度不变。
    wallRestitution = 0.9,
}

---@param value number
---@return number
function Proportions.BlockScaleForValue(value)
    local safeValue = math.max(2, tonumber(value) or 2)
    local exact = blockScaleByValue[safeValue]
    if exact then return exact end

    if safeValue > REFERENCE_BLOCK_VALUE then
        -- 参考游戏到 2048 为止；4096+ 延续原项目每级 4.5% 的温和增长。
        return 1 + math.log(safeValue / REFERENCE_BLOCK_VALUE, 2) * 0.045
    end

    -- 非 2 的幂也能稳定工作：在相邻合成等级间按 log2 线性插值。
    local level = math.log(safeValue, 2)
    local lowerValue = 2 ^ math.floor(level)
    local upperValue = math.min(REFERENCE_BLOCK_VALUE, lowerValue * 2)
    local lowerScale = blockScaleByValue[lowerValue]
    if type(lowerScale) ~= "number" then lowerScale = 0.330948 end
    local upperScale = blockScaleByValue[upperValue]
    if type(upperScale) ~= "number" then upperScale = lowerScale end
    return lowerScale + (upperScale - lowerScale) * (level - math.floor(level))
end

---@param value number
---@return number
function Proportions.LegacyBlockScaleForValue(value)
    local safeValue = math.max(2, tonumber(value) or 2)
    local levelDifference = math.log(safeValue / REFERENCE_BLOCK_VALUE, 2)
    return math.max(0.55, 1 + levelDifference * 0.045)
end

return Proportions
