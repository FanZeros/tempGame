-- ============================================================================
-- ScrollView Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Scrollable container with optional scrollbars
-- ============================================================================
--[[

⚠️ COMMON ISSUE: ScrollView cannot scroll in flex layout?

   CAUSE: By default, flexBasis is "auto", which means the ScrollView will
          expand to fit its content height, leaving no room to scroll.

   SOLUTION: Add flexBasis = 0 when using flexGrow:

   ✅ CORRECT USAGE:
   UI.ScrollView {
       flexGrow = 1,
       flexBasis = 0,  -- IMPORTANT! Prevents content from expanding ScrollView
       scrollY = true,
   }

   ❌ WRONG USAGE (will not scroll):
   UI.ScrollView {
       flexGrow = 1,   -- Without flexBasis=0, ScrollView expands to content height
       scrollY = true,
   }

   WHY: In Yoga/Flexbox, flexBasis controls the initial size before flex
        distribution. "auto" means use content size, "0" means start from zero
        and let flexGrow allocate space from the parent container.

]]

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")

-- Helper to detect if touch input mode (mobile or touch emulation)
local function isTouchInputMode()
    -- Check for mobile platform
    if GetNativePlatform then
        local p = GetNativePlatform()
        if p == "Android" or p == "iOS" or p == "HarmonyOS" then
            return true
        end
    end
    -- Check for touch emulation on desktop
    if input and input.touchEmulation then
        return true
    end
    return false
end

---@class ScrollViewProps : WidgetProps
---@field scrollX? boolean Enable horizontal scroll
---@field scrollY? boolean Enable vertical scroll (default: true)
---@field showScrollbar? boolean Show scrollbar indicators
---@field scrollbarInteractive? boolean Enable scrollbar drag and track click
---@field bounces? boolean Enable bounce effect at edges
---@field scrollSnapType? string "y mandatory" | "y proximity" | "x mandatory" | "x proximity"
---@field onScroll? fun(self: ScrollView, scrollX: number, scrollY: number) Scroll callback

---@class ScrollView : Widget
---@overload fun(props?: ScrollViewProps): ScrollView
---@field props ScrollViewProps
---@field new fun(self, props?: ScrollViewProps): ScrollView
---@field state {scrollX: number, scrollY: number, isDragging: boolean, velocityX: number, velocityY: number}
---@field GetScroll fun(self): number, number Get current scroll position
---@field AddChild fun(self, child: Widget): self Add child widget
---@field RemoveChild fun(self, child: Widget): self Remove child widget
local ScrollView = Widget:Extend("ScrollView")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ScrollViewProps?
function ScrollView:Init(props)
    props = props or {}

    -- Default scroll settings
    props.scrollX = props.scrollX ~= false and props.scrollX or false
    props.scrollY = props.scrollY ~= false  -- Default true for vertical
    props.showScrollbar = props.showScrollbar ~= false  -- Default true
    props.bounces = props.bounces ~= false  -- Default true

    -- scrollbarInteractive: default to false on touch devices (mobile/touch emulation)
    -- Users can still explicitly set it to true if needed
    if props.scrollbarInteractive == nil then
        props.scrollbarInteractive = not isTouchInputMode()
    end

    -- Clip children to bounds
    props.overflow = "hidden"

    -- Auto-fix: flexGrow without flexBasis is the most common ScrollView mistake.
    -- When flexBasis is "auto" (default/nil), ScrollView expands to content height,
    -- leaving no room to scroll. Fix by setting flexBasis = 0.
    -- Note: flex=N is a shorthand that sets flexGrow=N, flexShrink=N, flexBasis=0
    -- at the Yoga level, but in Lua props only props.flex is set. However, Yoga
    -- already handles flexBasis=0 internally for flex=N, so we only need to fix
    -- the case where flexGrow is set explicitly without flexBasis.
    local hasFlexGrow = (props.flexGrow and props.flexGrow > 0)
                     or (props.flex and props.flex > 0)
    if hasFlexGrow and props.flexBasis == nil and not props.flex then
        -- Only auto-set flexBasis when flexGrow is used without flex shorthand.
        -- flex=N already implies flexBasis=0 at Yoga level, no Lua-side fix needed.
        props.flexBasis = 0
        print(string.format(
            "[ScrollView] Auto-set flexBasis=0 (flexGrow=%g detected). "
            .. "ScrollView needs flexBasis=0 to scroll in flex layout. "
            .. "Set flexBasis explicitly to suppress this message.",
            props.flexGrow
        ))
    end

    -- Initialize state
    self.state = {
        scrollX = 0,
        scrollY = 0,
        isDragging = false,
        velocityX = 0,
        velocityY = 0,
    }

    -- Internal state
    self.contentWidth_ = 0
    self.contentHeight_ = 0
    self.dragStartScrollX_ = 0
    self.dragStartScrollY_ = 0
    self.scrollbarOpacity_ = 0
    self.scrollbarFadeTimer_ = 0

    -- Scrollbar interaction state
    self.isDraggingScrollbarV_ = false  -- Dragging vertical scrollbar
    self.isDraggingScrollbarH_ = false  -- Dragging horizontal scrollbar
    self.scrollbarDragStartY_ = 0       -- Mouse Y when drag started
    self.scrollbarDragStartX_ = 0       -- Mouse X when drag started
    self.scrollbarDragStartScrollY_ = 0 -- Scroll position when drag started
    self.scrollbarDragStartScrollX_ = 0
    -- Cached drag parameters (calculated at drag start for smooth dragging)
    self.scrollbarDragTrackRangeV_ = 0
    self.scrollbarDragTrackRangeH_ = 0
    self.scrollbarDragMaxScrollV_ = 0
    self.scrollbarDragMaxScrollH_ = 0

    -- Cached scrollbar bounds for hit testing
    self.vScrollbarBounds_ = nil  -- { x, y, w, h }
    self.hScrollbarBounds_ = nil
    self.vTrackBounds_ = nil      -- Full track area
    self.hTrackBounds_ = nil

    -- Scroll snap state
    self.snapTargetX_ = nil
    self.snapTargetY_ = nil
    self.isSnapping_ = false
    self.snapChecked_ = false

    -- Parse scrollSnapType once (avoid per-frame string.match)
    if props.scrollSnapType then
        local axis, mode = props.scrollSnapType:match("^(%a+)%s+(%a+)$")
        self.snapAxis_ = axis
        self.snapMode_ = mode
    end

    Widget.Init(self, props)
