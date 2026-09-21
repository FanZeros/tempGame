local Util = {}

function Util.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Util.Lerp(a, b, t)
    return a + (b - a) * t
end

function Util.Sign(value)
    if value < 0 then return -1 end
    if value > 0 then return 1 end
    return 0
end

function Util.Length(x, y)
    return math.sqrt(x * x + y * y)
end

function Util.Normalize(x, y)
    local length = Util.Length(x, y)
    if length <= 0.00001 then
        return 0, 1
    end
    return x / length, y / length
end

function Util.Hash01(x, y, seed)
    local n = math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453123
    return n - math.floor(n)
end

function Util.HashInt(x, y, seed, minimum, maximum)
    return minimum + math.floor(Util.Hash01(x, y, seed) * (maximum - minimum + 1))
end

function Util.Color(v, alpha)
    return nvgRGBA(v[1], v[2], v[3], alpha or v[4] or 255)
end

function Util.Copy(source)
    if type(source) ~= "table" then return source end
    local result = {}
    for key, value in pairs(source) do
        result[key] = Util.Copy(value)
    end
    return result
end

function Util.PointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function Util.FormatNumber(value)
    value = math.floor(value or 0)
    if value < 1000 then return tostring(value) end
    local suffixes = { "K", "M", "B", "T", "Qa", "Qi" }
    local scaled = value
    local suffix = 0
    while scaled >= 1000 and suffix < #suffixes do
        scaled = scaled / 1000
        suffix = suffix + 1
    end
    if scaled >= 100 then
        return string.format("%.0f%s", scaled, suffixes[suffix])
    elseif scaled >= 10 then
        return string.format("%.1f%s", scaled, suffixes[suffix])
    end
    return string.format("%.2f%s", scaled, suffixes[suffix])
end

return Util
