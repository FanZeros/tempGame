local Config = require("diggin.Config")
local Tree = require("diggin.WorldTree")
local Catalog = require("diggin.DrillMechanicsCatalog")
local Stats = require("diggin.RunCombatStats")
local G = {}

local function distance(a, x, y)
    return ((a.x or 0)-x)^2 + ((a.y or 0)-y)^2
end
local function hit(app, x, y, damage)
    local tile = app.world:GetTile(x,y)
    if not tile or tile.indestructible then return end
    local destroyed, result = app.world:DamageTile(tile, damage, false, "tree_drill")
    if destroyed then app:OnTileDestroyed(result,"tree_drill")
    elseif app.AddHitFlash then app:AddHitFlash(result,false) end
end
local function activate(app, d, rank, tile, dx, dy, damage)
    local abyss, tower, p = app.abyss, app.abyss.tower, app.player
    local x,y = tile.x,tile.y
    local sx,sy = math.abs(dx)>=math.abs(dy) and (dx>=0 and 1 or -1) or 0,
        math.abs(dy)>math.abs(dx) and (dy>=0 and 1 or -1) or 0
    local scale = 0.3 + math.min(10,rank)*0.035
    local radius = 40 + math.min(10,rank)*4
    local id = d.id
    if id=="cross" then
        for _,o in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do hit(app,x+o[1],y+o[2],damage*scale) end
        if rank>=3 then hit(app,x+sx*2,y+sy*2,damage*scale) end
        if rank>=6 then
            for _,o in ipairs({{-1,-1},{1,1},{1,-1}}) do hit(app,x+o[1],y+o[2],damage*scale) end
        end
    elseif id=="pierce" then
        for i=1,math.min(6,2+math.floor(rank/2)) do hit(app,x+sx*i,y+sy*i,damage*scale) end
    elseif id=="fan" then
        local width = math.min(3,1+math.floor(rank/3))
        for i=-width,width do hit(app,x+sx-sy*i,y+sy+sx*i,damage*scale) end
    elseif id=="fracture" then
        hit(app,x,y,damage*(0.45+math.min(10,rank)*0.05))
    elseif id=="salvage" then
        local amount = app.maxFuel * math.min(0.03,0.01+rank*0.002)
        Stats.Record(app.combatStats,"tree_drill","fuel",amount,app.maxFuel-app.fuel)
        app.fuel=math.min(app.maxFuel,app.fuel+amount)
    elseif id=="battery" and tower then
        if (tower.laserCooldownRemaining or 0)>0 then
            tower.laserCooldownRemaining=math.max(0.05,tower.laserCooldownRemaining-0.15-rank*0.025)
        else
            tower.laserEnergy=math.min(tower.laserMax or 1,(tower.laserEnergy or 0)+(tower.laserMax or 1)*(0.03+rank*0.004))
        end
    elseif id=="magnet" and tower then
        for i=1,math.min(32,#(tower.pickups or {})) do
            local drop=tower.pickups[i]
            if distance(drop,p.x,p.y)<radius^2 then drop.x,drop.y=p.x,p.y end
        end
    elseif id=="vent" then
        -- Deterministic choice: largest remaining timer, then lexical ID.
        local selected, longest = "", 0
        for key, remaining in pairs(abyss.itemTimers or {}) do
            if remaining>longest or (remaining==longest and key<selected) then selected,longest=key,remaining end
        end
        if selected~="" then abyss.itemTimers[selected]=math.max(0.25,longest-0.5-rank*0.1) end
    elseif id=="repel" then
        local previous=abyss.monsterY or p.y
        abyss.monsterY=math.min(previous,math.max(p.y-Config.Abyss.warningGap*2,previous-4-rank*0.7))
    elseif id=="frost" and tower then
        for _, enemy in ipairs(tower.enemies or {}) do
            if distance(enemy,p.x,p.y)<radius^2 then enemy.slowTime=math.max(enemy.slowTime or 0,0.6+rank*0.12) end
        end
    elseif id=="parry" and tower then
        local removed=0
        for i=#(tower.projectiles or {}),1,-1 do
            if distance(tower.projectiles[i],p.x,p.y)<radius^2 then
                table.remove(tower.projectiles,i); removed=removed+1
                if removed>=math.min(8,1+rank) then break end
            end
        end
    elseif id=="turn" then
        for _,o in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do hit(app,x+o[1],y+o[2],damage*scale) end
    elseif id=="radar" and tower then
        if math.abs((tower.exitY or 0)*Config.TILE_SIZE-p.y) < 64+rank*16 then tower.exitRevealed=true end
    elseif id=="seam" then
        local found=0
        for _,o in ipairs({{-1,0},{1,0},{0,-1},{0,1},{-1,-1},{1,1},{1,-1},{-1,1}}) do
            local other=app.world:GetTile(x+o[1],y+o[2])
            if other and other.ore==tile.ore then
                hit(app,other.x,other.y,damage*scale); found=found+1
                if found>=math.min(8,2+math.floor(rank/2)) then break end
            end
        end
    elseif id=="counter" and tower then
        local closest, index = radius^2, 0
        for i,enemy in ipairs(tower.enemies or {}) do
            local dist=distance(enemy,p.x,p.y)
            if dist<closest then closest,index=dist,i end
        end
        if index>0 then tower:DamageEnemy(app,abyss,index,damage*(0.6+rank*0.07),"tree_drill") end
    elseif id=="echo" then
        local count=math.min(3,1+math.floor(rank/3))
        for i=1,count do
            hit(app,x-sx*i-sy,y-sy*i+sx,damage*scale)
            hit(app,x-sx*i+sy,y-sy*i-sx,damage*scale)
        end
    end
    if app.AddRing then app:AddRing(p.x,p.y,math.min(radius,48),Config.Palette.cyan,0.3) end
    if app.effects and #app.effects<100 then
        app.effects[#app.effects+1]={kind="skill_proc",node=d.icon,x=p.x,y=p.y-18,life=0.55,maxLife=0.55}
    end
end

function G.OnHit(app,tile,dx,dy,damage,destroyed)
    local abyss=app.abyss
    if not app.isAbyssRun or not abyss or not abyss.active or app.mode~="playing"
        or abyss.choice or (abyss.tower and abyss.tower.shopFloor) or not tile or tile.indestructible then return 0 end
    local rt=app.drillGameplay
    if not rt then
        rt={ranks=Catalog.Ranks(Tree,app.state),counts={},ready={},nextProc=0,cursor=1,streak=0}
        app.drillGameplay=rt
    end
    local key=tile.x..":"..tile.y
    rt.streak=rt.lastTile==key and rt.streak+1 or 1
    local turned=rt.lastDx and rt.lastDx*dx+rt.lastDy*dy<0
    rt.lastTile,rt.lastDx,rt.lastDy=key,dx,dy
    for _,d in ipairs(Catalog.DEFINITIONS) do
        if (rt.ranks[d.id] or 0)>0 and (not d.breaks or destroyed) then
            rt.counts[d.id]=math.min(d.every,(rt.counts[d.id] or 0)+1)
        end
    end
    local time=abyss.time or 0
    if time<rt.nextProc then return 0 end
    local count=0
    for offset=0,#Catalog.DEFINITIONS-1 do
        local index=(rt.cursor+offset-1)%#Catalog.DEFINITIONS+1
        local d=Catalog.DEFINITIONS[index]
        local rank=rt.ranks[d.id] or 0
        local condition=(d.id~="fracture" or (not destroyed and rt.streak>=(rank>=6 and 2 or 3)))
            and (d.id~="turn" or turned)
        if rank>0 and condition and (rt.counts[d.id] or 0)>=d.every and time>=(rt.ready[d.id] or 0) then
            activate(app,d,rank,tile,dx,dy,damage)
            rt.counts[d.id]=0
            rt.ready[d.id]=time+((d.id=="repel" or d.id=="salvage") and 6 or 1.5)
            count=count+1
            rt.nextCursor=index%#Catalog.DEFINITIONS+1
            if count==2 then break end
        end
    end
    if count>0 then rt.nextProc=time+0.3; rt.cursor=rt.nextCursor end
    return count
end
return G
