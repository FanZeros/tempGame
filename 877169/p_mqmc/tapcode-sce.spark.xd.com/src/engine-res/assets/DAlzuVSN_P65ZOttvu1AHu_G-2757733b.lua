-- ============================================================================
-- SkillTree Component
-- UrhoX UI Library - Skill tree visualization with zoom/pan support
--
-- Features:
--   - JSON-based skill tree configuration
--   - Parent-child node connections with lines
--   - State-based coloring (unlocked/locked/unlockable)
--   - Mouse wheel zoom and middle-button pan
--   - Boundary constraints
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")

---@class SkillTreeProps : WidgetProps
---@field nodes? table[] Skill node data array (default: empty)
---@field nodeSize? number Node size in pixels (default: 64)
---@field nodeShape? string Node shape: "circle", "rounded", "square" (default: "circle")
---@field lineWidth? number Connection line width (default: 3)
---@field colors? table Color scheme { unlocked, locked, unlockable, line_unlocked, line_locked }
---@field minZoom? number Minimum zoom level (default: 0.5)
---@field maxZoom? number Maximum zoom level (default: 2.0)
---@field onNodeClick? fun(node: table) Callback when node is clicked
---@field onNodeUnlock? fun(node: table) Callback when trying to unlock a node

---@class SkillTree : Widget
---@overload fun(props?: SkillTreeProps): SkillTree
---@field props SkillTreeProps
---@field new fun(self, props?: SkillTreeProps): SkillTree
local SkillTree = Widget:Extend("SkillTree")

-- ============================================================================
-- Default Colors
-- ============================================================================

