-- ============================================================================
-- Tabs Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Tab navigation with content panels
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

local DEFAULT_SHADOW_COLOR = {0, 0, 0, 128}

local function createRoundedRectPath(widget, nvg, x, y, width, height, radius)
    widget:CreateShapePath(nvg, widget:GetShapeGeometry({
        x = x,
        y = y,
        w = width,
        h = height,
    }, nil, radius))
end

local function insetRadius(radius, inset)
    if type(radius) == "table" then
        return {
            math.max(0, (radius[1] or 0) - inset),
            math.max(0, (radius[2] or 0) - inset),
            math.max(0, (radius[3] or 0) - inset),
            math.max(0, (radius[4] or 0) - inset),
        }
    end

    return math.max(0, (radius or 0) - inset)
end

---@class TabItem
---@field id string|number Tab identifier
---@field label? string Tab label (optional for icon-only tabs)
---@field icon? string Icon name
---@field disabled? boolean Is tab disabled
---@field content? Widget Tab content widget

---@class TabsProps : WidgetProps
---@field tabs? TabItem[] List of tabs
---@field activeTab? string|number Currently active tab ID
---@field variant? string "line" | "enclosed" | "pills" (default: "line")
---@field orientation? string "horizontal" | "vertical" (default: "horizontal")
---@field tabHeight? number Tab height (default: 40)
---@field tabWidth? number Tab width for vertical orientation (default: 120)
---@field activeTextColor? RGBAColor|string Active tab text color
---@field activeFontWeight? string Font weight for active tab (default: fontWeight)
---@field inactiveTextColor? RGBAColor|string Inactive tab text color (default: textSecondary)
---@field lineBorderWidth? number Base line border width for line variant (default: 1)
---@field lineBorderColor? RGBAColor|string Base line border color for line variant (default: border)
---@field indicatorThickness? number Active indicator thickness for line variant (default: 3)
---@field enclosedPadding? number Enclosed variant inner padding (default: 0)
---@field pillMargin? number|table Pills variant inset margin: number (uniform) or {top, right, bottom, left} (default: 4)
---@field tabGap? number Gap between tabs (default: 0)
---@field variantTabHeight? table Per-variant tab height { variant_name = number } (overrides tabHeight)
---@field variantTabGap? table Per-variant tab gap { variant_name = number }
---@field variantBoxShadow? table Per-variant active tab shadow { variant_name = boxShadow_array }
---@field variantInactiveBoxShadow? table Per-variant inactive tab shadow { variant_name = boxShadow_array }
---@field variantContainerBgColor? table Per-variant tab header container bg color { variant_name = color }
---@field variantContainerBorderRadius? table Per-variant tab header container radius { variant_name = number|table }
---@field variantContainerBorderColor? table Per-variant tab header container border color { variant_name = color }
---@field variantContainerBorderWidth? table|number Per-variant tab header container border width { variant_name = number }
---@field variantActiveBgColor? table Per-variant active tab bg color { variant_name = color }
---@field variantActiveBackgroundGradient? table Per-variant active tab background gradient { variant_name = gradient }
---@field variantInactiveBgColor? table Per-variant inactive tab bg color { variant_name = color }
---@field variantActiveTextColor? table Per-variant active tab text color { variant_name = color }
---@field variantInactiveTextColor? table Per-variant inactive tab text color { variant_name = color }
---@field variantActiveBorderColor? table Per-variant active tab border color { variant_name = color }
---@field variantActiveBorderWidth? table|number Per-variant active tab border width { variant_name = number }
---@field variantInactiveBorderColor? table Per-variant inactive tab border color { variant_name = color }
---@field variantInactiveBorderWidth? table|number Per-variant inactive tab border width { variant_name = number }
---@field variantBorderInset? table|number Per-variant tab border path inset { variant_name = number }
---@field variantBorderRadius? table Per-variant tab border radius { variant_name = number|table }
---@field tabHoverBgColor? RGBAColor|string Line variant hover background color (default: {128,128,128,20})
---@field tabHoverRadius? number|table Line variant hover border radius, supports per-corner table (default: 0)
---@field tabHoverTextColor? RGBAColor|string Line variant hover text color (default: uses normal inactive color)
---@field fontSize? number Tab text font size in pt (default: Theme.FontSizeOf("body"))
---@field minFontSize? number Minimum auto-fit font size (default: 1)
---@field onChange? fun(self: Tabs, tabId: string|number, tab: TabItem?) Tab change callback