end

-- ============================================================================
-- Child Management: Sticky cache invalidation + Prevent flex-shrink
-- ============================================================================
-- WHY FLEX-SHRINK=0:
-- In CSS, overflow:scroll creates a "scroll context" — children are laid out as
-- if the container has UNLIMITED size in the scroll direction. Children never
-- shrink; they overflow, and scrolling handles it.
--
-- Yoga does NOT replicate this behavior. Yoga's overflow property only controls
-- visual clipping, NOT layout. So in a Yoga-based ScrollView with flexGrow=1
-- and flexBasis=0 (fixed height), children with flexShrink>0 are SHRUNK by Yoga
-- to fit inside the container. With many children, each gets near-zero height,
-- contentHeight ≈ container height, and scrolling becomes impossible.
--
-- The fix: force flexShrink=0 on all direct children so they keep their natural
-- size and overflow the container, enabling proper scrolling.
--
-- This is analogous to what CSS does silently. Without it, any AI-generated UI
-- with a ScrollView containing many items (Labels, Cards, etc.) will produce
-- overlapping, unscrollable content — a subtle, hard-to-debug rendering bug.

--- Enforce flexShrink=0 on a child (prevents shrinking in scroll container)
--- In a scroll container, shrinking children is never correct.
--- If children shrink to fit, there's nothing to scroll.
---@param child Widget
function ScrollView:EnforceNoShrink_(child)
    if child and child.props then
        local fs = child.props.flexShrink
        -- Only override when user explicitly set a non-zero flexShrink.
        -- When nil (not set), Yoga default is already 0 — calling
        -- YGNodeStyleSetFlexShrink(node, 0) would change the style from
        -- "undefined" to "0", which Yoga treats as a change and triggers
        -- markDirtyAndPropagate(), resetting computedFlexBasis and potentially
        -- causing incorrect layout in multi-pass scenarios (e.g. SimpleGrid
        -- percentage flexBasis inside ScrollView).
        if fs ~= nil and fs ~= 0 then
            child.props.flexShrink = 0
            if child.node then
                YGNodeStyleSetFlexShrink(child.node, 0)
            end
        end
    end
end

--- Override AddChild to prevent flex shrinking and invalidate sticky cache
---@param child Widget
---@return ScrollView self
function ScrollView:AddChild(child)
    self:InvalidateStickyCache_()
    self:EnforceNoShrink_(child)
    return Widget.AddChild(self, child)
end

--- Override RemoveChild to invalidate sticky cache
---@param child Widget
---@return ScrollView self
function ScrollView:RemoveChild(child)
    self:InvalidateStickyCache_()
    return Widget.RemoveChild(self, child)
end

--- Override InsertChild to prevent flex shrinking and invalidate sticky cache
---@param child Widget
---@param index number 1-based index
---@return ScrollView self
function ScrollView:InsertChild(child, index)
    self:InvalidateStickyCache_()
    self:EnforceNoShrink_(child)
    return Widget.InsertChild(self, child, index)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function ScrollView:Render(nvg)
    -- Draw background if set
    if self.props.backgroundColor then
        self:RenderBackground(nvg, self.props.backgroundColor, self.props.borderRadius)
    end
    -- Children are rendered via CustomRenderChildren
    -- Scrollbars are rendered after children in CustomRenderChildren
end

