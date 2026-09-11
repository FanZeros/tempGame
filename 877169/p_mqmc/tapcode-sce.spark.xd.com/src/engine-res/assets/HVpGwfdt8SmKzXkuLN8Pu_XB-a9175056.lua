-- ============================================================================
-- Tree Widget
-- Hierarchical tree view for displaying nested data structures
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class TreeNode
---@field key? any Unique node key (defaults to id or label)
---@field id? any Node ID
---@field label? string Node display label
---@field title? string Alternative to label
---@field icon? string Node icon
---@field secondary? string Secondary text
---@field children? TreeNode[] Child nodes array
---@field expanded? boolean Initial expanded state
---@field disabled? boolean Disabled state
---@field data? any Custom user data

---@class TreeProps : WidgetProps
---@field nodes? TreeNode[] Tree nodes array
---@field data? TreeNode[] Alias for nodes
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field selectable? boolean Enable node selection (default: true)
---@field multiSelect? boolean Allow multiple selection (default: false)
---@field checkable? boolean Show checkboxes (default: false)
---@field showLines? boolean Show tree connection lines (default: false)
---@field showIcons? boolean Show node icons (default: true)
---@field expandOnClick? boolean Expand/collapse on click (default: true)
---@field defaultExpandAll? boolean Expand all nodes initially (default: false)
---@field defaultExpandedKeys? any[] Initially expanded node keys
---@field expandIcon? string Expand icon (default: ">")
---@field collapseIcon? string Collapse icon (default: "v")
---@field leafIcon? string Leaf node icon
---@field folderIcon? string Folder icon (collapsed)
---@field folderOpenIcon? string Folder icon (expanded)
---@field nodePaddingY? number Internal top/bottom padding per node row (default 0; row height = max(icon,text) + nodePaddingY*2)
---@field edgePaddingY? number Top/bottom margin between the node list and the outer frame edges
---@field fontSize? number Custom font size
---@field iconSize? number Custom icon size
---@field indent? number Indentation per level
---@field hoverBgColor? RGBAColor|string Node hover background color
---@field hoverRadius? number Node hover/selected highlight border radius
---@field selectedBgColor? RGBAColor|string Node selected background color
---@field iconColor? RGBAColor|string Node icon color for folder/leaf icons (default: textSecondary)
---@field selectedTextColor? RGBAColor|string Selected node text color (default: primary)
---@field hoverInset? number Horizontal inset for hover/selected highlight (default: 0)
---@field nodeGap? number Vertical gap between nodes (default: 0)
---@field onSelect? fun(tree: Tree, selectedKeys: any[], node: TreeNode) Selection callback
---@field onCheck? fun(tree: Tree, checkedKeys: any[]) Check callback
---@field onExpand? fun(tree: Tree, key: any, node: TreeNode) Expand callback
---@field onCollapse? fun(tree: Tree, key: any, node: TreeNode) Collapse callback
---@field onNodeClick? fun(tree: Tree, node: TreeNode, key: any) Node click callback
---@field onNodeDoubleClick? fun(tree: Tree, node: TreeNode, key: any) Node double-click callback

---@class Tree : Widget
---@overload fun(props?: TreeProps): Tree
---@field props TreeProps
---@field new fun(self, props?: TreeProps): Tree
local Tree = Widget:Extend("Tree")

-- ============================================================================
-- Size presets
-- ============================================================================

-- Row height = max(icon, text) + nodePaddingY*2. nodePaddingY defaults to 0 (content hugs the row edges).
local SIZE_PRESETS = {
    sm = { fontSize = 12, iconSize = 14, indent = 16 },
    md = { fontSize = 14, iconSize = 18, indent = 20 },
    lg = { fontSize = 16, iconSize = 22, indent = 24 },
}

