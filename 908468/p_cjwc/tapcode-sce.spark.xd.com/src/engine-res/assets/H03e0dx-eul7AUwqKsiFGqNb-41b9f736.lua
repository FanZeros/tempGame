-- ============================================================================
-- Label Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Text display widget
-- 
-- IMPORTANT: Yoga uses border-box model!
-- When setting explicit width, padding is INSIDE the width (like CSS box-sizing: border-box).
-- So width must = textWidth + paddingLeft + paddingRight
-- Reference: 3rd/yoga/website/docs/styling/width-height.mdx
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class LabelProps : WidgetProps
---@field text? string Text content
---@field fontSize? number Font size
---@field fontColor? RGBAColor|string RGBA color
---@field fontFamily? string Font name (base family, e.g. "sans")
---@field fontWeight? string "normal" | "bold" | "100"-"900"
---@field textAlign? string "left" | "center" | "right"
---@field verticalAlign? string "top" | "middle" | "bottom"
---@field maxLines? number Maximum lines (truncate with ...)
---@field pointerEvents? string "auto" | "none" (default: "none")
---@field color? RGBAColor|string Alias for fontColor
---@field lineHeight? number Line height multiplier (default: 1.4)
---@field letterSpacing? number Letter spacing in pixels
---@field textDecoration? string "none" | "underline" | "line-through"
---@field textTransform? string "none" | "uppercase" | "lowercase" | "capitalize"
---@field whiteSpace? string "nowrap" (default) | "normal" (auto-wrap)
---@field wordBreak? string "normal" | "break-word"
---@field textStroke? table Text outline { width: number, color: string|table(RGBA) }
---@field textShadow? table Text shadow { offsetX: number, offsetY: number, blur: number, color: string|table(RGBA) }
---@field minFontSize? number Lower bound for auto-fit font size (same units as fontSize)

---@class Label : Widget
---@overload fun(props?: LabelProps): Label
---@field props LabelProps
---@field new fun(self, props?: LabelProps): Label
local Label = Widget:Extend("Label")

-- Auto-fit only (pt, same units as fontSize). Box-local floor — separate from
-- bare-nvg CSS-logical min in Engine/i18n.lua (currently 7).
-- TODO: align both floors to the same CSS-logical visual-pixel scale.
local DEFAULT_AUTOFIT_MIN_FONT_SIZE = 8

-- ============================================================================
-- Helper: Calculate total padding
-- ============================================================================

---Calculate horizontal padding (left + right)
---Note: padding/paddingHorizontal/paddingVertical are already expanded to
---per-side props by Widget.expandPaddingShorthand at Init/SetStyle time.
---@param props table
---@return number paddingLeft, number paddingRight
local function getHorizontalPadding(props)
    return props.paddingLeft or 0, props.paddingRight or 0
end

---Calculate vertical padding (top + bottom)
---@param props table
---@return number paddingTop, number paddingBottom
local function getVerticalPadding(props)
    return props.paddingTop or 0, props.paddingBottom or 0
end

local FIT_RECT_EPSILON = 0.001

---Copy a cached measurement without sharing the mutable result table. The fit
---solver updates cache tables in place, so intrinsic and constrained results
---must never alias each other.
---@param source table
---@param target table|nil
---@return table
local function copyFitResult(source, target)
    if type(target) ~= "table" or target == source then
        target = {}
    else
        for key in pairs(target) do
            target[key] = nil
        end
    end
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

---Return Yoga-resolved padding so percentage padding and layout rounding use
---the same values as the final box geometry.
---@param widget Widget
---@param props table
---@return number left, number right, number top, number bottom
local function getResolvedPadding(widget, props)
    if widget.node and type(YGNodeLayoutGetPadding) == "function" then
        return YGNodeLayoutGetPadding(widget.node, YGEdgeLeft) or 0,
            YGNodeLayoutGetPadding(widget.node, YGEdgeRight) or 0,
            YGNodeLayoutGetPadding(widget.node, YGEdgeTop) or 0,
            YGNodeLayoutGetPadding(widget.node, YGEdgeBottom) or 0
    end

    local pl, pr = getHorizontalPadding(props)
    local pt, pb = getVerticalPadding(props)
    return tonumber(pl) or 0, tonumber(pr) or 0, tonumber(pt) or 0, tonumber(pb) or 0
end

---Calculate the text area after Yoga layout. Auto-fit additionally intersects
---the Label content box with its direct parent's content box, so a positioned
---Label fits the portion that can actually remain inside its parent.
---@param label Label
---@param layout table
---@param props table
---@return table rect
local function getEffectiveTextRect(label, layout, props)
    local pl, pr, pt, pb
    if UI.defaultAutoFitText then
        pl, pr, pt, pb = getResolvedPadding(label, props)
    else
        pl, pr = getHorizontalPadding(props)
        pt, pb = getVerticalPadding(props)
    end

    local ownX = layout.x + pl
    local ownY = layout.y + pt
    local ownW = math.max(0, layout.w - pl - pr)
    local ownH = math.max(0, layout.h - pt - pb)
    local rect = label.effectiveTextRect_
    if not rect then
        rect = {}
        label.effectiveTextRect_ = rect
    end
    rect.x = ownX
    rect.y = ownY
    rect.w = ownW
    rect.h = ownH
    rect.ownX = ownX
    rect.ownY = ownY
    rect.ownW = ownW
    rect.ownH = ownH
    rect.paddingLeft = pl
    rect.paddingRight = pr
    rect.paddingTop = pt
    rect.paddingBottom = pb
    rect.parentWidthConstrained = false
    rect.parentHeightConstrained = false
    rect.layoutHeightConstrained = false

    local parent = label.parent
    if not UI.defaultAutoFitText or not parent or not parent.GetAbsoluteLayout then
        return rect
    end

    -- ScrollView is an intentional overflow viewport, not a text-fit boundary.
    -- Its translate + scissor controls visibility; fitting remains entirely
    -- inside the Label's own content box and therefore stays stable while
    -- scrolling. Detect the public scrolling capability instead of importing
    -- or depending on the concrete ScrollView class.
    if type(parent.GetScroll) == "function" then
        return rect
    end

    local parentLayout = parent:GetAbsoluteLayout()
    local parentProps = parent.GetProps and parent:GetProps() or parent.props or {}
    local parentPL, parentPR, parentPT, parentPB = getResolvedPadding(parent, parentProps)
    local parentLeft = parentLayout.x + parentPL
    local parentTop = parentLayout.y + parentPT
    local parentRight = math.max(parentLeft, parentLayout.x + parentLayout.w - parentPR)
    local parentBottom = math.max(parentTop, parentLayout.y + parentLayout.h - parentPB)

    local right = math.min(ownX + ownW, parentRight)
    local bottom = math.min(ownY + ownH, parentBottom)
    rect.x = math.max(ownX, parentLeft)
    rect.y = math.max(ownY, parentTop)
    rect.w = math.max(0, right - rect.x)
    rect.h = math.max(0, bottom - rect.y)
    rect.parentWidthConstrained = rect.x > ownX + FIT_RECT_EPSILON
        or rect.w < ownW - FIT_RECT_EPSILON
    rect.parentHeightConstrained = rect.y > ownY + FIT_RECT_EPSILON
        or rect.h < ownH - FIT_RECT_EPSILON
    return rect
