local Config = require("nightgate.Config")
local UIData = require("nightgate.OriginalUIData")
local MapData = require("nightgate.OriginalMapData")
local UI = require("urhox-libs/UI")

local Renderer = {}
Renderer.__index = Renderer

local function rgba(color, alpha)
    return nvgRGBA(color[1], color[2], color[3], math.floor((color[4] or 255) * (alpha or 1)))
end

local function fillRect(ctx, x, y, w, h, color)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgFillColor(ctx, rgba(color))
    nvgFill(ctx)
end

local function strokeRect(ctx, x, y, w, h, color, width)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgStrokeColor(ctx, rgba(color))
    nvgStrokeWidth(ctx, width or 1)
    nvgStroke(ctx)
end

function Renderer.New(battle)
    local self = setmetatable({}, Renderer)
    self.battle = battle
    self.context = nvgCreate(1)
    if not self.context then
        error("Nightgate: failed to create NanoVG context")
    end
    nvgSetRenderOrder(self.context, 20)
    self.font = nvgCreateFont(self.context, "nightgate-pixel", "Fonts/FusionPixel-12px-Prop-zh_hans.ttf")
    self.fontBold = nvgCreateFont(self.context, "nightgate-pixel-bold", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")
    self.images = {}
    self.viewport = { scale = 1, offsetX = 0, offsetY = 0, width = UIData.designWidth, height = UIData.designHeight }
    self:LoadImages()
    return self
end

function Renderer:UpdateViewport()
    -- Match the Widget system's BASE PIXEL coordinate space. UI.Scale.DEFAULT
    -- is not always identical to the device DPR on phones.
    local width, height = UI.GetViewportSize()
    local pixelRatio = math.max(0.01, UI.GetScale())
    local scale = math.min(width / UIData.designWidth, height / UIData.designHeight)
    self.viewport.scale = scale
    self.viewport.offsetX = (width - UIData.designWidth * scale) * 0.5
    self.viewport.offsetY = (height - UIData.designHeight * scale) * 0.5
    self.viewport.width = width
    self.viewport.height = height
    return width, height, pixelRatio
end

function Renderer:ScreenToDesign(physicalX, physicalY)
    self:UpdateViewport()
    local pixelRatio = math.max(0.01, UI.GetScale())
    local x = physicalX / pixelRatio
    local y = physicalY / pixelRatio
    return (x - self.viewport.offsetX) / self.viewport.scale, (y - self.viewport.offsetY) / self.viewport.scale
end

function Renderer:LoadImage(key, path)
    if self.images[key] then
        return
    end
    local handle = nvgCreateImage(self.context, path, NVG_IMAGE_NEAREST)
    if handle and handle >= 0 then
        self.images[key] = handle
        return true
    else
        log:Write(LOG_WARNING, "Nightgate image failed: " .. path)
        return false
    end
end

function Renderer:LoadImages()
    self:LoadImage("grass", "image/nightgate/environment/base_grass_8836ef28.png")
    self:LoadImage("terrain", "image/nightgate/environment/battle_terrain_1920x1080.png")
    self:LoadImage("wall", "image/nightgate/environment/wall_layer_1920x1080.png")
    self:LoadImage("portal", "image/nightgate/environment/summon_gate.png")
    for index = 1, #Config.ARCHERS do
        local archer = Config.ARCHERS[index]
        self:LoadImage("archer:" .. tostring(archer.id), archer.sprite)
    end
    for index = 1, #Config.HEROES do
        local hero = Config.HEROES[index]
        self:LoadImage("hero:" .. tostring(hero.id), hero.sprite)
    end
    self:LoadImage("cursor", Config.CURSOR.sprite)
    self:LoadImage("coin", "image/nightgate/currency/asset_632cd9da.png")
    -- Recovered individual frames from the shipped demo. Loading frame images
    -- directly avoids shrinking an entire sprite sheet into one projectile.
    for frame = 1, 4 do
        self:LoadImage("skill:arcane:" .. tostring(frame), "image/nightgate/skills/dogen" .. tostring(frame) .. ".png")
    end
    for frame = 1, 9 do
        self:LoadImage("skill:fire:" .. tostring(frame), "image/nightgate/skills/prite-000" .. tostring(frame) .. ".png")
    end
    self:LoadImage("skill:arcane_burst", "image/nightgate/skills/spell_11-sheet.png")
    self:LoadImage("skill:sanctuary", "image/nightgate/skills/circle.png")
    self:LoadImage("skill:holy_sword", "image/nightgate/skills/holy_devotion_sword_48x48.png")
    self:LoadImage("skill:nature", "image/nightgate/skills/nature_forestry_80x176.png")
    self:LoadImage("skill:nature_spike", "image/nightgate/skills/nature_ii_16x32.png")
    self:LoadImage("skill:seed", "image/nightgate/skills/res_48.png")
    for id, monster in pairs(Config.MONSTERS) do
        self:LoadImage("monster:" .. id, monster.sprite)
    end
    for index = 1, #MapData.decorations do
        local item = MapData.decorations[index]
        self:LoadImage("decor:" .. item.path, item.path)
    end
end

function Renderer:DrawImage(key, x, y, w, h, alpha, tint)
    local handle = self.images[key]
    if not handle then
        return false
    end
    nvgBeginPath(self.context)
    nvgRect(self.context, x, y, w, h)
    if tint then
        nvgFillPaint(self.context, nvgImagePatternTinted(self.context, x, y, w, h, 0, handle, rgba(tint, alpha)))
    else
        nvgFillPaint(self.context, nvgImagePattern(self.context, x, y, w, h, 0, handle, alpha or 1))
    end
    nvgFill(self.context)
    return true
end

function Renderer:DrawRotatedImage(key, x, y, w, h, angle, alpha, tint)
    local ctx = self.context
    nvgSave(ctx)
    nvgTranslate(ctx, x, y)
    nvgRotate(ctx, angle or 0)
    local drawn = self:DrawImage(key, -w * 0.5, -h * 0.5, w, h, alpha, tint)
    nvgRestore(ctx)
    return drawn
end

function Renderer:DrawOutdoor(width, height)
    local ctx = self.context
    if self:DrawImage("terrain", 0, 0, width, height, 1) then
        return
    end
    fillRect(ctx, 0, 0, width, height, { 38, 82, 41, 255 })
    local tile = self.images.grass
    if tile then
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, width, height)
        nvgFillPaint(ctx, nvgImagePattern(ctx, 0, 0, 48, 48, 0, tile, 0.48))
        nvgFill(ctx)
    end
