-- ============================================================================
-- TextField Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Text input field with cursor and selection
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local EditMenu = require("urhox-libs/UI/Widgets/EditMenu")

-- UTF-8 helper functions
local function utf8Len(str)
    local len = 0
    local i = 1
    while i <= #str do
        local byte = string.byte(str, i)
        if byte < 128 then
            i = i + 1
        elseif byte < 224 then
            i = i + 2
        elseif byte < 240 then
            i = i + 3
        else
            i = i + 4
        end
        len = len + 1
    end
    return len
end

-- Get byte position of the n-th UTF-8 character
local function utf8BytePos(str, charPos)
    if charPos <= 0 then return 0 end
    local bytePos = 0
    local charCount = 0
    local i = 1
    while i <= #str and charCount < charPos do
        local byte = string.byte(str, i)
        if byte < 128 then
            i = i + 1
        elseif byte < 224 then
            i = i + 2
        elseif byte < 240 then
            i = i + 3
        else
            i = i + 4
        end
        charCount = charCount + 1
        bytePos = i - 1
    end
    if charCount < charPos then
        return #str
    end
    return bytePos
end

-- Get UTF-8 substring by character positions (1-based, inclusive)
local function utf8Sub(str, startChar, endChar)
    local startByte = startChar <= 1 and 1 or (utf8BytePos(str, startChar - 1) + 1)
    local endByte = endChar and utf8BytePos(str, endChar) or #str
    return string.sub(str, startByte, endByte)
end

-- Get UTF-8 codepoint at 1-based character index (safe for truncated sequences)
local function utf8Codepoint(str, charIdx)
    local byteStart = charIdx <= 1 and 1 or (utf8BytePos(str, charIdx - 1) + 1)
    local len = #str
    if byteStart > len then return nil end
    local b = string.byte(str, byteStart)
    if b < 128 then return b end
    if b < 224 then
        if byteStart + 1 > len then return nil end
        return (b - 192) * 64 + (string.byte(str, byteStart + 1) - 128)
    end
    if b < 240 then
        if byteStart + 2 > len then return nil end
        return (b - 224) * 4096 + (string.byte(str, byteStart + 1) - 128) * 64
            + (string.byte(str, byteStart + 2) - 128)
    end
    if byteStart + 3 > len then return nil end
    return (b - 240) * 262144 + (string.byte(str, byteStart + 1) - 128) * 4096
        + (string.byte(str, byteStart + 2) - 128) * 64
        + (string.byte(str, byteStart + 3) - 128)
end

-- 字符分类：用于双击选词的边界判断
-- 返回值: "cjk" / "word" / "space" / "punct"
-- 同类相邻字符构成一个选中单元，CJK 单字独立（对标 iOS）
local function charCategory(cp)
    if not cp then return "punct" end
    if cp == 0x20 or cp == 0x09 or cp == 0x0A or cp == 0x0D then return "space" end
    -- CJK 统一表意文字
    if cp >= 0x4E00 and cp <= 0x9FFF then return "cjk" end
    if cp >= 0x3400 and cp <= 0x4DBF then return "cjk" end
    if cp >= 0x20000 and cp <= 0x2A6DF then return "cjk" end
    -- 日文假名
    if cp >= 0x3040 and cp <= 0x309F then return "cjk" end
    if cp >= 0x30A0 and cp <= 0x30FF then return "cjk" end
    -- CJK 标点
    if cp >= 0x3000 and cp <= 0x303F then return "punct" end
    -- 全角标点
    if cp >= 0xFF01 and cp <= 0xFF0F then return "punct" end
    if cp >= 0xFF1A and cp <= 0xFF20 then return "punct" end
    -- ASCII 标点
    if cp >= 0x21 and cp <= 0x2F then return "punct" end
    if cp >= 0x3A and cp <= 0x40 then return "punct" end
    if cp >= 0x5B and cp <= 0x60 then return "punct" end
    if cp >= 0x7B and cp <= 0x7E then return "punct" end
    return "word"
end

