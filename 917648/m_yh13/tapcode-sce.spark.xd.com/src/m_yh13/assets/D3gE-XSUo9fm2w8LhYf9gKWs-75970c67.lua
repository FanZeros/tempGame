local Stats = {}
function Stats.New() return { rows = {}, ore = 0, enemy = 0, fuel = 0 } end
function Stats.Record(ledger, source, kind, damage, health)
    if not ledger or ledger.frozen then return end
    local amount = math.min(math.max(0, tonumber(damage) or 0), math.max(0, tonumber(health) or 0))
    if amount <= 0 or amount ~= amount or amount == math.huge then return end
    source = require("diggin.AbyssInscriptions").NormalizeKey(tostring(source or "other"))
    local row = ledger.rows[source] or { source = source, ore = 0, enemy = 0, fuel = 0 }
    ledger.rows[source] = row
    row[kind] = (row[kind] or 0) + amount
    ledger[kind] = (ledger[kind] or 0) + amount
end
function Stats.Rows(ledger)
    local rows = {}
    for _, row in pairs(ledger and ledger.rows or {}) do rows[#rows + 1] = row end
    table.sort(rows, function(a,b)
        local da, db = a.ore + a.enemy, b.ore + b.enemy
        return da == db and a.source < b.source or da > db
    end)
    return rows
end
return Stats