---@class Tabs : Widget
---@overload fun(props?: TabsProps): Tabs
---@field props TabsProps
---@field new fun(self, props?: TabsProps): Tabs
---@field state {hoveredTab: string|number|nil}
local Tabs = Widget:Extend("Tabs")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props TabsProps?
function Tabs:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("Tabs")
    Style.ApplyDefaults(props, themeStyle)
    -- Hardcoded fallbacks (only hit when theme has no entry)
    props.tabHeight = props.tabHeight or 40
    props.borderRadius = props.borderRadius or 6

    -- Default settings
    props.tabs = props.tabs or {}
    props.variant = props.variant or "line"
    props.orientation = props.orientation or "horizontal"

    -- Set default active tab
    if not props.activeTab and #props.tabs > 0 then
        props.activeTab = props.tabs[1].id
    end

    -- Set default height for horizontal tabs (header only)
    if props.orientation ~= "vertical" and not props.height then
        local variant = props.variant or "line"
        local variantHeight = props.variantTabHeight and props.variantTabHeight[variant]
        props.height = variantHeight ~= nil and variantHeight or props.tabHeight
    end

    -- Flex direction based on orientation
    if props.orientation == "vertical" then
        props.flexDirection = "row"
    else
        props.flexDirection = "column"
    end

    -- Initialize state
    self.state = {
        hoveredTab = nil,
    }

    -- Animation state for indicator
    self.indicatorX_ = 0
    self.indicatorWidth_ = 0
    self.targetIndicatorX_ = 0
    self.targetIndicatorWidth_ = 0

    -- Tab content widgets
    self.tabContents_ = {}
    self.autoFitTabCaches_ = {}

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Tabs:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    local tabs = props.tabs
    local activeTab = props.activeTab
    local variant = props.variant
    local orientation = props.orientation
    local variantHeight = props.variantTabHeight and props.variantTabHeight[variant]
    local tabHeight = variantHeight ~= nil and variantHeight or props.tabHeight
    local borderRadius = props.borderRadius

    if #tabs == 0 then
        return
    end

    -- Store values for hit testing
    self.scaledTabHeight_ = tabHeight
    self.scaledTabWidth_ = props.tabWidth or 120

    -- Draw background if set
    if props.backgroundColor then
        self:RenderBackground(nvg, props.backgroundColor, borderRadius)
    end

    -- Calculate and cache layout for CustomRenderChildren
    if orientation == "vertical" then
        self.headerWidth_ = self.scaledTabWidth_
        self.headerHeight_ = l.h
        self.headerX_ = l.x
        self.headerY_ = l.y
        self.contentX_ = l.x + self.headerWidth_
        self.contentY_ = l.y
        self.contentWidth_ = l.w - self.headerWidth_
        self.contentHeight_ = l.h
    else
        self.headerWidth_ = l.w
        self.headerHeight_ = tabHeight
        self.headerX_ = l.x
        self.headerY_ = l.y
        self.contentX_ = l.x
        self.contentY_ = l.y + tabHeight
        self.contentWidth_ = l.w
        self.contentHeight_ = l.h - tabHeight
    end

    -- Draw tab header
    self:RenderTabHeader(nvg, self.headerX_, self.headerY_, self.headerWidth_, self.headerHeight_, tabs, activeTab, variant, orientation)

    -- Content area is rendered in CustomRenderChildren for proper child recursion
end

--- Custom child rendering for tab content
--- Renders tab content with proper child recursion via renderFn
---@param nvg NVGContextWrapper
---@param renderFn function Recursive render function
function Tabs:CustomRenderChildren(nvg, renderFn)
    -- Render tab content with recursive render function
    self:RenderTabContentWithRenderFn(nvg, self.contentX_, self.contentY_, self.contentWidth_, self.contentHeight_, self.props.activeTab, renderFn)

    -- Render standard children (if any, respecting z-index order)
    local renderList = self:GetRenderChildren()
    for i = 1, #renderList do
        renderFn(renderList[i], nvg)
    end
end

