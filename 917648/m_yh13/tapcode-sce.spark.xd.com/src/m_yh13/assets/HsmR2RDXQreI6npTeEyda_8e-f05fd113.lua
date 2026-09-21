local Config = require("diggin.Config")

local DamageBreakdown = {}

local ACTIVE_NODE_TO_ID = {
    DynamiteActive = "dynamite",
    ShockwaveActive = "shockwave",
    Shrapnel = "shrapnel_debris",
    Boomerang = "pickarang",
    DrillMissiles = "drill_missile",
    DrillDrones = "drill_drones",
    SpinningPickaxe = "pickaxe_orbit",
    BouncingBall = "bouncing_ball",
    BulletWorms = "bullet_worms",
}

local CAPSTONE_MULTIPLIERS = {
    FallingPickaxe = { multiplier = Config.CapstoneDamageMultipliers.FallingPickaxe, suffix = "每次命中／落地爆炸" },
    TermiteDrones = { multiplier = Config.CapstoneDamageMultipliers.TermiteDrones, suffix = "每架无人机每次命中" },
    Molenir = { multiplier = Config.CapstoneDamageMultipliers.Molenir, suffix = "撞击及爆炸各一次" },
    TheWorm = { multiplier = Config.CapstoneDamageMultipliers.TheWorm, suffix = "每 0.11 秒一次" },
}

local function numberText(value)
    value = tonumber(value) or 0
    if math.abs(value - math.floor(value)) < 0.001 then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end

function DamageBreakdown.GetNodeLines(node, state)
    if not node or not state then return {} end
    local drillDamage = state:GetGeneralStat("drill_damage")
    local activeId = ACTIVE_NODE_TO_ID[node.id]
    if not activeId and node.stat_id == "damage" and Config.ActiveBaseStats[node.upgrade_id] then
        activeId = node.upgrade_id
    end
    if activeId and Config.ActiveBaseStats[activeId] then
        local percent = state:GetActiveStat(activeId, "damage")
        local damage = drillDamage * percent / 100
        return {
            string.format("伤害公式：钻头 %s × %s%% = %s/次", numberText(drillDamage), numberText(percent), numberText(damage)),
            "钻头伤害提高后，该技能伤害会同步提高。",
        }
    end
    local capstone = CAPSTONE_MULTIPLIERS[node.id]
    if capstone then
        local damage = drillDamage * capstone.multiplier
        return {
            string.format("伤害公式：钻头 %s × %s = %s", numberText(drillDamage), numberText(capstone.multiplier), numberText(damage)),
            "结算方式：" .. capstone.suffix .. "；会随钻头伤害成长。",
        }
    end
    return {}
end

return DamageBreakdown