-- Find word boundaries around a 0-based character position.
-- CJK 单字选中（对标 iOS），其他字符按同类扩展。
-- Returns selStart, selEnd (0-based)
local function findWordAt(str, charPos)
    local len = utf8Len(str)
    if len == 0 then return 0, 0 end
    local pos = math.max(1, math.min(charPos + 1, len))
    local cat = charCategory(utf8Codepoint(str, pos))

    -- CJK 单字独立选中
    if cat == "cjk" then
        return pos - 1, pos
    end

    local s = pos
    while s > 1 do
        if charCategory(utf8Codepoint(str, s - 1)) ~= cat then break end
        s = s - 1
    end
    local e = pos
    while e < len do
        if charCategory(utf8Codepoint(str, e + 1)) ~= cat then break end
        e = e + 1
    end
    return s - 1, e
end

---@class TextFieldProps : WidgetProps
---@field value? string Current text value
---@field placeholder? string Placeholder text
---@field disabled? boolean Is input disabled
---@field error? boolean Render error border state
---@field password? boolean Show as password (dots)
---@field maxLength? number Maximum character length
---@field fontSize? number Font size
---@field borderColor? RGBAColor|string Default border color
---@field borderWidth? number Default border width
---@field focusedBorderColor? RGBAColor|string Focused border color
---@field focusedBorderWidth? number Focused border width
---@field filledBorderColor? RGBAColor|string Filled border color
---@field filledBorderWidth? number Filled border width
---@field errorBorderColor? RGBAColor|string Error border color
---@field errorBorderWidth? number Error border width
---@field disabledBorderColor? RGBAColor|string Disabled border color
---@field disabledBorderWidth? number Disabled border width
---@field focusedBgColor? RGBAColor|string Focused background color
---@field filledBgColor? RGBAColor|string Filled background color
---@field disabledBgColor? RGBAColor|string Disabled background color
---@field textColor? RGBAColor|string Text color
---@field placeholderColor? RGBAColor|string Placeholder text color
---@field disabledTextColor? RGBAColor|string Disabled text color
---@field cursorColor? RGBAColor|string Cursor color
---@field selectionBgColor? RGBAColor|string Selection background color
---@field onChange? fun(self: TextField, value: string) Value change callback
---@field onSubmit? fun(self: TextField, value: string) Submit callback (Enter key)
---@field onFocus? fun(self: TextField) Focus callback
---@field onBlur? fun(self: TextField) Blur callback

---@class TextField : Widget
---@overload fun(props?: TextFieldProps): TextField
---@field props TextFieldProps
---@field new fun(self, props?: TextFieldProps): TextField
---@field state {focused: boolean, cursorPos: number, cursorBlink: boolean, selectionStart: number|nil, selectionEnd: number|nil}
local TextField = Widget:Extend("TextField")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props TextFieldProps?
function TextField:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("TextField")
    Style.ApplyDefaults(props, themeStyle)
    -- Hardcoded fallbacks (only hit when theme has no entry)
    props.height = props.height or 40
    props.borderRadius = props.borderRadius or 4
    -- fontSize stored in pt, converted at render time
    props.fontSize = props.fontSize or Theme.BaseFontSize("body")
    props.paddingHorizontal = props.paddingHorizontal or 12

    -- Default value
    props.value = props.value or ""
    props.placeholder = props.placeholder or ""

    -- Initialize state (cursorPos is character position, not byte position)
    self.state = {
        focused = false,
        cursorPos = utf8Len(props.value or ""),
        cursorBlink = true,
        selectionStart = nil,
        selectionEnd = nil,
        scrollX = 0,  -- horizontal scroll offset for long text
    }

    -- Cursor blink timer
    self.blinkTimer_ = 0

    -- Cache for click-to-cursor calculation
    self.charPositions_ = {}  -- x positions of each character boundary
    self.textAreaX_ = 0       -- cached text area start x
    self.scrollX_ = 0         -- cached scroll offset for click calculation
    self.isDragging_ = false  -- is user dragging to select text
    self.lastPointerType_ = nil
    self.pendingActivation_ = false

    Widget.Init(self, props)
end

