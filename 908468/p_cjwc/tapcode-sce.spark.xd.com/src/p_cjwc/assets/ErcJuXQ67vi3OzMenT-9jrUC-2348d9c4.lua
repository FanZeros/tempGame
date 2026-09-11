local Widget = require("urhox-libs/UI/Core/Widget")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")

---@class NightgateSkillCanvas : Widget
local SkillCanvas = Widget:Extend("NightgateSkillCanvas")

local COLORS = {
    locked = { 36, 0, 106, 255 },
    available = { 255, 239, 42, 255 },
    owned = { 255, 239, 42, 255 },
    maxed = { 255, 239, 42, 255 },
    selected = { 255, 232, 145, 255 },
}

local FRAME_BG = "image/nightgate/ui/equipment/equipment_add_bg.png"
local FRAME_BORDER = "image/nightgate/ui/equipment/equipment_cell_border.png"

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function color(value, alpha)
    return nvgRGBA(value[1], value[2], value[3], math.floor((value[4] or 255) * (alpha or 1)))
end

function SkillCanvas:Init(props)
    props = props or {}
    props.overflow = "hidden"
    props.backgroundColor = props.backgroundColor or { 13, 6, 19, 255 }
    self.nodes_ = props.nodes or {}
    self.nodeMap_ = {}
    self.images_ = {}
    self.panX_ = 0
    self.panY_ = 0
    self.minZoom_ = math.max(0.4, tonumber(props.minZoom) or 0.7)
    self.maxZoom_ = math.max(self.minZoom_, tonumber(props.maxZoom) or 2.2)
    self.zoom_ = clamp(tonumber(props.zoom) or 1, self.minZoom_, self.maxZoom_)
    self.viewWidth_ = math.max(1, tonumber(props.width) or 1)
    self.viewHeight_ = math.max(1, tonumber(props.height) or 1)
    self.dragging_ = false
    self.activePointerId_ = nil
    self.touches_ = {}
    self.pinching_ = false
    self.pinchStartDistance_ = 0
    self.pinchStartZoom_ = self.zoom_
    self.pinchAnchorX_ = 0
    self.pinchAnchorY_ = 0
    self.hoveredId_ = nil
    self.dragDistance_ = 0
    self.lastX_ = 0
    self.lastY_ = 0
    self.lastTapNodeId_ = nil
    self.lastTapTime_ = -10000
    self.elapsedTimeMs_ = 0
    self.doubleTapInterval_ = math.max(200, tonumber(props.doubleTapInterval) or 380)
    self.flashNodeId_ = nil
    self.flashTimer_ = 0
    self.flashSuccess_ = false
    self.attentionNodeId_ = nil
    self.attentionTimer_ = 0
    self.minPanX_ = props.minPanX or -80
    self.maxPanX_ = props.maxPanX or 80
    self.minPanY_ = props.minPanY or -560
    self.maxPanY_ = props.maxPanY or 0
    self.hitPadding_ = math.max(0, tonumber(props.hitPadding) or 0)
    self.tapSlop_ = math.max(8, tonumber(props.tapSlop) or 8)
    Widget.Init(self, props)
    self:SetNodes(self.nodes_)
end

function SkillCanvas:SetHovered(node)
    local nextId = node and node.id or nil
    if nextId == self.hoveredId_ then return end
    self.hoveredId_ = nextId
    if self.props.onNodeHover then
        self.props.onNodeHover(node)
    end
end

function SkillCanvas:SetNodes(nodes)
    self.nodes_ = nodes or {}
    self.nodeMap_ = {}
    for index = 1, #self.nodes_ do
        self.nodeMap_[self.nodes_[index].id] = self.nodes_[index]
    end
end

function SkillCanvas:SetSelected(id)
    self.props.selectedId = id
end

function SkillCanvas:SetView(x, y, zoom)
    local nextZoom = clamp(tonumber(zoom) or self.zoom_, self.minZoom_, self.maxZoom_)
    local extraX = math.abs(nextZoom - 1) * self.viewWidth_ * 0.5
    local extraY = math.abs(nextZoom - 1) * self.viewHeight_ * 0.5
    local nextX = clamp(x or 0, self.minPanX_ * nextZoom - extraX, self.maxPanX_ * nextZoom + extraX)
    local nextY = clamp(y or 0, self.minPanY_ * nextZoom - extraY, self.maxPanY_ * nextZoom + extraY)
    local changed = nextX ~= self.panX_ or nextY ~= self.panY_ or nextZoom ~= self.zoom_
    self.panX_ = nextX
    self.panY_ = nextY
    self.zoom_ = nextZoom
    if changed and self.props.onPanChanged then
        self.props.onPanChanged(self.panX_, self.panY_, self.zoom_)
    end
