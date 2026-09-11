local Config = require("nightgate.Config")
local OriginalData = require("nightgate.OriginalData")

local Equipment = {}

local PERCENT_ATTRIBUTES = {
    [4] = true, [5] = true, [7] = true, [8] = true, [16] = true, [17] = true,
    [26] = true, [27] = true, [28] = true, [29] = true, [30] = true, [32] = true,
    [34] = true, [35] = true, [47] = true, [55] = true, [57] = true, [60] = true,
    [61] = true, [63] = true,
}

local function copyInstance(instance)
    return {
        id = instance.id,
        level = instance.level or 0,
        locked = instance.locked == true,
        new = instance.new == true,
    }
end

function Equipment.NormalizeInstance(value)
    local id = nil
    local level = 0
    local locked = false
    local isNew = false
    if type(value) == "number" then
        id = Config.EQUIPMENT_BY_ID[value] and value or Config.LEGACY_EQUIPMENT_MAP[value]
    elseif type(value) == "table" then
        local rawId = tonumber(value.id)
        id = Config.EQUIPMENT_BY_ID[rawId] and rawId or Config.LEGACY_EQUIPMENT_MAP[rawId]
        level = math.max(0, math.min(30, math.floor(tonumber(value.level) or 0)))
        locked = value.locked == true
        isNew = value.new == true
    end
    if not id then
        return nil
    end
    return { id = id, level = level, locked = locked, new = isNew }
end