--- Render tab header with all tabs
function Tabs:RenderTabHeader(nvg, x, y, width, height, tabs, activeTab, variant, orientation)
    local containerRadii = self.props.variantContainerBorderRadius
    local borderRadius = (type(containerRadii) == "number" and containerRadii)
        or (type(containerRadii) == "table" and containerRadii[variant])
        or self.props.borderRadius
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)

    local containerBorderWidths = self.props.variantContainerBorderWidth
    local containerBorderWidth = self.props.borderWidth or 0
    if type(containerBorderWidths) == "table" and containerBorderWidths[variant] ~= nil then
        containerBorderWidth = containerBorderWidths[variant]
    elseif type(containerBorderWidths) == "number" then
        containerBorderWidth = containerBorderWidths
    end

    -- Draw header background based on variant
    if variant == "enclosed" then
        local containerBgColors = self.props.variantContainerBgColor
        local bgColor = (containerBgColors and containerBgColors[variant])
            or Theme.Color("surface")
        local bw = containerBorderWidth
        if bw > 0 then
            -- Border as outer fill + inset surface fill (avoids stroke lines between tabs)
            local containerBorderColors = self.props.variantContainerBorderColor
            local borderColor = (containerBorderColors and containerBorderColors[variant])
                or self.props.borderColor
                or Theme.Color("border")
            createRoundedRectPath(self, nvg, x, y, width, height, borderRadius)
            nvgFillColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
            nvgFill(nvg)

            if width > bw * 2 and height > bw * 2 then
                createRoundedRectPath(self, nvg, x + bw, y + bw, width - bw * 2, height - bw * 2, insetRadius(borderRadius, bw))
                nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
                nvgFill(nvg)
            end
        else
            createRoundedRectPath(self, nvg, x, y, width, height, borderRadius)
            nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
            nvgFill(nvg)
        end
    end

    -- Calculate tab dimensions
    local encPad = 0
    if variant == "enclosed" then
        encPad = (self.props.enclosedPadding or 0) + containerBorderWidth
    end
    local variantGap = self.props.variantTabGap and self.props.variantTabGap[variant]
    local tabGap = variantGap ~= nil and variantGap or (self.props.tabGap or 0)
    local tabCount = #tabs
    local totalGap = (tabCount - 1) * tabGap
    local variantHeight = self.props.variantTabHeight and self.props.variantTabHeight[variant]
    local tabWidth, tabHeight
    if orientation == "vertical" then
        tabWidth = width - encPad * 2
        tabHeight = variantHeight ~= nil and variantHeight or self.props.tabHeight
    else
        tabWidth = (width - encPad * 2 - totalGap) / tabCount
        tabHeight = height - encPad * 2
    end

    -- Store tab layouts for hit testing
    self.tabLayouts_ = {}

    -- Render each tab
    for i, tab in ipairs(tabs) do
        local tabX, tabY

        if orientation == "vertical" then
            tabX = x + encPad
            tabY = y + encPad + (i - 1) * (tabHeight + tabGap)
        else
            tabX = x + encPad + (i - 1) * (tabWidth + tabGap)
            tabY = y + encPad
        end

        -- Store layout (relative to header origin for hit testing)
        self.tabLayouts_[tab.id] = {
            x = tabX - x,  -- relative to header X
            y = tabY - y,  -- relative to header Y
            w = tabWidth,
            h = tabHeight,
            index = i,
        }

        local isActive = tab.id == activeTab
        local isHovered = self.state.hoveredTab == tab.id
        local isDisabled = tab.disabled

        -- Update indicator target for active tab
        if isActive then
            if orientation == "vertical" then
                self.targetIndicatorX_ = tabY
                self.targetIndicatorWidth_ = tabHeight
            else
                self.targetIndicatorX_ = tabX
                self.targetIndicatorWidth_ = tabWidth
            end
        end

        self:RenderTab(nvg, tab, tabX, tabY, tabWidth, tabHeight, isActive, isHovered, isDisabled, variant, orientation)
    end

    -- Draw bottom border for line variant
    if variant == "line" and orientation == "horizontal" then
        local lineBorderWidth = self.props.lineBorderWidth
        if lineBorderWidth == nil then
            lineBorderWidth = 1
        end
        if lineBorderWidth > 0 then
            local explicitLineBorder = self.props.lineBorderColor or self.props.borderColor
            local borderColor = explicitLineBorder or Theme.Color("border")
            local alpha = explicitLineBorder and (borderColor[4] or 255) or 100
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x, y + height)
            nvgLineTo(nvg, x + width, y + height)
            nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], alpha))
            nvgStrokeWidth(nvg, lineBorderWidth)
            nvgStroke(nvg)
        end
    end

    -- Draw indicator line above the base line for "line" variant
    if variant == "line" then
        self:RenderIndicator(nvg, x, y, width, height, orientation)
    end
end

