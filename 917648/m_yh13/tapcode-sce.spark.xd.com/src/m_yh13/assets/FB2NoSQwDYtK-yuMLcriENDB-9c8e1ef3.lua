local Config = require("diggin.Config")
local Util = require("diggin.Util")
local WorldTree = require("diggin.WorldTree")
local AbyssItems = require("diggin.AbyssItems")
local AbyssLoot = require("diggin.AbyssLoot")
local AbyssRunTools = require("diggin.AbyssRunTools")
local AbyssProgressionRenderer = require("diggin.AbyssProgressionRenderer")
local AbyssPortalSchedule = require("diggin.AbyssPortalSchedule")

local AbyssRenderer = {}

local function timeText(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function merchantButtonRect(renderer, app)
    local tower = app.abyss and app.abyss.tower
    if not tower or not tower.shopFloor or app.abyss.choice then return nil end
    -- A fixed design-space target is intentionally used here.  The merchant
    -- sprite lives in world space and can sit underneath a mobile joystick or
    -- even outside the visible camera while entering the room.  Keeping the
    -- primary action in the safe centre makes it reliable on every aspect
    -- ratio after the physical-to-design coordinate conversion.
    return { x = 176, y = 120, w = 128, h = 28, enabled = true }
end

-- DrawWorldOverlay runs before Renderer:DrawHud, whose first step clears the
-- HUD button table. Register the merchant here, from the final HUD phase, so
-- the visible terminal always retains a live touch target on mobile.
function AbyssRenderer.RegisterMerchantButton(renderer, app)
    local rect = merchantButtonRect(renderer, app)
    if not rect then return false end
    renderer.hudButtons = renderer.hudButtons or {}
    renderer.hudButtons.abyss_merchant = rect
    local tower = app.abyss.tower
    local sx, sy = renderer:WorldToScreen(app.player, tower.merchantX, tower.merchantY)
    -- Keep direct taps on the merchant working too.  App gives both merchant
    -- targets priority over the movement pads when rectangles overlap.
    renderer.hudButtons.abyss_merchant_world = {
        x = sx - 46, y = sy - 38, w = 92, h = 68, enabled = true,
    }
    return true
end

local function drawAtmosphere(renderer, app)
    local intensity = Util.Clamp((app.runDepth or 0) / 260, 0.12, 0.72)
    nvgBeginPath(renderer.vg)
    nvgRect(renderer.vg, 0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT)
    nvgFillPaint(renderer.vg, nvgLinearGradient(renderer.vg, 0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT,
        nvgRGBA(48, 8, 72, math.floor(24 + intensity * 24)),
        nvgRGBA(4, 74, 94, math.floor(8 + intensity * 22))))
    nvgFill(renderer.vg)
    for index = 1, 22 do
        local x = math.floor(Util.Hash01(index, 9, 771) * Config.DESIGN_WIDTH)
        local drift = renderer.time * (4 + index % 5)
        local y = math.floor((Util.Hash01(index, 11, 991) * Config.DESIGN_HEIGHT + drift) % Config.DESIGN_HEIGHT)
        local color = index % 3 == 0 and Config.Palette.cyan or Config.Palette.purple
        renderer:FillRect(x, y, index % 7 == 0 and 2 or 1, 1,
            { color[1], color[2], color[3], math.floor(70 + intensity * 100) })
    end
end

local function drawTowerWorld(renderer, app)
    local tower = app.abyss and app.abyss.tower
    if not tower then return end
    if tower.exitOpen then
        local sx, sy = renderer:WorldToScreen(app.player,
            tower.exitX * Config.TILE_SIZE + 8, tower.exitY * Config.TILE_SIZE + 8)
        local frame = math.floor(renderer.time * 11) % 8 + 1
        local portalW = Config.TILE_SIZE * (Config.Abyss.exitHalfWidthTiles * 2 + 1)
        renderer:DrawSheetCell(Config.Paths.abyssTowerExit, 4, 2, frame,
            sx - portalW * 0.5, sy - portalW * 0.62, portalW, portalW * 1.12, 1)
    end
    if tower.shopFloor then
        local sx, sy = renderer:WorldToScreen(app.player, tower.merchantX, tower.merchantY)
        local frame = math.floor(renderer.time * 4) % 6 + 1
        renderer:DrawSheetCell(Config.Paths.abyssTowerShop, 3, 2, frame, sx - 18, sy - 30, 36, 36, 1)
        renderer:FillRect(sx - 39, sy + 8, 78, 14, { 19, 16, 28, 235 })
        renderer:StrokeRect(sx - 39, sy + 8, 78, 14, Config.Palette.cyan, 1)
        renderer:Text("商人 · 点击交易", sx, sy + 15, 7, Config.Palette.cream,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    local flash = tower.flashFx
    if flash then
        local age = 1 - Util.Clamp(flash.life / flash.maxLife, 0, 1)
        local frame = math.min(8, math.floor(age * 8) + 1)
        for _, point in ipairs({ { flash.x, flash.y }, { flash.toX, flash.toY } }) do
            local sx, sy = renderer:WorldToScreen(app.player, point[1], point[2])
            renderer:DrawSheetCell(Config.Paths.abyssTowerBlink, 4, 2, frame, sx - 18, sy - 18, 36, 36, 1)
        end
    end
    for _, pickup in ipairs(tower.pickups or {}) do
        local sx, sy = renderer:WorldToScreen(app.player, pickup.x, pickup.y)
        if pickup.kind == "coin" then
            renderer:DrawImage(Config.Paths.abyssTowerCoin, sx - 7, sy - 7, 14, 14, 1)
            if pickup.amount > 1 then renderer:Text("×" .. tostring(pickup.amount), sx + 7, sy, 6,
                Config.Palette.gold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE) end
        else
            local frame = math.floor(renderer.time * 9) % 8 + 1
            renderer:DrawSheetCell(Config.Paths.abyssTowerFuel, 4, 2, frame, sx - 8, sy - 8, 16, 16, 1)
        end
    end
    for _, enemy in ipairs(tower.enemies or {}) do
        local sx, sy = renderer:WorldToScreen(app.player, enemy.x, enemy.y)
        local size = enemy.size or 16
        renderer:DrawImage(enemy.path, sx - size * 0.5, sy - size * 0.5, size, size, 1)
        local ratio = Util.Clamp(enemy.hp / math.max(1, enemy.maxHp), 0, 1)
        renderer:FillRect(sx - size * 0.5, sy - size * 0.5 - 4, size, 2, { 25, 12, 18, 220 })
        renderer:FillRect(sx - size * 0.5, sy - size * 0.5 - 4, size * ratio, 2,
            ratio < 0.35 and Config.Palette.red or Config.Palette.green)
    end
    for _, shot in ipairs(tower.projectiles or {}) do
        local sx, sy = renderer:WorldToScreen(app.player, shot.x, shot.y)
        local frame = math.floor(shot.frame or 0) % 8 + 1
        renderer:DrawSheetCell(Config.Paths.abyssTowerProjectile, 4, 2, frame, sx - 7, sy - 7, 14, 14, 1)
    end
    for _, burst in ipairs(tower.bursts or {}) do
        local sx, sy = renderer:WorldToScreen(app.player, burst.x, burst.y)
        local age = 1 - Util.Clamp(burst.life / burst.maxLife, 0, 1)
        local frame = math.min(4, math.floor(age * 4) + 1)
        renderer:DrawSheetCell(Config.Paths.abyssTowerEnemyBurst, 2, 2, frame, sx - 18, sy - 18, 36, 36,
            Util.Clamp(burst.life / burst.maxLife, 0, 1))
    end
end

local function drawAbyssAttackWarning(renderer, app)
    local attack = app.abyss:GetBossAttack()
    if not attack then return end
    local remaining = math.max(0, attack.timer or 0)
    local pulse = math.floor(renderer.time * 12) % 2 == 0
    local alpha = pulse and 250 or 175
    local labelX, labelY = 240, 96
    for index, zone in ipairs(attack.zones or { attack }) do
        local x, y, w, h
        if zone.shape == "column" then
            local sx = renderer:WorldToScreen(app.player, zone.x, app.player.y)
            x, y, w, h = sx - zone.halfWidth, 1, zone.halfWidth * 2, Config.DESIGN_HEIGHT - 2
        elseif zone.shape == "band" then
            local _, sy = renderer:WorldToScreen(app.player, app.player.x, zone.y)
            x, y, w, h = 1, sy - zone.halfHeight, Config.DESIGN_WIDTH - 2, zone.halfHeight * 2
        else
            local sx, sy = renderer:WorldToScreen(app.player, zone.x, zone.y)
            x, y, w, h = sx - zone.radius, sy - zone.radius, zone.radius * 2, zone.radius * 2
        end
        renderer:FillRect(x, y, w, h, { 225, 20, 35, pulse and 42 or 24 })
        renderer:StrokeRect(x, y, w, h, { 255, 46, 58, alpha }, pulse and 2 or 1)
        renderer:StrokeRect(x + 3, y + 3, math.max(6, w - 6), math.max(6, h - 6),
            { 255, 190, 80, math.floor(alpha * 0.62) }, 1)
        if index == 1 then
            labelX = Util.Clamp(x + w * 0.5, 76, Config.DESIGN_WIDTH - 76)
            labelY = Util.Clamp(y + 4, 92, Config.DESIGN_HEIGHT - 18)
        end
    end
    renderer:Text(string.format("深渊 · %s · %.1fs", attack.name, remaining),
        labelX, labelY, 8,
        { 255, 230, 205, alpha }, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
end

function AbyssRenderer.DrawWorldOverlay(renderer, app)
    if not app.abyss or not app.abyss.active then return end
    drawAtmosphere(renderer, app)
    drawTowerWorld(renderer, app)
    local tower = app.abyss.tower
    if tower and tower.shopFloor then
        renderer:StrokeRect(2, 2, Config.DESIGN_WIDTH - 4, Config.DESIGN_HEIGHT - 4,
            { 70, 220, 205, 90 }, 1)
        return
    end
    if tower and tower.hordeActive and not tower.hordeRewardGranted
        and math.floor(renderer.time * 6) % 2 == 0 then
        renderer:StrokeRect(2, 2, Config.DESIGN_WIDTH - 4, Config.DESIGN_HEIGHT - 4,
            { 240, 55, 45, 145 }, 2)
    end
    local gap = app.abyss:GetGap(app.player.y)
    local warningGap = Config.Abyss.warningGap + WorldTree.GetStat(app.state, "warning_gap")
    local danger = Util.Clamp((warningGap - gap) / warningGap, 0, 1)
    local teethY = Config.DESIGN_HEIGHT * 0.5 - gap
    local width, height = 226, 109
    local bob = math.sin(renderer.time * 3.2) * 2
    local x = (Config.DESIGN_WIDTH - width) * 0.5
    local y = teethY - height * 0.72 + bob

    nvgBeginPath(renderer.vg)
    nvgRect(renderer.vg, 0, 0, Config.DESIGN_WIDTH, 102)
    nvgFillPaint(renderer.vg, nvgLinearGradient(renderer.vg, 0, 0, 0, 102,
        nvgRGBA(70 + math.floor(80 * danger), 8, 28, 210), nvgRGBA(18, 8, 25, 0)))
    nvgFill(renderer.vg)
    renderer:DrawImage(Config.Paths.abyssChaser, x, y, width, height, 1)

    if danger > 0 then
        renderer:FillRect(0, math.floor(teethY), Config.DESIGN_WIDTH, 1,
            { 225, 59, 62, math.floor(80 + danger * 170) })
        if math.floor(renderer.time * 8) % 2 == 0 then
            renderer:StrokeRect(1, 1, Config.DESIGN_WIDTH - 2, Config.DESIGN_HEIGHT - 2,
                { 225, 59, 62, math.floor(danger * 180) }, 2)
        end
    end
    drawAbyssAttackWarning(renderer, app)
end

local function drawLootLoadout(renderer, app)
    local x, y, w, h = 318, 31, 150, 38
    renderer:FillRect(x + 2, y + 2, w, h, Config.Palette.shadow)
    renderer:FillRect(x, y, w, h, { 23, 18, 34, 238 })
    renderer:StrokeRect(x, y, w, h, Config.Palette.cyan, 1)
    renderer:Text("深渊装备 · 晶尘 " .. tostring(app.state.abyssDust or 0), x + 5, y + 3, 6,
        Config.Palette.creamDim)
    for index, entry in ipairs(AbyssLoot.GetLoadout(app.state)) do
        local slotX, slotY = x + 5 + (index - 1) * 35, y + 13
        local color = entry.grade and AbyssLoot.GetGradeColor(entry.grade.id, renderer.time)
            or { 68, 61, 78, 255 }
        renderer:FillRect(slotX, slotY, 30, 20, { 12, 10, 18, 230 })
        renderer:StrokeRect(slotX, slotY, 30, 20, color, 1)
        if entry.grade and entry.grade.glow then
            nvgBeginPath(renderer.vg)
            nvgCircle(renderer.vg, slotX + 10, slotY + 10, entry.grade.prismatic and 13 or 10)
            nvgFillPaint(renderer.vg, nvgRadialGradient(renderer.vg, slotX + 10, slotY + 10, 1, 13,
                Util.Color(color, 135), Util.Color(color, 0)))
            nvgFill(renderer.vg)
        end
        renderer:DrawSheetCell(Config.Paths.abyssEquipmentAtlas, 5, 4, entry.iconIndex, slotX + 1, slotY + 1, 18, 18,
            entry.grade and 1 or 0.2)
        renderer:Text(entry.gradeId or "-", slotX + 27, slotY + 10, entry.gradeId == "SSS" and 5 or 6,
            color, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        renderer.hudButtons["abyss_loot_info:" .. entry.slot.id] = {
            x = slotX, y = slotY, w = 30, h = 20, enabled = true,
        }
    end
end

function AbyssRenderer.DrawHud(renderer, app)
    if not app.abyss or not app.abyss.active then return end
    local merchantVisible = AbyssRenderer.RegisterMerchantButton(renderer, app)
    local x, y, w, h = 167, 31, 146, 38
    local gap = math.max(0, math.floor(app.abyss:GetGap(app.player.y)))
    renderer:FillRect(x + 2, y + 2, w, h, Config.Palette.shadow)
    renderer:FillRect(x, y, w, h, { 31, 20, 40, 238 })
    local warningGap = Config.Abyss.warningGap + WorldTree.GetStat(app.state, "warning_gap")
    renderer:StrokeRect(x, y, w, h, gap < warningGap and Config.Palette.red or Config.Palette.purple, 1)
    local modeName = app.abyss:IsHardcore() and "硬核" or "无尽"
    renderer:Text(string.format("%s %d层·难度%d", modeName, app.abyss:GetFloor(),
        app.abyss:GetDifficultyStage() + 1), x + 7, y + 5, 7,
        app.abyss:IsHardcore() and Config.Palette.red or Config.Palette.cream)
    renderer:DrawImage(Config.Paths.worldTreePoint, x + 82, y + 4, 11, 11, 1)
    renderer:Text("+" .. tostring(app.abyss.projectedPoints or 0), x + 96, y + 10, 8,
        Config.Palette.cyan, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    renderer:Text(string.format("距 %d · %.1f/s", gap, app.abyss:GetCurrentSpeed()), x + w - 6, y + 10, 6,
        gap < warningGap and Config.Palette.red or Config.Palette.creamDim,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)

    local mutation = app.abyss:GetMutation()
    if mutation then
        renderer:DrawImage(mutation.icon, x + 5, y + 19, 15, 15, 1)
        renderer:Text(mutation.name .. " · " .. mutation.description, x + 24, y + 27, 6,
            mutation.color, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    else
        renderer:Text(string.format("下一点 %.1fs · 异变即将出现", app.abyss:GetSecondsToNextPoint()),
            x + 7, y + 27, 6, Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end

    if not app.hudCollapsed then drawLootLoadout(renderer, app) end

    local tower = app.abyss.tower
    if tower and not app.hudCollapsed then
        local tx, ty, tw, th = 112, 72, 288, 16
        renderer:FillRect(tx + 2, ty + 2, tw, th, Config.Palette.shadow)
        renderer:FillRect(tx, ty, tw, th, { 22, 18, 31, 238 })
        renderer:StrokeRect(tx, ty, tw, th, tower.exitOpen and Config.Palette.cyan or Config.Palette.gold, 1)
        renderer:DrawImage(Config.Paths.abyssTowerCoin, tx + 4, ty + 2, 12, 12, 1)
        renderer:Text(tostring(tower.coins or 0), tx + 19, ty + 8, 7, Config.Palette.gold,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        renderer:Text("得分 " .. Util.FormatNumber(app.abyss:GetRunScore()), tx + 52, ty + 8, 6, Config.Palette.cyan,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local enemyText = tower.shopFloor and "安全商店" or ("怪" .. tostring(#(tower.enemies or {})) .. "/击" .. tostring(tower.kills or 0))
        local enemyColor = Config.Palette.creamDim
        if tower.hordeActive then
            enemyText = tower.hordeRewardGranted and "兽潮已退"
                or string.format("兽潮 %d/%d", tower.hordeKills or 0, tower.hordeKillGoal or 0)
            enemyColor = tower.hordeRewardGranted and Config.Palette.gold or Config.Palette.red
        end
        renderer:Text(enemyText, tx + 143, ty + 8,
            6, enemyColor, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local exitText
        if tower.shopFloor then
            exitText = "巨物暂停 · 三格门已开"
        elseif not tower.portalFloor then
            exitText = "下个门 第" .. tostring(AbyssPortalSchedule.GetNextPortalFloor((tower.floor or 1) + 1)) .. "层"
        elseif tower.exitOpen then
            exitText = "三格传送门已开启"
        elseif tower.exitRevealed then
            exitText = "三格门 X=" .. tostring(tower.exitX)
        else
            exitText = "三格传送门未定位"
        end
        renderer:Text(exitText, tx + 190, ty + 8,
            6, tower.exitOpen and Config.Palette.cyan or Config.Palette.cream, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if tower.lastChestItem then
            renderer:DrawAtlasCell(Config.Paths.abyssTowerChestItems, tower.lastChestItem.iconIndex,
                tx + tw - 16, ty + 1, 14, 14, 1)
        end
    end

    local entries = AbyssItems.GetHudEntries(app.state, app.abyss)
    local capstoneCount = AbyssRunTools.GetEvolutionCount(app.abyss)
    local capstoneTotal = AbyssRunTools.GetEvolutionTotal()
    if #entries > 0 and not app.hudCollapsed and not app.abyssItemsCollapsed then
        local tileW, tileH, gapX = 58, 18, 4
        local totalW = #entries * tileW + (#entries - 1) * gapX
        local startX = math.floor((Config.DESIGN_WIDTH - totalW) * 0.5)
        for index, entry in ipairs(entries) do
            local itemX, itemY = startX + (index - 1) * (tileW + gapX), 92
            renderer:FillRect(itemX + 2, itemY + 2, tileW, tileH, Config.Palette.shadow)
            renderer:FillRect(itemX, itemY, tileW, tileH, { 24, 20, 34, 238 })
            renderer:StrokeRect(itemX, itemY, tileW, tileH, entry.color, 1)
            if entry.iconIndex then
                renderer:DrawSheetCell(Config.Paths.abyssWorldItemAtlas, 5, 2,
                    entry.iconIndex, itemX + 2, itemY + 2, 14, 14, 1)
            else
                renderer:DrawImage(entry.icon, itemX + 2, itemY + 2, 14, 14, 1)
            end
            renderer:Text("L" .. tostring(entry.level or 1) .. " " .. entry.status, itemX + 19, itemY + 9, 6, Config.Palette.cream,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        end
        renderer:Text(string.format("终极专武 %d/%d · 锻造 %d/3", capstoneCount, capstoneTotal,
            app.abyss.forgeProgress or 0), 240, 113, 7, Config.Palette.gold,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        renderer.hudButtons.abyss_items_toggle = { x = startX + totalW + 4, y = 92, w = 16, h = 18, enabled = true }
        renderer:FillRect(startX + totalW + 4, 92, 16, 18, { 24, 20, 34, 238 })
        renderer:StrokeRect(startX + totalW + 4, 92, 16, 18, Config.Palette.purple, 1)
        renderer:Text("×", startX + totalW + 12, 101, 10, Config.Palette.cream,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    elseif #entries > 0 and not app.hudCollapsed then
        renderer.hudButtons.abyss_items_toggle = { x = 378, y = 94, w = 42, h = 16, enabled = true }
        renderer:FillRect(378, 94, 42, 16, { 24, 20, 34, 238 })
        renderer:StrokeRect(378, 94, 42, 16, Config.Palette.purple, 1)
        renderer:Text("树具 +", 399, 102, 7, Config.Palette.gold,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    elseif not app.hudCollapsed then
        renderer:Text(string.format("终极专武 %d/%d · 锻造 %d/3", capstoneCount, capstoneTotal,
            app.abyss.forgeProgress or 0),
            240, 101, 7, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    if merchantVisible then
        local button = renderer.hudButtons.abyss_merchant
        renderer:FillRect(button.x + 3, button.y + 3, button.w, button.h, Config.Palette.shadow)
        renderer:FillRect(button.x, button.y, button.w, button.h, { 30, 27, 45, 248 })
        renderer:StrokeRect(button.x, button.y, button.w, button.h, Config.Palette.gold, 2)
        renderer:Text("打开随机商店 · 4件商品", button.x + button.w * 0.5,
            button.y + button.h * 0.5, 9, Config.Palette.cream,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    AbyssProgressionRenderer.Draw(renderer, app)
end

return AbyssRenderer