--- Custom child rendering with scroll offset and clipping
---@param nvg NVGContextWrapper
---@param renderFn function Recursive render function
function ScrollView:CustomRenderChildren(nvg, renderFn)
    local l = self:GetAbsoluteLayout()
    local state = self.state

    -- Save state and set up clipping
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    -- Translate for scroll offset
    nvgTranslate(nvg, -state.scrollX, -state.scrollY)

    -- Render children (with offset) using framework's render function
    -- Use GetRenderChildren() for z-index sort support
    local renderList = self:GetRenderChildren()
    for i = 1, #renderList do
        renderFn(renderList[i], nvg)
    end

    nvgRestore(nvg)

    -- Sticky header rendering: if a descendant has position="sticky" and its
    -- natural position has scrolled past the viewport top, re-render it pinned.
    -- Searches recursively (sticky child may be inside a content Panel wrapper).
    if self.props.scrollY and state.scrollY > 0 then
        local stickyChild, naturalY = self:FindStickyChild_()
        if stickyChild then
            local stickyOffset = stickyChild.props.stickyOffset or 0
            if state.scrollY > naturalY - stickyOffset then
                nvgSave(nvg)
                nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)
                -- After nvgRestore above, NVG has no scroll translate.
                -- Child's absolute layout places it at scrollViewAbsY + naturalY.
                -- We want it at scrollViewAbsY + stickyOffset.
                -- Also apply -scrollX so sticky child scrolls horizontally.
                nvgTranslate(nvg, -state.scrollX, stickyOffset - naturalY)
                renderFn(stickyChild, nvg)
                nvgRestore(nvg)
            end
        end
    end

    -- Draw scrollbars (after children, on top)
    -- Always show when interactive and content overflows, or when opacity > 0
    local shouldShowScrollbar = self.props.showScrollbar and (
        self.scrollbarOpacity_ > 0 or
        (self.props.scrollbarInteractive and (
            (self.props.scrollY and self.contentHeight_ > l.h) or
            (self.props.scrollX and self.contentWidth_ > l.w)
        ))
    )
    if shouldShowScrollbar then
        -- Ensure minimum opacity when interactive
        if self.props.scrollbarInteractive then
            self.scrollbarOpacity_ = math.max(0.5, self.scrollbarOpacity_)
        end
        self:RenderScrollbars(nvg)
    end
end

--- Render scrollbar indicators
function ScrollView:RenderScrollbars(nvg)
    local l = self:GetAbsoluteLayout()
    local state = self.state
    local interactive = self.props.scrollbarInteractive

    -- For hit testing, we need screen coordinates (accounting for parent scroll offsets).
    -- GetAbsoluteLayout() returns NanoVG-transform-relative coordinates (correct for drawing),
    -- but GetAbsoluteLayoutForHitTest() returns screen coordinates (correct for hit testing).
    -- The difference is the cumulative scroll offset from ancestor ScrollViews.
    local lht = self:GetAbsoluteLayoutForHitTest()
    local hitOffsetX = lht.x - l.x
    local hitOffsetY = lht.y - l.y

    -- Interactive scrollbars are wider for easier clicking
    local scrollbarWidth = interactive and 10 or 6
    local scrollbarMargin = 2
    local scrollbarRadius = scrollbarWidth / 2
    local alpha = math.floor(self.scrollbarOpacity_ * (interactive and 200 or 150))

    local scrollbarColor = { 128, 128, 128, alpha }
    local scrollbarHoverColor = { 100, 100, 100, alpha }
    local trackColor = { 200, 200, 200, math.floor(alpha * 0.3) }

    -- Clear cached bounds
    self.vScrollbarBounds_ = nil
    self.hScrollbarBounds_ = nil
    self.vTrackBounds_ = nil
    self.hTrackBounds_ = nil

    -- Vertical scrollbar
    if self.props.scrollY and self.contentHeight_ > l.h then
        local maxScrollY = self.contentHeight_ - l.h
        local viewRatio = l.h / self.contentHeight_
        local scrollRatio = maxScrollY > 0 and (state.scrollY / maxScrollY) or 0
        scrollRatio = math.max(0, math.min(1, scrollRatio))

        local trackX = l.x + l.w - scrollbarWidth - scrollbarMargin
        local trackY = l.y + scrollbarMargin
        local trackHeight = l.h - scrollbarMargin * 2

        local barHeight = math.max(30, trackHeight * viewRatio)
        local barY = trackY + (trackHeight - barHeight) * scrollRatio
        local barX = trackX

        -- Cache bounds for hit testing (in screen coordinates)
        self.vTrackBounds_ = { x = trackX + hitOffsetX, y = trackY + hitOffsetY, w = scrollbarWidth, h = trackHeight }
        self.vScrollbarBounds_ = { x = barX + hitOffsetX, y = barY + hitOffsetY, w = scrollbarWidth, h = barHeight }

        -- Draw track background (only when interactive)
        if interactive then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, trackX, trackY, scrollbarWidth, trackHeight, scrollbarRadius)
            nvgFillColor(nvg, nvgRGBA(trackColor[1], trackColor[2], trackColor[3], trackColor[4]))
            nvgFill(nvg)
        end

        -- Draw scrollbar thumb
        local color = self.isDraggingScrollbarV_ and scrollbarHoverColor or scrollbarColor
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, barX, barY, scrollbarWidth, barHeight, scrollbarRadius)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4]))
        nvgFill(nvg)
    end

    -- Horizontal scrollbar
    if self.props.scrollX and self.contentWidth_ > l.w then
        local maxScrollX = self.contentWidth_ - l.w
        local viewRatio = l.w / self.contentWidth_
        local scrollRatio = maxScrollX > 0 and (state.scrollX / maxScrollX) or 0
        scrollRatio = math.max(0, math.min(1, scrollRatio))

        local trackX = l.x + scrollbarMargin
        local trackY = l.y + l.h - scrollbarWidth - scrollbarMargin
        local trackWidth = l.w - scrollbarMargin * 2

        local barWidth = math.max(30, trackWidth * viewRatio)
        local barX = trackX + (trackWidth - barWidth) * scrollRatio
        local barY = trackY

        -- Cache bounds for hit testing (in screen coordinates)
        self.hTrackBounds_ = { x = trackX + hitOffsetX, y = trackY + hitOffsetY, w = trackWidth, h = scrollbarWidth }
        self.hScrollbarBounds_ = { x = barX + hitOffsetX, y = barY + hitOffsetY, w = barWidth, h = scrollbarWidth }

        -- Draw track background (only when interactive)
        if interactive then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, trackX, trackY, trackWidth, scrollbarWidth, scrollbarRadius)
            nvgFillColor(nvg, nvgRGBA(trackColor[1], trackColor[2], trackColor[3], trackColor[4]))
            nvgFill(nvg)
        end

        -- Draw scrollbar thumb
        local color = self.isDraggingScrollbarH_ and scrollbarHoverColor or scrollbarColor
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, barX, barY, barWidth, scrollbarWidth, scrollbarRadius)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4]))
        nvgFill(nvg)
    end
