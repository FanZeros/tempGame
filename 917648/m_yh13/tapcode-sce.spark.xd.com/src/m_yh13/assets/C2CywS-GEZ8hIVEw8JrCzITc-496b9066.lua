-- Stateless visual sampling: no gameplay RNG, particles, timers or save writes.
local Motion = {}
Motion.TIERS = { rare = 1, epic = 2, legendary = 3, mythic = 4 }
function Motion.Draw(r, item, x, y, w, h, alpha)
    local tier = Motion.TIERS[item.rarity] or 1
    if not r.FillRect or (alpha or 1) < 0.4 then return end
    local t = tonumber(r.time) or 0
    local color = ({ {74,168,236}, {187,108,230}, {250,186,60}, {63,238,209} })[tier]
    local cx, cy, radius = x+w/2, y+h/2, math.max(w,h)*0.46
    if tier >= 3 then
        for ghost = 1, tier-1 do
            local offset = ghost * w * 0.1
            r:DrawSheetCell(item.atlas, 5, 2, item.index, x-offset, y+math.sin(t+ghost)*h*0.035,
                w, h, alpha * 0.07 * (tier-ghost))
        end
    end
    for i = 1, tier*2 do
        local a = t * (item.slot == "drill" and 1.4 or 0.7) + i * math.pi / tier
        local c = color
        if tier == 4 then
            c = { math.floor(155+95*math.sin(a)), math.floor(155+95*math.sin(a+2.1)),
                math.floor(155+95*math.sin(a+4.2)) }
        end
        local px, py = cx+math.cos(a)*radius, cy+math.sin(a)*radius*0.7
        local size = math.max(1, math.min(3,w*0.055))
        local opacity = math.floor(alpha*(85+65*(0.5+0.5*math.sin(t*2+i))))
        r:FillRect(math.floor(px), math.floor(py), size, size, {c[1],c[2],c[3],opacity})
        if tier == 4 then
            r:FillRect(math.floor(px)-size, math.floor(py)+size, size*3, size*0.5,
                {c[1],c[2],c[3],math.floor(opacity*0.6)})
        end
    end
    if tier >= 2 and r.StrokeRect then
        local pulse = 1+math.sin(t*1.5)*0.08
        r:StrokeRect(cx-radius*pulse, cy-h*0.37, radius*2*pulse, h*0.74,
            {color[1],color[2],color[3],math.floor(45*alpha)}, 1)
    end
end
return Motion
