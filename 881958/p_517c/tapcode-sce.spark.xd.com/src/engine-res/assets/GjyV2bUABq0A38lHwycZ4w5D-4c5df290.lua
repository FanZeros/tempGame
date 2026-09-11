-- ============================================================================
-- SimpleGrid Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Equal-width column grid layout via flex wrap
-- ============================================================================
--
-- NOTE: This is NOT a CSS Grid implementation. It uses Yoga flex-wrap
-- to create equal-width columns. Same-row items have independent heights
-- (no cross-axis alignment like CSS Grid's grid-template-rows).
--
-- Good for: inventory grids, card lists, image galleries, icon grids.
-- NOT suitable for: complex 2D grid layouts requiring row+column alignment.
--
-- IMPLEMENTATION NOTE (fixed columns + gap/margin):
-- Yoga's flex-wrap line-breaking uses flexBasis + margin + columnGap to decide
-- when to wrap. Percentage flexBasis + pixel gap/margin always causes wrong
-- column count (e.g. 3×33.33% + 6px margin > 100% → wraps to 2 columns).
-- Fix: on first layout pass, use percentage basis without columnGap (correct
-- column count if no margin). In Render, read actual pixel width and set exact
-- pixel flexBasis (minus child margin) + columnGap. Second frame renders correctly.
-- This handles both gap and child margins transparently — AI can freely use
-- margin on grid children without breaking column count.
--
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI_MarkLayoutDirty -- lazy-loaded to avoid circular dependency

---@class SimpleGridProps : WidgetProps
---@field columns? number Number of columns (default: 4)
---@field minColumnWidth? number Minimum column width for responsive columns (overrides columns)
---@field gap? number Gap between items (both row and column)

---@class SimpleGrid : Widget
---@overload fun(props?: SimpleGridProps): SimpleGrid
---@field props SimpleGridProps
---@field new fun(self, props?: SimpleGridProps): SimpleGrid
local SimpleGrid = Widget:Extend("SimpleGrid")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props SimpleGridProps?
function SimpleGrid:Init(props)
    props = props or {}

    -- Grid layout: row direction with wrap
    props.flexDirection = "row"
    props.flexWrap = "wrap"

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("SimpleGrid")
    Style.ApplyDefaults(props, themeStyle)

    -- Store grid config
    self.columns_ = math.max(1, props.columns or 4)
    self.minColumnWidth_ = props.minColumnWidth
    self.gap_ = props.gap or 0

    if self.minColumnWidth_ then
        -- Responsive mode: pixel-based flexBasis works fine with columnGap
        if self.gap_ > 0 then
            props.columnGap = props.columnGap or self.gap_
            props.rowGap = props.rowGap or self.gap_
        end
    else
        -- Fixed columns: set rowGap only.
        -- columnGap is deferred to Render (after computing pixel widths).
        -- First frame: items at percentage basis without columnGap → correct column count, no gap.
        -- Second frame: pixel widths + columnGap → correct column count with gap.
        if self.gap_ > 0 then
            props.rowGap = props.rowGap or self.gap_
        end
    end

    Widget.Init(self, props)
end

-- ============================================================================
-- Child Management Override
-- ============================================================================

--- Override AddChild to set flex basis on children
---@param child Widget
---@return SimpleGrid self
function SimpleGrid:AddChild(child)
    if not child then return self end

    -- Calculate and set flex basis for equal-width columns
    self:ApplyChildBasis_(child)

    -- Call parent AddChild
    Widget.AddChild(self, child)

    -- Reset cached width so Render recalculates pixel-based widths
    -- for all children (new child's margin may differ)
    if not self.minColumnWidth_ then
        self.lastLayoutWidth_ = nil
    end

    return self
end

--- Apply flex basis to a child based on column configuration.
--- Uses SetStyle to apply both props AND Yoga node properties.
---@param child Widget
function SimpleGrid:ApplyChildBasis_(child)
    local style = {}

    if self.minColumnWidth_ then
        -- Responsive: let children grow, set minWidth + flexBasis for proper wrapping
        if not child.props.minWidth then style.minWidth = self.minColumnWidth_ end
        if not child.props.flexBasis then style.flexBasis = self.minColumnWidth_ end
        if not child.props.flexGrow then style.flexGrow = 1 end
        if not child.props.flexShrink then style.flexShrink = 1 end
    else
        -- Fixed columns: percentage basis as initial layout hint.
        -- Will be overridden with exact pixel values in Render.
        if not child.props.flexBasis then
            style.flexBasis = tostring(math.floor(10000 / self.columns_) / 100) .. "%"
        end
        if not child.props.flexGrow then style.flexGrow = 0 end
        if not child.props.flexShrink then style.flexShrink = 0 end
    end

    -- Apply to both props and Yoga node
    if next(style) then
        child:SetStyle(style)
    end
end

-- ============================================================================
-- Rendering
-- ============================================================================

function SimpleGrid:Render(nvg)
    -- Fixed columns: compute exact pixel widths from actual layout.
    -- Handles both gap and child margins — percentage flexBasis + pixel
    -- gap/margin causes wrong column count in Yoga's flex-wrap.
    if not self.minColumnWidth_ then
        local w = YGNodeLayoutGetWidth(self.node)
        if w > 0 and w ~= self.lastLayoutWidth_ then
            self.lastLayoutWidth_ = w
            local columns = self.columns_
            local gap = self.gap_
            local totalGap = (columns - 1) * gap
            -- Per-column available width (before child margin).
            -- Subtract 1px slack for multi-column grids: Yoga may wrap when
            -- items exactly fill the container (exact-fit edge case).
            local slack = columns > 1 and 1 or 0
            local colWidth = (w - totalGap - slack) / columns
            local styleTable = { flexBasis = 0 }
            for _, child in ipairs(self.children) do
                local marginH = self:GetChildHorizontalMargin_(child)
                -- Floor to integer pixels: Yoga rounds fractional basis UP during
                -- line-breaking, so 147.66 * 3 = 444 > 443 → wraps!
                -- floor(147.66) = 147, 147 * 3 = 441 ≤ 443 → correct.
                styleTable.flexBasis = math.max(0, math.floor(colWidth - marginH))
                child:SetStyle(styleTable)
            end
            -- Enable columnGap now that children have pixel-based flexBasis
            if gap > 0 and not self.gapApplied_ then
                YGNodeStyleSetGap(self.node, YGGutterColumn, gap)
                self.props.columnGap = gap
                self.gapApplied_ = true
            end
            -- Mark layout dirty so next frame's Layout() uses the new flexBasis.
            -- Without this, pixel-fix runs in Render (after Layout), but if no
            -- other trigger sets layoutDirty_, the new values are never applied.
            if not UI_MarkLayoutDirty then
                UI_MarkLayoutDirty = require("urhox-libs/UI").MarkLayoutDirty
            end
            UI_MarkLayoutDirty()
        end
    end

    self:RenderFullBackground(nvg)
end

--- Get total horizontal margin of a child (left + right).
--- Resolves margin shorthand precedence: marginLeft > marginHorizontal > margin.
---@param child Widget
---@return number
function SimpleGrid:GetChildHorizontalMargin_(child)
    local p = child.props
    if not p then return 0 end
    local base = p.margin or 0
    local horiz = p.marginHorizontal or base
    local ml = p.marginLeft or horiz
    local mr = p.marginRight or horiz
    -- Only handle numeric margins; percentage/auto strings are resolved by Yoga
    if type(ml) ~= "number" then ml = 0 end
    if type(mr) ~= "number" then mr = 0 end
    return ml + mr
end

--- Custom child rendering with clipping for overflow="hidden"
---@param nvg NVGContextWrapper
---@param renderFn function Recursive render function
function SimpleGrid:CustomRenderChildren(nvg, renderFn)
    local props = self.props
    local renderList = self:GetRenderChildren()

    if props.overflow == "hidden" then
        local l = self:GetAbsoluteLayout()
        nvgSave(nvg)
        nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)
        for i = 1, #renderList do
            renderFn(renderList[i], nvg)
        end
        nvgRestore(nvg)
    else
        for i = 1, #renderList do
            renderFn(renderList[i], nvg)
        end
    end
end

-- ============================================================================
-- Stateless
-- ============================================================================

function SimpleGrid:IsStateful()
    return false
end

return SimpleGrid