end

-- ============================================================================
-- Update
-- ============================================================================

function ScrollView:Update(dt)
    -- Update content size
    self:UpdateContentSize()

    local state = self.state
    local l = self:GetLayout()

    -- Apply velocity (momentum scrolling)
    -- Skip when dragging content or scrollbar
    local isDraggingAnything = state.isDragging or self.isDraggingScrollbarV_ or self.isDraggingScrollbarH_
    if not isDraggingAnything then
        local friction = 0.95
        state.velocityX = state.velocityX * friction
        state.velocityY = state.velocityY * friction

        if math.abs(state.velocityX) > 0.1 then
            self:ScrollBy(state.velocityX * dt * 60, 0)
        else
            state.velocityX = 0
        end

        if math.abs(state.velocityY) > 0.1 then
            self:ScrollBy(0, state.velocityY * dt * 60)
        else
            state.velocityY = 0
        end

        -- Bounce back if over-scrolled
        if self.props.bounces then
            local maxScrollX = math.max(0, self.contentWidth_ - l.w)
            local maxScrollY = math.max(0, self.contentHeight_ - l.h)

            if state.scrollX < 0 then
                state.scrollX = state.scrollX * 0.9
            elseif state.scrollX > maxScrollX then
                state.scrollX = maxScrollX + (state.scrollX - maxScrollX) * 0.9
            end

            if state.scrollY < 0 then
                state.scrollY = state.scrollY * 0.9
            elseif state.scrollY > maxScrollY then
                state.scrollY = maxScrollY + (state.scrollY - maxScrollY) * 0.9
            end
        end

        -- Scroll snap
        if self.isSnapping_ then
            -- Animate toward snap target
            local snapDone = true
            if self.snapTargetY_ then
                local diff = self.snapTargetY_ - state.scrollY
                if math.abs(diff) > 0.5 then
                    state.scrollY = state.scrollY + diff * 8 * dt
                    snapDone = false
                else
                    state.scrollY = self.snapTargetY_
                    self.snapTargetY_ = nil
                end
            end
            if self.snapTargetX_ then
                local diff = self.snapTargetX_ - state.scrollX
                if math.abs(diff) > 0.5 then
                    state.scrollX = state.scrollX + diff * 8 * dt
                    snapDone = false
                else
                    state.scrollX = self.snapTargetX_
                    self.snapTargetX_ = nil
                end
            end
            if snapDone then
                self.isSnapping_ = false
            end
            -- Trigger onScroll callback during snap animation
            if self.props.onScroll then
                self.props.onScroll(self, state.scrollX, state.scrollY)
            end
        elseif state.velocityX == 0 and state.velocityY == 0
               and self.snapAxis_ and not self.snapChecked_ then
            -- Detect snap point when velocity has fully stopped
            -- Only snap when scroll is within valid bounds (not during bounce-back)
            local maxScrollX2 = math.max(0, self.contentWidth_ - l.w)
            local maxScrollY2 = math.max(0, self.contentHeight_ - l.h)
            local inBounds = state.scrollX >= -0.5 and state.scrollX <= maxScrollX2 + 0.5
                         and state.scrollY >= -0.5 and state.scrollY <= maxScrollY2 + 0.5

            if inBounds then
                local target = self:FindSnapTarget_(self.snapAxis_, self.snapMode_, l)
                if target ~= nil then
                    if self.snapAxis_ == "y" then
                        self.snapTargetY_ = target
                    else
                        self.snapTargetX_ = target
                    end
                    self.isSnapping_ = true
                else
                    -- Already at snap point, skip until next user interaction
                    self.snapChecked_ = true
                end
            else
                self.snapChecked_ = true
            end
        end
    end

    -- Fade scrollbar
    if isDraggingAnything or self.isSnapping_ or math.abs(state.velocityX) > 0.1 or math.abs(state.velocityY) > 0.1 then
        self.scrollbarOpacity_ = 1
        self.scrollbarFadeTimer_ = 1
    else
        self.scrollbarFadeTimer_ = self.scrollbarFadeTimer_ - dt
        if self.scrollbarFadeTimer_ <= 0 then
            self.scrollbarOpacity_ = math.max(0, self.scrollbarOpacity_ - dt * 3)
        end
    end