end

function Renderer:DrawMapDecorations()
    local unit = MapData.pixelsPerWorldUnit
    for index = 1, #MapData.decorations do
        local item = MapData.decorations[index]
        if item.group ~= "summon" then
            local width = item.w / item.ppu * math.abs(item.sx) * unit
            local height = item.h / item.ppu * math.abs(item.sy) * unit
            local x = MapData.centerX + item.x * unit - width * 0.5
            local y = MapData.centerY - item.y * unit - height * 0.5
            self:DrawImage("decor:" .. item.path, x, y, width, height, 1)
        end
    end
end

function Renderer:DrawArenaGround(arena)
    local ctx = self.context
    if self:DrawImage("wall", 0, 0, UIData.designWidth, UIData.designHeight, 1) then
        return
    end
    local wall = 82
    fillRect(ctx, arena.x, arena.y, arena.size, wall, Config.COLORS.wall)
    fillRect(ctx, arena.x, arena.y + arena.size - wall, arena.size, wall, Config.COLORS.wall)
    fillRect(ctx, arena.x, arena.y + wall, wall, arena.size - wall * 2, Config.COLORS.wall)
    fillRect(ctx, arena.x + arena.size - wall, arena.y + wall, wall, arena.size - wall * 2, Config.COLORS.wall)

    -- Dark stone wall courses and the warm lamps seen on every side.
    local segments = 14
    local segment = arena.size / segments
    for index = 0, segments - 1 do
        local offset = index % 2 == 0 and 0 or 4
        strokeRect(ctx, arena.x + index * segment, arena.y + offset, segment, wall - offset, Config.COLORS.wallEdge, 1)
        strokeRect(ctx, arena.x + index * segment, arena.y + arena.size - wall, segment, wall - offset, Config.COLORS.wallEdge, 1)
        strokeRect(ctx, arena.x + offset, arena.y + index * segment, wall - offset, segment, Config.COLORS.wallEdge, 1)
        strokeRect(ctx, arena.x + arena.size - wall, arena.y + index * segment, wall - offset, segment, Config.COLORS.wallEdge, 1)
        if index % 3 == 1 then
            nvgBeginPath(ctx)
            nvgCircle(ctx, arena.x + (index + 0.5) * segment, arena.y + wall - 6, 2.2)
            nvgCircle(ctx, arena.x + (index + 0.5) * segment, arena.y + arena.size - wall + 6, 2.2)
            nvgCircle(ctx, arena.x + wall - 6, arena.y + (index + 0.5) * segment, 2.2)
            nvgCircle(ctx, arena.x + arena.size - wall + 6, arena.y + (index + 0.5) * segment, 2.2)
            nvgFillColor(ctx, nvgRGBA(255, 119, 38, 220))
            nvgFill(ctx)
        end
    end
    strokeRect(ctx, arena.x, arena.y, arena.size, arena.size, { 8, 8, 12, 255 }, 4)
    strokeRect(ctx, arena.x + wall, arena.y + wall, arena.size - wall * 2, arena.size - wall * 2, { 76, 70, 83, 255 }, 2)
