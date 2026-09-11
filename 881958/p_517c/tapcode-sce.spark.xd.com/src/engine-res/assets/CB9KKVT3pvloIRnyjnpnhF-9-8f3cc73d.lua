-- ============================================================================
-- UIInspector - Selection Module
-- Widget selection management, multi-select, LCA computation
-- ============================================================================

return function(ctx)

local M = {}

--- Check if a widget is in the selected list
function M.isWidgetSelected(widget)
    for _, w in ipairs(ctx.selectedWidgets) do
        if w == widget then return true end
    end
    return false
end

--- Toggle a widget in/out of the selection list
--- Returns true if widget was added, false if removed
function M.toggleWidgetSelection(widget)
    for i, w in ipairs(ctx.selectedWidgets) do
        if w == widget then
            table.remove(ctx.selectedWidgets, i)
            if ctx.syncInspectedWidgets then ctx.syncInspectedWidgets() end
            return false
        end
    end
    ctx.selectedWidgets[#ctx.selectedWidgets + 1] = widget
    if ctx.syncInspectedWidgets then ctx.syncInspectedWidgets() end
    return true
end

--- Get 1-based selection index of a widget (0 if not selected)
function M.getSelectionIndex(widget)
    for i, w in ipairs(ctx.selectedWidgets) do
        if w == widget then return i end
    end
    return 0
end

-- ============================================================================
-- LCA (Lowest Common Ancestor) Computation
-- ============================================================================

--- Get depth of widget in tree (root = 0)
local function getWidgetDepth(widget)
    local d = 0
    local w = widget.parent
    while w do
        d = d + 1
        w = w.parent
    end
    return d
end

--- Find LCA of two widgets
local function findLCA2(a, b)
    local da, db = getWidgetDepth(a), getWidgetDepth(b)
    while da > db do a = a.parent; da = da - 1 end
    while db > da do b = b.parent; db = db - 1 end
    while a ~= b do
        a = a.parent
        b = b.parent
    end
    return a
end

--- Find LCA of multiple widgets
function M.findLCA(widgets)
    if #widgets == 0 then return nil end
    if #widgets == 1 then return widgets[1].parent or widgets[1] end
    local lca = widgets[1]
    for i = 2, #widgets do
        lca = findLCA2(lca, widgets[i])
        if not lca then break end
    end
    return lca
end

--- Build path from ancestor to descendant (inclusive on both ends)
function M.buildPathBetween(ancestor, descendant)
    local path = {}
    local w = descendant
    while w and w ~= ancestor do
        table.insert(path, 1, w)
        w = w.parent
    end
    if w == ancestor then
        table.insert(path, 1, ancestor)
    end
    return path
end

return M
end