end

-- ============================================================================
-- Content Size
-- ============================================================================

function ScrollView:UpdateContentSize()
    local maxWidth = 0
    local maxHeight = 0

    -- Recursively calculate content bounds
    local function calculateBounds(widget, offsetX, offsetY)
        local cl = widget:GetLayout()
        local x = offsetX + cl.x
        local y = offsetY + cl.y

        -- Update max bounds
        maxWidth = math.max(maxWidth, x + cl.w)
        maxHeight = math.max(maxHeight, y + cl.h)

        -- Stop recursion at nested ScrollViews (overflow="hidden").
        -- They clip and manage their own content independently;
        -- the parent only needs their external dimensions (w, h from GetLayout).
        if widget.props and widget.props.overflow == "hidden" then
            return
        end

        -- Recurse into children
        for _, child in ipairs(widget.children or {}) do
            calculateBounds(child, x, y)
        end
    end

    for _, child in ipairs(self.children) do
        calculateBounds(child, 0, 0)
    end

    self.contentWidth_ = maxWidth
    self.contentHeight_ = maxHeight

    -- Runtime warning: detect when ScrollView cannot scroll due to layout issues
    local l = self:GetLayout()
    if not self.scrollWarningShown_ then
        -- flex=N is a shorthand (flexGrow=N, flexShrink=N, flexBasis=0 in Yoga).
        -- Must check both props.flexGrow and props.flex.
        local hasFlexGrow = (self.props.flexGrow and self.props.flexGrow > 0)
                         or (self.props.flex and self.props.flex > 0)
        local flexVal = self.props.flexGrow or self.props.flex or 0

        -- Check 1: ScrollView has zero size despite having flexGrow
        -- This typically happens when a parent uses maxHeight instead of height.
        -- maxHeight creates a content-driven size; flexBasis=0 children contribute 0,
        -- so Yoga gives them 0 height.
        local zeroHeight = hasFlexGrow and self.props.scrollY and l.h <= 0
        local zeroWidth = hasFlexGrow and self.props.scrollX and l.w <= 0
        if zeroHeight or zeroWidth then
            print(string.format(
                "[ScrollView Warning] Zero %s (%.0f) with flex/flexGrow=%g. "
                .. "Parent may be using maxHeight/maxWidth instead of height/width. "
                .. "flexGrow needs a parent with definite size (height/width, not maxHeight/maxWidth).",
                zeroHeight and "height" or "width",
                zeroHeight and l.h or l.w,
                flexVal
            ))
            self.scrollWarningShown_ = true
        end

        -- Check 2: Content fits in container (no scroll needed) with flexGrow but no flexBasis=0
        if not self.scrollWarningShown_ then
            local cannotScrollY = self.props.scrollY and maxHeight > 0 and maxHeight <= l.h
            local cannotScrollX = self.props.scrollX and maxWidth > 0 and maxWidth <= l.w

            if cannotScrollY or cannotScrollX then
                -- flex=N already implies flexBasis=0, so only warn for flexGrow without flexBasis
                local hasFlexBasis0 = self.props.flexBasis == 0
                                   or (self.props.flex and self.props.flex > 0)

                if hasFlexGrow and not hasFlexBasis0 then
                    print(string.format(
                        "[ScrollView Warning] Cannot scroll: content (%.0f) fits in layout (%.0f). " ..
                        "You have flexGrow=%d but no flexBasis=0. Try adding: flexBasis = 0",
                        cannotScrollY and maxHeight or maxWidth,
                        cannotScrollY and l.h or l.w,
                        flexVal
                    ))
                    self.scrollWarningShown_ = true
                end
            end
        end
    end
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function ScrollView:OnWheel(dx, dy)
    -- Interrupt snap animation on new scroll input
    self:CancelSnap_()

    -- Cancel pressed child widget so wheel scroll doesn't trigger clicks
    UI.CancelPointer(0, PointerEvent.PointerTypes.Mouse)

    -- Adapt scroll amount for different platforms
    -- Web/WASM wheel delta is typically much larger than desktop
    local scrollAmount = 40
    if GetPlatform and GetPlatform() == "Web" then
        -- Web browsers report larger delta values, reduce sensitivity
        scrollAmount = 0.4
    end

    if self.props.scrollY then
        self:ScrollBy(0, -dy * scrollAmount)
    end
    if self.props.scrollX then
        self:ScrollBy(-dx * scrollAmount, 0)
    end

    self.scrollbarOpacity_ = 1
    self.scrollbarFadeTimer_ = 1