end

function Renderer:DrawWallFlashes(arena)
    local ctx = self.context
    local thickness = 82
    for side = 1, 4 do
        local alpha = self.battle.wallFlash[side] / 0.16
        if alpha > 0 then
            local color = { 255, 66, 53, math.floor(180 * alpha) }
            if side == 1 then
                fillRect(ctx, arena.x, arena.y, arena.size, thickness, color)
            elseif side == 2 then
                fillRect(ctx, arena.x + arena.size - thickness, arena.y, thickness, arena.size, color)
            elseif side == 3 then
                fillRect(ctx, arena.x, arena.y + arena.size - thickness, arena.size, thickness, color)
            else
                fillRect(ctx, arena.x, arena.y, thickness, arena.size, color)
            end
        end
    end
end

function Renderer:DrawPortal(arena, elapsed)
    local ctx = self.context
    local x = arena.x + arena.size * 0.5
    local y = arena.y + arena.size * 0.5
    local pulse = 1 + math.sin(elapsed * 3.2) * 0.05
    nvgBeginPath(ctx)
    nvgCircle(ctx, x, y + 6, 47 * pulse)
    nvgFillPaint(ctx, nvgRadialGradient(ctx, x, y, 5, 50, nvgRGBA(255, 81, 19, 100), nvgRGBA(72, 22, 91, 0)))
    nvgFill(ctx)
    self:DrawImage("portal", x - 48 * pulse, y - 48 * pulse, 96 * pulse, 96 * pulse, 1)
end

function Renderer:DrawDefenders(elapsed)
    local battle = self.battle
    local stats = battle:GetStats()
    for side = 1, 4 do
        local count = battle:GetArcherCountForSide(side, stats)
        local visualCount = math.min(52, count)
        local size = visualCount > 14 and 25 or 30
        local archer = battle:GetArcherForSide(side) or Config.ARCHER
        for slot = 1, visualCount do
            local x, y = battle:GetDefenderPosition(side, slot, visualCount)
            local bob = math.sin(elapsed * 3 + slot * 0.7) * 0.7
            self:DrawImage("archer:" .. tostring(archer.id), x - size * 0.5, y - size * 0.72 + bob, size, size, 1)
        end
        -- Heroes are part of the four-wall force; draw them slightly outside the captain line.
        local hero = battle:GetHeroForSide(side)
        if hero then
            local hx, hy = battle:GetHeroPosition(side)
            self:DrawImage("hero:" .. tostring(hero.id), hx - 17, hy - 20, 34, 34, 1)
        end
    end
end