--- Render a single tab
function Tabs:RenderTab(nvg, tab, x, y, width, height, isActive, isHovered, isDisabled, variant, orientation)
    local variantRadii = self.props.variantBorderRadius
    local borderRadius = (type(variantRadii) == "number" and variantRadii)
        or (type(variantRadii) == "table" and variantRadii[variant])
        or self.props.borderRadius
        or 0
    -- Pill margin: number (uniform) or {top, right, bottom, left} CSS shorthand
    local pillMarginProp = self.props.pillMargin
    local pmT, pmR, pmB, pmL
    if type(pillMarginProp) == "table" then
        if #pillMarginProp == 1 then
            pmT, pmR, pmB, pmL = pillMarginProp[1], pillMarginProp[1], pillMarginProp[1], pillMarginProp[1]
        elseif #pillMarginProp == 2 then
            pmT, pmB = pillMarginProp[1], pillMarginProp[1]
            pmR, pmL = pillMarginProp[2], pillMarginProp[2]
        elseif #pillMarginProp == 3 then
            pmT = pillMarginProp[1]
            pmR, pmL = pillMarginProp[2], pillMarginProp[2]
            pmB = pillMarginProp[3]
        else
            pmT, pmR, pmB, pmL = pillMarginProp[1], pillMarginProp[2], pillMarginProp[3], pillMarginProp[4]
        end
    else
        local pm = pillMarginProp or 4
        pmT, pmR, pmB, pmL = pm, pm, pm, pm
    end
    local fontWeight = isActive and (self.props.activeFontWeight or self.props.fontWeight) or self.props.fontWeight
    local fontFamily = Theme.FontFace(self.props.fontFamily, fontWeight)
    local padding = 12

    -- Determine colors
    local bgColor, bgGradient, textColor

    if isDisabled then
        bgColor = nil
        textColor = Theme.Color("disabledText")
    elseif isActive then
        local varActiveBg = self.props.variantActiveBgColor
        local variantBg = varActiveBg and varActiveBg[variant]
        local varActiveGrad = self.props.variantActiveBackgroundGradient
        local variantGradient = varActiveGrad and varActiveGrad[variant]
        local varActiveText = self.props.variantActiveTextColor
        local variantText = varActiveText and varActiveText[variant]
        if variant == "pills" then
            bgColor = variantBg or self.props.activeBgColor or Theme.Color("primary")
            bgGradient = variantGradient
            textColor = variantText or self.props.activeTextColor or { 255, 255, 255, 255 }
        elseif variant == "enclosed" then
            bgColor = variantBg or self.props.activeBgColor or Theme.Color("background")
            bgGradient = variantGradient
            textColor = variantText or self.props.activeTextColor or Theme.Color("text")
        else
            bgColor = nil
            textColor = variantText or self.props.activeTextColor or Theme.Color("primary")
        end
    elseif isHovered then
        if variant == "pills" then
            bgColor = Theme.Color("surfaceHover") or Style.Lighten(Theme.Color("surface"), 0.1)
        else
            bgColor = nil
        end
        textColor = Theme.Color("text")
        -- Override hover text color if specified (line variant)
        if self.props.tabHoverTextColor then
            textColor = self.props.tabHoverTextColor
        end
    else
        local varInactiveBg = self.props.variantInactiveBgColor
        local variantBg = varInactiveBg and varInactiveBg[variant]
        if variantBg ~= nil then
            bgColor = variantBg
        elseif variant == "pills" then
            bgColor = Theme.Color("surface")  -- pills are button-style, inactive has background
        else
            bgColor = nil                     -- line/enclosed inactive: transparent
        end
        local varInactiveText = self.props.variantInactiveTextColor
        local variantText = varInactiveText and varInactiveText[variant]
        textColor = variantText or self.props.inactiveTextColor or Theme.Color("textSecondary")
    end

    -- Draw per-variant tab shadow (before background so bg covers shadow)
    local varShadows
    if isActive then
        varShadows = self.props.variantBoxShadow
    else
        varShadows = self.props.variantInactiveBoxShadow
    end
    local tabShadow = varShadows and varShadows[variant]
    if tabShadow and tabShadow ~= false and not isDisabled then
        local tx, ty, tw, th
        if variant == "pills" then
            tx, ty = x + pmL, y + pmT
            tw, th = width - pmL - pmR, height - pmT - pmB
        else
            tx, ty, tw, th = x, y, width, height
        end
        for _, s in ipairs(tabShadow) do
            local scolor = s.color or DEFAULT_SHADOW_COLOR
            createRoundedRectPath(self, nvg, tx + (s.x or 0), ty + (s.y or 0), tw, th, borderRadius)
            nvgFillColor(nvg, nvgRGBA(scolor[1], scolor[2], scolor[3], scolor[4] or 128))
            nvgFill(nvg)
        end
    end

    -- Draw background
    if bgColor or bgGradient then
        local bgX, bgY, bgW, bgH, bgRadius
        if variant == "pills" then
            bgX, bgY = x + pmL, y + pmT
            bgW, bgH = width - pmL - pmR, height - pmT - pmB
            bgRadius = borderRadius
        elseif variant == "enclosed" and isActive then
            bgX, bgY, bgW, bgH = x, y, width, height
            bgRadius = borderRadius
        else
            bgX, bgY, bgW, bgH = x, y, width, height
            bgRadius = 0
        end

        local bgGeom = self:GetShapeGeometry({ x = bgX, y = bgY, w = bgW, h = bgH }, nil, bgRadius)
        if bgColor then
            self:CreateShapePath(nvg, bgGeom)
            nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
            nvgFill(nvg)
        end
        if bgGradient then
            self:RenderGradientBackground(nvg, bgGeom, bgGradient)
        end
    end

    -- Draw tab border for pills and enclosed active tabs.
    local shouldDrawTabBorder = variant == "pills" or (variant == "enclosed" and isActive)
    if shouldDrawTabBorder then
        local activeBorderWidths = self.props.variantActiveBorderWidth
        local inactiveBorderWidths = self.props.variantInactiveBorderWidth
        local tabBorderWidth = variant == "pills" and self.props.borderWidth or nil
        if isActive then
            if type(activeBorderWidths) == "table" and activeBorderWidths[variant] ~= nil then
                tabBorderWidth = activeBorderWidths[variant]
            elseif type(activeBorderWidths) == "number" then
                tabBorderWidth = activeBorderWidths
            end
        elseif variant == "pills" then
            if type(inactiveBorderWidths) == "table" and inactiveBorderWidths[variant] ~= nil then
                tabBorderWidth = inactiveBorderWidths[variant]
            elseif type(inactiveBorderWidths) == "number" then
                tabBorderWidth = inactiveBorderWidths
            end
        end
        if tabBorderWidth and tabBorderWidth > 0 then
            -- Inset path by half stroke width unless a variant inset is supplied.
            local borderInsets = self.props.variantBorderInset
            local bInset = tabBorderWidth / 2
            if type(borderInsets) == "table" and borderInsets[variant] ~= nil then
                bInset = borderInsets[variant]
            elseif type(borderInsets) == "number" then
                bInset = borderInsets
            end
            local bx, by, bw, bh
            if variant == "pills" then
                bx = x + pmL + bInset
                by = y + pmT + bInset
                bw = width - pmL - pmR - bInset * 2
                bh = height - pmT - pmB - bInset * 2
            else
                bx = x + bInset
                by = y + bInset
                bw = width - bInset * 2
                bh = height - bInset * 2
            end
            local bRadius
            if type(borderRadius) == "table" then
                bRadius = {
                    math.max(0, (borderRadius[1] or 0) - bInset),
                    math.max(0, (borderRadius[2] or 0) - bInset),
                    math.max(0, (borderRadius[3] or 0) - bInset),
                    math.max(0, (borderRadius[4] or 0) - bInset),
                }
            else
                bRadius = math.max(0, borderRadius - bInset)
            end
            createRoundedRectPath(self, nvg, bx, by, bw, bh, bRadius)
            local tabBorderColor
            if isActive then
                local varBorders = self.props.variantActiveBorderColor
                tabBorderColor = (varBorders and varBorders[variant])
                    or self.props.activeBorderColor
                    or Theme.Color("primary")
            else
                local varInactiveBorders = self.props.variantInactiveBorderColor
                tabBorderColor = (varInactiveBorders and varInactiveBorders[variant])
                    or self.props.borderColor
                    or Theme.Color("border")
            end
            nvgStrokeColor(nvg, nvgRGBA(tabBorderColor[1], tabBorderColor[2], tabBorderColor[3], tabBorderColor[4] or 255))
            nvgStrokeWidth(nvg, tabBorderWidth)
            nvgStroke(nvg)
        end
    end

    -- Draw hover background for non-pill variants
    if isHovered and not isActive and not isDisabled and variant ~= "pills" then
        if variant == "enclosed" then
            createRoundedRectPath(self, nvg, x, y, width, height, borderRadius)
        else
            local hoverRadius = self.props.tabHoverRadius
            if hoverRadius then
                if type(hoverRadius) == "table" then
                    nvgBeginPath(nvg)
                    nvgRoundedRectVarying(nvg, x, y, width, height, hoverRadius[1] or 0, hoverRadius[2] or 0, hoverRadius[3] or 0, hoverRadius[4] or 0)
                else
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, x, y, width, height, hoverRadius)
                end
            else
                nvgBeginPath(nvg)
                nvgRect(nvg, x, y, width, height)
            end
        end
        local hoverBgColor = self.props.tabHoverBgColor
        if hoverBgColor then
            nvgFillColor(nvg, nvgRGBA(hoverBgColor[1], hoverBgColor[2], hoverBgColor[3], hoverBgColor[4] or 255))
        else
            nvgFillColor(nvg, nvgRGBA(128, 128, 128, 20))
        end
        nvgFill(nvg)
    end

    -- Draw label
    local label = tab.label or ""
    local baseFontSize = self.props.fontSize
        and Theme.FontSize(self.props.fontSize)
        or Theme.FontSizeOf("body")
    local textWidth = math.max(0, width - padding * 2)
    local renderFontSize = baseFontSize
    if UI.defaultAutoFitText then
        local cacheKey = tab.id or tab
        local fitResult = UI.MeasureTextFit(label, {
            fontSize = baseFontSize,
            fontFace = fontFamily,
            width = textWidth,
            height = math.max(0, height),
            multiline = false,
            minFontSize = self.props.minFontSize
                and Theme.FontSize(self.props.minFontSize) or 1,
            cache = self.autoFitTabCaches_[cacheKey],
        })
        self.autoFitTabCaches_[cacheKey] = fitResult
        renderFontSize = fitResult.fontSize or baseFontSize
    end

    if UI.defaultAutoFitText then
        nvgSave(nvg)
        nvgIntersectScissor(nvg, x + padding, y, textWidth, height)
    end
    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, renderFontSize)
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    if UI.defaultAutoFitText then
        nvgText(nvg, x + width / 2, y + height / 2,
            label, nil, false)
    else
        nvgText(nvg, x + width / 2, y + height / 2, label, nil)
    end
    if UI.defaultAutoFitText then
        nvgRestore(nvg)
    end