-- Helper: Calculate cursor position from x coordinate
function TextField:GetCursorPosFromX(x)
    local textAreaX = self.textAreaX_ or 0
    local scrollX = self.scrollX_ or 0
    local charPositions = self.charPositions_ or { 0 }

    -- Convert x to text-relative position (accounting for scroll)
    local relativeX = x - textAreaX + scrollX

    -- Find the closest character boundary
    local cursorPos = 0
    local minDist = math.abs(relativeX - (charPositions[1] or 0))

    for i = 1, #charPositions do
        local charX = charPositions[i] or 0
        local dist = math.abs(relativeX - charX)
        if dist < minDist then
            minDist = dist
            cursorPos = i - 1  -- charPositions is 1-indexed, cursorPos is 0-indexed
        end
    end

    return cursorPos
end

-- Helper: Check if there is a selection
function TextField:HasSelection()
    local state = self.state
    return state.selectionStart ~= nil and state.selectionEnd ~= nil
        and state.selectionStart ~= state.selectionEnd
end

-- Helper: Get ordered selection range (start <= end)
function TextField:GetSelectionRange()
    local state = self.state
    if not self:HasSelection() then
        return nil, nil
    end
    local s, e = state.selectionStart, state.selectionEnd
    if s > e then
        s, e = e, s
    end
    return s, e
end

-- Helper: Delete selected text and return new value and cursor pos
function TextField:DeleteSelection()
    local value = self.props.value or ""
    local selStart, selEnd = self:GetSelectionRange()
    if not selStart then
        return value, self.state.cursorPos
    end

    local beforeSel = selStart > 0 and utf8Sub(value, 1, selStart) or ""
    local afterSel = utf8Sub(value, selEnd + 1)
    local newValue = beforeSel .. afterSel

    return newValue, selStart
end

-- Helper: Clear selection
function TextField:ClearSelection()
    self.state.selectionStart = nil
    self.state.selectionEnd = nil
end

-- ============================================================================
-- Rendering
-- ============================================================================

