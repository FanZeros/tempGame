local Config = require("diggin.Config")
local Util = require("diggin.Util")

local AbyssBoss = {}

local BOSSES = {
    { name = "渊口噬岩兽", color = Config.Palette.red },
    { name = "根须监察者", color = Config.Palette.green },
    { name = "轮回地龙王", color = Config.Palette.purple },
}

local ITEM_DAMAGE = {
    starcore_bomb = 28,
    amber_swarm = 18,
    chronobloom = 12,
    root_aegis = 16,
}

function AbyssBoss.Start(abyss, app, floor)
    local cycle = math.floor((floor - 1) / 10) + 1
    local template = BOSSES[((math.floor(floor / 5) - 1) % #BOSSES) + 1]
    abyss.boss = {
        active = true,
        floor = floor,
        name = template.name,
        color = template.color,
        maxHp = 100 + (cycle - 1) * 24 + math.floor(floor / 5) * 8,
        hp = 100 + (cycle - 1) * 24 + math.floor(floor / 5) * 8,
        roots = math.min(5, 2 + cycle),
        maxRoots = math.min(5, 2 + cycle),
        lockY = app.player.y,
        stagger = 0,
        itemHits = 0,
    }
    abyss.bossAttack = nil
    abyss.nextBossAttackAt = abyss.time + 1.8
    abyss.rootPauseTime = math.max(abyss.rootPauseTime or 0, 2)
    app.drillingActive = false
    if app.audio and app.audio.SetDrilling then app.audio:SetDrilling(false) end
    if app.ShowToast then
        app:ShowToast("Boss战 · " .. template.name .. " · 只能用世界树道具破盾伤害", template.color, 3.4)
    end
end

function AbyssBoss.IsActive(abyss)
    return abyss and abyss.boss and abyss.boss.active == true
end

function AbyssBoss.Update(abyss, app, dt)
    local boss = abyss and abyss.boss
    if not boss or not boss.active then return false end
    boss.stagger = math.max(0, (boss.stagger or 0) - dt)
    if app.player.y > boss.lockY then
        app.player.y = boss.lockY
        app.player.vy = math.min(0, app.player.vy or 0)
    end
    -- Keep the fight on one screen while still allowing horizontal movement,
    -- dodge and all four normal active skills.
    app.drillingActive = false
    if boss.stagger <= 0 then abyss:UpdateBossAttack(app, dt) end
    return true
end

function AbyssBoss.OnItemTriggered(abyss, app, itemId, powerMultiplier)
    local boss = abyss and abyss.boss
    if not boss or not boss.active then return false end
    local base = ITEM_DAMAGE[itemId]
    if not base then return false end
    boss.itemHits = boss.itemHits + 1
    if boss.roots > 0 then
        local removed = itemId == "starcore_bomb" and 2 or 1
        boss.roots = math.max(0, boss.roots - removed)
        abyss.rootPauseTime = math.max(abyss.rootPauseTime or 0, 3.2)
        abyss.monsterY = abyss.monsterY - 18 * removed
        if app.ShowToast then
            app:ShowToast(string.format("摧毁根须 %d/%d · 追击暂停", boss.maxRoots - boss.roots, boss.maxRoots),
                Config.Palette.green, 1.8)
        end
        return true
    end
    local damage = base * math.max(0.4, tonumber(powerMultiplier) or 1)
    boss.hp = math.max(0, boss.hp - damage)
    if app.AddBurst then app:AddBurst(app.player.x, app.player.y - 38, boss.color, 18) end
    if boss.hp <= 0 then
        boss.active = false
        abyss.bossAttack = nil
        abyss:OnBossDefeated(app, boss)
    elseif app.ShowToast then
        app:ShowToast(string.format("%s -%.0f · 剩余 %.0f%%", boss.name, damage, boss.hp / boss.maxHp * 100),
            boss.color, 1.4)
    end
    return true
end

function AbyssBoss.OnPerfectDodge(abyss, app)
    local boss = abyss and abyss.boss
    local push = boss and boss.active and 34 or 24
    abyss.monsterY = abyss.monsterY - push
    abyss.rootPauseTime = math.max(abyss.rootPauseTime or 0, 2.8)
    if boss and boss.active then
        boss.stagger = math.max(boss.stagger or 0, 2.2)
        if boss.roots > 0 then boss.roots = boss.roots - 1 end
    end
    if app.AddBurst then app:AddBurst(app.player.x, app.player.y, Config.Palette.cyan, 22) end
    if app.KickCamera then app:KickCamera(3.5, 0.25) end
    if app.ShowToast then app:ShowToast("完美闪避 · 击退巨物并打断Boss", Config.Palette.cyan, 2) end
end

function AbyssBoss.GetHpRatio(abyss)
    local boss = abyss and abyss.boss
    if not boss or not boss.active then return 0 end
    return Util.Clamp(boss.hp / math.max(1, boss.maxHp), 0, 1)
end

return AbyssBoss