local function resolveVerticalPadding(props)
    local shorthandTop, shorthandBottom = 0, 0
    local padding = props.padding

    if type(padding) == "number" or type(padding) == "string" then
        shorthandTop, shorthandBottom = padding, padding
    elseif type(padding) == "table" then
        local count = #padding
        if count == 1 then
            shorthandTop, shorthandBottom = padding[1], padding[1]
        elseif count == 2 then
            shorthandTop, shorthandBottom = padding[1], padding[1]
        elseif count >= 3 then
            shorthandTop, shorthandBottom = padding[1], padding[3]
        end

        if padding.vertical ~= nil then
            shorthandTop, shorthandBottom = padding.vertical, padding.vertical
        end
        if padding.top ~= nil then shorthandTop = padding.top end
        if padding.bottom ~= nil then shorthandBottom = padding.bottom end
    end

    local paddingTop = props.paddingTop
    if paddingTop == nil then paddingTop = props.paddingVertical end
    if paddingTop == nil then paddingTop = shorthandTop end

    local paddingBottom = props.paddingBottom
    if paddingBottom == nil then paddingBottom = props.paddingVertical end
    if paddingBottom == nil then paddingBottom = shorthandBottom end

    local numericTop = tonumber(paddingTop)
    if numericTop == nil and paddingTop ~= nil then
        print("[Tree] ERROR: failed to convert top padding to number: " .. tostring(paddingTop) .. "; using 0")
    end

    local numericBottom = tonumber(paddingBottom)
    if numericBottom == nil and paddingBottom ~= nil then
        print("[Tree] ERROR: failed to convert bottom padding to number: " .. tostring(paddingBottom) .. "; using 0")
    end

    return numericTop or 0, numericBottom or 0
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props TreeProps?
function Tree:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Tree")
    Style.ApplyDefaults(props, themeStyle)

    -- Tree props
    self.nodes_ = props.nodes or props.data or {}
    self.size_ = props.size or "md"
    self.selectable_ = props.selectable ~= false  -- default true
    self.multiSelect_ = props.multiSelect or false
    self.checkable_ = props.checkable or false
    self.showLines_ = props.showLines or false
    self.showIcons_ = props.showIcons ~= false  -- default true
    self.expandOnClick_ = props.expandOnClick ~= false  -- default true
    self.defaultExpandAll_ = props.defaultExpandAll or false
    self.defaultExpandedKeys_ = props.defaultExpandedKeys or {}

    -- Icons
    self.expandIcon_ = props.expandIcon or ">"
    self.collapseIcon_ = props.collapseIcon or "v"
    -- Default node icons (emoji, rendered via the engine color-emoji font fallback):
    -- folder collapsed / folder open / leaf(file). Per-node item.icon still overrides.
    self.leafIcon_ = props.leafIcon or "📄"
    self.folderIcon_ = props.folderIcon or "📁"
    self.folderOpenIcon_ = props.folderOpenIcon or "📂"

    -- Callbacks
    self.onSelect_ = props.onSelect
    self.onCheck_ = props.onCheck
    self.onExpand_ = props.onExpand
    self.onCollapse_ = props.onCollapse
    self.onNodeClick_ = props.onNodeClick
    self.onNodeDoubleClick_ = props.onNodeDoubleClick

    -- State
    self.expandedKeys_ = {}
    self.selectedKeys_ = {}
    self.checkedKeys_ = {}
    self.hoverKey_ = nil
    self.hoverExpandKey_ = nil  -- Track hover on expand icon

    -- Initialize expanded state
    if self.defaultExpandAll_ then
        self:ExpandAll()
    else
        -- Check for defaultExpandedKeys
        for _, key in ipairs(self.defaultExpandedKeys_) do
            self.expandedKeys_[key] = true
        end
        -- Also check for nodes with expanded = true
        self:InitExpandedFromNodes(self.nodes_)
    end

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.fontSize_ = props.fontSize and Theme.FontSize(props.fontSize) or Theme.FontSize(sizePreset.fontSize)
    self.iconSize_ = props.iconSize or sizePreset.iconSize
    self.indent_ = props.indent or sizePreset.indent
    -- Internal top/bottom padding per node row (default 0 = content hugs the row edges).
    self.nodePaddingY_ = props.nodePaddingY or 0
    self.nodeHeight_ = math.max(self.iconSize_, self.fontSize_) + self.nodePaddingY_ * 2
    -- Top/bottom margin between the whole node list and the outer frame edges.
    self.edgePaddingY_ = props.edgePaddingY or 0
    -- Opacity of the default (primary-derived) selected-node background.
    self.selectedBgOpacity_ = props.selectedBgOpacity or 0.15

    props.flexDirection = "column"

    -- Auto-calculate height if not specified.
    if not props.height then
        props.height = self:CalculateRequiredHeight()
    end

    Widget.Init(self, props)