function TextField:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    local disabled = props.disabled
    local focused = state.focused
    local value = props.value or ""
    local placeholder = props.placeholder or ""
    local isPassword = props.password

    -- Colors
    local filled = value ~= ""
    local bgColor
    if disabled then
        bgColor = props.disabledBgColor or Theme.Color("disabled")
    elseif focused then
        bgColor = props.focusedBgColor or props.backgroundColor or Theme.Color("surface")
    elseif filled then
        bgColor = props.filledBgColor or props.backgroundColor or Theme.Color("surface")
    else
        bgColor = props.backgroundColor or Theme.Color("surface")
    end
    local borderColor
    local borderWidth
    local defaultBorderWidth = props.borderWidth
    if defaultBorderWidth == nil then
        defaultBorderWidth = 1
    end

    if disabled then
        borderColor = props.disabledBorderColor or props.borderColor or Theme.Color("border")
        borderWidth = props.disabledBorderWidth
    elseif props.error then
        borderColor = props.errorBorderColor or Theme.Color("error")
        borderWidth = props.errorBorderWidth
    elseif focused then
        borderColor = props.focusedBorderColor or Theme.Color("borderFocus")
        borderWidth = props.focusedBorderWidth
    elseif filled then
        borderColor = props.filledBorderColor or props.borderColor or Theme.Color("border")
        borderWidth = props.filledBorderWidth
    else
        borderColor = props.borderColor or Theme.Color("border")
        borderWidth = props.borderWidth
    end
    if borderWidth == nil then
        borderWidth = focused and 2 or defaultBorderWidth
    end

    local textColor = disabled
        and (props.disabledTextColor or props.textColor or Theme.Color("disabledText"))
        or (props.textColor or Theme.Color("text"))
    local placeholderColor = props.placeholderColor or Theme.Color("textSecondary")
    local cursorColor = props.cursorColor or textColor
    local borderRadius = props.borderRadius

    -- Draw background
    self:CreateShapePath(nvg, self:GetShapeGeometry(l, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    -- Draw border
    if borderColor and borderWidth > 0 then
        self:CreateShapePath(nvg, self:GetShapeGeometry(l, nil, borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, borderWidth)
        nvgStroke(nvg)
    end

    -- Set up text rendering
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, Theme.FontSize(props.fontSize))

    local paddingL = props.paddingLeft or 0
    local paddingR = props.paddingRight or 0
    local textAreaX = l.x + paddingL
    local textAreaWidth = l.w - paddingL - paddingR
    local textY = l.y + l.h / 2

    -- Display text or placeholder
    local valueLen = utf8Len(value)
    local displayText = value
    if isPassword and valueLen > 0 then
        displayText = string.rep("●", valueLen)
    end

    -- Cache values for click-to-cursor calculation
    self.textAreaX_ = textAreaX

    if #displayText > 0 then
        -- Calculate and cache character positions for click-to-cursor
        -- nvgTextBounds returns base pixels (it internally handles scale conversion)
        local charPositions = { 0 }  -- position 0 is at x=0
        for i = 1, valueLen do
            local subText = isPassword
                and string.rep("●", i)
                or utf8Sub(value, 1, i)
            local charX = nvgTextBounds(nvg, 0, 0, subText)
            charPositions[i + 1] = charX
        end
        self.charPositions_ = charPositions

        -- Calculate cursor position for scrolling
        local cursorOffset = charPositions[state.cursorPos + 1] or 0

        -- Update scroll to keep cursor visible
        local scrollX = state.scrollX or 0
        if cursorOffset - scrollX > textAreaWidth then
            -- Cursor is past the right edge
            scrollX = cursorOffset - textAreaWidth + 2
        elseif cursorOffset < scrollX then
            -- Cursor is past the left edge
            scrollX = cursorOffset
        end
        -- Clamp scroll
        local totalTextWidth = charPositions[valueLen + 1] or 0
        local maxScroll = math.max(0, totalTextWidth - textAreaWidth)
        scrollX = math.max(0, math.min(scrollX, maxScroll))
        state.scrollX = scrollX
        self.scrollX_ = scrollX  -- cache for click calculation

        -- Clip text area
        nvgSave(nvg)
        nvgIntersectScissor(nvg, textAreaX, l.y, textAreaWidth, l.h)

        -- Draw selection highlight
        if self:HasSelection() then
            local selStart, selEnd = self:GetSelectionRange()
            local selStartX = charPositions[selStart + 1] or 0
            local selEndX = charPositions[selEnd + 1] or 0

            local selectionColor = props.selectionBgColor or Theme.Color("primary") or { 66, 133, 244, 100 }
            local selectionAlpha = props.selectionBgColor and (selectionColor[4] or 255) or 100
            local _, _, selLineH = nvgTextMetrics(nvg)
            local selH = math.min(selLineH, l.h - 2)
            local selTop = l.y + (l.h - selH) / 2
            nvgBeginPath(nvg)
            nvgRect(nvg,
                textAreaX + selStartX - scrollX,
                selTop,
                selEndX - selStartX,
                selH
            )
            nvgFillColor(nvg, nvgRGBA(selectionColor[1], selectionColor[2], selectionColor[3], selectionAlpha))
            nvgFill(nvg)
        end

        -- Draw text with scroll offset
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, textAreaX - scrollX, textY, displayText, nil)

        -- Draw cursor if focused
        if focused and state.cursorBlink then
            local cursorX = textAreaX + cursorOffset - scrollX
            local _, _, lineH = nvgTextMetrics(nvg)
            local cursorH = math.min(lineH, l.h - 2)
            local cursorTop = l.y + (l.h - cursorH) / 2

            -- Draw cursor line
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, cursorX, cursorTop)
            nvgLineTo(nvg, cursorX, cursorTop + cursorH)
            nvgStrokeColor(nvg, nvgRGBA(cursorColor[1], cursorColor[2], cursorColor[3], cursorColor[4] or 255))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end

        nvgRestore(nvg)
    else
        -- Clear char positions cache for empty text
        self.charPositions_ = { 0 }
        self.scrollX_ = 0
        -- Draw placeholder
        nvgFillColor(nvg, nvgRGBA(placeholderColor[1], placeholderColor[2], placeholderColor[3], placeholderColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, textAreaX, textY, placeholder, nil)

        -- Draw cursor at start if focused
        if focused and state.cursorBlink then
            local _, _, lineH = nvgTextMetrics(nvg)
            local cursorH = math.min(lineH, l.h - 2)
            local cursorTop = l.y + (l.h - cursorH) / 2
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, textAreaX, cursorTop)
            nvgLineTo(nvg, textAreaX, cursorTop + cursorH)
            nvgStrokeColor(nvg, nvgRGBA(cursorColor[1], cursorColor[2], cursorColor[3], cursorColor[4] or 255))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end
    end