end

function ScrollView:OnPanStart(event)
    -- Only allow content dragging for touch input
    -- Desktop users should use mouse wheel or scrollbar
    if event.pointerType ~= "touch" then
        return false
    end

    -- Don't claim gesture if not scrollable in any direction
    if not self.props.scrollX and not self.props.scrollY then
        return false
    end

    -- Interrupt snap animation on new drag
    self:CancelSnap_()

    -- Cancel pressed child widget so scroll doesn't trigger clicks
    UI.CancelPointer(event.pointerId, event.pointerType)

    self.state.isDragging = true
    self.dragStartScrollX_ = self.state.scrollX
    self.dragStartScrollY_ = self.state.scrollY
    self.state.velocityX = 0
    self.state.velocityY = 0
    return true  -- We're handling this pan gesture
end

function ScrollView:OnPanMove(event)
    if not self.state.isDragging then return end

    local dx = self.props.scrollX and -event.totalDeltaX or 0
    local dy = self.props.scrollY and -event.totalDeltaY or 0

    self:SetScroll(
        self.dragStartScrollX_ + dx,
        self.dragStartScrollY_ + dy
    )

    -- Track velocity for momentum
    self.state.velocityX = -event.deltaX
    self.state.velocityY = -event.deltaY
end

function ScrollView:OnPanEnd(event)
    if not self.state.isDragging then return end
    self.state.isDragging = false
end

-- Helper: Check if point is inside bounds
function ScrollView:PointInBounds(x, y, bounds)
    if not bounds then return false end
    return x >= bounds.x and x <= bounds.x + bounds.w and
           y >= bounds.y and y <= bounds.y + bounds.h
end

-- Override HitTest to include scrollbar area
function ScrollView:HitTest(x, y)
    -- First check normal bounds
    local l = self:GetAbsoluteLayoutForHitTest()
    if l and x >= l.x and x <= l.x + l.w and y >= l.y and y <= l.y + l.h then
        return true
    end

    -- Also check scrollbar bounds (they might extend slightly outside)
    if self.props.scrollbarInteractive then
        if self:PointInBounds(x, y, self.vTrackBounds_) then
            return true
        end
        if self:PointInBounds(x, y, self.hTrackBounds_) then
            return true
        end
    end

    return false
end

-- Return priority hit areas (scrollbar) that should be checked before children
function ScrollView:GetPriorityHitAreas()
    if not self.props.scrollbarInteractive then
        return nil
    end

    local areas = {}

    -- Add vertical scrollbar track
    if self.vTrackBounds_ then
        table.insert(areas, self.vTrackBounds_)
    end

    -- Add horizontal scrollbar track
    if self.hTrackBounds_ then
        table.insert(areas, self.hTrackBounds_)
    end

    return #areas > 0 and areas or nil
end

-- Scrollbar interaction handlers
function ScrollView:OnPointerDown(event)
    Widget.OnPointerDown(self, event)

    if not self.props.scrollbarInteractive then return end

    -- Interrupt snap animation on scrollbar interaction
    self:CancelSnap_()

    local x, y = event.x, event.y

    -- Check vertical scrollbar thumb
    if self:PointInBounds(x, y, self.vScrollbarBounds_) then
        self.isDraggingScrollbarV_ = true
        self.scrollbarDragStartY_ = y
        self.scrollbarDragStartScrollY_ = self.state.scrollY
        -- Cache drag parameters for smooth dragging
        local l = self:GetAbsoluteLayout()
        local scrollbarMargin = 2
        local trackHeight = l.h - scrollbarMargin * 2
        local viewRatio = l.h / self.contentHeight_
        local thumbHeight = math.max(30, trackHeight * viewRatio)
        self.scrollbarDragTrackRangeV_ = trackHeight - thumbHeight
        self.scrollbarDragMaxScrollV_ = math.max(0, self.contentHeight_ - l.h)
        self.scrollbarOpacity_ = 1
        return true  -- Consume event
    end

    -- Check horizontal scrollbar thumb
    if self:PointInBounds(x, y, self.hScrollbarBounds_) then
        self.isDraggingScrollbarH_ = true
        self.scrollbarDragStartX_ = x
        self.scrollbarDragStartScrollX_ = self.state.scrollX
        -- Cache drag parameters for smooth dragging
        local l = self:GetAbsoluteLayout()
        local scrollbarMargin = 2
        local trackWidth = l.w - scrollbarMargin * 2
        local viewRatio = l.w / self.contentWidth_
        local thumbWidth = math.max(30, trackWidth * viewRatio)
        self.scrollbarDragTrackRangeH_ = trackWidth - thumbWidth
        self.scrollbarDragMaxScrollH_ = math.max(0, self.contentWidth_ - l.w)
        self.scrollbarOpacity_ = 1
        return true
    end

    -- Check vertical track (click to jump)
    if self:PointInBounds(x, y, self.vTrackBounds_) then
        local track = self.vTrackBounds_
        local thumb = self.vScrollbarBounds_
        local l = self:GetLayout()
        local maxScrollY = math.max(0, self.contentHeight_ - l.h)

        if thumb and maxScrollY > 0 then
            -- Calculate where user clicked relative to track
            local clickRatio = (y - track.y) / track.h
            -- Jump to that position (center the thumb on click point)
            local targetScrollY = clickRatio * maxScrollY
            self:SetScroll(self.state.scrollX, targetScrollY)
        end
        self.scrollbarOpacity_ = 1
        return true
    end

    -- Check horizontal track (click to jump)
    if self:PointInBounds(x, y, self.hTrackBounds_) then
        local track = self.hTrackBounds_
        local thumb = self.hScrollbarBounds_
        local l = self:GetLayout()
        local maxScrollX = math.max(0, self.contentWidth_ - l.w)

        if thumb and maxScrollX > 0 then
            local clickRatio = (x - track.x) / track.w
            local targetScrollX = clickRatio * maxScrollX
            self:SetScroll(targetScrollX, self.state.scrollY)
        end
        self.scrollbarOpacity_ = 1
        return true
    end
