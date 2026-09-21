local Config = require("diggin.Config")
local Util = require("diggin.Util")
local AbyssPassives = require("diggin.AbyssPassives")
local AbyssContent = require("diggin.AbyssContent")

local AbyssLoot = {}

AbyssLoot.GRADES = {
    { id = "F",   name = "F级",   index = 1, power = 1,  color = { 132, 137, 148, 255 } },
    { id = "E",   name = "E级",   index = 2, power = 2,  color = { 174, 113, 62, 255 } },
    { id = "D",   name = "D级",   index = 3, power = 4,  color = { 103, 173, 79, 255 } },
    { id = "C",   name = "C级",   index = 4, power = 7,  color = { 65, 142, 224, 255 } },
    { id = "B",   name = "B级",   index = 5, power = 11, color = { 150, 82, 219, 255 } },
    { id = "A",   name = "A级",   index = 6, power = 17, color = { 244, 187, 43, 255 } },
    { id = "S",   name = "S级",   index = 7, power = 25, color = { 239, 70, 70, 255 }, glow = true },
    { id = "SS",  name = "SS级",  index = 8, power = 36, color = { 73, 226, 247, 255 }, glow = true },
    { id = "SSS", name = "SSS级", index = 9, power = 52, color = { 255, 106, 232, 255 }, glow = true, prismatic = true },
}

AbyssLoot.SLOTS = {
    { id = "drill_core", name = "钻心", stat = "drill_damage_pct", suffix = "深渊钻头伤害",
        description = "强化深渊中的钻掘伤害，品级越高提升越明显。" },
    { id = "greaves", name = "履带靴", stat = "move_speed_pct", suffix = "移动速度",
        description = "提高深渊移动速度，帮助躲开红框轰击并拉开追击距离。" },
    { id = "shell", name = "护壳", stat = "boss_damage_reduction_pct", suffix = "Boss伤害减免",
        description = "降低深渊Boss技能命中时损失的燃料。" },
    { id = "sigil", name = "寻宝印", stat = "point_gain_pct", suffix = "世界树点数",
        description = "同时提高世界树点数收益与高品级装备掉落幸运。" },
}

AbyssLoot.SETS = {
    titan = { name = "巨镐", color = Config.Palette.red,
        two = { stat = "item_power_pct", value = 12, text = "2件：道具伤害 +12%" },
        four = { stat = "item_power_pct", value = 30, text = "4件：道具伤害额外 +30%" } },
    swarm = { name = "蜂群", color = Config.Palette.cyan,
        two = { stat = "item_cooldown_pct", value = 8, text = "2件：道具冷却 -8%" },
        four = { stat = "item_cooldown_pct", value = 20, text = "4件：道具冷却额外 -20%" } },
    root = { name = "根盾", color = Config.Palette.green,
        two = { stat = "boss_damage_reduction_pct", value = 8, text = "2件：Boss伤害减免 +8%" },
        four = { stat = "boss_damage_reduction_pct", value = 18, text = "4件：Boss伤害减免额外 +18%" } },
    chrono = { name = "时轮", color = Config.Palette.purple,
        two = { stat = "perfect_window", value = 0.05, text = "2件：完美闪避窗口 +0.05秒" },
        four = { stat = "perfect_window", value = 0.12, text = "4件：完美闪避窗口额外 +0.12秒" } },
}

AbyssLoot.AFFIXES = {
    { id = "force", name = "强袭", stat = "item_power_pct", scale = 0.65, suffix = "% 道具伤害" },
    { id = "rapid", name = "迅捷", stat = "item_cooldown_pct", scale = 0.38, suffix = "% 道具冷却" },
    { id = "ward", name = "庇护", stat = "boss_damage_reduction_pct", scale = 0.34, suffix = "% Boss减伤" },
    { id = "fortune", name = "寻宝", stat = "loot_luck", scale = 0.45, suffix = " 寻宝幸运" },
    { id = "step", name = "踏风", stat = "move_speed_pct", scale = 0.28, suffix = "% 移动速度" },
}

