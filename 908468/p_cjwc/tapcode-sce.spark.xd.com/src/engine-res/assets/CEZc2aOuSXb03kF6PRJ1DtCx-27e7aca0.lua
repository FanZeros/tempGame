-- ============================================================================
-- ChatWindow Component
-- UrhoX UI Library - MMO-style chat window
--
-- Features:
--   - Message list with scrolling
--   - Uses RichText for content rendering (tags, items, links, emojis)
--   - Auto-scroll to bottom
--   - Message bubbles with sender names
--   - Item tooltips on click
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local UI = require("urhox-libs/UI/Core/UI")
local RichText = require("urhox-libs/UI/Widgets/RichText")
local ItemTooltip = require("urhox-libs/UI/Components/ItemTooltip")

---@class ChatWindowProps : WidgetProps
---@field messages? table[] Initial messages
---@field maxMessages? number Maximum messages to keep (default: 100)
---@field fontSize? number Font size (default: 14)
---@field lineHeight? number Line height multiplier (default: 1.4)
---@field bubblePadding? number Padding inside bubbles (default: 8)
---@field messageGap? number Gap between messages (default: 8)
---@field onItemClick? fun(item: table) Item click callback
---@field onLinkClick? fun(url: string, text: string) Link click callback
---@field itemResolver? fun(id: string): table|nil Returns item data
---@field emojiResolver? fun(name: string): table|nil Returns emoji data

---@class ChatWindow : Widget
---@overload fun(props?: ChatWindowProps): ChatWindow
---@field props ChatWindowProps
---@field new fun(self, props?: ChatWindowProps): ChatWindow
local ChatWindow = Widget:Extend("ChatWindow")

-- ============================================================================
-- Default Colors
-- ============================================================================