end

--- Render the active tab indicator
function Tabs:RenderIndicator(nvg, headerX, headerY, headerWidth, headerHeight, orientation)
    -- Animate indicator position
    local speed = 0.2
    self.indicatorX_ = self.indicatorX_ + (self.targetIndicatorX_ - self.indicatorX_) * speed
    self.indicatorWidth_ = self.indicatorWidth_ + (self.targetIndicatorWidth_ - self.indicatorWidth_) * speed

    local varBorders = self.props.variantActiveBorderColor
    local indicatorColor = (varBorders and varBorders["line"])
        or self.props.activeBorderColor
        or Theme.Color("primary")
    local indicatorThickness = self.props.indicatorThickness or 3

    nvgBeginPath(nvg)

    if orientation == "vertical" then
        -- Vertical indicator on left side
        nvgRoundedRect(nvg,
            headerX,
            self.indicatorX_,
            indicatorThickness,
            self.indicatorWidth_,
            indicatorThickness / 2
        )
    else
        -- Horizontal indicator at bottom
        nvgRoundedRect(nvg,
            self.indicatorX_,
            headerY + headerHeight - indicatorThickness,
            self.indicatorWidth_,
            indicatorThickness,
            indicatorThickness / 2
        )
    end

    nvgFillColor(nvg, nvgRGBA(indicatorColor[1], indicatorColor[2], indicatorColor[3], indicatorColor[4] or 255))
    nvgFill(nvg)