local GRADE_BY_ID = {}
local SLOT_BY_ID = {}
local AFFIX_BY_ID = {}
local ARCHETYPE_BY_SLOT = {}
local STAT_LABELS = {
    drill_damage_pct = "钻头伤害", item_cooldown_pct = "道具冷却缩减",
    boss_damage_reduction_pct = "Boss伤害减免", loot_luck = "寻宝幸运",
    move_speed_pct = "移动速度", perfect_window = "完美闪避窗口",
    fuel_efficiency_pct = "燃料效率", item_power_pct = "道具伤害",
    point_gain_pct = "世界树点数", fuel_capacity_pct = "最大燃料",
}
local ROUTE_LABELS = {
    universal = "通用", safe = "脆岩捷径", treasure = "丰矿支脉", risk = "灾变裂谷",
}
for _, grade in ipairs(AbyssLoot.GRADES) do GRADE_BY_ID[grade.id] = grade end
for _, slot in ipairs(AbyssLoot.SLOTS) do SLOT_BY_ID[slot.id] = slot end
for _, affix in ipairs(AbyssLoot.AFFIXES) do AFFIX_BY_ID[affix.id] = affix end
for _, archetype in ipairs(AbyssContent.EQUIPMENT) do
    ARCHETYPE_BY_SLOT[archetype.slot] = ARCHETYPE_BY_SLOT[archetype.slot] or {}
    ARCHETYPE_BY_SLOT[archetype.slot][#ARCHETYPE_BY_SLOT[archetype.slot] + 1] = archetype
end

AbyssLoot.EQUIPMENT = AbyssContent.EQUIPMENT
AbyssLoot.MAX_FORGE_LEVEL = 12

local GRADE_WEIGHTS = { 520, 300, 170, 92, 48, 24, 10, 4, 1 }

function AbyssLoot.GetGrade(id)
    if type(id) == "table" then id = id.grade end
    return GRADE_BY_ID[tostring(id or "")]
end

function AbyssLoot.GetSlot(id)
    return SLOT_BY_ID[tostring(id or "")]
end

function AbyssLoot.GetArchetype(id)
    return AbyssContent.EQUIPMENT_BY_ID[tostring(id or "")]
end

function AbyssLoot.GetEquipmentCatalog()
    return AbyssContent.EQUIPMENT
end

function AbyssLoot.GetDiscoveredCount(state)
    local count = 0
    for _, item in ipairs(AbyssContent.EQUIPMENT) do
        if state and state.abyssDiscoveredEquipment and state.abyssDiscoveredEquipment[item.id] == true then
            count = count + 1
        end
    end
    return count
end

function AbyssLoot.GetGradeIndex(id)
    local grade = AbyssLoot.GetGrade(id)
    return grade and grade.index or 0
end

function AbyssLoot.GetGradeColor(id, time)
    local grade = AbyssLoot.GetGrade(id) or AbyssLoot.GRADES[1]
    if not grade.prismatic then return grade.color end
    local phase = (tonumber(time) or 0) * 2.4
    return {
        math.floor(170 + 85 * math.sin(phase)),
        math.floor(170 + 85 * math.sin(phase + 2.094)),
        math.floor(170 + 85 * math.sin(phase + 4.188)),
        255,
    }
end

function AbyssLoot.GetEquippedGrade(state, slotId)
    local equipment = state and state.abyssEquipment or nil
    return equipment and AbyssLoot.GetGrade(equipment[slotId]) or nil
end

function AbyssLoot.NormalizeEquipmentEntry(value, slotId)
    local grade = AbyssLoot.GetGrade(value)
    if not grade or not AbyssLoot.GetSlot(slotId) then return nil end
    if type(value) == "table" then
        local archetype = AbyssLoot.GetArchetype(value.archetypeId)
        if not archetype or archetype.slot ~= slotId then archetype = (ARCHETYPE_BY_SLOT[slotId] or {})[1] end
        local result = {
            grade = grade.id, slot = slotId, setId = AbyssLoot.SETS[value.setId] and value.setId or nil,
            uid = math.max(0, math.floor(tonumber(value.uid) or 0)),
            affixes = {}, reforgeCount = math.max(0, math.floor(tonumber(value.reforgeCount) or 0)),
            archetypeId = archetype and archetype.id or nil,
            routeId = tostring(value.routeId or (archetype and archetype.route) or "universal"),
            forgeLevel = Util.Clamp(math.floor(tonumber(value.forgeLevel) or 0), 0, AbyssLoot.MAX_FORGE_LEVEL),
        }
        for _, rolled in ipairs(type(value.affixes) == "table" and value.affixes or {}) do
            if AFFIX_BY_ID[rolled.id] then
                result.affixes[#result.affixes + 1] = { id = rolled.id, value = tonumber(rolled.value) or 0 }
            end
        end
        return result
    end
    local fallback = (ARCHETYPE_BY_SLOT[slotId] or {})[1]
    return { grade = grade.id, slot = slotId, affixes = {}, reforgeCount = 0,
        archetypeId = fallback and fallback.id or nil, routeId = "universal", forgeLevel = 0, uid = 0 }
end

function AbyssLoot.GetEquippedItem(state, slotId)
    local equipment = state and state.abyssEquipment or nil
    return equipment and AbyssLoot.NormalizeEquipmentEntry(equipment[slotId], slotId) or nil
end

function AbyssLoot.GetSetCounts(state)
    local counts = {}
    for _, slot in ipairs(AbyssLoot.SLOTS) do
        local item = AbyssLoot.GetEquippedItem(state, slot.id)
        if item and item.setId then counts[item.setId] = (counts[item.setId] or 0) + 1 end
    end
    return counts
end

local function setBonus(state, statId)
    local total = 0
    for setId, count in pairs(AbyssLoot.GetSetCounts(state)) do
        local set = AbyssLoot.SETS[setId]
        if count >= 2 and set.two.stat == statId then total = total + set.two.value end
        if count >= 4 and set.four.stat == statId then total = total + set.four.value end
    end
    return total
end

function AbyssLoot.GetBonus(state, statId)
    if not state or not statId then return 0 end
    local total = 0
    for _, slot in ipairs(AbyssLoot.SLOTS) do
        local item = AbyssLoot.GetEquippedItem(state, slot.id)
        if slot.stat == statId then
            local grade = AbyssLoot.GetEquippedGrade(state, slot.id)
            if grade then
                local forgedPower = grade.power * (1 + (item.forgeLevel or 0) * 0.06)
                if statId == "drill_damage_pct" then total = total + forgedPower * 3 end
                if statId == "move_speed_pct" then total = total + forgedPower * 0.75 end
                if statId == "boss_damage_reduction_pct" then total = total + math.min(62, forgedPower) end
                if statId == "point_gain_pct" then total = total + forgedPower * 1.25 end
            end
        end
        local archetype = item and AbyssLoot.GetArchetype(item.archetypeId)
        local grade = item and AbyssLoot.GetGrade(item.grade)
        if archetype and grade and archetype.intrinsicStat == statId then
            total = total + grade.power * archetype.intrinsicScale * (1 + (item.forgeLevel or 0) * 0.04)
        end
        for _, rolled in ipairs(item and item.affixes or {}) do
            local affix = AFFIX_BY_ID[rolled.id]
            if affix and affix.stat == statId then total = total + rolled.value end
        end
    end
    if statId == "loot_luck" then
        local grade = AbyssLoot.GetEquippedGrade(state, "sigil")
        local item = AbyssLoot.GetEquippedItem(state, "sigil")
        total = total + (grade and grade.power * 0.65 * (1 + (item and item.forgeLevel or 0) * 0.04) or 0)
    end
    return total + setBonus(state, statId)
end

function AbyssLoot.GetLoadout(state)
    local result = {}
    for _, slot in ipairs(AbyssLoot.SLOTS) do
        local grade = AbyssLoot.GetEquippedGrade(state, slot.id)
        local item = AbyssLoot.GetEquippedItem(state, slot.id)
        result[#result + 1] = {
            slot = slot,
            grade = grade,
            gradeId = grade and grade.id or nil,
            iconIndex = item and (AbyssLoot.GetArchetype(item.archetypeId) or {}).iconIndex or 1,
            item = item,
        }
    end
    return result
end

function AbyssLoot.GetGradeBonusText(slotId, gradeId)
    local grade = AbyssLoot.GetGrade(gradeId)
    if not grade then return "尚未获得该槽位装备" end
    if slotId == "drill_core" then
        return string.format("深渊钻头伤害 +%.0f%%", grade.power * 3)
    elseif slotId == "greaves" then
        return string.format("深渊移动速度 +%.1f%%", grade.power * 0.75)
    elseif slotId == "shell" then
        return string.format("Boss命中燃料伤害 -%.0f%%", math.min(55, grade.power))
    elseif slotId == "sigil" then
        return string.format("世界树点数 +%.1f%% · 寻宝幸运 +%.1f",
            grade.power * 1.25, grade.power * 0.65)
    end
    return "未知装备属性"
end

local function getPrimaryBonusText(slotId, grade, item)
    if not grade then return "尚未获得该槽位装备" end
    local forgedPower = grade.power * (1 + ((item and item.forgeLevel) or 0) * 0.06)
    if slotId == "drill_core" then
        return string.format("深渊钻头伤害 +%.1f%%", forgedPower * 3)
    elseif slotId == "greaves" then
        return string.format("深渊移动速度 +%.1f%%", forgedPower * 0.75)
    elseif slotId == "shell" then
        return string.format("Boss命中燃料伤害 -%.1f%%", math.min(62, forgedPower))
    elseif slotId == "sigil" then
        return string.format("世界树点数 +%.1f%% · 寻宝幸运 +%.1f",
            forgedPower * 1.25, forgedPower * 0.65)
    end
    return "未知装备属性"
end

local function getIntrinsicText(archetype, grade, item)
    if not archetype or not grade then return nil end
    local value = grade.power * archetype.intrinsicScale
        * (1 + ((item and item.forgeLevel) or 0) * 0.04)
    local label = STAT_LABELS[archetype.intrinsicStat] or "专属属性"
    if archetype.intrinsicStat == "perfect_window" then
        return string.format("%s +%.3f秒", label, value)
    elseif archetype.intrinsicStat == "loot_luck" then
        return string.format("%s +%.1f", label, value)
    end
    return string.format("%s +%.1f%%", label, value)
end

function AbyssLoot.GetSlotBonusText(state, slotId)
    local slot = AbyssLoot.GetSlot(slotId)
    local grade = AbyssLoot.GetEquippedGrade(state, slotId)
    if not slot or not grade then return "尚未获得该槽位装备" end
    local item = AbyssLoot.GetEquippedItem(state, slotId)
    local archetype = item and AbyssLoot.GetArchetype(item.archetypeId)
    local lines = { getPrimaryBonusText(slotId, grade, item) }
    if archetype then
        lines[#lines + 1] = (ROUTE_LABELS[archetype.route] or archetype.route) .. "装备"
        lines[#lines + 1] = getIntrinsicText(archetype, grade, item)
    end
    if item and (item.forgeLevel or 0) > 0 then lines[#lines + 1] = "锻造 +" .. item.forgeLevel end
    if item and item.setId then lines[#lines + 1] = AbyssLoot.SETS[item.setId].name .. "套装" end
    for _, rolled in ipairs(item and item.affixes or {}) do
        local affix = AFFIX_BY_ID[rolled.id]
        if affix then lines[#lines + 1] = string.format("%s +%.1f%s", affix.name, rolled.value, affix.suffix) end
    end
    return table.concat(lines, " · ")
end

function AbyssLoot.GetResonanceText(state, slotId)
    local item = AbyssLoot.GetEquippedItem(state, slotId)
    if not item or not item.setId then return "无套装共鸣" end
    local set = AbyssLoot.SETS[item.setId]
    local count = AbyssLoot.GetSetCounts(state)[item.setId] or 0
    local active = count >= 4 and (set.two.text .. " · " .. set.four.text)
        or (count >= 2 and set.two.text or "集齐2件后激活")
    return string.format("%s共鸣 %d/4 · %s", set.name, count, active)
end

function AbyssLoot.GetItemDetails(state, slotId)
    local slot = AbyssLoot.GetSlot(slotId)
    if not slot then return nil end
    local grade = AbyssLoot.GetEquippedGrade(state, slotId)
    local item = AbyssLoot.GetEquippedItem(state, slotId)
    local archetype = item and AbyssLoot.GetArchetype(item.archetypeId)
    local nextGrade = grade and AbyssLoot.GRADES[grade.index + 1] or AbyssLoot.GRADES[1]
    return {
        slot = slot,
        grade = grade,
        title = grade and (grade.name .. "·" .. (archetype and archetype.name or slot.name)) or ("未装备·" .. slot.name),
        attribute = grade and getPrimaryBonusText(slotId, grade, item) or "当前属性：未生效",
        description = slot.description,
        power = grade and grade.power or 0,
        gradeIndex = grade and grade.index or 0,
        iconIndex = archetype and archetype.iconIndex or 1,
        forgeLevel = item and item.forgeLevel or 0,
        archetype = archetype,
        salvage = grade and math.max(1, math.floor(grade.power * 0.5)) or 0,
        nextGrade = nextGrade,
        nextAttribute = nextGrade and AbyssLoot.GetGradeBonusText(slotId, nextGrade.id) or "已达到最高品级",
        affixText = AbyssLoot.GetSlotBonusText(state, slotId),
        resonance = AbyssLoot.GetResonanceText(state, slotId),
        reforgeCost = grade and (4 + grade.power + math.max(0, math.floor(tonumber((item or {}).reforgeCount) or 0)) * 3) or 0,
        forgeCost = grade and AbyssLoot.GetForgeCost(state, slotId) or 0,
        promoteCost = grade and AbyssLoot.GetPromoteCost(state, slotId) or 0,
    }
end

function AbyssLoot.GetEquipmentScore(item)
    if type(item) ~= "table" then return 0 end
    local grade = AbyssLoot.GetGrade(item.grade)
    if not grade then return 0 end
    return grade.index * 1000 + math.max(0, tonumber(item.forgeLevel) or 0) * 25
        + #(type(item.affixes) == "table" and item.affixes or {})
end

function AbyssLoot.GetSalvageValue(item)
    local grade = item and AbyssLoot.GetGrade(item.grade)
    return grade and math.max(1, math.floor(grade.power * 0.5 + (item.forgeLevel or 0) * 0.5)) or 0
end

function AbyssLoot.GetStandaloneDetails(state, item)
    if type(item) ~= "table" then return nil end
    item = AbyssLoot.NormalizeEquipmentEntry(item, item.slot)
    if not item then return nil end
    local slot = AbyssLoot.GetSlot(item.slot)
    local grade = AbyssLoot.GetGrade(item.grade)
    local archetype = AbyssLoot.GetArchetype(item.archetypeId)
    local lines = { getPrimaryBonusText(item.slot, grade, item) }
    if archetype then
        lines[#lines + 1] = (ROUTE_LABELS[archetype.route] or archetype.route) .. "装备"
        lines[#lines + 1] = getIntrinsicText(archetype, grade, item)
    end
    if (item.forgeLevel or 0) > 0 then lines[#lines + 1] = "锻造 +" .. item.forgeLevel end
    if item.setId and AbyssLoot.SETS[item.setId] then
        lines[#lines + 1] = AbyssLoot.SETS[item.setId].name .. "套装"
    end
    for _, rolled in ipairs(item.affixes or {}) do
        local affix = AFFIX_BY_ID[rolled.id]
        if affix then lines[#lines + 1] = string.format("%s +%.1f%s", affix.name, rolled.value, affix.suffix) end
    end
    return {
        item = item, slot = slot, grade = grade, archetype = archetype,
        title = grade.name .. "·" .. (archetype and archetype.name or slot.name),
        iconIndex = archetype and archetype.iconIndex or 1,
        affixText = table.concat(lines, " · "),
        salvage = AbyssLoot.GetSalvageValue(item),
        score = AbyssLoot.GetEquipmentScore(item),
    }
end

local function chooseArchetype(slotId, routeId)
    local candidates = {}
    for _, archetype in ipairs(ARCHETYPE_BY_SLOT[slotId] or {}) do
        if archetype.route == "universal" or archetype.route == routeId then
            candidates[#candidates + 1] = archetype
        end
    end
    if #candidates == 0 then candidates = ARCHETYPE_BY_SLOT[slotId] or {} end
    return #candidates > 0 and candidates[math.random(1, #candidates)] or nil
end

function AbyssLoot.MakeItem(gradeId, slotId, routeId)
    local grade = AbyssLoot.GetGrade(gradeId)
    local slot = AbyssLoot.GetSlot(slotId)
    if not grade or not slot then return nil end
    routeId = tostring(routeId or "universal")
    local archetype = chooseArchetype(slotId, routeId)
    local setIds = { "titan", "swarm", "root", "chrono" }
    local affixCount = math.min(3, 1 + math.floor((grade.index - 1) / 3))
    local affixes, used = {}, {}
    for _ = 1, affixCount do
        local index = math.random(1, #AbyssLoot.AFFIXES)
        while used[index] do index = index % #AbyssLoot.AFFIXES + 1 end
        used[index] = true
        local affix = AbyssLoot.AFFIXES[index]
        local roll = 0.75 + math.random() * 0.5
        affixes[#affixes + 1] = { id = affix.id, value = math.max(0.1, grade.power * affix.scale * roll) }
    end
    return {
        grade = grade.id,
        gradeIndex = grade.index,
        slot = slot.id,
        name = grade.name .. "·" .. (archetype and archetype.name or slot.name),
        archetypeId = archetype and archetype.id or nil,
        routeId = routeId,
        iconIndex = archetype and archetype.iconIndex or 1,
        color = grade.color,
        setId = setIds[math.random(1, #setIds)],
        affixes = affixes,
        reforgeCount = 0,
        forgeLevel = 0,
    }
end

function AbyssLoot.Reforge(state, slotId)
    local current = AbyssLoot.GetEquippedItem(state, slotId)
    local grade = current and AbyssLoot.GetGrade(current.grade)
    if not current or not grade then return false, "该槽位尚无装备" end
    local cost = 4 + grade.power + current.reforgeCount * 3
    if (state.abyssDust or 0) < cost then return false, "晶尘不足，需要 " .. cost end
    local rerolled = AbyssLoot.MakeItem(grade.id, slotId, current.routeId)
    rerolled.archetypeId = current.archetypeId
    local archetype = AbyssLoot.GetArchetype(current.archetypeId)
    rerolled.name = grade.name .. "·" .. (archetype and archetype.name or AbyssLoot.GetSlot(slotId).name)
    rerolled.reforgeCount = current.reforgeCount + 1
    rerolled.forgeLevel = current.forgeLevel or 0
    state.abyssEquipment[slotId] = rerolled
    state.abyssDust = state.abyssDust - cost
    if state.Save then state:Save() end
    return true, cost, rerolled
end

function AbyssLoot.GetForgeCost(state, slotId)
    local item = AbyssLoot.GetEquippedItem(state, slotId)
    local grade = item and AbyssLoot.GetGrade(item.grade)
    if not item or not grade or (item.forgeLevel or 0) >= AbyssLoot.MAX_FORGE_LEVEL then return 0 end
    local level = item.forgeLevel or 0
    return math.floor(10 + grade.power * 1.8 + level * level * 2.5)
end

function AbyssLoot.Forge(state, slotId)
    local item = AbyssLoot.GetEquippedItem(state, slotId)
    if not item then return false, "该槽位尚无装备" end
    if (item.forgeLevel or 0) >= AbyssLoot.MAX_FORGE_LEVEL then return false, "已达到 +12" end
    local cost = AbyssLoot.GetForgeCost(state, slotId)
    if (state.abyssDust or 0) < cost then return false, "晶尘不足，需要 " .. cost end
    item.forgeLevel = (item.forgeLevel or 0) + 1
    state.abyssEquipment[slotId] = item
    state.abyssDust = state.abyssDust - cost
    if state.Save then state:Save() end
    return true, cost, item.forgeLevel
end

function AbyssLoot.GetPromoteCost(state, slotId)
    local item = AbyssLoot.GetEquippedItem(state, slotId)
    local grade = item and AbyssLoot.GetGrade(item.grade)
    if not item or not grade or grade.index >= #AbyssLoot.GRADES or (item.forgeLevel or 0) < 5 then return 0 end
    return math.floor(70 + grade.power * 9 + grade.index * grade.index * 8)
end

function AbyssLoot.Promote(state, slotId)
    local item = AbyssLoot.GetEquippedItem(state, slotId)
    local grade = item and AbyssLoot.GetGrade(item.grade)
    if not item or not grade then return false, "该槽位尚无装备" end
    if grade.index >= #AbyssLoot.GRADES then return false, "已达到 SSS" end
    if (item.forgeLevel or 0) < 5 then return false, "装备达到 +5 后才能升阶" end
    local cost = AbyssLoot.GetPromoteCost(state, slotId)
    if (state.abyssDust or 0) < cost then return false, "晶尘不足，需要 " .. cost end
    local nextGrade = AbyssLoot.GRADES[grade.index + 1]
    item.grade, item.forgeLevel = nextGrade.id, item.forgeLevel - 5
    state.abyssEquipment[slotId] = item
    state.abyssDust = state.abyssDust - cost
    if state.Save then state:Save() end
    return true, cost, nextGrade.id
end

function AbyssLoot.RollGrade(state, abyss, layerIndex, chestDrop, randomValue)
    local absoluteFloor = math.max(1, math.floor(tonumber(layerIndex) or 1))
    local runBonus = math.max(0, math.floor(tonumber(abyss and abyss.lootGradeBonus) or 0))
        + math.max(0, math.floor(tonumber(abyss and abyss.extractionStreak) or 0))
        + math.max(0, math.floor(tonumber(abyss and abyss.boons and abyss.boons.abyss_luck) or 0))
    local passiveLuck = AbyssPassives.GetStat(abyss, "luck")
    -- High grades are tied to real tower milestones instead of elapsed time.
    -- This keeps a 700-floor run aspirational without letting a short run
    -- open and fill the whole SSS pool.
    local thresholds = { 1, 1, 8, 18, 40, 85, 160, 320, 600 }
    local effectiveFloor = absoluteFloor + math.min(80, runBonus * 5 + math.floor(passiveLuck / 5)
        + (chestDrop and 8 or 0))
    local maxIndex = 1
    for index, threshold in ipairs(thresholds) do
        if effectiveFloor >= threshold then maxIndex = index end
    end
    local luck = AbyssLoot.GetBonus(state, "loot_luck") + passiveLuck
    local total = 0
    local weights = {}
    for index = 1, maxIndex do
        local highTierBoost = 1 + math.max(0, index - 3) * (math.min(700, absoluteFloor) / 1400 + luck / 220)
        local weight = GRADE_WEIGHTS[index] * highTierBoost
        weights[index] = weight
        total = total + weight
    end
    local roll = Util.Clamp(tonumber(randomValue) or math.random(), 0, 0.999999) * total
    for index = 1, maxIndex do
        roll = roll - weights[index]
        if roll <= 0 then return AbyssLoot.GRADES[index] end
    end
    return AbyssLoot.GRADES[maxIndex]
end

function AbyssLoot.TryDrop(app, abyss, tile, worldX, worldY, force)
    if not app or not abyss or not tile or not app.isAbyssRun then return nil end
    abyss.lootLayers = abyss.lootLayers or {}
    abyss.tilesSinceLoot = math.max(0, math.floor(tonumber(abyss.tilesSinceLoot) or 0)) + 1
    local layer = math.max(1, math.floor(tonumber(tile.abyssFloor or tile.layerIndex) or 1))
    local firstInLayer = abyss.lootLayers[layer] ~= true
    local chestDrop = tile.modifier == "chest"
    -- Tower equipment is a rare chase drop. Entering a new floor and opening
    -- an ordinary chest no longer guarantee a piece; explicit reward rolls
    -- (such as the chest equipment proc) still use force=true.
    local pityTarget = Config.Abyss.lootPityTiles + math.min(180, math.floor((layer - 1) * 0.35))
    local wasPity = force ~= true and abyss.tilesSinceLoot >= pityTarget
    local guaranteed = force == true or wasPity
    local luck = AbyssLoot.GetBonus(app.state, "loot_luck") + AbyssPassives.GetStat(abyss, "luck")
    local routeMultiplier = abyss.route and abyss.route.lootMultiplier or 1
    local chance = (1.2 + math.min(5, abyss.tilesSinceLoot / 18)
        + math.min(2.5, (abyss.time or 0) / 120) + luck / 8
        + (abyss.extractionStreak or 0) * 0.6) * routeMultiplier
        * (Config.Abyss.lootDropChanceMultiplier or 1)
    if not guaranteed and math.random() * 100 >= chance then return nil end

    abyss.lootLayers[layer] = true
    abyss.tilesSinceLoot = 0
    abyss.lootSlotCursor = math.max(1, math.floor(tonumber(abyss.lootSlotCursor) or 1))
    local slotIndex
    if firstInLayer then
        slotIndex = abyss.lootSlotCursor
        abyss.lootSlotCursor = abyss.lootSlotCursor % #AbyssLoot.SLOTS + 1
    else
        slotIndex = math.random(1, #AbyssLoot.SLOTS)
    end
    local grade = AbyssLoot.RollGrade(app.state, abyss, layer, chestDrop)
    local item = AbyssLoot.MakeItem(grade.id, AbyssLoot.SLOTS[slotIndex].id,
        abyss.route and abyss.route.id or "universal")
    if item then item.pityDrop = wasPity end
    if item and app.QueueAbyssLootDrop then
        app:QueueAbyssLootDrop(item, worldX, worldY)
        return item
    end
    return nil
end

function AbyssLoot.GrantBossDrop(app, abyss, floor)
    local slotIndex = (math.floor(floor / 5) - 1) % #AbyssLoot.SLOTS + 1
    local grade = AbyssLoot.RollGrade(app.state, abyss, floor, true, 0.985)
    local item = AbyssLoot.MakeItem(grade.id, AbyssLoot.SLOTS[slotIndex].id,
        abyss.route and abyss.route.id or "universal")
    if item and app.QueueAbyssLootDrop then
        app:QueueAbyssLootDrop(item, app.player.x, app.player.y - 28)
    end
    return item
end

function AbyssLoot.GrantForgeDrop(app, abyss, floor)
    local lowestIndex, candidates = 999, {}
    for index, slot in ipairs(AbyssLoot.SLOTS) do
        local equipped = AbyssLoot.GetEquippedGrade(app.state, slot.id)
        local gradeIndex = equipped and equipped.index or 0
        if gradeIndex < lowestIndex then lowestIndex, candidates = gradeIndex, { index }
        elseif gradeIndex == lowestIndex then candidates[#candidates + 1] = index end
    end
    local slotIndex = candidates[((math.max(1, floor) - 1) % #candidates) + 1]
    local grade = AbyssLoot.RollGrade(app.state, abyss, floor, true, 0.9)
    local item = AbyssLoot.MakeItem(grade.id, AbyssLoot.SLOTS[slotIndex].id,
        abyss.route and abyss.route.id or "universal")
    if item and app.QueueAbyssLootDrop then
        app:QueueAbyssLootDrop(item, app.player.x, app.player.y - 24)
    end
    return item
end

return AbyssLoot
