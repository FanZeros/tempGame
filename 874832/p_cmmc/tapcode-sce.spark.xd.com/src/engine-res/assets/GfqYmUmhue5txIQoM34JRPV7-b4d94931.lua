-- ============================================================================
-- Pagination Widget
-- Page navigation component for paginated content
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class PaginationProps : WidgetProps
---@field currentPage? number Current page number (default: 1)
---@field page? number Alias for currentPage
---@field totalPages? number Total number of pages (default: 1)
---@field count? number Alias for totalPages
---@field siblingCount? number Pages shown on each side of current (default: 1)
---@field boundaryCount? number Pages shown at start/end (default: 1)
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field variant? string "outlined" | "filled" | "text" (default: "outlined")
---@field shape? string "rounded" | "circular" | "square" (default: "rounded")
---@field showFirstButton? boolean Show first page button (default: false)
---@field showLastButton? boolean Show last page button (default: false)
---@field showPrevNext? boolean Show prev/next buttons (default: true)
---@field disabled? boolean Disabled state (default: false)
---@field hideDisabled? boolean Hide prev/next when disabled (default: false)
---@field color? string Theme color name (default: "primary")
---@field buttonSize? number Custom button size
---@field fontSize? number Custom font size
---@field gap? number Gap between buttons
---@field hoverBgColor? RGBAColor|string|false Hover background color (false to disable, default: baseColor@10%)
---@field buttonBoxShadow? table Per-button box shadow (not container-level)
---@field activeButtonBoxShadow? table Active page button box shadow (default: uses buttonBoxShadow)
---@field buttonBgColor? RGBAColor|string Normal button background color for outlined variant (default: transparent)
---@field activeFontWeight? string Font weight for active page button (default: fontWeight)
---@field onChange? fun(pagination: Pagination, page: number) Page change callback

---@class Pagination : Widget
---@overload fun(props?: PaginationProps): Pagination
---@field props PaginationProps
---@field new fun(self, props?: PaginationProps): Pagination
local Pagination = Widget:Extend("Pagination")

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { buttonSize = 28, fontSize = 12, gap = 4 },
    md = { buttonSize = 36, fontSize = 14, gap = 6 },
    lg = { buttonSize = 44, fontSize = 16, gap = 8 },
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props PaginationProps?
function Pagination:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Pagination")
    Style.ApplyDefaults(props, themeStyle)

    -- Pagination props
    self.currentPage_ = props.currentPage or props.page or 1
    self.totalPages_ = props.totalPages or props.count or 1
    self.siblingCount_ = props.siblingCount or 1  -- Pages shown on each side of current
    self.boundaryCount_ = props.boundaryCount or 1  -- Pages shown at start/end
    self.size_ = props.size or "md"
    self.variant_ = props.variant or "outlined"  -- outlined, filled, text
    self.shape_ = props.shape or "rounded"  -- rounded, circular, square
    self.showFirstButton_ = props.showFirstButton or false
    self.showLastButton_ = props.showLastButton or false
    self.showPrevNext_ = props.showPrevNext ~= false  -- default true
    self.disabled_ = props.disabled or false
    self.hideDisabled_ = props.hideDisabled or false  -- Hide prev/next when disabled

    -- Colors
    self.color_ = props.color or "primary"

    -- Callbacks
    self.onChange_ = props.onChange

    -- State
    self.hoverIndex_ = nil

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.buttonSize_ = props.buttonSize or sizePreset.buttonSize
    self.fontSize_ = props.fontSize and Theme.FontSize(props.fontSize) or Theme.FontSize(sizePreset.fontSize)
    self.gap_ = props.gap or sizePreset.gap

    props.height = props.height or self.buttonSize_
    props.flexDirection = "row"
    props.alignItems = "center"
    props.gap = self.gap_

    Widget.Init(self, props)
end

-- ============================================================================
-- Page Management
-- ============================================================================

function Pagination:GetCurrentPage()
    return self.currentPage_
end

function Pagination:SetCurrentPage(page)
    page = math.max(1, math.min(self.totalPages_, page))

    if self.currentPage_ ~= page then
        self.currentPage_ = page
        self:DispatchEvent("change", self, page)
        if self.onChange_ then
            self.onChange_(self, page)
        end
    end
end

