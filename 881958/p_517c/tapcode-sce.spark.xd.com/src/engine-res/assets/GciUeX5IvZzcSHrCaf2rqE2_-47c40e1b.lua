-- ============================================================================
-- ItemTooltip Component (Global Singleton)
-- UrhoX UI Library - Item tooltip rendered on overlay layer
--
-- Usage:
--   local ItemTooltip = require("urhox-libs/UI/Components/ItemTooltip")
--   ItemTooltip.Show(item, bounds)  -- Show tooltip for item near bounds
--   ItemTooltip.Hide()              -- Hide tooltip
--
-- Item format:
--   {
--     name = "Excalibur",
--     icon = "⚔",                   -- Optional emoji/icon
--     rarity = "legendary",         -- common/uncommon/rare/epic/legendary
--     description = "A legendary sword",
--     stats = { ... },              -- Optional stats table
--   }
-- ============================================================================

local Theme = require("urhox-libs/UI/Core/Theme")

-- ============================================================================
-- Singleton State
-- ============================================================================

local ItemTooltip = {}

local state_ = {
    visible = false,
    item = nil,
    bounds = nil,       -- { x, y, w, h } of trigger element
    opacity = 0,
    targetOpacity = 0,
    registered = false, -- Has been registered with UI system
}

-- UI module (lazy loaded to avoid circular dependency)
local UI_ = nil

local function getUI()
    if not UI_ then
        UI_ = require("urhox-libs/UI/Core/UI")
    end
    return UI_
end

-- ============================================================================
-- Rarity Colors
-- ============================================================================

local RARITY_COLORS = {
    common = { 200, 200, 200, 255 },
    uncommon = { 30, 255, 30, 255 },
    rare = { 100, 150, 255, 255 },
    epic = { 180, 100, 255, 255 },
    legendary = { 255, 180, 80, 255 },
}

-- ============================================================================
-- Registration (called automatically on first Show)
-- ============================================================================

local function ensureRegistered()
    if state_.registered then return end

    local UI = getUI()
    if UI and UI.RegisterGlobalComponent then
        UI.RegisterGlobalComponent("ItemTooltip", ItemTooltip)
        state_.registered = true
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Show item tooltip
---@param item table Item data { name, icon, rarity, description, stats }
---@param bounds table|nil { x, y, w, h } Position to anchor tooltip
function ItemTooltip.Show(item, bounds)
    if not item then return end

    ensureRegistered()

    state_.visible = true
    state_.item = item
    state_.bounds = bounds
    state_.targetOpacity = 1
end

--- Hide item tooltip
function ItemTooltip.Hide()
    state_.visible = false
    state_.targetOpacity = 0
end

--- Check if tooltip is visible
---@return boolean
function ItemTooltip.IsVisible()
    return state_.visible or state_.opacity > 0
end

--- Get current item
---@return table|nil
function ItemTooltip.GetItem()
    return state_.item
end

-- ============================================================================
-- Update (called by UI system via RegisterGlobalComponent)
-- ============================================================================

function ItemTooltip:Update(dt)
    -- Animate opacity
    local speed = 12
    if state_.opacity < state_.targetOpacity then
        state_.opacity = math.min(state_.targetOpacity, state_.opacity + dt * speed)
    elseif state_.opacity > state_.targetOpacity then
        state_.opacity = math.max(state_.targetOpacity, state_.opacity - dt * speed)
    end

    -- Clear item when fully hidden
    if state_.opacity <= 0 and not state_.visible then
        state_.item = nil
        state_.bounds = nil
    end
end

-- ============================================================================
-- Render (called by UI system via RegisterGlobalComponent)
-- ============================================================================