end

-- ============================================================================
-- Update (for cursor blink)
-- ============================================================================

function TextField:Update(dt)
    if self.state.focused then
        self.blinkTimer_ = self.blinkTimer_ + dt
        if self.blinkTimer_ >= 0.5 then
            self.blinkTimer_ = 0
            self.state.cursorBlink = not self.state.cursorBlink
        end
    end
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function TextField:OnFocus()
    if self.props.disabled then return end
    ui.useSystemClipboard = true
    if self.lastPointerType_ == "touch" then
        -- touch：延迟到 OnPointerUp 激活（避免滚动误触弹键盘）
        self.pendingActivation_ = true
    else
        -- mouse：立即激活（桌面标准）
        self:ActivateInput_()
    end
end

-- 剪贴板包装：优先系统剪贴板，设置失败时 fallback 到本地备份
local clipboardBackup_ = ""

local function setClipboard(text)
    ui:SetClipboardText(text)
    local readBack = ui:GetClipboardText()
    if readBack ~= text then
        clipboardBackup_ = text
    else
        clipboardBackup_ = ""
    end
end

local function getClipboard()
    local text = ui:GetClipboardText()
    if not text or #text == 0 then
        text = clipboardBackup_
    end
    return text
end

function TextField:ActivateInput_()
    self:SetState({ focused = true, cursorBlink = true })
    self.blinkTimer_ = 0
    if input then
        input:SetScreenKeyboardVisible(true)
    end
    if self.props.onFocus then
        self.props.onFocus(self)
    end
end

function TextField:OnBlur()
    self.pendingActivation_ = false
    EditMenu.Hide()
    self:ClearSelection()
    self:SetState({ focused = false })
    -- Disable text input (SDL_StopTextInput)
    if input then
        input:SetScreenKeyboardVisible(false)
    end
    if self.props.onBlur then
        self.props.onBlur(self)
    end
end

function TextField:DoCopy()
    if self:HasSelection() then
        local value = self.props.value or ""
        local selStart, selEnd = self:GetSelectionRange()
        setClipboard(utf8Sub(value, selStart + 1, selEnd))
    end
end

function TextField:DoCut()
    if self:HasSelection() then
        self:DoCopy()
        local newValue, newCursorPos = self:DeleteSelection()
        self:SetValue(newValue)
        self:SetState({ cursorPos = newCursorPos })
        self:ClearSelection()
    end
end

function TextField:DoPaste()
    local clipText = getClipboard()
    if clipText and #clipText > 0 then
        self:OnTextInput(clipText)
    end
end