function Pagination:GetTotalPages()
    return self.totalPages_
end

function Pagination:SetTotalPages(total)
    self.totalPages_ = math.max(1, total)
    if self.currentPage_ > self.totalPages_ then
        self:SetCurrentPage(self.totalPages_)
    end
end

function Pagination:GoToFirst()
    self:SetCurrentPage(1)
end

function Pagination:GoToLast()
    self:SetCurrentPage(self.totalPages_)
end

function Pagination:GoToPrev()
    self:SetCurrentPage(self.currentPage_ - 1)
end

function Pagination:GoToNext()
    self:SetCurrentPage(self.currentPage_ + 1)
end

function Pagination:IsFirstPage()
    return self.currentPage_ == 1
end

function Pagination:IsLastPage()
    return self.currentPage_ == self.totalPages_
end

-- ============================================================================
-- Page Range Calculation
-- ============================================================================

function Pagination:GetPageRange()
    local current = self.currentPage_
    local total = self.totalPages_
    local sibling = self.siblingCount_
    local boundary = self.boundaryCount_

    -- Simple case: all pages fit
    local totalNumbers = boundary * 2 + sibling * 2 + 3  -- boundaries + siblings + current + 2 ellipsis
    if total <= totalNumbers then
        local pages = {}
        for i = 1, total do
            table.insert(pages, i)
        end
        return pages
    end

    local pages = {}

    -- Left boundary
    for i = 1, boundary do
        table.insert(pages, i)
    end

    -- Calculate sibling range
    local leftSibling = math.max(boundary + 1, current - sibling)
    local rightSibling = math.min(total - boundary, current + sibling)

    -- Adjust if too close to boundaries
    local showLeftEllipsis = leftSibling > boundary + 2
    local showRightEllipsis = rightSibling < total - boundary - 1

    if not showLeftEllipsis and showRightEllipsis then
        -- No left ellipsis, extend left side
        local leftRange = boundary + 1 + sibling * 2 + 1
        for i = boundary + 1, leftRange do
            if i <= total then
                table.insert(pages, i)
            end
        end
        table.insert(pages, "...")
    elseif showLeftEllipsis and not showRightEllipsis then
        -- No right ellipsis, extend right side
        table.insert(pages, "...")
        local rightRange = total - boundary - sibling * 2 - 1
        for i = rightRange, total - boundary do
            if i > boundary then
                table.insert(pages, i)
            end
        end
    else
        -- Both ellipsis
        table.insert(pages, "...")
        for i = leftSibling, rightSibling do
            table.insert(pages, i)
        end
        table.insert(pages, "...")
    end

    -- Right boundary
    for i = total - boundary + 1, total do
        if i > 0 then
            table.insert(pages, i)
        end
    end

    return pages
end

-- ============================================================================
-- Drawing Helpers
-- ============================================================================

