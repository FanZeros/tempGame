local Schedule = {}

local function normalizeFloor(floor)
    return math.max(1, math.floor(tonumber(floor) or 1))
end

function Schedule.GetInterval(floor)
    floor = normalizeFloor(floor)
    if floor < 50 then return 3 end
    if floor < 100 then return 5 end
    return 10
end

function Schedule.IsPortalFloor(floor)
    floor = normalizeFloor(floor)
    -- Floors 50 and 100 are explicit transition checkpoints between cadence
    -- bands, even though 50 is not divisible by the preceding three-floor band.
    if floor == 50 or floor == 100 then return true end
    return floor % Schedule.GetInterval(floor) == 0
end

function Schedule.GetNextPortalFloor(floor)
    floor = normalizeFloor(floor)
    local candidate = floor
    if Schedule.IsPortalFloor(candidate) then return candidate end
    repeat candidate = candidate + 1 until Schedule.IsPortalFloor(candidate)
    return candidate
end

return Schedule
