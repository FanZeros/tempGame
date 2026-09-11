-- ============================================================================
-- RichText Widget
-- UrhoX UI Library - Rich text display with extensible tag support
--
-- Features:
--   - Built-in tags: <b>, <i>, <color>, <size>, <br>
--   - Game tags: <item>, <link>, <emoji>, <img>
--   - Extensible via registerTag()
--   - Clickable segments with callbacks
--   - Auto-height calculation
--   - Inline images/sprites
--
-- IMPORTANT: Yoga uses border-box model!
-- When setting explicit width, padding is INSIDE the width.
-- This widget correctly handles padding by inset text rendering.
-- See: 3rd/yoga/website/docs/styling/width-height.mdx
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")
local UI = require("urhox-libs/UI/Core/UI")

---@class RichTextProps : WidgetProps
---@field content? string Text content with tags
---@field fontSize? number Base font size (default: 14)
---@field lineHeight? number Line height multiplier (default: 1.4)
---@field fontColor? RGBAColor|string Default text color RGBA
---@field linkColor? RGBAColor|string Link text color RGBA
---@field wrapWidth? number Max width before wrapping (default: container width)
---@field onLinkClick? fun(url: string, text: string) Link click callback
---@field onItemClick? fun(item: table, bounds: table) Item click callback
---@field itemResolver? fun(id: any): table|nil Function to resolve item data by ID
---@field emojiResolver? fun(name: string): table|nil Function to resolve emoji data by name

---@class RichText : Widget
---@overload fun(props?: RichTextProps): RichText
---@field props RichTextProps
---@field new fun(self, props?: RichTextProps): RichText
local RichText = Widget:Extend("RichText")

-- ============================================================================
-- Segment Types
-- ============================================================================

local SEGMENT = {
    TEXT = "text",
    BOLD = "bold",
    ITALIC = "italic",
    COLOR = "color",
    SIZE = "size",
    LINK = "link",
    ITEM = "item",
    EMOJI = "emoji",
    IMAGE = "image",
    LINEBREAK = "linebreak",
}

-- ============================================================================
-- Default Item Rarity Colors
-- ============================================================================

local RARITY_COLORS = {
    common = { 200, 200, 200, 255 },
    uncommon = { 100, 255, 100, 255 },
    rare = { 100, 150, 255, 255 },
    epic = { 180, 100, 255, 255 },
    legendary = { 255, 180, 80, 255 },
}

-- ============================================================================
-- Custom Tag Registry (static)
-- ============================================================================

local customTags_ = {}

--- Register a custom tag parser
---@param tagName string Tag name (e.g., "quest", "player")
---@param parser function(tagContent, fullContent, afterTag) Returns segment, newPos
function RichText.RegisterTag(tagName, parser)
    customTags_[tagName] = parser
end

