-- Single-player cosmetics never feed combat stats. Previewing does not grant.
local Cosmetics = {}
Cosmetics.rarity = {
    rare = { name = "稀有", motion = "微光火花", color = { 74, 168, 236, 255 }, weight = 70 },
    epic = { name = "史诗", motion = "环绕粒子", color = { 187, 108, 230, 255 }, weight = 23 },
    legendary = { name = "传说", motion = "金光幻影", color = { 250, 186, 60, 255 }, weight = 6 },
    mythic = { name = "神话", motion = "彩色符文", color = { 63, 238, 209, 255 }, weight = 1 },
}
Cosmetics.atlases = {
    character = "image/diggin/generated/abyss/s2-characters-v1.png",
    drill = "image/diggin/generated/abyss/s2-drills-v1.png",
}
local themes = {
    { "moss", "苔原探客", "苔铜螺旋", "rare" },
    { "furnace", "熔炉工匠", "熔炉钻机", "rare" },
    { "ice", "霜晶卫士", "冰晶尖锋", "rare" },
    { "spore", "蘑菇旅人", "孢子旋钻", "rare" },
    { "honey", "琥珀蜂匠", "蜜蜡蜂钻", "epic" },
    { "thunder", "雷霆工程师", "雷鸣引擎", "epic" },
    { "obsidian", "黑曜行者", "烬火黑钻", "epic" },
    { "moon", "月白星旅", "月轮星钻", "legendary" },
    { "rift", "裂界幽影", "裂界晶锥", "legendary" },
    { "worldtree", "世界树守望", "翠金根钻", "mythic" },
}
Cosmetics.items, Cosmetics.byId = {}, {}
for _, slot in ipairs({ "character", "drill" }) do
    for index, theme in ipairs(themes) do
        local item = { id = "s2_" .. slot .. "_" .. theme[1], slot = slot,
            name = theme[slot == "character" and 2 or 3], rarity = theme[4],
            atlas = Cosmetics.atlases[slot], index = index }
        Cosmetics.items[#Cosmetics.items + 1] = item
        Cosmetics.byId[item.id] = item
    end
end

function Cosmetics.Normalize(value)
    value = type(value) == "table" and value or {}
    local result = { owned = {}, equipped = {} }
    if type(value.owned) == "table" then
        for id, owned in pairs(value.owned) do
            if owned == true and Cosmetics.byId[id] then result.owned[id] = true end
        end
    end
    if type(value.equipped) == "table" then
        for _, slot in ipairs({ "character", "drill" }) do
            local id = value.equipped[slot]
            local item = Cosmetics.byId[id]
            if item and item.slot == slot and result.owned[id] then result.equipped[slot] = id end
        end
    end
    return result
end

function Cosmetics.MergeOwnership(current, incoming)
    local result, other = Cosmetics.Normalize(current), Cosmetics.Normalize(incoming)
    for id in pairs(other.owned) do result.owned[id] = true end
    -- Stale cloud saves can restore ownership, never change the current outfit.
    return result
end

function Cosmetics.Equip(state, slot, id)
    if slot ~= "character" and slot ~= "drill" then return false end
    local profile = Cosmetics.Normalize(state.cosmetics)
    if id ~= nil then
        local item = Cosmetics.byId[id]
        if not item or item.slot ~= slot or not profile.owned[id] then return false end
    end
    profile.equipped[slot] = id
    state.cosmetics = profile
    state:Save()
    return true
end

function Cosmetics.GetEquipped(state, slot)
    local profile = state.cosmetics
    if type(profile) ~= "table" or type(profile.equipped) ~= "table" then return nil end
    local id = profile.equipped[slot]
    local item = Cosmetics.byId[id]
    if item and item.slot == slot and profile.owned and profile.owned[id] == true then return item end
end

function Cosmetics.Draw(renderer, item, x, y, w, h, alpha)
    if not item then return end
    require("diggin.CosmeticMotion").Draw(renderer, item, x, y, w, h, alpha or 1)
    renderer:DrawSheetCell(item.atlas, 5, 2, item.index, x, y, w, h, alpha or 1)
end

-- One chance per completed Abyss run, not per ore or frame. Shop time is
-- already excluded from settlement.time. Never changes the combat RNG mid-run.
Cosmetics.dropChance = 0.005
function Cosmetics.GetDropPool(state)
    local owned = Cosmetics.Normalize(state.cosmetics).owned
    local counts, pool, total = {}, {}, 0
    for _, item in ipairs(Cosmetics.items) do counts[item.rarity] = (counts[item.rarity] or 0) + 1 end
    for _, item in ipairs(Cosmetics.items) do
        if not owned[item.id] then
            local weight = Cosmetics.rarity[item.rarity].weight / counts[item.rarity]
            pool[#pool + 1] = { item = item, weight = weight }
            total = total + weight
        end
    end
    return pool, total
end

function Cosmetics.GrantRunDrop(state, settlement, random)
    if not settlement or settlement.cosmeticRolled then return nil end
    settlement.cosmeticRolled = true
    if (tonumber(settlement.floor) or 0) < 10 or (tonumber(settlement.time) or 0) < 180 then return nil end
    local pool, total = Cosmetics.GetDropPool(state)
    if #pool == 0 then return nil end
    random = random or math.random
    if random() >= Cosmetics.dropChance then return nil end
    local cursor = random() * total
    local selected = pool[#pool].item
    for _, row in ipairs(pool) do
        cursor = cursor - row.weight
        if cursor < 0 then selected = row.item; break end
    end
    state.cosmetics = Cosmetics.Normalize(state.cosmetics)
    state.cosmetics.owned[selected.id] = true
    settlement.cosmeticId = selected.id
    -- Caller persists with the same end-of-run inventory commit.
    return selected
end

return Cosmetics
