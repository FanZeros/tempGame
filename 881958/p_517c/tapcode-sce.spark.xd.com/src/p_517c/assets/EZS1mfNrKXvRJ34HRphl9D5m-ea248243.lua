-- 弹射 4096 - TapTap Maker / UrhoX Lua 实现
-- 玩法：在红线下方按住选择发射点，向下拖拽蓄力，松手发射；相同数字方块碰撞后合成。

local Theme = require "Bounce4096Theme"
local SpawnManager = require "SpawnManager"
local Proportions = require "Bounce4096Proportions"
local MetaGame = require "Bounce4096MetaGame"
local MetaUI = require "Bounce4096MetaUI"

local DDA_CONFIG = SpawnManager.CONFIG
-- DDA 的危险区前向余量也按地图纵深缩放，否则短地图几乎全会被误判为临界区。
DDA_CONFIG.board.nearFailureZMargin = 1.2 * Proportions.WORLD.motionScale
local spawnManager_ = SpawnManager.new(DDA_CONFIG)

local SAVE_FILE = "bounce4096_save.json"
local DAILY_SAVE_FILE = "bounce4096_daily_challenge_save.json"
local META_SAVE_FILE = "bounce4096_meta_save.json"
local META_CLOUD_KEY = "bounce4096_meta_v1"
local SAVE_VERSION = 4
local LEGACY_SAVE_VERSION = 1
local PREVIOUS_PROPORTION_SAVE_VERSION = 2
local PREVIOUS_PHYSICS_SAVE_VERSION = 3
local DDA_PROFILE_FILE = DDA_CONFIG.persistence.fileName
local DANGER_COUNTDOWN_SECONDS = 3.0
local AIM_CANCEL_RADIUS = math.max(0.3, 0.55 * Proportions.WORLD.motionScale)
-- 微信版当前调校：力度映射行程扩大到旧基准的 6 倍，轻拖更细腻，
-- 同时保留最低可感知发射速度。
local FULL_POWER_DRAG_DISTANCE = 1.45 * Proportions.WORLD.motionScale * 6
local MIN_LAUNCH_POWER = 0.005
local MAX_LAUNCH_POWER = 0.1875
local SHOOT_COOLDOWN_SECONDS = 0.45
local MERGE_COLLISION_PROTECTION_MIN = 0.06
local MERGE_COLLISION_PROTECTION_MAX = 1.4
local MERGE_TARGET_RED_LINE_EXCLUSION_RATIO = 0.5
local LEADERBOARD_KEY = "bounce4096_high_score"
local LEADERBOARD_WINDOW_COUNT = 10
local WORLD = Proportions.WORLD

local PALETTE = Theme.PALETTE
local RETRO = Theme.RETRO
local COMIC = Theme.COMIC
local FLOOR = Theme.FLOOR
local BACKGROUND_BLUE = Theme.BACKGROUND_BLUE
local DOODLE_COLORS = Theme.DOODLE_COLORS
local VALUE_COLORS = Theme.VALUE_COLORS

local POP = {
    ink = RETRO.ink,
    deep = RETRO.forest,
    purple = RETRO.plum,
    pink = RETRO.blood,
    cyan = RETRO.teal,
    yellow = RETRO.mustard,
    lime = RETRO.mint,
    coral = RETRO.burgundy,
    white = RETRO.cream,
}

local ROUNDED_BOX_ROUNDNESS = 0.15
local ROUNDED_BOX_CORE = 1 - ROUNDED_BOX_ROUNDNESS
local ROUNDED_BOX_GRID = { -1, -ROUNDED_BOX_CORE, ROUNDED_BOX_CORE, 1 }
local ROUNDED_BOX_FACES = {
    { normal = { x = 0, y = 0, z = 1 }, u = { x = 1, y = 0, z = 0 }, v = { x = 0, y = 1, z = 0 } },
    { normal = { x = 0, y = 0, z = -1 }, u = { x = -1, y = 0, z = 0 }, v = { x = 0, y = 1, z = 0 } },
    { normal = { x = 1, y = 0, z = 0 }, u = { x = 0, y = 0, z = -1 }, v = { x = 0, y = 1, z = 0 } },
    { normal = { x = -1, y = 0, z = 0 }, u = { x = 0, y = 0, z = 1 }, v = { x = 0, y = 1, z = 0 } },
    { normal = { x = 0, y = 1, z = 0 }, u = { x = 1, y = 0, z = 0 }, v = { x = 0, y = 0, z = -1 } },
    { normal = { x = 0, y = -1, z = 0 }, u = { x = 1, y = 0, z = 0 }, v = { x = 0, y = 0, z = 1 } },
}

---@class Vec3
---@field x number
---@field y number
---@field z number

---@class Block
---@field id integer
---@field value integer
---@field x number
---@field y number
---@field z number
---@field vx number
---@field vy number
---@field vz number
---@field mass number
---@field rx number
---@field ry number
---@field rz number
---@field spinX number
---@field spinY number
---@field spinZ number
---@field scale number
---@field targetScale number
---@field cooldown number
---@field age number
---@field dangerTime number|nil
---@field afterimages table[]
---@field afterimageTimer number
---@field launchTrail boolean
---@field frozen boolean

---@type NVGContextWrapper|nil
local vg_ = nil
local fontBody_ = -1
local fontNumber_ = -1
local FONT_BODY_PATH = "Fonts/MiSans-Bounce4096.ttf"
local FONT_NUMBER_PATH = "Fonts/TitanOne-Regular.ttf"
local logicalW_ = 375
local logicalH_ = 667
local dpr_ = 1

local camera_ = nil
local blocks_ = {}
local effects_ = {}
local impacts_ = {}
local score_ = 0
local maxValue_ = 2
local currentValue_ = 2
local gameOver_ = false
local gameMode_ = "normal"
---@type table|nil
local metaGame_ = nil
---@type table|nil
local metaUI_ = nil
local metaCloudLoaded_ = false
local metaCloudDirty_ = false
local metaCloudSaveRemaining_ = nil
local maxComboThisRun_ = 0
local dangerCountdown_ = nil
local canShoot_ = true
local shootCooldown_ = 0
local aiming_ = false
local aimStart_ = nil
local aimPoint_ = nil
local aimCanceling_ = false
local launchPos_ = nil
local heavyBlock_ = nil
local nextId_ = 1
local tip_ = "向后拖动方块发射"
local showLaunchHint_ = true
local shakeTime_ = 0
local shakePower_ = 0
local mergeSlowTime_ = 0
local RuntimeFlow = {
    inFlight = false,
    completed = false,
    watchdogRemaining = nil,
    requestGeneration = 0,
    message = nil,
    reviveUsed = false,
    reviveButton = nil,
    restartButton = nil,
    leaderboardButton = nil,
    leaderboardCloseButton = nil,
    leaderboardPrevButton = nil,
    leaderboardNextButton = nil,
    collisionLastIndex = 0,
    clearAnimations = {},
    pendingReviveClearRemaining = nil,
    fullLeaderboardNicknameRequestId = nil,
    fullLeaderboardNicknameGeneration = 0,
    comboCount = 0,
    comboWindowSeconds = 2.0,
    comboPopupAge = nil,
    comboPopupSerial = 0,
    metaRunSettled = false,
}

function RuntimeFlow.CanonicalUserId(value)
    if value == nil then return nil end
    local valueType = type(value)
    if valueType == "string" then
        local normalized = value:match("^%s*(.-)%s*$")
        if normalized == "" then return nil end
        local sign, digits = normalized:match("^([+-]?)(%d+)$")
        if digits then
            digits = digits:gsub("^0+", "")
            if digits == "" then digits = "0" end
            return (sign == "-" and "-" or "") .. digits
        end
        return normalized
    end
    if valueType == "number" then
        if math.type and math.type(value) == "integer" then
            return string.format("%d", value)
        end
        if value == math.floor(value) then
            return string.format("%.0f", value)
        end
    end
    return tostring(value)
end
function RuntimeFlow.NativeUserId(value)
    if type(value) == "number" then
        return math.tointeger and (math.tointeger(value) or value) or value
    end
    if type(value) == "string" then
        local numberValue = tonumber(value)
        if numberValue == nil then return nil end
        return math.tointeger and (math.tointeger(numberValue) or numberValue) or numberValue
    end
    return nil
end