--- Returns: textColor, bgColor, bgOpaque (3rd value = whether bg can cover border fill)
function Pagination:GetButtonColor(isActive, isHovered, isDisabled)
    if isDisabled then
        local disabledTable = Theme.Color("textDisabled")
        local transparentTable = Theme.Color("transparent")
        return nvgRGBA(disabledTable[1], disabledTable[2], disabledTable[3], disabledTable[4] or 255),
               nvgRGBA(transparentTable[1], transparentTable[2], transparentTable[3], transparentTable[4] or 0), false
    end

    local colorName = self.color_
    local baseColorTable = Theme.Color(colorName)
    local baseColor = nvgRGBA(baseColorTable[1], baseColorTable[2], baseColorTable[3], baseColorTable[4] or 255)
    local textColorTable = Theme.Color("text")
    local textColor = nvgRGBA(textColorTable[1], textColorTable[2], textColorTable[3], textColorTable[4] or 255)
    local textSecondaryTable = Theme.Color("textSecondary")
    local textSecondary = nvgRGBA(textSecondaryTable[1], textSecondaryTable[2], textSecondaryTable[3], textSecondaryTable[4] or 255)

    -- Resolve hover background (shared by all variants)
    local hoverBgProp = self.props.hoverBgColor
    local resolvedHoverBg
    if hoverBgProp == false then
        resolvedHoverBg = nvgRGBA(0, 0, 0, 0)
    elseif hoverBgProp then
        resolvedHoverBg = nvgRGBA(hoverBgProp[1], hoverBgProp[2], hoverBgProp[3], hoverBgProp[4] or 255)
    else
        resolvedHoverBg = nvgTransRGBAf(baseColor, 0.1)
    end

    if self.variant_ == "filled" then
        if isActive then
            return nvgRGBA(255, 255, 255, 255), baseColor, true
        elseif isHovered then
            return textColor, resolvedHoverBg, false
        else
            return textColor, nvgRGBA(0, 0, 0, 0), false
        end
    elseif self.variant_ == "outlined" then
        if isActive then
            local activeBg = self.props.activeBgColor
            if activeBg then
                local activeText = self.props.activeTextColor
                if activeText then
                    return nvgRGBA(activeText[1], activeText[2], activeText[3], activeText[4] or 255), nvgRGBA(activeBg[1], activeBg[2], activeBg[3], activeBg[4] or 255), true
                end
                return nvgRGBA(255, 255, 255, 255), nvgRGBA(activeBg[1], activeBg[2], activeBg[3], activeBg[4] or 255), true
            end
            return baseColor, nvgRGBA(0, 0, 0, 0), false
        elseif isHovered then
            -- hoverBgColor=false means "keep normal bg on hover", not "make transparent"
            if hoverBgProp == false then
                local btnBg = self.props.buttonBgColor
                if btnBg then
                    return textColor, nvgRGBA(btnBg[1], btnBg[2], btnBg[3], btnBg[4] or 255), true
                end
            end
            return textColor, resolvedHoverBg, false
        else
            local btnBg = self.props.buttonBgColor
            if btnBg then
                return textSecondary, nvgRGBA(btnBg[1], btnBg[2], btnBg[3], btnBg[4] or 255), true
            end
            return textSecondary, nvgRGBA(0, 0, 0, 0), false
        end
    else  -- text
        if isActive then
            return baseColor, nvgRGBA(0, 0, 0, 0), false
        elseif isHovered then
            return textColor, resolvedHoverBg, false
        else
            return textSecondary, nvgRGBA(0, 0, 0, 0), false
        end
    end
end

function Pagination:DrawButton(nvg, x, y, text, isActive, isHovered, isDisabled, isArrow)
    return self:DrawButtonScaled(nvg, x, y, text, isActive, isHovered, isDisabled, isArrow, self.buttonSize_, self.fontSize_)
end