function Renderer:DrawEnemies()
    local ctx = self.context
    for index = 1, #self.battle.enemies do
        local enemy = self.battle.enemies[index]
        local size = enemy.size
        local y = enemy.y + math.sin(enemy.bob) * 1.2
        if enemy.elite and enemy.affixColor then
            local pulse = 0.75 + math.sin(enemy.bob * 1.3) * 0.12
            nvgBeginPath(ctx)
            nvgCircle(ctx, enemy.x, y, size * 0.68)
            nvgFillPaint(ctx, nvgRadialGradient(ctx, enemy.x, y, size * 0.18, size * 0.72,
                rgba(enemy.affixColor, 0.34 * pulse), rgba(enemy.affixColor, 0)))
            nvgFill(ctx)
        end
        nvgBeginPath(ctx)
        nvgEllipse(ctx, enemy.x, enemy.y + size * 0.3, size * 0.34, size * 0.1)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 90))
        nvgFill(ctx)
        self:DrawImage("monster:" .. enemy.id, enemy.x - size * 0.5, y - size * 0.58, size, size, 1, enemy.flash > 0 and { 255, 180, 180, 255 } or nil)
        if enemy.seedDamage then
            local seedPulse = 1 + math.sin(enemy.bob * 1.7) * 0.16
            self:DrawImage("skill:seed", enemy.x - 7 * seedPulse, y - size * 0.72 - 13, 14 * seedPulse, 14 * seedPulse, 1)
        end
        if enemy.elite and enemy.affixName then
            nvgFontFace(ctx, "nightgate-pixel-bold")
            nvgFontSize(ctx, 11)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 220))
            nvgText(ctx, enemy.x + 1, y - size * 0.78 + 1, enemy.affixName, nil)
            nvgFillColor(ctx, rgba(enemy.affixColor, 1))
            nvgText(ctx, enemy.x, y - size * 0.78, enemy.affixName, nil)
        end
        if enemy.boss or enemy.elite or enemy.hp < enemy.maxHP then
            local width = size * 0.82
            fillRect(ctx, enemy.x - width * 0.5, y - size * 0.64, width, 4, { 18, 15, 20, 220 })
            fillRect(ctx, enemy.x - width * 0.5 + 1, y - size * 0.64 + 1, (width - 2) * math.max(0, enemy.hp / enemy.maxHP), 2, Config.COLORS.danger)
        end
    end
end

function Renderer:DrawProjectiles()
    local ctx = self.context
    local frameClock = GetTime():GetElapsedTime()
    for index = 1, #self.battle.projectiles do
        local projectile = self.battle.projectiles[index]
        local target = projectile.target
        local dx = target and target.x - projectile.x or 1
        local dy = target and target.y - projectile.y or 0
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        local visualScale = math.max(0.75, math.min(2.6, projectile.projectileSize or (projectile.special and 1.8 or 1)))
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, projectile.x - dx / d * (projectile.special and 18 or 11) * visualScale, projectile.y - dy / d * (projectile.special and 18 or 11) * visualScale)
        nvgLineTo(ctx, projectile.x, projectile.y)
        nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, 130))
        nvgStrokeWidth(ctx, (projectile.special and 6 or 3.5) * visualScale)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, projectile.x - dx / d * (projectile.special and 18 or 11) * visualScale, projectile.y - dy / d * (projectile.special and 18 or 11) * visualScale)
        nvgLineTo(ctx, projectile.x, projectile.y)
        nvgStrokeColor(ctx, rgba(projectile.color))
        nvgStrokeWidth(ctx, (projectile.special and 3.5 or 1.6) * visualScale)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, projectile.x, projectile.y, (projectile.special and 3.5 or 1.8) * visualScale)
        nvgFillColor(ctx, rgba(projectile.color))
        nvgFill(ctx)
        if projectile.special then
            local angle = math.atan(dy, dx)
            if projectile.skillId == 2001 then
                local frame = math.floor(frameClock * 12) % 4 + 1
                self:DrawRotatedImage("skill:arcane:" .. tostring(frame), projectile.x, projectile.y, 30 * visualScale, 24 * visualScale, angle, 1, projectile.color)
            elseif projectile.skillId == 2006 then
                self:DrawRotatedImage("skill:holy_sword", projectile.x, projectile.y, 18 * visualScale, 30 * visualScale, angle + math.pi * 0.5, 1, { 255, 232, 119, 255 })
            elseif projectile.skillId == 2009 then
                self:DrawRotatedImage("skill:seed", projectile.x, projectile.y, 14 * visualScale, 14 * visualScale, angle, 1)
            end
        elseif projectile.heroProfession then
            local angle = math.atan(dy, dx)
            if projectile.heroProfession == 2 then
                local frame = math.floor(frameClock * 12) % 4 + 1
                self:DrawRotatedImage("skill:arcane:" .. tostring(frame), projectile.x, projectile.y, 22 * visualScale, 18 * visualScale, angle, 1, projectile.color)
            elseif projectile.heroProfession == 4 then
                local frame = math.floor(frameClock * 15) % 9 + 1
                self:DrawImage("skill:fire:" .. tostring(frame), projectile.x - 10 * visualScale, projectile.y - 10 * visualScale, 20 * visualScale, 20 * visualScale, 1)
            elseif projectile.heroProfession == 3 then
                self:DrawImage("skill:seed", projectile.x - 6 * visualScale, projectile.y - 6 * visualScale, 12 * visualScale, 12 * visualScale, 1)
            else
                self:DrawRotatedImage("skill:holy_sword", projectile.x, projectile.y, 10 * visualScale, 18 * visualScale, angle + math.pi * 0.5, 1, projectile.color)
            end
        end
    end