end

---Apply textTransform to text string (pure, no side effects)
---@param text string
---@param transform string|nil
---@return string
local function applyTextTransform(text, transform)
    if not transform or transform == "none" then return text end
    if transform == "uppercase" then return string.upper(text) end
    if transform == "lowercase" then return string.lower(text) end
    if transform == "capitalize" then
        return text:gsub("(%a)([%w_']*)", function(a, b) return string.upper(a) .. b end)
    end
    return text
end

--- Clear cached single-line widths used by autoWidth / wrap decisions.
---@param label Label
local function clearMeasuredTextWidths(label)
    label.measuredTextWidth_ = nil
    label.measuredSourceTextWidth_ = nil
end

--- Measure display-text width and, in translated mode, source-text width together.
--- Same write points as the historical measuredTextWidth_ cache; source width is
--- only needed for wrap parity under UI.defaultAutoFitText.
---@param label Label
---@param displayText string
---@param fontSize number
---@param fontFace string
---@param letterSpacing number|nil
---@return number displayWidth
local function measureAndCacheTextWidths(
        label, displayText, fontSize, fontFace, letterSpacing)
    local displayWidth = UI.MeasureTextWidth(
        displayText, fontSize, fontFace, letterSpacing)
    if not displayWidth or displayWidth <= 0 then
        clearMeasuredTextWidths(label)
        return 0
    end

    label.measuredTextWidth_ = displayWidth

    local sourceWidth = displayWidth
    if UI.defaultAutoFitText
        and type(i18n) == "table"
        and type(i18n.GetSourceTextForDisplay) == "function"
    then
        local sourceText = i18n.GetSourceTextForDisplay(displayText)
        if type(sourceText) == "string"
            and sourceText ~= ""
            and sourceText ~= displayText
        then
            local measuredSource = UI.MeasureTextWidth(
                sourceText, fontSize, fontFace, letterSpacing)
            if measuredSource and measuredSource > 0 then
                sourceWidth = measuredSource
            end
        end
    end
    label.measuredSourceTextWidth_ = sourceWidth
    return displayWidth
end

--- Compute single-line content min height (CSS min-height:auto equivalent).
--- Same formula as the default height calculation in Init.
---@param props table Label props (needs fontSize, lineHeight, padding)
---@return number Single-line content height including vertical padding
local function computeSingleLineMinHeight(props)
    local basePxSize = Theme.FontSize(props.fontSize)
    local lh = props.lineHeight or 1.4
    local pt, pb = getVerticalPadding(props)
    return math.ceil(basePxSize * lh) + pt + pb
end

---Resolve the numeric Yoga min-height owned by Label's automatic line-box
---protection. A definite user height caps the automatic minimum just like the
---specified-size suggestion caps CSS flexbox's automatic minimum size.
---@param label Label
---@param props table
---@return number
local function resolveAutoMinHeight(label, props)
    local naturalMinHeight = computeSingleLineMinHeight(props)
    if label.userSetHeight_ and type(props.height) == "number" then
        return math.min(naturalMinHeight, math.max(0, props.height))
    end
    return naturalMinHeight
end

---Synchronize the derived Yoga min-height without giving up automatic
---ownership. Only an explicit user minHeight disables this path.
---@param label Label
---@param props table
local function syncAutoMinHeight(label, props)
    if label.autoMinHeight_ then
        Widget.SetMinHeight(label, resolveAutoMinHeight(label, props))
    end
end

---Resolve the text-flow mode from current props and text. This must not be
---treated as constructor-only state: UIInspector changes whiteSpace through
---SetStyle, and text updates can add or remove an explicit newline at runtime.
---@param props table
---@param text string
---@return boolean
local function usesMultilineFlow(props, text)
    return props.whiteSpace == "normal"
        or (props.whiteSpace == nil and string.find(text, "\n", 1, true) ~= nil)
end

local function resetTextFlowCaches(label)
    label.lastMultilineWidth_ = nil
    label.lastMultilineFontSize_ = nil
    label.lastMultilineLineHeight_ = nil
    label.lastMultilineLetterSpacing_ = nil
    label.lastMultilineFontFace_ = nil
    label.lastMultilineText_ = nil
    label.lastMultilineHAlign_ = nil
    label.lastMultilineFontVersion_ = nil
    label.lastMultilineScale_ = nil
    label.lastMultilineContext_ = nil
    label.multilineMetrics_ = nil
    label.autoFitCache_ = nil
    label.autoHeightNaturalFitCache_ = nil
    label.autoHeightDesiredHeight_ = nil
end

---Synchronize the derived flow and intrinsic-sizing state after a runtime
---style/text update. Entering whiteSpace=normal follows the same rules as a
---Label constructed in multiline mode; leaving it restores intrinsic sizing
---when width/height were not explicitly provided by the caller.
---@param label Label
---@return boolean changed
local function refreshTextFlowMode(label)
    local props = label.props
    local text = label.displayText_ or props.text or ""
    local multiline = usesMultilineFlow(props, text)
    local changed = label.multiline_ ~= multiline
    label.multiline_ = multiline

    if changed then
        resetTextFlowCaches(label)
    end

    if multiline then
        if not label.userSetWidth_ and (changed or label.autoWidth_) then
            -- Drop the internal single-line measurement. A width-less
            -- multiline Label derives its wrapping width from the parent.
            Widget.SetWidthAuto(label)
            label.autoWidth_ = false
            clearMeasuredTextWidths(label)
        end
        if not label.userSetWidth_ and props.alignSelf == nil then
            Widget.SetStyle(label, { alignSelf = "stretch" })
            label.multilineAddedAlignSelf_ = true
        end
        if not label.userSetHeight_ then
            label.autoHeight_ = true
        end
    else
        if label.multilineAddedAlignSelf_ and props.alignSelf == "stretch" then
            -- Restore Yoga's implicit align-self value without retaining an
            -- implementation detail in the public props table.
            Widget.SetStyle(label, { alignSelf = "auto" })
            label.props.alignSelf = nil
        end
        label.multilineAddedAlignSelf_ = false

        if not label.userSetHeight_ and (changed or label.autoHeight_) then
            label.autoHeight_ = false
            Widget.SetHeight(label, computeSingleLineMinHeight(props))
        end
        if not label.userSetWidth_ and (changed or not label.autoWidth_) then
            label:SetWidthAuto()
        end
    end

    return changed
end

