local Tools = require("diggin.AbyssRunTools")
local Passives = require("diggin.AbyssPassives")
local PortalSchedule = require("diggin.AbyssPortalSchedule")
local Build = {}

function Build.IsMilestone(floor)
    if math.floor(tonumber(floor) or 0) < 1 then return false end
    return PortalSchedule.IsPortalFloor(floor)
end

function Build.Make(state, abyss, floor)
    local tools = Tools.MakeChoice(state, abyss, floor)
    local passives = Passives.MakeChoice(abyss, floor)
    local options, seen = {}, {}
    -- Alternate the two pools; never pad an exhausted build with supplies.
    for index = 1, 3 do
        for _, choice in ipairs({ tools or false, passives or false }) do
            local option = choice and choice.options[index]
            if option and not option.reward and not seen[option.id] and #options < 3 then
                options[#options + 1], seen[option.id] = option, true
            end
        end
    end
    if #options == 0 then return nil end
    return { kind = "build", floor = floor, options = options,
        title = "构筑选择 · 道具与被动", description = "本局最多5件道具、5个被动，各最高5级" }
end

return Build