function ItemTooltip:Render(nvg)
    if state_.opacity <= 0 or not state_.item then return end

    local UI = getUI()
    local item = state_.item
    local alpha = state_.opacity

    -- Sizes (all in base pixels)
    local padding = 12
    local fontSize = 14
    local iconSize = 20
    local borderRadius = 8
    local maxWidth = 280
    local lineSpacing = 4

    -- Get rarity color
    local rarityColor = RARITY_COLORS[item.rarity] or RARITY_COLORS.common

    -- Calculate content
    local name = item.name or "Unknown Item"
    local description = item.description
    local stats = item.stats
    local hasIcon = item.icon and #item.icon > 0

    -- Measure text widths
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, fontSize)

    local nameWidth = nvgTextBounds(nvg, 0, 0, name) or (#name * fontSize * 0.5)
    if hasIcon then
        nameWidth = nameWidth + iconSize + 4
    end

    local descWidth = 0
    local descLines = {}
    if description then
        -- Simple word wrap
        nvgFontSize(nvg, fontSize * 0.9)
        local words = {}
        for word in description:gmatch("%S+") do
            table.insert(words, word)
        end

        local line = ""
        local lineWidth = 0
        local spaceWidth = fontSize * 0.3

        for _, word in ipairs(words) do
            local wordWidth = nvgTextBounds(nvg, 0, 0, word) or (#word * fontSize * 0.45)
            if lineWidth + wordWidth > maxWidth - padding * 2 and #line > 0 then
                table.insert(descLines, line)
                descWidth = math.max(descWidth, lineWidth)
                line = word
                lineWidth = wordWidth
            else
                if #line > 0 then
                    line = line .. " " .. word
                    lineWidth = lineWidth + spaceWidth + wordWidth
                else
                    line = word
                    lineWidth = wordWidth
                end
            end
        end
        if #line > 0 then
            table.insert(descLines, line)
            descWidth = math.max(descWidth, lineWidth)
        end
    end

    -- Stats lines
    local statLines = {}
    if stats then
        nvgFontSize(nvg, fontSize * 0.85)
        for statName, statValue in pairs(stats) do
            local statText = string.format("%s: %s", statName, tostring(statValue))
            local statWidth = nvgTextBounds(nvg, 0, 0, statText) or (#statText * fontSize * 0.4)
            table.insert(statLines, { text = statText, width = statWidth })
            descWidth = math.max(descWidth, statWidth)
        end
    end

    -- Calculate tooltip size
    local tooltipWidth = math.max(nameWidth, descWidth, 120) + padding * 2
    tooltipWidth = math.min(tooltipWidth, maxWidth)

    local tooltipHeight = padding * 2 + fontSize + 6  -- Name line + rarity bar
    if #descLines > 0 then
        tooltipHeight = tooltipHeight + lineSpacing + (#descLines * fontSize * 0.9) + (#descLines - 1) * lineSpacing * 0.5
    end
    if #statLines > 0 then
        tooltipHeight = tooltipHeight + lineSpacing * 2 + (#statLines * fontSize * 0.85) + (#statLines - 1) * lineSpacing * 0.5
    end

    -- Calculate position
    local screenWidth = UI.GetWidth() or 800
    local screenHeight = UI.GetHeight() or 600
    local tipX, tipY

    if state_.bounds then
        local b = state_.bounds
        -- Position below the trigger
        tipX = b.x
        tipY = b.y + b.h + 6

        -- Adjust if out of bounds
        if tipX + tooltipWidth > screenWidth - 8 then
            tipX = screenWidth - tooltipWidth - 8
        end
        if tipX < 8 then
            tipX = 8
        end
        if tipY + tooltipHeight > screenHeight - 8 then
            -- Show above instead
            tipY = b.y - tooltipHeight - 6
        end
        if tipY < 8 then
            tipY = 8
        end
    else
        -- Center fallback
        tipX = (screenWidth - tooltipWidth) / 2
        tipY = (screenHeight - tooltipHeight) / 2
    end

    -- Draw shadow
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tipX + 2, tipY + 2, tooltipWidth, tooltipHeight, borderRadius)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(80 * alpha)))
    nvgFill(nvg)

    -- Draw background
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tipX, tipY, tooltipWidth, tooltipHeight, borderRadius)
    nvgFillColor(nvg, nvgRGBA(20, 22, 28, math.floor(250 * alpha)))
    nvgFill(nvg)

    -- Draw border with rarity color
    nvgStrokeColor(nvg, nvgRGBA(rarityColor[1], rarityColor[2], rarityColor[3], math.floor(180 * alpha)))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- Draw rarity indicator line at top
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tipX + 4, tipY + 4, tooltipWidth - 8, 3, 1.5)
    nvgFillColor(nvg, nvgRGBA(rarityColor[1], rarityColor[2], rarityColor[3], math.floor(200 * alpha)))
    nvgFill(nvg)

    -- Content position
    local contentX = tipX + padding
    local contentY = tipY + padding + 6  -- Extra space for rarity line

    -- Draw icon + name
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, fontSize)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    if hasIcon then
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * alpha)))
        nvgText(nvg, contentX, contentY, item.icon)
        contentX = contentX + iconSize + 4
    end

    nvgFillColor(nvg, nvgRGBA(rarityColor[1], rarityColor[2], rarityColor[3], math.floor(255 * alpha)))
    nvgText(nvg, contentX, contentY, name)

    contentX = tipX + padding
    contentY = contentY + fontSize + lineSpacing

    -- Draw description
    if #descLines > 0 then
        nvgFontSize(nvg, fontSize * 0.9)
        nvgFillColor(nvg, nvgRGBA(180, 180, 190, math.floor(255 * alpha)))
        for _, line in ipairs(descLines) do
            nvgText(nvg, contentX, contentY, line)
            contentY = contentY + fontSize * 0.9 + lineSpacing * 0.5
        end
    end

    -- Draw stats
    if #statLines > 0 then
        contentY = contentY + lineSpacing
        nvgFontSize(nvg, fontSize * 0.85)
        nvgFillColor(nvg, nvgRGBA(100, 200, 100, math.floor(255 * alpha)))
        for _, stat in ipairs(statLines) do
            nvgText(nvg, contentX, contentY, stat.text)
            contentY = contentY + fontSize * 0.85 + lineSpacing * 0.5
        end
    end
end

-- ============================================================================
-- HitTest (prevent clicks through tooltip)
-- ============================================================================

function ItemTooltip:HitTest(x, y)
    -- Tooltip doesn't capture clicks, let them pass through
    return false
end

return ItemTooltip