end

function ScrollView:OnPointerMove(event)
    if not self.props.scrollbarInteractive then return end

    local x, y = event.x, event.y

    -- Handle vertical scrollbar drag
    if self.isDraggingScrollbarV_ then
        local trackRange = self.scrollbarDragTrackRangeV_
        local maxScrollY = self.scrollbarDragMaxScrollV_

        if trackRange > 0 and maxScrollY > 0 then
            local deltaY = y - self.scrollbarDragStartY_
            local scrollDelta = (deltaY / trackRange) * maxScrollY
            local newScrollY = self.scrollbarDragStartScrollY_ + scrollDelta
            -- Clamp directly for scrollbar drag (no bounce)
            newScrollY = math.max(0, math.min(maxScrollY, newScrollY))
            -- Use SetScrollDirect to update state and trigger onScroll callback
            self:SetScrollDirect(self.state.scrollX, newScrollY)
        end
        return true
    end

    -- Handle horizontal scrollbar drag
    if self.isDraggingScrollbarH_ then
        local trackRange = self.scrollbarDragTrackRangeH_
        local maxScrollX = self.scrollbarDragMaxScrollH_

        if trackRange > 0 and maxScrollX > 0 then
            local deltaX = x - self.scrollbarDragStartX_
            local scrollDelta = (deltaX / trackRange) * maxScrollX
            local newScrollX = self.scrollbarDragStartScrollX_ + scrollDelta
            -- Clamp directly for scrollbar drag (no bounce)
            newScrollX = math.max(0, math.min(maxScrollX, newScrollX))
            -- Use SetScrollDirect to update state and trigger onScroll callback
            self:SetScrollDirect(newScrollX, self.state.scrollY)
        end
        return true
    end
end

function ScrollView:OnPointerUp(event)
    Widget.OnPointerUp(self, event)

    self.isDraggingScrollbarV_ = false
    self.isDraggingScrollbarH_ = false
end

-- ============================================================================
-- Scroll Snap
-- ============================================================================

--- Find the nearest snap target for the given axis
---@param axis string "x" or "y"
---@param mode string "mandatory" or "proximity"
---@param l table Layout of this ScrollView
---@return number|nil snapTarget scroll position to snap to, or nil
function ScrollView:FindSnapTarget_(axis, mode, l)
    local isY = axis == "y"
    local containerSize = isY and l.h or l.w
    local currentScroll = isY and self.state.scrollY or self.state.scrollX
    local maxScroll = math.max(0, (isY and self.contentHeight_ or self.contentWidth_) - containerSize)

    local bestTarget = nil
    local bestDist = math.huge

    for _, child in ipairs(self.children) do
        local align = child.props.scrollSnapAlign
        if align then
            local cl = child:GetLayout()
            local childPos = isY and cl.y or cl.x
            local childSize = isY and cl.h or cl.w

            local snapPoint
            if align == "start" then
                snapPoint = childPos
            elseif align == "center" then
                snapPoint = childPos + childSize / 2 - containerSize / 2
            elseif align == "end" then
                snapPoint = childPos + childSize - containerSize
            end

            if snapPoint then
                snapPoint = math.max(0, math.min(maxScroll, snapPoint))
                local dist = math.abs(snapPoint - currentScroll)
                if dist < bestDist then
                    bestDist = dist
                    bestTarget = snapPoint
                end
            end
        end
    end

    -- Proximity mode: only snap if close enough (< 40% of container)
    if bestTarget and mode == "proximity" then
        if bestDist > containerSize * 0.4 then
            return nil
        end
    end

    -- Don't snap if already at target
    if bestTarget and bestDist < 0.5 then
        return nil
    end

    return bestTarget