function Equipment.NormalizeInventory(source)
    local result = {}
    if type(source) == "table" then
        for index = 1, #source do
            local instance = Equipment.NormalizeInstance(source[index])
            if instance and #result < Config.EQUIPMENT_CAPACITY then
                result[#result + 1] = instance
            end
        end
    end
    return result
end

local function emptyEquipment()
    local result = {}
    for wallIndex = 1, 4 do
        result[wallIndex] = { captain = {}, hero = {} }
    end
    return result
end

local function place(result, wallIndex, instance, forcedRole, forcedSlot)
    local item = instance and Config.EQUIPMENT_BY_ID[instance.id]
    if not item then
        return
    end
    local role = forcedRole or item.role
    local slot = forcedSlot or item.slot
    if result[wallIndex] and result[wallIndex][role] and slot >= 1 and slot <= 2 then
        result[wallIndex][role][slot] = instance
    end
end

function Equipment.NormalizeEquipped(source)
    local result = emptyEquipment()
    if type(source) ~= "table" then
        return result
    end
    for wallIndex = 1, 4 do
        local wall = source[wallIndex] or source[tostring(wallIndex)]
        if type(wall) == "table" then
            for _, role in ipairs({ "captain", "hero" }) do
                local stored = wall[role]
                if type(stored) == "table" and stored.id == nil then
                    for slot = 1, 2 do
                        place(result, wallIndex, Equipment.NormalizeInstance(stored[slot] or stored[tostring(slot)]), role, slot)
                    end
                else
                    -- Migration from the old one-item-per-role save format.
                    place(result, wallIndex, Equipment.NormalizeInstance(stored))
                end
            end
        end
    end
    return result
end

function Equipment.GetItem(instance)
    local normalized = Equipment.NormalizeInstance(instance)
    return normalized and Config.EQUIPMENT_BY_ID[normalized.id] or nil
end

function Equipment.GetEquipped(battle, wallIndex, role, slot)
    local wall = battle.equipment[wallIndex]
    return wall and wall[role] and wall[role][slot] or nil
end

function Equipment.EquipInventoryItem(battle, inventoryIndex, wallIndex)
    local instance = battle.inventory[inventoryIndex]
    local item = Equipment.GetItem(instance)
    if not item or wallIndex < 1 or wallIndex > 4 then
        return false, "装备不存在"
    end
    if battle.IsRoleUnlocked and not battle:IsRoleUnlocked(wallIndex, item.role) then
        return false, battle:GetRoleUnlockMessage(wallIndex, item.role)
    end
    local previous = battle.equipment[wallIndex][item.role][item.slot]
    battle.equipment[wallIndex][item.role][item.slot] = copyInstance(instance)
    table.remove(battle.inventory, inventoryIndex)
    if previous then
        battle.inventory[#battle.inventory + 1] = previous
    end
    return true, item.qualityName .. " · " .. item.name .. " 已装配"
end

function Equipment.Unequip(battle, wallIndex, role, slot)
    local instance = Equipment.GetEquipped(battle, wallIndex, role, slot)
    if not instance then
        return false, "当前槽位为空"
    end
    if #battle.inventory >= Config.EQUIPMENT_CAPACITY then
        return false, "背包已满"
    end
    battle.inventory[#battle.inventory + 1] = instance
    battle.equipment[wallIndex][role][slot] = nil
    return true, "装备已卸下"
end

function Equipment.SortInventory(battle)
    table.sort(battle.inventory, function(a, b)
        local itemA = Equipment.GetItem(a)
        local itemB = Equipment.GetItem(b)
        if itemA.quality ~= itemB.quality then
            return itemA.quality > itemB.quality
        elseif itemA.pos ~= itemB.pos then
            return itemA.pos < itemB.pos
        elseif itemA.id ~= itemB.id then
            return itemA.id < itemB.id
        end
        return (a.level or 0) > (b.level or 0)
    end)
    return true, "已按品质与部位排序"
end

local function findMergePair(inventory)
    local firstById = {}
    for index = 1, #inventory do
        local instance = inventory[index]
        local item = Equipment.GetItem(instance)
        if item and item.mergeTargetId > 0 and not instance.locked then
            if firstById[item.id] then
                return firstById[item.id], index, item.mergeTargetId
            end
            firstById[item.id] = index
        end
    end
    return nil
end

function Equipment.QuickMerge(battle)
    local merged = 0
    while true do
        local first, second, targetId = findMergePair(battle.inventory)
        if not first then
            break
        end
        local level = math.max(battle.inventory[first].level or 0, battle.inventory[second].level or 0)
        table.remove(battle.inventory, second)
        table.remove(battle.inventory, first)
        battle.inventory[#battle.inventory + 1] = { id = targetId, level = level, locked = false, new = true }
        merged = merged + 1
    end
    if merged == 0 then
        return false, "没有相同种类与品质的装备"
    end
    Equipment.SortInventory(battle)
    return true, "已完成 " .. tostring(merged) .. " 次合成"
end

function Equipment.GetRecyclePreview(battle)
    local count = 0
    local shards = 0
    for index = 1, #battle.inventory do
        local instance = battle.inventory[index]
        local item = Equipment.GetItem(instance)
        if item and not instance.locked then
            count = count + 1
            shards = shards + (Config.EQUIPMENT_RECYCLE[item.quality] or 0)
        end
    end
    return count, shards
end

function Equipment.RecycleInventory(battle)
    local count, shards = Equipment.GetRecyclePreview(battle)
    if count == 0 then
        return false, "没有可分解装备"
    end
    for index = #battle.inventory, 1, -1 do
        if not battle.inventory[index].locked then
            table.remove(battle.inventory, index)
        end
    end
    battle.equipmentShards = battle.equipmentShards + shards
    return true, "分解 " .. tostring(count) .. " 件，获得 " .. tostring(shards) .. " 装备碎片"
end

function Equipment.Strengthen(battle, wallIndex, role, slot)
    if battle.IsRoleUnlocked and not battle:IsRoleUnlocked(wallIndex, role) then
        return false, battle:GetRoleUnlockMessage(wallIndex, role)
    end
    local instance = Equipment.GetEquipped(battle, wallIndex, role, slot)
    if not instance then
        return false, "请先选择已装备的槽位"
    end
    local nextDefinition = Config.EQUIPMENT_STRENGTHEN[(instance.level or 0) + 1]
    if not nextDefinition or instance.level >= 30 then
        return false, "装备已强化至满级"
    end
    if battle.equipmentShards < nextDefinition.cost then
        return false, "装备碎片不足"
    end
    battle.equipmentShards = battle.equipmentShards - nextDefinition.cost
    instance.level = (instance.level or 0) + 1
    return true, "强化成功 · Lv." .. tostring(instance.level)
end

function Equipment.GetStrengthenCost(instance)
    local normalized = Equipment.NormalizeInstance(instance)
    if not normalized or normalized.level >= 30 then
        return nil
    end
    local definition = Config.EQUIPMENT_STRENGTHEN[normalized.level + 1]
    return definition and definition.cost or nil
end

function Equipment.Describe(instance)
    local normalized = Equipment.NormalizeInstance(instance)
    local item = normalized and Config.EQUIPMENT_BY_ID[normalized.id]
    if not item then
        return "空装备槽"
    end
    local parts = {}
    for index = 1, #item.attributes do
        local attr = item.attributes[index]
        parts[#parts + 1] = (OriginalData.AttributeNames[attr.type] or tostring(attr.type)) .. "+" .. tostring(attr.value)
    end
    return item.qualityName .. " · " .. item.name .. "  Lv." .. tostring(normalized.level) .. "  " .. table.concat(parts, " / ")
end

local function formatEffectValue(value, isPercent)
    return string.format("%.1f", value) .. (isPercent and "%" or "")
end

function Equipment.DescribeEffects(instance)
    local normalized = Equipment.NormalizeInstance(instance)
    local item = normalized and Config.EQUIPMENT_BY_ID[normalized.id]
    if not item then return "" end
    local strengthen = Config.EQUIPMENT_STRENGTHEN[(normalized.level or 0) + 1]
    local multiplier = 1 + (strengthen and strengthen.effectAdd or 0)
    local lines = {}
    for index = 1, #item.attributes do
        local attr = item.attributes[index]
        lines[#lines + 1] = (OriginalData.AttributeNames[attr.type] or tostring(attr.type)) .. "  +" .. formatEffectValue(attr.value * multiplier, PERCENT_ATTRIBUTES[attr.type] == true)
    end
    return table.concat(lines, "\n")
end

return Equipment
