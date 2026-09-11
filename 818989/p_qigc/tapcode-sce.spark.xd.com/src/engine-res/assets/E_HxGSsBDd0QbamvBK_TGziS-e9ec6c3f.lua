-- ============================================================================
-- UIInspector - Shared Context
-- Centralized state, constants, and utility functions for all inspector modules
-- ============================================================================

local Style = require("urhox-libs/UI/Core/Style")
local Theme = require("urhox-libs/UI/Core/Theme")
local ColorPicker = require("urhox-libs/UI/Widgets/ColorPicker")
local Schema = require("urhox-libs/UI/Core/UIInspector/Schema")

local ctx = {}

-- ============================================================================
-- State Machine Constants
-- ============================================================================

ctx.STATE_IDLE       = "idle"
ctx.STATE_PICKING    = "picking"
ctx.STATE_DESCRIBING = "describing"
ctx.STATE_EDITING    = "editing"

-- ============================================================================
-- Shared Mutable State
-- ============================================================================

ctx.state             = "idle"
ctx.uiModule          = nil
ctx.hoveredWidget     = nil
ctx.hoverEditWidget   = nil
ctx.editToolHoverTip  = nil
ctx.pointerOverInspectorChrome = false
ctx.activeWidget      = nil
ctx.selectedWidget    = nil -- compatibility alias for activeWidget
ctx.inspectedWidgets  = {}
ctx.selectedWidgets   = {}
ctx.multiSelect        = false
ctx.lastActiveWidget   = nil
ctx.selectionLimitPulseTime = nil
ctx.eventNode         = nil
ctx.eventScriptObject = nil
ctx.HOTKEY            = nil

-- Quick Tweak state
ctx.propsSnapshots            = {}
ctx.copiedSnapshots           = nil
ctx.tweakFields               = {}
ctx.dragState                 = nil
ctx.editPending               = nil
ctx.editState                 = nil
ctx.editRecords               = {}
ctx.copiedEditRecordCount     = 0
ctx.inspectorOverlayCallbacks = {}
ctx.confirmOverlay            = nil
ctx.propKeyTooltip            = nil
ctx.propContextMenu           = nil
ctx.layoutConstraintHints     = {}
ctx.widgetPrompts             = {}
ctx.groupPrompt               = ""
ctx.groupPromptSignature      = nil
ctx.groupPromptWidgets        = nil
ctx.expandedPromptWidget      = nil
ctx.selectedWidgetInfoExpanded = {}
ctx.selectedWidgetListExpanded = false

-- Panel state
ctx.inspectorPanelRoot = nil
ctx.descTextField      = nil
ctx.groupDescTextField = nil
ctx.inspectorPanelDrag = nil
ctx.inspectorPanelResizeDrag = nil
ctx.inspectorPanelHeightRatio = nil
ctx.inspectorPanelHeight = nil
ctx.inspectorPanelDefaultHeight = nil
ctx.inspectorPanelUserResized = false

-- UIInspector table reference (set by init.lua for cross-module access)
ctx.UIInspector = nil

-- ============================================================================
-- Module References
-- ============================================================================

ctx.Style       = Style
ctx.Theme       = Theme
ctx.ColorPicker = ColorPicker
ctx.Schema      = Schema

function ctx.nowSeconds()
    if time and time.GetElapsedTime then
        return time:GetElapsedTime()
    elseif time and time.elapsedTime then
        return time.elapsedTime
    end
    return os.clock and os.clock() or 0
end

-- ============================================================================
-- Constants
-- ============================================================================

-- Highlight colors
ctx.HOVER_FILL      = { 255, 255, 255, 24 }
ctx.HOVER_STROKE    = { 255, 255, 255, 205 }
ctx.SELECT_FILL     = { 255, 185, 80, 52 }
ctx.SELECT_STROKE   = { 255, 185, 80, 245 }
ctx.SELECT2_FILL    = { 255, 255, 255, 28 }
ctx.SELECT2_STROKE  = { 255, 255, 255, 230 }
ctx.ACTIVE_STROKE   = { 255, 185, 80, 255 }
ctx.DIRTY_COLOR     = { 255, 252, 238, 235 }
ctx.PROMPT_COLOR    = { 255, 255, 255, 165 }
ctx.ANCESTOR_STROKE = { 255, 255, 255, 45 }
ctx.HIGHLIGHT_WIDTH = 2.0

-- Tweak label colors
ctx.TWEAK_LABEL_NORMAL   = { 191, 191, 191 }
ctx.TWEAK_LABEL_MODIFIED = { 245, 166, 35 }

-- Box model colors (Chrome DevTools style)
ctx.MARGIN_COLOR  = { 246, 178, 107, 100 }
ctx.PADDING_COLOR = { 147, 196, 125, 100 }
ctx.CONTENT_COLOR = { 111, 168, 220, 80 }

-- ============================================================================
-- Property Definitions
-- ============================================================================

ctx.AI_PROMPT_PREVIEW_CHARS = 16

Schema.apply()

local function inferPropOrder(key)
    local order = Schema.getPropOrder(key)
    if order then return order end
    return 99999
end

function ctx.getPropLabel(key)
    return Schema.getPropLabel(key)
end

function ctx.comparePropKeys(a, b)
    local ao = inferPropOrder(a)
    local bo = inferPropOrder(b)
    if ao ~= bo then return ao < bo end
    return tostring(a) < tostring(b)
end

function ctx.sortPropKeys(keys)
    table.sort(keys, ctx.comparePropKeys)
    return keys
end