end

function SkillCanvas:SetPan(x, y)
    self:SetView(x, y, self.zoom_)
end

function SkillCanvas:GetZoom()
    return self.zoom_
end

function SkillCanvas:FlashNode(id, success)
    self.flashNodeId_ = id
    self.flashSuccess_ = success == true
    self.flashTimer_ = 0.8
end

function SkillCanvas:SetAttention(id)
    self.attentionNodeId_ = id
end

function SkillCanvas:Update(dt)
    dt = tonumber(dt) or 0
    self.elapsedTimeMs_ = self.elapsedTimeMs_ + dt * 1000
    self.flashTimer_ = math.max(0, self.flashTimer_ - dt)
    self.attentionTimer_ = (self.attentionTimer_ + dt) % 1.2
    if self.flashTimer_ <= 0 then self.flashNodeId_ = nil end
end

function SkillCanvas:GetTouchPair()
    local first = nil
    local second = nil
    for _, touch in pairs(self.touches_) do
        if not first then
            first = touch
        else
            second = touch
            break
        end
    end
    return first, second
end

function SkillCanvas:BeginPinch()
    local first, second = self:GetTouchPair()
    if not first or not second then return false end
    local startDistance = distance(first.x, first.y, second.x, second.y)
    if startDistance < 1 then return false end
    local centerX, centerY = self:ScreenToCanvas(
        (first.x + second.x) * 0.5,
        (first.y + second.y) * 0.5
    )
    self.pinching_ = true
    self.dragging_ = false
    self.activePointerId_ = nil
    self.pinchStartDistance_ = startDistance
    self.pinchStartZoom_ = self.zoom_
    self.pinchAnchorX_ = (centerX - self.panX_) / self.zoom_
    self.pinchAnchorY_ = (centerY - self.panY_) / self.zoom_
    self:SetHovered(nil)
    return true
end

function SkillCanvas:UpdatePinch()
    local first, second = self:GetTouchPair()
    if not self.pinching_ or not first or not second then return false end
    local currentDistance = distance(first.x, first.y, second.x, second.y)
    local centerX, centerY = self:ScreenToCanvas(
        (first.x + second.x) * 0.5,
        (first.y + second.y) * 0.5
    )
    local nextZoom = clamp(self.pinchStartZoom_ * currentDistance / self.pinchStartDistance_, self.minZoom_, self.maxZoom_)
    self:SetView(centerX - self.pinchAnchorX_ * nextZoom, centerY - self.pinchAnchorY_ * nextZoom, nextZoom)
    return true
end

function SkillCanvas:EnsureImages(ctx)
    if self.frameBg_ == nil then
        local handle = nvgCreateImage(ctx, FRAME_BG, NVG_IMAGE_NEAREST)
        self.frameBg_ = handle and handle >= 0 and handle or false
    end
    if self.frameBorder_ == nil then
        local handle = nvgCreateImage(ctx, FRAME_BORDER, NVG_IMAGE_NEAREST)
        self.frameBorder_ = handle and handle >= 0 and handle or false
    end
    for index = 1, #self.nodes_ do
        local node = self.nodes_[index]
        if node.revealed and node.icon and self.images_[node.icon] == nil then
            local handle = nvgCreateImage(ctx, node.icon, NVG_IMAGE_NEAREST)
            self.images_[node.icon] = handle and handle >= 0 and handle or false
        end
    end
end

function SkillCanvas:ScreenToCanvas(pointerX, pointerY)
    -- urhox-libs/UI reports pointer positions in base-screen space after removing
    -- visual transforms. Nodes are stored in this widget's content space, so
    -- remove the canvas' absolute origin before undoing pan and zoom. Otherwise
    -- the top bar and aspect-ratio margins shift every hit target away from art.
    local layout = self:GetAbsoluteLayoutForHitTest()
    if not layout then layout = self:GetAbsoluteLayout() end
    local localX = (pointerX or 0) - (layout and layout.x or 0)
    local localY = (pointerY or 0) - (layout and layout.y or 0)
    return localX, localY
end