--- Adjust breakWidth and renderX to keep glyph visuals within parent clip.
--- Decorative fonts have strokes extending beyond advance width; even standard
--- fonts can have small negative left bearings. When the parent container clips
--- (e.g. ScrollView via nvgIntersectScissor), edge characters get visually clipped.
---
--- Strategy: measure glyph bounds, detect overhang beyond layout area, then
--- narrow breakWidth so text wraps in a tighter area and overhang stays within
--- the parent's clip region. When actual overhang is detected, an extra 1px
--- safety margin covers NanoVG's AA fringe (fringeWidth ~1px beyond path bounds).
---
--- One re-verification pass after narrowing catches new overhang from changed
--- line wrapping (different characters at line edges). Convergence is guaranteed:
--- glyph overhang is bounded (~2-3px per side), so each pass subtracts a small
--- bounded amount from an already-narrowed width.
---
---@param nvg NVGContextWrapper
---@param breakWidth number Available width for text wrapping
---@param contentX number Left edge of content area
---@param text string Text to measure
---@param boxHAlign number NanoVG horizontal alignment (NVG_ALIGN_LEFT/CENTER/RIGHT)
---@return number renderBreakWidth Adjusted break width
---@return number renderX Adjusted left edge for nvgTextBox
---@return table renderBounds Final measured bounds {x1,y1,x2,y2}
local function adjustForOverhang(nvg, breakWidth, contentX, text, boxHAlign)
    nvgTextAlign(nvg, boxHAlign + NVG_ALIGN_TOP)
    local bounds = nvgTextBoxBounds(
        nvg, 0, 0, breakWidth, text, nil, nil, false)

    -- Detect overhang: bounds[1] < 0 = left overhang, bounds[3] > breakWidth = right.
    -- Only add 1px AA fringe margin when actual overhang is detected, to avoid
    -- unnecessary narrowing for standard fonts with no overhang (bounds[1] ≈ 0).
    local leftOH, rightOH = 0, 0
    if bounds and bounds[1] and bounds[3] then
        leftOH = math.max(0, -bounds[1])
        rightOH = math.max(0, bounds[3] - breakWidth)
        if leftOH > 0 then leftOH = leftOH + 1 end
        if rightOH > 0 then rightOH = rightOH + 1 end
    end

    -- Narrow breakWidth so overhang stays within parent clip.
    -- Expanding Label's own scissor doesn't help: nvgIntersectScissor takes
    -- intersection with parent (e.g. ScrollView) — parent's clip wins.
    local renderBreakWidth = breakWidth
    local renderX = contentX
    if leftOH > 0 or rightOH > 0 then
        renderBreakWidth = math.max(1, breakWidth - leftOH - rightOH)
        renderX = contentX + leftOH
    end

    -- Re-verify: narrowing changes line wrapping, new line-start characters
    -- may have different overhang. Apply one correction pass.
    local renderBounds = (renderBreakWidth ~= breakWidth)
        and nvgTextBoxBounds(
            nvg, 0, 0, renderBreakWidth, text, nil, nil, false)
        or bounds
    if renderBounds and renderBreakWidth ~= breakWidth then
        local newLeftOH = math.max(0, -renderBounds[1])
        local newRightOH = math.max(0, renderBounds[3] - renderBreakWidth)
        if newLeftOH > 0 then newLeftOH = newLeftOH + 1 end
        if newRightOH > 0 then newRightOH = newRightOH + 1 end
        if newLeftOH > 0 or newRightOH > 0 then
            renderBreakWidth = math.max(1, renderBreakWidth - newLeftOH - newRightOH)
            renderX = renderX + newLeftOH
            renderBounds = nvgTextBoxBounds(
                nvg, 0, 0, renderBreakWidth, text, nil, nil, false)
        end
    end

    return renderBreakWidth, renderX, renderBounds
end