local DEFAULT_COLORS = {
    unlocked = { 100, 200, 100, 255 },       -- Green for unlocked
    locked = { 80, 80, 90, 255 },            -- Dark gray for locked
    unlockable = { 255, 200, 80, 255 },      -- Gold for unlockable
    line_unlocked = { 80, 160, 80, 255 },    -- Darker green for unlocked lines
    line_locked = { 50, 50, 60, 255 },       -- Dark gray for locked lines
    background = { 30, 32, 40, 255 },        -- Panel background
    node_border = { 255, 255, 255, 100 },    -- Node border
    text = { 255, 255, 255, 255 },           -- Text color
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props SkillTreeProps?
function SkillTree:Init(props)
    props = props or {}

    -- Defaults
    props.nodeSize = props.nodeSize or 64
    props.nodeShape = props.nodeShape or "circle"  -- Default to circle (mainstream style)
    props.lineWidth = props.lineWidth or 3
    props.minZoom = props.minZoom or 0.5
    props.maxZoom = props.maxZoom or 2.0
    props.colors = props.colors or DEFAULT_COLORS

    -- Ensure we have a background
    props.backgroundColor = props.backgroundColor or DEFAULT_COLORS.background
    props.overflow = "hidden"  -- Clip content outside bounds

    -- Internal state
    self.zoom_ = 1.0
    self.panX_ = 0
    self.panY_ = 0
    self.isPanning_ = false
    self.lastPanX_ = 0
    self.lastPanY_ = 0

    -- Node lookup by ID
    self.nodeMap_ = {}

    -- Animation state
    self.time_ = 0

    -- Hover state
    self.hoveredNode_ = nil

    -- Content bounds (calculated from nodes)
    self.contentBounds_ = { minX = 0, minY = 0, maxX = 0, maxY = 0 }

    -- Flag for initial centering (layout not ready in Init)
    self.needsInitialCenter_ = true

    Widget.Init(self, props)

    -- Build node map
    self:RebuildNodeMap()
end

-- ============================================================================
-- Node Management
-- ============================================================================

--- Rebuild the node lookup map and calculate content bounds
function SkillTree:RebuildNodeMap()
    self.nodeMap_ = {}
    local nodes = self.props.nodes or {}

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local nodeSize = self.props.nodeSize

    for _, node in ipairs(nodes) do
        self.nodeMap_[node.id] = node

        -- Track bounds
        local x, y = (node.x or 0), (node.y or 0)
        minX = math.min(minX, x)
        minY = math.min(minY, y)
        maxX = math.max(maxX, x + nodeSize)
        maxY = math.max(maxY, y + nodeSize)
    end

    -- Add padding
    local padding = nodeSize
    self.contentBounds_ = {
        minX = minX - padding,
        minY = minY - padding,
        maxX = maxX + padding,
        maxY = maxY + padding,
    }
end

--- Set nodes data
---@param nodes table[]
function SkillTree:SetNodes(nodes)
    self.props.nodes = nodes
    self:RebuildNodeMap()
end

--- Get node by ID
---@param id any
---@return table|nil
function SkillTree:GetNode(id)
    return self.nodeMap_[id]
end

--- Check if a node is unlockable (all parents unlocked)
---@param node table
---@return boolean
function SkillTree:IsUnlockable(node)
    if node.unlocked then
        return false  -- Already unlocked
    end

    -- No parent means it's a root node, always unlockable if not unlocked
    if not node.parentId then
        return true
    end

    -- Check if parent is unlocked
    local parent = self.nodeMap_[node.parentId]
    if parent and parent.unlocked then
        return true
    end

    return false
end

--- Get node state
---@param node table
---@return string "unlocked", "locked", or "unlockable"
function SkillTree:GetNodeState(node)
    if node.unlocked then
        return "unlocked"
    elseif self:IsUnlockable(node) then
        return "unlockable"
    else
        return "locked"
    end
end

--- Unlock a node (if unlockable)
---@param nodeId any
---@return boolean success
function SkillTree:UnlockNode(nodeId)
    local node = self.nodeMap_[nodeId]
    if not node then
        return false
    end

    if not self:IsUnlockable(node) then
        return false
    end

    node.unlocked = true

    if self.props.onNodeUnlock then
        self.props.onNodeUnlock(node)
    end

    return true
end

--- Check if a node can be locked (no unlocked children depend on it)
---@param node table
---@return boolean
function SkillTree:CanLock(node)
    if not node.unlocked then
        return false  -- Already locked
    end

    -- Check if any unlocked node depends on this one
    local nodes = self.props.nodes or {}
    for _, child in ipairs(nodes) do
        if child.parentId == node.id and child.unlocked then
            return false  -- Has unlocked child, cannot lock
        end
    end

    return true
end

--- Lock a node (if lockable)
---@param nodeId any
---@return boolean success
function SkillTree:LockNode(nodeId)
    local node = self.nodeMap_[nodeId]
    if not node then
        return false
    end

    if not self:CanLock(node) then
        return false
    end

    node.unlocked = false

    if self.props.onNodeLock then
        self.props.onNodeLock(node)
    end

    return true
end

-- ============================================================================
-- Zoom and Pan
-- ============================================================================

--- Set zoom level (clamped to min/max)
---@param zoom number
function SkillTree:SetZoom(zoom)
    self.zoom_ = math.max(self.props.minZoom, math.min(self.props.maxZoom, zoom))
    self:ClampPan()
end

--- Get current zoom level
---@return number
function SkillTree:GetZoom()
    return self.zoom_
end

--- Set pan offset
---@param x number
---@param y number
function SkillTree:SetPan(x, y)
    self.panX_ = x
    self.panY_ = y
    self:ClampPan()
end

--- Get pan offset
---@return number, number
function SkillTree:GetPan()
    return self.panX_, self.panY_
end

--- Clamp pan to content bounds
function SkillTree:ClampPan()
    local layout = self:GetLayout()
    if not layout or layout.w <= 0 or layout.h <= 0 then
        return
    end

    local viewW = layout.w
    local viewH = layout.h
    local bounds = self.contentBounds_
    local zoom = self.zoom_

    -- Calculate scaled content size
    local contentW = (bounds.maxX - bounds.minX) * zoom
    local contentH = (bounds.maxY - bounds.minY) * zoom

    -- Calculate pan limits
    -- Allow panning so content edge can reach view edge (both directions)
    local minPanX, maxPanX
    local minPanY, maxPanY

    if contentW <= viewW then
        -- Content smaller than view: allow panning within view bounds
        minPanX = 0
        maxPanX = viewW - contentW
    else
        -- Content larger than view: standard scroll limits
        minPanX = viewW - contentW - bounds.minX * zoom
        maxPanX = -bounds.minX * zoom
    end

    if contentH <= viewH then
        -- Content smaller than view: allow panning within view bounds
        minPanY = 0
        maxPanY = viewH - contentH
    else
        -- Content larger than view: standard scroll limits
        minPanY = viewH - contentH - bounds.minY * zoom
        maxPanY = -bounds.minY * zoom
    end

    self.panX_ = math.max(minPanX, math.min(maxPanX, self.panX_))
    self.panY_ = math.max(minPanY, math.min(maxPanY, self.panY_))
end

--- Center view on a node
---@param nodeId any
function SkillTree:CenterOnNode(nodeId)
    local node = self.nodeMap_[nodeId]
    if not node then return end

    local layout = self:GetLayout()
    if not layout then return end

    local nodeSize = self.props.nodeSize
    local centerX = node.x + nodeSize / 2
    local centerY = node.y + nodeSize / 2

    self.panX_ = layout.w / 2 - centerX * self.zoom_
    self.panY_ = layout.h / 2 - centerY * self.zoom_
    self:ClampPan()
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function SkillTree:OnWheel(dx, dy)
    -- Zoom with scroll wheel
    local zoomFactor = 1.1
    local oldZoom = self.zoom_

    if dy > 0 then
        self:SetZoom(self.zoom_ * zoomFactor)
    elseif dy < 0 then
        self:SetZoom(self.zoom_ / zoomFactor)
    end

    -- Adjust pan to zoom toward cursor (TODO: get cursor position)
    -- For now, zoom toward center
end

function SkillTree:OnPointerDown(event)
    Widget.OnPointerDown(self, event)

    -- Middle mouse button for panning
    if event.button == PointerEvent.Button.Middle then
        self.isPanning_ = true
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    -- Left click on node
    if event.button == PointerEvent.Button.Left or event.button == nil then
        local node = self:FindNodeAt(event.x, event.y)
        if node then
            if self.props.onNodeClick then
                self.props.onNodeClick(node)
            end

            local state = self:GetNodeState(node)
            if state == "unlockable" then
                -- Unlock
                self:UnlockNode(node.id)
            elseif state == "unlocked" and self:CanLock(node) then
                -- Lock (refund)
                self:LockNode(node.id)
            end
            return true
        end
    end
end

function SkillTree:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    if self.isPanning_ then
        local dx = event.x - self.lastPanX_
        local dy = event.y - self.lastPanY_
        self.panX_ = self.panX_ + dx
        self.panY_ = self.panY_ + dy
        self:ClampPan()
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    -- Update hover state
    self.hoveredNode_ = self:FindNodeAt(event.x, event.y)
end

function SkillTree:OnPointerLeave(event)
    Widget.OnPointerLeave(self, event)
    self.hoveredNode_ = nil
end

function SkillTree:OnPointerUp(event)
    Widget.OnPointerUp(self, event)

    -- Middle button release
    if event.button == PointerEvent.Button.Middle then
        self.isPanning_ = false
    end
end

--- Find node at screen position
---@param screenX number
---@param screenY number
---@return table|nil
function SkillTree:FindNodeAt(screenX, screenY)
    local layout = self:GetAbsoluteLayout()
    if not layout then return nil end

    -- Convert screen coords to content coords
    local contentX = (screenX - layout.x - self.panX_) / self.zoom_
    local contentY = (screenY - layout.y - self.panY_) / self.zoom_

    local nodeSize = self.props.nodeSize
    local nodeShape = self.props.nodeShape
    local nodes = self.props.nodes or {}
    local isCircle = (nodeShape == "circle")

    -- Check nodes in reverse order (top-most first)
    for i = #nodes, 1, -1 do
        local node = nodes[i]
        local nx, ny = (node.x or 0), (node.y or 0)

        if isCircle then
            -- Circular hit test
            local centerX = nx + nodeSize / 2
            local centerY = ny + nodeSize / 2
            local radius = nodeSize / 2
            local dx = contentX - centerX
            local dy = contentY - centerY
            if (dx * dx + dy * dy) <= (radius * radius) then
                return node
            end
        else
            -- Rectangular hit test
            if contentX >= nx and contentX <= nx + nodeSize and
               contentY >= ny and contentY <= ny + nodeSize then
                return node
            end
        end
    end

    return nil
end

-- ============================================================================
-- Update (for animation)
-- ============================================================================

function SkillTree:Update(dt)
    self.time_ = self.time_ + dt
end

-- ============================================================================
-- Rendering
-- ============================================================================

function SkillTree:Render(nvg)
    local layout = self:GetAbsoluteLayout()
    if not layout or layout.w <= 0 or layout.h <= 0 then
        return
    end

    -- Initial centering (deferred until layout is ready)
    if self.needsInitialCenter_ then
        self.needsInitialCenter_ = false
        self:ClampPan()  -- This will center content if it fits
    end

    -- Render background
    self:RenderFullBackground(nvg)

    -- Set up clipping
    nvgSave(nvg)
    nvgIntersectScissor(nvg, layout.x, layout.y, layout.w, layout.h)

    -- Apply zoom and pan transform
    nvgTranslate(nvg, layout.x + self.panX_, layout.y + self.panY_)
    nvgScale(nvg, self.zoom_, self.zoom_)

    -- Render connections first (behind nodes)
    self:RenderConnections(nvg)

    -- Render nodes
    self:RenderNodes(nvg)

    nvgRestore(nvg)
end

function SkillTree:RenderConnections(nvg)
    local nodes = self.props.nodes or {}
    local colors = self.props.colors
    local lineWidth = self.props.lineWidth
    local nodeSize = self.props.nodeSize

    for _, node in ipairs(nodes) do
        if node.parentId then
            local parent = self.nodeMap_[node.parentId]
            if parent then
                -- Calculate line endpoints (center of nodes)
                local x1 = parent.x + nodeSize / 2
                local y1 = parent.y + nodeSize / 2
                local x2 = node.x + nodeSize / 2
                local y2 = node.y + nodeSize / 2

                -- Determine line color based on connection state
                local lineColor
                if parent.unlocked and node.unlocked then
                    lineColor = colors.line_unlocked
                else
                    lineColor = colors.line_locked
                end

                -- Draw line
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, x1, y1)
                nvgLineTo(nvg, x2, y2)
                nvgStrokeColor(nvg, nvgRGBA(lineColor[1], lineColor[2], lineColor[3], lineColor[4]))
                nvgStrokeWidth(nvg, lineWidth)
                nvgStroke(nvg)
            end
        end
    end