function TextField:OnKeyDown(key)
    if not self.state.focused or self.props.disabled then return end
    EditMenu.Hide()

    local value = self.props.value or ""
    local cursorPos = self.state.cursorPos  -- character position
    local valueLen = utf8Len(value)
    local hasSelection = self:HasSelection()

    -- Check for Ctrl modifier
    local ctrlDown = input and input:GetQualifierDown(QUAL_CTRL)

    if ctrlDown and key == KEY_A then
        self:SelectAll()
        return
    end
    if ctrlDown and key == KEY_C then
        self:DoCopy()
        return
    end
    if ctrlDown and key == KEY_X then
        self:DoCut()
        return
    end
    if ctrlDown and key == KEY_V then
        -- Web + touch: browser paste event via hidden input already injects TextInput,
        -- skip DoPaste to avoid double-paste. All other cases (web mouse, native) use DoPaste.
        local isWebTouch = (GetPlatform and GetPlatform() == "Web") and self.lastPointerType_ == "touch"
        if not isWebTouch then
            self:DoPaste()
        end
        return
    end

    -- Handle special keys
    if key == KEY_BACKSPACE then
        if hasSelection then
            -- Delete selected text
            local newValue, newCursorPos = self:DeleteSelection()
            self:SetValue(newValue)
            self:SetState({ cursorPos = newCursorPos })
            self:ClearSelection()
        elseif cursorPos > 0 then
            -- Delete character before cursor (UTF-8 aware)
            local beforeCursor = cursorPos > 1 and utf8Sub(value, 1, cursorPos - 1) or ""
            local afterCursor = cursorPos < valueLen and utf8Sub(value, cursorPos + 1) or ""
            local newValue = beforeCursor .. afterCursor
            self:SetValue(newValue)
            self:SetState({ cursorPos = cursorPos - 1 })
        end
    elseif key == KEY_DELETE then
        if hasSelection then
            -- Delete selected text
            local newValue, newCursorPos = self:DeleteSelection()
            self:SetValue(newValue)
            self:SetState({ cursorPos = newCursorPos })
            self:ClearSelection()
        elseif cursorPos < valueLen then
            -- Delete character after cursor (UTF-8 aware)
            local beforeCursor = cursorPos > 0 and utf8Sub(value, 1, cursorPos) or ""
            local afterCursor = cursorPos + 1 < valueLen and utf8Sub(value, cursorPos + 2) or ""
            local newValue = beforeCursor .. afterCursor
            self:SetValue(newValue)
        end
    elseif key == KEY_LEFT then
        if hasSelection then
            -- Move cursor to start of selection
            local selStart, _ = self:GetSelectionRange()
            self:SetState({ cursorPos = selStart, cursorBlink = true })
            self:ClearSelection()
        elseif cursorPos > 0 then
            self:SetState({ cursorPos = cursorPos - 1, cursorBlink = true })
        end
        self.blinkTimer_ = 0
    elseif key == KEY_RIGHT then
        if hasSelection then
            -- Move cursor to end of selection
            local _, selEnd = self:GetSelectionRange()
            self:SetState({ cursorPos = selEnd, cursorBlink = true })
            self:ClearSelection()
        elseif cursorPos < valueLen then
            self:SetState({ cursorPos = cursorPos + 1, cursorBlink = true })
        end
        self.blinkTimer_ = 0
    elseif key == KEY_HOME then
        self:ClearSelection()
        self:SetState({ cursorPos = 0, cursorBlink = true })
        self.blinkTimer_ = 0
    elseif key == KEY_END then
        self:ClearSelection()
        self:SetState({ cursorPos = valueLen, cursorBlink = true })
        self.blinkTimer_ = 0
    elseif key == KEY_RETURN or key == KEY_KP_ENTER then
        self:DispatchEvent("submit", self, value)
        if self.props.onSubmit then
            self.props.onSubmit(self, value)
        end
    end
end

function TextField:OnTextInput(text)
    if not self.state.focused or self.props.disabled then
        return
    end
    EditMenu.Hide()

    local value = self.props.value or ""
    local cursorPos = self.state.cursorPos  -- character position
    local maxLength = self.props.maxLength

    -- If there's a selection, delete it first
    if self:HasSelection() then
        value, cursorPos = self:DeleteSelection()
        self:ClearSelection()
    end

    local valueLen = utf8Len(value)

    -- Check max length (in characters)
    if maxLength and valueLen >= maxLength then
        return
    end

    -- Insert text at cursor position (using UTF-8 aware functions)
    local beforeCursor = cursorPos > 0 and utf8Sub(value, 1, cursorPos) or ""
    local afterCursor = cursorPos < valueLen and utf8Sub(value, cursorPos + 1) or ""
    local newValue = beforeCursor .. text .. afterCursor

    -- Apply max length (in characters)
    local textCharLen = utf8Len(text)
    if maxLength and utf8Len(newValue) > maxLength then
        newValue = utf8Sub(newValue, 1, maxLength)
        textCharLen = maxLength - valueLen
    end

    self:SetValue(newValue)
    local newCursorPos = cursorPos + textCharLen
    self:SetState({ cursorPos = newCursorPos, cursorBlink = true })
    self.blinkTimer_ = 0
