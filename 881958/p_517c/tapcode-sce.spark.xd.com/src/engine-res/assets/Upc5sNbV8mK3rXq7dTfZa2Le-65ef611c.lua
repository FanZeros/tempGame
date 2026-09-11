-- ============================================================================
-- PulsingCircles Widget
-- UrhoX UI Library - Yoga + NanoVG
-- 脉冲圆环加载动画：从中心向外扩散的同心圆环，常用于"匹配中 / 连接中"。
-- 动画由 UI.Update(dt) 逐帧驱动（自累加 animTime_），无需调用方传时间。
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")

---@class PulsingCircles : Widget
---@operator call(table?): PulsingCircles
local PulsingCircles = Widget:Extend("PulsingCircles")

function PulsingCircles:Init(props)
    props = props or {}
    props.width = props.width or 280
    props.height = props.height or 280
    self.color_ = props.color or { 51, 153, 255 }
    self.ringCount_ = props.ringCount or 3
    self.animTime_ = 0
    Widget.Init(self, props)
end

function PulsingCircles:Update(dt)
    self.animTime_ = self.animTime_ + dt
end

function PulsingCircles:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local cx, cy = l.x + l.w / 2, l.y + l.h / 2
    local maxRadius = math.min(l.w, l.h) / 2
    local color = self.color_
    local ringCount = self.ringCount_
    local time = self.animTime_
    for i = 1, ringCount do
        local phase = (i - 1) / ringCount
        local progress = (time * 0.15 + phase) % 1.0
        local radius = maxRadius * 0.3 + maxRadius * 0.7 * progress
        local alpha = (1.0 - progress) * 0.6
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, radius)
        nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], alpha * 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end
end

return PulsingCircles
