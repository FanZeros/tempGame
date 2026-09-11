-- ============================================================================
-- Panel Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Container with background and border
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class PanelProps : WidgetProps

---@class Panel : Widget
---@overload fun(props?: PanelProps): Panel
---@field props PanelProps
---@field new fun(self, props?: PanelProps): Panel
local Panel = Widget:Extend("Panel")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props PanelProps?
function Panel:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("Panel")
    Style.ApplyDefaults(props, themeStyle)

    -- backgroundColor defaults to nil (transparent), matching industry standard
    -- Use Theme.Color("surface") explicitly if you need a themed background

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Panel:Render(nvg)
    -- Render full background (shadow + color + image + border)
    -- Children are rendered by framework (or CustomRenderChildren for overflow="hidden")
    self:RenderFullBackground(nvg)
end

--- Custom child rendering with clipping for overflow="hidden"
---@param nvg NVGContextWrapper
---@param renderFn function Recursive render function
function Panel:CustomRenderChildren(nvg, renderFn)
    local props = self.props
    local renderList = self:GetRenderChildren()

    -- Render children with optional clipping
    if props.overflow == "hidden" then
        local l = self:GetAbsoluteLayout()
        nvgSave(nvg)
        nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)
        for i = 1, #renderList do
            renderFn(renderList[i], nvg)
        end
        nvgRestore(nvg)
    else
        -- No clipping needed, use standard framework recursion
        for i = 1, #renderList do
            renderFn(renderList[i], nvg)
        end
    end
end

-- ============================================================================
-- Stateless
-- ============================================================================

function Panel:IsStateful()
    return false
end

return Panel