end

--- Initialize expanded state from nodes with expanded = true
function Tree:InitExpandedFromNodes(nodes)
    for _, node in ipairs(nodes) do
        local key = node.key or node.id or node.label
        if node.expanded then
            self.expandedKeys_[key] = true
        end
        if node.children and #node.children > 0 then
            self:InitExpandedFromNodes(node.children)
        end
    end
end

--- Calculate total height needed to display all visible nodes
function Tree:CalculateTotalHeight()
    local function countVisibleNodes(nodes, expandedKeys)
        local count = 0
        for _, node in ipairs(nodes) do
            count = count + 1
            local key = node.key or node.id or node.label
            local hasChildren = node.children and #node.children > 0
            local isExpanded = expandedKeys[key] or node.expanded
            if hasChildren and isExpanded then
                count = count + countVisibleNodes(node.children, expandedKeys)
            end
        end
        return count
    end

    local visibleCount = countVisibleNodes(self.nodes_, self.expandedKeys_)
    local nodeGap = self.props.nodeGap or 0
    return visibleCount * self.nodeHeight_ + math.max(0, visibleCount - 1) * nodeGap
end

--- Calculate the outer height required for all visible nodes and vertical insets.
function Tree:CalculateRequiredHeight()
    local paddingTop, paddingBottom = resolveVerticalPadding(self.props)
    return self:CalculateTotalHeight() + paddingTop + paddingBottom + self.edgePaddingY_ * 2
end

--- Update height after expand/collapse
function Tree:UpdateHeight()
    local newHeight = self:CalculateRequiredHeight()
    self:SetHeight(newHeight)
end

-- ============================================================================
-- Node Management
-- ============================================================================

function Tree:GetNodes()
    return self.nodes_
end

function Tree:SetNodes(nodes)
    self.nodes_ = nodes or {}
end

function Tree:GetNodeByKey(key, nodes)
    nodes = nodes or self.nodes_

    for _, node in ipairs(nodes) do
        local nodeKey = node.key or node.id or node.label
        if nodeKey == key then
            return node
        end
        if node.children then
            local found = self:GetNodeByKey(key, node.children)
            if found then return found end
        end
    end

    return nil
end

-- ============================================================================
-- Expand/Collapse
-- ============================================================================

function Tree:IsExpanded(key)
    return self.expandedKeys_[key] == true
end

function Tree:Expand(key)
    if not self.expandedKeys_[key] then
        self.expandedKeys_[key] = true
        self:UpdateHeight()
        local node = self:GetNodeByKey(key)
        self:DispatchEvent("expand", self, key, node)
        if self.onExpand_ then
            self.onExpand_(self, key, node)
        end
    end
end

function Tree:Collapse(key)
    if self.expandedKeys_[key] then
        self.expandedKeys_[key] = nil
        self:UpdateHeight()
        local node = self:GetNodeByKey(key)
        self:DispatchEvent("collapse", self, key, node)
        if self.onCollapse_ then
            self.onCollapse_(self, key, node)
        end
    end
end

function Tree:Toggle(key)
    if self:IsExpanded(key) then
        self:Collapse(key)
    else
        self:Expand(key)
    end
end

function Tree:ExpandAll(nodes, isRecursive)
    nodes = nodes or self.nodes_

    for _, node in ipairs(nodes) do
        local key = node.key or node.id or node.label
        if node.children and #node.children > 0 then
            self.expandedKeys_[key] = true
            self:ExpandAll(node.children, true)
        end
    end

    -- Only update height at the top level call
    if not isRecursive then
        self:UpdateHeight()
    end
end

function Tree:CollapseAll()
    self.expandedKeys_ = {}
    self:UpdateHeight()
end

-- ============================================================================
-- Selection
-- ============================================================================

function Tree:IsSelected(key)
    return self.selectedKeys_[key] == true
end

function Tree:Select(key)
    if not self.selectable_ then return end

    if not self.multiSelect_ then
        self.selectedKeys_ = {}
    end

    self.selectedKeys_[key] = true

    local node = self:GetNodeByKey(key)
    local selectedList = {}
    for k, _ in pairs(self.selectedKeys_) do
        table.insert(selectedList, k)
    end
    self:DispatchEvent("select", self, selectedList, node)
    if self.onSelect_ then
        self.onSelect_(self, selectedList, node)
    end
