local Util = require("diggin.Util")

local EffectRenderer = {}

local ROOT = "image/diggin/original/"
local UPGRADES = ROOT .. "Upgrades/"

local PATHS = {
    shrapnel = UPGRADES .. "shrapnel.png",
    pickarang = UPGRADES .. "boomerang pickaxe.png",
    missile = UPGRADES .. "drill missile.png",
    ball = UPGRADES .. "bouncing ball.png",
    wormBullet = UPGRADES .. "wormBullet.png",
    drillDrone = UPGRADES .. "drilldrone.png",
    spinningPickaxe = UPGRADES .. "bolji spinning pick.png",
    shockwave = ROOT .. "UI/shockwav.png",
    missileTarget = UPGRADES .. "target.png",
    fallingPickaxe = UPGRADES .. "falling pickaxe.png",
    termiteDrone = UPGRADES .. "bolji termit dron.png",
    hammer = UPGRADES .. "hammer.png",
    worm = UPGRADES .. "WORM.png",
    dynamite = UPGRADES .. "dynamiteAsset.png",
    explosion = ROOT .. "UI/Explosion-0001.png",
}

local function drawFrame(renderer, path, x, y, width, height, sheetWidth, sheetHeight, frameX, frameY, frameWidth, frameHeight, alpha)
    local image = renderer:GetImage(path)
    if not image then return false end
    local scaleX, scaleY = width / frameWidth, height / frameHeight
    nvgBeginPath(renderer.vg)
    nvgRect(renderer.vg, x, y, width, height)
    nvgFillPaint(renderer.vg, nvgImagePattern(
        renderer.vg,
        x - frameX * scaleX,
        y - frameY * scaleY,
        sheetWidth * scaleX,
        sheetHeight * scaleY,
        0,
        image,
        alpha or 1
    ))
    nvgFill(renderer.vg)
    return true
end

local function drawRotated(renderer, path, x, y, width, height, rotation, alpha)
    nvgSave(renderer.vg)
    nvgTranslate(renderer.vg, x, y)
    nvgRotate(renderer.vg, rotation or 0)
    local drawn = renderer:DrawImage(path, -width * 0.5, -height * 0.5, width, height, alpha)
    nvgRestore(renderer.vg)
    return drawn
end

local function drawRotatedFrame(renderer, path, x, y, width, height, rotation, sheetWidth, sheetHeight, frameX, frameY, frameWidth, frameHeight, alpha)
    nvgSave(renderer.vg)
    nvgTranslate(renderer.vg, x, y)
    nvgRotate(renderer.vg, rotation or 0)
    local drawn = drawFrame(renderer, path, -width * 0.5, -height * 0.5, width, height,
        sheetWidth, sheetHeight, frameX, frameY, frameWidth, frameHeight, alpha)
    nvgRestore(renderer.vg)
    return drawn
end

local function velocityAngle(effect)
    return math.atan(effect.vy or 0, effect.vx or 1)
end

