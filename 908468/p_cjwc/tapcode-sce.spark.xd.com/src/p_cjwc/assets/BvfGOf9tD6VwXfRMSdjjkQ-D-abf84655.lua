local Button = require("urhox-libs/UI/Widgets/Button")

---@class NightgateAnimatedButton : Button
local AnimatedButton = Button:Extend("NightgateAnimatedButton")

function AnimatedButton:Init(props)
    props = props or {}
    self.motionHoverScale_ = tonumber(props.motionHoverScale) or 1.025
    self.motionPressedScale_ = tonumber(props.motionPressedScale) or 0.94
    self.dragThreshold_ = tonumber(props.dragThreshold) or 9
    self.dragCandidate_ = false
    self.dragging_ = false
    self.suppressClick_ = false
    props.scale = tonumber(props.scale) or 1
    props.transformOrigin = props.transformOrigin or "center"
    props.transition = props.transition or "scale 0.09s easeOut, backgroundColor 0.12s easeOut"

    -- Invisible click surfaces sit over the original pixel artwork. Give them a
    -- restrained tint so equipment cells and baked menu buttons still react.
    local color = props.backgroundColor
    if color and (color[4] or 255) == 0 and not props.backgroundImage and (props.backgroundImageOpacity or 0) == 0 then
        props.hoverBackgroundColor = props.hoverBackgroundColor or { 255, 255, 255, 18 }
        props.pressedBackgroundColor = props.pressedBackgroundColor or { 244, 171, 46, 38 }
    end
    if props.backgroundImage then
        props.hoverBackgroundImageOpacity = props.hoverBackgroundImageOpacity or 1
        props.pressedBackgroundImageOpacity = props.pressedBackgroundImageOpacity or 0.86
        props.disabledBackgroundImageOpacity = props.disabledBackgroundImageOpacity or 0.52
    end

    Button.Init(self, props)
end

function AnimatedButton:OnMouseEnter()
    Button.OnMouseEnter(self)
    if not self.props.disabled and not self.state.pressed then
        self:SetStyle({ scale = self.motionHoverScale_ })
    end
end

function AnimatedButton:OnMouseLeave()
    Button.OnMouseLeave(self)
    self:SetStyle({ scale = 1 })
end

function AnimatedButton:OnPointerDown(event)
    Button.OnPointerDown(self, event)
    if self.state.pressed then
        self:SetStyle({ scale = self.motionPressedScale_ })
        if self.props.onDragStart then
            self.dragCandidate_ = true
            self.dragging_ = false
            self.dragStartX_ = event.x
            self.dragStartY_ = event.y
        end
    end
end

function AnimatedButton:OnPointerMove(event)
    if not self.dragCandidate_ and not self.dragging_ then return end
    if not self.dragging_ then
        local distance = math.abs(event.x - self.dragStartX_) + math.abs(event.y - self.dragStartY_)
        if distance < self.dragThreshold_ then return end
        self.dragCandidate_ = false
        self.dragging_ = self.props.onDragStart(self, event) ~= false
        self.suppressClick_ = self.dragging_
    end
    if self.dragging_ and self.props.onDragMove then
        self.props.onDragMove(self, event)
    end
end

function AnimatedButton:OnPointerUp(event)
    local wasDragging = self.dragging_
    Button.OnPointerUp(self, event)
    self:SetStyle({ scale = self.state.hovered and self.motionHoverScale_ or 1 })
    self.dragCandidate_ = false
    self.dragging_ = false
    if wasDragging and self.props.onDragEnd then
        self.props.onDragEnd(self, event)
    end
end

function AnimatedButton:OnPointerCancel(event)
    local wasDragging = self.dragging_
    self.dragCandidate_ = false
    self.dragging_ = false
    Button.OnPointerCancel(self, event)
    self:SetStyle({ scale = 1 })
    if wasDragging and self.props.onDragCancel then
        self.props.onDragCancel(self, event)
    end
end

function AnimatedButton:OnClick(event)
    if self.suppressClick_ then
        self.suppressClick_ = false
        return
    end
    Button.OnClick(self, event)
end

function AnimatedButton:SetDisabled(disabled)
    Button.SetDisabled(self, disabled)
    if disabled then
        self:SetStyle({ scale = 1 })
    end
    return self
end

return AnimatedButton
