local Config = require("diggin.Config")
local DamageBreakdown = require("diggin.DamageBreakdown")

local SkillText = {}

local BRANCH_NAMES = {
    core = "核心", damage = "伤害", fuel = "燃料", quake = "震荡", world = "世界",
}

local STAT_NAMES = {
    additional_amount = "额外产量", amount = "数量", attack_speed = "攻击速度",
    chance = "触发概率", cooldown = "触发间隔", crit_proc = "暴击触发率",
    critical_chance = "钻头暴击率", critical_damage_multiplier = "暴击伤害倍率",
    damage = "技能伤害", diamond_enabled = "钻石精炼", diamond_mult = "钻石产量",
    diamond_smelting_rate = "钻石精炼间隔", drill_damage = "钻头伤害",
    drill_speed = "钻探速度", duration = "持续时间", emerald_enabled = "绿宝石精炼",
    emerald_mult = "绿宝石产量", emerald_smelting_rate = "绿宝石精炼间隔",
    energy_per_drill_hit = "每次钻击充能", explosion_radius = "爆炸半径",
    fov_radius = "照明视野", fuel_amount = "最大燃料", fuel_efficiency = "燃料效率",
    laser_amount = "激光容量", laser_drill_scaling = "钻头伤害转化",
    last_ditch = "背水增幅", lifetime = "持续时间", movement_speed = "移动速度",
    overdrive_amount = "超频容量", overdrive_regeneration = "超频恢复",
    overdrive_strength = "超频伤害", production_amount = "单次产量",
    production_rate = "生产间隔", radius = "作用半径", ruby_mult = "红宝石产量",
    ruby_smelting_rate = "红宝石精炼间隔", tiles = "影响方块数", world_width = "矿井宽度",
}

local SERIES_NAMES = {
    MiningDamage = "钻头威力", FuelTank = "燃料容量", FuelEfficiency = "燃料效率",
    CritChance = "暴击率", CritDamage = "暴击伤害", MiningRate = "钻探速度",
    FieldOfView = "照明视野",
}

local DESCRIPTION_OVERRIDES = {
    OverdriveActive = "按住钻探圆盘或鼠标左键进入超频；消耗超频能量，显著提高钻击威力与推进速度。",
    Laser = "能量足够时，按住右侧“光”键或鼠标右键发射远程钻探光束；终极密度同样可用。",
    LaserDamage = "提高钻头伤害转化；达到3级后激光分裂为三束，侧束继承55%伤害。",
    UpgradeStart = "钻探旅程的起点。购买相邻节点后，四条成长路线会逐步展开。",
}

local function numberText(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value)) < 0.001 then return tostring(math.floor(value)) end
    local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
    return text
end

local function isPercentStat(node)
    return node.upgrade_type == 1 or node.stat_id == "chance"
        or node.stat_id == "critical_chance" or node.stat_id == "crit_proc"
        or node.stat_id == "last_ditch"
end

local function currentValue(node, state)
    if not node.is_stat then return nil end
    if node.upgrade_id == "general_stats" then return state:GetGeneralStat(node.stat_id) end
    if Config.ActiveBaseStats[node.upgrade_id] then return state:GetActiveStat(node.upgrade_id, node.stat_id) end
    return nil
end

local function valueWithUnit(node, value, signed)
    local prefix = signed and ((value or 0) >= 0 and "+" or "") or ""
    local suffix = isPercentStat(node) and "%" or ""
    if node.stat_id == "critical_damage_multiplier" then suffix = "倍" end
    return prefix .. numberText(value) .. suffix
end

function SkillText.GetName(node)
    local prefix, tier = tostring(node.id or ""):match("^([A-Za-z_]+)(%d+)$")
    if prefix and SERIES_NAMES[prefix] then return SERIES_NAMES[prefix] .. " " .. tier end
    return tostring(node.name or node.name_en or "未命名天赋")
end

function SkillText.GetSummary(node, state)
    if DESCRIPTION_OVERRIDES[node.id] then return DESCRIPTION_OVERRIDES[node.id] end
    local text = tostring(node.description or "暂无说明")
    text = text:gsub('%[img.-%]res://Assets/ControlsUI/lmb%.tres%[/img%]', "钻探圆盘或鼠标左键")
    text = text:gsub('%[img.-%]res://Assets/ControlsUI/rmb%.tres%[/img%]', "右侧光束键或鼠标右键")
    text = text:gsub("%b[]", ""):gsub("res://[%w%p]+", "操作键")
    -- gsub replacement strings treat '%' as an escape marker. Percentage
    -- talents therefore threw here (for example "+20%") and aborted the
    -- entire NanoVG frame. A function replacement returns the text verbatim.
    local statAmountText = valueWithUnit(node, node.stat_amount or 0, false)
    text = text:gsub("{statAmount}", function() return statAmountText end)
    local current = currentValue(node, state) or node.stat_amount or 0
    local currentAmountText = numberText(current)
    text = text:gsub("{currentAmount}", function() return currentAmountText end)
    return text
end

function SkillText.GetDetail(node, state)
    local lines = {
        string.format("路线：%s  ·  类型：%s", BRANCH_NAMES[node.branch] or "特殊",
            node.is_artefact and "天赋遗物" or (node.is_stat and "数值强化" or "技能机制")),
    }
    if node.is_stat then
        local label = STAT_NAMES[node.stat_id] or "技能数值"
        lines[#lines + 1] = "每级效果：" .. label .. " " .. valueWithUnit(node, node.stat_amount or 0, true)
        local current = currentValue(node, state)
        if current ~= nil then lines[#lines + 1] = "当前总值：" .. valueWithUnit(node, current, false) end
    end
    if node.is_artefact then
        if state:GetLevel(node.id) > 0 then
            lines[#lines + 1] = "天赋遗物：已镶入并生效；后续等级只消耗资源。"
        elseif state.artefacts[node.id] then
            lines[#lines + 1] = "天赋遗物：已持有；购买首级时镶入并开始生效。"
        else
            lines[#lines + 1] = "获得方式：打开任意矿井宝箱随机发现，并永久记录到天赋遗物图鉴。"
        end
        lines[#lines + 1] = "查看位置：主菜单 → 遗物库 → 天赋遗物 → " .. SkillText.GetName(node)
    end
    if node.cost and node.cost.MissionRewardOre then
        lines[#lines + 1] = "任务徽章：每个密度首次到达每层获得 30 枚；旧记录自动补发差额。"
    end
    for _, line in ipairs(DamageBreakdown.GetNodeLines(node, state)) do
        lines[#lines + 1] = line
    end
    local parentId = node.parents and node.parents[1]
    local parent = parentId and state.nodeById[parentId]
    if parent then
        lines[#lines + 1] = string.format("前置：%s 达到 %d 级", SkillText.GetName(parent), node.level_to_unlock or 1)
    else
        lines[#lines + 1] = "前置：无"
    end
    return table.concat(lines, "\n")
end

return SkillText
