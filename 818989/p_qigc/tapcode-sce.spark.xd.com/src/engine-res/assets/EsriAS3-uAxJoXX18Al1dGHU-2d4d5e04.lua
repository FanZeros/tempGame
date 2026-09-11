-- ============================================================================
-- UIInspector - Report Module
-- Report generation, serialization, clipboard export format
-- ============================================================================

return function(ctx, Selection)

local M = {}
local isWidgetAlive = ctx.isWidgetAlive
local formatSource = ctx.formatSource

-- ============================================================================
-- Props Serialization
-- ============================================================================

--- Check if a prop should be exported (skip callbacks, internals, defaults)
local function shouldExportProp(key, value)
    if type(key) ~= "string" then return false end
    -- Skip internal fields
    if key:sub(1, 1) == "_" then return false end
    if key:sub(-1) == "_" then return false end
    -- Skip functions/callbacks
    if type(value) == "function" then return false end
    -- Skip event handlers (onXxx)
    if #key > 2 and key:sub(1, 2) == "on" and key:sub(3, 3):match("[A-Z]") then return false end
    -- Skip common defaults
    if key == "visible" and value == true then return false end
    if key == "pointerEvents" and value == "box-none" then return false end
    -- Skip userdata
    if type(value) == "userdata" then return false end
    -- Skip children array stored in props
    if key == "children" then return false end
    return true
end