end

function Tree:Deselect(key)
    self.selectedKeys_[key] = nil
end

function Tree:ToggleSelect(key)
    if self:IsSelected(key) then
        self:Deselect(key)
    else
        self:Select(key)
    end
end

function Tree:ClearSelection()
    self.selectedKeys_ = {}
end

function Tree:GetSelectedKeys()
    local keys = {}
    for k, _ in pairs(self.selectedKeys_) do
        table.insert(keys, k)
    end
    return keys
end

-- ============================================================================
-- Checkbox
-- ============================================================================

function Tree:IsChecked(key)
    return self.checkedKeys_[key] == true
end

function Tree:Check(key)
    self.checkedKeys_[key] = true
    self:UpdateParentCheckState(key)

    local checkedList = {}
    for k, _ in pairs(self.checkedKeys_) do
        table.insert(checkedList, k)
    end
    self:DispatchEvent("check", self, checkedList)
    if self.onCheck_ then
        self.onCheck_(self, checkedList)
    end
end

function Tree:Uncheck(key)
    self.checkedKeys_[key] = nil
    self:UpdateParentCheckState(key)
end

function Tree:ToggleCheck(key)
    if self:IsChecked(key) then
        self:Uncheck(key)
    else
        self:Check(key)
    end
end

function Tree:UpdateParentCheckState(key)
    -- This would require parent references - simplified for now
end

function Tree:GetCheckedKeys()
    local keys = {}
    for k, _ in pairs(self.checkedKeys_) do
        table.insert(keys, k)
    end
    return keys
end

-- ============================================================================
-- Drawing Helpers
-- ============================================================================

function Tree:DrawExpandIcon(nvg, x, y, isExpanded, hasChildren, isHovered, iconSize, nodeHeight)
    if not hasChildren then return end

    local size = iconSize * 0.35
    local cx = x + iconSize / 2
    local cy = y + nodeHeight / 2
    local bgRadius = iconSize * 0.45

    -- Draw hover background
    if isHovered then
        local hoverRadius = type(self.props.borderRadius) == "number" and self.props.borderRadius or bgRadius
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - bgRadius, cy - bgRadius, bgRadius * 2, bgRadius * 2, hoverRadius)
        nvgFillColor(nvg, Theme.NvgColor("surfaceHover"))
        nvgFill(nvg)
    end

    -- Draw filled triangle arrow
    nvgBeginPath(nvg)
    if isExpanded then
        -- Down triangle (pointing down)
        nvgMoveTo(nvg, cx - size, cy - size * 0.4)
        nvgLineTo(nvg, cx + size, cy - size * 0.4)
        nvgLineTo(nvg, cx, cy + size * 0.6)
        nvgClosePath(nvg)
    else
        -- Right triangle (pointing right)
        nvgMoveTo(nvg, cx - size * 0.4, cy - size)
        nvgLineTo(nvg, cx + size * 0.6, cy)
        nvgLineTo(nvg, cx - size * 0.4, cy + size)
        nvgClosePath(nvg)
    end
    local arrowColor = self.props.arrowColor or Theme.Color("textSecondary")
    nvgFillColor(nvg, nvgRGBA(arrowColor[1], arrowColor[2], arrowColor[3], arrowColor[4] or 255))
    nvgFill(nvg)
end

function Tree:DrawCheckbox(nvg, x, y, isChecked, isIndeterminate, iconSize, nodeHeight)
    local size = iconSize * 0.8
    local cx = x + size / 2
    local cy = y + nodeHeight / 2
    local boxSize = size * 0.8
    local half = boxSize / 2

    -- Box
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, cx - half, cy - half, boxSize, boxSize,
        type(self.props.borderRadius) == "number" and self.props.borderRadius or 3)

    if isChecked or isIndeterminate then
        nvgFillColor(nvg, Theme.NvgColor("primary"))
        nvgFill(nvg)

        -- Checkmark or dash
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgStrokeWidth(nvg, 2)
        nvgBeginPath(nvg)

        if isIndeterminate then
            nvgMoveTo(nvg, cx - half * 0.5, cy)
            nvgLineTo(nvg, cx + half * 0.5, cy)
        else
            nvgMoveTo(nvg, cx - half * 0.4, cy)
            nvgLineTo(nvg, cx - half * 0.1, cy + half * 0.4)
            nvgLineTo(nvg, cx + half * 0.5, cy - half * 0.3)
        end
        nvgStroke(nvg)
    else
        nvgStrokeColor(nvg, Theme.NvgColor("border"))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end

    return size + 4