function ctx.getWidgetScreenRect(widget)
    if not ctx.isWidgetAlive(widget) then return nil end
    local layout = nil
    if ctx.uiModule and ctx.uiModule.GetVisualRect then
        layout = ctx.uiModule.GetVisualRect(widget)
    elseif widget.GetAbsoluteLayoutForHitTest then
        layout = widget:GetAbsoluteLayoutForHitTest()
    elseif widget.GetAbsoluteLayout then
        layout = widget:GetAbsoluteLayout()
    end
    if not layout or layout.x ~= layout.x or layout.y ~= layout.y
        or layout.w ~= layout.w or layout.h ~= layout.h then return nil end
    return { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
end

function ctx.getWidgetLayoutRect(widget)
    if not ctx.isWidgetAlive(widget) or not widget.GetAbsoluteLayout then return nil end
    local layout = widget:GetAbsoluteLayout()
    if not layout or layout.x ~= layout.x or layout.y ~= layout.y
        or layout.w ~= layout.w or layout.h ~= layout.h then return nil end
    return { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
end

function ctx.getEditablePropsForWidgets(widgets)
    return Schema.getEditableProps(widgets, ctx.sortPropKeys)
end

function ctx.getPropDefForSelection(key, widgets)
    return Schema.getPropDefForWidgets(key, widgets)
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

--- Check if widget is still alive (not destroyed)
function ctx.isWidgetAlive(widget)
    return widget and widget.node ~= nil and widget.props ~= nil
end

--- Compare two values (handles tables like spacing/color)
function ctx.valuesEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end

    for k, v in pairs(a) do
        if not ctx.valuesEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

--- Deep copy a value (for snapshotting)
function ctx.deepCopyValue(v)
    if type(v) ~= "table" then return v end
    local copy = {}
    for i = 1, #v do copy[i] = ctx.deepCopyValue(v[i]) end
    for k, val in pairs(v) do
        if type(k) == "string" then copy[k] = ctx.deepCopyValue(val) end
    end
    return copy
end

--- Format source location as short string
function ctx.formatSource(widget)
    if not widget._sourceFile then return "" end
    local shortSrc = widget._sourceFile:match("[/\\]([^/\\]+)$") or widget._sourceFile
    return " (" .. shortSrc .. ":" .. (widget._sourceLine or "?") .. ")"
end

function ctx.escapeStringForInput(value)
    if value == nil then return "" end
    local s = tostring(value)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\t", "\\t")
    return s
end

function ctx.unescapeStringFromInput(value)
    local map = {
        n = "\n",
        r = "\r",
        t = "\t",
        ["\\"] = "\\",
    }
    local result = tostring(value or ""):gsub("\\([nrt\\])", map)
    return result
end

--- Format a property value to display string
function ctx.formatPropValue(widget, key)
    local def = Schema.getWidgetPropDef(key, widget)
    local v = widget.props[key]
    if not def then
        if v == nil then return "" end
        if type(v) == "string" then return ctx.escapeStringForInput(v) end
        if type(v) == "boolean" then return tostring(v) end
        if type(v) == "number" then
            if v == math.floor(v) then return tostring(math.floor(v)) end
            return string.format("%.1f", v)
        end
        if type(v) == "table" then
            if type(key) == "string" and key:sub(-5):lower() == "color" and #v >= 3 then
                local r, g, b, a = v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 255
                if a ~= 255 then
                    return string.format("#%02X%02X%02X%02X", r, g, b, a)
                end
                return string.format("#%02X%02X%02X", r, g, b)
            end
            local parts = {}
            for i = 1, #v do parts[#parts + 1] = tostring(v[i]) end
            if #parts > 0 then return "{" .. table.concat(parts, ", ") .. "}" end
            return tostring(v)
        end
        return tostring(v)
    end

    if def.type == "string" or def.type == "path" or def.type == "enum" then
        if def.type == "string" then
            return ctx.escapeStringForInput(v)
        end
        return v and tostring(v) or ""

    elseif def.type == "boolean" then
        if v == nil then return "" end
        return tostring(v)

    elseif def.type == "number" then
        if not v then return "" end
        if type(v) == "string" then return v end
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return string.format("%.1f", v)

    elseif def.type == "layout" then
        if v == nil then return "" end
        if type(v) == "number" then
            if v == math.floor(v) then return tostring(math.floor(v)) end
            return string.format("%.1f", v)
        end
        return tostring(v)

    elseif def.type == "color" then
        if not v or type(v) ~= "table" then return "" end
        local r, g, b, a = v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 255
        if a ~= 255 then
            return string.format("#%02X%02X%02X%02X", r, g, b, a)
        end
        return string.format("#%02X%02X%02X", r, g, b)

    elseif def.type == "spacing" then
        if v ~= nil then
            if type(v) == "number" then
                return tostring(math.floor(v))
            elseif type(v) == "table" and #v > 0 then
                if #v >= 4 and v[1] == v[2] and v[2] == v[3] and v[3] == v[4] then
                    return tostring(math.floor(v[1]))
                end
                local parts = {}
                for i = 1, #v do parts[i] = tostring(math.floor(v[i])) end
                return table.concat(parts, " ")
            end
        end
        -- Fallback: read per-side props
        local sides = { "Top", "Right", "Bottom", "Left" }
        local vals = {}
        local hasAny = false
        for i, side in ipairs(sides) do
            local sv = widget.props[key .. side]
            if sv and type(sv) == "number" then
                vals[i] = math.floor(sv)
                hasAny = true
            else
                vals[i] = 0
            end
        end
        if not hasAny then return "0" end
        if vals[1] == vals[2] and vals[2] == vals[3] and vals[3] == vals[4] then
            return tostring(vals[1])
        end
        return vals[1] .. " " .. vals[2] .. " " .. vals[3] .. " " .. vals[4]
    end

    return ""
end

return ctx