---Resolve multiline measurement only when an input that affects line breaking
---or glyph bounds changes. Position and box height are deliberately excluded:
---the cached X value is relative to contentX, while NanoVG wraps by width only.
---@param label Label
---@param nvg NVGContextWrapper
---@param breakWidth number
---@param contentX number
---@param text string
---@param boxHAlign number
---@param fontSize number
---@param lineHeight number
---@param letterSpacing number
---@param fontFace string
---@return number renderBreakWidth
---@return number renderX
---@return number|nil textHeight
local function resolveMultilineMetrics(label, nvg, breakWidth, contentX, text,
        boxHAlign, fontSize, lineHeight, letterSpacing, fontFace)
    local metrics = label.multilineMetrics_
    local fontVersion = UI.GetFontVersion()
    local scale = Theme.GetScale()
    local metricsDirty = metrics == nil
        or label.lastMultilineWidth_ ~= breakWidth
        or label.lastMultilineFontSize_ ~= fontSize
        or label.lastMultilineLineHeight_ ~= lineHeight
        or label.lastMultilineLetterSpacing_ ~= letterSpacing
        or label.lastMultilineFontFace_ ~= fontFace
        or label.lastMultilineText_ ~= text
        or label.lastMultilineHAlign_ ~= boxHAlign
        or label.lastMultilineFontVersion_ ~= fontVersion
        or label.lastMultilineScale_ ~= scale
        or label.lastMultilineContext_ ~= nvg

    -- adjustForOverhang sets this on a cache miss. Set it explicitly on a hit
    -- as well because NanoVG alignment state persists across sibling widgets.
    nvgTextAlign(nvg, boxHAlign + NVG_ALIGN_TOP)

    if metricsDirty then
        local renderBreakWidth, renderX, bounds
            = adjustForOverhang(nvg, breakWidth, contentX, text, boxHAlign)
        metrics = metrics or {}
        metrics.breakWidth = renderBreakWidth
        metrics.xOffset = renderX - contentX
        metrics.textHeight = bounds and bounds[2] and bounds[4]
            and (bounds[4] - bounds[2]) or nil
        label.multilineMetrics_ = metrics

        label.lastMultilineWidth_ = breakWidth
        label.lastMultilineFontSize_ = fontSize
        label.lastMultilineLineHeight_ = lineHeight
        label.lastMultilineLetterSpacing_ = letterSpacing
        label.lastMultilineFontFace_ = fontFace
        label.lastMultilineText_ = text
        label.lastMultilineHAlign_ = boxHAlign
        label.lastMultilineFontVersion_ = fontVersion
        label.lastMultilineScale_ = scale
        label.lastMultilineContext_ = nvg
    end

    return metrics.breakWidth, contentX + metrics.xOffset, metrics.textHeight
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props LabelProps?
function Label:Init(props)
    props = props or {}

    -- Label defaults to not intercepting pointer events (like iOS UILabel)
    -- This prevents Label from stealing hover/click from parent Button
    -- Set pointerEvents = "auto" explicitly if you need clickable text
    props.pointerEvents = props.pointerEvents or "none"

    -- Apply typography defaults
    local typography = Theme.Typography("body")
    props.fontSize = props.fontSize or typography.fontSize
    props.fontFamily = props.fontFamily or Theme.FontFamily()
    props.fontColor = props.fontColor or props.color or Theme.Color("text")
    props.textAlign = props.textAlign or "left"
    props.verticalAlign = props.verticalAlign or "middle"

    local basePxSize = Theme.FontSize(props.fontSize)

    -- Expand padding shorthand before reading padding values
    -- (Widget.Init calls this again, but it's idempotent)
    Widget.ExpandPaddingShorthand(props)

    -- Calculate padding
    local pl, pr = getHorizontalPadding(props)
    local pt, pb = getVerticalPadding(props)

    -- Track user intent before applying defaults and intrinsic measurements.
    -- props.width/height may later contain internal measured values, so they
    -- cannot recover whether the caller explicitly fixed the box.
    local userSetWidth = props.width ~= nil
    local userSetHeight = props.height ~= nil
    self.userSetWidth_ = userSetWidth
    self.userSetHeight_ = userSetHeight
    self.multilineAddedAlignSelf_ = false

    -- Set default height based on font size (with line height) + vertical padding
    -- IMPORTANT: Yoga uses border-box, so height must include padding
    if not props.height then
        local lh = props.lineHeight or 1.4
        props.height = math.ceil(basePxSize * lh) + pt + pb
    end

    -- Labels adapt to available space (text is clipped if shrunk below text width)
    props.flexShrink = props.flexShrink or 1

    -- CSS min-height:auto protection: prevent a Label from collapsing below
    -- its line box. A definite user height caps this derived minimum; an
    -- explicit user minHeight remains a strict constraint.
    if props.minHeight == nil then
        props.minHeight = resolveAutoMinHeight(self, props)
        self.autoMinHeight_ = true
    else
        self.autoMinHeight_ = false
    end

    -- Track whether width was explicitly set by user or auto-calculated from text.
    -- SetText() only recalculates width when autoWidth is true.
    self.autoWidth_ = not userSetWidth

    -- Multiline mode: width from parent, height from content
    -- Auto-detect: text containing \n enables multiline when whiteSpace not explicitly set
    self.multiline_ = usesMultilineFlow(props, props.text or "")
    if self.multiline_ then
        if self.autoWidth_ then
            -- No explicit width → stretch to fill parent (like CSS block element)
            if props.alignSelf == nil then
                props.alignSelf = "stretch"
                self.multilineAddedAlignSelf_ = true
            end
            self.autoWidth_ = false  -- Don't measure single-line text width
        end
        -- Mark for auto-height (Render will calculate via nvgTextBoxBounds)
        if not userSetHeight then
            self.autoHeight_ = true
            -- Keep the initial single-line height from above; Render will correct it
        end
    else
        self.autoHeight_ = false
    end

    -- Cache display text (with textTransform applied) to avoid per-frame recomputation
    if props.text then
        self.displayText_ = applyTextTransform(props.text, props.textTransform)
    end

    -- Record font version at measurement time for DWP reload detection
    self.fontVersion_ = UI.GetFontVersion()

    -- Set initial width using precise measurement + horizontal padding
    -- IMPORTANT: Yoga uses border-box, so width must include padding
    if self.autoWidth_ and self.displayText_ then
        local nvgFontSize = Theme.FontSize(props.fontSize)
        local fontFace = Theme.FontFace(props.fontFamily, props.fontWeight)
        -- Cache display (+ source under translated mode) widths for Render
        -- auto-wrap. Comparing against cached values avoids false positives
        -- from floating-point differences between Init and Render measurement.
        local measuredWidth = measureAndCacheTextWidths(
            self, self.displayText_, nvgFontSize, fontFace, props.letterSpacing)
        if measuredWidth > 0 then
            -- width = content (text) + padding (border-box model)
            props.width = measuredWidth + pl + pr
            -- Cap auto-width to parent's available width (like CSS behavior).
            -- Without this, text with explicit pixel width bypasses Yoga's parent constraint,
            -- causing overflow when alignItems="center" (parent doesn't limit child width).
            -- Only when measuredWidth>0 to avoid affecting emoji labels (measurement returns 0).
            if not props.maxWidth then
                props.maxWidth = "100%"
            end
        end
    end

    -- Parse nested color fields before Widget.Init
    -- (NormalizeColorProps only auto-parses top-level *Color props, not nested tables)
    if props.textStroke and type(props.textStroke.color) == "string" then
        props.textStroke.color = Style.ParseColor(props.textStroke.color)
    end
    if props.textShadow and type(props.textShadow.color) == "string" then
        props.textShadow.color = Style.ParseColor(props.textShadow.color)
    end

    Widget.Init(self, props)

    -- Cache the effective props used by Render and all derived measurements.
    -- Render refreshes this with the latest parent overrides every frame.
    self.props_override = self.props

    -- Set baseline value for Yoga alignItems="baseline" alignment
    -- Baseline = paddingTop + text ascender (distance from node top to text baseline)
    local nvgFontSize = Theme.FontSize(props.fontSize)
    local fontFace = Theme.FontFace(props.fontFamily, props.fontWeight)
    local ascender = UI.MeasureTextBaseline(nvgFontSize, fontFace)
    YGNodeSetBaselineValue(self.node, pt + ascender)
end

--- Return the effective props cached by Render.
--- Before the first Render, fall back to the Label's own props.
---@return LabelProps
function Label:GetProps()
    return self.props_override or self.props
end

-- ============================================================================
-- Text Effects Helper
-- ============================================================================

-- 8-direction offsets for text stroke (N, NE, E, SE, S, SW, W, NW)
local STROKE_OFFSETS = {
    { 0, -1}, { 1, -1}, { 1,  0}, { 1,  1},
    { 0,  1}, {-1,  1}, {-1,  0}, {-1, -1},
}

--- Draw text at (x+dx, y+dy) using the appropriate NanoVG call.
---@param nvg NVGContextWrapper
---@param x number Base X
---@param y number Base Y
---@param dx number X offset
---@param dy number Y offset
---@param text string Text to draw
---@param boxWidth number|nil If non-nil, use nvgTextBox with this width; otherwise nvgText
local function drawTextAt(nvg, x, y, dx, dy, text, boxWidth)
    if boxWidth then
        nvgTextBox(nvg, x + dx, y + dy, boxWidth, text, nil, false)
    elseif UI.defaultAutoFitText then
        nvgText(nvg, x + dx, y + dy, text, nil, false)
    else
        nvgText(nvg, x + dx, y + dy, text, nil)
    end
end

--- Draw text with optional shadow and stroke effects (no per-frame closure).
---@param nvg NVGContextWrapper
---@param props table Label props (textShadow, textStroke)
---@param fillColor table RGBA fill color
---@param x number Base X position
---@param y number Base Y position
---@param text string Text to draw
---@param boxWidth number|nil If non-nil, use nvgTextBox; otherwise nvgText
local function drawTextWithEffects(nvg, props, fillColor, x, y, text, boxWidth)
    local shadow = props.textShadow
    local stroke = props.textStroke

    -- Layer 1: Shadow (behind everything)
    if shadow then
        local sc = shadow.color or {0, 0, 0, 128}
        nvgFontBlur(nvg, shadow.blur or 0)
        nvgFillColor(nvg, nvgRGBA(sc[1], sc[2], sc[3], sc[4] or 255))
        drawTextAt(nvg, x, y, shadow.offsetX or 0, shadow.offsetY or 0, text, boxWidth)
        nvgFontBlur(nvg, 0)
    end

    -- Layer 2: Stroke (8-direction offset)
    if stroke and stroke.width and stroke.width > 0 then
        local sc = stroke.color or {0, 0, 0, 255}
        nvgFillColor(nvg, nvgRGBA(sc[1], sc[2], sc[3], sc[4] or 255))
        local w = stroke.width
        for i = 1, 8 do
            local off = STROKE_OFFSETS[i]
            drawTextAt(nvg, x, y, off[1] * w, off[2] * w, text, boxWidth)
        end
    end

    -- Layer 3: Fill text (on top)
    nvgFillColor(nvg, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 255))
    drawTextAt(nvg, x, y, 0, 0, text, boxWidth)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Label:Render(nvg)
    local l = self:GetAbsoluteLayout()

    -- Refresh the effective props once per frame. Non-render measurement paths use
    -- the same cached table so their layout matches what is actually drawn.
    local previousProps = self:GetProps()
    self.props_override = Widget.GetParentOverride(self, self.props)
    local props = self:GetProps()
    if previousProps.fontSize ~= props.fontSize then
        self:RefreshFontLayout(props)
    end

    -- Render background if set (shadow + color + image + border)
    -- Yoga returns border-box dimensions, so background covers the full area including padding
    if props.backgroundColor or props.backgroundImage or props.borderColor then
        self:RenderFullBackground(nvg)
    end

    local text = self.displayText_ or props.text or ""
    if text == "" then
        return
    end

    -- DWP font reload: re-measure cached text dimensions when font version changes
    local curFontVer = UI.GetFontVersion()
    if self.fontVersion_ ~= curFontVer then
        self.fontVersion_ = curFontVer
        local nvgFS = Theme.FontSize(props.fontSize)
        local ff = Theme.FontFace(props.fontFamily, props.fontWeight)
        -- Re-measure width (same logic as SetText), including source width.
        if self.autoWidth_ and self.displayText_ then
            local prevDisplayWidth = self.measuredTextWidth_
            local textWidth = measureAndCacheTextWidths(
                self, self.displayText_, nvgFS, ff, props.letterSpacing)
            if textWidth > 0 and textWidth ~= prevDisplayWidth then
                local pl, pr = getHorizontalPadding(props)
                Widget.SetWidth(self, textWidth + pl + pr)
            end
        else
            clearMeasuredTextWidths(self)
        end
        -- Re-measure min height
        syncAutoMinHeight(self, props)
        -- Re-measure baseline
        local ascender = UI.MeasureTextBaseline(nvgFS, ff)
        local pt = props.paddingTop or 0
        YGNodeSetBaselineValue(self.node, pt + ascender)
        -- Clear multiline cache to trigger height recalc
        if self.multiline_ or self.autoHeight_ then
            self.lastMultilineWidth_ = nil
        end
    end

    -- Auto-fit uses the visible intersection with the direct parent. The same
    -- rectangle drives measurement, alignment, drawing and scissoring.
    local textRect = getEffectiveTextRect(self, l, props)
    local contentX = textRect.x
    local contentY = textRect.y
    local contentW = textRect.w
    local contentH = textRect.h
    local clipY = UI.defaultAutoFitText and contentY or l.y
    local clipH = UI.defaultAutoFitText and contentH or l.h
    if UI.defaultAutoFitText then
        self.autoFitRect_ = textRect
    else
        self.autoFitRect_ = nil
    end

    -- Multiline when whiteSpace=normal or text contains explicit newlines.
    -- Overflow auto-wrap is decided separately below using source-width policy
    -- under translated autofit (not a blanket single-line shrink).
    -- Resolve from effective render props as well as the synchronized base
    -- state, so parent overrides of whiteSpace take effect immediately.
    local useMultiline = usesMultilineFlow(props, text)
    local useAutoWrap = false
    local breakWidth = contentW

    -- Overflow auto-wrap (CSS-like): when the laid-out width is tighter than the
    -- intrinsic single-line measurement, draw via nvgTextBox instead.
    -- Translated mode: only keep auto-wrap when the *source* text would also
    -- overflow this same box (same predicate as source-language auto-wrap).
    -- If source stays on one line, keep single-line fit (min font floor below).
    if not useMultiline and self.autoWidth_ and self.measuredTextWidth_ and contentW > 0 then
        local wrapTolerance = math.ceil(0.5 / (Theme.GetScale() or 1)) + 0.5
        local translatedWouldWrap = contentW < self.measuredTextWidth_ - wrapTolerance
        if not UI.defaultAutoFitText then
            useAutoWrap = translatedWouldWrap
        elseif translatedWouldWrap then
            -- Source width was measured with display width (Init/SetText/font
            -- reload). Fall back to display width when source is unknown/same.
            local sourceWidth = self.measuredSourceTextWidth_
                or self.measuredTextWidth_
            useAutoWrap = contentW < sourceWidth - wrapTolerance
        end
    end

    -- A zero-sized intersection means no part of the text belongs inside the
    -- parent. Do not collapse the cache to minFontSize or draw stale text.
    local autoHeightWithoutMax = useMultiline and self.autoHeight_
        and props.maxHeight == nil
    -- maxHeight participates in the natural-height/fitted-height two-pass only
    -- when fitting is enabled. Preserve the original Label behavior otherwise.
    local autoWrapAutoHeight = UI.defaultAutoFitText
        and useAutoWrap and not self.userSetHeight_
    local managedAutoHeight = autoHeightWithoutMax
        or (UI.defaultAutoFitText and useMultiline and self.autoHeight_)
        or autoWrapAutoHeight
    -- Keep the intrinsic height requested on the previous frame separate from
    -- Yoga's possibly-shrunk layout height. Otherwise a fixed parent can cause
    -- an auto-height Label to alternate between the base and fitted font sizes.
    local layoutShrankAutoHeight = managedAutoHeight
        and self.autoHeightDesiredHeight_ ~= nil
        and self.autoHeightDesiredHeight_ > l.h + 1
    local effectiveParentHeightConstrained = textRect.parentHeightConstrained
        or layoutShrankAutoHeight
    textRect.layoutHeightConstrained = layoutShrankAutoHeight == true
    local canGrowAutoHeight = managedAutoHeight
        and not effectiveParentHeightConstrained
    if UI.defaultAutoFitText and (contentW <= FIT_RECT_EPSILON
            or (contentH <= FIT_RECT_EPSILON and not canGrowAutoHeight)) then
        self.autoFitCache_ = nil
        return
    end

    -- Calculate position based on alignment within content area
    local x, y
    local hAlign, vAlign

    -- Horizontal align
    if props.textAlign == "center" then
        x = contentX + contentW / 2
        hAlign = NVG_ALIGN_CENTER_VISUAL
    elseif props.textAlign == "right" then
        x = contentX + contentW
        hAlign = NVG_ALIGN_RIGHT
    else
        x = contentX
        hAlign = NVG_ALIGN_LEFT
    end

    local fontFace = Theme.FontFace(props.fontFamily, props.fontWeight)
    local baseFontSize = Theme.FontSize(props.fontSize)
    local renderLineHeight = props.lineHeight or 1.0
    local renderLetterSpacing = props.letterSpacing or 0
    local renderFontSize = baseFontSize

    -- Fit only at render time. Yoga dimensions and the configured fontSize stay
    -- unchanged, so enabling the feature cannot recursively resize the layout.
    local fitResult
    local naturalFitResult
    if UI.defaultAutoFitText then
        local minFontSize = props.minFontSize
            and Theme.FontSize(props.minFontSize)
            or Theme.FontSize(DEFAULT_AUTOFIT_MIN_FONT_SIZE)
        -- Auto-wrap under autofit is still multi-line drawing; fit height against
        -- the text box, not a single-line width squeeze.
        local fitMultiline = useMultiline or useAutoWrap
        local fitOptions = {
            fontSize = baseFontSize,
            fontFace = fontFace,
            letterSpacing = renderLetterSpacing,
            lineHeight = renderLineHeight,
            width = math.max(0, contentW),
            multiline = fitMultiline,
            minFontSize = minFontSize,
        }

        -- Auto-height keeps an unconstrained intrinsic measurement even when
        -- the actual glyphs must fit a fixed parent height. The intrinsic value
        -- remains Yoga's requested height, while renderFontSize is free to fit.
        if managedAutoHeight then
            fitOptions.cache = self.autoHeightNaturalFitCache_
            naturalFitResult = UI.MeasureTextFit(text, fitOptions)
            self.autoHeightNaturalFitCache_ = naturalFitResult
            local naturalTextH = naturalFitResult.height or 0
            self.autoHeightDesiredHeight_ = math.ceil(naturalTextH)
                + textRect.paddingTop + textRect.paddingBottom
        end

        local fitHeight = contentH
        -- An unconstrained auto-height label derives its height from the wrapped
        -- text below. Yoga applies maxHeight and parent/flex limits to that natural
        -- request; a later frame then fits into the allocation.
        if canGrowAutoHeight then
            fitHeight = nil
        end
        if canGrowAutoHeight and naturalFitResult then
            fitResult = copyFitResult(naturalFitResult, self.autoFitCache_)
        else
            fitOptions.height = fitHeight and math.max(0, fitHeight) or nil
            fitOptions.cache = self.autoFitCache_
            fitResult = UI.MeasureTextFit(text, fitOptions)
        end
        self.autoFitCache_ = fitResult
        renderFontSize = fitResult.fontSize or baseFontSize
    end

    -- Set the effective font after fitting. Always reset line height and letter
    -- spacing because NanoVG state persists across sibling widgets.
    nvgFontFace(nvg, fontFace)
    nvgFontSize(nvg, renderFontSize)
    nvgTextLineHeight(nvg, renderLineHeight)
    nvgTextLetterSpacing(nvg, renderLetterSpacing)

    local color = props.fontColor
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))

    if useMultiline then
        -- nvgTextBox only recognizes NVG_ALIGN_LEFT/CENTER/RIGHT in its internal mask.
        -- NVG_ALIGN_CENTER_VISUAL (bit 7) is not included, causing text to not render.
        -- Map it to standard NVG_ALIGN_CENTER for multiline.
        local boxHAlign = hAlign
        if hAlign == NVG_ALIGN_CENTER_VISUAL then
            boxHAlign = NVG_ALIGN_CENTER
        end

        -- breakWidth safety: ensure at least 1px to prevent nvgTextBox rendering nothing
        breakWidth = math.max(1, contentW)

        -- Detect glyph overhang and adjust breakWidth/renderX to keep text
        -- within parent clip (see adjustForOverhang doc comment for details)
        local renderBreakWidth, renderX, measuredTextH
            = resolveMultilineMetrics(
                self, nvg, breakWidth, contentX, text, boxHAlign,
                renderFontSize, renderLineHeight, renderLetterSpacing, fontFace
            )
        local textH = measuredTextH or contentH

        -- Auto-height: recalculate when width changes (like RichText pattern)
        if self.autoHeight_ and contentW > 0 then
            if textH > 0 then
                local mpt, mpb = getVerticalPadding(props)
                if UI.defaultAutoFitText then
                    mpt, mpb = textRect.paddingTop, textRect.paddingBottom
                end
                local intrinsicTextH = naturalFitResult
                    and (naturalFitResult.height or textH) or textH
                local newHeight = math.ceil(intrinsicTextH) + mpt + mpb
                self.autoHeightDesiredHeight_ = newHeight
                if math.abs(newHeight - (self.props.height or l.h)) > 1 then
                    Widget.SetHeight(self, newHeight)
                end
            end
        end

        -- Vertical align
        -- When autoHeight_ is true, use measured textH instead of stale Yoga contentH.
        -- Yoga height updates one frame late, so contentH may lag behind actual text height
        -- (e.g., during typewriter effects when line count changes mid-frame).
        local alignH = self.autoHeight_ and not effectiveParentHeightConstrained
            and textH or contentH
        if props.verticalAlign == "top" then
            y = contentY
        elseif props.verticalAlign == "bottom" then
            y = contentY + alignH - textH
        else
            y = contentY + (alignH - textH) / 2
        end

        -- Draw multiline text
        -- IMPORTANT: nvgTextBox x is always the LEFT edge of the text box.
        -- Alignment (center/right) is handled internally by NanoVG within breakWidth.
        -- This differs from nvgText where x is the alignment anchor point.
        local needClip = not self.autoWidth_ or UI.defaultAutoFitText
        if needClip then
            nvgSave(nvg)
            nvgIntersectScissor(nvg, contentX, clipY, contentW, clipH)
        end
        if props.textShadow or props.textStroke then
            drawTextWithEffects(nvg, props, color, renderX, y, text, renderBreakWidth)
        else
            nvgTextBox(nvg, renderX, y, renderBreakWidth, text, nil, false)
        end
        if needClip then
            nvgRestore(nvg)
        end
    else
        -- Single-line rendering (default: whiteSpace = "nowrap")

        -- Auto-wrap: when maxWidth constrains layout width significantly below text measurement,
        -- switch to multiline rendering (like CSS white-space: normal).
        if useAutoWrap then
            local boxHAlign = hAlign
            if hAlign == NVG_ALIGN_CENTER_VISUAL then
                boxHAlign = NVG_ALIGN_CENTER
            end

            local wrapWidth = math.max(1, contentW)
            local renderWrapWidth, renderWrapX, measuredTextH
                = resolveMultilineMetrics(
                    self, nvg, wrapWidth, contentX, text, boxHAlign,
                    renderFontSize, renderLineHeight, renderLetterSpacing, fontFace
                )
            local textH = measuredTextH or contentH

            -- Auto-adjust height for wrapped text (same pattern as multiline autoHeight_)
            if textH > 0 then
                local mpt, mpb = getVerticalPadding(props)
                local newHeight = autoWrapAutoHeight
                    and self.autoHeightDesiredHeight_
                    or (math.ceil(textH) + mpt + mpb)
                if math.abs(newHeight - (self.props.height or l.h)) > 1 then
                    Widget.SetHeight(self, newHeight)
                end
            end

            -- Vertical align within content area (use textH when auto-height)
            local wrapAlignH = self.autoHeight_ and textH or contentH
            if props.verticalAlign == "top" then
                y = contentY
            elseif props.verticalAlign == "bottom" then
                y = contentY + wrapAlignH - textH
            else
                y = contentY + (wrapAlignH - textH) / 2
            end

            if props.textShadow or props.textStroke then
                drawTextWithEffects(nvg, props, color, renderWrapX, y, text, renderWrapWidth)
            else
                nvgTextBox(nvg, renderWrapX, y, renderWrapWidth, text, nil, false)
            end
            return
        end

        -- Normal single-line path (text fits in layout width)
        -- Vertical align
        if props.verticalAlign == "top" then
            y = contentY
            vAlign = NVG_ALIGN_TOP
        elseif props.verticalAlign == "bottom" then
            y = contentY + contentH
            vAlign = NVG_ALIGN_BOTTOM
        else
            y = contentY + contentH / 2
            vAlign = NVG_ALIGN_MIDDLE
        end

        nvgTextAlign(nvg, hAlign + vAlign)

        -- Draw text: only clip when user set an explicit width (autoWidth_ = false).
        -- Auto-width labels are sized from text measurement; clipping them
        -- causes regressions (emoji measurement inaccuracy, sub-pixel rounding).
        -- Keep the historical no-clip behavior for auto-width labels whose
        -- fallback glyph has no measurable bounds (for example some emoji).
        local needClip = not self.autoWidth_
            or (UI.defaultAutoFitText and fitResult and fitResult.width > 0)
        if needClip then
            nvgSave(nvg)
            nvgIntersectScissor(nvg, contentX, clipY, contentW, clipH)
        end
        if props.textShadow or props.textStroke then
            drawTextWithEffects(nvg, props, color, x, y, text, nil)
        else
            if UI.defaultAutoFitText then
                nvgText(nvg, x, y, text, nil, false)
            else
                nvgText(nvg, x, y, text, nil)
            end
        end

        -- Draw text decoration (underline / line-through)
        local decoration = props.textDecoration
        if decoration and decoration ~= "none" then
            -- Get text metrics for line positioning
            local asc, desc, lineH = nvgTextMetrics(nvg)
            local textW2 = nvgTextBounds(
                nvg, x, y, text, nil, nil, false)

            -- Calculate text start X based on alignment
            local lineStartX
            if props.textAlign == "center" then
                lineStartX = x - textW2 / 2
            elseif props.textAlign == "right" then
                lineStartX = x - textW2
            else
                lineStartX = x
            end

            -- Draw the line
            nvgBeginPath(nvg)
            nvgStrokeWidth(nvg, 1)
            nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))

            if decoration == "underline" then
                -- Underline: below the baseline
                local lineY = y + desc * 0.5 + 1
                if vAlign == NVG_ALIGN_MIDDLE then
                    lineY = y + asc * 0.3 + 1
                elseif vAlign == NVG_ALIGN_TOP then
                    lineY = y + asc + 2
                end
                nvgMoveTo(nvg, lineStartX, lineY)
                nvgLineTo(nvg, lineStartX + textW2, lineY)
            elseif decoration == "line-through" then
                -- Strikethrough: middle of text
                local lineY = y
                if vAlign == NVG_ALIGN_MIDDLE then
                    lineY = y - asc * 0.15
                elseif vAlign == NVG_ALIGN_TOP then
                    lineY = y + asc * 0.4
                elseif vAlign == NVG_ALIGN_BOTTOM then
                    lineY = y - asc * 0.4
                end
                nvgMoveTo(nvg, lineStartX, lineY)
                nvgLineTo(nvg, lineStartX + textW2, lineY)
            end

            nvgStroke(nvg)
        end

        if needClip then
            nvgRestore(nvg)
        end
    end