local DEFAULT_COLORS = {
    bubble_self = { 70, 130, 180, 255 },
    bubble_other = { 50, 55, 65, 255 },
    bubble_system = { 80, 60, 80, 255 },
    text = { 255, 255, 255, 255 },
    text_system = { 200, 180, 220, 255 },
    name_self = { 150, 200, 255, 255 },
    name_other = { 180, 180, 180, 255 },
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ChatWindowProps?
function ChatWindow:Init(props)
    props = props or {}

    -- Defaults
    props.maxMessages = props.maxMessages or 100
    props.fontSize = props.fontSize or 14
    props.lineHeight = props.lineHeight or 1.4
    props.bubblePadding = props.bubblePadding or 8
    props.messageGap = props.messageGap or 8
    props.colors = props.colors or DEFAULT_COLORS

    -- Background
    props.backgroundColor = props.backgroundColor or { 25, 28, 35, 240 }
    props.borderRadius = props.borderRadius or 8

    -- Internal state
    self.messages_ = {}
    self.contentHeight_ = 0
    self.scrollOffset_ = 0
    self.autoScroll_ = true
    self.lastLayoutWidth_ = 0

    Widget.Init(self, props)

    -- Process initial messages
    if props.messages then
        for _, msg in ipairs(props.messages) do
            self:AddMessage(msg)
        end
    end
end

-- ============================================================================
-- Message Management
-- ============================================================================

--- Add a new message
---@param message table { sender, content, isSelf, isSystem }
function ChatWindow:AddMessage(message)
    local processed = {
        sender = message.sender or "Unknown",
        content = message.content or "",
        isSelf = message.isSelf or false,
        isSystem = message.isSystem or false,
        timestamp = message.timestamp,
        -- Layout info (calculated later)
        height = 0,
        y = 0,
        bubbleWidth = 0,
        richText = nil,  -- RichText widget instance
    }

    table.insert(self.messages_, processed)

    -- Trim old messages
    while #self.messages_ > self.props.maxMessages do
        local old = table.remove(self.messages_, 1)
        if old.richText then
            old.richText:Destroy()
        end
    end

    -- Recalculate layout
    self:RecalculateLayout()

    -- Auto-scroll to bottom
    if self.autoScroll_ then
        self:ScrollToBottom()
    end
end

--- Clear all messages
function ChatWindow:ClearMessages()
    for _, msg in ipairs(self.messages_) do
        if msg.richText then
            msg.richText:Destroy()
        end
    end
    self.messages_ = {}
    self.contentHeight_ = 0
    self.scrollOffset_ = 0
end

-- ============================================================================
-- Layout Calculation
-- ============================================================================

--- Recalculate layout for all messages
function ChatWindow:RecalculateLayout()
    local layout = self:GetLayout()
    if not layout or layout.w <= 0 then return end

    local padding = self.props.bubblePadding
    local gap = self.props.messageGap
    local fontSize = self.props.fontSize
    local lineHeight = fontSize * self.props.lineHeight
    local maxBubbleWidth = layout.w * 0.75

    local y = gap

    for _, msg in ipairs(self.messages_) do
        msg.y = y

        -- Create or update RichText for this message
        local contentWidth = maxBubbleWidth - padding * 2
        if not msg.richText then
            msg.richText = RichText {
                content = msg.content,
                fontSize = self.props.fontSize,
                lineHeight = self.props.lineHeight,
                fontColor = msg.isSystem and self.props.colors.text_system or self.props.colors.text,
                wrapWidth = contentWidth,
                itemResolver = self.props.itemResolver,
                emojiResolver = self.props.emojiResolver,
                onItemClick = function(item, bounds)
                    self:ShowItemTooltip(item, msg, bounds)
                    if self.props.onItemClick then
                        self.props.onItemClick(item)
                    end
                end,
                onLinkClick = self.props.onLinkClick,
            }
        end

        -- Calculate content height using RichText
        local contentHeight = msg.richText:CalculateHeight(contentWidth)

        -- Add sender name height for non-system messages
        local nameHeight = 0
        if not msg.isSystem then
            nameHeight = fontSize + 4
        end

        msg.height = nameHeight + contentHeight + padding * 2

        -- Calculate bubble width
        local measuredWidth = self:MeasureContentWidth(msg, fontSize)
        local bubbleWidth = measuredWidth + padding * 2

        -- Clamp to min/max
        msg.bubbleWidth = math.max(80, math.min(maxBubbleWidth, bubbleWidth))

        y = y + msg.height + gap
    end

    self.contentHeight_ = y
end

--- Measure content width for a message
function ChatWindow:MeasureContentWidth(msg, fontSize)
    -- Use RichText's measurement
    local width = msg.richText and msg.richText:MeasureWidth() or 0

    -- Also consider sender name width
    if not msg.isSystem then
        local nameWidth = UI.MeasureTextWidth(msg.sender, fontSize * 0.85, "sans")
        width = math.max(width, nameWidth)
    end

    return width
end

-- ============================================================================
-- Scroll
-- ============================================================================

function ChatWindow:ScrollToBottom()
    local layout = self:GetLayout()
    if layout and self.contentHeight_ > layout.h then
        self.scrollOffset_ = self.contentHeight_ - layout.h
    else
        self.scrollOffset_ = 0
    end
end

function ChatWindow:OnWheel(dx, dy)
    local layout = self:GetLayout()
    if not layout then return end

    local scrollAmount = 40
    self.scrollOffset_ = self.scrollOffset_ - dy * scrollAmount

    local maxScroll = math.max(0, self.contentHeight_ - layout.h)
    self.scrollOffset_ = math.max(0, math.min(maxScroll, self.scrollOffset_))

    self.autoScroll_ = (self.scrollOffset_ >= maxScroll - 10)
end

-- ============================================================================
-- Tooltip
-- ============================================================================

function ChatWindow:ShowItemTooltip(item, msg, bounds)
    -- Use global ItemTooltip (renders on overlay layer)
    local itemData = item.data or item
    ItemTooltip.Show(itemData, bounds)
end

function ChatWindow:HideTooltip()
    ItemTooltip.Hide()
end

-- ============================================================================
-- Rendering
-- ============================================================================

function ChatWindow:Render(nvg)
    local layout = self:GetAbsoluteLayout()
    if not layout or layout.w <= 0 or layout.h <= 0 then return end

    -- Recalculate layout if needed
    if #self.messages_ > 0 then
        local needsLayout = self.messages_[1].height == 0
        if not needsLayout and self.lastLayoutWidth_ ~= layout.w then
            needsLayout = true
        end
        if needsLayout then
            self.lastLayoutWidth_ = layout.w
            self:RecalculateLayout()
        end
    end

    local colors = self.props.colors
    local padding = self.props.bubblePadding
    local fontSize = self.props.fontSize

    -- Background
    self:RenderFullBackground(nvg)

    -- Clip content
    nvgSave(nvg)
    nvgIntersectScissor(nvg, layout.x, layout.y, layout.w, layout.h)

    -- Render messages
    for _, msg in ipairs(self.messages_) do
        local msgY = layout.y + msg.y - self.scrollOffset_

        -- Skip if outside visible area
        if msgY + msg.height < layout.y or msgY > layout.y + layout.h then
            goto continue
        end

        -- Determine bubble position and color
        local bubbleX, bubbleColor
        if msg.isSystem then
            bubbleX = layout.x + (layout.w - msg.bubbleWidth) / 2
            bubbleColor = colors.bubble_system
        elseif msg.isSelf then
            bubbleX = layout.x + layout.w - msg.bubbleWidth - 8
            bubbleColor = colors.bubble_self
        else
            bubbleX = layout.x + 8
            bubbleColor = colors.bubble_other
        end

        -- Draw bubble background
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bubbleX, msgY, msg.bubbleWidth, msg.height, 8)
        nvgFillColor(nvg, nvgRGBA(bubbleColor[1], bubbleColor[2], bubbleColor[3], bubbleColor[4]))
        nvgFill(nvg)

        -- Content position
        local contentX = bubbleX + padding
        local contentY = msgY + padding

        -- Draw sender name (if not system message)
        if not msg.isSystem then
            nvgFontSize(nvg, fontSize * 0.85)
            nvgFontFace(nvg, "sans")
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local nameColor = msg.isSelf and colors.name_self or colors.name_other
            nvgFillColor(nvg, nvgRGBA(nameColor[1], nameColor[2], nameColor[3], nameColor[4]))
            nvgText(nvg, contentX, contentY, msg.sender)
            contentY = contentY + fontSize + 2
        end

        -- Render message content using RichText
        if msg.richText then
            -- Set render offset for RichText (it will use this in GetAbsoluteLayout)
            msg.richText.renderOffsetX_ = contentX
            msg.richText.renderOffsetY_ = contentY
            msg.richText.renderWidth_ = msg.bubbleWidth - padding * 2
            msg.richText.renderHeight_ = msg.height - padding * 2 - (msg.isSystem and 0 or (fontSize + 2))
            msg.richText:Render(nvg)
        end

        ::continue::
    end

    nvgRestore(nvg)
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function ChatWindow:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    -- Forward to RichText widgets for hover detection
    for _, msg in ipairs(self.messages_) do
        if msg.richText then
            msg.richText:OnPointerMove(event)
        end
    end
end

function ChatWindow:OnPointerLeave(event)
    Widget.OnPointerLeave(self, event)
    ItemTooltip.Hide()

    for _, msg in ipairs(self.messages_) do
        if msg.richText then
            msg.richText:OnPointerLeave(event)
        end
    end
end

function ChatWindow:OnPointerDown(event)
    Widget.OnPointerDown(self, event)

    -- Hide tooltip on click elsewhere
    ItemTooltip.Hide()

    -- Forward to RichText widgets
    for _, msg in ipairs(self.messages_) do
        if msg.richText then
            local handled = msg.richText:OnClick(event)
            if handled then
                return true
            end
        end
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

function ChatWindow:SetAutoScroll(enabled)
    self.autoScroll_ = enabled
end

function ChatWindow:IsAutoScrollEnabled()
    return self.autoScroll_
end

function ChatWindow:GetMessageCount()
    return #self.messages_
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function ChatWindow:Destroy()
    for _, msg in ipairs(self.messages_) do
        if msg.richText then
            msg.richText:Destroy()
        end
    end
    Widget.Destroy(self)
end

return ChatWindow