end

function Tree:DrawNodeIcon(nvg, x, y, node, isExpanded, iconSize, nodeHeight)
    local icon = node.icon

    if not icon then
        local hasChildren = node.children and #node.children > 0
        if hasChildren then
            icon = isExpanded and (self.folderOpenIcon_ or "O") or (self.folderIcon_ or "F")
        else
            icon = self.leafIcon_ or "f"
        end
    end

    nvgFontSize(nvg, iconSize * 0.8)
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    local iconFillColor = self.props.iconColor or Theme.Color("textSecondary")
    nvgFillColor(nvg, nvgRGBA(iconFillColor[1], iconFillColor[2], iconFillColor[3], iconFillColor[4] or 255))
    nvgText(nvg, x + iconSize / 2, y + nodeHeight / 2, icon)

    return iconSize + 4
end

function Tree:DrawConnectionLines(nvg, x, y, depth, isLast, parentLines, indent, nodeHeight)
    if not self.showLines_ then return end

    nvgStrokeColor(nvg, Theme.NvgColor("border"))
    nvgStrokeWidth(nvg, 1)

    local lineX = x - indent / 2
    local midY = y + nodeHeight / 2

    -- Vertical line from parent
    if depth > 0 then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, lineX, y)
        nvgLineTo(nvg, lineX, midY)
        nvgLineTo(nvg, x, midY)
        nvgStroke(nvg)

        -- Continue vertical line if not last
        if not isLast then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, lineX, midY)
            nvgLineTo(nvg, lineX, y + nodeHeight)
            nvgStroke(nvg)
        end
    end

    -- Draw parent continuation lines
    for i, hasLine in ipairs(parentLines or {}) do
        if hasLine then
            local parentX = x - (depth - i + 1) * indent - indent / 2
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, parentX, y)
            nvgLineTo(nvg, parentX, y + nodeHeight)
            nvgStroke(nvg)
        end
    end
end

-- ============================================================================
-- Render Node
-- ============================================================================