end

-- ============================================================================
-- SetStyle Override
-- ============================================================================

--- Override SetStyle to update derived state when text, sizing, or font props change.
--- Widget:SetStyle merges props directly (bypasses setter methods), so caches would go stale.
---@param style table
---@return Label self
function Label:SetStyle(style)
    local needFontUpdate = style.fontSize ~= nil
    local needTextUpdate = style.text ~= nil or style.textTransform ~= nil

    -- UIInspector and normal style updates both use SetStyle rather than the
    -- dedicated setters. Keep the sizing-mode flags identical to SetWidth,
    -- SetHeight, and SetMinHeight so an intrinsic Label can be fixed at runtime.
    if style.width ~= nil then
        self.userSetWidth_ = true
        self.autoWidth_ = false
        if self.multiline_ then
            self.lastMultilineWidth_ = nil
        end
    end
    if style.height ~= nil then
        self.userSetHeight_ = true
        self.autoHeight_ = false
    end
    if style.minHeight ~= nil then
        self.autoMinHeight_ = false
    end
    if style.alignSelf ~= nil then
        self.multilineAddedAlignSelf_ = false
    end

    -- Parse nested color fields in textStroke/textShadow before merging
    if style.textStroke and type(style.textStroke.color) == "string" then
        style.textStroke.color = Style.ParseColor(style.textStroke.color)
    end
    if style.textShadow and type(style.textShadow.color) == "string" then
        style.textShadow.color = Style.ParseColor(style.textShadow.color)
    end

    -- Let base SetStyle handle all props (Yoga, transitions, merge) before
    -- deriving text-flow state. This also makes UIInspector Delete work: it
    -- removes the raw prop and calls SetStyle({}), which must re-read props.
    Widget.SetStyle(self, style)

    if style.height ~= nil then
        syncAutoMinHeight(self, self:GetProps())
    end

    if needTextUpdate then
        self.displayText_ = applyTextTransform(
            self.props.text or "",
            self.props.textTransform
        )
    end

    local flowChanged = refreshTextFlowMode(self)

    -- Update font-derived layout (baseline + auto min-height); shared with the
    -- Render parent-override path via RefreshFontLayout.
    if needFontUpdate then
        self:RefreshFontLayout(self:GetProps())
    end

    if needTextUpdate then
        if self.multiline_ then
            self.lastMultilineWidth_ = nil
            return self
        end
        if not flowChanged and self.autoWidth_ and self.displayText_ ~= "" then
            local props = self:GetProps()
            local nvgFontSize = Theme.FontSize(props.fontSize)
            local fontFace = Theme.FontFace(props.fontFamily, props.fontWeight)
            local textWidth = measureAndCacheTextWidths(
                self,
                self.displayText_,
                nvgFontSize,
                fontFace,
                props.letterSpacing
            )
            if textWidth > 0 then
                self.fontVersion_ = UI.GetFontVersion()
                local pl, pr = getHorizontalPadding(props)
                Widget.SetWidth(self, textWidth + pl + pr)
            end
        end
    end

    return self
