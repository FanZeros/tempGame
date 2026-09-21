local Config = require("diggin.Config")
local Util = require("diggin.Util")

local MobileControlLayout = {}

MobileControlLayout.ORDER = { "move", "aim", "jump", "auto", "laser" }
MobileControlLayout.DEFINITIONS = {
    move = { label = "移动圆盘", shape = "circle", xField = "moveX", yField = "moveY",
        radiusField = "moveRadius", paddingField = "moveTouchPadding" },
    aim = { label = "钻头圆盘", shape = "circle", xField = "aimX", yField = "aimY",
        radiusField = "aimRadius", paddingField = "aimTouchPadding" },
    jump = { label = "跳跃", shape = "rect", xField = "jumpX", yField = "jumpY",
        wField = "jumpW", hField = "jumpH" },
    auto = { label = "自动钻探", shape = "rect", xField = "autoX", yField = "autoY",
        wField = "autoW", hField = "autoH" },
    laser = { label = "激光", shape = "rect", xField = "laserX", yField = "laserY",
        wField = "laserW", hField = "laserH" },
}

local function copyControls()
    local result = {}
    for key, value in pairs(Config.Controls) do result[key] = value end
    return result
end

local function normalizedEntry(id, value)
    local definition = MobileControlLayout.DEFINITIONS[id]
    local defaults = Config.Controls
    value = type(value) == "table" and value or {}
    if definition.shape == "circle" then
        local radius = defaults[definition.radiusField] + defaults[definition.paddingField]
        return {
            x = Util.Clamp(tonumber(value.x) or defaults[definition.xField], radius, Config.DESIGN_WIDTH - radius),
            y = Util.Clamp(tonumber(value.y) or defaults[definition.yField], 105 + radius, Config.DESIGN_HEIGHT - radius),
        }
    end
    local width, height = defaults[definition.wField], defaults[definition.hField]
    return {
        x = Util.Clamp(tonumber(value.x) or defaults[definition.xField], 2, Config.DESIGN_WIDTH - width - 2),
        y = Util.Clamp(tonumber(value.y) or defaults[definition.yField], 105, Config.DESIGN_HEIGHT - height - 2),
    }
end

function MobileControlLayout.Normalize(saved)
    local result = {}
    for _, id in ipairs(MobileControlLayout.ORDER) do
        result[id] = normalizedEntry(id, saved and saved[id])
    end
    return result
end

function MobileControlLayout.ToControls(saved)
    local layout = copyControls()
    saved = MobileControlLayout.Normalize(saved)
    for _, id in ipairs(MobileControlLayout.ORDER) do
        local definition, entry = MobileControlLayout.DEFINITIONS[id], saved[id]
        layout[definition.xField], layout[definition.yField] = entry.x, entry.y
    end
    return layout
end

function MobileControlLayout.GetBounds(saved, id)
    local definition = MobileControlLayout.DEFINITIONS[id]
    if not definition then return nil end
    local entry = MobileControlLayout.Normalize(saved)[id]
    if definition.shape == "circle" then
        local radius = Config.Controls[definition.radiusField] + Config.Controls[definition.paddingField]
        return { x = entry.x - radius, y = entry.y - radius, w = radius * 2, h = radius * 2,
            circle = true, cx = entry.x, cy = entry.y, radius = radius }
    end
    return { x = entry.x, y = entry.y, w = Config.Controls[definition.wField], h = Config.Controls[definition.hField] }
end

local function overlaps(a, b)
    return a.x < b.x + b.w and a.x + a.w > b.x
        and a.y < b.y + b.h and a.y + a.h > b.y
end

function MobileControlLayout.SetPosition(saved, id, pointerX, pointerY)
    local definition = MobileControlLayout.DEFINITIONS[id]
    if not definition then return false, MobileControlLayout.Normalize(saved) end
    local result = MobileControlLayout.Normalize(saved)
    local value = { x = pointerX, y = pointerY }
    if definition.shape == "rect" then
        value.x = pointerX - Config.Controls[definition.wField] * 0.5
        value.y = pointerY - Config.Controls[definition.hField] * 0.5
    end
    result[id] = normalizedEntry(id, value)
    local candidate = MobileControlLayout.GetBounds(result, id)
    for _, otherId in ipairs(MobileControlLayout.ORDER) do
        if otherId ~= id and overlaps(candidate, MobileControlLayout.GetBounds(result, otherId)) then
            return false, MobileControlLayout.Normalize(saved)
        end
    end
    return true, result
end

function MobileControlLayout.Hit(saved, x, y)
    for index = #MobileControlLayout.ORDER, 1, -1 do
        local id = MobileControlLayout.ORDER[index]
        local bounds = MobileControlLayout.GetBounds(saved, id)
        local inside = bounds.circle
            and Util.Length(x - bounds.cx, y - bounds.cy) <= bounds.radius
            or (not bounds.circle and Util.PointInRect(x, y, bounds))
        if inside then return id end
    end
    return nil
end

return MobileControlLayout