function RuntimeFlow.CollectNicknameRecords(source)
    local records = {}
    if type(source) ~= "table" then return records end
    for key, value in pairs(source) do
        if type(value) == "table" then
            if value.userId or value.user_id or value.player or value.id then
                records[#records + 1] = value
            else
                local record = {}
                for field, fieldValue in pairs(value) do record[field] = fieldValue end
                record.userId = key
                records[#records + 1] = record
            end
        elseif value ~= nil then
            records[#records + 1] = { userId = key, nickname = value }
        end
    end
    return records
end

local audioStarted_ = false
local audioInitialized_ = false
local lastDangerSecond_ = nil
local leaderboard_ = {}
local leaderboardLoading_ = false
local leaderboardError_ = nil
RuntimeFlow.fullLeaderboardPageSize = 10
RuntimeFlow.fullLeaderboardOpen = false
RuntimeFlow.fullLeaderboard = {}
RuntimeFlow.fullLeaderboardPage = 0
RuntimeFlow.fullLeaderboardTotal = 0
RuntimeFlow.fullLeaderboardLoading = false
RuntimeFlow.fullLeaderboardError = nil
RuntimeFlow.fullLeaderboardRequestGeneration = 0
local leaderboardSubmitted_ = false
local personalBest_ = 0
local myNickname_ = ""
local nicknameLoading_ = false
---@type number|nil
local nicknameRetryRemaining_ = nil
---@type number|nil
local nicknameRequestRemaining_ = nil
local nicknameRequestGeneration_ = 0
local nicknameAttempts_ = 0
---@type integer|nil
local nicknameNativeRequestId_ = nil
local nicknameNativeGeneration_ = 0
local NICKNAME_FAST_RETRY_ATTEMPTS = 1
local NICKNAME_MAX_RETRY_ATTEMPTS = 2
local NICKNAME_REQUEST_TIMEOUT = 8.0

---@type Scene|nil
local audioScene_ = nil
---@type SoundSource|nil
local musicSource_ = nil
local sfxPools_ = {}
local sounds_ = {}
local blockLabelWidthCache_ = {}
local ddaElapsed_ = 0
local ddaDebugVisible_ = DDA_CONFIG.debug.enabledByDefault

local function V3(x, y, z)
    return { x = x, y = y, z = z }
end

local function BlockMassForValue(_value)
    return WORLD.normalBlockMass
end

local function Add(a, b)
    return V3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function Sub(a, b)
    return V3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function Scale(a, s)
    return V3(a.x * s, a.y * s, a.z * s)
end

local function Dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function Cross(a, b)
    return V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function Len3(a)
    return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

local function Norm(a)
    local l = Len3(a)
    if l <= 0.0001 then return V3(0, 0, 1) end
    return V3(a.x / l, a.y / l, a.z / l)
end

local function Clamp(v, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, v))
end

local function Length2(x, z)
    return math.sqrt(x * x + z * z)
end

function RuntimeFlow.DragStrength(distance)
    local effectiveDistance = math.max(0.001, FULL_POWER_DRAG_DISTANCE - AIM_CANCEL_RADIUS)
    return Clamp((distance - AIM_CANCEL_RADIUS) / effectiveDistance, 0, 1)
end

function RuntimeFlow.LaunchPower(distance)
    local strength = RuntimeFlow.DragStrength(distance)
    return MIN_LAUNCH_POWER + strength * (MAX_LAUNCH_POWER - MIN_LAUNCH_POWER)
end

local function BlockScaleForValue(value)
    return Proportions.BlockScaleForValue(value)
end

local function BlockSizeForValue(value)
    return WORLD.cube * BlockScaleForValue(value)
end

local function Color(c, alpha)
    return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255)
end

local function CreateNanoVGFont(name, path)
    local fontId = nvgCreateFont(vg_, name, path)
    if fontId ~= -1 then
        print("[Bounce4096] 字体加载成功 name=" .. name .. " path=" .. path)
        return fontId
    end
    print("[Bounce4096] 字体加载失败 name=" .. name .. " path=" .. path)
    return -1
end

local function LoadFonts()
    fontBody_ = CreateNanoVGFont("sans", FONT_BODY_PATH)
    fontNumber_ = CreateNanoVGFont("titan", FONT_NUMBER_PATH)
    if fontNumber_ == -1 then
        fontNumber_ = fontBody_
        print("[Bounce4096] Titan 字体不可用，数字使用正文字体")
    end
end

local function SelectBodyFont()
    if fontBody_ ~= -1 then
        nvgFontFaceId(vg_, fontBody_)
    end
end

local function SelectNumberFont()
    if fontNumber_ ~= -1 then
        nvgFontFaceId(vg_, fontNumber_)
    elseif fontBody_ ~= -1 then
        nvgFontFaceId(vg_, fontBody_)
    end
end

local function MeasureTextWidth(text, fallbackFontSize)
    local bounds = nvgTextBounds(vg_, 0, 0, text, nil)
    if type(bounds) == "number" then
        return math.max(1, bounds)
    end
    if type(bounds) == "table" then
        local left = bounds[1] or bounds.left or bounds.minX or bounds.x or 0
        local right = bounds[3] or bounds.right or bounds.maxX or bounds.x2 or bounds.width or 0
        if bounds.width then
            return math.max(1, bounds.width)
        end
        if right ~= left then
            return math.max(1, right - left)
        end
    end
    return math.max(1, #text * (fallbackFontSize or 16) * 0.55)
end

local function ValueColor(value)
    local base = VALUE_COLORS[value] or RETRO.charcoal
    local cosmetic = metaGame_ and metaGame_:Equipped("block") or nil
    if cosmetic and cosmetic.palette and #cosmetic.palette > 0 then
        local level = math.max(1, math.floor(math.log(math.max(2, value), 2) + 0.5))
        return cosmetic.palette[(level - 1) % #cosmetic.palette + 1]
    end
    return base
end

local function CurrentSaveFile()
    return gameMode_ == "daily" and DAILY_SAVE_FILE or SAVE_FILE
end

local function SaveMetaGame()
    if not metaGame_ then return end
    local file = File(META_SAVE_FILE, FILE_WRITE)
    if file and file:IsOpen() then
        file:WriteString(cjson.encode(metaGame_:Export()))
        file:Close()
        file:Dispose()
    end
    if clientCloud and metaCloudLoaded_ then
        metaCloudDirty_ = true
        metaCloudSaveRemaining_ = 1.0
    end
end

local function FlushMetaCloud(force)
    if not clientCloud or not metaCloudLoaded_ or not metaCloudDirty_ or not metaGame_ then return end
    if not force and (metaCloudSaveRemaining_ or 0) > 0 then return end
    metaCloudDirty_ = false
    metaCloudSaveRemaining_ = nil
    clientCloud:Set(META_CLOUD_KEY, metaGame_:Export(), {
            ok = function() print("[Bounce4096] 成长档案已同步到 TapTap 云端") end,
            error = function(code, reason)
                metaCloudDirty_ = true
                metaCloudSaveRemaining_ = 5.0
                print("[Bounce4096] 成长档案云同步失败: " .. tostring(code) .. " " .. tostring(reason))
            end,
    })
end

local function AttachMetaGame(data)
    metaGame_ = MetaGame.new(data, os.time())
    metaGame_.onChanged = SaveMetaGame
end

local function LoadMetaGame()
    local data = nil
    if fileSystem and fileSystem:FileExists(META_SAVE_FILE) then
        local file = File(META_SAVE_FILE, FILE_READ)
        if file and file:IsOpen() then
            local ok, decoded = pcall(cjson.decode, file:ReadString())
            file:Close(); file:Dispose()
            if ok and type(decoded) == "table" then data = decoded end
        end
    end
    AttachMetaGame(data)
    metaUI_ = MetaUI.new()
    if not clientCloud then metaCloudLoaded_ = true; return end
    clientCloud:Get(META_CLOUD_KEY, {
        ok = function(remote)
            local merged = MetaGame.MergeRemote(metaGame_:Export(), remote)
            AttachMetaGame(merged)
            metaCloudLoaded_ = true
            SaveMetaGame()
            print("[Bounce4096] TapTap 成长云存档加载完成")
        end,
        error = function(code, reason)
            metaCloudLoaded_ = true
            print("[Bounce4096] 成长云存档读取失败，继续使用本地档案: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

local function BuildSpawnState()
    local boardCounts = {}
    local occupiedArea = 0
    local nearFailure = dangerCountdown_ ~= nil or gameOver_
    for _, block in ipairs(blocks_) do
        boardCounts[block.value] = (boardCounts[block.value] or 0) + 1
        local blockSize = WORLD.cube * (block.scale or BlockScaleForValue(block.value))
        occupiedArea = occupiedArea + blockSize * blockSize
        local speed = Length2(block.vx, block.vz)
        if block.dangerTime
            or (block.age > DDA_CONFIG.board.nearFailureMinAge
                and speed < DDA_CONFIG.board.stationarySpeed
                and block.z > WORLD.dangerZ - DDA_CONFIG.board.nearFailureZMargin) then
            nearFailure = true
        end
    end
    local boardArea = WORLD.playBoundaryW * WORLD.playBoundaryL * DDA_CONFIG.board.occupancyAreaScale
    return {
        boardOccupancy = Clamp(occupiedArea / math.max(0.001, boardArea), 0, 1),
        highestValue = maxValue_,
        score = score_,
        boardCounts = boardCounts,
        nearFailure = nearFailure,
    }
end

local function RandomValue()
    local value = spawnManager_:ChooseNext(BuildSpawnState(), ddaElapsed_)
    return value
end

local function ClampLaunchPoint(point)
    local half = BlockSizeForValue(currentValue_) / 2
    return {
        x = Clamp(point.x, -WORLD.trayW / 2 + half + 0.2, WORLD.trayW / 2 - half - 0.2),
        y = half,
        z = Clamp(point.z, WORLD.launchMinZ, WORLD.launchMaxZ),
    }
end

local function SetupCamera()
    -- 相机距离跟随完整棋盘纵深，focal 再按屏幕边界做 contain 限制。
    -- 取样包含底座和墙顶，确保任何纵横比下整张地图都不会越出屏幕。
    -- 保持相机高度，用较小的纵向偏移获得更接近垂直俯视的视角。
    local pos = V3(0, WORLD.trayL * 0.94, WORLD.trayL * 0.40)
    local target = V3(0, 0.65, 0)
    local forward = Norm(Sub(target, pos))
    local right = Norm(Cross(forward, V3(0, 1, 0)))
    local up = Norm(Cross(right, forward))
    local cx = logicalW_ / 2
    local cy = logicalH_ * 0.48
    local desiredFocal = math.min(logicalH_ * 1.1, logicalW_ * 2.08)
    local fitFocal = math.huge
    local marginX = math.max(4, logicalW_ * 0.012)
    local marginY = math.max(4, logicalH_ * 0.008)
    local outerHalfW = WORLD.trayW * 0.5 + math.max(WORLD.wallT, 0.575) + 0.08
    local outerHalfL = WORLD.trayL * 0.5 + math.max(WORLD.wallT, 0.575) + 0.08
    local framePoints = {
        V3(-outerHalfW, -0.58, -outerHalfL), V3(outerHalfW, -0.58, -outerHalfL),
        V3(-outerHalfW, -0.58, outerHalfL), V3(outerHalfW, -0.58, outerHalfL),
        V3(-outerHalfW, WORLD.wallH + 0.08, -outerHalfL), V3(outerHalfW, WORLD.wallH + 0.08, -outerHalfL),
        V3(-outerHalfW, WORLD.wallH + 0.08, outerHalfL), V3(outerHalfW, WORLD.wallH + 0.08, outerHalfL),
    }
    for _, point in ipairs(framePoints) do
        local delta = Sub(point, pos)
        local depth = Dot(delta, forward)
        if depth > 0.15 then
            local nx = Dot(delta, right) / depth
            local ny = -Dot(delta, up) / depth
            if nx < -0.00001 then fitFocal = math.min(fitFocal, (cx - marginX) / -nx)
            elseif nx > 0.00001 then fitFocal = math.min(fitFocal, (logicalW_ - marginX - cx) / nx) end
            if ny < -0.00001 then fitFocal = math.min(fitFocal, (cy - marginY) / -ny)
            elseif ny > 0.00001 then fitFocal = math.min(fitFocal, (logicalH_ - marginY - cy) / ny) end
        end
    end
    camera_ = {
        pos = pos,
        forward = forward,
        right = right,
        up = up,
        focal = math.min(desiredFocal, fitFocal * 0.985),
        cx = cx,
        cy = cy,
    }
end

local function UpdateScreenMetrics()
    local g = GetGraphics()
    dpr_ = math.max(1, g:GetDPR())
    logicalW_ = g:GetWidth() / dpr_
    logicalH_ = g:GetHeight() / dpr_
    SetupCamera()
    if launchPos_ then
        launchPos_ = ClampLaunchPoint(launchPos_)
    end
end

local function Project(p)
    local c = camera_
    if not c then return nil end
    local d = Sub(p, c.pos)
    local z = Dot(d, c.forward)
    if z <= 0.15 then return nil end
    local s = c.focal / z
    return {
        x = c.cx + Dot(d, c.right) * s,
        y = c.cy - Dot(d, c.up) * s,
        z = z,
        scale = s,
    }
end

local function ScreenRay(x, y)
    local c = camera_
    local nx = (x - c.cx) / c.focal
    local ny = -(y - c.cy) / c.focal
    return Norm(Add(Add(Scale(c.right, nx), Scale(c.up, ny)), c.forward))
end

local function ScreenToWorldOnPlane(x, y, planeY)
    local c = camera_
    local ray = ScreenRay(x, y)
    if math.abs(ray.y) < 0.0001 then return nil end
    local t = (planeY - c.pos.y) / ray.y
    if t <= 0 then return nil end
    return Add(c.pos, Scale(ray, t))
end

local function RotatePoint(p, rx, ry, rz)
    local x, y, z = p.x, p.y, p.z
    local c, s = math.cos(rx), math.sin(rx)
    y, z = y * c - z * s, y * s + z * c
    c, s = math.cos(ry), math.sin(ry)
    x, z = x * c + z * s, -x * s + z * c
    c, s = math.cos(rz), math.sin(rz)
    x, y = x * c - y * s, x * s + y * c
    return V3(x, y, z)
end

local function Polygon(points, color, strokeColor, alpha)
    if #points < 3 then return end
    nvgGlobalAlpha(vg_, alpha or 1)
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, points[1].x, points[1].y)
    for i = 2, #points do
        nvgLineTo(vg_, points[i].x, points[i].y)
    end
    nvgClosePath(vg_)
    nvgFillColor(vg_, Color(color))
    nvgFill(vg_)
    if strokeColor then
        nvgStrokeColor(vg_, Color(strokeColor))
        nvgStrokeWidth(vg_, 1.2)
        nvgStroke(vg_)
    end
    nvgGlobalAlpha(vg_, 1)
end

local function DrawFloorPolygon(points, color, alpha)
    local projected = {}
    for i = 1, #points do
        local p = Project(points[i])
        if not p then return end
        projected[#projected + 1] = p
    end
    Polygon(projected, color, nil, alpha)
end

local function DrawFloorLine(a, b, color, width, alpha)
    local pa = Project(a)
    local pb = Project(b)
    if not pa or not pb then return end
    nvgGlobalAlpha(vg_, alpha or 1)
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, pa.x, pa.y)
    nvgLineTo(vg_, pb.x, pb.y)
    nvgStrokeColor(vg_, Color(color))
    nvgStrokeWidth(vg_, width)
    nvgStroke(vg_)
    nvgGlobalAlpha(vg_, 1)
end

local function MixColor(a, b, amount)
    return {
        math.floor(a[1] + (b[1] - a[1]) * amount),
        math.floor(a[2] + (b[2] - a[2]) * amount),
        math.floor(a[3] + (b[3] - a[3]) * amount),
        255,
    }
end

-- 微信版当前的卡通色阶光照。保持大色面干净，只在阈值附近做短距离
-- 平滑过渡，方块转动时不会出现整面颜色突跳。
local STYLIZED_LIGHT_DIRECTION = Norm(V3(-0.56, 0.76, -0.33))
local TOON_LIGHT_THRESHOLDS = { -0.36, 0.08, 0.52 }
local TOON_LIGHT_TRANSITION_WIDTH = 0.14

local function SmoothToonStep(edge, value, width)
    local safeWidth = math.max(0.0001, tonumber(width) or 0)
    local t = Clamp((value - edge + safeWidth) / (safeWidth * 2), 0, 1)
    return t * t * (3 - 2 * t)
end

local function StylizedLightingPalette()
    return {
        warm = MixColor(PALETTE.cream, PALETTE.yellow, 0.34),
        cool = MixColor(BACKGROUND_BLUE, PALETTE.blue, 0.48),
        bounce = MixColor(FLOOR.base, BACKGROUND_BLUE, 0.24),
        shadow = MixColor(FLOOR.base, MixColor(PALETTE.blue, BACKGROUND_BLUE, 0.3), 0.64),
    }
end

local function StylizedSurfaceColor(color, normal)
    if type(color) ~= "table" then return color end
    local n = normal or V3(0, 1, 0)
    local palette = StylizedLightingPalette()
    local direct = Clamp(Dot(n, STYLIZED_LIGHT_DIRECTION), -1, 1)
    local base = MixColor(color, palette.bounce, 0.025)
    local bandColors = {
        MixColor(MixColor(base, palette.cool, 0.29), palette.shadow, 0.08),
        MixColor(base, palette.cool, 0.11),
        MixColor(base, palette.warm, 0.12),
        MixColor(base, palette.warm, 0.27),
    }
    local shaded = bandColors[1]
    for i, threshold in ipairs(TOON_LIGHT_THRESHOLDS) do
        shaded = MixColor(
            shaded,
            bandColors[i + 1],
            SmoothToonStep(threshold, direct, TOON_LIGHT_TRANSITION_WIDTH)
        )
    end
    local groundBounce = SmoothToonStep(0.48, -n.y, 0.22)
    local skyWarmth = SmoothToonStep(0.48, n.y, 0.22)
    shaded = MixColor(shaded, palette.bounce, groundBounce * 0.16)
    return MixColor(shaded, palette.warm, skyWarmth * 0.05)
end

local function DrawCubeLabelLegacy(center, sizeX, sizeY, sizeZ, rotation, label, alpha)
    local rx = rotation and rotation.x or 0
    local ry = rotation and rotation.y or 0
    local rz = rotation and rotation.z or 0
    local faces = {
        { c = V3(0, 0, sizeZ / 2 + 0.035), normal = V3(0, 0, 1), w = sizeX, h = sizeY },
        { c = V3(sizeX / 2 + 0.035, 0, 0), normal = V3(1, 0, 0), w = sizeZ, h = sizeY },
        { c = V3(0, sizeY / 2 + 0.035, 0), normal = V3(0, 1, 0), w = sizeX, h = sizeZ },
    }
    local text = tostring(label)
    for _, f in ipairs(faces) do
        local faceCenter = Add(center, RotatePoint(f.c, rx, ry, rz))
        local normal = Norm(RotatePoint(f.normal, rx, ry, rz))
        local toCamera = Norm(Sub(camera_.pos, faceCenter))
        if Dot(normal, toCamera) > 0.08 then
            local p = Project(faceCenter)
            if p then
                local fontSize = Clamp(math.min(f.w, f.h) * p.scale * 0.52, 15, 66)
                nvgSave(vg_)
                nvgGlobalAlpha(vg_, alpha or 1)
                SelectNumberFont()
                nvgFontSize(vg_, fontSize)
                nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg_, Color(RETRO.ink, 230))
                nvgText(vg_, p.x + 2, p.y + 3, text, nil)
                nvgFillColor(vg_, Color(PALETTE.cream))
                nvgText(vg_, p.x, p.y, text, nil)
                nvgRestore(vg_)
            end
        end
    end
end

local function GetCubeFaceFrame(center, rx, ry, rz, localCenter, rightOffset, downOffset, localNormal)
    local faceCenter = Add(center, RotatePoint(localCenter, rx, ry, rz))
    local faceNormal = Norm(RotatePoint(localNormal, rx, ry, rz))
    local toCamera = Norm(Sub(camera_.pos, faceCenter))
    if Dot(faceNormal, toCamera) <= 0.02 then return nil end

    local rightPoint = Add(center, RotatePoint(Add(localCenter, rightOffset), rx, ry, rz))
    local downPoint = Add(center, RotatePoint(Add(localCenter, downOffset), rx, ry, rz))
    local projectedCenter = Project(faceCenter)
    local projectedRight = Project(rightPoint)
    local projectedDown = Project(downPoint)
    local rightLength = Len3(rightOffset)
    local downLength = Len3(downOffset)
    if not projectedCenter or not projectedRight or not projectedDown or rightLength <= 0 or downLength <= 0 then
        return nil
    end

    return {
        center = projectedCenter,
        axisX = {
            x = (projectedRight.x - projectedCenter.x) / rightLength,
            y = (projectedRight.y - projectedCenter.y) / rightLength,
        },
        axisY = {
            x = (projectedDown.x - projectedCenter.x) / downLength,
            y = (projectedDown.y - projectedCenter.y) / downLength,
        },
    }
end

local function DrawCubeSurfaceLabel(frame, faceWidth, faceHeight, label, alpha)
    if not frame then return end
    local text = tostring(label)
    local fontSize = 100
    -- NanoVG 会把当前变换计入字体栅格尺寸；必须在透视面变换前测量，
    -- 否则屏幕投影的轴缩放会让字形大到无法放入字体图集。
    SelectNumberFont()
    nvgFontSize(vg_, fontSize)
    local measuredWidth = blockLabelWidthCache_[text]
    if not measuredWidth then
        measuredWidth = MeasureTextWidth(text, fontSize)
        blockLabelWidthCache_[text] = measuredWidth
    end
    nvgSave(vg_)
    nvgTransform(vg_, frame.axisX.x, frame.axisX.y, frame.axisY.x, frame.axisY.y, frame.center.x, frame.center.y)
    nvgScissor(vg_, -faceWidth * 0.46, -faceHeight * 0.43, faceWidth * 0.92, faceHeight * 0.86)
    SelectNumberFont()
    nvgFontSize(vg_, fontSize)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local scaleY = faceHeight * 0.54 / fontSize
    local scaleX = math.min(scaleY * 1.04, faceWidth * 0.82 / measuredWidth)
    nvgScale(vg_, scaleX, scaleY)
    nvgGlobalAlpha(vg_, alpha * 0.34)
    nvgFillColor(vg_, Color(RETRO.ink))
    nvgText(vg_, 2.4, 4.2, text, nil)
    nvgGlobalAlpha(vg_, alpha)
    nvgFillColor(vg_, Color(PALETTE.cream))
    nvgText(vg_, 0, 1.5, text, nil)
    nvgRestore(vg_)
end

local function DrawCubeLabel(center, sizeX, sizeY, sizeZ, rotation, label, alpha)
    local rot = rotation or { x = 0, y = 0, z = 0 }
    local rx, ry, rz = rot.x or 0, rot.y or 0, rot.z or 0
    local epsilon = 0.025
    local faces = {
        { center = V3(0, 0, sizeZ / 2 + epsilon), right = V3(sizeX / 2, 0, 0), down = V3(0, -sizeY / 2, 0), normal = V3(0, 0, 1), width = sizeX, height = sizeY, alpha = alpha },
        { center = V3(0, 0, -sizeZ / 2 - epsilon), right = V3(-sizeX / 2, 0, 0), down = V3(0, -sizeY / 2, 0), normal = V3(0, 0, -1), width = sizeX, height = sizeY, alpha = alpha },
        { center = V3(sizeX / 2 + epsilon, 0, 0), right = V3(0, 0, -sizeZ / 2), down = V3(0, -sizeY / 2, 0), normal = V3(1, 0, 0), width = sizeZ, height = sizeY, alpha = alpha },
        { center = V3(-sizeX / 2 - epsilon, 0, 0), right = V3(0, 0, sizeZ / 2), down = V3(0, -sizeY / 2, 0), normal = V3(-1, 0, 0), width = sizeZ, height = sizeY, alpha = alpha },
        { center = V3(0, sizeY / 2 + epsilon, 0), right = V3(sizeX / 2, 0, 0), down = V3(0, 0, sizeZ / 2), normal = V3(0, 1, 0), width = sizeX, height = sizeZ, alpha = alpha * 0.94 },
        { center = V3(0, -sizeY / 2 - epsilon, 0), right = V3(sizeX / 2, 0, 0), down = V3(0, 0, -sizeZ / 2), normal = V3(0, -1, 0), width = sizeX, height = sizeZ, alpha = alpha * 0.94 },
    }
    local visibleFaces = {}
    for _, face in ipairs(faces) do
        local frame = GetCubeFaceFrame(center, rx, ry, rz, face.center, face.right, face.down, face.normal)
        if frame then visibleFaces[#visibleFaces + 1] = { frame = frame, face = face } end
    end
    table.sort(visibleFaces, function(a, b) return a.frame.center.z > b.frame.center.z end)
    for _, item in ipairs(visibleFaces) do
        DrawCubeSurfaceLabel(item.frame, item.face.width, item.face.height, label, item.face.alpha)
    end
end

local function RoundedBoxLocalPoint(face, u, v, hx, hy, hz)
    local q = {
        x = face.normal.x + face.u.x * u + face.v.x * v,
        y = face.normal.y + face.u.y * u + face.v.y * v,
        z = face.normal.z + face.u.z * u + face.v.z * v,
    }
    local inner = {
        x = Clamp(q.x, -ROUNDED_BOX_CORE, ROUNDED_BOX_CORE),
        y = Clamp(q.y, -ROUNDED_BOX_CORE, ROUNDED_BOX_CORE),
        z = Clamp(q.z, -ROUNDED_BOX_CORE, ROUNDED_BOX_CORE),
    }
    local offset = Sub(q, inner)
    local offsetLength = math.max(0.0001, Len3(offset))
    return V3(
        (inner.x + offset.x / offsetLength * ROUNDED_BOX_ROUNDNESS) * hx,
        (inner.y + offset.y / offsetLength * ROUNDED_BOX_ROUNDNESS) * hy,
        (inner.z + offset.z / offsetLength * ROUNDED_BOX_ROUNDNESS) * hz
    )
end

local roundedBoxFaceCache_ = nil

local function GetRoundedBoxFaceCache()
    if roundedBoxFaceCache_ then return roundedBoxFaceCache_ end
    roundedBoxFaceCache_ = {}
    for _, face in ipairs(ROUNDED_BOX_FACES) do
        local group = { face = face, patches = {} }
        for row = 1, #ROUNDED_BOX_GRID - 1 do
            for column = 1, #ROUNDED_BOX_GRID - 1 do
                local u0, u1 = ROUNDED_BOX_GRID[column], ROUNDED_BOX_GRID[column + 1]
                local v0, v1 = ROUNDED_BOX_GRID[row], ROUNDED_BOX_GRID[row + 1]
                group.patches[#group.patches + 1] = {
                    RoundedBoxLocalPoint(face, u0, v0, 1, 1, 1),
                    RoundedBoxLocalPoint(face, u1, v0, 1, 1, 1),
                    RoundedBoxLocalPoint(face, u1, v1, 1, 1, 1),
                    RoundedBoxLocalPoint(face, u0, v1, 1, 1, 1),
                }
            end
        end
        roundedBoxFaceCache_[#roundedBoxFaceCache_ + 1] = group
    end
    return roundedBoxFaceCache_
end

local function DrawRoundedCuboid(center, sizeX, sizeY, sizeZ, rotation, color, alpha, label)
    local hx, hy, hz = sizeX / 2, sizeY / 2, sizeZ / 2
    local rx = rotation and rotation.x or 0
    local ry = rotation and rotation.y or 0
    local rz = rotation and rotation.z or 0
    local patches = {}
    for _, group in ipairs(GetRoundedBoxFaceCache()) do
        local face = group.face
        local faceOffset = V3(face.normal.x * hx, face.normal.y * hy, face.normal.z * hz)
        local faceCenter = Add(center, RotatePoint(faceOffset, rx, ry, rz))
        local faceNormal = Norm(RotatePoint(face.normal, rx, ry, rz))
        if Dot(faceNormal, Norm(Sub(camera_.pos, faceCenter))) > -0.08 then
            for _, cachedPoints in ipairs(group.patches) do
                local worldPoints = {}
                for i = 1, 4 do
                    local unit = cachedPoints[i]
                    local localPoint = V3(unit.x * hx, unit.y * hy, unit.z * hz)
                    worldPoints[i] = Add(center, RotatePoint(localPoint, rx, ry, rz))
                end
                local projected, depth, visible = {}, 0, true
                for i = 1, 4 do
                    local p = Project(worldPoints[i])
                    if not p then visible = false break end
                    projected[i] = p
                    depth = depth + p.z
                end
                if visible then
                    patches[#patches + 1] = {
                        points = projected,
                        depth = depth / 4,
                        color = StylizedSurfaceColor(color, faceNormal),
                    }
                end
            end
        end
    end
    table.sort(patches, function(a, b) return a.depth > b.depth end)
    nvgLineJoin(vg_, NVG_ROUND)
    for _, patch in ipairs(patches) do
        Polygon(patch.points, patch.color, patch.color, alpha or 1)
    end
    if label then DrawCubeLabel(center, sizeX, sizeY, sizeZ, rotation, label, alpha or 1) end
end

local function DrawCuboid(center, sizeX, sizeY, sizeZ, rotation, color, alpha, label, withoutOutline, withoutStroke)
    if withoutOutline then
        DrawRoundedCuboid(center, sizeX, sizeY, sizeZ, rotation, color, alpha, label)
        return
    end
    local hx, hy, hz = sizeX / 2, sizeY / 2, sizeZ / 2
    local rx = rotation and rotation.x or 0
    local ry = rotation and rotation.y or 0
    local rz = rotation and rotation.z or 0
    local localPts = {
        V3(-hx, -hy, -hz), V3(hx, -hy, -hz), V3(hx, hy, -hz), V3(-hx, hy, -hz),
        V3(-hx, -hy, hz), V3(hx, -hy, hz), V3(hx, hy, hz), V3(-hx, hy, hz),
    }
    local world = {}
    for i = 1, #localPts do
        world[i] = Add(center, RotatePoint(localPts[i], rx, ry, rz))
    end

    local faceData = {
        { idx = { 1, 2, 3, 4 }, n = V3(0, 0, -1) },
        { idx = { 6, 5, 8, 7 }, n = V3(0, 0, 1) },
        { idx = { 5, 1, 4, 8 }, n = V3(-1, 0, 0) },
        { idx = { 2, 6, 7, 3 }, n = V3(1, 0, 0) },
        { idx = { 4, 3, 7, 8 }, n = V3(0, 1, 0) },
        { idx = { 5, 6, 2, 1 }, n = V3(0, -1, 0) },
    }
    local faces = {}
    for _, f in ipairs(faceData) do
        local centerFace = Scale(Add(Add(world[f.idx[1]], world[f.idx[2]]), Add(world[f.idx[3]], world[f.idx[4]])), 0.25)
        local normal = Norm(RotatePoint(f.n, rx, ry, rz))
        if Dot(normal, Norm(Sub(camera_.pos, centerFace))) > -0.03 then
            local points = {}
            local depth = 0
            local visible = true
            for _, idx in ipairs(f.idx) do
                local p = Project(world[idx])
                if not p then visible = false break end
                points[#points + 1] = p
                depth = depth + p.z
            end
            if visible then
                faces[#faces + 1] = {
                    points = points,
                    depth = depth / 4,
                    color = StylizedSurfaceColor(color, normal),
                }
            end
        end
    end
    table.sort(faces, function(a, b) return a.depth > b.depth end)
    for _, f in ipairs(faces) do
        Polygon(f.points, f.color, withoutStroke and nil or { 0, 79, 166, 46 }, alpha)
    end
    if label then
        DrawCubeLabel(center, sizeX, sizeY, sizeZ, rotation, label, alpha or 1)
    end
end

local function DrawRoundRect(x, y, w, h, r, color, alpha)
    nvgGlobalAlpha(vg_, alpha or 1)
    nvgBeginPath(vg_)
    nvgRoundedRect(vg_, x, y, w, h, r)
    nvgFillColor(vg_, Color(color))
    nvgFill(vg_)
    nvgGlobalAlpha(vg_, 1)
end

local function DrawBoard()
    local w, l = WORLD.trayW, WORLD.trayL
    local halfW, halfL = w / 2, l / 2
    DrawCuboid(V3(0, -0.28, 0), w + 1.15, 0.55, l + 1.15, nil, FLOOR.boundary, 1, nil, false, true)
    DrawFloorPolygon({ V3(-halfW, 0.03, -halfL), V3(halfW, 0.03, -halfL), V3(halfW, 0.03, halfL), V3(-halfW, 0.03, halfL) }, FLOOR.base, 1)

    local gutterW = 0.72
    local laneLeft = -halfW + gutterW
    local laneRight = halfW - gutterW
    local laneWidth = laneRight - laneLeft
    local plankColors = { FLOOR.plankLight, FLOOR.plankWarm, FLOOR.plankGold }
    for i = 0, 9 do
        local x0 = laneLeft + laneWidth * i / 10
        local x1 = laneLeft + laneWidth * (i + 1) / 10
        DrawFloorPolygon({ V3(x0, 0.052, -halfL), V3(x1, 0.052, -halfL), V3(x1, 0.052, halfL), V3(x0, 0.052, halfL) }, plankColors[i % 3 + 1], 1)
    end
    DrawFloorPolygon({ V3(-1.2, 0.061, -halfL), V3(0.42, 0.061, -halfL), V3(1.6, 0.061, halfL), V3(-0.1, 0.061, halfL) }, FLOOR.base, 0.2)
    DrawFloorPolygon({ V3(-halfW, 0.068, -halfL), V3(laneLeft, 0.068, -halfL), V3(laneLeft, 0.068, halfL), V3(-halfW, 0.068, halfL) }, FLOOR.gutter, 1)
    DrawFloorPolygon({ V3(laneRight, 0.068, -halfL), V3(halfW, 0.068, -halfL), V3(halfW, 0.068, halfL), V3(laneRight, 0.068, halfL) }, FLOOR.gutter, 1)
    DrawFloorPolygon({ V3(laneLeft, 0.078, -halfL), V3(laneLeft + 0.16, 0.078, -halfL), V3(laneLeft + 0.16, 0.078, halfL), V3(laneLeft, 0.078, halfL) }, FLOOR.seam, 1)
    DrawFloorPolygon({ V3(laneRight - 0.16, 0.078, -halfL), V3(laneRight, 0.078, -halfL), V3(laneRight, 0.078, halfL), V3(laneRight - 0.16, 0.078, halfL) }, FLOOR.seam, 1)

    for i = 1, 9 do
        local x = laneLeft + laneWidth * i / 10
        DrawFloorLine(V3(x, 0.084, -halfL + 0.15), V3(x, 0.084, halfL - 0.15), FLOOR.seam, 0.8, 0.38)
    end
    for j = 1, 4 do
        local z = -halfL + WORLD.trayL * j / 5
        DrawFloorLine(V3(laneLeft + 0.16, 0.083, z), V3(laneRight - 0.16, 0.083, z), FLOOR.marker, 0.7, 0.18)
    end

    local arrowXs = { -2.35, -1.18, 0, 1.18, 2.35 }
    for i, x in ipairs(arrowXs) do
        local depth = i == 3 and 0.82 or 0.66
        local arrowWidth = i == 3 and 0.25 or 0.2
        DrawFloorPolygon({
            V3(x, 0.093, 0.25 - depth),
            V3(x - arrowWidth, 0.093, 0.37),
            V3(x + arrowWidth, 0.093, 0.37),
        }, FLOOR.marker, 0.78)
    end

    DrawFloorPolygon({ V3(-w / 2 + 0.72, 0.085, WORLD.dangerZ), V3(w / 2 - 0.72, 0.085, WORLD.dangerZ), V3(w / 2 - 0.72, 0.085, halfL - 0.35), V3(-w / 2 + 0.72, 0.085, halfL - 0.35) }, FLOOR.plankGold, 0.22)

    -- 阴影在地面标记与墙体之间绘制，既保留球道纹理，也不会盖住前墙。
    RuntimeFlow.DrawBlockGroundShadows()

    local a = Project(V3(-w / 2, 0.11, WORLD.dangerZ))
    local b = Project(V3(w / 2, 0.11, WORLD.dangerZ))
    if a and b then
        nvgBeginPath(vg_)
        nvgMoveTo(vg_, a.x, a.y)
        nvgLineTo(vg_, b.x, b.y)
        local dangerFlash = dangerCountdown_ and (math.floor(os.clock() * 8) % 2 == 0 and 1.0 or 0.12) or 1
        nvgGlobalAlpha(vg_, dangerFlash)
        nvgStrokeColor(vg_, Color(RETRO.blood))
        nvgStrokeWidth(vg_, dangerCountdown_ and 9 or 7)
        nvgStroke(vg_)
        nvgStrokeColor(vg_, Color(RETRO.cream))
        nvgStrokeWidth(vg_, dangerCountdown_ and 3 or 2)
        nvgStroke(vg_)
        nvgGlobalAlpha(vg_, 1)
    end

    if launchPos_ then
        local center = V3(launchPos_.x, 0.12, launchPos_.z)
        local launchIndicatorSize = BlockSizeForValue(currentValue_)
        local points = {}
        for i = 0, 35 do
            local ang = i / 36 * math.pi * 2
            local p = Project(V3(center.x + math.cos(ang) * launchIndicatorSize * 0.82, center.y, center.z + math.sin(ang) * launchIndicatorSize * 0.82))
            if p then points[#points + 1] = p end
        end
        if #points > 2 then
            nvgBeginPath(vg_)
            for i = 1, #points do
                if i == 1 then nvgMoveTo(vg_, points[i].x, points[i].y) else nvgLineTo(vg_, points[i].x, points[i].y) end
            end
            nvgClosePath(vg_)
            nvgStrokeColor(vg_, Color(PALETTE.yellow))
            nvgStrokeWidth(vg_, 5)
            nvgStroke(vg_)
        end
    end

    DrawCuboid(V3(0, WORLD.wallH / 2, -l / 2 - WORLD.wallT / 2), w + WORLD.wallT * 2, WORLD.wallH, WORLD.wallT, nil, FLOOR.boundary, 1, nil, false, true)
    DrawCuboid(V3(-w / 2 - WORLD.wallT / 2, WORLD.wallH / 2, 0), WORLD.wallT, WORLD.wallH, l, nil, FLOOR.boundary, 1, nil, false, true)
    DrawCuboid(V3(w / 2 + WORLD.wallT / 2, WORLD.wallH / 2, 0), WORLD.wallT, WORLD.wallH, l, nil, FLOOR.boundary, 1, nil, false, true)
end

local function DrawFrontWall()
    DrawCuboid(V3(0, WORLD.wallH / 2, WORLD.trayL / 2 + WORLD.wallT / 2), WORLD.trayW + WORLD.wallT * 2, WORLD.wallH, WORLD.wallT, nil, FLOOR.boundary, 0.98, nil, false, true)
end

local function CreateBlock(value, x, y, z, vx, vy, vz, fromMerge)
    local initialTilt = fromMerge and 0.16 or 0
    local initialSpin = fromMerge and 2.0 or 0
    local targetScale = BlockScaleForValue(value)
    local block = {
        id = nextId_,
        value = value,
        x = x, y = y, z = z,
        vx = vx or 0, vy = vy or 0, vz = vz or 0,
        mass = BlockMassForValue(value),
        rx = (math.random() - 0.5) * initialTilt,
        ry = (math.random() - 0.5) * initialTilt,
        rz = (math.random() - 0.5) * initialTilt,
        spinX = (math.random() - 0.5) * initialSpin,
        spinY = (math.random() - 0.5) * initialSpin,
        spinZ = (math.random() - 0.5) * initialSpin,
        scale = targetScale * (fromMerge and 0.45 or 1),
        targetScale = targetScale,
        cooldown = fromMerge and 0.16 or 0,
        canAirSpin = fromMerge or false,
        squash = fromMerge and 0.08 or 0,
        age = 0,
        dangerTime = nil,
        afterimages = {},
        afterimageTimer = 0,
        launchTrail = false,
        collisionSfxCooldown = 0,
        mergeCollisionProtected = fromMerge or false,
        mergeCollisionProtectionAge = fromMerge and 0 or nil,
        frozen = false,
    }
    nextId_ = nextId_ + 1
    return block
end

local function ResetGame(keepSave)
    blocks_ = {}
    effects_ = {}
    impacts_ = {}
    score_ = 0
    maxValue_ = 2
    maxComboThisRun_ = 0
    spawnManager_:StartRun(ddaElapsed_)
    currentValue_ = RandomValue()
    nextId_ = 1
    gameOver_ = false
    dangerCountdown_ = nil
    canShoot_ = true
    shootCooldown_ = 0
    aiming_ = false
    aimStart_ = nil
    aimPoint_ = nil
    aimCanceling_ = false
    heavyBlock_ = nil
    launchPos_ = { x = 0, y = BlockSizeForValue(currentValue_) / 2, z = WORLD.defaultLaunchZ }
    tip_ = "向后拖动方块发射"
    showLaunchHint_ = true
    shakeTime_ = 0
    shakePower_ = 0
    mergeSlowTime_ = 0
    RuntimeFlow.restartButton = nil
    RuntimeFlow.reviveButton = nil
    RuntimeFlow.reviveUsed = false
    RuntimeFlow.inFlight = false
    RuntimeFlow.completed = false
    RuntimeFlow.watchdogRemaining = nil
    RuntimeFlow.requestGeneration = RuntimeFlow.requestGeneration + 1
    RuntimeFlow.message = nil
    RuntimeFlow.clearAnimations = {}
    RuntimeFlow.pendingReviveClearRemaining = nil
    RuntimeFlow.ResetComboState()
    RuntimeFlow.metaRunSettled = false
    lastDangerSecond_ = nil
    leaderboardSubmitted_ = false
    if metaGame_ then metaGame_:BeginRun(nil, os.time()) end
    if not keepSave and fileSystem then
        fileSystem:Delete(CurrentSaveFile())
    end
end

local function LoadSound(name, path, looped)
    if sounds_[name] then return sounds_[name] end
    local snd = cache:GetResource("Sound", path)
    if snd then
        snd:SetLooped(looped == true)
        sounds_[name] = snd
        print("[Bounce4096] 已加载音频: " .. path .. ", looped=" .. tostring(snd:IsLooped()))
    else
        print("[Bounce4096] 音频加载失败: " .. path)
    end
    return snd
end

local function InitAudio()
    if audioInitialized_ then return end
    audioInitialized_ = true
    audioScene_ = Scene()
    local musicNode = audioScene_:CreateChild("Music")
    musicSource_ = musicNode:CreateComponent("SoundSource")
    musicSource_.soundType = SOUND_MUSIC
    musicSource_.gain = 0.11
    sfxPools_ = {}
end

local function EnsureSoundLoaded(name)
    if sounds_[name] then return sounds_[name] end
    if name == "bgm" then
        return LoadSound(name, "Sounds/Bounce4096/bgm.wav", true)
    elseif name == "launch" then
        return LoadSound(name, "Sounds/Bounce4096/launch.wav", false)
    elseif name == "danger" then
        return LoadSound(name, "Sounds/Bounce4096/danger.wav", false)
    elseif name == "game_over" then
        return LoadSound(name, "Sounds/Bounce4096/game_over.wav", false)
    end
    local collisionIndex = name:match("^collision_(%d+)$")
    if collisionIndex then
        return LoadSound(name, "Sounds/Bounce4096/Collision/collision_" .. collisionIndex .. ".wav", false)
    end
    local mergeValue = name:match("^merge_(%d+)$")
    if mergeValue then
        return LoadSound(name, "Sounds/Bounce4096/merge_" .. mergeValue .. ".wav", false)
    end
    return nil
end

function RuntimeFlow.WarmCollisionAudio()
    if sfxPools_.collision then return end

    local pool = { sources = {}, cursor = 1 }
    for i = 1, 4 do
        local sfxNode = audioScene_:CreateChild("SFX_collision_" .. i)
        local source = sfxNode:CreateComponent("SoundSource")
        source.soundType = SOUND_EFFECT
        source:SetDeclickEnabled(false)
        pool.sources[i] = source
        EnsureSoundLoaded("collision_" .. i)
    end
    sfxPools_.collision = pool
    print("[Bounce4096] 碰撞音效与播放通道预热完成")
end

local function StartAudio()
    if audioStarted_ then return end
    InitAudio()
    audioStarted_ = true
    RuntimeFlow.WarmCollisionAudio()
    local bgm = EnsureSoundLoaded("bgm")
    if musicSource_ and bgm then
        bgm:SetLooped(true)
        musicSource_:Play(bgm)
        print("[Bounce4096] BGM 开始播放，looped=" .. tostring(bgm:IsLooped()))
    end
end

local function PlaySfx(name, gain)
    if not audioStarted_ then StartAudio() end
    local poolName = string.sub(name, 1, 6) == "merge_" and "merge"
        or (string.sub(name, 1, 10) == "collision_" and "collision" or name)
    local pool = sfxPools_[poolName]
    if not pool then
        local poolSizes = { launch = 1, merge = 2, danger = 1, game_over = 1, collision = 4 }
        local size = poolSizes[poolName]
        if size then
            pool = { sources = {}, cursor = 1 }
            for i = 1, size do
                local sfxNode = audioScene_:CreateChild("SFX_" .. poolName .. "_" .. i)
                local source = sfxNode:CreateComponent("SoundSource")
                source.soundType = SOUND_EFFECT
                source:SetDeclickEnabled(poolName ~= "collision")
                pool.sources[i] = source
            end
            sfxPools_[poolName] = pool
        end
    end
    if not pool or #pool.sources == 0 then
        print("[Bounce4096] 音效播放失败：没有可用通道 " .. tostring(poolName))
        return false
    end
    local snd = EnsureSoundLoaded(name)
    if not snd then
        print("[Bounce4096] 音效播放失败：未加载 " .. tostring(name))
        return false
    end
    local source = pool.sources[pool.cursor]
    pool.cursor = pool.cursor % #pool.sources + 1
    source:StopImmediate()
    source:SetGain(gain or 0.85)
    source:Play(snd)
    return true
end

local function PlayMergeSfx(value)
    local level = Clamp(math.floor(math.log(value, 2) + 0.5), 2, 13)
    local audioValue = math.floor(2 ^ level + 0.5)
    local name = "merge_" .. audioValue
    if PlaySfx(name, Clamp(0.62 + (level - 2) * 0.01, 0.62, 0.73)) then
        print("[Bounce4096] 播放合成音效: " .. name)
    end
end

function RuntimeFlow.PlayCollisionSfx(impactSpeed, a, b)
    if impactSpeed < 0.75 then return false end
    if a and (a.collisionSfxCooldown or 0) > 0 then return false end
    if b and (b.collisionSfxCooldown or 0) > 0 then return false end

    local index = math.random(1, 4)
    if index == RuntimeFlow.collisionLastIndex then
        index = index % 4 + 1
    end
    RuntimeFlow.collisionLastIndex = index
    local gain = math.min(
        Clamp(0.18 + (impactSpeed - 0.75) / 12 * 0.42, 0.18, 0.6) * 2,
        1.0
    )
    if not PlaySfx("collision_" .. index, gain) then return false end

    -- 每个方块独立节流，避免一次持续接触在多个物理子步中反复播放。
    local cooldown = 0.065
    if a then a.collisionSfxCooldown = cooldown end
    if b then b.collisionSfxCooldown = cooldown end
    return true
end

local function SaveGame()
    if gameOver_ then return end
    local data = {
        version = SAVE_VERSION,
        score = score_,
        maxValue = maxValue_,
        currentValue = currentValue_,
        nextId = nextId_,
        launchPos = launchPos_,
        blocks = {},
    }
    for i = 1, #blocks_ do
        local b = blocks_[i]
        data.blocks[#data.blocks + 1] = {
            id = b.id, value = b.value, x = b.x, y = b.y, z = b.z,
            vx = b.vx, vy = b.vy, vz = b.vz,
            rx = b.rx, ry = b.ry, rz = b.rz,
            spinX = b.spinX, spinY = b.spinY, spinZ = b.spinZ,
            scale = b.scale, cooldown = b.cooldown, age = b.age,
            canAirSpin = b.canAirSpin, squash = b.squash,
            dangerTime = b.dangerTime,
            frozen = b.frozen == true,
        }
    end
    local file = File(CurrentSaveFile(), FILE_WRITE)
    if file and file:IsOpen() then
        file:WriteString(cjson.encode(data))
        file:Close()
        file:Dispose()
    end
end

local function SaveDDAProfile()
    local file = File(DDA_PROFILE_FILE, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[SpawnManager] DDA 档案保存失败: " .. DDA_PROFILE_FILE)
        return
    end
    file:WriteString(cjson.encode(spawnManager_:ExportProfile()))
    file:Close()
    file:Dispose()
end

local function LoadDDAProfile()
    if not fileSystem:FileExists(DDA_PROFILE_FILE) then return false end
    local file = File(DDA_PROFILE_FILE, FILE_READ)
    if not file or not file:IsOpen() then return false end
    local text = file:ReadString()
    file:Close()
    file:Dispose()
    local ok, profile = pcall(cjson.decode, text)
    if not ok or type(profile) ~= "table" or profile.version ~= DDA_CONFIG.persistence.version then
        print("[SpawnManager] DDA 档案无效，使用默认统计")
        return false
    end
    spawnManager_:ImportProfile(profile)
    print("[SpawnManager] 已加载跨局 DDA 统计，完成局数=" .. tostring(profile.completedRuns or 0))
    return true
end

local function LoadGame()
    local saveFile = CurrentSaveFile()
    if not fileSystem:FileExists(saveFile) then return false end
    local file = File(saveFile, FILE_READ)
    if not file or not file:IsOpen() then return false end
    local text = file:ReadString()
    file:Close()
    file:Dispose()
    local ok, data = pcall(cjson.decode, text)
    local supportedVersion = type(data) == "table"
        and (data.version == SAVE_VERSION
            or data.version == PREVIOUS_PHYSICS_SAVE_VERSION
            or data.version == PREVIOUS_PROPORTION_SAVE_VERSION
            or data.version == LEGACY_SAVE_VERSION)
    if not ok or not supportedVersion or type(data.blocks) ~= "table" then
        fileSystem:Delete(saveFile)
        return false
    end
    local migrateLegacyLayout = data.version == LEGACY_SAVE_VERSION
    local migratePreviousBoundaryLayout = data.version == PREVIOUS_PROPORTION_SAVE_VERSION
    ResetGame(true)
    score_ = math.max(0, data.score or 0)
    maxValue_ = math.max(2, data.maxValue or 2)
    currentValue_ = data.currentValue or RandomValue()
    nextId_ = math.max(1, data.nextId or 1)
    launchPos_ = { x = 0, y = BlockSizeForValue(currentValue_) / 2, z = WORLD.defaultLaunchZ }
    local largestId = 0
    for _, raw in ipairs(data.blocks) do
        if type(raw) == "table" and raw.value and raw.x and raw.y and raw.z then
            local blockX, blockY, blockZ = raw.x, raw.y, raw.z
            local blockVX, blockVY, blockVZ = raw.vx or 0, raw.vy or 0, raw.vz or 0
            if migrateLegacyLayout then
                local sizeRatio = BlockScaleForValue(raw.value) / Proportions.LegacyBlockScaleForValue(raw.value)
                blockX = blockX * WORLD.trayW / 9.5
                blockY = blockY * sizeRatio
                blockZ = blockZ * WORLD.trayL / 24.0
                blockVX = blockVX * WORLD.trayW / 9.5
                blockVY = blockVY * sizeRatio
                blockVZ = blockVZ * WORLD.trayL / 24.0
            elseif migratePreviousBoundaryLayout then
                local zRatio = WORLD.trayL / Proportions.PREVIOUS_TRAY_LENGTH
                blockZ = blockZ * zRatio
                blockVZ = blockVZ * zRatio
            end
            local b = CreateBlock(raw.value, blockX, blockY, blockZ, blockVX, blockVY, blockVZ, false)
            b.id = math.max(1, math.floor(raw.id or b.id))
            b.rx, b.ry, b.rz = raw.rx or 0, raw.ry or 0, raw.rz or 0
            b.spinX, b.spinY, b.spinZ = raw.spinX or 0, raw.spinY or 0, raw.spinZ or 0
            -- 存档里的 scale 可能来自旧版统一尺寸；加载时按数值重建稳定尺寸。
            b.scale = b.targetScale
            b.cooldown = raw.cooldown or 0
            b.canAirSpin = raw.canAirSpin or false
            b.squash = raw.squash or 0
            b.age = raw.age or 0
            b.dangerTime = raw.dangerTime
            b.frozen = raw.frozen == true
            if b.frozen then b.mass = 1000000000 end
            blocks_[#blocks_ + 1] = b
            largestId = math.max(largestId, b.id)
        end
    end
    nextId_ = math.max(nextId_, largestId + 1)
    tip_ = "已恢复上一局，继续合成吧"
    showLaunchHint_ = #blocks_ == 0
    if migrateLegacyLayout or migratePreviousBoundaryLayout then
        SaveGame()
        print("[Bounce4096] 已将旧存档迁移到红线前 Boundary 布局")
    end
    print("[Bounce4096] 已恢复存档，方块数=" .. #blocks_)
    return true
end

local function AddScore(value)
    score_ = score_ + value
    maxValue_ = math.max(maxValue_, value)
end

local function InvalidateNicknameRequest()
    nicknameRequestGeneration_ = nicknameRequestGeneration_ + 1
    nicknameLoading_ = false
    nicknameRetryRemaining_ = nil
    nicknameRequestRemaining_ = nil
    nicknameNativeRequestId_ = nil
    nicknameNativeGeneration_ = 0
end

local function SetUnresolvedNicknameFallback(fallback)
    for _, entry in ipairs(leaderboard_) do
        if not entry.nickname or entry.nickname == "" then
            entry.nickname = fallback
        end
    end
end

local function ScheduleNicknameRetry()
    nicknameLoading_ = false
    nicknameRequestRemaining_ = nil
    nicknameNativeRequestId_ = nil
    if nicknameAttempts_ >= NICKNAME_MAX_RETRY_ATTEMPTS then
        nicknameRetryRemaining_ = nil
        SetUnresolvedNicknameFallback("昵称不可用")
        print("[Bounce4096] 排行榜昵称重试已达上限，使用回退名称")
        return
    end
    local retryDelay = nicknameAttempts_ < NICKNAME_FAST_RETRY_ATTEMPTS and 2.0 or 10.0
    nicknameRetryRemaining_ = retryDelay
    print("[Bounce4096] 将在" .. retryDelay .. "秒后重试排行榜昵称，次数=" .. nicknameAttempts_)
end

local function ApplyLeaderboardNicknames(requestGeneration, nicknames)
    if requestGeneration ~= nicknameRequestGeneration_ then return end
    nicknameLoading_ = false
    nicknameRequestRemaining_ = nil
    nicknameNativeRequestId_ = nil

    local names = {}
    local records = RuntimeFlow.CollectNicknameRecords(nicknames)
    for _, info in ipairs(records) do
        local userId = info.userId or info.user_id or info.player or info.id
        local nickname = info.nickname or info.nickName or info.nick_name
            or info.displayName or info.display_name or info.name
        local key = RuntimeFlow.CanonicalUserId(userId)
        if key and nickname and nickname ~= "" then
            names[key] = tostring(nickname)
        end
    end

    local resolved, unresolved = 0, 0
    for _, entry in ipairs(leaderboard_) do
        local key = RuntimeFlow.CanonicalUserId(entry.userId)
        local nickname = key and names[key] or nil
        if nickname then
            entry.nickname = nickname
            resolved = resolved + 1
            if entry.isMe then myNickname_ = nickname end
        elseif not entry.nickname then
            unresolved = unresolved + 1
        end
    end
    local ownKey = clientCloud and RuntimeFlow.CanonicalUserId(clientCloud.userId) or nil
    local ownNickname = ownKey and names[ownKey] or nil
    if ownNickname then myNickname_ = ownNickname end

    if unresolved > 0 then
        print("[Bounce4096] 昵称响应未覆盖全部玩家，记录=" .. tostring(#records)
            .. "，匹配=" .. tostring(resolved) .. "，未解析=" .. tostring(unresolved))
        ScheduleNicknameRetry()
    else
        nicknameRetryRemaining_ = nil
        print("[Bounce4096] 排行榜昵称加载完成，匹配=" .. tostring(resolved))
    end
end

local function FailLeaderboardNicknames(requestGeneration, errorCode)
    if requestGeneration ~= nicknameRequestGeneration_ then return end
    print("[Bounce4096] 排行榜昵称加载失败: " .. tostring(errorCode))
    ScheduleNicknameRetry()
end

function RuntimeFlow.ParseNicknamePayload(payload)
    if not payload or payload == "" then return {} end
    local ok, parsed = pcall(cjson.decode, payload)
    if not ok or type(parsed) ~= "table" then
        print("[Bounce4096] 昵称响应 JSON 解析失败")
        return {}
    end
    if type(parsed.nicknames) == "table" then
        return RuntimeFlow.CollectNicknameRecords(parsed.nicknames)
    end
    if type(parsed.data) == "table" and type(parsed.data.nicknames) == "table" then
        return RuntimeFlow.CollectNicknameRecords(parsed.data.nicknames)
    end
    return RuntimeFlow.CollectNicknameRecords(parsed)
end

function RuntimeFlow.ApplyFullLeaderboardNicknames(requestGeneration, nicknames)
    if requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
    RuntimeFlow.fullLeaderboardNicknameRequestId = nil

    local names = {}
    local records = RuntimeFlow.CollectNicknameRecords(nicknames)
    for _, info in ipairs(records) do
        local userId = info.userId or info.user_id or info.player or info.id
        local nickname = info.nickname or info.nickName or info.nick_name
            or info.displayName or info.display_name or info.name
        local key = RuntimeFlow.CanonicalUserId(userId)
        if key and nickname and nickname ~= "" then names[key] = tostring(nickname) end
    end

    local resolved = 0
    for _, entry in ipairs(RuntimeFlow.fullLeaderboard) do
        local key = RuntimeFlow.CanonicalUserId(entry.userId)
        if key and names[key] then
            entry.nickname = names[key]
            resolved = resolved + 1
        end
    end
    print("[Bounce4096] 完整排行榜昵称加载完成，记录=" .. #records
        .. "，匹配=" .. resolved)
end

---@param eventType string
---@param eventData VariantMap
function HandleUserNicknameResponse(eventType, eventData)
    local requestId = eventData:GetInt("RequestId")
    if RuntimeFlow.fullLeaderboardNicknameRequestId
        and requestId == RuntimeFlow.fullLeaderboardNicknameRequestId then
        local requestGeneration = RuntimeFlow.fullLeaderboardNicknameGeneration
        RuntimeFlow.fullLeaderboardNicknameRequestId = nil
        if not eventData:GetBool("Success") then
            print("[Bounce4096] 完整排行榜昵称加载失败: "
                .. eventData:GetInt("ErrorCode"))
            return
        end
        RuntimeFlow.ApplyFullLeaderboardNicknames(
            requestGeneration,
            RuntimeFlow.ParseNicknamePayload(eventData:GetString("Nicknames"))
        )
        return
    end

    if not nicknameNativeRequestId_ or requestId ~= nicknameNativeRequestId_ then return end

    local requestGeneration = nicknameNativeGeneration_
    if not eventData:GetBool("Success") then
        FailLeaderboardNicknames(requestGeneration, eventData:GetInt("ErrorCode"))
        return
    end

    local payload = eventData:GetString("Nicknames")
    ApplyLeaderboardNicknames(
        requestGeneration,
        RuntimeFlow.ParseNicknamePayload(payload)
    )
end

local function ResolveLeaderboardNicknames()
    if nicknameLoading_ or #leaderboard_ == 0 then return end

    local userIds, seen = {}, {}
    for _, entry in ipairs(leaderboard_) do
        local key = RuntimeFlow.CanonicalUserId(entry.userId)
        if key and not seen[key] and not entry.nickname then
            seen[key] = true
            userIds[#userIds + 1] = entry.userId
        end
    end
    if clientCloud and clientCloud.userId then
        local myKey = RuntimeFlow.CanonicalUserId(clientCloud.userId)
        if myKey and not seen[myKey] then
            seen[myKey] = true
            userIds[#userIds + 1] = clientCloud.userId
        end
    end
    if #userIds == 0 then
        nicknameRetryRemaining_ = nil
        return
    end

    nicknameLoading_ = true
    nicknameRetryRemaining_ = nil
    nicknameAttempts_ = nicknameAttempts_ + 1
    nicknameRequestGeneration_ = nicknameRequestGeneration_ + 1
    local requestGeneration = nicknameRequestGeneration_
    nicknameRequestRemaining_ = NICKNAME_REQUEST_TIMEOUT
    print("[Bounce4096] 请求排行榜 TapTap 昵称，玩家数=" .. tostring(#userIds)
        .. "，批次=" .. tostring(requestGeneration))

    -- 真机优先直接走 lobby，并由本脚本处理 UserNicknameResponse。
    -- 这避免统一封装的 pendingRequests 在二维码运行环境中丢失回调。
    local lobbyApi = rawget(_G, "lobby")
    if lobbyApi and lobbyApi.GetUserNickname then
        local numericUserIds = {}
        for _, userId in ipairs(userIds) do
            local nativeId = RuntimeFlow.NativeUserId(userId)
            if nativeId ~= nil then
                numericUserIds[#numericUserIds + 1] = nativeId
            else
                print("[Bounce4096] 无法转换昵称查询用户ID: " .. tostring(userId))
            end
        end
        if #numericUserIds == 0 then
            ScheduleNicknameRetry()
            return
        end
        local requestId = lobbyApi:GetUserNickname(numericUserIds)
        if requestId and requestId >= 0 then
            nicknameNativeRequestId_ = requestId
            nicknameNativeGeneration_ = requestGeneration
            return
        end
        print("[Bounce4096] lobby:GetUserNickname 未返回有效请求ID")
    end

    if not GetUserNickname then
        ScheduleNicknameRetry()
        return
    end
    GetUserNickname({
        userIds = userIds,
        onSuccess = function(nicknames)
            ApplyLeaderboardNicknames(requestGeneration, nicknames)
        end,
        onError = function(errorCode)
            FailLeaderboardNicknames(requestGeneration, errorCode)
        end,
    })
end

local function RefreshLeaderboard()
    if not clientCloud or leaderboardLoading_ then return end
    leaderboardLoading_ = true
    leaderboardError_ = nil

    local function FailLeaderboardLoad(code, reason)
        leaderboardLoading_ = false
        leaderboardError_ = "排行榜暂时不可用"
        print("[Bounce4096] 排行榜加载失败: " .. tostring(code) .. " " .. tostring(reason))
    end

    local function TimeoutLeaderboardLoad()
        leaderboardLoading_ = false
        leaderboardError_ = "排行榜加载超时"
    end

    local function LoadRankWindow(myRank)
        local rank = math.max(1, math.floor(tonumber(myRank) or 1))
        local startRank = math.max(1, rank - math.floor(LEADERBOARD_WINDOW_COUNT / 2))
        local startOffset = startRank - 1
        print("[Bounce4096] 加载本人附近排名，本人=" .. rank
            .. "，起始=" .. startRank .. "，最多=" .. LEADERBOARD_WINDOW_COUNT .. "人")

        clientCloud:GetRankList(LEADERBOARD_KEY, startOffset, LEADERBOARD_WINDOW_COUNT, {
            ok = function(rankList)
                local knownNicknames = {}
                for _, entry in ipairs(leaderboard_) do
                    if entry.userId and entry.nickname and entry.nickname ~= ""
                        and entry.nickname ~= "未知玩家" and entry.nickname ~= "昵称不可用" then
                        local key = RuntimeFlow.CanonicalUserId(entry.userId)
                        if key then knownNicknames[key] = entry.nickname end
                    end
                end
                InvalidateNicknameRequest()

                local entries = {}
                for i, item in ipairs(rankList or {}) do
                    local userId = item.userId or item.player
                    local globalRank = math.max(1, math.floor(tonumber(item.rank) or (startRank + i - 1)))
                    if userId then
                        local scoreValues = item.iscore or {}
                        entries[#entries + 1] = {
                            rank = globalRank,
                            userId = userId,
                            nickname = knownNicknames[RuntimeFlow.CanonicalUserId(userId)],
                            score = math.floor(tonumber(scoreValues[LEADERBOARD_KEY] or item.scoreValue or item.value) or 0),
                            isMe = RuntimeFlow.CanonicalUserId(userId)
                                == RuntimeFlow.CanonicalUserId(clientCloud.userId),
                        }
                    else
                        print("[Bounce4096] 忽略缺少用户ID的排行榜条目，rank=" .. tostring(globalRank))
                    end
                end
                leaderboard_ = entries
                leaderboardLoading_ = false
                nicknameAttempts_ = 0
                ResolveLeaderboardNicknames()
            end,
            error = FailLeaderboardLoad,
            timeout = TimeoutLeaderboardLoad,
        })
    end

    clientCloud:GetUserRank(clientCloud.userId, LEADERBOARD_KEY, {
        ok = function(rank)
            if rank == nil then
                print("[Bounce4096] 当前玩家尚未进入排行榜，改为加载榜首成绩")
                LoadRankWindow(1)
                return
            end
            LoadRankWindow(rank)
        end,
        error = FailLeaderboardLoad,
        timeout = TimeoutLeaderboardLoad,
    })
end

function RuntimeFlow.ResolveFullLeaderboardNicknames(entries, requestGeneration)
    if #entries == 0 then return end
    local userIds, seen = {}, {}
    for _, entry in ipairs(entries) do
        local key = RuntimeFlow.CanonicalUserId(entry.userId)
        if key and not seen[key] then
            seen[key] = true
            userIds[#userIds + 1] = entry.userId
        end
    end
    if #userIds == 0 then return end

    local lobbyApi = rawget(_G, "lobby")
    if lobbyApi and lobbyApi.GetUserNickname then
        local numericUserIds = {}
        for _, userId in ipairs(userIds) do
            local nativeId = RuntimeFlow.NativeUserId(userId)
            if nativeId ~= nil then numericUserIds[#numericUserIds + 1] = nativeId end
        end
        if #numericUserIds > 0 then
            local requestId = lobbyApi:GetUserNickname(numericUserIds)
            if requestId and requestId >= 0 then
                RuntimeFlow.fullLeaderboardNicknameRequestId = requestId
                RuntimeFlow.fullLeaderboardNicknameGeneration = requestGeneration
                return
            end
        end
    end

    if not GetUserNickname then
        print("[Bounce4096] 当前环境没有可用的完整排行榜昵称接口")
        return
    end
    GetUserNickname({
        userIds = userIds,
        onSuccess = function(nicknames)
            RuntimeFlow.ApplyFullLeaderboardNicknames(requestGeneration, nicknames)
        end,
        onError = function(errorCode)
            if requestGeneration == RuntimeFlow.fullLeaderboardRequestGeneration then
                print("[Bounce4096] 完整排行榜昵称加载失败: " .. tostring(errorCode))
            end
        end,
    })
end

function RuntimeFlow.RefreshFullLeaderboardPage(page, refreshTotal)
    if not clientCloud then
        RuntimeFlow.fullLeaderboardLoading = false
        RuntimeFlow.fullLeaderboardError = "当前环境无法访问排行榜"
        return
    end
    page = math.max(0, math.floor(tonumber(page) or 0))
    RuntimeFlow.fullLeaderboardRequestGeneration = RuntimeFlow.fullLeaderboardRequestGeneration + 1
    local requestGeneration = RuntimeFlow.fullLeaderboardRequestGeneration
    RuntimeFlow.fullLeaderboardLoading = true
    RuntimeFlow.fullLeaderboardError = nil

    local function LoadPage()
        if requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
        if RuntimeFlow.fullLeaderboardTotal > 0 then
            local lastPage = math.max(0, math.ceil(RuntimeFlow.fullLeaderboardTotal / RuntimeFlow.fullLeaderboardPageSize) - 1)
            page = math.min(page, lastPage)
        end
        local startOffset = page * RuntimeFlow.fullLeaderboardPageSize
        clientCloud:GetRankList(LEADERBOARD_KEY, startOffset, RuntimeFlow.fullLeaderboardPageSize, {
            ok = function(rankList)
                if requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
                local entries = {}
                for i, item in ipairs(rankList or {}) do
                    local userId = item.userId or item.player
                    if userId then
                        local scoreValues = item.iscore or {}
                        entries[#entries + 1] = {
                            rank = math.max(1, math.floor(tonumber(item.rank) or (startOffset + i))),
                            userId = userId,
                            score = math.floor(tonumber(scoreValues[LEADERBOARD_KEY]
                                or item.scoreValue or item.value) or 0),
                            isMe = RuntimeFlow.CanonicalUserId(userId)
                                == RuntimeFlow.CanonicalUserId(clientCloud.userId),
                        }
                    end
                end
                RuntimeFlow.fullLeaderboard = entries
                RuntimeFlow.fullLeaderboardPage = page
                if RuntimeFlow.fullLeaderboardTotal <= 0 then
                    RuntimeFlow.fullLeaderboardTotal = startOffset + #entries
                    if #entries == RuntimeFlow.fullLeaderboardPageSize then
                        RuntimeFlow.fullLeaderboardTotal = RuntimeFlow.fullLeaderboardTotal + 1
                    end
                end
                RuntimeFlow.fullLeaderboardLoading = false
                RuntimeFlow.ResolveFullLeaderboardNicknames(entries, requestGeneration)
                print("[Bounce4096] 完整排行榜第" .. tostring(page + 1)
                    .. "页加载完成，条目=" .. tostring(#entries))
            end,
            error = function(code, reason)
                if requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
                RuntimeFlow.fullLeaderboardLoading = false
                RuntimeFlow.fullLeaderboardError = "排行榜暂时不可用"
                print("[Bounce4096] 完整排行榜加载失败: " .. tostring(code) .. " " .. tostring(reason))
            end,
            timeout = function()
                if requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
                RuntimeFlow.fullLeaderboardLoading = false
                RuntimeFlow.fullLeaderboardError = "排行榜加载超时"
            end,
        })
    end

    if refreshTotal and clientCloud.GetRankTotal then
        local totalResolved = false
        clientCloud:GetRankTotal(LEADERBOARD_KEY, {
            ok = function(total)
                if totalResolved or requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
                totalResolved = true
                RuntimeFlow.fullLeaderboardTotal = math.max(0, math.floor(tonumber(total) or 0))
                LoadPage()
            end,
            error = function(code, reason)
                if totalResolved or requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
                totalResolved = true
                RuntimeFlow.fullLeaderboardTotal = 0
                print("[Bounce4096] 排行榜总人数读取失败: " .. tostring(code) .. " " .. tostring(reason))
                LoadPage()
            end,
            timeout = function()
                if totalResolved or requestGeneration ~= RuntimeFlow.fullLeaderboardRequestGeneration then return end
                totalResolved = true
                RuntimeFlow.fullLeaderboardTotal = 0
                LoadPage()
            end,
        })
    else
        LoadPage()
    end
end

local function SubmitHighScore()
    if leaderboardSubmitted_ or not clientCloud then return end
    leaderboardSubmitted_ = true
    leaderboardLoading_ = true
    leaderboardError_ = nil
    local finalScore = math.max(0, math.floor(score_))
    clientCloud:Get(LEADERBOARD_KEY, {
        ok = function(values, iscores)
            personalBest_ = math.max(0, math.floor((iscores and iscores[LEADERBOARD_KEY]) or 0))
            if finalScore <= personalBest_ then
                leaderboardLoading_ = false
                RefreshLeaderboard()
                return
            end
            clientCloud:SetInt(LEADERBOARD_KEY, finalScore, {
                ok = function()
                    personalBest_ = finalScore
                    leaderboardLoading_ = false
                    print("[Bounce4096] 新历史最高分已上榜: " .. finalScore)
                    RefreshLeaderboard()
                end,
                error = function(code, reason)
                    leaderboardLoading_ = false
                    leaderboardError_ = "最高分保存失败"
                    print("[Bounce4096] 最高分保存失败: " .. tostring(code) .. " " .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            leaderboardLoading_ = false
            leaderboardError_ = "最高分读取失败"
            print("[Bounce4096] 最高分读取失败: " .. tostring(code) .. " " .. tostring(reason))
            RefreshLeaderboard()
        end,
        timeout = function()
            leaderboardLoading_ = false
            leaderboardError_ = "最高分读取超时"
            RefreshLeaderboard()
        end,
    })
end

local function TriggerShake(power, duration)
    shakePower_ = math.max(shakePower_, power)
    shakeTime_ = math.max(shakeTime_, duration)
end

local function CreateMergeEffect(x, y, z, value, showImpact, showScore, explosion)
    local color = ValueColor(value)
    local mergeCosmetic = metaGame_ and metaGame_:Equipped("merge") or nil
    if mergeCosmetic and mergeCosmetic.color then color = mergeCosmetic.color end
    local level = math.log(value, 2)
    local particles = {}
    local count = explosion
        and math.min(30, 18 + math.floor(level * 1.4))
        or (showImpact == false
            and math.min(18, 8 + math.floor(level * 1.2))
            or math.min(36, 12 + math.floor(level * 2.4)))
    local fireworks = metaGame_ and metaGame_:Equipped("fireworks") or nil
    if RuntimeFlow.comboCount >= 2 and fireworks and fireworks.effect ~= "classic" then
        count = math.floor(count * (fireworks.effect == "starfall" and 1.55 or 1.35))
    end
    for i = 1, count do
        local a = math.random() * math.pi * 2
        local speed = explosion
            and (7.2 + math.random() * (7.5 + level * 0.45))
            or (4.2 + math.random() * (5.8 + level * 0.4))
        local particleColor = color
        if math.random() <= (explosion and 0.48 or 0.26) then
            particleColor = math.random() > 0.45 and RETRO.cream or RETRO.mustard
        end
        particles[#particles + 1] = {
            x = x, y = y + 0.4, z = z,
            vx = math.cos(a) * speed,
            vy = explosion
                and (5.8 + math.random() * (6.2 + level * 0.24))
                or (4.4 + math.random() * (4.2 + level * 0.2)),
            vz = math.sin(a) * speed,
            size = explosion
                and (0.11 + math.random() * 0.18)
                or (0.08 + math.random() * 0.12),
            age = 0,
            life = explosion
                and (0.48 + math.random() * 0.3)
                or (0.58 + math.random() * 0.24),
            color = particleColor,
        }
    end
    effects_[#effects_ + 1] = {
        x = x, y = y, z = z,
        value = value, level = level, age = 0,
        life = explosion and 0.72 or (0.88 + math.min(level * 0.045, 0.5)),
        color = color, particles = particles,
        showScore = showScore ~= false,
        explosion = explosion == true,
    }
    if showImpact ~= false then
        local seed = math.floor(math.abs(x * 97000 + z * 193000 + value * 17 + os.clock() * 100000))
        impacts_[#impacts_ + 1] = {
            x = x, z = z, age = 0,
            life = 1.18 + math.min(level * 0.055, 0.62),
            color = color, value = value, level = level,
            power = Clamp(0.72 + level * 0.045, 0.78, 1.16),
            seed = seed,
            rotation = ((seed % 1000) / 1000 - 0.5) * 0.8,
        }
        if #impacts_ > 2 then table.remove(impacts_, 1) end
        mergeSlowTime_ = math.max(mergeSlowTime_, math.min(0.08, 0.035 + level * 0.004))
    end
end

function RuntimeFlow.ResetComboState()
    RuntimeFlow.comboCount = 0
    RuntimeFlow.comboPopupAge = nil
    RuntimeFlow.comboPopupSerial = 0
end

function RuntimeFlow.RecordComboMerge()
    local continued = RuntimeFlow.comboPopupAge ~= nil
        and RuntimeFlow.comboPopupAge <= RuntimeFlow.comboWindowSeconds
    if continued then
        RuntimeFlow.comboCount = RuntimeFlow.comboCount + 1
    else
        RuntimeFlow.comboCount = 1
    end

    -- 每次合成都刷新固定的 2 秒 COMBO 续连窗口；首次合成只计数，
    -- 第二次连续合成开始显示。
    RuntimeFlow.comboPopupAge = 0
    maxComboThisRun_ = math.max(maxComboThisRun_, RuntimeFlow.comboCount)
    print("[Bounce4096] COMBO " .. (continued and "续连至 " or "重新开始为 ")
        .. RuntimeFlow.comboCount)
    if RuntimeFlow.comboCount >= 2 then
        RuntimeFlow.comboPopupSerial = RuntimeFlow.comboPopupSerial + 1
        local comboIntensity = Clamp((RuntimeFlow.comboCount - 2) / 10, 0, 1)
        TriggerShake(4.5 + comboIntensity * 8.5, 0.09 + comboIntensity * 0.1)
    end
end

function RuntimeFlow.UpdateComboWindow(dt)
    if RuntimeFlow.comboPopupAge == nil then return end

    RuntimeFlow.comboPopupAge = RuntimeFlow.comboPopupAge + dt
    if RuntimeFlow.comboPopupAge <= RuntimeFlow.comboWindowSeconds then return end

    if RuntimeFlow.comboCount > 0 then
        print("[Bounce4096] COMBO窗口结束且没有新合成，COMBO 从 "
            .. RuntimeFlow.comboCount .. " 清零")
    end
    RuntimeFlow.comboCount = 0
    RuntimeFlow.comboPopupAge = nil
end

local function FindNearestMergeFlightTarget(value, x, z, excludedA, excludedB, maxTargetZ, searchRadius)
    local nearest, nearestDistance = nil, math.huge
    for _, candidate in ipairs(blocks_) do
        if candidate ~= excludedA and candidate ~= excludedB
            and candidate.value == value
            and candidate.z <= maxTargetZ then
            local distance = Length2(candidate.x - x, candidate.z - z)
            if distance <= searchRadius and distance < nearestDistance then
                nearest, nearestDistance = candidate, distance
            end
        end
    end
    return nearest and { block = nearest, distance = nearestDistance } or nil
end

local function DampedTravelFactor(seconds)
    local damping = Clamp(WORLD.airLinearDamping or 0, 0, 0.999999)
    local dampingRate = -math.log(1 - damping)
    if dampingRate < 0.0001 then return seconds end
    return (1 - math.exp(-dampingRate * seconds)) / dampingRate
end

local function MergeFlightChance(distance, searchRadius)
    local normalRadius = WORLD.trayW * 0.5
    local radiusScale = normalRadius > 0 and searchRadius / normalRadius or 1
    local guaranteedDistance = math.min(3.5 * radiusScale, searchRadius)
    if distance <= guaranteedDistance then return 1 end
    if distance >= searchRadius then return 0.5 end
    local stepSize = 0.2 * radiusScale
    local totalSteps = math.max(1, math.ceil((searchRadius - guaranteedDistance) / stepSize))
    local distanceStep = math.min(
        totalSteps,
        math.ceil((distance - guaranteedDistance) / stepSize - 1e-9)
    )
    return 1 - 0.5 * distanceStep / totalSteps
end

local function PlanMergedBlockFlight(value, x, y, z, excludedA, excludedB, jumpVelocity)
    local redLineSafetyDistance = BlockSizeForValue(value) * 1.25
    local nearRedLine = z >= WORLD.dangerZ - redLineSafetyDistance
    local maxTargetZ = WORLD.dangerZ
        - WORLD.playBoundaryL * MERGE_TARGET_RED_LINE_EXCLUSION_RATIO
    local searchRadius = WORLD.trayW * 0.5
    local nearby = FindNearestMergeFlightTarget(
        value,
        x,
        z,
        excludedA,
        excludedB,
        maxTargetZ,
        searchRadius
    )
    local homingChance = nearby and MergeFlightChance(nearby.distance, searchRadius) or 0
    if nearby and math.random() < homingChance then
        local target = nearby.block
        -- 此处只需要预测目标高度；目标若已翻滚，保守使用当前中心高度，
        -- 否则以标准半边长作为地面高度。
        local targetY = math.max(BlockSizeForValue(target.value) / 2, target.y)
        local heightDelta = targetY - y
        local discriminant = math.max(
            0,
            jumpVelocity * jumpVelocity - 2 * WORLD.gravity * heightDelta
        )
        local travelTime = Clamp(
            (jumpVelocity + math.sqrt(discriminant)) / WORLD.gravity,
            0.35,
            3
        )
        local travelFactor = math.max(0.001, DampedTravelFactor(travelTime))
        local targetX = target.x + target.vx * travelFactor
        local targetZ = math.min(target.z + target.vz * travelFactor, maxTargetZ)
        return {
            vx = (targetX - x) / travelFactor,
            vy = jumpVelocity,
            vz = (targetZ - z) / travelFactor,
            homing = true,
            targetId = target.id,
        }
    end

    local driftSpeed = 0.2 + math.random() * 0.5
    local driftVX, driftVZ
    if nearRedLine then
        local inwardAngle = (math.random() - 0.5) * math.pi * 2 / 3
        driftVX = math.sin(inwardAngle) * driftSpeed
        driftVZ = -math.cos(inwardAngle) * driftSpeed
    else
        local driftAngle = math.random() * math.pi * 2
        driftVX = math.cos(driftAngle) * driftSpeed
        driftVZ = math.sin(driftAngle) * driftSpeed
    end
    return { vx = driftVX, vy = jumpVelocity, vz = driftVZ, homing = false, targetId = nil }
end

local function MergeBlocks(a, b)
    local value = a.value * 2
    local x = (a.x + b.x) / 2
    local z = (a.z + b.z) / 2
    local mergedSize = BlockSizeForValue(value)
    local y = math.max(mergedSize / 2 + 0.35, (a.y + b.y) / 2)
    local inheritedDanger = nil
    if a.dangerTime and b.dangerTime then inheritedDanger = math.min(a.dangerTime, b.dangerTime)
    elseif a.dangerTime then inheritedDanger = a.dangerTime
    elseif b.dangerTime then inheritedDanger = b.dangerTime end

    local thawedIce = a.frozen == true or b.frozen == true
    if heavyBlock_ == a or heavyBlock_ == b then heavyBlock_ = nil end
    for i = #blocks_, 1, -1 do
        if blocks_[i] == a or blocks_[i] == b then table.remove(blocks_, i) end
    end

    local jumpVelocity = math.sqrt(2 * WORLD.gravity * mergedSize * 4.575)
    local flight = PlanMergedBlockFlight(value, x, y, z, a, b, jumpVelocity)
    local block = CreateBlock(value, x, y, z, flight.vx, flight.vy, flight.vz, true)
    block.mergeFlightTargetId = flight.targetId
    block.mergeFlightHoming = flight.homing
    block.dangerTime = z > WORLD.dangerZ and inheritedDanger or nil
    blocks_[#blocks_ + 1] = block
    AddScore(value)
    spawnManager_:RecordMerge(value, ddaElapsed_)
    RuntimeFlow.RecordComboMerge()
    if metaGame_ then
        metaGame_:RecordMerge(value, RuntimeFlow.comboCount, os.time())
        if gameMode_ == "daily" and thawedIce then metaGame_:RecordChallengeThaw() end
        if gameMode_ == "daily" then
            local reward = metaGame_:RecordChallengeScore(score_)
            if reward > 0 and metaUI_ then metaUI_:SetToast("寒冰连发完成！奖励 ★" .. reward) end
        end
    end
    CreateMergeEffect(x, y, z, value)
    PlayMergeSfx(value)
    local level = math.log(value, 2)
    local growth = math.max(1, level - 1) ^ 1.32
    TriggerShake(Clamp(3.2 + growth * 0.78, 5, 28), 0.08 + math.min(0.12, level * 0.009))
    tip_ = "向后拖动方块发射"
    print("[Bounce4096] 合成 " .. value .. "，score=" .. score_)
    SaveGame()
end

-- 将后续物理、游戏循环、渲染和输入声明放进独立函数作用域。
-- Lua 主 chunk 最多允许 200 个局部变量；这里通过闭包继续访问上方状态，
-- 同时为主 chunk 留出局部变量余量，避免后续新增 helper 再次触顶。
function RuntimeFlow.InstallGameScope()
local function GetBlockDeformation(_block)
    -- 动物的不规则占地只用于推导统一边长；视觉、碰撞与拖影始终共用
    -- 同一个 X/Y/Z 缩放，避免方块在发射或落地时变成长方体。
    return { x = 1, y = 1, z = 1 }
end

local function CubeSupportHeightAt(rx, ry, rz, scaleValue)
    local axisX = RotatePoint(V3(1, 0, 0), rx, ry, rz)
    local axisY = RotatePoint(V3(0, 1, 0), rx, ry, rz)
    local axisZ = RotatePoint(V3(0, 0, 1), rx, ry, rz)
    return WORLD.cube * (scaleValue or 1) / 2
        * (math.abs(axisX.y) + math.abs(axisY.y) + math.abs(axisZ.y))
end

local function CubeGroundSupportHeight(block)
    local scaleValue = block.scale or BlockScaleForValue(block.value)
    if not block.canAirSpin then return WORLD.cube * scaleValue / 2 end
    return CubeSupportHeightAt(block.rx, block.ry, block.rz, scaleValue)
end

local function NearestStableCubeAngle(angle)
    local quarterTurn = math.pi / 2
    return math.floor(angle / quarterTurn + 0.5) * quarterTurn
end

local function UpdateGroundedBlockRotation(block, dt)
    local sampleAngle = 0.003
    local scaleValue = block.scale or BlockScaleForValue(block.value)
    local blockSize = WORLD.cube * scaleValue
    local inertiaPerMass = blockSize * blockSize / 6
    local slopeX = (CubeSupportHeightAt(block.rx + sampleAngle, block.ry, block.rz, scaleValue)
            - CubeSupportHeightAt(block.rx - sampleAngle, block.ry, block.rz, scaleValue))
        / (sampleAngle * 2)
    local slopeZ = (CubeSupportHeightAt(block.rx, block.ry, block.rz + sampleAngle, scaleValue)
            - CubeSupportHeightAt(block.rx, block.ry, block.rz - sampleAngle, scaleValue))
        / (sampleAngle * 2)
    local groundDamping = 0.965 ^ (dt * 60)
    local yawDamping = 0.94 ^ (dt * 60)
    block.spinX = (block.spinX - WORLD.gravity * slopeX / inertiaPerMass * dt) * groundDamping
    block.spinZ = (block.spinZ - WORLD.gravity * slopeZ / inertiaPerMass * dt) * groundDamping
    block.spinY = block.spinY * yawDamping
    block.rx = block.rx + block.spinX * dt
    block.ry = block.ry + block.spinY * dt
    block.rz = block.rz + block.spinZ * dt
    local targetX, targetZ = NearestStableCubeAngle(block.rx), NearestStableCubeAngle(block.rz)
    if math.abs(targetX - block.rx) < 0.035 and math.abs(block.spinX) < 0.78 then
        block.rx, block.spinX = targetX, 0
    end
    if math.abs(targetZ - block.rz) < 0.035 and math.abs(block.spinZ) < 0.78 then
        block.rz, block.spinZ = targetZ, 0
    end
    if math.abs(block.spinY) < 0.012 then block.spinY = 0 end
end

local function VisibleExtents(block)
    local deformation = GetBlockDeformation(block)
    local scaleValue = block.scale or 1
    local halfX = WORLD.cube * scaleValue * deformation.x / 2
    local halfY = WORLD.cube * scaleValue * deformation.y / 2
    local halfZ = WORLD.cube * scaleValue * deformation.z / 2
    local axisX = RotatePoint(V3(1, 0, 0), block.rx, block.ry, block.rz)
    local axisY = RotatePoint(V3(0, 1, 0), block.rx, block.ry, block.rz)
    local axisZ = RotatePoint(V3(0, 0, 1), block.rx, block.ry, block.rz)
    return {
        x = math.abs(axisX.x) * halfX + math.abs(axisY.x) * halfY + math.abs(axisZ.x) * halfZ,
        y = math.abs(axisX.y) * halfX + math.abs(axisY.y) * halfY + math.abs(axisZ.y) * halfZ,
        z = math.abs(axisX.z) * halfX + math.abs(axisY.z) * halfY + math.abs(axisZ.z) * halfZ,
    }
end

local function ShadowHullCross(origin, a, b)
    return (a.x - origin.x) * (b.z - origin.z)
        - (a.z - origin.z) * (b.x - origin.x)
end

local function ShadowConvexHull(points)
    local sorted = {}
    for i, point in ipairs(points) do sorted[i] = point end
    table.sort(sorted, function(a, b)
        return a.x == b.x and a.z < b.z or a.x < b.x
    end)
    if #sorted <= 2 then return sorted end

    local lower = {}
    for _, point in ipairs(sorted) do
        while #lower >= 2
            and ShadowHullCross(lower[#lower - 1], lower[#lower], point) <= 0 do
            table.remove(lower)
        end
        lower[#lower + 1] = point
    end
    local upper = {}
    for i = #sorted, 1, -1 do
        local point = sorted[i]
        while #upper >= 2
            and ShadowHullCross(upper[#upper - 1], upper[#upper], point) <= 0 do
            table.remove(upper)
        end
        upper[#upper + 1] = point
    end
    table.remove(lower)
    table.remove(upper)
    for _, point in ipairs(upper) do lower[#lower + 1] = point end
    return lower
end

local function ProjectedBlockShadowHull(block, groundY)
    if not block then return {} end
    local deformation = GetBlockDeformation(block)
    local size = WORLD.cube * block.scale
    local sx, sy, sz = size * deformation.x, size * deformation.y, size * deformation.z
    local visualY = block.y <= CubeGroundSupportHeight(block) + 0.08
        and block.y + (sy - size) / 2 or block.y
    local center = V3(block.x, visualY, block.z)
    local projected = {}
    for _, ix in ipairs({ -1, 1 }) do
        for _, iy in ipairs({ -1, 1 }) do
            for _, iz in ipairs({ -1, 1 }) do
                local corner = Add(center, RotatePoint(
                    V3(ix * sx / 2, iy * sy / 2, iz * sz / 2),
                    block.rx or 0,
                    block.ry or 0,
                    block.rz or 0
                ))
                local rayDistance = math.max(0, corner.y - groundY)
                    / math.max(0.001, STYLIZED_LIGHT_DIRECTION.y)
                projected[#projected + 1] = V3(
                    corner.x - STYLIZED_LIGHT_DIRECTION.x * rayDistance,
                    groundY,
                    corner.z - STYLIZED_LIGHT_DIRECTION.z * rayDistance
                )
            end
        end
    end
    return ShadowConvexHull(projected)
end

function RuntimeFlow.DrawBlockGroundShadow(block)
    local hull = ProjectedBlockShadowHull(block, 0)
    if #hull < 3 then return end
    local palette = StylizedLightingPalette()
    local supportY = CubeGroundSupportHeight(block)
    local airborne = Clamp(
        (block.y - supportY) / math.max(0.01, WORLD.cube * block.scale * 3),
        0,
        1
    )
    local centerX, centerZ = 0, 0
    for _, point in ipairs(hull) do
        centerX = centerX + point.x
        centerZ = centerZ + point.z
    end
    centerX, centerZ = centerX / #hull, centerZ / #hull

    -- NanoVG 没有 Canvas shadowBlur；用三层轻微外扩轮廓近似柔边半影。
    for layer = 3, 1, -1 do
        local expansion = (0.018 + airborne * 0.07) * layer
        local renderHull = {}
        for i, point in ipairs(hull) do
            renderHull[i] = V3(
                centerX + (point.x - centerX) * (1 + expansion),
                0.101,
                centerZ + (point.z - centerZ) * (1 + expansion)
            )
        end
        local alpha = (0.055 + (4 - layer) * 0.025) * (1 - airborne * 0.38)
        DrawFloorPolygon(renderHull, palette.shadow, alpha)
    end
    if airborne < 0.72 then
        local coreHull = {}
        for i, point in ipairs(hull) do coreHull[i] = V3(point.x, 0.102, point.z) end
        DrawFloorPolygon(coreHull, palette.shadow, 0.14 * (1 - airborne / 0.72))
    end
end

function RuntimeFlow.DrawBlockGroundShadows()
    for _, block in ipairs(blocks_) do RuntimeFlow.DrawBlockGroundShadow(block) end
end

local function UpdateMergeCollisionProtection(block, dt)
    -- 合成起飞阶段碰撞区（俯视）：
    --   [邻块]∩[新合成块] 仍重叠 → 暂不参与方块碰撞
    --   重叠解除或达到 1.4 秒上限 → 恢复正常碰撞/合成
    -- 边界：最少保护 0.06 秒，避免同一物理帧刚删除父块就产生分离冲量。
    if not block.mergeCollisionProtected then return end
    block.mergeCollisionProtectionAge = (block.mergeCollisionProtectionAge or 0) + dt
    if block.mergeCollisionProtectionAge < MERGE_COLLISION_PROTECTION_MIN then return end

    local extent = VisibleExtents(block)
    local stillOverlapping = false
    for _, other in ipairs(blocks_) do
        if other ~= block then
            local otherExtent = VisibleExtents(other)
            local overlapX = extent.x + otherExtent.x - math.abs(other.x - block.x)
            local overlapY = extent.y + otherExtent.y - math.abs(other.y - block.y)
            local overlapZ = extent.z + otherExtent.z - math.abs(other.z - block.z)
            if overlapX > 0 and overlapY > 0 and overlapZ > 0 then
                stillOverlapping = true
                break
            end
        end
    end
    if not stillOverlapping
        or block.mergeCollisionProtectionAge >= MERGE_COLLISION_PROTECTION_MAX then
        block.mergeCollisionProtected = false
        block.mergeCollisionProtectionAge = nil
    end
end

local function ConstrainBlockToTray(block)
    local e = VisibleExtents(block)
    local limitX = math.max(0, WORLD.trayW / 2 - e.x - 0.035)
    local limitZ = math.max(0, WORLD.trayL / 2 - e.z - 0.035)
    local hitWall = false
    local wallImpactSpeed = 0
    if block.x < -limitX then
        wallImpactSpeed = math.max(wallImpactSpeed, math.max(0, -block.vx))
        block.x = -limitX
        block.vx = math.abs(block.vx) * WORLD.wallRestitution
        hitWall = true
    elseif block.x > limitX then
        wallImpactSpeed = math.max(wallImpactSpeed, math.max(0, block.vx))
        block.x = limitX
        block.vx = -math.abs(block.vx) * WORLD.wallRestitution
        hitWall = true
    end
    if block.z < -limitZ then
        wallImpactSpeed = math.max(wallImpactSpeed, math.max(0, -block.vz))
        block.z = -limitZ
        block.vz = math.abs(block.vz) * WORLD.wallRestitution
        hitWall = true
    elseif block.z > limitZ then
        wallImpactSpeed = math.max(wallImpactSpeed, math.max(0, block.vz))
        block.z = limitZ
        block.vz = -math.abs(block.vz) * WORLD.wallRestitution
        hitWall = true
    end
    if hitWall then
        RuntimeFlow.PlayCollisionSfx(wallImpactSpeed, block, nil)
        block.launchTrail = false
    end
end

local function ApplySameValueAttraction(dt)
    for i = 1, #blocks_ do
        local a = blocks_[i]
        for j = i + 1, #blocks_ do
            local b = blocks_[j]
            -- 提前跳过：不同值方块不会互相吸引
            if a.value ~= b.value then goto continue end
            if a.cooldown > 0.24 or b.cooldown > 0.24 then goto continue end
            
            -- 提前粗略距离检测
            local dx, dz = b.x - a.x, b.z - a.z
            local dist = Length2(dx, dz)
            if dist >= WORLD.attractionRange then goto continue end
            
            local speedA, speedB = Length2(a.vx, a.vz), Length2(b.vx, b.vz)
            local contactSize = WORLD.cube * ((a.scale or 1) + (b.scale or 1)) / 2
            if dist <= contactSize * 1.02 then goto continue end
            
            local groundA, groundB = CubeGroundSupportHeight(a), CubeGroundSupportHeight(b)
            local movingPair = speedA > 0.7 or speedB > 0.7
                or a.y > groundA + 0.12 or b.y > groundB + 0.12
            if movingPair and math.abs(a.y - b.y) <= contactSize * 1.45 then
                local pull = (1 - dist / WORLD.attractionRange) ^ 2 * WORLD.attractionStrength * dt
                local nx, nz = dx / dist, dz / dist
                local massA, massB = a.mass or BlockMassForValue(a.value), b.mass or BlockMassForValue(b.value)
                a.vx = a.vx + nx * pull / massA
                a.vz = a.vz + nz * pull / massA
                b.vx = b.vx - nx * pull / massB
                b.vz = b.vz - nz * pull / massB
            end
            ::continue::
        end
    end
end

local function UpdateBlockAfterimages(block, dt)
    for i = #block.afterimages, 1, -1 do
        local ghost = block.afterimages[i]
        ghost.age = ghost.age + dt
        if ghost.age >= ghost.life then table.remove(block.afterimages, i) end
    end
    if not block.launchTrail or Length2(block.vx, block.vz) < 4 then
        block.launchTrail = false
        return
    end
    block.afterimageTimer = block.afterimageTimer - dt
    if block.afterimageTimer > 0 then return end
    block.afterimageTimer = 0.072
    local deformation = GetBlockDeformation(block)
    block.afterimages[#block.afterimages + 1] = {
        x = block.x,
        y = block.y,
        z = block.z,
        rx = block.rx,
        ry = block.ry,
        rz = block.rz,
        scale = block.scale,
        deformX = deformation.x,
        deformY = deformation.y,
        deformZ = deformation.z,
        age = 0,
        life = 0.29,
    }
    if #block.afterimages > 3 then table.remove(block.afterimages, 1) end
end

local function UpdateBlocks(dt)
    local groundFriction = WORLD.slideFriction ^ (dt * 60)
    local airDamping = (1 - Clamp(WORLD.airLinearDamping or 0, 0, 0.999999)) ^ dt
    for _, b in ipairs(blocks_) do
        if b.frozen then
            b.mass = 1000000000
            b.vx, b.vy, b.vz = 0, 0, 0
            b.spinX, b.spinY, b.spinZ = 0, 0, 0
            b.canAirSpin = false
        end
        b.age = b.age + dt
        b.cooldown = math.max(0, b.cooldown - dt)
        b.collisionSfxCooldown = math.max(0, (b.collisionSfxCooldown or 0) - dt)

        local groundHeightBefore = CubeGroundSupportHeight(b)
        local wasAirborne = b.y > groundHeightBefore + 0.03 or b.vy > 0.05
        local horizontalDamping = wasAirborne and airDamping or groundFriction
        b.vx = b.vx * horizontalDamping
        b.vz = b.vz * horizontalDamping
        if wasAirborne then
            b.vy = b.vy - WORLD.gravity * dt
        else
            b.y = groundHeightBefore
            b.vy = 0
        end
        if math.abs(b.vx) < 0.08 then b.vx = 0 end
        if math.abs(b.vz) < 0.08 then b.vz = 0 end
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.z = b.z + b.vz * dt
        local isAirborne = b.y > groundHeightBefore + 0.08 or b.vy > 0.15
        if isAirborne and b.canAirSpin then
            b.rx = b.rx + b.spinX * dt
            b.ry = b.ry + b.spinY * dt
            b.rz = b.rz + b.spinZ * dt
            b.spinX = b.spinX * (0.999 ^ (dt * 60))
            b.spinY = b.spinY * (0.999 ^ (dt * 60))
            b.spinZ = b.spinZ * (0.999 ^ (dt * 60))
        elseif b.canAirSpin then
            UpdateGroundedBlockRotation(b, dt)
        end
        b.squash = (b.squash or 0) * (0.82 ^ (dt * 60))
        local groundHeightAfter = CubeGroundSupportHeight(b)
        if b.y < groundHeightAfter then
            local landingSpeed = math.max(0, -b.vy)
            local landingStrength = Clamp((landingSpeed - 3) / 13, 0, 1)
            local landingSquash = landingStrength * landingStrength * (3 - 2 * landingStrength) * 0.28
            b.y = groundHeightAfter
            b.vy = math.abs(b.vy) > 1.2 and -b.vy * WORLD.floorBounce or 0
            if landingSquash > 0 then b.squash = math.max(b.squash, landingSquash) end
            if b.canAirSpin and landingStrength > 0 then
                b.spinX = b.spinX - b.vz * 0.075 * landingStrength
                b.spinZ = b.spinZ + b.vx * 0.075 * landingStrength
            end
        elseif not isAirborne and math.abs(b.vy) <= 0.05 then
            b.y = groundHeightAfter
        end
        b.scale = b.scale + (b.targetScale - b.scale) * math.min(1, dt * 8.5)
        UpdateMergeCollisionProtection(b, dt)
        ConstrainBlockToTray(b)
        UpdateBlockAfterimages(b, dt)
    end
end

local function BlocksWithinMergeContact(a, b, extentA, extentB)
    local minimumVisibleOverlap = WORLD.cube * 0.015
    local contactTolerance = WORLD.collisionSeparation + minimumVisibleOverlap
    local overlapX = extentA.x + extentB.x - math.abs(b.x - a.x)
    local overlapY = extentA.y + extentB.y - math.abs(b.y - a.y)
    local overlapZ = extentA.z + extentB.z - math.abs(b.z - a.z)
    local horizontalContact = (overlapX > minimumVisibleOverlap and overlapZ >= -contactTolerance)
        or (overlapZ > minimumVisibleOverlap and overlapX >= -contactTolerance)
    return horizontalContact and overlapY > minimumVisibleOverlap
end

local function CollisionSquashAmount(impactSpeed, massA, massB)
    local reducedMassScale = math.sqrt(2 * massA * massB / (massA + massB))
    local weightedImpact = impactSpeed * Clamp(reducedMassScale, 1, 1.35)
    local strength = Clamp((weightedImpact - 3.2) / 17.8, 0, 1)
    return strength * strength * (3 - 2 * strength) * 0.3
end

local function LaunchedPushContext(a, b)
    -- 首次弹射推撞（俯视）：
    --   发射块 A  --->  [目标 B]
    -- A 沿发射方向保留 55% 速度，B 至少获得 72%；侧向分量仍由普通
    -- 碰撞求解处理。擦边/反向移动不会触发此额外推撞。
    local launched = heavyBlock_ == a and a or (heavyBlock_ == b and b or nil)
    if not launched then return nil end
    local pushed = launched == a and b or a
    local dirX = tonumber(launched.launchDirX) or 0
    local dirZ = tonumber(launched.launchDirZ) or 0
    local directionLength = Length2(dirX, dirZ)
    if directionLength < 0.001 then
        dirX, dirZ = launched.vx, launched.vz
        directionLength = Length2(dirX, dirZ)
    end
    if directionLength < 0.001 then return nil end
    dirX, dirZ = dirX / directionLength, dirZ / directionLength
    local launchedForwardSpeed = launched.vx * dirX + launched.vz * dirZ
    if launchedForwardSpeed <= 0.05 then return nil end
    return {
        launched = launched,
        pushed = pushed,
        dirX = dirX,
        dirZ = dirZ,
        launchedForwardSpeed = launchedForwardSpeed,
        pushedForwardSpeed = pushed.vx * dirX + pushed.vz * dirZ,
    }
end

local function ApplyLaunchedPush(context, impactSpeed)
    if not context or impactSpeed <= 0 then return end
    if context.pushed.frozen then return end
    local launchedSpeed = context.launchedForwardSpeed * WORLD.launchedImpactRetain
    local pushedSpeed = math.max(
        context.pushedForwardSpeed,
        context.launchedForwardSpeed * WORLD.launchedImpactTransfer
    )
    local launchedCurrent = context.launched.vx * context.dirX
        + context.launched.vz * context.dirZ
    local pushedCurrent = context.pushed.vx * context.dirX
        + context.pushed.vz * context.dirZ
    context.launched.vx = context.launched.vx
        + (launchedSpeed - launchedCurrent) * context.dirX
    context.launched.vz = context.launched.vz
        + (launchedSpeed - launchedCurrent) * context.dirZ
    context.pushed.vx = context.pushed.vx
        + (pushedSpeed - pushedCurrent) * context.dirX
    context.pushed.vz = context.pushed.vz
        + (pushedSpeed - pushedCurrent) * context.dirZ
end

local function ResolveBlockCollisions()
    -- 俯视碰撞区域（旋转、缩放后的可见 AABB）：
    --   [ A 的半宽 ]|<-- overlapX -->|[ B 的半宽 ]
    -- 检测目的：同值且三轴重叠时合成；不同值重叠时沿较浅轴分离并自然反弹。
    -- 边界情况：旋转方块取包围盒、大小不同取双方尺寸之和、同值冷却期间保留少量重叠。
    local pairs = {}
    local merged = {}
    for i = 1, #blocks_ do
        local a = blocks_[i]
        if not merged[a.id] then
            for j = i + 1, #blocks_ do
                local b = blocks_[j]
                if not merged[b.id] then
                    local dx, dz = b.x - a.x, b.z - a.z
                    local extentA, extentB = VisibleExtents(a), VisibleExtents(b)
                    local contactSizeX = extentA.x + extentB.x
                    local contactSizeY = extentA.y + extentB.y
                    local contactSizeZ = extentA.z + extentB.z
                    local overlapX = contactSizeX - math.abs(dx)
                    local overlapZ = contactSizeZ - math.abs(dz)
                    local sameValue = a.value == b.value
                    local collisionProtected = a.mergeCollisionProtected or b.mergeCollisionProtected
                    local mergeContact = sameValue and not collisionProtected
                        and BlocksWithinMergeContact(a, b, extentA, extentB)
                    if mergeContact and a.cooldown <= 0 and b.cooldown <= 0 then
                        pairs[#pairs + 1] = { a, b }
                        merged[a.id] = true
                        merged[b.id] = true
                    elseif not collisionProtected and overlapX > 0 and overlapZ > 0
                        and math.abs(a.y - b.y) <= contactSizeY * 0.9 then
                        local massA, massB = a.mass or 1, b.mass or 1
                        local totalMass = massA + massB
                        local waitingForMerge = sameValue and (a.cooldown > 0 or b.cooldown > 0)
                        local retainedMergeOverlap = WORLD.cube * 0.02
                        local impactSpeed = 0
                        local launchedPush = LaunchedPushContext(a, b)

                        if overlapX < overlapZ then
                            local sign = dx >= 0 and 1 or -1
                            impactSpeed = math.max(0, (a.vx - b.vx) * sign)
                            local separation = waitingForMerge
                                    and math.max(0, overlapX - retainedMergeOverlap)
                                or overlapX + WORLD.collisionSeparation
                            a.x = a.x - separation * massB / totalMass * sign
                            b.x = b.x + separation * massA / totalMass * sign

                            if impactSpeed > 0 then
                                local restitution = waitingForMerge and 0 or WORLD.blockRestitution
                                local impulse = (1 + restitution) * impactSpeed
                                    / (1 / massA + 1 / massB)
                                a.vx = a.vx - impulse / massA * sign
                                b.vx = b.vx + impulse / massB * sign
                                local angularImpact = Clamp((impactSpeed - 4) / 14, 0, 1) * 3.2
                                if angularImpact > 0 then
                                    a.canAirSpin, b.canAirSpin = true, true
                                    a.spinZ = a.spinZ - sign * angularImpact * massB / totalMass
                                    b.spinZ = b.spinZ + sign * angularImpact * massA / totalMass
                                    local offCenter = Clamp(dz / math.max(0.001, contactSizeZ), -1, 1)
                                    a.spinY = a.spinY + offCenter * angularImpact * 0.38
                                    b.spinY = b.spinY + offCenter * angularImpact * 0.38
                                end
                            end
                        else
                            local sign = dz >= 0 and 1 or -1
                            impactSpeed = math.max(0, (a.vz - b.vz) * sign)
                            local separation = waitingForMerge
                                    and math.max(0, overlapZ - retainedMergeOverlap)
                                or overlapZ + WORLD.collisionSeparation
                            a.z = a.z - separation * massB / totalMass * sign
                            b.z = b.z + separation * massA / totalMass * sign

                            if impactSpeed > 0 then
                                local restitution = waitingForMerge and 0 or WORLD.blockRestitution
                                local impulse = (1 + restitution) * impactSpeed
                                    / (1 / massA + 1 / massB)
                                a.vz = a.vz - impulse / massA * sign
                                b.vz = b.vz + impulse / massB * sign
                                local angularImpact = Clamp((impactSpeed - 4) / 14, 0, 1) * 3.2
                                if angularImpact > 0 then
                                    a.canAirSpin, b.canAirSpin = true, true
                                    a.spinX = a.spinX + sign * angularImpact * massB / totalMass
                                    b.spinX = b.spinX - sign * angularImpact * massA / totalMass
                                    local offCenter = Clamp(dx / math.max(0.001, contactSizeX), -1, 1)
                                    a.spinY = a.spinY - offCenter * angularImpact * 0.38
                                    b.spinY = b.spinY - offCenter * angularImpact * 0.38
                                end
                            end
                        end

                        if impactSpeed > 0 then
                            ApplyLaunchedPush(launchedPush, impactSpeed)
                            RuntimeFlow.PlayCollisionSfx(impactSpeed, a, b)
                            a.launchTrail = false
                            b.launchTrail = false
                        end
                        local impactSquash = CollisionSquashAmount(impactSpeed, massA, massB)
                        if impactSquash > 0 then
                            a.squash = math.max(a.squash or 0, impactSquash)
                            b.squash = math.max(b.squash or 0, impactSquash)
                        end
                    end
                end
            end
        end
    end
    local alive = {}
    for _, block in ipairs(blocks_) do alive[block.id] = true end
    for _, pair in ipairs(pairs) do
        local a, b = pair[1], pair[2]
        if alive[a.id] and alive[b.id] then
            alive[a.id], alive[b.id] = nil, nil
            MergeBlocks(a, b)
        end
    end
    for _, block in ipairs(blocks_) do ConstrainBlockToTray(block) end
end

function RuntimeFlow.QueueReviveClear(block, delay)
    RuntimeFlow.clearAnimations[#RuntimeFlow.clearAnimations + 1] = {
        x = block.x,
        y = block.y,
        z = block.z,
        value = block.value,
        scale = block.scale or BlockScaleForValue(block.value),
        rx = block.rx or 0,
        ry = block.ry or 0,
        rz = block.rz or 0,
        spinX = block.spinX or 0,
        spinY = block.spinY or 0,
        spinZ = block.spinZ or 0,
        age = 0,
        delay = delay,
        life = 0.28,
        burst = false,
    }
end

function RuntimeFlow.ExecuteReviveClear()
    -- 清除区域（俯视，Z 轴向红线/发射区增大）：
    -- -trayL/2 [保留的远端 50%] cutoff [清除的近红线 50%] dangerZ [全部清除]
    -- 方块先从物理系统移出，再由 clearAnimations 保留视觉快照完成爆炸动画，
    -- 避免动画期间继续碰撞、合成或重新触发危险倒计时。
    local clearCutoffZ = WORLD.dangerZ - WORLD.playBoundaryL * 0.5
    local clearedCount = 0
    RuntimeFlow.clearAnimations = {}
    for i = #blocks_, 1, -1 do
        local block = blocks_[i]
        if block.z >= clearCutoffZ then
            local distanceFromLine = math.abs(block.z - WORLD.dangerZ)
            local delay = Clamp(distanceFromLine / WORLD.playBoundaryL * 0.22, 0, 0.18)
                + math.abs(block.x) / WORLD.trayW * 0.035
            RuntimeFlow.QueueReviveClear(block, delay)
            table.remove(blocks_, i)
            clearedCount = clearedCount + 1
        else
            block.dangerTime = nil
        end
    end
    if clearedCount > 0 then
        TriggerShake(7.5, 0.22)
    end
    heavyBlock_ = nil
    dangerCountdown_ = nil
    lastDangerSecond_ = nil
    canShoot_ = true
    shootCooldown_ = 0
    launchPos_ = ClampLaunchPoint({
        x = 0,
        y = BlockSizeForValue(currentValue_) / 2,
        z = WORLD.defaultLaunchZ,
    })
    tip_ = clearedCount > 0
        and ("复活成功，已清除危险半场的 " .. clearedCount .. " 个方块")
        or "复活成功，继续合成吧"
    if musicSource_ and sounds_.bgm and audioStarted_ then musicSource_:Play(sounds_.bgm) end
    SaveGame()
    print("[Bounce4096] 复活返回后延迟0.5秒完成清场，清除方块数=" .. clearedCount
        .. ", 清除阈值Z=" .. string.format("%.3f", clearCutoffZ))
end

function RuntimeFlow.ReviveAfterReward()
    if not gameOver_ or RuntimeFlow.reviveUsed then return end

    -- 广告成功只负责立即返回游戏；目标球保持原位并暂停物理。
    -- 玩家看到棋盘 0.5 秒后，UpdateGame 再执行清除和连锁爆炸。
    RuntimeFlow.reviveUsed = true
    RuntimeFlow.pendingReviveClearRemaining = 0.5
    gameOver_ = false
    leaderboardSubmitted_ = false
    dangerCountdown_ = nil
    lastDangerSecond_ = nil
    canShoot_ = false
    shootCooldown_ = 0
    aiming_ = false
    aimStart_, aimPoint_ = nil, nil
    aimCanceling_ = false
    heavyBlock_ = nil
    tip_ = "复活成功，危险区域即将爆破"
    RuntimeFlow.restartButton = nil
    RuntimeFlow.reviveButton = nil
    RuntimeFlow.message = nil
    print("[Bounce4096] 激励广告完成，玩家已返回游戏，0.5秒后清除危险区域")
end

function RuntimeFlow.FinishRevive(requestGeneration, result)
    if requestGeneration ~= RuntimeFlow.requestGeneration or RuntimeFlow.completed then return end
    RuntimeFlow.completed = true
    RuntimeFlow.inFlight = false
    RuntimeFlow.watchdogRemaining = nil
    if result and result.success == true and gameOver_ and not RuntimeFlow.reviveUsed then
        if metaGame_ then metaGame_:ApplyMissionEvent("watch_video", 1, os.time()) end
        RuntimeFlow.ReviveAfterReward()
        return
    end
    local message = result and tostring(result.msg or "") or ""
    if message == "embed manual close" then
        RuntimeFlow.message = "需完整观看广告才能复活"
    else
        RuntimeFlow.message = "广告暂不可用，请稍后重试"
    end
    print("[Bounce4096] 激励广告未完成: " .. (message ~= "" and message or "无返回结果"))
end

function RuntimeFlow.ShowRevive()
    if not gameOver_ or RuntimeFlow.reviveUsed or RuntimeFlow.inFlight then return end
    local sdkApi = rawget(_G, "sdk")
    if not sdkApi or not sdkApi.ShowRewardVideoAd then
        RuntimeFlow.message = "当前环境暂不支持广告"
        return
    end

    RuntimeFlow.requestGeneration = RuntimeFlow.requestGeneration + 1
    local requestGeneration = RuntimeFlow.requestGeneration
    RuntimeFlow.inFlight = true
    RuntimeFlow.completed = false
    RuntimeFlow.watchdogRemaining = 45.0
    RuntimeFlow.message = "广告加载中…"
    local callbackFired = false
    local accepted = sdkApi:ShowRewardVideoAd(function(result)
        callbackFired = true
        RuntimeFlow.FinishRevive(requestGeneration, result)
    end)
    if accepted == false and not callbackFired then
        RuntimeFlow.FinishRevive(requestGeneration, { success = false, msg = "request rejected" })
    end
end

local function TryFreezeDailyBlock()
    if gameMode_ ~= "daily" or not metaGame_ then return false end
    local candidates = {}
    -- 冻结区域（俯视）：后墙 ---- [安全区候选] ---- dangerZ 红线
    -- 只冻结已稳定落地且未进入危险区的方块；发射中的重球与已冻结方块排除。
    -- 无候选时保留 pendingFreezes，等待后续方块稳定，避免五连进度被吞掉。
    for _, block in ipairs(blocks_) do
        local speed = Length2(block.vx, block.vz)
        if not block.frozen and block ~= heavyBlock_ and block.age > 0.65
            and speed < 0.8 and math.abs(block.vy) < 0.12 and block.z <= WORLD.dangerZ then
            candidates[#candidates + 1] = block
        end
    end
    if #candidates == 0 or not metaGame_:ClaimChallengeFreeze() then return false end
    table.sort(candidates, function(a, b) return a.z > b.z end)
    local block = candidates[1]
    block.frozen = true
    block.mass = 1000000000
    block.vx, block.vy, block.vz = 0, 0, 0
    block.spinX, block.spinY, block.spinZ = 0, 0, 0
    block.canAirSpin = false
    block.launchTrail = false
    tip_ = "寒冰降临：同值合成可破冰"
    TriggerShake(5.5, 0.12)
    SaveGame()
    print("[Bounce4096] 每日挑战冻结方块 id=" .. block.id .. " value=" .. block.value)
    return true
end

local function FinalizeMetaRun()
    if RuntimeFlow.metaRunSettled or not metaGame_ then return end
    RuntimeFlow.metaRunSettled = true
    metaGame_:FinishRun(score_, maxValue_, maxComboThisRun_, os.time())
    if gameMode_ == "daily" then metaGame_:ResetChallengeAttempt() end
end

local function CheckGameOver(dt)
    if gameOver_ then return end
    local shortest = nil
    for _, b in ipairs(blocks_) do
        local speed = Length2(b.vx, b.vz)
        local wasDangerous = b.dangerTime ~= nil
        if b.z <= WORLD.dangerZ then
            b.dangerTime = nil
            if wasDangerous and metaGame_ then metaGame_:RecordDangerRescue(os.time()) end
        elseif b.dangerTime == nil then
            if b.age > 1.0 and speed < 0.85 and b.y < WORLD.cube * (b.scale or 1) * 1.42 then
                b.dangerTime = DANGER_COUNTDOWN_SECONDS
            end
        else
            b.dangerTime = math.max(0, b.dangerTime - dt)
        end
        if b.dangerTime then
            shortest = shortest and math.min(shortest, b.dangerTime) or b.dangerTime
            if b.dangerTime <= 0 then
                gameOver_ = true
                dangerCountdown_ = nil
                canShoot_ = false
                aiming_ = false
                tip_ = "倒计时结束，游戏结束"
                if fileSystem then fileSystem:Delete(CurrentSaveFile()) end
                if musicSource_ then musicSource_:Stop() end
                PlaySfx("game_over", 0.7)
                TriggerShake(11, 0.24)
                local runDuration, wasShort = spawnManager_:RecordGameOver(ddaElapsed_)
                SaveDDAProfile()
                SubmitHighScore()
                print(string.format("[Bounce4096] 游戏结束，时长=%.1f秒，短局=%s", runDuration, tostring(wasShort)))
                return
            end
        end
    end
    dangerCountdown_ = shortest
    local dangerSecond = shortest and math.max(1, math.ceil(shortest)) or nil
    if dangerSecond ~= lastDangerSecond_ then
        lastDangerSecond_ = dangerSecond
        if dangerSecond then PlaySfx("danger", 0.58) end
    end
end

function RuntimeFlow.UpdatePendingReviveClear(dt)
    if not RuntimeFlow.pendingReviveClearRemaining then return false end

    RuntimeFlow.pendingReviveClearRemaining =
        RuntimeFlow.pendingReviveClearRemaining - dt
    if RuntimeFlow.pendingReviveClearRemaining <= 0 then
        RuntimeFlow.pendingReviveClearRemaining = nil
        RuntimeFlow.ExecuteReviveClear()
        return false
    end
    return true
end

function RuntimeFlow.UpdateReviveClearAnimations(dt)
    for i = #RuntimeFlow.clearAnimations, 1, -1 do
        local animation = RuntimeFlow.clearAnimations[i]
        animation.age = animation.age + dt
        if not animation.burst and animation.age >= animation.delay then
            animation.burst = true
            CreateMergeEffect(
                animation.x,
                animation.y,
                animation.z,
                animation.value,
                false,
                false,
                true
            )
        end
        if animation.age >= animation.delay + animation.life then
            table.remove(RuntimeFlow.clearAnimations, i)
        end
    end
end

local function UpdateEffects(dt)
    for i = #effects_, 1, -1 do
        local e = effects_[i]
        e.age = e.age + dt
        for _, p in ipairs(e.particles) do
            p.age = p.age + dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.z = p.z + p.vz * dt
            p.vy = p.vy - 10.5 * dt
            p.vx = p.vx * (0.985 ^ (dt * 60))
            p.vz = p.vz * (0.985 ^ (dt * 60))
        end
        if e.age >= e.life then table.remove(effects_, i) end
    end
    for i = #impacts_, 1, -1 do
        impacts_[i].age = impacts_[i].age + dt
        if impacts_[i].age >= impacts_[i].life then table.remove(impacts_, i) end
    end
end

local function PhysicsSubstepCount(dt)
    -- 高速碰撞推演（俯视图）：
    --   [A 上一子步] ---> | [B / 墙体] |   每个子步最多移动约方块宽度的 8%
    -- 目的：避免 A 在单帧内从 B 的一侧直接跨到另一侧，漏掉重叠检测。
    -- 边界：最高发射速度、斜向运动和低帧率时最多拆为 12 个子步。
    local maxSpeed = 0
    local smallestBlockSize = WORLD.cube
    for _, b in ipairs(blocks_) do
        maxSpeed = math.max(maxSpeed, Length2(b.vx, b.vz))
        smallestBlockSize = math.min(smallestBlockSize, WORLD.cube * (b.scale or 1))
    end
    return Clamp(math.ceil(maxSpeed * dt / (smallestBlockSize * 0.08)), 1, 12)
end

local function UpdateGame(dt)
    if metaCloudSaveRemaining_ then metaCloudSaveRemaining_ = math.max(0, metaCloudSaveRemaining_ - dt) end
    FlushMetaCloud(false)
    if metaUI_ then
        metaUI_:Update(dt)
        if metaUI_:IsOpen() then return end
    end
    ddaElapsed_ = ddaElapsed_ + dt
    if RuntimeFlow.watchdogRemaining then
        RuntimeFlow.watchdogRemaining = RuntimeFlow.watchdogRemaining - dt
        if RuntimeFlow.watchdogRemaining <= 0 then
            RuntimeFlow.FinishRevive(RuntimeFlow.requestGeneration, { success = false, msg = "timeout" })
        end
    end
    if nicknameRequestRemaining_ then
        nicknameRequestRemaining_ = nicknameRequestRemaining_ - dt
        if nicknameRequestRemaining_ <= 0 then
            nicknameRequestGeneration_ = nicknameRequestGeneration_ + 1
            print("[Bounce4096] 排行榜昵称请求超时")
            ScheduleNicknameRetry()
        end
    elseif nicknameRetryRemaining_ then
        nicknameRetryRemaining_ = nicknameRetryRemaining_ - dt
        if nicknameRetryRemaining_ <= 0 then
            nicknameRetryRemaining_ = nil
            ResolveLeaderboardNicknames()
        end
    end

    if shootCooldown_ > 0 then
        shootCooldown_ = math.max(0, shootCooldown_ - dt)
        if shootCooldown_ <= 0 and not gameOver_ then
            canShoot_ = true
            tip_ = "向后拖动方块发射"
        elseif not gameOver_ then
            tip_ = string.format("下一枚方块准备中 %.1f秒", shootCooldown_)
        end
    end

    local timeScale = mergeSlowTime_ > 0 and 0.55 or 1
    local simulationDt = dt * timeScale
    mergeSlowTime_ = math.max(0, mergeSlowTime_ - dt)
    RuntimeFlow.UpdateComboWindow(dt)

    local reviveClearPending = RuntimeFlow.UpdatePendingReviveClear(dt)
    if reviveClearPending then
        -- 返回游戏后的 0.5 秒展示原棋盘，不推进方块物理。
    elseif not gameOver_ then
        TryFreezeDailyBlock()
        local substeps = PhysicsSubstepCount(simulationDt)
        local stepDt = simulationDt / substeps
        for _ = 1, substeps do
            ApplySameValueAttraction(stepDt)
            UpdateBlocks(stepDt)
            -- 碰撞区域：每个方块使用旋转后的可见 AABB；先分离重叠，再触发同值合成。
            -- 低方块数保留第二次松弛，堆积变多时只做一次，避免 O(n²) 求解拖慢整帧。
            local collisionPasses = #blocks_ <= 12 and 2 or 1
            for _ = 1, collisionPasses do ResolveBlockCollisions() end
            CheckGameOver(stepDt)
            if gameOver_ then break end
        end
    else
        UpdateBlocks(simulationDt * 0.2)
    end
    RuntimeFlow.UpdateReviveClearAnimations(dt)
    UpdateEffects(simulationDt)
    if shakeTime_ > 0 then
        shakeTime_ = math.max(0, shakeTime_ - dt)
        shakePower_ = shakePower_ * (0.9 ^ (dt * 60))
    else
        shakePower_ = 0
    end
end

local function EaseOutBack(t)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function VividComicColor(color, saturationBoost, brightness)
    local gray = color[1] * 0.299 + color[2] * 0.587 + color[3] * 0.114
    local factor = 1 + saturationBoost
    return {
        Clamp(math.floor((gray + (color[1] - gray) * factor) * brightness + 0.5), 0, 255),
        Clamp(math.floor((gray + (color[2] - gray) * factor) * brightness + 0.5), 0, 255),
        Clamp(math.floor((gray + (color[3] - gray) * factor) * brightness + 0.5), 0, 255),
        255,
    }
end

local function BurstNoise(seed, index)
    local value = math.sin(seed * 0.0137 + index * 78.233) * 43758.5453
    return value - math.floor(value)
end

local function DrawStarburstPath(cx, cy, points, innerRadius, outerRadius, rotation, seed)
    nvgBeginPath(vg_)
    for i = 0, points * 2 - 1 do
        local radiusNoise = 0.82 + BurstNoise(seed, i) * 0.34
        local radius = (i % 2 == 0 and outerRadius or innerRadius) * radiusNoise
        local angle = rotation + i / (points * 2) * math.pi * 2
        local x, y = cx + math.cos(angle) * radius, cy + math.sin(angle) * radius
        if i == 0 then nvgMoveTo(vg_, x, y) else nvgLineTo(vg_, x, y) end
    end
    nvgClosePath(vg_)
end

local function DrawRetroZigzag(x, y, radius, rotation, lengthScale, seed, alpha, color)
    nvgSave(vg_)
    nvgTranslate(vg_, x, y)
    nvgRotate(vg_, rotation)
    nvgGlobalAlpha(vg_, alpha)
    nvgLineCap(vg_, NVG_ROUND)
    nvgLineJoin(vg_, NVG_ROUND)
    nvgBeginPath(vg_)
    local startX = radius * (0.18 + BurstNoise(seed, 21) * 0.16)
    nvgMoveTo(vg_, startX, -radius * 0.12)
    nvgLineTo(vg_, radius * 0.55, -radius * 0.36)
    nvgLineTo(vg_, radius * 0.43, radius * 0.02)
    nvgLineTo(vg_, radius * lengthScale, radius * 0.27)
    nvgStrokeColor(vg_, Color(color))
    nvgStrokeWidth(vg_, math.max(5, radius * 0.045))
    nvgStroke(vg_)
    nvgRestore(vg_)
end

local function DrawComicGeometryCluster(width, height, rotation, seed, level, mergeColor)
    local mergeLight = MixColor(mergeColor, COMIC.cream, 0.24)
    local mergeDark = MixColor(mergeColor, COMIC.ink, 0.32)
    local colors = { mergeColor, mergeLight, COMIC.cream, mergeDark, COMIC.yellow }
    local shortSide = math.min(width, height)
    local shapeCount = 8 + math.min(4, math.floor(level / 3))
    for i = 0, shapeCount - 1 do
        local x = width * (0.04 + BurstNoise(seed, 330 + i) * 0.92)
        local y = height * (0.04 + BurstNoise(seed, 360 + i) * 0.92)
        local size = shortSide * (0.025 + BurstNoise(seed, 390 + i) * 0.055)
        local color = colors[(i + math.floor(level)) % #colors + 1]
        local angle = rotation + BurstNoise(seed, 420 + i) * math.pi * 2
        nvgSave(vg_)
        nvgTranslate(vg_, x, y)
        nvgRotate(vg_, angle)
        nvgLineCap(vg_, NVG_ROUND)
        nvgLineJoin(vg_, NVG_ROUND)
        local variant = i % 5
        if variant == 0 then
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, 0, -size)
            nvgLineTo(vg_, size * 0.88, size * 0.72)
            nvgLineTo(vg_, -size * 0.88, size * 0.72)
            nvgClosePath(vg_)
            nvgFillColor(vg_, Color(color))
            nvgFill(vg_)
        elseif variant == 1 then
            nvgBeginPath(vg_)
            nvgCircle(vg_, 0, 0, size * 0.72)
            nvgStrokeColor(vg_, Color(color))
            nvgStrokeWidth(vg_, math.max(3, size * 0.22))
            nvgStroke(vg_)
        elseif variant == 2 then
            nvgBeginPath(vg_)
            nvgRect(vg_, -size * 1.25, -size * 0.25, size * 2.5, size * 0.5)
            nvgFillColor(vg_, Color(color))
            nvgFill(vg_)
        elseif variant == 3 then
            nvgBeginPath(vg_)
            nvgCircle(vg_, -size * 0.3, 0, size * 0.62)
            nvgFillColor(vg_, Color(color))
            nvgFill(vg_)
            nvgBeginPath(vg_)
            nvgCircle(vg_, size * 0.38, 0, size * 0.48)
            nvgFillColor(vg_, Color(colors[(i + math.floor(level) + 2) % #colors + 1]))
            nvgFill(vg_)
        else
            nvgBeginPath(vg_)
            nvgRect(vg_, -size * 0.82, -size * 0.82, size * 1.64, size * 1.64)
            nvgStrokeColor(vg_, Color(color))
            nvgStrokeWidth(vg_, math.max(3, size * 0.22))
            nvgStroke(vg_)
        end
        nvgRestore(vg_)
    end
end

local function DrawMergeBackgroundImpact()
    for impactIndex, impact in ipairs(impacts_) do
        local t = Clamp(impact.age / impact.life, 0, 1)
        local intro = Clamp(t / 0.16, 0, 1)
        local opacity = 0.96 * ((1 - t) ^ 0.48)
        local pop = 0.18 + EaseOutBack(intro) * 0.82
        local shortSide = math.min(logicalW_, logicalH_)
        local radius = shortSide * (0.3 + math.min(impact.level * 0.012, 0.14)) * impact.power
        local points = math.min(28, 12 + math.floor(impact.level * 1.15))
        local rotation = impact.rotation + t * (impactIndex % 2 == 1 and 0.18 or -0.18)
        local seed = impact.seed
        local mergeColor = VividComicColor(impact.color, 0.32, 1.18)
        local mergeLight = MixColor(mergeColor, COMIC.cream, 0.24)
        local mergeDark = MixColor(mergeColor, COMIC.ink, 0.32)
        local leftX = logicalW_ * (0.03 + BurstNoise(seed, 12) * 0.18)
        local leftY = logicalH_ * (0.18 + BurstNoise(seed, 13) * 0.58)
        local rightX = logicalW_ * (0.78 + BurstNoise(seed, 14) * 0.2)
        local rightY = logicalH_ * (0.12 + BurstNoise(seed, 15) * 0.68)
        local centerX = logicalW_ * (0.3 + BurstNoise(seed, 16) * 0.4)
        local centerY = logicalH_ * (0.25 + BurstNoise(seed, 17) * 0.5)

        nvgSave(vg_)
        nvgGlobalAlpha(vg_, opacity)
        nvgTranslate(vg_, logicalW_ / 2, logicalH_ / 2)
        nvgScale(vg_, pop, pop)
        nvgTranslate(vg_, -logicalW_ / 2, -logicalH_ / 2)

        nvgSave(vg_)
        nvgTranslate(vg_, centerX, centerY)
        nvgRotate(vg_, rotation * 0.45)
        nvgBeginPath(vg_)
        nvgRect(vg_, -logicalW_ * 0.38, -radius * 0.24, logicalW_ * 0.76, radius * 0.48)
        nvgFillColor(vg_, Color(mergeColor))
        nvgFill(vg_)
        nvgRestore(vg_)

        nvgBeginPath(vg_)
        nvgCircle(vg_, rightX, rightY, radius * 0.52)
        nvgFillColor(vg_, Color(mergeLight))
        nvgFill(vg_)

        DrawStarburstPath(leftX, leftY, points, radius * 0.38, radius, rotation, seed)
        nvgFillColor(vg_, Color(COMIC.cream))
        nvgFill(vg_)
        DrawStarburstPath(rightX, logicalH_ - rightY * 0.55, math.max(9, points - 5), radius * 0.23, radius * 0.72, -rotation * 0.72, seed + 83)
        nvgFillColor(vg_, Color(impact.level >= 10 and mergeLight or mergeColor))
        nvgFill(vg_)

        DrawRetroZigzag(logicalW_ * 0.12, logicalH_ * 0.12, radius, -0.62 + rotation, 1.03, seed, 0.96, mergeColor)
        DrawRetroZigzag(logicalW_ * 0.58, logicalH_ * 0.64, radius, 2.3 + rotation, 0.82, seed + 17, 0.78, COMIC.cream)
        if impact.level >= 8 then
            DrawRetroZigzag(logicalW_ * 0.32, logicalH_ * 0.86, radius, 0.82 - rotation, 0.7, seed + 31, 0.68, mergeLight)
        end

        DrawComicGeometryCluster(logicalW_, logicalH_, rotation, seed, impact.level, mergeColor)

        local dotColors = { mergeDark, mergeColor, COMIC.cream, mergeLight, COMIC.yellow }
        local dotCount = 7 + math.min(5, math.floor(impact.level / 3))
        for i = 1, dotCount do
            local x = logicalW_ * BurstNoise(seed, 99 + i)
            local y = logicalH_ * BurstNoise(seed, 129 + i)
            local dotRadius = shortSide * (0.012 + BurstNoise(seed, 159 + i) * 0.035)
            nvgBeginPath(vg_)
            nvgCircle(vg_, x, y, dotRadius)
            nvgFillColor(vg_, Color(dotColors[(i + math.floor(impact.level)) % #dotColors + 1]))
            nvgFill(vg_)
        end
        nvgBeginPath(vg_)
        nvgCircle(vg_, centerX, centerY, radius * 0.12)
        nvgFillColor(vg_, Color(mergeDark))
        nvgFill(vg_)

        nvgGlobalAlpha(vg_, opacity * 0.28)
        local grainCount = 12 + math.min(12, math.floor(impact.level))
        for i = 0, grainCount - 1 do
            local x = logicalW_ * BurstNoise(seed, 210 + i)
            local y = logicalH_ * BurstNoise(seed, 250 + i)
            local grainRadius = 0.7 + BurstNoise(seed, 290 + i) * 1.7
            nvgBeginPath(vg_)
            nvgCircle(vg_, x, y, grainRadius)
            nvgFillColor(vg_, Color(i % 3 == 0 and mergeDark or mergeColor))
            nvgFill(vg_)
        end
        nvgRestore(vg_)
    end
end

local function DrawDoodleMark(x, y, size, color, rotation, variant)
    nvgSave(vg_)
    nvgTranslate(vg_, x, y)
    nvgRotate(vg_, rotation)
    nvgLineCap(vg_, NVG_ROUND)
    nvgLineJoin(vg_, NVG_ROUND)
    nvgBeginPath(vg_)
    if variant == 0 then
        nvgCircle(vg_, 0, 0, size * 0.38)
    elseif variant == 1 then
        nvgMoveTo(vg_, 0, -size * 0.45)
        nvgLineTo(vg_, size * 0.42, size * 0.34)
        nvgLineTo(vg_, -size * 0.42, size * 0.34)
        nvgClosePath(vg_)
    elseif variant == 2 then
        nvgRect(vg_, -size * 0.36, -size * 0.36, size * 0.72, size * 0.72)
    elseif variant == 3 then
        nvgMoveTo(vg_, 0, -size * 0.44)
        nvgLineTo(vg_, size * 0.4, 0)
        nvgLineTo(vg_, 0, size * 0.44)
        nvgLineTo(vg_, -size * 0.4, 0)
        nvgClosePath(vg_)
    elseif variant == 4 then
        nvgMoveTo(vg_, -size * 0.32, 0)
        nvgLineTo(vg_, size * 0.32, 0)
    elseif variant == 5 then
        nvgMoveTo(vg_, -size * 0.45, -size * 0.12)
        nvgBezierTo(vg_, -size * 0.26, -size * 0.42, -size * 0.12, size * 0.18, 0, 0)
        nvgBezierTo(vg_, size * 0.14, -size * 0.2, size * 0.26, size * 0.42, size * 0.45, size * 0.12)
    elseif variant == 6 then
        nvgCircle(vg_, 0, 0, size * 0.2)
        nvgFillColor(vg_, Color(color))
        nvgFill(vg_)
        nvgRestore(vg_)
        return
    else
        nvgMoveTo(vg_, -size * 0.3, 0)
        nvgLineTo(vg_, size * 0.3, 0)
        nvgMoveTo(vg_, 0, -size * 0.3)
        nvgLineTo(vg_, 0, size * 0.3)
    end
    nvgStrokeColor(vg_, Color(color))
    nvgStrokeWidth(vg_, math.max(2.2, size * 0.07))
    nvgStroke(vg_)
    nvgRestore(vg_)
end

local function DrawBackground()
    local time = os.clock()
    local cell = Clamp(math.min(logicalW_, logicalH_) * 0.16, 58, 76)
    local travelX, travelY = time * 7, time * 3.8
    local baseColumn, baseRow = math.floor(travelX / cell), math.floor(travelY / cell)
    local driftX, driftY = travelX - baseColumn * cell, travelY - baseRow * cell
    local columns = math.ceil(logicalW_ / cell) + 3
    local rows = math.ceil(logicalH_ / cell) + 3
    local mergePatternBoost = 0
    for _, impact in ipairs(impacts_) do
        local pulseT = Clamp(impact.age / 0.32, 0, 1)
        local attack = Clamp(pulseT / 0.12, 0, 1)
        local decay = (1 - pulseT) ^ 1.35
        local levelStrength = Clamp(0.62 + impact.level * 0.045, 0.72, 1.02)
        mergePatternBoost = math.max(mergePatternBoost, attack * decay * levelStrength * impact.power)
    end

    local backgroundColor = BACKGROUND_BLUE
    local themeCosmetic = metaGame_ and metaGame_:Equipped("theme") or nil
    if gameMode_ == "daily" then
        backgroundColor = { 35, 112, 142, 255 }
    elseif themeCosmetic and themeCosmetic.effect == "mint" then
        backgroundColor = { 49, 151, 137, 255 }
    elseif themeCosmetic and themeCosmetic.effect == "tomato" then
        backgroundColor = { 190, 73, 55, 255 }
    end
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, logicalW_, logicalH_)
    nvgFillColor(vg_, Color(backgroundColor))
    nvgFill(vg_)

    nvgSave(vg_)
    for row = -2, rows - 1 do
        for column = -2, columns - 1 do
            local logicalRow = row - baseRow
            local logicalColumn = column - baseColumn
            local seed = math.abs(logicalRow * 47 + logicalColumn * 83)
            local phase = seed * 0.37
            local x = column * cell + (logicalRow % 2) * cell * 0.5 + driftX
            local y = row * cell + driftY
            local floatX = math.sin(time * 0.38 + phase) * 2.2
            local floatY = math.cos(time * 0.32 + phase) * 2.2
            local pulse = 1 + math.sin(time * 0.7 + phase) * 0.045
            local size = cell * (0.23 + seed % 4 * 0.05) * pulse * (1 + mergePatternBoost)
            local rotation = (seed % 7 - 3) * 0.16 + math.sin(time * 0.2 + phase) * 0.055
            local color = DOODLE_COLORS[seed % #DOODLE_COLORS + 1]
            nvgGlobalAlpha(vg_, math.min(1, 0.72 + seed % 3 * 0.08 + mergePatternBoost * 0.12))
            DrawDoodleMark(x + floatX, y + floatY, size, color, rotation, seed % 8)
            if seed % 3 == 0 then
                nvgGlobalAlpha(vg_, 0.72)
                nvgBeginPath(vg_)
                nvgCircle(vg_, x + cell * 0.34, y - cell * 0.28, 1.7 + seed % 2)
                nvgFillColor(vg_, Color(DOODLE_COLORS[(seed + 1) % #DOODLE_COLORS + 1]))
                nvgFill(vg_)
            end
        end
    end
    nvgRestore(vg_)
    DrawMergeBackgroundImpact()
end

RuntimeFlow.BilliardStyles = {
    [1] = { pattern = "solid" },
    [2] = { pattern = "solid" },
    [3] = { pattern = "solid" },
    [4] = { pattern = "solid" },
    [5] = { pattern = "solid" },
    [6] = { pattern = "solid" },
    [7] = { pattern = "solid" },
    [8] = { pattern = "solid" },
    [9] = { pattern = "stripe" },
    [10] = { pattern = "stripe" },
    [11] = { pattern = "stripe" },
    [12] = { pattern = "stripe" },
    [13] = { pattern = "stripe" },
    [14] = { pattern = "stripe" },
    [15] = { pattern = "stripe" },
    [16] = { pattern = "double" },
    [17] = { pattern = "double" },
}

function RuntimeFlow.BilliardNumber(value)
    return Clamp(math.floor(math.log(math.max(2, value or 2), 2) + 0.5), 1, 17)
end

function RuntimeFlow.DrawSphereBand(centerX, centerY, radius, angle, offset, halfThickness, color)
    local upper = offset - halfThickness
    local lower = offset + halfThickness
    local samples = 28

    nvgSave(vg_)
    nvgTranslate(vg_, centerX, centerY)
    nvgRotate(vg_, angle)
    nvgBeginPath(vg_)
    local started = false
    for i = 0, samples do
        local x = -radius + radius * 2 * i / samples
        local circleY = math.sqrt(math.max(0, radius * radius - x * x))
        local y = math.max(-circleY, upper)
        if y <= math.min(circleY, lower) then
            if started then nvgLineTo(vg_, x, y) else nvgMoveTo(vg_, x, y); started = true end
        end
    end
    if not started then nvgRestore(vg_); return end
    for i = samples, 0, -1 do
        local x = -radius + radius * 2 * i / samples
        local circleY = math.sqrt(math.max(0, radius * radius - x * x))
        local y = math.min(circleY, lower)
        if math.max(-circleY, upper) <= y then nvgLineTo(vg_, x, y) end
    end
    nvgClosePath(vg_)
    nvgFillColor(vg_, Color(color))
    nvgFill(vg_)
    nvgRestore(vg_)
end

function RuntimeFlow.BallSurfaceNormal(center, rotation)
    local rot = rotation or { x = 0, y = 0, z = 0 }
    -- 初始号码朝向相机；之后把累计物理旋转应用到贴花法线。
    local toCamera = Norm(Sub(camera_.pos, center))
    local normal = RotatePoint(toCamera, rot.x or 0, rot.y or 0, rot.z or 0)
    -- 台球两侧各有同号贴花；背面转来时切换到对侧贴花，避免号码无故消失。
    if Dot(normal, toCamera) < 0 then normal = Scale(normal, -1) end
    return normal, toCamera
end

function RuntimeFlow.DrawBilliardNumberDecal(center, worldRadius, rotation, number)
    local rot = rotation or { x = 0, y = 0, z = 0 }
    local normal, toCamera = RuntimeFlow.BallSurfaceNormal(center, rot)
    local facing = Clamp(Dot(normal, toCamera), 0, 1)
    local capSin = number >= 10 and 0.62 or 0.58

    local tangentRight = RotatePoint(camera_.right, rot.x or 0, rot.y or 0, rot.z or 0)
    tangentRight = Norm(Sub(tangentRight, Scale(normal, Dot(tangentRight, normal))))
    local tangentUp = Norm(Cross(normal, tangentRight))
    local capCos = math.sqrt(math.max(0, 1 - capSin * capSin))
    local surfaceRadius = worldRadius * 1.006
    local projectedCenter = Project(Add(center, Scale(normal, surfaceRadius)))
    if not projectedCenter then return end

    -- 在真实三维球面上采样圆牌边缘，而不是在屏幕上画一个平面椭圆。
    nvgBeginPath(vg_)
    local samples = 40
    for i = 0, samples do
        local angle = i / samples * math.pi * 2
        local direction = Add(Scale(normal, capCos), Add(
            Scale(tangentRight, math.cos(angle) * capSin),
            Scale(tangentUp, math.sin(angle) * capSin)
        ))
        local point = Project(Add(center, Scale(direction, surfaceRadius)))
        if not point then return end
        if i == 0 then nvgMoveTo(vg_, point.x, point.y) else nvgLineTo(vg_, point.x, point.y) end
    end
    nvgClosePath(vg_)
    nvgFillColor(vg_, Color(PALETTE.cream))
    nvgFill(vg_)
    nvgStrokeColor(vg_, nvgRGBA(0, 79, 166, 46))
    nvgStrokeWidth(vg_, 1.2)
    nvgStroke(vg_)

    -- 用同一球面贴花的切线方向投影文字，使文字与圆牌共同倾斜、缩短和滚动。
    local textAngle = math.asin(capSin) * 0.7
    local textSin, textCos = math.sin(textAngle), math.cos(textAngle)
    local rightDirection = Add(Scale(normal, textCos), Scale(tangentRight, textSin))
    local downDirection = Add(Scale(normal, textCos), Scale(tangentUp, -textSin))
    local projectedRight = Project(Add(center, Scale(rightDirection, surfaceRadius)))
    local projectedDown = Project(Add(center, Scale(downDirection, surfaceRadius)))
    if not projectedRight or not projectedDown then return end

    local axisX = {
        x = projectedRight.x - projectedCenter.x,
        y = projectedRight.y - projectedCenter.y,
    }
    local axisY = {
        x = projectedDown.x - projectedCenter.x,
        y = projectedDown.y - projectedCenter.y,
    }
    local widthScale = number >= 10 and 1.05 or 1.28
    SelectNumberFont()
    -- 保持白色球面贴花面积不变，只调整其中号码大小。
    nvgFontSize(vg_, 150)
    nvgSave(vg_)
    nvgTransform(vg_,
        axisX.x * widthScale / 100, axisX.y * widthScale / 100,
        axisY.x * 1.2 / 100, axisY.y * 1.2 / 100,
        projectedCenter.x, projectedCenter.y)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, Color(RETRO.ink))
    nvgText(vg_, 0, 4, tostring(number), nil)
    nvgRestore(vg_)
end

function RuntimeFlow.DrawBilliardBall(center, diameter, rotation, value, alpha, showNumber, _showShadow)
    local projected = Project(center)
    if not projected then return end
    local radius = math.max(2, diameter * projected.scale * 0.5)
    local number = RuntimeFlow.BilliardNumber(value)
    local style = RuntimeFlow.BilliardStyles[number] or RuntimeFlow.BilliardStyles[17]
    -- 与原方块完全共用同一数值色表和回退色，不再单独维护台球配色。
    local mainColor = ValueColor(value)
    local rot = rotation or { x = 0, y = 0, z = 0 }
    local rollPhase = rot.x or 0
    local bandAngle = (rot.z or 0) + (rot.y or 0) * 0.42
    local bandOffset = math.sin(rollPhase) * radius * 0.5
    local bandDepth = 0.68 + math.abs(math.cos(rollPhase)) * 0.32

    nvgSave(vg_)
    nvgGlobalAlpha(vg_, alpha or 1)

    -- 原方块同款纯色填充：无渐变、无高光、无环境阴影、无投影。
    nvgBeginPath(vg_)
    nvgCircle(vg_, projected.x, projected.y, radius)
    nvgFillColor(vg_, Color(mainColor))
    nvgFill(vg_)

    -- 花纹也只用主题纯色，保留 9–17 号的辨识度与滚动反馈。
    if style.pattern == "stripe" then
        RuntimeFlow.DrawSphereBand(projected.x, projected.y, radius * 0.985, bandAngle,
            bandOffset, radius * 0.32 * bandDepth, PALETTE.cream)
    elseif style.pattern == "double" then
        local spacing = radius * (0.25 + math.abs(math.cos(rollPhase)) * 0.06)
        RuntimeFlow.DrawSphereBand(projected.x, projected.y, radius * 0.985, bandAngle,
            bandOffset - spacing, radius * 0.09 * bandDepth, PALETTE.cream)
        RuntimeFlow.DrawSphereBand(projected.x, projected.y, radius * 0.985, bandAngle,
            bandOffset + spacing, radius * 0.09 * bandDepth, PALETTE.cream)
    end

    -- 与原方块 Polygon 相同的低透明蓝色轮廓。
    nvgBeginPath(vg_)
    nvgCircle(vg_, projected.x, projected.y, radius)
    nvgStrokeColor(vg_, nvgRGBA(0, 79, 166, 46))
    nvgStrokeWidth(vg_, 1.2)
    nvgStroke(vg_)

    if showNumber ~= false then
        RuntimeFlow.DrawBilliardNumberDecal(center, diameter * 0.5, rot, number)
    end

    nvgRestore(vg_)
end

local function DrawBlockAfterimages(block)
    local count = #block.afterimages
    if count == 0 then return end
    local trailColor = ValueColor(block.value)

    nvgSave(vg_)
    nvgLineJoin(vg_, NVG_ROUND)

    -- 将相邻采样点连接成无缝梯形带片，宽度从球后方连续收束到尾端。
    -- 相比逐段圆头描边，不会出现一串半透明圆珠。
    for i = 1, count - 1 do
        local from = block.afterimages[i]
        local to = block.afterimages[i + 1]
        local fromLife = Clamp(1 - from.age / from.life, 0, 1)
        local toLife = Clamp(1 - to.age / to.life, 0, 1)
        local fromOrder = count > 1 and (i - 1) / (count - 1) or 1
        local toOrder = count > 1 and i / (count - 1) or 1
        local a = Project(V3(from.x, from.y, from.z))
        local b = Project(V3(to.x, to.y, to.z))
        if a and b and fromLife > 0 and toLife > 0 then
            local dx, dy = b.x - a.x, b.y - a.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0.001 then
                local px, py = -dy / length, dx / length
                local fromTaper = 0.06 + fromOrder * 0.94
                local toTaper = 0.06 + toOrder * 0.94
                local fromWidth = from.width * a.scale * fromTaper * fromLife
                local toWidth = to.width * b.scale * toTaper * toLife
                local alpha = math.floor(150 * math.min(fromLife, toLife) ^ 1.5)
                local overlapX, overlapY = dx / length * 0.75, dy / length * 0.75

                nvgBeginPath(vg_)
                nvgMoveTo(vg_, a.x - overlapX + px * fromWidth * 0.5,
                    a.y - overlapY + py * fromWidth * 0.5)
                nvgLineTo(vg_, b.x + overlapX + px * toWidth * 0.5,
                    b.y + overlapY + py * toWidth * 0.5)
                nvgLineTo(vg_, b.x + overlapX - px * toWidth * 0.5,
                    b.y + overlapY - py * toWidth * 0.5)
                nvgLineTo(vg_, a.x - overlapX - px * fromWidth * 0.5,
                    a.y - overlapY - py * fromWidth * 0.5)
                nvgClosePath(vg_)
                nvgFillColor(vg_, Color(trailColor, alpha))
                nvgFill(vg_)
            end
        end
    end

    -- 只在轨迹最旧端补一个小圆头。
    local oldest = block.afterimages[1]
    local oldestLife = Clamp(1 - oldest.age / oldest.life, 0, 1)
    local oldestPoint = Project(V3(oldest.x, oldest.y, oldest.z))
    if oldestPoint and oldestLife > 0 then
        local tipWidth = oldest.width * oldestPoint.scale * 0.06 * oldestLife
        nvgBeginPath(vg_)
        nvgCircle(vg_, oldestPoint.x, oldestPoint.y, math.max(0.8, tipWidth * 0.5))
        nvgFillColor(vg_, Color(trailColor, math.floor(90 * oldestLife ^ 1.5)))
        nvgFill(vg_)
    end

    -- 最新采样点到当前球心补齐轨迹，避免球后方留下可见断口。
    local latest = block.afterimages[count]
    local latestLife = Clamp(1 - latest.age / latest.life, 0, 1)
    local a = Project(V3(latest.x, latest.y, latest.z))
    local b = Project(V3(block.x, block.y, block.z))
    if block.launchTrail and a and b and latestLife > 0 then
        local dx, dy = b.x - a.x, b.y - a.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.001 then
            local px, py = -dy / length, dx / length
            local widthA = latest.width * a.scale * latestLife
            local widthB = latest.width * b.scale
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, a.x + px * widthA * 0.5, a.y + py * widthA * 0.5)
            nvgLineTo(vg_, b.x + px * widthB * 0.5, b.y + py * widthB * 0.5)
            nvgLineTo(vg_, b.x - px * widthB * 0.5, b.y - py * widthB * 0.5)
            nvgLineTo(vg_, a.x - px * widthA * 0.5, a.y - py * widthA * 0.5)
            nvgClosePath(vg_)
            nvgFillColor(vg_, Color(trailColor, math.floor(150 * latestLife ^ 1.5)))
            nvgFill(vg_)
        end
    end
    nvgRestore(vg_)
end

function RuntimeFlow.DrawBlockAfterimages(block)
    local trailCosmetic = metaGame_ and metaGame_:Equipped("trail") or nil
    local trailColor = trailCosmetic and trailCosmetic.color or ValueColor(block.value)
    for _, ghost in ipairs(block.afterimages) do
        local life = Clamp(1 - ghost.age / ghost.life, 0, 1)
        if life > 0 then
            local size = WORLD.cube * ghost.scale * (0.9 + life * 0.08)
            local height = size * (ghost.deformY or 1)
            local groundSupport = CubeSupportHeightAt(
                ghost.rx,
                ghost.ry,
                ghost.rz,
                ghost.scale
            )
            local visualY = ghost.y <= groundSupport + 0.08
                    and ghost.y + (height - size) / 2
                or ghost.y
            DrawCuboid(
                V3(ghost.x, visualY, ghost.z),
                size * (ghost.deformX or 1),
                height,
                size * (ghost.deformZ or 1),
                { x = ghost.rx, y = ghost.ry, z = ghost.rz },
                trailColor,
                (life ^ 1.55) * 0.5,
                nil,
                false,
                true
            )
        end
    end
end

local function DrawBlock(block)
    local deformation = GetBlockDeformation(block)
    local size = WORLD.cube * block.scale
    local sizeX, sizeY, sizeZ = size * deformation.x, size * deformation.y, size * deformation.z
    local visualY = block.y <= CubeGroundSupportHeight(block) + 0.08 and block.y + (sizeY - size) / 2 or block.y
    local alpha = 1.0
    if block.dangerTime then
        alpha = math.floor(os.clock() * 8) % 2 == 0 and 1.0 or 0.12
    end
    DrawCuboid(
        V3(block.x, visualY, block.z),
        sizeX,
        sizeY,
        sizeZ,
        { x = block.rx, y = block.ry, z = block.rz },
        ValueColor(block.value),
        alpha,
        block.value,
        true
    )
    if block.frozen then
        local iceSize = size * 1.08
        DrawCuboid(
            V3(block.x, visualY, block.z), iceSize, iceSize, iceSize,
            { x = block.rx, y = block.ry, z = block.rz },
            { 126, 220, 255, 255 }, 0.34, nil, false, true
        )
    end
end

function RuntimeFlow.DrawReviveClearAnimations()
    for _, animation in ipairs(RuntimeFlow.clearAnimations) do
        local activeAge = math.max(0, animation.age - animation.delay)
        local t = Clamp(activeAge / animation.life, 0, 1)
        local burstT = Clamp(t / 0.34, 0, 1)
        local swell = 1 + math.sin(burstT * math.pi) * 0.2
        local collapse = t < 0.32 and 1 or Clamp(1 - (t - 0.32) / 0.24, 0, 1)
        local jitter = math.sin(activeAge * 92 + animation.x * 4.3) * 0.045 * (1 - t)
        local diameter = WORLD.cube * animation.scale * swell * collapse
        local alpha = Clamp(1 - math.max(0, t - 0.28) / 0.22, 0, 1)
        if alpha > 0 and diameter > 0.01 then
            local deformation = GetBlockDeformation(animation)
            DrawCuboid(
                V3(animation.x + jitter, animation.y, animation.z - jitter * 0.6),
                diameter * deformation.x,
                diameter * deformation.y,
                diameter * deformation.z,
                {
                    x = animation.rx + animation.spinX * activeAge + t * 3.6,
                    y = animation.ry + animation.spinY * activeAge + t * 4.8,
                    z = animation.rz + animation.spinZ * activeAge
                        + (animation.x >= 0 and 1 or -1) * t * 3.2,
                },
                ValueColor(animation.value),
                alpha,
                animation.value,
                true
            )
        end
    end
end

local function DrawPreview()
    if gameOver_ or not canShoot_ or not launchPos_ then return end
    local p = aiming_ and aimStart_ or launchPos_
    if not p then return end
    local breathe = 1 + math.sin(os.clock() * 5) * 0.025
    local rotation = { x = 0, y = 0, z = 0 }
    if aiming_ and aimStart_ and aimPoint_ and not aimCanceling_ then
        local dragX = aimStart_.x - aimPoint_.x
        local dragZ = aimStart_.z - aimPoint_.z
        local dist = Length2(dragX, dragZ)
        local power = RuntimeFlow.LaunchPower(dist)
        if dist > 0.001 then
            rotation.x = -dragZ / dist * power * 0.22
            rotation.z = dragX / dist * power * 0.22
        end
    end
    local baseSize = BlockSizeForValue(currentValue_)
    local previewSize = baseSize * breathe
    DrawCuboid(
        V3(p.x, p.y + (previewSize - baseSize) / 2, p.z),
        previewSize,
        previewSize,
        previewSize,
        rotation,
        ValueColor(currentValue_),
        1,
        currentValue_,
        true
    )
end

local function DrawAim()
    if not aiming_ or not aimStart_ or not aimPoint_ or aimCanceling_ then return end
    local dx = aimStart_.x - aimPoint_.x
    local dz = aimStart_.z - aimPoint_.z
    local dist = Length2(dx, dz)
    local strength = RuntimeFlow.DragStrength(dist)
    if dist > 0.05 then
        local dirX, dirZ = dx / dist, dz / dist
        local a = Project(V3(aimStart_.x, 0.22, aimStart_.z))
        local guideLength = WORLD.aimGuideBase + strength * WORLD.aimGuideExtra
        local b = Project(V3(aimStart_.x + dirX * guideLength, 0.22, aimStart_.z + dirZ * guideLength))
        if a and b then
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, a.x, a.y)
            nvgLineTo(vg_, b.x, b.y)
            nvgStrokeColor(vg_, Color(RETRO.cream, 245))
            nvgStrokeWidth(vg_, 4)
            nvgStroke(vg_)
            nvgBeginPath(vg_)
            nvgCircle(vg_, b.x, b.y, 7)
            nvgFillColor(vg_, Color(RETRO.mint))
            nvgFill(vg_)
        end
    end
    local barW = math.min(190, logicalW_ * 0.52)
    local barX = (logicalW_ - barW) / 2
    local barY = logicalH_ - 67
    DrawRoundRect(barX, barY, barW, 9, 6, RETRO.cream, 0.35)
    DrawRoundRect(barX, barY, barW * strength, 9, 6, RETRO.mint, 1)
end

local function DrawScoreVfx(effect, point, t)
    local level = effect.level or math.log(effect.value, 2)
    local coolness = Clamp((level - 2) / 11, 0, 1)
    local fade = t < 0.58 and 1 or Clamp(1 - (t - 0.58) / 0.42, 0, 1)
    local intro = Clamp(t / 0.2, 0, 1)
    local pop = t < 0.2 and (0.24 + EaseOutBack(intro) * 0.76)
        or (1 + math.sin((t - 0.2) * 21) * math.exp(-(t - 0.2) * 5) * 0.055)
    local scaleUp = pop * (1 + coolness * 0.34)
    local fontSize = Clamp(30 + level * 2.1 + point.scale * 0.42, 42, 88)
    local color = ValueColor(effect.value)
    local dark = MixColor(color, RETRO.ink, 0.58)
    local text = "+" .. effect.value
    local rayCount = 6 + math.floor(coolness * 12)
    local sparkleCount = 4 + math.floor(coolness * 10)
    local extrusionDepth = math.floor(5 + coolness * 5)

    nvgSave(vg_)
    nvgTranslate(vg_, point.x, point.y)
    nvgRotate(vg_, math.sin(effect.age * 10 + level) * 0.045 * coolness * (1 - t))
    nvgScale(vg_, scaleUp, scaleUp)
    nvgGlobalAlpha(vg_, fade)
    for i = 0, rayCount - 1 do
        local angle = i / rayCount * math.pi * 2 + effect.age * (0.8 + coolness * 1.2)
        local inner = fontSize * (0.58 + t * 0.18)
        local outer = inner + fontSize * (0.38 + coolness * 0.72) * (1 - t * 0.45)
        nvgBeginPath(vg_)
        nvgMoveTo(vg_, math.cos(angle) * inner, math.sin(angle) * inner)
        nvgLineTo(vg_, math.cos(angle) * outer, math.sin(angle) * outer)
        nvgStrokeColor(vg_, Color(color, math.floor(255 * (0.22 + coolness * 0.28))))
        nvgStrokeWidth(vg_, 1.5 + coolness * 2.5)
        nvgStroke(vg_)
    end
    for i = 0, sparkleCount - 1 do
        local angle = i / sparkleCount * math.pi * 2 - effect.age * (1.8 + coolness * 1.4)
        local orbit = fontSize * (0.72 + t * (0.34 + coolness * 0.28))
        local size = 2 + coolness * 3.5 + (i % 3)
        nvgSave(vg_)
        nvgTranslate(vg_, math.cos(angle) * orbit, math.sin(angle) * orbit * 0.62)
        nvgRotate(vg_, angle + effect.age * 5)
        nvgBeginPath(vg_)
        nvgRect(vg_, -size / 2, -size / 2, size, size)
        nvgFillColor(vg_, Color(color))
        nvgFill(vg_)
        nvgRestore(vg_)
    end
    SelectNumberFont()
    nvgFontSize(vg_, fontSize)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, Color(dark))
    nvgText(vg_, extrusionDepth * 0.86 + 2, extrusionDepth * 1.12 + 2, text, nil)
    for depth = extrusionDepth, 0, -1 do
        nvgFillColor(vg_, Color(color))
        nvgText(vg_, depth * 0.86, depth * 1.12, text, nil)
    end
    for _, offset in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }) do
        nvgFillColor(vg_, Color(RETRO.ink))
        nvgText(vg_, offset[1], offset[2] + 1.5, text, nil)
    end
    nvgFillColor(vg_, Color(PALETTE.cream))
    nvgText(vg_, 0, 1.5, text, nil)
    nvgRestore(vg_)
end

local function DrawEffects()
    local items = {}
    for _, e in ipairs(effects_) do
        local p = Project(V3(e.x, e.y + 0.2, e.z))
        if p then items[#items + 1] = { depth = p.z, type = "ring", effect = e, p = p } end
        for _, part in ipairs(e.particles) do
            local pp = Project(V3(part.x, part.y, part.z))
            if pp then items[#items + 1] = { depth = pp.z, type = "particle", part = part, p = pp } end
        end
    end
    table.sort(items, function(a, b) return a.depth > b.depth end)
    for _, item in ipairs(items) do
        if item.type == "particle" then
            local part = item.part
            local t = Clamp(part.age / part.life, 0, 1)
            local s = Clamp(part.size * item.p.scale, 2, 9)
            nvgGlobalAlpha(vg_, 1 - t)
            nvgBeginPath(vg_)
            nvgRect(vg_, item.p.x - s / 2, item.p.y - s / 2, s, s)
            nvgFillColor(vg_, Color(part.color))
            nvgFill(vg_)
            nvgGlobalAlpha(vg_, 1)
        else
            local e = item.effect
            local t = Clamp(e.age / e.life, 0, 1)
            local radius = e.explosion
                and (0.42 + t * (4.2 + math.log(e.value, 2) * 0.13))
                or (0.6 + t * (2.8 + math.log(e.value, 2) * 0.15))
            local points = {}
            for j = 0, 27 do
                local a = j / 28 * math.pi * 2
                local p = Project(V3(e.x + math.cos(a) * radius, e.y + 0.08, e.z + math.sin(a) * radius))
                if p then points[#points + 1] = p end
            end
            if #points > 2 then
                nvgGlobalAlpha(vg_, (1 - t) * (e.explosion and 1 or 0.88))
                nvgBeginPath(vg_)
                for j = 1, #points do
                    if j == 1 then nvgMoveTo(vg_, points[j].x, points[j].y) else nvgLineTo(vg_, points[j].x, points[j].y) end
                end
                nvgClosePath(vg_)
                nvgStrokeColor(vg_, Color(e.explosion and RETRO.cream or e.color))
                nvgStrokeWidth(vg_, e.explosion and (7 * (1 - t) + 1.5) or (4 * (1 - t) + 1))
                nvgStroke(vg_)
                if e.explosion then
                    nvgGlobalAlpha(vg_, (1 - t) ^ 2 * 0.9)
                    nvgBeginPath(vg_)
                    nvgCircle(vg_, item.p.x, item.p.y, math.max(3, 22 * item.p.scale * (1 - t) + 3))
                    nvgFillColor(vg_, Color(RETRO.cream))
                    nvgFill(vg_)
                    nvgBeginPath(vg_)
                    nvgCircle(vg_, item.p.x, item.p.y, math.max(2, 12 * item.p.scale * (1 - t) + 2))
                    nvgFillColor(vg_, Color(e.color))
                    nvgFill(vg_)
                end
                nvgGlobalAlpha(vg_, 1)
            end
            local labelP = Project(V3(e.x, e.y + 2.1 + t * 1.5, e.z))
            if e.showScore ~= false and labelP then
                DrawScoreVfx(e, labelP, t)
            end
        end
    end
end

function RuntimeFlow.DrawCombo()
    if RuntimeFlow.comboCount < 2 or not RuntimeFlow.comboPopupAge or gameOver_ then return end

    local age = RuntimeFlow.comboPopupAge
    if age > RuntimeFlow.comboWindowSeconds then return end
    local combo = RuntimeFlow.comboCount
    local fadeDuration = 0.6
    local fadeStart = RuntimeFlow.comboWindowSeconds - fadeDuration
    local visibility = Clamp(1 - math.max(0, age - fadeStart) / fadeDuration, 0, 1)
    local intensity = Clamp((combo - 2) / 10, 0, 1)
    local intro = Clamp(age / 0.22, 0, 1)
    local punch = 1 + (1 - intro) * (0.46 + intensity * 0.34)
        + math.sin(intro * math.pi) * (0.2 + intensity * 0.13)
    local settlePulse = age < 0.8 and math.sin(age * (15 + intensity * 8))
        * math.exp(-age * 4.8) * (0.08 + intensity * 0.05) or 0
    local scale = punch + settlePulse
    local centerX = logicalW_ * 0.5
    local mapTop = Project(V3(0, 0.08, -WORLD.trayL * 0.5))
    local scoreBottomY = 148
    local centerY = mapTop
        and (scoreBottomY + mapTop.y) * 0.5
        or logicalH_ * 0.245
    local seed = RuntimeFlow.comboPopupSerial * 977 + combo * 131
    local color = DOODLE_COLORS[(combo - 2) % #DOODLE_COLORS + 1]
    local secondary = DOODLE_COLORS[(combo - 1) % #DOODLE_COLORS + 1]
    local burstAlpha = Clamp(1 - age / (0.62 + intensity * 0.38), 0, 1)
    local baseRadius = math.min(logicalW_, logicalH_) * (0.105 + intensity * 0.055)

    nvgSave(vg_)
    nvgGlobalAlpha(vg_, visibility)
    nvgTranslate(vg_, centerX, centerY)
    nvgRotate(vg_, math.sin(age * 13 + seed) * (1 - intro) * 0.055)

    if burstAlpha > 0 then
        nvgGlobalAlpha(vg_, burstAlpha * visibility * (0.48 + intensity * 0.28))
        DrawStarburstPath(0, 0, 11 + math.min(9, combo),
            baseRadius * (0.42 - intensity * 0.08),
            baseRadius * (1 + intro * (0.55 + intensity * 0.5)),
            age * (0.38 + intensity * 0.45), seed)
        nvgFillColor(vg_, Color(color))
        nvgFill(vg_)

        local rayCount = 7 + math.min(17, combo * 2)
        for i = 1, rayCount do
            local angle = i / rayCount * math.pi * 2 + age * (0.9 + intensity)
            local inner = baseRadius * (0.68 + BurstNoise(seed, i) * 0.22)
            local outer = inner + baseRadius * (0.45 + intensity * 0.78)
                * (0.55 + BurstNoise(seed, i + 40) * 0.65)
            nvgBeginPath(vg_)
            nvgMoveTo(vg_, math.cos(angle) * inner, math.sin(angle) * inner * 0.62)
            nvgLineTo(vg_, math.cos(angle) * outer, math.sin(angle) * outer * 0.62)
            nvgStrokeColor(vg_, Color(i % 2 == 0 and secondary or RETRO.cream))
            nvgStrokeWidth(vg_, 2.5 + intensity * 4.5)
            nvgStroke(vg_)
        end
        nvgGlobalAlpha(vg_, visibility)
    end

    nvgScale(vg_, scale, scale)
    SelectNumberFont()
    nvgFontSize(vg_, Clamp(48 + combo * 2.4, 54, 82))
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local text = "COMBO × " .. combo
    local outline = 3.4 + intensity * 2.2
    for _, offset in ipairs({
        { -outline, 0 }, { outline, 0 }, { 0, -outline }, { 0, outline },
        { -outline * 0.72, -outline * 0.72 }, { outline * 0.72, -outline * 0.72 },
        { -outline * 0.72, outline * 0.72 }, { outline * 0.72, outline * 0.72 },
    }) do
        nvgFillColor(vg_, Color(RETRO.ink))
        nvgText(vg_, offset[1], offset[2] + 3, text, nil)
    end
    nvgFillColor(vg_, Color(color))
    nvgText(vg_, 0, 3, text, nil)
    nvgGlobalAlpha(vg_, 0.72 * visibility)
    nvgFillColor(vg_, Color(RETRO.cream))
    nvgText(vg_, -1.5, 0.5, text, nil)
    nvgRestore(vg_)
end

local function DrawHudBowlingPin(x, y, scaleValue, rotation)
    nvgSave(vg_)
    nvgTranslate(vg_, x, y)
    nvgRotate(vg_, rotation or 0)
    nvgScale(vg_, scaleValue, scaleValue)
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, -3.1, 10)
    nvgBezierTo(vg_, -6.1, 7.2, -5.1, 2.4, -2.5, -1.2)
    nvgBezierTo(vg_, -1.5, -2.7, -1.3, -5.1, -2.1, -7.5)
    nvgBezierTo(vg_, -2.9, -10.2, -1.6, -12.8, 0, -12.8)
    nvgBezierTo(vg_, 1.6, -12.8, 2.9, -10.2, 2.1, -7.5)
    nvgBezierTo(vg_, 1.3, -5.1, 1.5, -2.7, 2.5, -1.2)
    nvgBezierTo(vg_, 5.1, 2.4, 6.1, 7.2, 3.1, 10)
    nvgClosePath(vg_)
    nvgFillColor(vg_, Color(RETRO.cream))
    nvgFill(vg_)
    nvgStrokeColor(vg_, Color(RETRO.ink, 72))
    nvgStrokeWidth(vg_, 1.2)
    nvgStroke(vg_)
    nvgBeginPath(vg_)
    nvgMoveTo(vg_, -2.2, -5.2)
    nvgLineTo(vg_, 2.2, -5.2)
    nvgStrokeColor(vg_, Color(RETRO.blood))
    nvgStrokeWidth(vg_, 1.7)
    nvgStroke(vg_)
    nvgRestore(vg_)
end

function RuntimeFlow.DrawLeaderboardButton()
    local buttonW, buttonH = 88, 36
    local buttonX, buttonY = 12, 73
    DrawRoundRect(buttonX + 3, buttonY + 3, buttonW, buttonH, 17, RETRO.burgundy, 1)
    DrawRoundRect(buttonX, buttonY, buttonW, buttonH, 17, RETRO.mustard, 1)
    nvgStrokeColor(vg_, Color(RETRO.ink))
    nvgStrokeWidth(vg_, 2)
    nvgStroke(vg_)
    SelectBodyFont()
    nvgFontSize(vg_, 14)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, Color(RETRO.ink))
    nvgText(vg_, buttonX + buttonW / 2, buttonY + buttonH / 2 + 1, "排行榜", nil)
    RuntimeFlow.leaderboardButton = { x = buttonX, y = buttonY, w = buttonW, h = buttonH }
end

local function DrawHud()
    local centerX, centerY = logicalW_ / 2, 90
    local scoreText = tostring(math.max(0, math.floor(score_)))
    if #scoreText < 2 then scoreText = "0" .. scoreText end
    local fontSize = #scoreText <= 3 and 55 or math.max(34, 55 - (#scoreText - 3) * 5)
    for i = 0, 23 do
        local angle = i / 24 * math.pi * 2
        local outer = 58 + (i % 2) * 5
        nvgBeginPath(vg_)
        nvgMoveTo(vg_, centerX + math.cos(angle) * 42, centerY + math.sin(angle) * 42)
        nvgLineTo(vg_, centerX + math.cos(angle) * outer, centerY + math.sin(angle) * outer)
        nvgStrokeColor(vg_, Color(RETRO.cream, 107))
        nvgStrokeWidth(vg_, 1.4)
        nvgStroke(vg_)
    end
    SelectNumberFont()
    nvgFontSize(vg_, fontSize)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, offset in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 }, { 3, 4 } }) do
        nvgFillColor(vg_, offset[1] == 3 and Color(RETRO.ink, 128) or Color(RETRO.cream))
        nvgText(vg_, centerX + offset[1], centerY + offset[2], scoreText, nil)
    end
    nvgFillColor(vg_, Color(RETRO.teal))
    nvgText(vg_, centerX, centerY, scoreText, nil)
    DrawHudBowlingPin(centerX - 14, centerY + 41, 0.72, -0.08)
    DrawHudBowlingPin(centerX, centerY + 38, 0.82, 0)
    DrawHudBowlingPin(centerX + 14, centerY + 41, 0.72, 0.08)
end

local function DrawDailyChallengeHud()
    if gameMode_ ~= "daily" or not metaGame_ then return end
    local challenge = metaGame_.data.daily.challenge
    local w, h = 176, 45
    local x, y = (logicalW_ - w) / 2, 148
    DrawRoundRect(x + 2, y + 3, w, h, 12, RETRO.ink, 0.5)
    DrawRoundRect(x, y, w, h, 12, { 126, 220, 255, 255 }, 0.94)
    nvgStrokeColor(vg_, Color(RETRO.ink)); nvgStrokeWidth(vg_, 1.5); nvgStroke(vg_)
    SelectBodyFont(); nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg_, 13); nvgFillColor(vg_, Color(RETRO.ink))
    nvgText(vg_, logicalW_ / 2, y + 14, "寒冰连发  " .. score_ .. "/4000", nil)
    nvgFontSize(vg_, 11)
    nvgText(vg_, logicalW_ / 2, y + 32, "冻结倒计数 " .. (challenge.launchProgress or 0) .. "/5", nil)
end

local function DrawDDADebug()
    if not ddaDebugVisible_ then return end
    local snapshot = spawnManager_:GetDebugSnapshot()
    if not snapshot or not snapshot.metrics or not snapshot.probabilities then return end

    local metrics = snapshot.metrics
    local panelW = math.min(346, logicalW_ - 16)
    local panelH = 174
    local panelX = 8
    local panelY = 8
    nvgSave(vg_)
    DrawRoundRect(panelX + 3, panelY + 4, panelW, panelH, 12, RETRO.ink, 0.48)
    DrawRoundRect(panelX, panelY, panelW, panelH, 12, RETRO.charcoal, 0.96)
    nvgStrokeColor(vg_, Color(RETRO.mustard, 220))
    nvgStrokeWidth(vg_, 1.5)
    nvgStroke(vg_)

    SelectBodyFont()
    nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg_, 13)
    nvgFillColor(vg_, Color(RETRO.mustard))
    nvgText(vg_, panelX + 12, panelY + 9,
        "DDA Spawn Manager  ·  " .. DDA_CONFIG.debug.toggleKeyLabel .. "关闭", nil)

    local mergeAgo = metrics.timeSinceMerge == math.huge
        and "--"
        or string.format("%.1fs", metrics.timeSinceMerge)
    nvgFontSize(vg_, 11)
    nvgFillColor(vg_, Color(RETRO.cream, 230))
    nvgText(vg_, panelX + 12, panelY + 29, string.format(
        "占用 %.1f%%  最高 %d  分数 %d  危险 %s",
        metrics.boardOccupancy * 100,
        metrics.highestValue,
        metrics.score,
        metrics.nearFailure and "是" or "否"
    ), nil)
    nvgText(vg_, panelX + 12, panelY + 45, string.format(
        "近10发 %d  有效 %d  近合成 %d  距上次 %s",
        metrics.recentLaunchCount,
        metrics.successfulLaunches,
        metrics.recentMergeCount,
        mergeAgo
    ), nil)
    nvgText(vg_, panelX + 12, panelY + 61, string.format(
        "Combo %d  连续未合成 %d  短局连败 %d  十发无合成 %s",
        metrics.combo,
        metrics.consecutiveMisses,
        metrics.shortGameStreak,
        metrics.noMergeLastTen and "是" or "否"
    ), nil)

    local values = DDA_CONFIG.pool
    local barX = panelX + 48
    local barW = panelW - 112
    for i, value in ipairs(values) do
        local y = panelY + 79 + (i - 1) * 21
        local probability = snapshot.probabilities[value] or 0
        nvgFontSize(vg_, 12)
        nvgTextAlign(vg_, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, Color(RETRO.cream))
        nvgText(vg_, barX - 7, y + 6, tostring(value), nil)
        DrawRoundRect(barX, y + 2, barW, 9, 4.5, RETRO.cream, 0.14)
        DrawRoundRect(barX, y + 2, barW * probability, 9, 4.5, ValueColor(value), 1)
        nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg_, Color(RETRO.cream))
        nvgText(vg_, barX + barW + 8, y + 6, string.format("%5.1f%%", probability * 100), nil)
    end
    nvgRestore(vg_)
end

local function DrawTip()
    if not showLaunchHint_ or gameOver_ or not launchPos_ then return end
    local anchor = Project(V3(launchPos_.x, 0.04, launchPos_.z))
    if not anchor then return end
    local text = "向后拖动方块"
    local y = anchor.y + 24
    local pulse = 0.82 + math.sin(os.clock() * 6) * 0.18
    nvgSave(vg_)
    nvgGlobalAlpha(vg_, pulse)
    SelectBodyFont()
    nvgFontSize(vg_, 15)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, offset in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }) do
        nvgFillColor(vg_, Color(FLOOR.boundary, 240))
        nvgText(vg_, anchor.x + offset[1], y + offset[2], text, nil)
    end
    nvgFillColor(vg_, Color(PALETTE.cream))
    nvgText(vg_, anchor.x, y, text, nil)
    nvgRestore(vg_)
end

local function DrawDangerCountdown()
    if gameOver_ or not dangerCountdown_ then return end
    local remaining = math.max(0, dangerCountdown_)
    local seconds = math.max(1, math.ceil(remaining))
    local progress = Clamp(remaining / DANGER_COUNTDOWN_SECONDS, 0, 1)
    local cardW = math.min(224, logicalW_ - 40)
    local cardH = 88
    local cardX = (logicalW_ - cardW) / 2
    local cardY = 145
    local pulse = 0.96 + math.sin(os.clock() * 12) * 0.04
    nvgSave(vg_)
    nvgTranslate(vg_, logicalW_ / 2, cardY + cardH / 2)
    nvgScale(vg_, pulse, pulse)
    nvgTranslate(vg_, -logicalW_ / 2, -(cardY + cardH / 2))
    DrawRoundRect(cardX + 3, cardY + 4, cardW, cardH, 18, RETRO.burgundy, 1)
    DrawRoundRect(cardX, cardY, cardW, cardH, 18, RETRO.ink, 0.96)
    nvgStrokeColor(vg_, Color(RETRO.blood))
    nvgStrokeWidth(vg_, 2.5)
    nvgStroke(vg_)
    SelectBodyFont()
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg_, 15)
    nvgFillColor(vg_, Color(RETRO.cream))
    nvgText(vg_, logicalW_ / 2, cardY + 11, "危险！快把方块推回安全区域", nil)
    nvgFontSize(vg_, 31)
    nvgFillColor(vg_, Color(RETRO.mustard))
    nvgText(vg_, logicalW_ / 2, cardY + 32, seconds .. " 秒", nil)
    local barX, barY, barW = cardX + 15, cardY + cardH - 11, cardW - 30
    DrawRoundRect(barX, barY, barW, 5, 3, RETRO.cream, 0.25)
    DrawRoundRect(barX, barY, barW * progress, 5, 3, RETRO.mint, 1)
    nvgRestore(vg_)
end

local function DrawGameOver()
    if not gameOver_ then return end
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, logicalW_, logicalH_)
    nvgFillColor(vg_, Color(RETRO.ink, 178))
    nvgFill(vg_)
    local cardW = math.min(330, logicalW_ - 28)
    local cardH = math.min(470, logicalH_ - 34)
    local cardX = (logicalW_ - cardW) / 2
    local cardY = (logicalH_ - cardH) / 2
    DrawRoundRect(cardX + 5, cardY + 6, cardW, cardH, 20, RETRO.teal, 1)
    DrawRoundRect(cardX, cardY, cardW, cardH, 20, RETRO.cream, 1)
    nvgStrokeColor(vg_, Color(RETRO.ink))
    nvgStrokeWidth(vg_, 2.5)
    nvgStroke(vg_)
    DrawRoundRect(cardX + 11, cardY + 12, cardW - 22, 50, 14, RETRO.blood, 1)
    SelectBodyFont()
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg_, 31)
    nvgFillColor(vg_, Color(RETRO.cream))
    nvgText(vg_, logicalW_ / 2, cardY + 25, "游戏结束", nil)
    nvgFontSize(vg_, 16)
    nvgFillColor(vg_, Color(RETRO.ink))
    nvgText(vg_, logicalW_ / 2, cardY + 70, "本局 " .. math.floor(score_) .. " 分  ·  我的附近排名", nil)
    nvgFontSize(vg_, 13)
    nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local listX, listY = cardX + 22, cardY + 96
    if leaderboardLoading_ then
        nvgText(vg_, listX, listY, "排行榜加载中…", nil)
    elseif leaderboardError_ then
        nvgFillColor(vg_, Color(RETRO.blood))
        nvgText(vg_, listX, listY, leaderboardError_, nil)
    elseif #leaderboard_ == 0 then
        nvgText(vg_, listX, listY, "暂无历史成绩，等你成为第一名！", nil)
    else
        for i, entry in ipairs(leaderboard_) do
            local y = listY + (i - 1) * 25
            if entry.isMe then
                DrawRoundRect(listX - 7, y - 4, cardW - 30, 22, 7, RETRO.mustard, 0.42)
            end
            nvgFillColor(vg_, Color(entry.isMe and RETRO.burgundy or RETRO.ink))
            local displayName = entry.nickname
                or (entry.isMe and "我" or ("玩家 " .. tostring(entry.userId)))
            nvgText(vg_, listX, y, string.format("%2d. %s", entry.rank, displayName), nil)
            nvgTextAlign(vg_, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgText(vg_, cardX + cardW - 22, y, tostring(entry.score), nil)
            nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        end
    end
    local btnGap = 10
    local btnW, btnH = (cardW - 42) / 2, 42
    local btnY = cardY + cardH - 55
    local reviveX = cardX + 16
    local restartX = reviveX + btnW + btnGap

    if RuntimeFlow.message then
        nvgFontSize(vg_, 12)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg_, Color(RuntimeFlow.inFlight and RETRO.burgundy or RETRO.ink))
        nvgText(vg_, logicalW_ / 2, btnY - 6, RuntimeFlow.message, nil)
    end

    local reviveDisabled = RuntimeFlow.reviveUsed or RuntimeFlow.inFlight
    DrawRoundRect(reviveX + 3, btnY + 4, btnW, btnH, 21, RETRO.burgundy, 1)
    DrawRoundRect(reviveX, btnY, btnW, btnH, 21, reviveDisabled and RETRO.charcoal or RETRO.mint, 1)
    nvgStrokeColor(vg_, Color(RETRO.ink))
    nvgStrokeWidth(vg_, 2)
    nvgStroke(vg_)
    nvgFontSize(vg_, 15)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, Color(reviveDisabled and RETRO.cream or RETRO.ink))
    local reviveLabel = RuntimeFlow.reviveUsed and "本局已复活" or (RuntimeFlow.inFlight and "广告播放中" or "看广告复活")
    nvgText(vg_, reviveX + btnW / 2, btnY + btnH / 2 + 1, reviveLabel, nil)

    DrawRoundRect(restartX + 3, btnY + 4, btnW, btnH, 21, RETRO.burgundy, 1)
    DrawRoundRect(restartX, btnY, btnW, btnH, 21, RETRO.mustard, 1)
    nvgStrokeColor(vg_, Color(RETRO.ink))
    nvgStrokeWidth(vg_, 2)
    nvgStroke(vg_)
    nvgFontSize(vg_, 15)
    nvgFillColor(vg_, Color(RETRO.ink))
    nvgText(vg_, restartX + btnW / 2, btnY + btnH / 2 + 1, "再来一局", nil)
    RuntimeFlow.reviveButton = { x = reviveX, y = btnY, w = btnW, h = btnH }
    RuntimeFlow.restartButton = { x = restartX, y = btnY, w = btnW, h = btnH }
end

function RuntimeFlow.DrawLeaderboardNavButton(x, y, w, h, label, disabled)
    DrawRoundRect(x + 2, y + 3, w, h, 16, RETRO.burgundy, disabled and 0.42 or 1)
    DrawRoundRect(x, y, w, h, 16, disabled and RETRO.charcoal or RETRO.mustard, 1)
    nvgStrokeColor(vg_, Color(RETRO.ink, disabled and 100 or 255))
    nvgStrokeWidth(vg_, 1.5)
    nvgStroke(vg_)
    SelectBodyFont()
    nvgFontSize(vg_, 13)
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg_, Color(disabled and RETRO.cream or RETRO.ink, disabled and 150 or 255))
    nvgText(vg_, x + w / 2, y + h / 2 + 1, label, nil)
end

function RuntimeFlow.DrawFullLeaderboard()
    if not RuntimeFlow.fullLeaderboardOpen then return end

    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, logicalW_, logicalH_)
    nvgFillColor(vg_, Color(RETRO.ink, 205))
    nvgFill(vg_)

    local cardW = math.min(342, logicalW_ - 20)
    local cardH = math.min(568, logicalH_ - 26)
    local cardX = (logicalW_ - cardW) / 2
    local cardY = (logicalH_ - cardH) / 2
    DrawRoundRect(cardX + 5, cardY + 6, cardW, cardH, 21, RETRO.teal, 1)
    DrawRoundRect(cardX, cardY, cardW, cardH, 21, RETRO.cream, 1)
    nvgStrokeColor(vg_, Color(RETRO.ink))
    nvgStrokeWidth(vg_, 2.5)
    nvgStroke(vg_)
    DrawRoundRect(cardX + 10, cardY + 11, cardW - 20, 54, 15, RETRO.blood, 1)

    SelectBodyFont()
    nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg_, 25)
    nvgFillColor(vg_, Color(RETRO.cream))
    nvgText(vg_, logicalW_ / 2, cardY + 24, "完整排行榜", nil)

    local totalPages = RuntimeFlow.fullLeaderboardTotal > 0
        and math.max(1, math.ceil(RuntimeFlow.fullLeaderboardTotal / RuntimeFlow.fullLeaderboardPageSize)) or nil
    nvgFontSize(vg_, 12)
    nvgFillColor(vg_, Color(RETRO.ink))
    local pageText = totalPages
        and string.format("第 %d / %d 页 · 共 %d 人", RuntimeFlow.fullLeaderboardPage + 1, totalPages, RuntimeFlow.fullLeaderboardTotal)
        or string.format("第 %d 页", RuntimeFlow.fullLeaderboardPage + 1)
    nvgText(vg_, logicalW_ / 2, cardY + 73, pageText, nil)

    local listX, listY = cardX + 20, cardY + 101
    local scoreX = cardX + cardW - 20
    nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg_, 14)
    if RuntimeFlow.fullLeaderboardLoading then
        nvgText(vg_, listX, listY, "排行榜加载中…", nil)
    elseif RuntimeFlow.fullLeaderboardError then
        nvgFillColor(vg_, Color(RETRO.blood))
        nvgText(vg_, listX, listY, RuntimeFlow.fullLeaderboardError, nil)
    elseif #RuntimeFlow.fullLeaderboard == 0 then
        nvgText(vg_, listX, listY, "暂无上榜玩家", nil)
    else
        for i, entry in ipairs(RuntimeFlow.fullLeaderboard) do
            local y = listY + (i - 1) * 34
            if entry.isMe then
                DrawRoundRect(listX - 8, y - 6, cardW - 24, 28, 8, RETRO.mustard, 0.55)
            elseif i % 2 == 0 then
                DrawRoundRect(listX - 8, y - 6, cardW - 24, 28, 8, RETRO.teal, 0.08)
            end
            local rankColor = entry.rank <= 3 and RETRO.burgundy or RETRO.ink
            nvgFillColor(vg_, Color(rankColor))
            nvgTextAlign(vg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local displayName = entry.nickname
                or (entry.isMe and "我" or ("玩家 " .. tostring(entry.userId)))
            nvgText(vg_, listX, y, string.format("%d. %s", entry.rank, displayName), nil)
            nvgTextAlign(vg_, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgText(vg_, scoreX, y, tostring(entry.score), nil)
        end
    end

    local buttonY = cardY + cardH - 49
    local sideW, closeW, buttonH, gap = 72, 78, 34, 8
    local groupW = sideW * 2 + closeW + gap * 2
    local firstX = (logicalW_ - groupW) / 2
    local prevDisabled = RuntimeFlow.fullLeaderboardLoading or RuntimeFlow.fullLeaderboardPage <= 0
    local nextDisabled = RuntimeFlow.fullLeaderboardLoading
        or (RuntimeFlow.fullLeaderboardTotal > 0
            and (RuntimeFlow.fullLeaderboardPage + 1) * RuntimeFlow.fullLeaderboardPageSize >= RuntimeFlow.fullLeaderboardTotal)
        or (RuntimeFlow.fullLeaderboardTotal <= 0 and #RuntimeFlow.fullLeaderboard < RuntimeFlow.fullLeaderboardPageSize)
    RuntimeFlow.DrawLeaderboardNavButton(firstX, buttonY, sideW, buttonH, "上一页", prevDisabled)
    RuntimeFlow.DrawLeaderboardNavButton(firstX + sideW + gap, buttonY, closeW, buttonH, "关闭", false)
    RuntimeFlow.DrawLeaderboardNavButton(firstX + sideW + gap + closeW + gap, buttonY,
        sideW, buttonH, "下一页", nextDisabled)
    RuntimeFlow.leaderboardPrevButton = prevDisabled and nil
        or { x = firstX, y = buttonY, w = sideW, h = buttonH }
    RuntimeFlow.leaderboardCloseButton = {
        x = firstX + sideW + gap, y = buttonY, w = closeW, h = buttonH,
    }
    RuntimeFlow.leaderboardNextButton = nextDisabled and nil or {
        x = firstX + sideW + gap + closeW + gap, y = buttonY, w = sideW, h = buttonH,
    }
end

local function RenderGame()
    DrawBackground()
    nvgSave(vg_)
    if shakePower_ > 0 then
        nvgTranslate(vg_, (math.random() - 0.5) * shakePower_, (math.random() - 0.5) * shakePower_)
    end
    DrawBoard()
    local drawBlocks = {}
    for i = 1, #blocks_ do drawBlocks[i] = blocks_[i] end
    table.sort(drawBlocks, function(a, b)
        local pa = Project(V3(a.x, a.y, a.z))
        local pb = Project(V3(b.x, b.y, b.z))
        return (pa and pa.z or 0) > (pb and pb.z or 0)
    end)
    for _, b in ipairs(drawBlocks) do RuntimeFlow.DrawBlockAfterimages(b) end
    for _, b in ipairs(drawBlocks) do DrawBlock(b) end
    RuntimeFlow.DrawReviveClearAnimations()
    DrawAim()
    DrawPreview()
    DrawEffects()
    DrawFrontWall()
    nvgRestore(vg_)
    DrawHud()
    DrawDailyChallengeHud()
    RuntimeFlow.DrawCombo()
    DrawDangerCountdown()
    DrawTip()
    DrawGameOver()
    DrawDDADebug()
    if not RuntimeFlow.fullLeaderboardOpen then RuntimeFlow.DrawLeaderboardButton() end
    RuntimeFlow.DrawFullLeaderboard()
    if metaUI_ then
        metaUI_:Draw({ vg = vg_, w = logicalW_, h = logicalH_, selectBody = SelectBodyFont }, metaGame_, gameMode_ == "daily")
    end
end

local InputFlow = {}

local function SwitchGameMode(mode)
    if mode ~= "normal" and mode ~= "daily" then return end
    if gameMode_ == mode and not gameOver_ then return end
    if gameOver_ then FinalizeMetaRun() else SaveGame() end
    gameMode_ = mode
    if not LoadGame() then ResetGame(true) end
    if mode == "daily" then
        tip_ = "寒冰连发：每 5 次发射冻结一个方块"
    else
        tip_ = "已返回普通模式"
    end
    if musicSource_ and sounds_.bgm and audioStarted_ then musicSource_:Play(sounds_.bgm) end
    print("[Bounce4096] 切换模式: " .. mode)
end

function InputFlow.PointInRect(x, y, rect)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function InputFlow.WorldPointFromInput(x, y)
    local launchHeight = BlockSizeForValue(currentValue_) / 2
    local hit = ScreenToWorldOnPlane(x / dpr_, y / dpr_, launchHeight)
    if not hit then return nil end
    return ClampLaunchPoint(hit)
end

function InputFlow.IsInsideLaunchArea(point)
    local half = BlockSizeForValue(currentValue_) / 2
    return point and math.abs(point.x) <= WORLD.trayW / 2 - half and point.z >= WORLD.launchMinZ - 0.45 and point.z <= WORLD.launchMaxZ + 0.45
end

function InputFlow.BeginAim(screenX, screenY)
    local x, y = screenX / dpr_, screenY / dpr_
    if metaUI_ and metaUI_:HandleTap(x, y, metaGame_, {
        startChallenge = function() SwitchGameMode("daily") end,
        normalMode = function() SwitchGameMode("normal") end,
    }) then
        aiming_ = false
        aimStart_, aimPoint_ = nil, nil
        aimCanceling_ = false
        return
    end
    if RuntimeFlow.fullLeaderboardOpen then
        if InputFlow.PointInRect(x, y, RuntimeFlow.leaderboardCloseButton) then
            RuntimeFlow.fullLeaderboardOpen = false
            RuntimeFlow.fullLeaderboardRequestGeneration = RuntimeFlow.fullLeaderboardRequestGeneration + 1
            RuntimeFlow.fullLeaderboardLoading = false
        elseif InputFlow.PointInRect(x, y, RuntimeFlow.leaderboardPrevButton) then
            RuntimeFlow.RefreshFullLeaderboardPage(RuntimeFlow.fullLeaderboardPage - 1, false)
        elseif InputFlow.PointInRect(x, y, RuntimeFlow.leaderboardNextButton) then
            RuntimeFlow.RefreshFullLeaderboardPage(RuntimeFlow.fullLeaderboardPage + 1, false)
        end
        return
    end
    if InputFlow.PointInRect(x, y, RuntimeFlow.leaderboardButton) then
        aiming_ = false
        aimStart_, aimPoint_ = nil, nil
        aimCanceling_ = false
        RuntimeFlow.fullLeaderboardOpen = true
        RuntimeFlow.fullLeaderboardPage = 0
        RuntimeFlow.fullLeaderboardTotal = 0
        RuntimeFlow.fullLeaderboard = {}
        RuntimeFlow.RefreshFullLeaderboardPage(0, true)
        return
    end
    if gameOver_ then
        if InputFlow.PointInRect(x, y, RuntimeFlow.reviveButton) and not RuntimeFlow.reviveUsed and not RuntimeFlow.inFlight then
            RuntimeFlow.ShowRevive()
        elseif InputFlow.PointInRect(x, y, RuntimeFlow.restartButton) then
            FinalizeMetaRun()
            ResetGame(false)
            if musicSource_ and sounds_.bgm and audioStarted_ then musicSource_:Play(sounds_.bgm) end
            print("[Bounce4096] 新游戏")
        end
        return
    end
    StartAudio()
    if not canShoot_ then return end
    local worldPoint = InputFlow.WorldPointFromInput(screenX, screenY)
    if not InputFlow.IsInsideLaunchArea(worldPoint) then return end
    aiming_ = true
    aimStart_ = { x = launchPos_.x, y = launchPos_.y, z = launchPos_.z }
    aimPoint_ = { x = launchPos_.x, y = launchPos_.y, z = launchPos_.z }
    aimCanceling_ = true
end

function InputFlow.MoveAim(screenX, screenY)
    if (metaUI_ and metaUI_:IsOpen()) or RuntimeFlow.fullLeaderboardOpen or not aiming_ then return end
    local launchHeight = BlockSizeForValue(currentValue_) / 2
    local hit = ScreenToWorldOnPlane(screenX / dpr_, screenY / dpr_, launchHeight)
    if not hit then return end
    aimPoint_ = {
        x = Clamp(hit.x, -WORLD.trayW / 2 - WORLD.aimDragMarginX, WORLD.trayW / 2 + WORLD.aimDragMarginX),
        y = launchHeight,
        z = Clamp(hit.z, WORLD.dangerZ + 0.1, WORLD.trayL / 2 + WORLD.aimDragMarginZ),
    }
    aimCanceling_ = Length2(aimPoint_.x - aimStart_.x, aimPoint_.z - aimStart_.z) <= AIM_CANCEL_RADIUS
end

function InputFlow.EndAim()
    if metaUI_ and metaUI_:IsOpen() then
        aiming_ = false
        aimStart_, aimPoint_ = nil, nil
        aimCanceling_ = false
        return
    end
    if RuntimeFlow.fullLeaderboardOpen then
        aiming_ = false
        aimStart_, aimPoint_ = nil, nil
        aimCanceling_ = false
        return
    end
    if not aiming_ or not aimStart_ or not aimPoint_ then return end
    local start, point = aimStart_, aimPoint_
    local dx, dz = start.x - point.x, start.z - point.z
    local dist = Length2(dx, dz)
    aiming_ = false
    aimStart_, aimPoint_ = nil, nil
    if aimCanceling_ or dist <= AIM_CANCEL_RADIUS then
        aimCanceling_ = false
        tip_ = "向后拖动方块发射"
        return
    end
    aimCanceling_ = false
    if dist < 0.32 or dz > -0.12 then
        tip_ = "向下拖拽得越远，发射越有力"
        return
    end
    local power = RuntimeFlow.LaunchPower(dist)
    local dirX, dirZ = dx / dist, dz / dist
    local speed = WORLD.launchBaseSpeed + power * WORLD.launchPowerSpeed
    if heavyBlock_ then heavyBlock_.mass = BlockMassForValue(heavyBlock_.value) end
    heavyBlock_ = nil
    local block = CreateBlock(currentValue_, start.x, start.y, start.z, dirX * speed, 0, dirZ * speed, false)
    local launchLean = power * 0.22
    local launchAngularSpeed = 4.5 + power * 7.5
    block.rx = -dirZ * launchLean
    block.ry = 0
    block.rz = dirX * launchLean
    block.spinX = -dirZ * launchAngularSpeed
    block.spinY = 0
    block.spinZ = dirX * launchAngularSpeed
    block.canAirSpin = true
    block.y = CubeGroundSupportHeight(block)
    block.mass = BlockMassForValue(block.value) * WORLD.launchedMassMultiplier
    block.launchDirX = dirX
    block.launchDirZ = dirZ
    block.launchTrail = true
    block.afterimageTimer = 0
    heavyBlock_ = block
    blocks_[#blocks_ + 1] = block
    PlaySfx("launch", 0.46)
    canShoot_ = false
    shootCooldown_ = SHOOT_COOLDOWN_SECONDS
    tip_ = string.format("下一枚方块准备中 %.1f秒", SHOOT_COOLDOWN_SECONDS)
    -- 先根据已经完成的发射结果决定下一枚，再把本次发射加入最近10次记录。
    currentValue_ = RandomValue()
    spawnManager_:RecordLaunch(block.value, ddaElapsed_)
    if metaGame_ then
        metaGame_:RecordLaunch(block.value, os.time())
        if gameMode_ == "daily" then
            local triggerFreeze = metaGame_:RecordChallengeLaunch(os.time())
            if triggerFreeze then TryFreezeDailyBlock() end
        end
    end
    launchPos_ = ClampLaunchPoint(launchPos_)
    tip_ = "向后拖动方块发射"
    showLaunchHint_ = false
    SaveGame()
    print("[Bounce4096] 发射方块 id=" .. block.id .. " value=" .. block.value)
end

function Start()
    math.randomseed(os.time())
    graphics.windowTitle = "弹射4096"
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true
    UpdateScreenMetrics()
    print(string.format(
        "[Bounce4096] 比例布局 boundary=%.3fx%.3f, tray=%.3fx%.3f, block2=%.3f, block2048=%.3f",
        WORLD.playBoundaryW,
        WORLD.playBoundaryL,
        WORLD.trayW,
        WORLD.trayL,
        BlockSizeForValue(2),
        BlockSizeForValue(2048)
    ))
    launchPos_ = { x = 0, y = BlockSizeForValue(currentValue_) / 2, z = WORLD.defaultLaunchZ }

    vg_ = nvgCreate(1)
    if not vg_ then
        print("[Bounce4096] ERROR: NanoVG 创建失败")
        return
    end
    LoadFonts()

    LoadMetaGame()
    LoadDDAProfile()
    if not LoadGame() then ResetGame(true) end
    SubscribeToEvent("UserNicknameResponse", "HandleUserNicknameResponse")

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonUp", "HandleMouseButtonUp")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent(vg_, "NanoVGRender", "HandleNanoVGRender")

    print("[Bounce4096] 启动完成：拖拽发射，相同数字碰撞合成")
end

function Stop()
    if gameOver_ then FinalizeMetaRun() end
    SaveGame()
    SaveMetaGame()
    FlushMetaCloud(true)
    SaveDDAProfile()
    if musicSource_ then musicSource_:Stop() end
    for _, pool in pairs(sfxPools_) do
        for _, source in ipairs(pool.sources) do source:Stop() end
    end
    sfxPools_ = {}
    if audioScene_ then audioScene_:Dispose(); audioScene_ = nil end
    if vg_ then nvgDelete(vg_); vg_ = nil end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")
    UpdateGame(math.min(1 / 30, math.max(0.001, dt)))
end

function HandleScreenMode()
    UpdateScreenMetrics()
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseButtonDown(eventType, eventData)
    if eventData:GetInt("Button") == MOUSEB_LEFT then
        InputFlow.BeginAim(eventData:GetInt("X"), eventData:GetInt("Y"))
    end
end

---@param eventType string
---@param eventData MouseMoveEventData
function HandleMouseMove(eventType, eventData)
    InputFlow.MoveAim(eventData:GetInt("X"), eventData:GetInt("Y"))
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function HandleMouseButtonUp(eventType, eventData)
    if eventData:GetInt("Button") == MOUSEB_LEFT then
        InputFlow.EndAim()
    end
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    InputFlow.BeginAim(eventData:GetInt("X"), eventData:GetInt("Y"))
end

---@param eventType string
---@param eventData TouchMoveEventData
function HandleTouchMove(eventType, eventData)
    InputFlow.MoveAim(eventData:GetInt("X"), eventData:GetInt("Y"))
end

---@param eventType string
---@param eventData TouchEndEventData
function HandleTouchEnd(eventType, eventData)
    InputFlow.EndAim()
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData:GetInt("Key")
    if key == KEY_R then
        if gameOver_ then FinalizeMetaRun() end
        ResetGame(false)
        print("[Bounce4096] 按 R 重开")
    elseif key == DDA_CONFIG.debug.toggleKey then
        ddaDebugVisible_ = not ddaDebugVisible_
        print("[SpawnManager] DDA Debug=" .. tostring(ddaDebugVisible_))
    elseif key == KEY_SPACE then
        StartAudio()
    end
end

function HandleNanoVGRender()
    if not vg_ then return end
    nvgBeginFrame(vg_, logicalW_, logicalH_, dpr_)
    RenderGame()
    nvgEndFrame(vg_)
end
end

RuntimeFlow.InstallGameScope()