end

-- ============================================================================
-- Text Manipulation
-- ============================================================================

--- Set text content
---@param text string
---@return Label self
function Label:SetText(text)
    -- Skip if text hasn't changed
    if self.props.text == text then
        return self
    end
    self.props.text = text

    -- Update cached display text
    self.displayText_ = applyTextTransform(text, self.props.textTransform)

    -- A newline can switch the implicit flow mode when whiteSpace is unset.
    -- Explicit whiteSpace=normal/nowrap remains authoritative.
    local flowChanged = refreshTextFlowMode(self)

    -- Multiline: reset cache to trigger height recalc in next Render
    if self.multiline_ then
        self.lastMultilineWidth_ = nil
        return self
    end

    -- Only recalculate width if it was auto-sized (no explicit width set by user).
    -- If user set width="100%" or width=200, we respect that and let text clip.
    if self.autoWidth_ and not flowChanged then
        local props = self:GetProps()
        local nvgFontSize = Theme.FontSize(props.fontSize)
        local fontFace = Theme.FontFace(props.fontFamily, props.fontWeight)
        local textWidth = measureAndCacheTextWidths(
            self, self.displayText_, nvgFontSize, fontFace,
            props.letterSpacing)

        if textWidth > 0 then
            self.fontVersion_ = UI.GetFontVersion()
            local pl, pr = getHorizontalPadding(props)
            -- Use Widget.SetWidth directly to avoid triggering autoWidth_ = false
            Widget.SetWidth(self, textWidth + pl + pr)
        end
    end

    return self