function Pagination:DrawButtonScaled(nvg, x, y, text, isActive, isHovered, isDisabled, isArrow, size, fontSize)
    local textColor, bgColor, bgOpaque = self:GetButtonColor(isActive, isHovered, isDisabled)

    -- Determine border radius based on shape
    local radius
    if self.shape_ == "circular" then
        radius = self.props.borderRadius or (size / 2)
    elseif self.shape_ == "square" then
        radius = 0
    else  -- rounded
        radius = self.props.borderRadius or 6
    end

    -- Box shadow (skip for disabled buttons)
    local shadow = not isDisabled and (isActive and (self.props.activeButtonBoxShadow or self.props.buttonBoxShadow) or self.props.buttonBoxShadow)
    if shadow then
        for _, s in ipairs(shadow) do
            if s.color then
                local sx = x + (s.x or 0)
                local sy = y + (s.y or 0)
                local sblur = s.blur or 0
                if sblur > 0 then
                    -- Blurred shadow using nvgBoxGradient (matches Widget base behavior)
                    local spread = sblur * 2
                    local paint = nvgBoxGradient(nvg,
                        sx, sy, size, size,
                        radius + sblur * 0.5, sblur,
                        nvgRGBA(s.color[1], s.color[2], s.color[3], s.color[4] or 255),
                        nvgRGBA(0, 0, 0, 0)
                    )
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - spread, sy - spread, size + spread * 2, size + spread * 2)
                    nvgFillPaint(nvg, paint)
                    nvgFill(nvg)
                else
                    -- Hard shadow (no blur)
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, sx, sy, size, size, radius)
                    nvgFillColor(nvg, nvgRGBA(s.color[1], s.color[2], s.color[3], s.color[4] or 255))
                    nvgFill(nvg)
                end
            end
        end
    end

    -- Determine border properties
    local borderColor
    if self.variant_ == "outlined" then
        if isActive then
            local activeBorderColor = self.props.activeBorderColor
            borderColor = activeBorderColor or Theme.Color(self.color_)
        else
            borderColor = Theme.Color("border")
        end
    end

    -- Hover border highlight (state token)
    if isHovered and not isActive and not isDisabled then
        local hoverBorderColor = self.props.hoverBorderColor
        if hoverBorderColor then
            borderColor = hoverBorderColor
        end
    end

    -- Parse border widths
    local tw, rw_, bw, lw = 0, 0, 0, 0
    if borderColor then
        local bbw = self.props.buttonBorderWidth or 1
        if type(bbw) == "table" then
            if #bbw == 1 then
                tw, rw_, bw, lw = bbw[1], bbw[1], bbw[1], bbw[1]
            elseif #bbw == 2 then
                tw, bw = bbw[1], bbw[1]
                rw_, lw = bbw[2], bbw[2]
            elseif #bbw == 3 then
                tw, rw_, lw, bw = bbw[1], bbw[2], bbw[2], bbw[3]
            else
                tw, rw_, bw, lw = bbw[1], bbw[2], bbw[3], bbw[4]
            end
        else
            tw, rw_, bw, lw = bbw, bbw, bbw, bbw
        end
    end

    -- Draw background + border
    if borderColor and (tw > 0 or rw_ > 0 or bw > 0 or lw > 0) and bgOpaque then
        -- Opaque bg: use "outer fill + inset bg" (doesn't extend outside button, preserves shadow)
        local bc = nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, size, size, radius)
        nvgFillColor(nvg, bc)
        nvgFill(nvg)

        local inX = x + lw
        local inY = y + tw
        local inW = size - lw - rw_
        local inH = size - tw - bw
        if inW > 0 and inH > 0 then
            local rTL = math.max(0, radius - math.max(tw, lw))
            local rTR = math.max(0, radius - math.max(tw, rw_))
            local rBR = math.max(0, radius - math.max(bw, rw_))
            local rBL = math.max(0, radius - math.max(bw, lw))
            nvgBeginPath(nvg)
            nvgRoundedRectVarying(nvg, inX, inY, inW, inH, rTL, rTR, rBR, rBL)
            nvgFillColor(nvg, bgColor)
            nvgFill(nvg)
        end
    else
        -- Transparent bg or no border: same layout as "outer fill + inset bg" for consistency
        if borderColor and (tw > 0 or rw_ > 0 or bw > 0 or lw > 0) then
            -- Border stroke (inset so outer edge = button bounds)
            local bc = nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255)
            local inset = tw / 2
            local inRadius = math.max(0, radius - inset)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x + inset, y + inset, size - tw, size - tw, inRadius)
            nvgStrokeColor(nvg, bc)
            nvgStrokeWidth(nvg, tw)
            nvgStroke(nvg)

            -- Bg fill inside border (same inset as "outer fill + inset bg" mode)
            local inX = x + lw
            local inY = y + tw
            local inW = size - lw - rw_
            local inH = size - tw - bw
            if inW > 0 and inH > 0 then
                local rTL = math.max(0, radius - math.max(tw, lw))
                local rTR = math.max(0, radius - math.max(tw, rw_))
                local rBR = math.max(0, radius - math.max(bw, rw_))
                local rBL = math.max(0, radius - math.max(bw, lw))
                nvgBeginPath(nvg)
                nvgRoundedRectVarying(nvg, inX, inY, inW, inH, rTL, rTR, rBR, rBL)
                nvgFillColor(nvg, bgColor)
                nvgFill(nvg)
            end
        else
            -- No border: fill entire button
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y, size, size, radius)
            nvgFillColor(nvg, bgColor)
            nvgFill(nvg)
        end
    end

    -- Draw text/icon
    local fontWeight = isActive and (self.props.activeFontWeight or self.props.fontWeight) or self.props.fontWeight
    nvgFontSize(nvg, fontSize)
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, textColor)

    if isArrow then
        -- Draw arrow icons
        local cx = x + size / 2
        local cy = y + size / 2
        local arrowSize = fontSize * 0.4

        nvgBeginPath(nvg)
        if text == "first" then
            nvgMoveTo(nvg, cx + arrowSize * 0.5, cy - arrowSize)
            nvgLineTo(nvg, cx - arrowSize * 0.5, cy)
            nvgLineTo(nvg, cx + arrowSize * 0.5, cy + arrowSize)
            nvgMoveTo(nvg, cx - arrowSize * 0.3, cy - arrowSize)
            nvgLineTo(nvg, cx - arrowSize * 0.3, cy + arrowSize)
        elseif text == "last" then
            nvgMoveTo(nvg, cx - arrowSize * 0.5, cy - arrowSize)
            nvgLineTo(nvg, cx + arrowSize * 0.5, cy)
            nvgLineTo(nvg, cx - arrowSize * 0.5, cy + arrowSize)
            nvgMoveTo(nvg, cx + arrowSize * 0.3, cy - arrowSize)
            nvgLineTo(nvg, cx + arrowSize * 0.3, cy + arrowSize)
        elseif text == "prev" then
            nvgMoveTo(nvg, cx + arrowSize * 0.3, cy - arrowSize)
            nvgLineTo(nvg, cx - arrowSize * 0.3, cy)
            nvgLineTo(nvg, cx + arrowSize * 0.3, cy + arrowSize)
        elseif text == "next" then
            nvgMoveTo(nvg, cx - arrowSize * 0.3, cy - arrowSize)
            nvgLineTo(nvg, cx + arrowSize * 0.3, cy)
            nvgLineTo(nvg, cx - arrowSize * 0.3, cy + arrowSize)
        end
        nvgStrokeColor(nvg, textColor)
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    else
        nvgText(nvg, x + size / 2, y + size / 2, text)
    end

    return size