end

function Renderer:DrawCursor()
    local cursor = self.battle.cursor
    if not cursor.visible then
        return
    end
    local ctx = self.context
    local stats = self.battle:GetStats()
    nvgBeginPath(ctx)
    nvgCircle(ctx, cursor.x + 3.5, cursor.y + 4.5, stats.cursorRadius)
    nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, cursor.pulse > 0 and 150 or 90))
    nvgStrokeWidth(ctx, cursor.pulse > 0 and 8 or 5)
    nvgStroke(ctx)
    nvgBeginPath(ctx)
    nvgCircle(ctx, cursor.x, cursor.y, stats.cursorRadius)
    nvgFillColor(ctx, nvgRGBA(184, 184, 169, 35))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(215, 105, 49, cursor.pulse > 0 and 210 or 105))
    nvgStrokeWidth(ctx, cursor.pulse > 0 and 2.5 or 1.2)
    nvgStroke(ctx)
    self:DrawImage("cursor", cursor.x - 13, cursor.y - 13, 28, 28, 1)
end

function Renderer:DrawCoins()
    local ctx = self.context
    for index = 1, #self.battle.coinPickups do
        local coin = self.battle.coinPickups[index]
        if coin.age >= 0 then
            local pulse = 1 + math.sin(coin.rotation) * 0.12
            local size = 18 * pulse
            nvgBeginPath(ctx)
            nvgEllipse(ctx, coin.x + 3, coin.y + 6, size * 0.48, size * 0.24)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 130))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgCircle(ctx, coin.x, coin.y, size * 0.72)
            nvgFillPaint(ctx, nvgRadialGradient(ctx, coin.x, coin.y, 1, size * 0.72, nvgRGBA(255, 202, 56, 85), nvgRGBA(255, 151, 25, 0)))
            nvgFill(ctx)
            self:DrawImage("coin", coin.x - size * 0.5, coin.y - size * 0.5, size, size, 1)
        end
    end
end

function Renderer:DrawVFX()
    local ctx = self.context
    for index = 1, #self.battle.particles do
        local particle = self.battle.particles[index]
        local alpha = particle.life / particle.maxLife
        fillRect(ctx, particle.x - particle.size * 0.5, particle.y - particle.size * 0.5, particle.size, particle.size, { particle.color[1], particle.color[2], particle.color[3], math.floor((particle.color[4] or 255) * alpha) })
    end
    for index = 1, #self.battle.rings do
        local ring = self.battle.rings[index]
        local alpha = ring.life / ring.maxLife
        local shadowWidth = ring.style == "cursor" and (8 + alpha * 5) or (6 + alpha * 3)
        nvgBeginPath(ctx)
        nvgCircle(ctx, ring.x + 4, ring.y + 5, ring.radius)
        nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, math.floor(145 * alpha)))
        nvgStrokeWidth(ctx, shadowWidth)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, ring.x, ring.y, ring.radius)
        nvgStrokeColor(ctx, rgba(ring.color, alpha * 0.28))
        nvgStrokeWidth(ctx, shadowWidth + 2)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, ring.x, ring.y, ring.radius)
        nvgStrokeColor(ctx, rgba(ring.color, alpha))
        nvgStrokeWidth(ctx, 1.5 + alpha * 2)
        nvgStroke(ctx)
    end
    self:DrawSkillEffects()
    nvgFontFace(ctx, "nightgate-pixel-bold")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    for index = 1, #self.battle.floatingText do
        local item = self.battle.floatingText[index]
        local alpha = item.life / item.maxLife
        nvgFontSize(ctx, item.size)
        local emphasized = item.style == "cursor" or item.style == "reward" or item.style == "jackpot"
        local outline = item.style == "jackpot" and 3 or (emphasized and 2 or 1)
        local shadowAlpha = math.floor((emphasized and 235 or 190) * alpha)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, shadowAlpha))
        nvgText(ctx, item.x - outline, item.y, item.text, nil)
        nvgText(ctx, item.x + outline, item.y, item.text, nil)
        nvgText(ctx, item.x, item.y - outline, item.text, nil)
        nvgText(ctx, item.x, item.y + outline, item.text, nil)
        if emphasized then
            nvgText(ctx, item.x - outline, item.y - outline, item.text, nil)
            nvgText(ctx, item.x + outline, item.y - outline, item.text, nil)
            nvgText(ctx, item.x - outline, item.y + outline, item.text, nil)
            nvgText(ctx, item.x + outline, item.y + outline, item.text, nil)
        end
        nvgFillColor(ctx, rgba(item.color, alpha))
        nvgText(ctx, item.x, item.y, item.text, nil)
    end