end

--- Render tab content area with recursive render function
--- This version uses renderFn for proper child recursion
---@param nvg NVGContextWrapper
---@param x number Content X position
---@param y number Content Y position
---@param width number Content width
---@param height number Content height
---@param activeTab string|number Active tab ID
---@param renderFn function Recursive render function
function Tabs:RenderTabContentWithRenderFn(nvg, x, y, width, height, activeTab, renderFn)
    -- Only render if we have content area
    if not x or not height or height <= 0 then
        return
    end

    -- Draw content background
    local bgColor = Theme.Color("background")
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, width, height)
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    -- Find and render active tab content
    local activeContent = self.tabContents_[activeTab]
    if activeContent then
        nvgSave(nvg)
        nvgIntersectScissor(nvg, x, y, width, height)

        -- Set content render offset and size (for widgets not in Yoga tree)
        activeContent.renderOffsetX_ = x
        activeContent.renderOffsetY_ = y
        activeContent.renderWidth_ = width
        activeContent.renderHeight_ = height

        -- Calculate Yoga layout for content subtree (since it's not in main Yoga tree)
        -- Yoga works in base pixels, pass width/height directly
        if activeContent.node then
            activeContent:SetWidth(width)
            activeContent:SetHeight(height)
            YGNodeCalculateLayout(activeContent.node, width, height, YGDirectionLTR)
        end

        -- Use renderFn for proper recursive rendering of content and its children
        renderFn(activeContent, nvg)

        nvgRestore(nvg)
    end
end

--- [DEPRECATED] Render tab content area (for backward compatibility)
--- Use RenderTabContentWithRenderFn in CustomRenderChildren instead
function Tabs:RenderTabContent(nvg, x, y, width, height, activeTab)
    -- This method is kept for backward compatibility
    -- New code should use CustomRenderChildren which calls RenderTabContentWithRenderFn
    if not x or not height or height <= 0 then
        return
    end

    local bgColor = Theme.Color("background")
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, width, height)
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    local activeContent = self.tabContents_[activeTab]
    if activeContent then
        nvgSave(nvg)
        nvgIntersectScissor(nvg, x, y, width, height)

        activeContent.renderOffsetX_ = x
        activeContent.renderOffsetY_ = y
        activeContent.renderWidth_ = width
        activeContent.renderHeight_ = height

        if activeContent.node then
            activeContent:SetWidth(width)
            activeContent:SetHeight(height)
            YGNodeCalculateLayout(activeContent.node, width, height, YGDirectionLTR)
        end

        activeContent:Render(nvg)

        nvgRestore(nvg)
    end