end

function TextField:OnPointerDown(event)
    self.lastPointerType_ = event.pointerType
    EditMenu.Hide()
    Widget.OnPointerDown(self, event)

    if not self.props.disabled and (self.state.focused or self.lastPointerType_ ~= "touch") then
        local newCursorPos = self:GetCursorPosFromX(event.x)

        -- 右键点击选区内：保留选区，跳过光标重置
        if event.button == MOUSEB_RIGHT and self:HasSelection() then
            local s, e = self:GetSelectionRange()
            if newCursorPos >= s and newCursorPos <= e then
                self.blinkTimer_ = 0
                return
            end
        end

        self.isDragging_ = true
        self:SetState({
            cursorPos = newCursorPos,
            selectionStart = newCursorPos,
            selectionEnd = newCursorPos,
            cursorBlink = true
        })
        self.blinkTimer_ = 0
    end
end

function TextField:OnPointerMove(event)
    self:DragUpdateSelection_(event)
end

function TextField:OnClick(event)
    -- touch 延迟激活
    if self.pendingActivation_ and not self.props.disabled then
        self.pendingActivation_ = false
        self:ActivateInput_()
        self:SetState({ cursorPos = self:GetCursorPosFromX(event.x) })
    elseif self.state.focused and not self.props.disabled and input
        and not EditMenu.IsVisible() and not self:HasSelection() then
        -- 已聚焦状态再次点击：重新弹出键盘（键盘可能被系统收起）
        -- 有选区时跳过（刚拖选完或长按弹菜单，不弹键盘）
        input:SetScreenKeyboardVisible(true)
    end

    -- 右键弹菜单（光标/选区已在 OnPointerDown 处理）
    if event.button == MOUSEB_RIGHT and not self.props.disabled then
        self:ShowEditMenu()
    end
end

-- touch 模式下 ScrollView 会 claim pan 手势并 cancel 子控件的 pointer，
-- TextField 聚焦时 claim pan 来阻止 ScrollView 抢拖拽
function TextField:OnPanStart(event)
    if self.state.focused and not self.props.disabled then
        return true
    end
    return false
end

function TextField:OnPanMove(event)
    self:DragUpdateSelection_(event)
end

function TextField:OnPanEnd(event)
    self.isDragging_ = false
    if self:HasSelection() and not EditMenu.IsVisible() then
        self:ShowEditMenu()
    end
end

function TextField:DragUpdateSelection_(event)
    if self.isDragging_ and not self.props.disabled and not EditMenu.IsVisible() then
        local newCursorPos = self:GetCursorPosFromX(event.x)
        self:SetState({
            cursorPos = newCursorPos,
            selectionEnd = newCursorPos,
            cursorBlink = true
        })
        self.blinkTimer_ = 0
    end
end

function TextField:OnPointerUp(event)
    Widget.OnPointerUp(self, event)
    self.isDragging_ = false

    -- 菜单已弹出时松手：预读系统剪贴板（用户手势内，为粘贴按钮准备缓存）
    if EditMenu.IsVisible() then
        getClipboard()
    end

    local hasSel = self.state.selectionStart ~= self.state.selectionEnd
    if not hasSel then
        self:ClearSelection()
    elseif not EditMenu.IsVisible() and self.lastPointerType_ == "touch" then
        self:ShowEditMenu()
    end
end


-- ============================================================================
-- EditMenu integration
-- ============================================================================