function Tree:RenderNode(nvg, node, x, y, depth, isLast, parentLines, params)
    local key = node.key or node.id or node.label
    local hasChildren = node.children and #node.children > 0
    local isExpanded = self:IsExpanded(key)
    local isSelected = self:IsSelected(key)
    local isChecked = self:IsChecked(key)
    local isHovered = self.hoverKey_ == key
    local isDisabled = node.disabled

    -- Use parameters
    local nodeHeight = params.nodeHeight
    local iconSize = params.iconSize
    local indent = params.indent
    local fontSize = params.fontSize

    local nodeX = x + depth * indent
    local nodeWidth = params.contentWidth - (nodeX - x)

    -- Store node position for hit testing
    self.nodePositions_[key] = {
        x1 = nodeX,
        x2 = nodeX + nodeWidth,
        y1 = y,
        y2 = y + nodeHeight,
        node = node,
        key = key,
        depth = depth,
        iconSize = iconSize,
    }

    -- Draw connection lines
    self:DrawConnectionLines(nvg, nodeX, y, depth, isLast, parentLines, indent, nodeHeight)

    -- Selection/hover background
    local highlightRadius = self.props.hoverRadius ~= nil and self.props.hoverRadius
        or (type(self.props.borderRadius) == "number" and self.props.borderRadius or 4)
    local hoverInset = self.props.hoverInset or 0
    -- Auto-round corners for nodes near container edges
    local containerR = params.containerR or 0
    local containerRLimit = params.containerRLimit or 0
    local nearTop = y - params.containerY < containerRLimit
    local nearBottom = params.containerY + params.containerH - (y + nodeHeight) < containerRLimit
    local itemRadius
    if type(containerR) == "table" then
        itemRadius = {
            nearTop and (containerR[1] or 0) or highlightRadius,
            nearTop and (containerR[2] or 0) or highlightRadius,
            nearBottom and (containerR[3] or 0) or highlightRadius,
            nearBottom and (containerR[4] or 0) or highlightRadius,
        }
    else
        local topR = nearTop and containerR or highlightRadius
        local botR = nearBottom and containerR or highlightRadius
        itemRadius = { topR, topR, botR, botR }
    end
    if isSelected or isHovered then
        self:CreateShapePath(nvg, self:GetShapeGeometry(
            { x = nodeX + hoverInset, y = y, w = nodeWidth - hoverInset * 2, h = nodeHeight },
            nil,
            itemRadius))
        if isSelected then
            local selColor = self.props.selectedBgColor
            if selColor then
                nvgFillColor(nvg, nvgRGBA(selColor[1], selColor[2], selColor[3], selColor[4] or 255))
            else
                local primaryColor = Theme.Color("primary")
                nvgFillColor(nvg, nvgTransRGBAf(nvgRGBA(primaryColor[1], primaryColor[2], primaryColor[3], primaryColor[4] or 255), self.selectedBgOpacity_))
            end
        else
            local hoverColor = self.props.hoverBgColor or Theme.Color("surfaceHover")
            nvgFillColor(nvg, nvgRGBA(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4] or 255))
        end
        nvgFill(nvg)
    end

    local contentX = nodeX

    -- Expand icon (with hover state)
    local isExpandHovered = self.hoverExpandKey_ == key
    self:DrawExpandIcon(nvg, contentX, y, isExpanded, hasChildren, isExpandHovered, iconSize, nodeHeight)
    contentX = contentX + iconSize + 2

    -- Checkbox
    if self.checkable_ then
        local checkWidth = self:DrawCheckbox(nvg, contentX, y, isChecked, false, iconSize, nodeHeight)
        contentX = contentX + checkWidth
    end

    -- Node icon
    if self.showIcons_ then
        local iconWidth = self:DrawNodeIcon(nvg, contentX, y, node, isExpanded, iconSize, nodeHeight)
        contentX = contentX + iconWidth
    end

    -- Label
    local textColor
    if isDisabled then
        textColor = Theme.NvgColor("textDisabled")
    elseif isSelected then
        local selTextColor = self.props.selectedTextColor
        textColor = selTextColor
            and nvgRGBA(selTextColor[1], selTextColor[2], selTextColor[3], selTextColor[4] or 255)
            or Theme.NvgColor("primary")
    else
        local normalTextColor = self.props.textColor
        textColor = normalTextColor
            and nvgRGBA(normalTextColor[1], normalTextColor[2], normalTextColor[3], normalTextColor[4] or 255)
            or Theme.NvgColor("text")
    end

    nvgFontSize(nvg, fontSize)
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, textColor)
    nvgText(nvg, contentX, y + nodeHeight / 2, node.label or node.title or "")

    -- Secondary text
    if node.secondary then
        nvgFontSize(nvg, fontSize * 0.85)
        nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
        local labelBounds = {}
        nvgTextBounds(nvg, contentX, y, node.label or "", labelBounds)
        local labelWidth = labelBounds[3] - labelBounds[1]
        nvgText(nvg, contentX + labelWidth + 8, y + nodeHeight / 2, node.secondary)
    end

    local nodeGap = self.props.nodeGap or 0
    local nextY = y + nodeHeight + nodeGap

    -- Render children if expanded
    if hasChildren and isExpanded then
        local childCount = #node.children
        local newParentLines = {}
        for _, line in ipairs(parentLines or {}) do
            table.insert(newParentLines, line)
        end
        table.insert(newParentLines, not isLast)

        for i, child in ipairs(node.children) do
            local childIsLast = (i == childCount)
            nextY = self:RenderNode(nvg, child, x, nextY, depth + 1, childIsLast, newParentLines, params)
        end
    end

    return nextY
end

-- ============================================================================
-- Render
-- ============================================================================