end

function Renderer:DrawSkillEffects()
    local ctx = self.context
    for index = 1, #self.battle.skillEffects do
        local effect = self.battle.skillEffects[index]
        local t = math.max(0, math.min(1, effect.age / effect.maxLife))
        local alpha = math.max(0, effect.life / effect.maxLife)
        local radius = effect.radius
        local skillId = effect.skillId

        if skillId == 2001 then
            local orbit = radius * (0.2 + t * 0.42)
            for ray = 1, 4 do
                local angle = ray * math.pi * 0.5 + t * 2.4
                local x = effect.x + math.cos(angle) * orbit
                local y = effect.y + math.sin(angle) * orbit
                local frame = math.floor((effect.age * 12 + ray) % 4) + 1
                self:DrawRotatedImage("skill:arcane:" .. tostring(frame), x, y, radius * 0.58, radius * 0.42, angle, alpha, { 189, 143, 255, 255 })
            end
            self:DrawImage("skill:arcane_burst", effect.x - radius * 0.45, effect.y - radius * 0.45, radius * 0.9, radius * 0.9, alpha * 0.7, { 185, 126, 255, 255 })
        elseif skillId == 2002 then
            for slash = 1, 3 do
                local angle = -0.85 + (slash - 1) * 0.62
                local offset = (slash - 2) * radius * 0.16
                local dx = math.cos(angle) * radius * (0.68 + t * 0.22)
                local dy = math.sin(angle) * radius * (0.68 + t * 0.22)
                local ox = -math.sin(angle) * offset
                local oy = math.cos(angle) * offset
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, effect.x - dx + ox + 3, effect.y - dy + oy + 4)
                nvgLineTo(ctx, effect.x + dx + ox + 3, effect.y + dy + oy + 4)
                nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, math.floor(190 * alpha)))
                nvgStrokeWidth(ctx, 8)
                nvgStroke(ctx)
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, effect.x - dx + ox, effect.y - dy + oy)
                nvgLineTo(ctx, effect.x + dx + ox, effect.y + dy + oy)
                nvgStrokeColor(ctx, nvgRGBA(196, 139, 255, math.floor(255 * alpha)))
                nvgStrokeWidth(ctx, 4)
                nvgStroke(ctx)
            end
        elseif skillId == 2003 then
            local size = radius * (1.0 + math.sin(t * math.pi) * 0.35)
            local frame = math.max(1, math.min(9, math.floor(t * 8) + 1))
            self:DrawRotatedImage("skill:fire:" .. tostring(frame), effect.x, effect.y, size, size, t * 2.2, alpha, { 255, 168, 71, 255 })
        elseif skillId == 2004 then
            self:DrawImage("skill:sanctuary", effect.x - radius, effect.y - radius, radius * 2, radius * 2, alpha, { 255, 236, 143, 255 })
            nvgBeginPath(ctx)
            nvgCircle(ctx, effect.x, effect.y, radius * (0.55 + t * 0.35))
            nvgFillPaint(ctx, nvgRadialGradient(ctx, effect.x, effect.y, 2, radius, nvgRGBA(255, 244, 168, math.floor(95 * alpha)), nvgRGBA(255, 192, 53, 0)))
            nvgFill(ctx)
        elseif skillId == 2005 then
            local fall = (1 - t) * radius * 1.15
            self:DrawRotatedImage("skill:holy_sword", effect.x, effect.y - fall - radius * 0.16, radius * 0.48, radius * 0.86, 0, alpha, { 255, 226, 107, 255 })
            nvgBeginPath(ctx)
            nvgCircle(ctx, effect.x, effect.y, radius * (0.24 + t * 0.38))
            nvgStrokeColor(ctx, nvgRGBA(255, 232, 137, math.floor(230 * alpha)))
            nvgStrokeWidth(ctx, 3)
            nvgStroke(ctx)
        elseif skillId == 2006 then
            self:DrawRotatedImage("skill:holy_sword", effect.x, effect.y, radius * 0.44, radius * 0.78, t * 0.7, alpha, { 255, 238, 150, 255 })
        elseif skillId == 2007 then
            local height = radius * (1.25 + t * 0.55)
            self:DrawImage("skill:nature", effect.x - height * 0.23, effect.y - height * 0.76, height * 0.46, height, alpha, { 151, 231, 112, 255 })
            self:DrawImage("skill:nature_spike", effect.x - radius * 0.25, effect.y - radius * 0.52, radius * 0.5, radius, alpha, { 151, 231, 112, 255 })
        elseif skillId == 2008 then
            local size = radius * (1.08 + math.sin(t * math.pi) * 0.35)
            local frame = math.max(1, math.min(9, math.floor(t * 8) + 1))
            self:DrawRotatedImage("skill:fire:" .. tostring(frame), effect.x, effect.y, size, size, -0.4 + t * 1.7, alpha, { 255, 106, 37, 255 })
            for claw = -1, 1 do
                local ox = claw * radius * 0.2
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, effect.x - radius * 0.42 + ox, effect.y + radius * 0.34)
                nvgLineTo(ctx, effect.x + radius * 0.36 + ox, effect.y - radius * 0.42)
                nvgStrokeColor(ctx, nvgRGBA(255, 209, 82, math.floor(230 * alpha)))
                nvgStrokeWidth(ctx, 3)
                nvgStroke(ctx)
            end
        elseif skillId == 2009 then
            local pulse = 1 + math.sin(t * math.pi) * 0.45
            self:DrawImage("skill:seed", effect.x - radius * 0.2 * pulse, effect.y - radius * 0.2 * pulse, radius * 0.4 * pulse, radius * 0.4 * pulse, alpha)
            nvgBeginPath(ctx)
            nvgCircle(ctx, effect.x, effect.y, radius * (0.25 + t * 0.65))
            nvgStrokeColor(ctx, nvgRGBA(110, 226, 106, math.floor(230 * alpha)))
            nvgStrokeWidth(ctx, 3)
            nvgStroke(ctx)
        end
    end