function TextField:ShowEditMenu()
    local items = {}
    local hasSelection = self:HasSelection()
    local value = self.props.value or ""
    local hasText = utf8Len(value) > 0
    local clipText = getClipboard()
    local hasClipboard = clipText and #clipText > 0

    if not hasSelection and not hasText and not hasClipboard then return end

    if hasSelection then
        items[#items + 1] = { label = _tr("t_fXa4atu5fQHe5nzP"), action = function() self:DoCut(); EditMenu.Hide() end }
        items[#items + 1] = { label = _tr("t_114gvb36W11aBW4BTG"), action = function() self:DoCopy(); EditMenu.Hide() end }
    end
    if hasClipboard then
        items[#items + 1] = { label = _tr("t_1EBK8BLGj1EgojTxmF"), action = function() self:DoPaste(); EditMenu.Hide() end }
    end
    local valueLen = utf8Len(value)
    local isAllSelected = false
    if hasSelection then
        local s, e = self:GetSelectionRange()
        isAllSelected = (s == 0 and e == valueLen)
    end
    if hasText and not isAllSelected then
        items[#items + 1] = { label = _tr("t_fdqeIMw7fRiBFzTZ"), action = function() self:SelectAll(); self:ShowEditMenu() end }
    end

    if #items == 0 then return end

    local l = self:GetAbsoluteLayoutForHitTest()
    local state = self.state
    local anchorX
    if hasSelection then
        local selStart, selEnd = self:GetSelectionRange()
        local positions = self.charPositions_ or { 0 }
        local startX = positions[selStart + 1] or 0
        local endX = positions[selEnd + 1] or 0
        local scrollX = state.scrollX or 0
        local paddingL = self.props.paddingLeft or 0
        anchorX = l.x + paddingL + (startX + endX) / 2 - scrollX
    else
        local positions = self.charPositions_ or { 0 }
        local cursorX = positions[state.cursorPos + 1] or 0
        local scrollX = state.scrollX or 0
        local paddingL = self.props.paddingLeft or 0
        anchorX = l.x + paddingL + cursorX - scrollX
    end

    EditMenu.Show({
        items = items,
        anchorX = anchorX,
        anchorY = l.y,
        anchorH = l.h,
        owner = self,
    })
end

function TextField:OnLongPressStart(event)
    if self.props.disabled then return end
    if self.lastPointerType_ == "touch" then
        self:ShowEditMenu()
    end
end

function TextField:OnDoubleTap(event)
    if self.props.disabled then return end
    local value = self.props.value or ""
    if utf8Len(value) == 0 then
        if self.lastPointerType_ == "touch" then
            self:ShowEditMenu()
        end
        return
    end
    local cursorPos = self:GetCursorPosFromX(event.x)
    local selStart, selEnd = findWordAt(value, cursorPos)
    self:SetState({
        cursorPos = selEnd,
        selectionStart = selStart,
        selectionEnd = selEnd,
        cursorBlink = true,
    })
    self.blinkTimer_ = 0
    if self.lastPointerType_ == "touch" then
        self:ShowEditMenu()
    end
end


-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set the text value
---@param value string
---@return TextField self
function TextField:SetValue(value)
    local oldValue = self.props.value
    self.props.value = value

    if value ~= oldValue then
        self:DispatchEvent("change", self, value)
        if self.props.onChange then
            self.props.onChange(self, value)
        end
    end

    return self
end

--- Get the text value
---@return string
function TextField:GetValue()
    return self.props.value or ""
end

--- Set placeholder text
---@param placeholder string
---@return TextField self
function TextField:SetPlaceholder(placeholder)
    self.props.placeholder = placeholder
    return self
end

--- Set disabled state
---@param disabled boolean
---@return TextField self
function TextField:SetDisabled(disabled)
    self.props.disabled = disabled
    if disabled then
        self:SetState({ focused = false })
    end
    return self
end

--- Clear the text
---@return TextField self
function TextField:Clear()
    self:SetValue("")
    self:SetState({ cursorPos = 0 })
    return self
end

--- Select all text
function TextField:SelectAll()
    local value = self.props.value or ""
    local valueLen = utf8Len(value)
    self:SetState({
        selectionStart = 0,
        selectionEnd = valueLen,
        cursorPos = valueLen,
    })
end

--- Alias for SetValue (for API consistency with Label)
---@param text string
---@return TextField self
function TextField:SetText(text)
    return self:SetValue(text)
end

--- Alias for GetValue (for API consistency with Label)
---@return string
function TextField:GetText()
    return self:GetValue()
end

-- ============================================================================
-- Stateful
-- ============================================================================

function TextField:IsStateful()
    return true
end

return TextField
