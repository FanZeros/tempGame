local Config = require("diggin.Config")
local AbyssRunTools = require("diggin.AbyssRunTools")
local AbyssPassives = require("diggin.AbyssPassives")
local AbyssInscriptions = require("diggin.AbyssInscriptions")

local AbyssProgressionRenderer = {}

local function drawMerchantChoice(renderer, app, choice)
    local abyss, tower = app.abyss, app.abyss.tower
    renderer:FillRect(0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT, { 8, 5, 14, 215 })
    local x, y, w, h = 12, 24, 456, 226
    renderer:FillRect(x + 3, y + 3, w, h, Config.Palette.shadow)
    renderer:FillRect(x, y, w, h, { 27, 21, 38, 252 })
    renderer:StrokeRect(x, y, w, h, Config.Palette.cyan, 2)
    if renderer.DrawImage then
        renderer:DrawImage(Config.Paths.abyssMerchantShopkeeper, x + 5, y + 2, 60, 40, 1)
    end
    renderer:Text(choice.title or "深渊商人", 240, y + 13, 12, Config.Palette.cream,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    renderer:Text(string.format("金币 %d · 已购 %d/%d · 每件道具3个铭刻位",
        tower and tower.coins or 0, abyss.inscriptionShopPurchases or 0,
        Config.Abyss.inscriptionShopPurchaseLimit), 240, y + 29, 6, Config.Palette.creamDim,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for index, option in ipairs(choice.options or {}) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local cardX, cardY, cardW, cardH = x + 12 + column * 222, y + 39 + row * 70, 210, 64
        local color = option.color or Config.Palette.purple
        local coins = tower and tower.coins or 0
        local definition = AbyssInscriptions.GetDefinition(option.inscriptionId)
        local available = definition and AbyssInscriptions.IsCompatible(definition, option.toolKey)
            and not AbyssInscriptions.HasCategory(abyss, option.toolKey, definition.category)
            and not AbyssInscriptions.Has(abyss, option.toolKey, option.inscriptionId)
            and AbyssInscriptions.GetSlotCount(abyss, option.toolKey) < AbyssInscriptions.MAX_SLOTS_PER_TOOL
        local price = AbyssInscriptions.GetPrice(abyss, option.toolKey, option.inscriptionId)
        local enabled = not option.sold and available and coins >= price
            and (abyss.inscriptionShopPurchases or 0) < Config.Abyss.inscriptionShopPurchaseLimit
        renderer:FillRect(cardX + 2, cardY + 2, cardW, cardH, Config.Palette.shadow)
        renderer:FillRect(cardX, cardY, cardW, cardH, option.sold and { 30, 27, 34, 245 } or { 39, 31, 52, 250 })
        renderer:StrokeRect(cardX, cardY, cardW, cardH, enabled and color or Config.Palette.inkSoft, 1)
        renderer:DrawSheetCell(Config.Paths.abyssInscriptionAtlas, 5, 5, option.inscriptionIndex,
            cardX + 7, cardY + 7, 30, 30, option.sold and 0.25 or 1)
        renderer:Text(option.name, cardX + 44, cardY + 11, 9, enabled and color or Config.Palette.creamDim)
        renderer:Text(option.toolName .. " · 刻槽 "
            .. tostring(AbyssInscriptions.GetSlotCount(abyss, option.toolKey)) .. "/3",
            cardX + 44, cardY + 23, 6, Config.Palette.creamDim)
        renderer:TextBox(option.description, cardX + 44, cardY + 31, 104, 6,
            Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local actionX, actionY, actionW, actionH = cardX + 151, cardY + 20, 52, 24
        renderer:FillRect(actionX, actionY, actionW, actionH,
            enabled and { color[1], color[2], color[3], 58 } or { 38, 34, 44, 220 })
        renderer:StrokeRect(actionX, actionY, actionW, actionH, enabled and color or Config.Palette.inkSoft, 1)
        renderer:Text(option.sold and "已售" or (not available and "不可刻入" or ("购买 " .. tostring(price))),
            actionX + actionW * 0.5, actionY + actionH * 0.5, 7,
            enabled and Config.Palette.cream or Config.Palette.creamDim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.hudButtons["abyss_choice:" .. option.id] = {
            x = cardX, y = cardY, w = cardW, h = cardH, enabled = enabled,
        }
    end
    if #(choice.options or {}) == 0 then
        renderer:Text("当前道具没有可用铭刻 · 可先补充燃料后继续下潜", 240, y + 104, 8,
            Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end

    local buttonY, buttonW, buttonH = y + h - 27, 116, 19
    local fuelCost = tower and tower:GetShopCost(choice.floor) or 0
    local fuelEnabled = tower and not tower.merchantFuelPurchased
        and app.fuel < app.maxFuel and (tower.coins or 0) >= fuelCost
    local rerollCost = AbyssInscriptions.GetRerollCost(abyss)
    local rerollEnabled = tower and (tower.coins or 0) >= rerollCost and #(choice.options or {}) > 0
        and (abyss.inscriptionShopPurchases or 0) < Config.Abyss.inscriptionShopPurchaseLimit
    local controls = {
        { id = "abyss_merchant_fuel", x = x + 12, label = tower and tower.merchantFuelPurchased
            and "燃料已补充" or ("补充燃料 " .. tostring(fuelCost)), enabled = fuelEnabled, color = Config.Palette.green },
        { id = "abyss_merchant_reroll", x = x + 170, label = "刷新商品 " .. tostring(rerollCost),
            enabled = rerollEnabled, color = Config.Palette.cyan },
        { id = "abyss_merchant_close", x = x + 328, label = "关闭商店", enabled = true, color = Config.Palette.creamDim },
    }
    for _, button in ipairs(controls) do
        local color = button.enabled and button.color or Config.Palette.inkSoft
        renderer:FillRect(button.x, buttonY, buttonW, buttonH,
            button.enabled and { color[1], color[2], color[3], 48 } or { 38, 34, 44, 220 })
        renderer:StrokeRect(button.x, buttonY, buttonW, buttonH, color, 1)
        renderer:Text(button.label, button.x + buttonW * 0.5, buttonY + buttonH * 0.5, 7,
            button.enabled and Config.Palette.cream or Config.Palette.creamDim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.hudButtons[button.id] = { x = button.x, y = buttonY, w = buttonW, h = buttonH, enabled = button.enabled }
    end
end

local function drawChoice(renderer, app)
    local choice = app.abyss.choice
    if not choice then return end
    if choice.kind == "merchant_shop" then return drawMerchantChoice(renderer, app, choice) end
    renderer:FillRect(0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT, { 8, 5, 14, 205 })
    local x, y, w, h = 14, 44, 452, 180
    renderer:FillRect(x + 3, y + 3, w, h, Config.Palette.shadow)
    renderer:FillRect(x, y, w, h, { 27, 21, 38, 252 })
    renderer:StrokeRect(x, y, w, h, Config.Palette.cyan, 2)
    renderer:Text(choice.title, 240, y + 11, 12, Config.Palette.cream,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local count = #choice.options
    local cardW = count == 2 and 188 or 134
    local gap = count == 2 and 16 or 10
    local total = cardW * count + gap * (count - 1)
    local startX = math.floor((Config.DESIGN_WIDTH - total) * 0.5)
    for index, option in ipairs(choice.options) do
        local cardX, cardY = startX + (index - 1) * (cardW + gap), y + 31
        local color = option.color or Config.Palette.purple
        renderer:FillRect(cardX + 2, cardY + 2, cardW, 107, Config.Palette.shadow)
        renderer:FillRect(cardX, cardY, cardW, 107, { 39, 31, 52, 250 })
        renderer:StrokeRect(cardX, cardY, cardW, 107, color, 1)
        renderer:Text(option.name, cardX + cardW * 0.5, cardY + 14, 10, color,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if option.inscriptionIndex then
            renderer:DrawSheetCell(Config.Paths.abyssInscriptionAtlas, 5, 5, option.inscriptionIndex,
                cardX + cardW * 0.5 - 13, cardY + 21, 26, 26, 1)
        elseif choice.kind == "route" and option.iconIndex then
            renderer:DrawSheetCell(Config.Paths.abyssTowerRouteIcons, 3, 1, option.iconIndex,
                cardX + cardW * 0.5 - 13, cardY + 22, 26, 26, 1)
        elseif option.iconIndex then
            renderer:DrawSheetCell(Config.Paths.abyssWorldItemAtlas, 5, 2, option.iconIndex,
                cardX + cardW * 0.5 - 12, cardY + 22, 24, 24, 1)
        elseif option.icon == Config.Paths.abyssTowerShop then
            renderer:DrawSheetCell(option.icon, 3, 2, 1, cardX + cardW * 0.5 - 12, cardY + 23, 24, 24, 1)
        elseif option.icon then
            renderer:DrawImage(option.icon, cardX + cardW * 0.5 - 12, cardY + 22, 24, 24, 1)
        end
        if option.maxLevel then
            renderer:Text(string.format("%s Lv.%d/%d", option.slotType or "强化", option.nextLevel or 1,
                option.maxLevel), cardX + cardW * 0.5, cardY + 49, 6, color,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
        if option.inscription then
            local slots = AbyssInscriptions.GetSlotCount(app.abyss, option.toolKey)
            renderer:Text(string.format("%s · 刻槽 %d/%d", option.toolName, slots,
                AbyssInscriptions.MAX_SLOTS_PER_TOOL), cardX + cardW * 0.5, cardY + 50, 6,
                color, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
        if option.capstoneId then renderer:Text("◆ 局内终极专武", cardX + cardW * 0.5, cardY + 31, 7, Config.Palette.gold,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE) end
        local hasLargeIcon = option.inscriptionIndex ~= nil
            or (choice.kind == "route" and option.iconIndex) or option.icon ~= nil
        local descriptionY = option.inscription and 57
            or (option.maxLevel and 57
            or (hasLargeIcon and 51 or (option.capstoneId and 42 or 31)))
        renderer:TextBox(option.description, cardX + 9, cardY + descriptionY, cardW - 18, 7,
            Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        if option.synergyText then
            renderer:Text(option.synergyText, cardX + 9, cardY + 73, 6, Config.Palette.cyan)
        end
        local optionEnabled = not option.inscription
            or (((app.abyss.tower and app.abyss.tower.coins) or 0) >= (option.cost or 0)
                and (app.abyss.inscriptionShopPurchases or 0) < Config.Abyss.inscriptionShopPurchaseLimit)
        local buttonColor = optionEnabled and color or Config.Palette.inkSoft
        renderer:FillRect(cardX + 9, cardY + 81, cardW - 18, 18,
            { buttonColor[1], buttonColor[2], buttonColor[3], optionEnabled and 55 or 30 })
        renderer:StrokeRect(cardX + 9, cardY + 81, cardW - 18, 18, buttonColor, 1)
        local actionLabel = "选择"
        if option.inscription then
            actionLabel = "购买 " .. tostring(option.cost or 0)
        end
        renderer:Text(actionLabel,
            cardX + cardW * 0.5, cardY + 90, 8, Config.Palette.cream,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.hudButtons["abyss_choice:" .. option.id] = {
            x = cardX, y = cardY, w = cardW, h = 107, enabled = optionEnabled,
        }
    end
    local rerollable = choice.kind == "build" or choice.kind == "tool" or choice.kind == "passive"
        or choice.kind == "weapon" or choice.kind == "reward" or choice.kind == "boon"
    local status = string.format("道具 %d/%d · 被动 %d/%d · 刷新 %d",
        AbyssRunTools.GetSlotCount(app.abyss), AbyssRunTools.MAX_SLOTS,
        AbyssPassives.GetSlotCount(app.abyss), AbyssPassives.MAX_SLOTS, app.abyss.rerolls or 0)
    if choice.kind == "route" then status = "构筑间隔：前30层每3层，至100层每5层，之后每10层"
    elseif choice.hardcoreStarter then status = "硬核保障：第1层开打前先获得1件局内道具"
    elseif choice.kind == "inscription_shop" then
        status = string.format("金币 %d · 本店已购 %d/%d · 每件道具最多3枚铭刻",
            (app.abyss.tower and app.abyss.tower.coins) or 0,
            app.abyss.inscriptionShopPurchases or 0, Config.Abyss.inscriptionShopPurchaseLimit)
    end
    renderer:Text(status, 240, y + h - 30, 6, Config.Palette.creamDim,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if choice.kind ~= "inscription_shop" then
        -- Center the emergency action instead of placing it over the left
        -- movement joystick's muscle-memory position.
        local rescueW, rescueH = 91, 16
        local rescueX, rescueY = math.floor((Config.DESIGN_WIDTH - rescueW) * 0.5), y + h - 20
        renderer:FillRect(rescueX, rescueY, rescueW, rescueH, { 66, 39, 49, 245 })
        renderer:StrokeRect(rescueX, rescueY, rescueW, rescueH, Config.Palette.gold, 1)
        renderer:Text("卡住？保底继续", rescueX + rescueW * 0.5, rescueY + rescueH * 0.5, 7,
            Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.hudButtons.abyss_choice_recover = {
            x = rescueX, y = rescueY, w = rescueW, h = rescueH, enabled = true,
        }
    end
    if choice.kind == "inscription_shop" then
        local leaveX, buttonY, buttonW, buttonH = x + 10, y + h - 20, 92, 16
        renderer:FillRect(leaveX, buttonY, buttonW, buttonH, { 54, 45, 60, 245 })
        renderer:StrokeRect(leaveX, buttonY, buttonW, buttonH, Config.Palette.creamDim, 1)
        renderer:Text("不购买 · 继续", leaveX + buttonW * 0.5, buttonY + buttonH * 0.5, 7,
            Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.hudButtons.abyss_shop_leave = {
            x = leaveX, y = buttonY, w = buttonW, h = buttonH, enabled = true,
        }
        local rerollCost = AbyssInscriptions.GetRerollCost(app.abyss)
        local rerollX = x + w - buttonW - 10
        local rerollEnabled = ((app.abyss.tower and app.abyss.tower.coins) or 0) >= rerollCost
        renderer:FillRect(rerollX, buttonY, buttonW, buttonH,
            rerollEnabled and { 28, 68, 79, 245 } or { 39, 34, 44, 220 })
        renderer:StrokeRect(rerollX, buttonY, buttonW, buttonH,
            rerollEnabled and Config.Palette.cyan or Config.Palette.inkSoft, 1)
        renderer:Text("刷新货架 " .. tostring(rerollCost), rerollX + buttonW * 0.5,
            buttonY + buttonH * 0.5, 7, rerollEnabled and Config.Palette.cream
                or Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.hudButtons.abyss_shop_reroll = {
            x = rerollX, y = buttonY, w = buttonW, h = buttonH, enabled = rerollEnabled,
        }
    end
    if rerollable then
        local bx, by, bw, bh = x + w - 100, y + h - 20, 90, 16
        local freeRerolls = app.abyss.rerolls or 0
        local hasFreeReroll = freeRerolls > 0
        local canAdReroll = not hasFreeReroll and app.abyss.adRerollUsed ~= true
            and not app.abyss:IsHardcore()
        local pending = app.abyssRerollAdPending == true
        local enabled = not app.adPending and (hasFreeReroll or canAdReroll)
        local buttonId = hasFreeReroll and "abyss_reroll" or "abyss_reroll_ad"
        local label
        if pending then label = "广告播放中…"
        elseif hasFreeReroll then label = "刷新 ×" .. tostring(freeRerolls)
        elseif app.abyss:IsHardcore() then label = "硬核禁用刷新"
        elseif app.abyss.adRerollUsed then label = "额外刷新已用"
        else label = "看广告额外刷新" end
        renderer:FillRect(bx, by, bw, bh, enabled and { 28, 68, 79, 245 } or { 39, 34, 44, 220 })
        renderer:StrokeRect(bx, by, bw, bh, enabled and Config.Palette.cyan or Config.Palette.inkSoft, 1)
        renderer:Text(label, bx + bw * 0.5, by + bh * 0.5, 7,
            enabled and Config.Palette.cream or Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.hudButtons[buttonId] = { x = bx, y = by, w = bw, h = bh, enabled = enabled }
    end
end

local function drawDodge(renderer, app)
    if app.abyss.choice then return end
    local x, y, w, h = 306, 232, 58, 26
    local cooldown = math.max(0, app.abyss.dodgeCooldown or 0)
    local ready = cooldown <= 0
    local color = ready and Config.Palette.cyan or Config.Palette.inkSoft
    renderer:FillRect(x + 2, y + 2, w, h, Config.Palette.shadow)
    renderer:FillRect(x, y, w, h, { 22, 29, 42, 235 })
    renderer:StrokeRect(x, y, w, h, color, ready and 2 or 1)
    local frame = math.floor(renderer.time * 12) % 8 + 1
    renderer:DrawSheetCell(Config.Paths.abyssTowerBlink, 4, 2, frame, x + 3, y + 3, 20, 20, ready and 1 or 0.3)
    renderer:Text(ready and "闪现" or string.format("%.1fs", cooldown), x + 39, y + h * 0.5,
        8, ready and Config.Palette.cream or Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- Keep the cooldown button touchable so a tap is consumed instead of
    -- falling through to the full-screen drill gesture underneath it.
    renderer.hudButtons.abyss_dodge = { x = x, y = y, w = w, h = h, enabled = true }
end

function AbyssProgressionRenderer.Draw(renderer, app)
    drawDodge(renderer, app)
    drawChoice(renderer, app)
end

return AbyssProgressionRenderer