end

--- Cancel any active snap animation
function ScrollView:CancelSnap_()
    self.isSnapping_ = false
    self.snapTargetX_ = nil
    self.snapTargetY_ = nil
    self.snapChecked_ = false
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Scroll by delta
---@param dx number
---@param dy number
---@return ScrollView self
function ScrollView:ScrollBy(dx, dy)
    return self:SetScroll(self.state.scrollX + dx, self.state.scrollY + dy)
end

--- Set scroll position
---@param x number
---@param y number
---@return ScrollView self
function ScrollView:SetScroll(x, y)
    local l = self:GetLayout()
    local maxScrollX = math.max(0, self.contentWidth_ - l.w)
    local maxScrollY = math.max(0, self.contentHeight_ - l.h)

    local newX = x
    local newY = y

    -- Clamp or allow bounce
    if not self.props.bounces then
        newX = math.max(0, math.min(maxScrollX, newX))
        newY = math.max(0, math.min(maxScrollY, newY))
    else
        -- Allow some over-scroll with resistance
        local bounceLimit = 100
        if newX < 0 then
            newX = newX * 0.3
            newX = math.max(-bounceLimit, newX)
        elseif newX > maxScrollX then
            newX = maxScrollX + (newX - maxScrollX) * 0.3
            newX = math.min(maxScrollX + bounceLimit, newX)
        end

        if newY < 0 then
            newY = newY * 0.3
            newY = math.max(-bounceLimit, newY)
        elseif newY > maxScrollY then
            newY = maxScrollY + (newY - maxScrollY) * 0.3
            newY = math.min(maxScrollY + bounceLimit, newY)
        end
    end

    self.state.scrollX = newX
    self.state.scrollY = newY

    if self.props.onScroll then
        self.props.onScroll(self, newX, newY)
    end

    return self
end

--- Set scroll position directly (no bounce, no clamping)
--- Used internally by scrollbar drag which handles its own clamping
---@param x number
---@param y number
---@return ScrollView self
function ScrollView:SetScrollDirect(x, y)
    self.state.scrollX = x
    self.state.scrollY = y

    if self.props.onScroll then
        self.props.onScroll(self, x, y)
    end

    return self
end

--- Get scroll position
---@return number # scrollX
---@return number # scrollY
function ScrollView:GetScroll()
    return self.state.scrollX, self.state.scrollY
end

--- Scroll to top
---@return ScrollView self
function ScrollView:ScrollToTop()
    return self:SetScroll(self.state.scrollX, 0)
end

--- Scroll to bottom
---@return ScrollView self
function ScrollView:ScrollToBottom()
    local l = self:GetLayout()
    local maxScrollY = math.max(0, self.contentHeight_ - l.h)
    return self:SetScroll(self.state.scrollX, maxScrollY)
end

--- Get content size
---@return number # width
---@return number # height
function ScrollView:GetContentSize()
    return self.contentWidth_, self.contentHeight_
end

-- ============================================================================
-- Child Override
-- ============================================================================

-- Override GetAbsoluteLayout for children to account for scroll offset
-- Note: Children need to query parent for scroll offset in their render

-- ============================================================================
-- Sticky Support
-- ============================================================================

--- Find the first sticky descendant and its Y offset from the ScrollView.
--- Searches recursively so sticky children inside content Panels are found.
--- Result is cached after first search (cleared when children change).
---@return Widget|nil stickyChild, number naturalY (offset from ScrollView content top)
function ScrollView:FindStickyChild_()
    if self.stickySearchDone_ then
        return self.stickyChild_, self.stickyNaturalY_
    end
    self.stickySearchDone_ = true

    local function search(widget, yOffset)
        for _, child in ipairs(widget.children) do
            local childY = yOffset + YGNodeLayoutGetTop(child.node)
            if child.props.position == "sticky" then
                return child, childY
            end
            local found, foundY = search(child, childY)
            if found then return found, foundY end
        end
        return nil, 0
    end

    self.stickyChild_, self.stickyNaturalY_ = search(self, 0)
    return self.stickyChild_, self.stickyNaturalY_
end

--- Invalidate sticky child cache (call when children change)
function ScrollView:InvalidateStickyCache_()
    self.stickySearchDone_ = false
    self.stickyChild_ = nil
    self.stickyNaturalY_ = nil
end

-- ============================================================================
-- Stateful
-- ============================================================================

function ScrollView:IsStateful()
    return true
end

-- ============================================================================
-- Overflow Check Override
-- ============================================================================

--- Override CheckOverflow to skip warning for ScrollView itself
--- (overflow is expected and intentional for scrollable content)
--- but still check children recursively
function ScrollView:CheckOverflow(recursive)
    -- Skip overflow warning for ScrollView itself - content overflow is expected
    -- But still check children recursively
    if recursive then
        for _, child in ipairs(self.children) do
            if child.CheckOverflow then
                child:CheckOverflow(true)
            end
        end
    end
end

return ScrollView