end

function Renderer:DrawMessage(width)
    if self.battle.messageTimer <= 0 or self.battle.state ~= "running" then
        return
    end
    local ctx = self.context
    nvgFontFace(ctx, "nightgate-pixel-bold")
    nvgFontSize(ctx, 23)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 190))
    nvgText(ctx, width * 0.5 + 2, 34, self.battle.message, nil)
    nvgFillColor(ctx, rgba(Config.COLORS.text))
    nvgText(ctx, width * 0.5, 32, self.battle.message, nil)
end

function Renderer:Render()
    if self.battle.state ~= "running" then
        return
    end
    local width, height, pixelRatio = self:UpdateViewport()
    self.battle:SetArena(UIData.arena.x, UIData.arena.y, UIData.arena.size)
    local arena = self.battle.arena
    local elapsed = GetTime():GetElapsedTime()

    nvgBeginFrame(self.context, width, height, pixelRatio)
    -- Extend the battlefield artwork into any aspect-ratio margins instead of
    -- exposing black bars around the 1920x1080 reference composition.
    self:DrawOutdoor(width, height)
    nvgSave(self.context)
    nvgTranslate(self.context, self.viewport.offsetX, self.viewport.offsetY)
    nvgScale(self.context, self.viewport.scale, self.viewport.scale)
    self:DrawOutdoor(UIData.designWidth, UIData.designHeight)
    self:DrawMapDecorations()
    self:DrawArenaGround(arena)
    self:DrawPortal(arena, elapsed)
    self:DrawDefenders(elapsed)
    self:DrawEnemies()
    self:DrawProjectiles()
    self:DrawCursor()
    self:DrawVFX()
    self:DrawCoins()
    self:DrawMessage(UIData.designWidth)
    nvgRestore(self.context)
    nvgEndFrame(self.context)
end

function Renderer:Destroy()
    if self.context then
        nvgDelete(self.context)
        self.context = nil
    end
end

return Renderer