--- Unregister a custom tag
---@param tagName string
function RichText.UnregisterTag(tagName)
    customTags_[tagName] = nil
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props RichTextProps?
function RichText:Init(props)
    props = props or {}

    -- Defaults
    props.fontSize = props.fontSize or 14
    props.lineHeight = props.lineHeight or 1.4
    props.fontColor = props.fontColor or { 255, 255, 255, 255 }
    props.linkColor = props.linkColor or { 100, 180, 255, 255 }

    -- Internal state
    self.segments_ = {}
    self.clickableBounds_ = {}
    self.hoveredSegment_ = nil
    self.contentHeight_ = 0
    self.lastWidth_ = 0
    self.fontVersion_ = UI.GetFontVersion()

    -- Expand padding shorthand before reading padding values
    -- (Widget.Init calls this again, but it's idempotent)
    Widget.ExpandPaddingShorthand(props)

    -- Calculate padding for height calculation
    -- IMPORTANT: Yoga uses border-box model, height must include padding
    local pt = props.paddingTop or 0
    local pb = props.paddingBottom or 0

    -- Auto-calculate initial height if not specified
    -- Minimum height = one line + vertical padding (for border-box model)
    if not props.height then
        local fontSize = props.fontSize or 14
        local lineHeight = props.lineHeight or 1.4
        props.height = math.ceil(fontSize * lineHeight) + pt + pb
    end

    Widget.Init(self, props)

    -- Parse content
    if props.content then
        self:SetContent(props.content)
    end
end

-- ============================================================================
-- Content Management
-- ============================================================================

--- Set content and parse tags
---@param content string
function RichText:SetContent(content)
    self.props.content = content or ""
    self.segments_ = self:ParseContent(content or "")
    self.contentHeight_ = 0  -- Force recalculation
end

--- Get raw content
---@return string
function RichText:GetContent()
    return self.props.content or ""
end

--- Get parsed segments
---@return table[]
function RichText:GetSegments()
    return self.segments_
end

-- ============================================================================
-- Tag Parser
-- ============================================================================

--- Parse content string into segments
---@param content string
---@return table[] segments
function RichText:ParseContent(content)
    if not content or #content == 0 then
        return {}
    end

    local segments = {}
    local pos = 1
    local len = #content

    -- Style stack for nested tags
    local styleStack = {}

    while pos <= len do
        -- Find next tag
        local tagStart = content:find("<", pos)

        if not tagStart then
            -- No more tags, add remaining text
            local text = content:sub(pos)
            if #text > 0 then
                table.insert(segments, self:CreateTextSegment(text, styleStack))
            end
            break
        end

        -- Add text before tag
        if tagStart > pos then
            local text = content:sub(pos, tagStart - 1)
            if #text > 0 then
                table.insert(segments, self:CreateTextSegment(text, styleStack))
            end
        end

        -- Check for closing tag
        local closingTag = content:match("^</(%w+)>", tagStart)
        if closingTag then
            -- Pop style from stack
            for i = #styleStack, 1, -1 do
                if styleStack[i].tag == closingTag then
                    table.remove(styleStack, i)
                    break
                end
            end
            pos = tagStart + #closingTag + 3  -- </tag>
        else
            -- Parse opening tag
            local tagEnd = content:find(">", tagStart)
            if not tagEnd then
                -- Malformed tag, treat as text
                table.insert(segments, self:CreateTextSegment(content:sub(tagStart), styleStack))
                break
            end

            local tagContent = content:sub(tagStart + 1, tagEnd - 1)
            local segment, newPos, pushStyle = self:ParseTag(tagContent, content, tagEnd + 1, styleStack)

            if segment then
                table.insert(segments, segment)
            end

            if pushStyle then
                table.insert(styleStack, pushStyle)
            end

            pos = newPos
        end
    end

    return segments
end

--- Create a text segment with current style
---@param text string
---@param styleStack table[]
---@return table
function RichText:CreateTextSegment(text, styleStack)
    local segment = {
        type = SEGMENT.TEXT,
        text = text,
    }

    -- Apply styles from stack
    for _, style in ipairs(styleStack) do
        if style.tag == "b" then
            segment.bold = true
        elseif style.tag == "i" then
            segment.italic = true
        elseif style.tag == "color" then
            segment.color = style.value
        elseif style.tag == "size" then
            segment.size = style.value
        end
    end

    return segment
end

--- Parse a single tag
---@param tagContent string Content inside < >
---@param fullContent string Full content string
---@param afterTag number Position after the opening tag
---@param styleStack table[] Current style stack
---@return table|nil segment, number newPos, table|nil pushStyle
function RichText:ParseTag(tagContent, fullContent, afterTag, styleStack)
    -- Self-closing tags first

    -- <br> or <br/>
    if tagContent:match("^br/?$") then
        return { type = SEGMENT.LINEBREAK }, afterTag, nil
    end

    -- <img src="..." width=X height=Y>
    local imgSrc = tagContent:match("^img%s+src=\"([^\"]+)\"") or
                   tagContent:match("^img%s+src=([^%s>]+)")
    if imgSrc then
        local imgWidth = tonumber(tagContent:match("width=(%d+)"))
        local imgHeight = tonumber(tagContent:match("height=(%d+)"))
        return {
            type = SEGMENT.IMAGE,
            src = imgSrc,
            width = imgWidth or 32,
            height = imgHeight or 32,
        }, afterTag, nil
    end

    -- <item id=123>
    local itemId = tagContent:match("^item%s+id=(%d+)") or
                   tagContent:match("^item%s+id=\"([^\"]+)\"")
    if itemId then
        local item = self:ResolveItem(itemId)
        return {
            type = SEGMENT.ITEM,
            id = itemId,
            name = item and item.name or ("[Item:" .. itemId .. "]"),
            icon = item and item.icon,
            rarity = item and item.rarity or "common",
            description = item and item.description,
            data = item,
        }, afterTag, nil
    end

    -- <emoji name=X>
    local emojiName = tagContent:match("^emoji%s+name=\"([^\"]+)\"") or
                      tagContent:match("^emoji%s+name=([%w_]+)")
    if emojiName then
        local emoji = self:ResolveEmoji(emojiName)
        return {
            type = SEGMENT.EMOJI,
            name = emojiName,
            image = emoji and emoji.image,
            text = emoji and emoji.text or (":" .. emojiName .. ":"),
        }, afterTag, nil
    end

    -- Paired tags with content

    -- <link url="...">text</link>
    local linkUrl = tagContent:match("^link%s+url=\"([^\"]+)\"") or
                    tagContent:match("^link%s+url=([^%s>]+)")
    if linkUrl then
        local closeStart, closeEnd = fullContent:find("</link>", afterTag)
        local linkText
        if closeStart then
            linkText = fullContent:sub(afterTag, closeStart - 1)
            afterTag = closeEnd + 1
        else
            linkText = linkUrl
        end
        return {
            type = SEGMENT.LINK,
            url = linkUrl,
            text = linkText,
        }, afterTag, nil
    end

    -- Style tags that push to stack

    -- <b>
    if tagContent == "b" then
        return nil, afterTag, { tag = "b" }
    end

    -- <i>
    if tagContent == "i" then
        return nil, afterTag, { tag = "i" }
    end

    -- <color=#RRGGBB> or <color=red>
    local colorValue = tagContent:match("^color=([^%s>]+)")
    if colorValue then
        local color = self:ParseColor(colorValue)
        return nil, afterTag, { tag = "color", value = color }
    end

    -- <size=N>
    local sizeValue = tagContent:match("^size=(%d+)")
    if sizeValue then
        return nil, afterTag, { tag = "size", value = tonumber(sizeValue) }
    end

    -- Check custom tags
    for tagName, parser in pairs(customTags_) do
        if tagContent:match("^" .. tagName) then
            local segment, newPos = parser(tagContent, fullContent, afterTag, self)
            if segment then
                return segment, newPos, nil
            end
        end
    end

    -- Unknown tag, treat as text
    return { type = SEGMENT.TEXT, text = "<" .. tagContent .. ">" }, afterTag, nil
end

--- Parse color string
---@param colorStr string e.g., "#FF0000", "red", "255,0,0"
---@return table RGBA
function RichText:ParseColor(colorStr)
    -- Hex color
    if colorStr:match("^#%x%x%x%x%x%x$") then
        local r = tonumber(colorStr:sub(2, 3), 16)
        local g = tonumber(colorStr:sub(4, 5), 16)
        local b = tonumber(colorStr:sub(6, 7), 16)
        return { r, g, b, 255 }
    end

    -- Named colors
    local namedColors = {
        red = { 255, 0, 0, 255 },
        green = { 0, 255, 0, 255 },
        blue = { 0, 0, 255, 255 },
        yellow = { 255, 255, 0, 255 },
        white = { 255, 255, 255, 255 },
        black = { 0, 0, 0, 255 },
        gray = { 128, 128, 128, 255 },
        orange = { 255, 165, 0, 255 },
        purple = { 128, 0, 128, 255 },
        cyan = { 0, 255, 255, 255 },
    }
    if namedColors[colorStr] then
        return namedColors[colorStr]
    end

    -- RGB format: "255,0,0"
    local r, g, b = colorStr:match("(%d+),(%d+),(%d+)")
    if r then
        return { tonumber(r), tonumber(g), tonumber(b), 255 }
    end

    return { 255, 255, 255, 255 }
end

-- ============================================================================
-- Resolvers
-- ============================================================================

--- Resolve item by ID
---@param id any
---@return table|nil
function RichText:ResolveItem(id)
    if self.props.itemResolver then
        return self.props.itemResolver(tonumber(id) or id)
    end
    return nil
end

--- Resolve emoji by name
---@param name string
---@return table|nil { image, text }
function RichText:ResolveEmoji(name)
    if self.props.emojiResolver then
        return self.props.emojiResolver(name)
    end
    -- Default emoji mapping
    local defaultEmojis = {
        smile = { text = "😊" },
        laugh = { text = "😂" },
        sad = { text = "😢" },
        angry = { text = "😠" },
        heart = { text = "❤" },
        star = { text = "⭐" },
        fire = { text = "🔥" },
        thumbsup = { text = "👍" },
    }
    return defaultEmojis[name]
end

-- ============================================================================
-- Layout Calculation
-- ============================================================================

--- Measure total content width (single line, no wrapping)
---@return number width in base pixels
function RichText:MeasureWidth()
    local fontSize = self.props.fontSize
    local emojiSize = fontSize * 1.2

    local width = 0

    for _, seg in ipairs(self.segments_) do
        if seg.type == SEGMENT.TEXT then
            local size = seg.size or self.props.fontSize
            width = width + UI.MeasureTextWidth(seg.text, size, "sans")
        elseif seg.type == SEGMENT.ITEM then
            local iconWidth = seg.icon and (emojiSize + 2) or 0
            local displayText = "[" .. (seg.name or "???") .. "]"
            width = width + iconWidth + UI.MeasureTextWidth(displayText, fontSize, "sans") + 4
        elseif seg.type == SEGMENT.LINK then
            width = width + UI.MeasureTextWidth(seg.text or "", fontSize, "sans") + 2
        elseif seg.type == SEGMENT.EMOJI then
            width = width + emojiSize
        elseif seg.type == SEGMENT.IMAGE then
            width = width + (seg.width or 32)
        end
    end

    return width
end

--- Calculate content height for given width
---@param maxWidth number
---@return number height
function RichText:CalculateHeight(maxWidth)
    local fontSize = self.props.fontSize
    local lineHeight = fontSize * self.props.lineHeight
    local emojiSize = fontSize * 1.2

    local x = 0
    local height = lineHeight  -- At least one line

    for _, seg in ipairs(self.segments_) do
        local segWidth = 0

        if seg.type == SEGMENT.TEXT then
            local size = seg.size or self.props.fontSize
            -- Use actual text measurement for accuracy
            segWidth = UI.MeasureTextWidth(seg.text, size, "sans")
            local availableWidth = maxWidth - x

            if segWidth <= availableWidth then
                -- Fits on current line
                x = x + segWidth
            else
                -- Text needs wrapping
                if x > 0 then
                    -- Move to new line first
                    height = height + lineHeight
                    x = 0
                end
                -- Calculate number of lines needed
                local numLines = math.ceil(segWidth / maxWidth)
                height = height + (numLines - 1) * lineHeight
                -- After multi-line text, start fresh on next line
                height = height + lineHeight
                x = 0
            end
            goto continue
        elseif seg.type == SEGMENT.ITEM then
            segWidth = emojiSize + #(seg.name or "") * fontSize * 0.5 + 8
        elseif seg.type == SEGMENT.LINK then
            segWidth = #(seg.text or "") * fontSize * 0.5
        elseif seg.type == SEGMENT.EMOJI then
            segWidth = emojiSize
        elseif seg.type == SEGMENT.IMAGE then
            -- Images on their own line
            if x > 0 then
                height = height + lineHeight
                x = 0
            end
            height = height + (seg.height or 32) + 4
            goto continue
        elseif seg.type == SEGMENT.LINEBREAK then
            height = height + lineHeight
            x = 0
            goto continue
        end

        -- Check wrap for non-TEXT segments
        if x + segWidth > maxWidth and x > 0 then
            height = height + lineHeight
            x = 0
        end
        x = x + segWidth

        ::continue::
    end

    return height
end

--- Calculate total height including padding (for border-box model)
---@param maxWidth number|nil Content width (defaults to current layout width - padding)
---@return number Total height including padding
function RichText:CalculateTotalHeight(maxWidth)
    local props = self.props
    local pt = props.paddingTop or 0
    local pb = props.paddingBottom or 0
    local pl = props.paddingLeft or 0
    local pr = props.paddingRight or 0

    -- If maxWidth not provided, try to get from layout
    if not maxWidth then
        local l = self:GetLayout()
        if l and l.w > 0 then
            -- layout.w is border-box, content width = layout.w - padding
            maxWidth = l.w - pl - pr
        else
            -- Fallback: use wrapWidth or a default
            maxWidth = props.wrapWidth or 300
        end
    end
    
    local contentHeight = self:CalculateHeight(maxWidth)
    return contentHeight + pt + pb
end

--- Update height after content change (for auto-height support)
function RichText:UpdateHeight()
    local newHeight = self:CalculateTotalHeight()
    self:SetHeight(newHeight)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function RichText:Render(nvg)
    local layout = self:GetAbsoluteLayout()

    -- Support renderOffset pattern for inline rendering (e.g., ChatWindow)
    if self.renderOffsetX_ then
        layout = {
            x = self.renderOffsetX_,
            y = self.renderOffsetY_ or 0,
            w = self.renderWidth_ or (layout and layout.w) or 0,
            h = self.renderHeight_ or (layout and layout.h) or 0,
        }
    end

    if not layout or layout.w <= 0 then return end

    -- DWP font reload: clear height cache so auto-height recalculates with new font metrics
    local curFontVer = UI.GetFontVersion()
    if self.fontVersion_ ~= curFontVer then
        self.fontVersion_ = curFontVer
        self.contentHeight_ = 0
        self.lastWidth_ = 0  -- Force height recalc below
    end

    -- Auto-height: check if height needs update based on content
    -- Only if not using renderOffset (which means we control our own layout)
    if not self.renderOffsetX_ and self.lastWidth_ ~= layout.w then
        self.lastWidth_ = layout.w
        -- Recalculate height based on new width
        local newHeight = self:CalculateTotalHeight()
        if newHeight > 0 and math.abs(newHeight - layout.h) > 1 then
            self:SetHeight(newHeight)
            -- Layout will be recalculated next frame
        end
    end

    -- Background (skip if using renderOffset - parent handles background)
    if not self.renderOffsetX_ then
        self:RenderFullBackground(nvg)
    end

    local fontSize = self.props.fontSize
    local lineHeight = fontSize * self.props.lineHeight
    local emojiSize = fontSize * 1.2

    -- Calculate padding (Yoga border-box: layout includes padding, we need to inset content)
    local props = self.props
    local pl = props.paddingLeft or 0
    local pr = props.paddingRight or 0
    local pt = props.paddingTop or 0
    -- pb not used in rendering, only in height calculation (CalculateTotalHeight)

    -- Calculate content area (inset by padding)
    local contentX = layout.x + pl
    local contentY = layout.y + pt
    local contentW = layout.w - pl - pr

    -- Use the smaller of wrapWidth and contentW to prevent overflow
    local maxWidth
    local wrapWidth = self.props.wrapWidth
    -- Handle NaN: wrapWidth ~= wrapWidth is true only for NaN
    if wrapWidth and wrapWidth == wrapWidth then
        maxWidth = math.min(wrapWidth, contentW)
    else
        maxWidth = contentW
    end

    local x = contentX
    local y = contentY
    local startX = x

    self.clickableBounds_ = {}
    local segIdx = 0

    for _, seg in ipairs(self.segments_) do
        segIdx = segIdx + 1
        local segId = tostring(segIdx)

        if seg.type == SEGMENT.TEXT then
            local size = seg.size or self.props.fontSize
            local color = seg.color or self.props.fontColor

            nvgFontSize(nvg, size)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))

            local text = seg.text
            local textWidth = nvgTextBounds(nvg, 0, 0, text) or (#text * size * 0.5)
            local availableWidth = maxWidth - (x - startX)

            -- If text fits in remaining space, render inline
            if textWidth <= availableWidth then
                nvgText(nvg, x, y, text)
                x = x + textWidth
            else
                -- Text needs wrapping - use nvgTextBox
                -- If not at line start, move to next line first for clean wrapping
                if x > startX then
                    y = y + lineHeight
                    x = startX
                end

                -- Debug: print wrap info
                print(string.format("[RichText] Wrapping text: width=%.1f, maxWidth=%.1f, x=%.1f, y=%.1f", textWidth, maxWidth, x, y))

                -- Render with nvgTextBox for automatic line breaking
                nvgTextBox(nvg, x, y, maxWidth, text)

                -- Get actual rendered bounds to calculate height
                local bounds = nvgTextBoxBounds(nvg, x, y, maxWidth, text)
                if bounds and bounds[4] and bounds[2] then
                    local textBoxHeight = bounds[4] - bounds[2]
                    -- Move y to after the text box
                    y = y + textBoxHeight
                else
                    -- Fallback: estimate based on text width
                    local numLines = math.max(1, math.ceil(textWidth / maxWidth))
                    y = y + numLines * lineHeight
                end
                x = startX
            end

        elseif seg.type == SEGMENT.ITEM then
            local rarityColor = RARITY_COLORS[seg.rarity] or RARITY_COLORS.common
            local isHovered = (self.hoveredSegment_ == segId)

            -- Calculate item width first for pre-wrap check
            local displayText = "[" .. (seg.name or "???") .. "]"
            nvgFontSize(nvg, fontSize)
            local textWidth = nvgTextBounds(nvg, 0, 0, displayText) or (#displayText * fontSize * 0.5)
            local iconWidth = seg.icon and (emojiSize + 2) or 0
            local itemWidth = iconWidth + textWidth + 4

            -- Pre-wrap check
            if x - startX + itemWidth > maxWidth and x > startX then
                y = y + lineHeight
                x = startX
            end

            local itemStartX = x

            -- Icon
            if seg.icon then
                nvgFontSize(nvg, emojiSize)
                nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
                nvgText(nvg, x, y + lineHeight / 2, seg.icon)
                x = x + emojiSize + 2
            end

            -- Name with brackets
            nvgFontSize(nvg, fontSize)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if isHovered then
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
            else
                nvgFillColor(nvg, nvgRGBA(rarityColor[1], rarityColor[2], rarityColor[3], rarityColor[4]))
            end
            nvgText(nvg, x, y, displayText)

            -- Store clickable bounds
            self.clickableBounds_[segId] = {
                x = itemStartX,
                y = y,
                w = x - itemStartX + textWidth,
                h = lineHeight,
                type = "item",
                data = seg,
            }

            x = x + textWidth + 4

        elseif seg.type == SEGMENT.LINK then
            local linkColor = self.props.linkColor
            local isHovered = (self.hoveredSegment_ == segId)

            -- Calculate link width for pre-wrap check
            nvgFontSize(nvg, fontSize)
            local textWidth = nvgTextBounds(nvg, 0, 0, seg.text) or (#seg.text * fontSize * 0.5)

            -- Pre-wrap check
            if x - startX + textWidth > maxWidth and x > startX then
                y = y + lineHeight
                x = startX
            end

            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if isHovered then
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
            else
                nvgFillColor(nvg, nvgRGBA(linkColor[1], linkColor[2], linkColor[3], linkColor[4]))
            end
            nvgText(nvg, x, y, seg.text)

            -- Underline
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x, y + lineHeight - 2)
            nvgLineTo(nvg, x + textWidth, y + lineHeight - 2)
            nvgStrokeColor(nvg, nvgRGBA(linkColor[1], linkColor[2], linkColor[3], linkColor[4]))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)

            -- Store clickable bounds
            self.clickableBounds_[segId] = {
                x = x,
                y = y,
                w = textWidth,
                h = lineHeight,
                type = "link",
                data = seg,
            }

            x = x + textWidth + 2

        elseif seg.type == SEGMENT.EMOJI then
            -- Pre-wrap check for emoji
            if x - startX + emojiSize > maxWidth and x > startX then
                y = y + lineHeight
                x = startX
            end

            nvgFontSize(nvg, emojiSize)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
            nvgText(nvg, x, y + lineHeight / 2, seg.text or "?")
            x = x + emojiSize

        elseif seg.type == SEGMENT.IMAGE then
            -- New line for images
            if x > startX then
                y = y + lineHeight
                x = startX
            end
            local imgW = seg.width or 32
            local imgH = seg.height or 32

            -- Try to render actual image
            local imgHandle = seg.src and ImageCache.Get(seg.src)
            if imgHandle and imgHandle > 0 then
                local imgPaint = nvgImagePattern(nvg, x, y, imgW, imgH, 0, imgHandle, 1)
                nvgBeginPath(nvg)
                nvgRect(nvg, x, y, imgW, imgH)
                nvgFillPaint(nvg, imgPaint)
                nvgFill(nvg)
            else
                -- Placeholder
                nvgBeginPath(nvg)
                nvgRect(nvg, x, y, imgW, imgH)
                nvgFillColor(nvg, nvgRGBA(60, 60, 70, 255))
                nvgFill(nvg)
                nvgFontSize(nvg, fontSize * 0.7)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(150, 150, 150, 255))
                nvgText(nvg, x + imgW / 2, y + imgH / 2, "[IMG]")
            end

            y = y + imgH + 4
            x = startX

        elseif seg.type == SEGMENT.LINEBREAK then
            y = y + lineHeight
            x = startX
        end

        -- Wrap check
        if x - startX > maxWidth then
            y = y + lineHeight
            x = startX
        end
    end