end

-- ============================================================================
-- Render
-- ============================================================================

function Pagination:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()

    -- Render background (if any)
    Widget.Render(self, nvg)

    -- Size values (no scale needed - nvgScale handles it)
    local buttonSize = self.buttonSize_
    local gap = self.gap_
    local fontSize = Theme.FontSize(SIZE_PRESETS[self.size_].fontSize)

    local currentX = x
    local buttonY = y + (h - buttonSize) / 2

    -- Store button positions for hit testing
    self.buttonPositions_ = {}

    local isFirst = self:IsFirstPage()
    local isLast = self:IsLastPage()

    -- First button
    if self.showFirstButton_ then
        local isDisabled = self.disabled_ or isFirst
        if not (self.hideDisabled_ and isDisabled) then
            local isHovered = self.hoverIndex_ == "first"
            self:DrawButtonScaled(nvg, currentX, buttonY, "first", false, isHovered, isDisabled, true, buttonSize, fontSize)
            table.insert(self.buttonPositions_, {
                x1 = currentX,
                x2 = currentX + buttonSize,
                action = "first",
                disabled = isDisabled,
            })
            currentX = currentX + buttonSize + gap
        end
    end

    -- Previous button
    if self.showPrevNext_ then
        local isDisabled = self.disabled_ or isFirst
        if not (self.hideDisabled_ and isDisabled) then
            local isHovered = self.hoverIndex_ == "prev"
            self:DrawButtonScaled(nvg, currentX, buttonY, "prev", false, isHovered, isDisabled, true, buttonSize, fontSize)
            table.insert(self.buttonPositions_, {
                x1 = currentX,
                x2 = currentX + buttonSize,
                action = "prev",
                disabled = isDisabled,
            })
            currentX = currentX + buttonSize + gap
        end
    end

    -- Page buttons
    local pageRange = self:GetPageRange()
    for _, page in ipairs(pageRange) do
        if page == "..." then
            -- Ellipsis
            nvgFontSize(nvg, fontSize)
            nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
            nvgText(nvg, currentX + buttonSize / 2, buttonY + buttonSize / 2, "...")
            currentX = currentX + buttonSize + gap
        else
            local isActive = page == self.currentPage_
            local isHovered = self.hoverIndex_ == page
            local isDisabled = self.disabled_

            self:DrawButtonScaled(nvg, currentX, buttonY, tostring(page), isActive, isHovered, isDisabled, false, buttonSize, fontSize)
            table.insert(self.buttonPositions_, {
                x1 = currentX,
                x2 = currentX + buttonSize,
                action = "page",
                page = page,
                disabled = isDisabled,
            })
            currentX = currentX + buttonSize + gap
        end
    end

    -- Next button
    if self.showPrevNext_ then
        local isDisabled = self.disabled_ or isLast
        if not (self.hideDisabled_ and isDisabled) then
            local isHovered = self.hoverIndex_ == "next"
            self:DrawButtonScaled(nvg, currentX, buttonY, "next", false, isHovered, isDisabled, true, buttonSize, fontSize)
            table.insert(self.buttonPositions_, {
                x1 = currentX,
                x2 = currentX + buttonSize,
                action = "next",
                disabled = isDisabled,
            })
            currentX = currentX + buttonSize + gap
        end
    end

    -- Last button
    if self.showLastButton_ then
        local isDisabled = self.disabled_ or isLast
        if not (self.hideDisabled_ and isDisabled) then
            local isHovered = self.hoverIndex_ == "last"
            self:DrawButtonScaled(nvg, currentX, buttonY, "last", false, isHovered, isDisabled, true, buttonSize, fontSize)
            table.insert(self.buttonPositions_, {
                x1 = currentX,
                x2 = currentX + buttonSize,
                action = "last",
                disabled = isDisabled,
            })
        end
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Pagination:GetButtonAtPosition(screenX, screenY)
    if not self.buttonPositions_ then return nil end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y

    -- Convert screen coords to render coords
    local px = screenX + offsetX
    local py = screenY + offsetY

    local w, h = self:GetComputedSize()
    local buttonSize = self.buttonSize_
    local buttonY = renderY + (h - buttonSize) / 2

    if py < buttonY or py > buttonY + buttonSize then
        return nil
    end

    for _, pos in ipairs(self.buttonPositions_) do
        if px >= pos.x1 and px <= pos.x2 then
            return pos
        end
    end

    return nil