function Tree:Render(nvg)
    local l = self:GetAbsoluteLayout()
    -- Yoga has resolved numeric and percentage padding by render time. Reading the
    -- computed values avoids arithmetic on raw strings such as "10%".
    local padTop = YGNodeLayoutGetPadding(self.node, YGEdgeTop) + self.edgePaddingY_
    local padBot = YGNodeLayoutGetPadding(self.node, YGEdgeBottom) + self.edgePaddingY_
    local padLeft = YGNodeLayoutGetPadding(self.node, YGEdgeLeft)
    local padRight = YGNodeLayoutGetPadding(self.node, YGEdgeRight)
    local x = l.x + padLeft
    local y = l.y + padTop
    local w = l.w - padLeft - padRight
    local h = l.h - padTop - padBot

    -- Parameters (no scale needed - nvgScale handles it)
    local containerR = self.props.borderRadius or 0
    local containerRLimit = containerR
    if type(containerR) == "table" then
        containerRLimit = math.max(containerR[1] or 0, containerR[2] or 0, containerR[3] or 0, containerR[4] or 0)
    end
    local params = {
        nodeHeight = self.nodeHeight_,
        iconSize = self.iconSize_,
        indent = self.indent_,
        -- Use the Init-computed size so props.fontSize (theme override) applies to drawn labels.
        fontSize = self.fontSize_,
        contentWidth = w,
        containerY = l.y,
        containerH = l.h,
        containerR = containerR,
        containerRLimit = containerRLimit,
    }

    -- Render background (if any)
    Widget.Render(self, nvg)

    -- Clip content to widget bounds
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)

    -- Reset node positions
    self.nodePositions_ = {}

    -- Render nodes
    local currentY = y
    local nodeCount = #self.nodes_

    for i, node in ipairs(self.nodes_) do
        local isLast = (i == nodeCount)
        currentY = self:RenderNode(nvg, node, x, currentY, 0, isLast, {}, params)
    end

    nvgRestore(nvg)
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Tree:GetNodeAtPosition(screenX, screenY)
    if not self.nodePositions_ then return nil end

    -- Convert screen coords to render coords
    local l = self:GetAbsoluteLayout()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local px = screenX + (l.x - hitTest.x)
    local py = screenY + (l.y - hitTest.y)

    -- Reject if outside widget bounds
    if py < l.y or py > l.y + l.h then return nil end

    for key, pos in pairs(self.nodePositions_) do
        if px >= pos.x1 and px <= pos.x2 and py >= pos.y1 and py <= pos.y2 then
            return pos
        end
    end

    return nil
end

function Tree:OnPointerMove(event)
    if not event then return end

    local nodePos = self:GetNodeAtPosition(event.x, event.y)

    if nodePos then
        self.hoverKey_ = nodePos.key

        -- Check if hovering over expand icon area
        local l = self:GetAbsoluteLayout()
        local hitTest = self:GetAbsoluteLayoutForHitTest()
        local px = event.x + (l.x - hitTest.x)

        local iconSize = nodePos.iconSize or self.iconSize_
        local expandIconX = nodePos.x1
        local expandIconEndX = expandIconX + iconSize
        local hasChildren = nodePos.node.children and #nodePos.node.children > 0

        if hasChildren and px >= expandIconX and px <= expandIconEndX then
            self.hoverExpandKey_ = nodePos.key
        else
            self.hoverExpandKey_ = nil
        end
    else
        self.hoverKey_ = nil
        self.hoverExpandKey_ = nil
    end
end

function Tree:OnMouseLeave(event)
    self.hoverKey_ = nil
    self.hoverExpandKey_ = nil
end

function Tree:HitTest(x, y)
    -- Convert screen coords to render coords (nodePositions_ uses render coords)
    local l = self:GetAbsoluteLayout()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local px = x + (l.x - hitTest.x)
    local py = y + (l.y - hitTest.y)

    -- Check if within horizontal bounds
    if px < l.x or px > l.x + l.w then
        return false
    end

    -- Check within widget bounds first
    if py < l.y or py > l.y + l.h then
        return false
    end

    -- Check if within any rendered node
    if self.nodePositions_ then
        for _, pos in pairs(self.nodePositions_) do
            if px >= pos.x1 and px <= pos.x2 and py >= pos.y1 and py <= pos.y2 then
                return true
            end
        end
    end

    return false
end