end

function SkillTree:RenderNodes(nvg)
    local nodes = self.props.nodes or {}
    local colors = self.props.colors
    local nodeSize = self.props.nodeSize
    local nodeShape = self.props.nodeShape

    for _, node in ipairs(nodes) do
        local state = self:GetNodeState(node)
        local x, y = (node.x or 0), (node.y or 0)
        local isHovered = (self.hoveredNode_ == node)

        -- Hover: slight scale up effect
        local hoverScale = isHovered and 1.08 or 1.0
        local drawSize = nodeSize * hoverScale
        local drawX = x - (drawSize - nodeSize) / 2
        local drawY = y - (drawSize - nodeSize) / 2

        -- Calculate shape-specific geometry
        local isCircle = (nodeShape == "circle")
        local centerX = drawX + drawSize / 2
        local centerY = drawY + drawSize / 2
        local radius = isCircle and (drawSize / 2) or (8 * hoverScale)

        -- Determine colors based on state
        local nodeColor
        local borderColor
        local borderWidth = 2
        local contentAlpha = 255

        if state == "unlocked" then
            nodeColor = colors.unlocked
            borderColor = { 80, 180, 80, 255 }
        elseif state == "unlockable" then
            nodeColor = colors.unlockable
            borderColor = { 220, 180, 60, 255 }
        else
            nodeColor = colors.locked
            borderColor = { 50, 50, 60, 255 }
            contentAlpha = 120
        end

        -- Hover: draw soft glow shadow first
        if isHovered then
            local glowColor
            if state == "unlocked" then
                glowColor = { 100, 200, 100 }
            elseif state == "unlockable" then
                glowColor = { 255, 200, 80 }
            else
                glowColor = { 150, 150, 180 }
            end
            -- Outer glow using box gradient
            local glowBlur = 8
            local glowPadding = 12
            local shadowPaint = nvgBoxGradient(nvg,
                drawX, drawY, drawSize, drawSize,
                radius, glowBlur,
                nvgRGBA(glowColor[1], glowColor[2], glowColor[3], 80),
                nvgRGBA(0, 0, 0, 0)
            )
            nvgBeginPath(nvg)
            nvgRect(nvg, drawX - glowPadding, drawY - glowPadding, drawSize + glowPadding * 2, drawSize + glowPadding * 2)
            nvgFillPaint(nvg, shadowPaint)
            nvgFill(nvg)
        end

        -- Draw node background
        nvgBeginPath(nvg)
        if isCircle then
            nvgCircle(nvg, centerX, centerY, radius)
        else
            nvgRoundedRect(nvg, drawX, drawY, drawSize, drawSize, radius)
        end
        nvgFillColor(nvg, nvgRGBA(nodeColor[1], nodeColor[2], nodeColor[3], nodeColor[4] or 255))
        nvgFill(nvg)

        -- Draw node border
        nvgBeginPath(nvg)
        if isCircle then
            nvgCircle(nvg, centerX, centerY, radius)
        else
            nvgRoundedRect(nvg, drawX, drawY, drawSize, drawSize, radius)
        end
        if isHovered then
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(nvg, 2)
        else
            nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4]))
            nvgStrokeWidth(nvg, borderWidth)
        end
        nvgStroke(nvg)

        -- Draw icon (centered)
        if node.icon then
            nvgFontSize(nvg, drawSize * 0.4)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, contentAlpha))
            nvgText(nvg, centerX, centerY, node.icon)
        end

        -- Draw name (below node, outside the circle)
        if node.name then
            nvgFontSize(nvg, 10 * hoverScale)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(nvg, nvgRGBA(colors.text[1], colors.text[2], colors.text[3], contentAlpha))
            nvgText(nvg, centerX, drawY + drawSize + 4, node.name)
        end
    end
end

return SkillTree
