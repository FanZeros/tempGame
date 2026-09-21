-- UISerializer.lua
-- Serialization for declarative .ui.json layout files.
-- Handles RGBA table → hex string conversion for color properties.

local UISerializer = {}

-- ============================================================================
-- Color Conversion (RGBA table → hex string)
-- ============================================================================

local colorPropertySuffixes = { "Color", "color", "Tint", "tint" }

--- Check if a property name is a color property by suffix.
---@param name string Property name
---@return boolean
local function isColorKey(name)
    if type(name) ~= "string" then return false end
    for _, suffix in ipairs(colorPropertySuffixes) do
        if name:sub(-#suffix) == suffix then
            return true
        end
    end
    return false
end

--- Convert an RGBA table {r, g, b, a} to a hex string.
--- Alpha = 255 → "#RRGGBB", alpha < 255 → "#RRGGBBAA".
---@param color table {r, g, b, a}
---@return string Hex color string
function UISerializer.RGBAToHex(color)
    local r = math.floor(color[1] or 0)
    local g = math.floor(color[2] or 0)
    local b = math.floor(color[3] or 0)
    local a = math.floor(color[4] or 255)

    if a >= 255 then
        return string.format("#%02X%02X%02X", r, g, b)
    else
        return string.format("#%02X%02X%02X%02X", r, g, b, a)
    end
end

-- ============================================================================
-- Deep Copy with Color Conversion
-- ============================================================================

--- Check if a table looks like an RGBA color (array of 3-4 numbers, values 0-255).
---@param t table
---@return boolean
local function isRGBATable(t)
    local len = #t
    if len < 3 or len > 4 then return false end
    for i = 1, len do
        if type(t[i]) ~= "number" then return false end
    end
    return true
end

--- Deep copy a JSON table, converting RGBA color tables back to hex strings.
---@param node table JSON node to copy
---@return table Deep copy with colors converted
local function deepCopyWithColors(node)
    if type(node) ~= "table" then return node end

    local copy = {}
    for k, v in pairs(node) do
        if type(v) == "table" then
            if isColorKey(k) and isRGBATable(v) then
                -- Color property: convert RGBA table → hex string
                copy[k] = UISerializer.RGBAToHex(v)
            elseif k == "children" then
                -- Children array: recurse into each child node
                local childCopies = {}
                for i, child in ipairs(v) do
                    childCopies[i] = deepCopyWithColors(child)
                end
                copy[k] = childCopies
            else
                -- Other tables (boxShadow, gradient, etc.): deep copy
                copy[k] = deepCopyWithColors(v)
            end
        else
            copy[k] = v
        end
    end
    return copy
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Encode a JSON table to a JSON string with colors converted to hex.
--- Deep copies the table to avoid mutating the original instance.json_.
---@param jsonTable table The root JSON table (instance.json_)
---@return string JSON string
function UISerializer.Encode(jsonTable)
    local copy = deepCopyWithColors(jsonTable)
    return cjson.encode(copy)
end

return UISerializer