end

--- Override SetWidth to disable auto-width recalculation in SetText
---@param width number Width in base pixels
---@return Label self
function Label:SetWidth(width)
    self.userSetWidth_ = true
    self.autoWidth_ = false
    if self.multiline_ then
        self.lastMultilineWidth_ = nil  -- Trigger height recalc
    end
    return Widget.SetWidth(self, width)
end

--- Clear an explicit width and restore the Label's intrinsic sizing mode.
--- UIInspector Delete reaches this through Widget:SetWidthAuto polymorphism.
---@return Label self
function Label:SetWidthAuto()
    self.userSetWidth_ = false
    Widget.SetWidthAuto(self)

    if self.multiline_ then
        -- A multiline Label without width follows its parent instead of using
        -- the single-line intrinsic text width.
        self.autoWidth_ = false
        self.lastMultilineWidth_ = nil
        if self.props.alignSelf == nil then
            Widget.SetStyle(self, { alignSelf = "stretch" })
            self.multilineAddedAlignSelf_ = true
        end
        return self
    end

    self.autoWidth_ = true
    clearMeasuredTextWidths(self)
    local text = self.displayText_ or self.props.text or ""
    if text == "" then
        return self
    end

    local props = self:GetProps()
    local nvgFontSize = Theme.FontSize(props.fontSize)
    local fontFace = Theme.FontFace(props.fontFamily, props.fontWeight)
    local textWidth = measureAndCacheTextWidths(
        self, text, nvgFontSize, fontFace, props.letterSpacing)
    if textWidth > 0 then
        self.fontVersion_ = UI.GetFontVersion()
        if self.props.maxWidth == nil then
            Widget.SetStyle(self, { maxWidth = "100%" })
        end
        local pl, pr = getHorizontalPadding(props)
        Widget.SetWidth(self, textWidth + pl + pr)
    end

    return self