end

-- ============================================================================
-- Input Handling
-- ============================================================================

function RichText:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    self.hoveredSegment_ = nil
    for segId, bounds in pairs(self.clickableBounds_) do
        if event.x >= bounds.x and event.x <= bounds.x + bounds.w and
           event.y >= bounds.y and event.y <= bounds.y + bounds.h then
            self.hoveredSegment_ = segId
            break
        end
    end
end

function RichText:OnPointerLeave(event)
    Widget.OnPointerLeave(self, event)
    self.hoveredSegment_ = nil
end

function RichText:OnClick(event)
    for segId, bounds in pairs(self.clickableBounds_) do
        if event.x >= bounds.x and event.x <= bounds.x + bounds.w and
           event.y >= bounds.y and event.y <= bounds.y + bounds.h then

            if bounds.type == "item" and self.props.onItemClick then
                -- Pass bounds for tooltip positioning
                self.props.onItemClick(bounds.data, bounds)
                return true
            elseif bounds.type == "link" and self.props.onLinkClick then
                self.props.onLinkClick(bounds.data.url, bounds.data.text)
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create RichText with content
---@param content string
---@param props table|nil
---@return RichText
function RichText.Create(content, props)
    props = props or {}
    props.content = content
    return RichText(props)
end

return RichText
