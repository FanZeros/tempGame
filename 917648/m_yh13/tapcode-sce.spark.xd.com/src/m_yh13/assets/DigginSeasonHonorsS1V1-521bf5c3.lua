-- Final S1 standings must be copied from a verified cutoff snapshot, never
-- inferred from live ranks: old clients can still submit to the old keys.
local Honors = {}
Honors.sealed = false
Honors.cutoff = ""
Honors.winners = { endless = {}, hardcore = {} }
-- Each entry: { userId = "stable-account-id", nickname = "display only", floor = 0 }
Honors.skinAtlas = "image/diggin/generated/abyss/season1_costumes-v1.png"
Honors.skinNames = { "鎏金先锋", "秘银巡猎", "赤铜守望" }

function Honors.GetSkinRank(userId)
    if not Honors.sealed or not userId or tostring(userId) == "0" then return nil end
    local best
    for _, mode in ipairs({ "endless", "hardcore" }) do
        for rank, row in ipairs(Honors.winners[mode] or {}) do
            if rank <= 3 and tostring(row.userId) == tostring(userId) then
                best = math.min(best or rank, rank)
            end
        end
    end
    return best
end

function Honors.GetCurrentSkinRank()
    return Honors.GetSkinRank(clientCloud and clientCloud.userId)
end

return Honors