end

--- Override SetHeight to disable auto-height recalculation in multiline Render
---@param height number Height in base pixels
---@return Label self
function Label:SetHeight(height)
    self.userSetHeight_ = true
    self.autoHeight_ = false
    Widget.SetHeight(self, height)
    syncAutoMinHeight(self, self:GetProps())
    return self
end

---Clear an explicit height and restore content-driven multiline height or the
---default single-line height. UIInspector Delete dispatches here when present.
---@return Label self
function Label:SetHeightAuto()
    self.userSetHeight_ = false
    self.autoHeight_ = self.multiline_ == true
    resetTextFlowCaches(self)
    local props = self:GetProps()
    Widget.SetHeight(self, computeSingleLineMinHeight(props))
    syncAutoMinHeight(self, props)
    return self
end

--- Override SetMinHeight to disable auto-computation when user explicitly sets minHeight
---@param minHeight number|string
---@return Label self
function Label:SetMinHeight(minHeight)
    self.autoMinHeight_ = false
    return Widget.SetMinHeight(self, minHeight)
end

--- Get text content
---@return string
function Label:GetText()
    return self.props.text or ""
end

--- Set font size
---@param size number
---@return Label self
function Label:SetFontSize(size)
    self.props.fontSize = size

    self:RefreshFontLayout(self:GetProps())

    return self
end

--- Update font-derived layout (baseline + auto min-height) from the effective props
--- (self.props with any parent overrides applied), without mutating self.props.
--- Called from Render and font-size setters. Uses Widget.* base setters so the
--- auto min-height flag is preserved.
---@param props table Effective props (fontSize already resolved)
function Label:RefreshFontLayout(props)
    local nvgFS = Theme.FontSize(props.fontSize)
    local ff = Theme.FontFace(props.fontFamily, props.fontWeight)

    YGNodeSetBaselineValue(self.node, (props.paddingTop or 0) + UI.MeasureTextBaseline(nvgFS, ff))
    syncAutoMinHeight(self, props)
end

--- Set font color
--- Supports multiple formats: RGBA table, hex string, or CSS rgb/rgba
---@param color table|string RGBA table or color string (e.g., "#ff0000", "rgba(255,0,0,1)")
---@return Label self
function Label:SetFontColor(color)
    self.props.fontColor = Style.ParseColor(color) or color
    return self
end

-- ============================================================================
-- Stateless
-- ============================================================================

function Label:IsStateful()
    return false
end

return Label