end

function Pagination:OnPointerMove(event)
    if not event then return end

    local button = self:GetButtonAtPosition(event.x, event.y)

    if button and not button.disabled then
        if button.action == "page" then
            self.hoverIndex_ = button.page
        else
            self.hoverIndex_ = button.action
        end
    else
        self.hoverIndex_ = nil
    end
end

function Pagination:OnPointerLeave(event)
    self.hoverIndex_ = nil
end

function Pagination:OnClick(event)
    if not event then return end

    local button = self:GetButtonAtPosition(event.x, event.y)

    if button and not button.disabled then
        if button.action == "first" then
            self:GoToFirst()
        elseif button.action == "last" then
            self:GoToLast()
        elseif button.action == "prev" then
            self:GoToPrev()
        elseif button.action == "next" then
            self:GoToNext()
        elseif button.action == "page" then
            self:SetCurrentPage(button.page)
        end
    end
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a simple pagination
---@param totalPages number Total number of pages
---@param currentPage number|nil Current page (default 1)
---@param props table|nil Additional props
---@return Pagination
function Pagination.Simple(totalPages, currentPage, props)
    props = props or {}
    props.totalPages = totalPages
    props.currentPage = currentPage or 1
    props.siblingCount = 1
    props.boundaryCount = 1
    return Pagination(props)
end

--- Create a compact pagination (prev/next only)
---@param totalPages number Total number of pages
---@param currentPage number|nil Current page
---@param props table|nil Additional props
---@return Pagination
function Pagination.Compact(totalPages, currentPage, props)
    props = props or {}
    props.totalPages = totalPages
    props.currentPage = currentPage or 1
    props.siblingCount = 0
    props.boundaryCount = 0
    return Pagination(props)
end

--- Create a full-featured pagination
---@param totalPages number Total number of pages
---@param currentPage number|nil Current page
---@param props table|nil Additional props
---@return Pagination
function Pagination.Full(totalPages, currentPage, props)
    props = props or {}
    props.totalPages = totalPages
    props.currentPage = currentPage or 1
    props.showFirstButton = true
    props.showLastButton = true
    props.siblingCount = 2
    props.boundaryCount = 1
    return Pagination(props)
end

--- Create pagination for table/list data
---@param totalItems number Total number of items
---@param itemsPerPage number Items per page
---@param currentPage number|nil Current page
---@param props table|nil Additional props
---@return Pagination
function Pagination.ForData(totalItems, itemsPerPage, currentPage, props)
    props = props or {}
    props.totalPages = math.ceil(totalItems / itemsPerPage)
    props.currentPage = currentPage or 1
    return Pagination(props)
end

return Pagination