function SkillCanvas:FindNode(pointerX, pointerY)
    local localX, localY = self:ScreenToCanvas(pointerX, pointerY)
    -- Undo the same pan + zoom transform used by Render().
    local x = (localX - self.panX_) / self.zoom_
    local y = (localY - self.panY_) / self.zoom_
    for index = #self.nodes_, 1, -1 do
        local node = self.nodes_[index]
        local hitPadding = math.max(0, tonumber(node.hitPadding) or self.hitPadding_)
        if node.revealed
            and x >= node.x - hitPadding and x <= node.x + node.size + hitPadding
            and y >= node.y - hitPadding and y <= node.y + node.size + hitPadding then
            return node
        end
    end
    return nil
end

---@return boolean
function SkillCanvas:OnPointerDown(event)
    Widget.OnPointerDown(self, event)
    if event.button == PointerEvent.Button.Left or event.button == nil then
        if event:IsTouch() then
            self.touches_[event.pointerId] = { x = event.x, y = event.y }
            local first, second = self:GetTouchPair()
            if first and second then
                self:BeginPinch()
                return true
            end
        end
        self.activePointerId_ = event.pointerId
        self.dragging_ = true
        self.dragDistance_ = 0
        self.lastX_ = event.x
        self.lastY_ = event.y
        return true
    end
    return false
end

---@return boolean
function SkillCanvas:OnPointerMove(event)
    Widget.OnPointerMove(self, event)
    if event:IsTouch() and self.touches_[event.pointerId] then
        self.touches_[event.pointerId].x = event.x
        self.touches_[event.pointerId].y = event.y
        if self.pinching_ then
            return self:UpdatePinch()
        end
    end
    if self.dragging_ and event.pointerId == self.activePointerId_ then
        local dx = event.x - self.lastX_
        local dy = event.y - self.lastY_
        self.dragDistance_ = self.dragDistance_ + math.abs(dx) + math.abs(dy)
        if self.dragDistance_ >= self.tapSlop_ then self:SetHovered(nil) end
        self:SetPan(self.panX_ + dx, self.panY_ + dy)
        self.lastX_ = event.x
        self.lastY_ = event.y
        return true
    end
    self:SetHovered(self:FindNode(event.x, event.y))
    return false
end

---@return boolean
function SkillCanvas:OnPointerUp(event)
    Widget.OnPointerUp(self, event)
    local wasPinching = self.pinching_
    if event:IsTouch() then
        self.touches_[event.pointerId] = nil
        local first, second = self:GetTouchPair()
        if wasPinching then
            if not first or not second then self.pinching_ = false end
            self.dragging_ = false
            self.activePointerId_ = nil
            return true
        end
    end
    if self.dragging_ and event.pointerId == self.activePointerId_ then
        self.dragging_ = false
        self.activePointerId_ = nil
        if self.dragDistance_ < self.tapSlop_ then
            local node = self:FindNode(event.x, event.y)
            if node then
                if self.props.onNodeClick then self.props.onNodeClick(node) end
                local now = self.elapsedTimeMs_
                local doubleTapped = node.id == self.lastTapNodeId_
                    and now - self.lastTapTime_ >= 0
                    and now - self.lastTapTime_ <= self.doubleTapInterval_
                if doubleTapped then
                    self.lastTapNodeId_ = nil
                    self.lastTapTime_ = -10000
                    if self.props.onNodeDoubleTap then self.props.onNodeDoubleTap(node) end
                else
                    self.lastTapNodeId_ = node.id
                    self.lastTapTime_ = now
                end
            end
        end
        return true
    end
    return false
end

function SkillCanvas:OnPointerLeave(event)
    Widget.OnPointerLeave(self, event)
    self:SetHovered(nil)
end

function SkillCanvas:OnPointerCancel(event)
    Widget.OnPointerCancel(self, event)
    self.touches_[event.pointerId] = nil
    if event.pointerId == self.activePointerId_ or self.pinching_ then
        self.dragging_ = false
        self.pinching_ = false
        self.activePointerId_ = nil
    end
end

function SkillCanvas:DrawImage(ctx, handle, x, y, w, h, alpha, tint)
    if not handle then return end
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    if tint then
        nvgFillPaint(ctx, nvgImagePatternTinted(ctx, x, y, w, h, 0, handle, color(tint, alpha)))
    else
        nvgFillPaint(ctx, nvgImagePattern(ctx, x, y, w, h, 0, handle, alpha or 1))
    end
    nvgFill(ctx)
end