function EffectRenderer.Draw(renderer, effect, sx, sy, alpha)
    if effect.toolVisual and require("diggin.WorldItemVisuals").Draw(renderer, effect, sx, sy, alpha) then return true end
    local visualScale = math.max(0.5, tonumber(effect.visualScale) or 1)
    if effect.legendary then
        nvgBeginPath(renderer.vg)
        nvgCircle(renderer.vg, sx, sy, 13 * visualScale)
        nvgFillPaint(renderer.vg, nvgRadialGradient(renderer.vg, sx, sy, 1, 15 * visualScale,
            nvgRGBA(255, 222, 92, math.floor(170 * alpha)), nvgRGBA(150, 65, 255, 0)))
        nvgFill(renderer.vg)
    end
    if effect.kind == "dynamite" then
        return drawRotated(renderer, PATHS.dynamite, sx, sy, 18 * visualScale, 18 * visualScale, effect.rotation, alpha)
    elseif effect.kind == "explosion" then
        local progress = Util.Clamp(1 - alpha, 0, 0.999)
        local frame = math.min(5, math.floor(progress * 6))
        local size = Util.Clamp(effect.radius * 2.4 * visualScale, 48, 144)
        return drawFrame(renderer, PATHS.explosion, sx - size * 0.5, sy - size * 0.625,
            size, size * 1.25, 384, 320, frame * 64, 0, 64, 80, 1)
    end
    if effect.kind ~= "active_effect" then return false end

    local effectId = effect.effectId
    local age = effect.age or 0
    if effectId == "shrapnel_debris" then
        local frame = math.floor(age * 15) % 4
        return drawRotatedFrame(renderer, PATHS.shrapnel, sx, sy, 12 * visualScale, 14 * visualScale, velocityAngle(effect),
            24, 7, frame * 6, 0, 6, 7, alpha)
    elseif effectId == "pickarang" then
        return drawRotated(renderer, PATHS.pickarang, sx, sy, 20 * visualScale, 20 * visualScale, effect.rotation, alpha)
    elseif effectId == "drill_missile" then
        local pulse = 0.72 + math.sin(age * 10) * 0.2
        renderer:DrawImage(PATHS.missileTarget,
            sx + effect.targetX - effect.x - 13,
            sy + effect.targetY - effect.y - 13,
            26, 26, Util.Clamp(pulse, 0.35, 1))
        return drawRotated(renderer, PATHS.missile, sx, sy, 14 * visualScale, 23 * visualScale, velocityAngle(effect) - math.pi * 0.5, alpha)
    elseif effectId == "bouncing_ball" then
        return drawRotated(renderer, PATHS.ball, sx, sy, 15 * visualScale, 15 * visualScale, effect.rotation, alpha)
    elseif effectId == "bullet_worms" then
        local frame = math.floor(age * 10) % 2
        return drawRotatedFrame(renderer, PATHS.wormBullet, sx, sy, 18 * visualScale, 18 * visualScale, velocityAngle(effect) - math.pi * 0.5,
            32, 16, frame * 16, 0, 16, 16, alpha)
    elseif effectId == "drill_drones" then
        return drawRotated(renderer, PATHS.drillDrone, sx, sy, 18 * visualScale, 18 * visualScale, velocityAngle(effect), 1)
    elseif effectId == "pickaxe_orbit" then
        return drawRotated(renderer, PATHS.spinningPickaxe, sx, sy, 21 * visualScale, 21 * visualScale, effect.rotation, 1)
    elseif effectId == "shockwave" then
        local progress = Util.Clamp(age / (effect.maxLife or 0.58), 0, 1)
        local size = (18 + effect.radius * 2 * progress) * visualScale
        return renderer:DrawImage(PATHS.shockwave, sx - size * 0.5, sy - size * 0.5, size, size, 1 - progress * 0.35)
    elseif effectId == "falling_pickaxe" then
        return drawRotated(renderer, PATHS.fallingPickaxe, sx, sy, 44 * visualScale, 44 * visualScale, effect.rotation, alpha)
    elseif effectId == "termite_drone" then
        return drawRotated(renderer, PATHS.termiteDrone, sx, sy, 20 * visualScale, 14 * visualScale, velocityAngle(effect), alpha)
    elseif effectId == "molenir" then
        local frame = math.floor(age * 12) % 8
        return drawRotatedFrame(renderer, PATHS.hammer, sx, sy, 38 * visualScale, 38 * visualScale, velocityAngle(effect),
            128, 16, frame * 16, 0, 16, 16, alpha)
    elseif effectId == "the_worm" then
        local frame = math.floor(age * 9) % 9
        return drawRotatedFrame(renderer, PATHS.worm, sx, sy, 56 * visualScale, 40 * visualScale, velocityAngle(effect),
            144, 16, frame * 16, 0, 16, 16, alpha)
    end

    -- Unknown active effects still use an original fragment sprite instead of a vector placeholder.
    return drawRotatedFrame(renderer, PATHS.shrapnel, sx, sy, 12, 14, velocityAngle(effect),
        24, 7, 0, 0, 6, 7, alpha)
end

return EffectRenderer