--- Serialize a value to a readable string
local function serializeValue(v)
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
    elseif t == "number" then
        if v == math.floor(v) then
            return tostring(math.floor(v))
        end
        return string.format("%.2f", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        -- Array-like table (color, etc.)
        local arr = {}
        for i = 1, #v do
            arr[i] = tostring(v[i])
        end
        if #arr > 0 then
            return "{" .. table.concat(arr, ", ") .. "}"
        end
        -- Named table (small)
        local parts = {}
        for k, val in pairs(v) do
            if type(k) == "string" then
                parts[#parts + 1] = k .. "=" .. serializeValue(val)
            end
        end
        if #parts > 0 then
            table.sort(parts)
            return "{" .. table.concat(parts, ", ") .. "}"
        end
        return "{}"
    end
    return tostring(v)
end

--- Serialize widget props to a single-line string
local function serializeProps(props)
    local keys = {}
    for k, v in pairs(props) do
        if shouldExportProp(k, v) then
            keys[#keys + 1] = k
        end
    end
    if #keys == 0 then return "{}" end

    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. "=" .. serializeValue(props[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local COMPACT_PROP_KEYS = {
    "id", "text", "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
    "aspectRatio", "flexBasis",
    "position", "left", "top", "right", "bottom",
    "margin", "marginTop", "marginRight", "marginBottom", "marginLeft",
    "padding", "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
    "flexDirection", "justifyContent", "alignItems", "gap", "rowGap", "columnGap",
    "fontSize", "backgroundColor", "backgroundImage", "opacity", "zIndex",
}

local function serializeCompactProps(widget)
    if not isWidgetAlive(widget) then return "{}" end
    local parts = {}
    for _, key in ipairs(COMPACT_PROP_KEYS) do
        local value = widget.props[key]
        if value ~= nil and shouldExportProp(key, value) then
            parts[#parts + 1] = key .. "=" .. serializeValue(value)
        end
    end
    if #parts == 0 then return "{}" end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- ============================================================================
-- Widget Path Helpers
-- ============================================================================

--- Get child index (0-based) within parent
local function getChildIndex(widget)
    if not widget.parent then return "root" end
    for i, c in ipairs(widget.parent.children) do
        if c == widget then return i - 1 end
    end
    return "?"
end

--- Build widget chain from root to target
local function buildWidgetPath(widget)
    local path = {}
    local w = widget
    while w do
        table.insert(path, 1, w)
        w = w.parent
    end
    return path
end

local function formatPathToken(widget)
    local className = widget._className or "Widget"
    local idx = getChildIndex(widget)
    if idx == "root" then return className end
    return className .. "[" .. tostring(idx) .. "]"
end

local function formatWidgetPath(widget)
    local path = buildWidgetPath(widget)
    local parts = {}
    for _, w in ipairs(path) do
        parts[#parts + 1] = formatPathToken(w)
    end
    return table.concat(parts, ">")
end

local function formatWidgetLabel(widget)
    local className = widget._className or "Widget"
    local label = className
    if widget.props.id then
        label = label .. " #" .. tostring(widget.props.id)
    end
    if widget.props.text then
        local text = tostring(widget.props.text)
        if #text > 24 then text = text:sub(1, 24) .. "..." end
        label = label .. "「" .. text .. "」"
    end
    return label
end

local function formatRectLine(widget)
    local l = widget and widget.GetAbsoluteLayout and widget:GetAbsoluteLayout()
    if not l or l.w ~= l.w then return "rect={x=?,y=?,w=?,h=?}" end
    return string.format("rect={x=%.0f,y=%.0f,w=%.0f,h=%.0f}", l.x, l.y, l.w, l.h)
end

local function formatSourceCompact(widget)
    local src = formatSource(widget)
    if src == "" then return "(unknown)" end
    return src:match("^%s*(.-)%s*$") or src
end

local function compactDiffsForWidget(widget)
    local lines = {}
    for _, entry in ipairs(ctx.propsSnapshots or {}) do
        if entry.widget == widget and isWidgetAlive(widget) then
            for _, key in ipairs(entry.keys or {}) do
                local oldVal = entry.snapshot[key]
                local newVal = widget.props[key]
                if not ctx.valuesEqual(oldVal, newVal) then
                    lines[#lines + 1] = key .. ": " .. serializeValue(oldVal) .. " -> " .. serializeValue(newVal)
                end
            end
        end
    end

    return lines
end

local function formatParentSummary(widget)
    local p = widget and widget.parent
    if not isWidgetAlive(p) then return nil end
    local children = {}
    for i, child in ipairs(p.children or {}) do
        local marker = child == widget and "*" or ""
        children[#children + 1] = tostring(i - 1) .. ":" .. marker .. (child._className or "Widget")
    end
    local source = formatSourceCompact(p)
    return _tr("t_10S1Sn7Na10xRPmmyi", formatWidgetLabel(p), source)
        .. _tr("t_ttWC7NXxtmDoQ0H5", serializeCompactProps(p))
        .. _tr("t_1F4s9tKWW1FGvviZF8", table.concat(children, ","))
end

local function formatWidgetSourcePath(widget)
    local path = buildWidgetPath(widget)
    local parts = {}
    for depth, w in ipairs(path) do
        local source = formatSourceCompact(w)
        if source == "(unknown)" then
            parts[#parts + 1] = formatPathToken(w)
        else
            parts[#parts + 1] = formatPathToken(w) .. source
        end
    end
    return table.concat(parts, ">")
end

-- ============================================================================
-- Single-Select Report
-- ============================================================================

--- Generate the full report text for clipboard
function M.generateReport(widget, description)
    if not widget then return "No widget selected." end

    local lines = {}
    lines[#lines + 1] = "=== UI Inspector Report ==="

    -- Clear summary: what was selected and what the user wants
    local className = widget._className or "Widget"
    local textProp = widget.props.text and ('"' .. tostring(widget.props.text) .. '"') or ""
    local idProp = widget.props.id and ("#" .. widget.props.id) or ""
    local selectedLabel = className
    if idProp ~= "" then selectedLabel = selectedLabel .. " " .. idProp end
    if textProp ~= "" then selectedLabel = selectedLabel .. " " .. textProp end
    local src = formatSource(widget)
    lines[#lines + 1] = "Selected: " .. selectedLabel .. src
    lines[#lines + 1] = 'User: "' .. (description or "") .. '"'
    lines[#lines + 1] = ""
    lines[#lines + 1] = "IMPORTANT: Only modify the selected widget (marked with *). Do NOT change its siblings."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "--- Widget Path (Root -> Selected) ---"
    lines[#lines + 1] = ""

    local path = buildWidgetPath(widget)
    for depth, w in ipairs(path) do
        local indent = string.rep("  ", depth - 1)
        local wClassName = w._className or "Widget"
        local marker = (w == widget) and " [SELECTED]" or ""
        local wSrc = formatSource(w)
        local idStr = w.props.id and (' id="' .. w.props.id .. '"') or ""

        lines[#lines + 1] = indent .. "[" .. (depth - 1) .. "] " .. wClassName .. idStr .. marker .. wSrc

        -- Props
        local propsStr = serializeProps(w.props)
        if propsStr ~= "{}" then
            lines[#lines + 1] = indent .. "  props: " .. propsStr
        end

        -- Computed layout
        local l = w:GetAbsoluteLayout()
        if l and l.w == l.w then  -- NaN guard
            lines[#lines + 1] = string.format(
                "%s  layout: { x=%.0f, y=%.0f, w=%.0f, h=%.0f }",
                indent, l.x, l.y, l.w, l.h
            )
        end

        -- Child index info
        local childIdx = getChildIndex(w)
        local parentChildCount = w.parent and #w.parent.children or 0
        local childIndexStr
        if childIdx == "root" then
            childIndexStr = "root"
        else
            childIndexStr = tostring(childIdx) .. "/" .. tostring(parentChildCount)
        end
        lines[#lines + 1] = indent .. "  childIndex: " .. childIndexStr
            .. ", children: " .. tostring(#w.children)
        lines[#lines + 1] = ""
    end

    -- Siblings section (for context only, DO NOT modify siblings)
    if widget.parent then
        lines[#lines + 1] = "--- Siblings (context only, do not modify) ---"
        for i, sibling in ipairs(widget.parent.children) do
            local marker = (sibling == widget) and " [SELECTED]" or ""
            local sibClassName = sibling._className or "Widget"
            local sibText = ""
            if sibling.props.text then
                sibText = ' "' .. tostring(sibling.props.text) .. '"'
            end
            local briefProps = serializeProps(sibling.props)
            lines[#lines + 1] = "[" .. (i - 1) .. "] " .. sibClassName .. marker .. sibText .. " " .. briefProps
        end
    end

    return table.concat(lines, "\n")
end

-- ============================================================================
-- Multi-Select Report
-- ============================================================================

--- Format a single widget node for the report (shared by single/multi)
local function formatNodeForReport(widget, indent, marker)
    local lines = {}
    local wClassName = widget._className or "Widget"
    local src = formatSource(widget)
    local idStr = widget.props.id and (' id="' .. widget.props.id .. '"') or ""

    lines[#lines + 1] = indent .. wClassName .. idStr .. marker .. src

    local propsStr = serializeProps(widget.props)
    if propsStr ~= "{}" then
        lines[#lines + 1] = indent .. "  props: " .. propsStr
    end

    local l = widget:GetAbsoluteLayout()
    if l and l.w == l.w then
        lines[#lines + 1] = string.format(
            "%s  layout: { x=%.0f, y=%.0f, w=%.0f, h=%.0f }",
            indent, l.x, l.y, l.w, l.h
        )
    end

    local childIdx = getChildIndex(widget)
    local parentChildCount = widget.parent and #widget.parent.children or 0
    local childIndexStr
    if childIdx == "root" then
        childIndexStr = "root"
    else
        childIndexStr = tostring(childIdx) .. "/" .. tostring(parentChildCount)
    end
    lines[#lines + 1] = indent .. "  childIndex: " .. childIndexStr
        .. ", children: " .. tostring(#widget.children)

    return lines
end

--- Generate report for multi-select
function M.generateMultiReport(widgets, description)
    if #widgets == 0 then return "No widgets selected." end

    -- Single-select: delegate to original format
    if #widgets == 1 then
        return M.generateReport(widgets[1], description)
    end

    local lines = {}
    lines[#lines + 1] = "=== UI Inspector Report (Multi-Select) ==="
    lines[#lines + 1] = ""

    -- Summary of all selected widgets
    lines[#lines + 1] = "Selected widgets (" .. #widgets .. "):"
    for i, w in ipairs(widgets) do
        local className = w._className or "Widget"
        local idProp = w.props.id and ("#" .. w.props.id) or ""
        local textProp = w.props.text and ('"' .. tostring(w.props.text) .. '"') or ""
        local label = className
        if idProp ~= "" then label = label .. " " .. idProp end
        if textProp ~= "" then label = label .. " " .. textProp end
        lines[#lines + 1] = "  [" .. i .. "] " .. label .. formatSource(w)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = 'User: "' .. (description or "") .. '"'
    lines[#lines + 1] = ""
    lines[#lines + 1] = "IMPORTANT: Only modify the selected widgets (marked with [SELECTED N]). Do NOT change other widgets."
    lines[#lines + 1] = ""

    -- Compute LCA
    local lca = Selection.findLCA(widgets)

    -- Shared path: Root -> LCA
    local sharedPath = buildWidgetPath(lca)
    lines[#lines + 1] = "--- Shared Path (Root -> LCA) ---"
    lines[#lines + 1] = ""
    for depth, w in ipairs(sharedPath) do
        local indent = string.rep("  ", depth - 1)
        local nodeLines = formatNodeForReport(w, indent, "")
        for _, line in ipairs(nodeLines) do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = ""
    end

    -- Branch segments: LCA -> each selected widget
    for i, w in ipairs(widgets) do
        local className = w._className or "Widget"
        local textProp = w.props.text and (' "' .. tostring(w.props.text) .. '"') or ""
        lines[#lines + 1] = "--- Branch " .. i .. ": LCA -> " .. className .. textProp .. " [SELECTED " .. i .. "] ---"
        lines[#lines + 1] = ""

        local branch = Selection.buildPathBetween(lca, w)
        -- Skip the LCA itself (already shown in shared path), unless LCA is the selected widget
        local startIdx = (branch[1] == lca and #branch > 1) and 2 or 1
        local baseDepth = #sharedPath  -- continue indentation from shared path

        for j = startIdx, #branch do
            local bw = branch[j]
            local depth = baseDepth + (j - startIdx)
            local indent = string.rep("  ", depth)
            local marker = (bw == w) and " [SELECTED " .. i .. "]" or ""
            local nodeLines = formatNodeForReport(bw, indent, marker)
            for _, line in ipairs(nodeLines) do
                lines[#lines + 1] = line
            end
            lines[#lines + 1] = ""
        end

        -- Siblings of the selected widget
        if w.parent then
            lines[#lines + 1] = "  Siblings of [SELECTED " .. i .. "] (context only, do not modify):"
            for si, sibling in ipairs(w.parent.children) do
                local sMarker = (sibling == w) and " [SELECTED " .. i .. "]" or ""
                local sibClassName = sibling._className or "Widget"
                local sibText = ""
                if sibling.props.text then
                    local t = tostring(sibling.props.text)
                    if #t > 20 then t = t:sub(1, 20) .. "..." end
                    sibText = ' "' .. t .. '"'
                end
                lines[#lines + 1] = "  [" .. (si - 1) .. "] " .. sibClassName .. sMarker .. sibText
            end
            lines[#lines + 1] = ""
        end
    end

    return table.concat(lines, "\n")
end

-- ============================================================================
-- Diff Report
-- ============================================================================

local function formatRect(rect)
    if not rect then return "{ x=?, y=?, w=?, h=? }" end
    return string.format("{ x=%.0f, y=%.0f, w=%.0f, h=%.0f }", rect.x, rect.y, rect.w, rect.h)
end

local function formatEditValue(widget, key, value)
    if value == nil then return "nil" end
    local fake = {
        props = { [key] = value },
        children = widget and widget.children or {},
        _className = widget and widget._className or "Widget",
    }
    local formatted = ctx.formatPropValue(fake, key)
    if formatted ~= "" then return formatted end
    return serializeValue(value)
end

--- Generate edit-tool report with target geometry and applied layout props.
function M.generateEditReport()
    local records = ctx.editRecords or {}
    if #records == 0 then return nil end

    local lines = {}
    for _, record in ipairs(records) do
        local w = record.widget
        if isWidgetAlive(w) and record.changed then
            local className = w._className or "Widget"
            local idStr = w.props.id and (" #" .. w.props.id) or ""
            local action = record.mode == "resize"
                and ("resize " .. tostring(record.handle or ""))
                or "move"
            lines[#lines + 1] = className .. idStr .. formatSource(w) .. ":"
            lines[#lines + 1] = "  action: " .. action
            lines[#lines + 1] = "  before rect: " .. formatRect(record.beforeRect)
            lines[#lines + 1] = "  target rect: " .. formatRect(record.afterRect)
            if #record.applied > 0 then
                lines[#lines + 1] = "  applied props:"
                for _, change in ipairs(record.applied) do
                    lines[#lines + 1] = "    " .. change.key .. ": "
                        .. formatEditValue(w, change.key, change.old)
                        .. " -> " .. formatEditValue(w, change.key, change.new)
                end
            else
                lines[#lines + 1] = "  applied props: none"
            end
            if record.note then
                lines[#lines + 1] = "  note: " .. record.note
            end
            lines[#lines + 1] = ""
        end
    end

    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

--- Generate diff report comparing snapshots with current values
function M.generateDiffReport()
    local diffs = {}
    for _, entry in ipairs(ctx.propsSnapshots) do
        local w = entry.widget
        if not isWidgetAlive(w) then goto continue end
        local widgetDiffs = {}
        for _, k in ipairs(entry.keys) do
            local oldVal = entry.snapshot[k]  -- may be nil
            local newVal = w.props[k]
            if not ctx.valuesEqual(oldVal, newVal) then
                local oldStr = ctx.formatPropValue({ props = entry.snapshot, children = w.children, _className = w._className }, k)
                local newStr = ctx.formatPropValue(w, k)
                widgetDiffs[#widgetDiffs + 1] = "  " .. k .. ": " .. oldStr .. " -> " .. newStr
            end
        end
        if #widgetDiffs > 0 then
            local className = w._className or "Widget"
            local idStr = w.props.id and (" #" .. w.props.id) or ""
            local src = formatSource(w)
            diffs[#diffs + 1] = className .. idStr .. src .. ":"
            for _, d in ipairs(widgetDiffs) do
                diffs[#diffs + 1] = d
            end
            diffs[#diffs + 1] = ""
        end
        ::continue::
    end
    if #diffs == 0 then return nil end
    return table.concat(diffs, "\n")
end

-- ============================================================================
-- Compact AI Context
-- ============================================================================

local function trimPrompt(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function addPromptLines(lines, prompt, firstPrefix, continuationPrefix)
    prompt = trimPrompt(prompt)
    if prompt == "" then return end

    firstPrefix = firstPrefix or ""
    continuationPrefix = continuationPrefix or firstPrefix
    local first = true
    for line in (prompt .. "\n"):gmatch("(.-)\n") do
        if first then
            lines[#lines + 1] = firstPrefix .. line
            first = false
        else
            lines[#lines + 1] = continuationPrefix .. line
        end
    end
end

local function getScopedGroupPrompt(entry, widgetIndex)
    if type(entry) ~= "table" then return "", {} end
    local prompt = trimPrompt(entry.prompt)
    if prompt == "" then return "", {} end

    local indices = {}
    local seen = {}
    for _, widget in ipairs(entry.widgets or {}) do
        local index = widgetIndex[widget]
        if index and not seen[index] then
            seen[index] = true
            indices[#indices + 1] = index
        end
    end
    table.sort(indices)
    if #indices == 0 then return "", {} end
    return prompt, indices
end

--- Generate a compact AI-friendly context for the current selection.
function M.generateCompactReport(widgets, options)
    widgets = widgets or {}
    options = options or {}

    if #widgets == 0 then
        return _tr("t_8Cox1tOW8iJY3wi2")
    end

    local prompt = ""
    if #widgets > 1 then
        prompt = trimPrompt(options.groupPrompt)
    else
        local widget = widgets[1]
        prompt = trimPrompt(options.widgetPrompts and options.widgetPrompts[widget])
    end

    local widgetPrompts = {}
    local hasWidgetPrompts = false
    for _, widget in ipairs(widgets) do
        local widgetPrompt = trimPrompt(options.widgetPrompts and options.widgetPrompts[widget])
        if widgetPrompt ~= "" then
            widgetPrompts[widget] = widgetPrompt
            hasWidgetPrompts = true
        end
    end

    local widgetIndex = {}
    for i, widget in ipairs(widgets) do
        widgetIndex[widget] = i
    end
    local scopedGroupPrompt, scopedGroupPromptIndices = getScopedGroupPrompt(options.groupPromptEntry, widgetIndex)
    if prompt ~= "" then
        scopedGroupPrompt = ""
        scopedGroupPromptIndices = {}
    end
    local hasPrompts = prompt ~= "" or scopedGroupPrompt ~= "" or hasWidgetPrompts

    local widgetDiffs = {}
    local hasDiffs = false
    for _, widget in ipairs(widgets) do
        if isWidgetAlive(widget) then
            local diffs = compactDiffsForWidget(widget)
            widgetDiffs[widget] = diffs
            if #diffs > 0 then
                hasDiffs = true
            end
        end
    end

    local lines = {}
    if hasDiffs then
        lines[#lines + 1] = _tr("t_iPO36CYCiq2eCnry")
    elseif hasPrompts then
        lines[#lines + 1] = _tr("t_9jqbBgoD9Xi8S0fv")
    else
        lines[#lines + 1] = _tr("t_HLgaeKfkGv21orR4")
    end
    lines[#lines + 1] = ""

    lines[#lines + 1] = (#widgets > 1) and _tr("t_5qf9YQkx5xxXnuMD") or _tr("t_u0IGjuGMto9qT7aK")
    if prompt ~= "" then
        addPromptLines(lines, prompt)
    else
        lines[#lines + 1] = _tr("t_1C8zIl6LB1BwvW34d5")
    end
    if scopedGroupPrompt ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _tr("t_dDxMUKQKciXSMdzy")
            .. table.concat(scopedGroupPromptIndices, "、") .. "）："
        addPromptLines(lines, scopedGroupPrompt)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = _tr("t_EIRcTTzyDrrlFDHM", tostring(#widgets))
        .. _tr("t_YFPh9HcDXjv5iggV")
    lines[#lines + 1] = ""
    lines[#lines + 1] = _tr("t_fkWMI5wzfF1lEarT")

    for i, widget in ipairs(widgets) do
        if isWidgetAlive(widget) then
            lines[#lines + 1] = tostring(i) .. ". " .. formatWidgetLabel(widget)
            lines[#lines + 1] = _tr("t_Phim0thVQD8ivLND", formatSourceCompact(widget))
            if #widgets > 1 and widgetPrompts[widget] then
                addPromptLines(lines, widgetPrompts[widget], _tr("t_PhFFkzJuQCjt8ESO"), "      ")
            end
            local diffs = widgetDiffs[widget] or {}
            if #diffs > 0 then
                lines[#lines + 1] = _tr("t_amoiHsv9aMEoRAYz", table.concat(diffs, "; "))
            end
            lines[#lines + 1] = _tr("t_MGoB1CBMM9VkX8CM", serializeCompactProps(widget))
            local parentSummary = formatParentSummary(widget)
            if parentSummary then
                lines[#lines + 1] = _tr("t_EipAngSCEWghyVbu", parentSummary)
            end
            lines[#lines + 1] = _tr("t_kPQt0h3CkWeclsD6", formatRectLine(widget):gsub("^rect=", ""))
            lines[#lines + 1] = _tr("t_nnrxl8tInNDMvJYI", formatWidgetSourcePath(widget))
            lines[#lines + 1] = ""
        end
    end

    lines[#lines + 1] = _tr("t_Rh7uPyToRoLdw5wk")






    return table.concat(lines, "\n")
end

return M
end