function Tree:OnClick(event)
    if not event then return end

    local nodePos = self:GetNodeAtPosition(event.x, event.y)

    if nodePos and not nodePos.node.disabled then
        local key = nodePos.key
        local node = nodePos.node
        local hasChildren = node.children and #node.children > 0

        -- Convert screen coords to render coords for icon area check
        local l = self:GetAbsoluteLayout()
        local hitTest = self:GetAbsoluteLayoutForHitTest()
        local px = event.x + (l.x - hitTest.x)

        -- Use stored iconSize
        local iconSize = nodePos.iconSize or self.iconSize_
        local spacing = 2

        -- Check if clicked on expand icon area
        local expandIconX = nodePos.x1
        local expandIconEndX = expandIconX + iconSize

        if px >= expandIconX and px <= expandIconEndX and hasChildren then
            -- Toggle expand
            self:Toggle(key)
        elseif self.checkable_ then
            -- Check if clicked on checkbox area
            local checkboxX = expandIconX + iconSize + spacing
            local checkboxEndX = checkboxX + iconSize

            if px >= checkboxX and px <= checkboxEndX then
                self:ToggleCheck(key)
            else
                -- Select node
                if self.selectable_ then
                    if self.multiSelect_ then
                        self:ToggleSelect(key)
                    else
                        self:Select(key)
                    end
                end
            end
        else
            -- Select node
            if self.selectable_ then
                if self.multiSelect_ then
                    self:ToggleSelect(key)
                else
                    self:Select(key)
                end
            end
        end

        -- Call node click callback
        if self.onNodeClick_ then
            self.onNodeClick_(self, node, key)
        end
    end
end

function Tree:OnDoubleTap(event)
    if not event then return end

    local nodePos = self:GetNodeAtPosition(event.x, event.y)

    if nodePos and not nodePos.node.disabled then
        local key = nodePos.key
        local node = nodePos.node
        local hasChildren = node.children and #node.children > 0

        -- Double-click toggles expand/collapse for directories
        if hasChildren then
            self:Toggle(key)
        end

        -- Call node double-click callback
        if self.onNodeDoubleClick_ then
            self.onNodeDoubleClick_(self, node, key)
        end
    end
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a tree from flat data with parent references
---@param flatData table[] Array of { id, parentId, label, ... }
---@param props table|nil Additional props
---@return Tree
function Tree.FromFlatData(flatData, props)
    props = props or {}

    -- Build tree structure
    local nodeMap = {}
    local roots = {}

    -- First pass: create node map
    for _, item in ipairs(flatData) do
        nodeMap[item.id] = {
            key = item.id,
            label = item.label or item.name or item.title,
            icon = item.icon,
            children = {},
            data = item,
        }
    end

    -- Second pass: build hierarchy
    for _, item in ipairs(flatData) do
        local node = nodeMap[item.id]
        if item.parentId and nodeMap[item.parentId] then
            table.insert(nodeMap[item.parentId].children, node)
        else
            table.insert(roots, node)
        end
    end

    props.nodes = roots
    return Tree(props)
end

--- Create a file tree
---@param files table[] Array of file/folder items
---@param props table|nil Additional props
---@return Tree
function Tree.FileTree(files, props)
    props = props or {}
    props.nodes = files
    props.showIcons = true
    props.folderIcon = "D"
    props.folderOpenIcon = "O"
    props.leafIcon = "f"
    return Tree(props)
end

--- Create a checkable tree
---@param nodes table[] Tree nodes
---@param props table|nil Additional props
---@return Tree
function Tree.Checkable(nodes, props)
    props = props or {}
    props.nodes = nodes
    props.checkable = true
    props.selectable = false
    return Tree(props)
end

--- Create a menu/navigation tree
---@param menuItems table[] Menu items
---@param onSelect function Selection handler
---@param props table|nil Additional props
---@return Tree
function Tree.Menu(menuItems, onSelect, props)
    props = props or {}
    props.nodes = menuItems
    props.onSelect = function(tree, keys, node)
        if onSelect and #keys > 0 then
            onSelect(keys[1], node)
        end
    end
    props.showIcons = true
    props.expandOnClick = true
    return Tree(props)
end

--- Create an organization tree
---@param orgData table[] Organization hierarchy
---@param props table|nil Additional props
---@return Tree
function Tree.Organization(orgData, props)
    props = props or {}
    props.nodes = orgData
    props.showLines = true
    props.showIcons = true
    return Tree(props)
end

return Tree