end

-- ============================================================================
-- Update
-- ============================================================================

function Tabs:Update(dt)
    -- Update active tab content
    local activeContent = self.tabContents_[self.props.activeTab]
    if activeContent and activeContent.Update then
        activeContent:Update(dt)
    end
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

--- Check if point is in header area (returns true) or content area (returns false)
function Tabs:IsInHeaderArea(localX, localY)
    local props = self.props

    -- Use values stored during render for consistent hit testing
    if props.orientation == "vertical" then
        local headerWidth = self.scaledTabWidth_ or (props.tabWidth or 120)
        return localX < headerWidth
    else
        local tabHeight = self.scaledTabHeight_ or props.tabHeight
        return localY < tabHeight
    end
end

--- Get active tab content widget
function Tabs:GetActiveContent()
    return self.tabContents_[self.props.activeTab]
end

--- Get children for hit testing (used by UI.findWidgetAt)
function Tabs:GetHitTestChildren()
    local content = self:GetActiveContent()
    if content and content.renderOffsetX_ then
        return { content }
    end
    return nil
end

function Tabs:OnMouseEnter()
    -- Handled by OnPointerMove
end

function Tabs:OnMouseLeave()
    self:SetState({ hoveredTab = nil })
end

function Tabs:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    local l = self:GetAbsoluteLayoutForHitTest()
    local localX = event.x - l.x
    local localY = event.y - l.y

    if self:IsInHeaderArea(localX, localY) then
        -- Handle header hover
        local hoveredTab = nil
        for tabId, layout in pairs(self.tabLayouts_ or {}) do
            if localX >= layout.x and localX <= layout.x + layout.w
                and localY >= layout.y and localY <= layout.y + layout.h then
                hoveredTab = tabId
                break
            end
        end

        if self.state.hoveredTab ~= hoveredTab then
            self:SetState({ hoveredTab = hoveredTab })
        end
    else
        -- Clear header hover
        if self.state.hoveredTab then
            self:SetState({ hoveredTab = nil })
        end
    end
end

function Tabs:OnPointerDown(event)
    Widget.OnPointerDown(self, event)
    -- Note: content event dispatching is handled by the UI framework via
    -- GetHitTestChildren — no manual forwarding needed here.
end

function Tabs:OnPointerUp(event)
    Widget.OnPointerUp(self, event)
end

function Tabs:OnClick(event)
    if not event then return end

    -- Get widget's screen position (for hit testing)
    local l = self:GetAbsoluteLayoutForHitTest()

    -- Convert event coordinates to local coordinates relative to Tabs widget
    local localX = event.x - l.x
    local localY = event.y - l.y

    if self:IsInHeaderArea(localX, localY) then
        -- Check which tab was clicked using local coordinates
        -- tabLayouts_ stores coordinates relative to header origin (0,0)
        for tabId, layout in pairs(self.tabLayouts_ or {}) do
            if localX >= layout.x and localX <= layout.x + layout.w
                and localY >= layout.y and localY <= layout.y + layout.h then

                -- Find tab and check if disabled
                for _, tab in ipairs(self.props.tabs) do
                    if tab.id == tabId and not tab.disabled then
                        self:SetActiveTab(tabId)
                        break
                    end
                end
                break
            end
        end
    end
    -- Content area clicks are handled by normal event propagation
    -- Do NOT forward clicks to content here - it causes infinite recursion
end

-- ============================================================================
-- Content Management
-- ============================================================================

--- Set content for a tab
---@param tabId string|number
---@param content Widget
---@return Tabs self
function Tabs:SetTabContent(tabId, content)
    if self.tabContents_[tabId] then
        self.tabContents_[tabId].parent = nil
    end
    self.tabContents_[tabId] = content
    if content then
        content.parent = self
    end
    return self
end

--- Get content for a tab
---@param tabId string|number
---@return Widget|nil
function Tabs:GetTabContent(tabId)
    return self.tabContents_[tabId]
end