function SkillCanvas:Render(ctx)
    local layout = self:GetAbsoluteLayout()
    if not layout or layout.w <= 0 or layout.h <= 0 then return end
    self:EnsureImages(ctx)

    nvgSave(ctx)
    nvgIntersectScissor(ctx, layout.x, layout.y, layout.w, layout.h)
    nvgBeginPath(ctx)
    nvgRect(ctx, layout.x, layout.y, layout.w, layout.h)
    local bg = nvgLinearGradient(ctx, layout.x, layout.y, layout.x, layout.y + layout.h,
        nvgRGBA(7, 4, 6, 255), nvgRGBA(57, 51, 76, 255))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)

    nvgTranslate(ctx, layout.x + self.panX_, layout.y + self.panY_)
    nvgScale(ctx, self.zoom_, self.zoom_)

    for index = 1, #self.nodes_ do
        local node = self.nodes_[index]
        if node.revealed then
            for parentIndex = 1, #(node.parents or {}) do
                local parent = self.nodeMap_[node.parents[parentIndex]]
                if parent and parent.revealed then
                    local active = node.state ~= "locked" and (parent.level or 0) > 0
                    local parentX = parent.x + parent.size * 0.5
                    local parentY = parent.y + parent.size * 0.5
                    local nodeX = node.x + node.size * 0.5
                    local nodeY = node.y + node.size * 0.5
                    local shadowOffset = node.size * 0.0375
                    nvgBeginPath(ctx)
                    nvgMoveTo(ctx, parentX + shadowOffset, parentY + shadowOffset)
                    nvgLineTo(ctx, nodeX + shadowOffset, nodeY + shadowOffset)
                    nvgStrokeColor(ctx, nvgRGBA(0, 0, 0, 102))
                    nvgStrokeWidth(ctx, math.max(2, node.size * 0.075))
                    nvgStroke(ctx)
                    nvgBeginPath(ctx)
                    nvgMoveTo(ctx, parentX, parentY)
                    nvgLineTo(ctx, nodeX, nodeY)
                    nvgStrokeColor(ctx, active and nvgRGBA(193, 140, 25, 255) or nvgRGBA(40, 19, 47, 255))
                    nvgStrokeWidth(ctx, math.max(2, node.size * 0.075))
                    nvgStroke(ctx)
                end
            end
        end
    end

    for index = 1, #self.nodes_ do
        local node = self.nodes_[index]
        if node.revealed then
            local selected = node.id == self.props.selectedId
            local border = selected and COLORS.selected or (COLORS[node.state] or COLORS.locked)
            local shadowOffset = node.size * 0.052
            nvgBeginPath(ctx)
            nvgRect(ctx, node.x + shadowOffset, node.y + shadowOffset, node.size, node.size)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, 102))
            nvgFill(ctx)
            self:DrawImage(ctx, self.frameBg_, node.x, node.y, node.size, node.size, 1)
            self:DrawImage(ctx, self.frameBorder_, node.x, node.y, node.size, node.size, 1, border)

            local inset = node.size * 0.1875
            local iconTint = node.state == "locked" and { 100, 100, 110, 255 }
                or (node.state == "available" and { 225, 220, 190, 255 } or nil)
            self:DrawImage(ctx, self.images_[node.icon], node.x + inset, node.y + inset,
                node.size - inset * 2, node.size - inset * 2, 1, iconTint)

            if node.id == self.attentionNodeId_ then
                local pulse = 0.35 + (0.5 + 0.5 * math.sin(self.attentionTimer_ / 1.2 * math.pi * 2)) * 0.65
                nvgBeginPath(ctx)
                nvgRect(ctx, node.x - node.size * 0.14, node.y - node.size * 0.14, node.size * 1.28, node.size * 1.28)
                nvgStrokeColor(ctx, nvgRGBA(255, 229, 70, math.floor(255 * pulse)))
                nvgStrokeWidth(ctx, math.max(4, node.size * 0.11))
                nvgStroke(ctx)
            end

            if node.id == self.flashNodeId_ and self.flashTimer_ > 0 then
                local pulse = 0.45 + math.abs(math.sin(self.flashTimer_ * 24)) * 0.55
                local flashColor = self.flashSuccess_ and { 113, 255, 78, 255 } or { 255, 73, 73, 255 }
                nvgBeginPath(ctx)
                nvgRect(ctx, node.x - node.size * 0.1, node.y - node.size * 0.1, node.size * 1.2, node.size * 1.2)
                nvgStrokeColor(ctx, color(flashColor, pulse))
                nvgStrokeWidth(ctx, math.max(3, node.size * 0.09))
                nvgStroke(ctx)
            end
        end
    end
    nvgRestore(ctx)
end

return SkillCanvas