--- Remove content for a tab
---@param tabId string|number
---@return Tabs self
function Tabs:RemoveTabContent(tabId)
    if self.tabContents_[tabId] then
        self.tabContents_[tabId].parent = nil
        self.tabContents_[tabId] = nil
    end
    return self
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set active tab
---@param tabId string|number
---@return Tabs self
function Tabs:SetActiveTab(tabId)
    if self.props.activeTab ~= tabId then
        -- Notify old content of mouse leave (clear hover state)
        local oldContent = self.tabContents_[self.props.activeTab]
        if oldContent and oldContent.OnMouseLeave then
            oldContent:OnMouseLeave()
        end

        self.props.activeTab = tabId

        -- Find tab object
        local tab = nil
        for _, t in ipairs(self.props.tabs) do
            if t.id == tabId then
                tab = t
                break
            end
        end

        self:DispatchEvent("change", self, tabId, tab)
        if self.props.onChange then
            self.props.onChange(self, tabId, tab)
        end
    end
    return self
end

--- Get active tab ID
---@return string|number
function Tabs:GetActiveTab()
    return self.props.activeTab
end

--- Add a tab
---@param tab TabItem
---@param content Widget|nil
---@return Tabs self
function Tabs:AddTab(tab, content)
    table.insert(self.props.tabs, tab)
    if content then
        self:SetTabContent(tab.id, content)
    end

    -- Set as active if first tab
    if #self.props.tabs == 1 then
        self.props.activeTab = tab.id
    end

    return self
end

--- Remove a tab by ID
---@param tabId string|number
---@return Tabs self
function Tabs:RemoveTab(tabId)
    for i, tab in ipairs(self.props.tabs) do
        if tab.id == tabId then
            table.remove(self.props.tabs, i)
            self.autoFitTabCaches_[tabId] = nil
            self:RemoveTabContent(tabId)

            -- Switch to another tab if active was removed
            if self.props.activeTab == tabId and #self.props.tabs > 0 then
                self.props.activeTab = self.props.tabs[1].id
            end
            break
        end
    end
    return self
end

--- Update tab properties
---@param tabId string|number
---@param updates table { label, disabled, etc }
---@return Tabs self
function Tabs:UpdateTab(tabId, updates)
    for _, tab in ipairs(self.props.tabs) do
        if tab.id == tabId then
            self.autoFitTabCaches_[tabId] = nil
            for k, v in pairs(updates) do
                tab[k] = v
            end
            break
        end
    end
    return self
end

--- Set tabs
---@param tabs TabItem[]
---@return Tabs self
function Tabs:SetTabs(tabs)
    self.props.tabs = tabs or {}
    self.autoFitTabCaches_ = {}

    -- Clear content
    for tabId, content in pairs(self.tabContents_) do
        content.parent = nil
    end
    self.tabContents_ = {}

    -- Reset active tab
    if #self.props.tabs > 0 then
        self.props.activeTab = self.props.tabs[1].id
    else
        self.props.activeTab = nil
    end

    return self
end

--- Get tab count
---@return number
function Tabs:GetTabCount()
    return #self.props.tabs
end

--- Set variant
---@param variant string "line" | "enclosed" | "pills"
---@return Tabs self
function Tabs:SetVariant(variant)
    self.props.variant = variant
    return self
end

--- Set orientation
---@param orientation string "horizontal" | "vertical"
---@return Tabs self
function Tabs:SetOrientation(orientation)
    self.props.orientation = orientation
    if orientation == "vertical" then
        self.props.flexDirection = "row"
    else
        self.props.flexDirection = "column"
    end
    return self
end

--- Navigate to next tab
---@return Tabs self
function Tabs:NextTab()
    local tabs = self.props.tabs
    local activeTab = self.props.activeTab

    for i, tab in ipairs(tabs) do
        if tab.id == activeTab then
            -- Find next non-disabled tab
            for j = i + 1, #tabs do
                if not tabs[j].disabled then
                    self:SetActiveTab(tabs[j].id)
                    return self
                end
            end
            -- Wrap to beginning
            for j = 1, i - 1 do
                if not tabs[j].disabled then
                    self:SetActiveTab(tabs[j].id)
                    return self
                end
            end
            break
        end
    end

    return self
end

--- Navigate to previous tab
---@return Tabs self
function Tabs:PrevTab()
    local tabs = self.props.tabs
    local activeTab = self.props.activeTab

    for i, tab in ipairs(tabs) do
        if tab.id == activeTab then
            -- Find previous non-disabled tab
            for j = i - 1, 1, -1 do
                if not tabs[j].disabled then
                    self:SetActiveTab(tabs[j].id)
                    return self
                end
            end
            -- Wrap to end
            for j = #tabs, i + 1, -1 do
                if not tabs[j].disabled then
                    self:SetActiveTab(tabs[j].id)
                    return self
                end
            end
            break
        end
    end

    return self
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Tabs:IsStateful()
    return true
end

return Tabs
