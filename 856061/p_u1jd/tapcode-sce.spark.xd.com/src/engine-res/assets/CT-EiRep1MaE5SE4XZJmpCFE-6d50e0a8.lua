-- ============================================================================
-- EditMenu - iOS-style text editing context menu (Widget)
-- Non-focusable overlay widget. Clicking it does not steal focus from
-- the owner text input. Singleton — only one EditMenu visible at a time.
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local UI = require("urhox-libs/UI/Core/UI")
local Theme = require("urhox-libs/UI/Core/Theme")

-- ============================================================================
-- Constants
-- ============================================================================

local HEIGHT = 36
local PAD_H = 8
local FONT_SIZE = 14
local RADIUS = 8
local ARROW = 6
local GAP = 4

-- ============================================================================
-- Singleton instance
-- ============================================================================

local instance_ = nil

-- ============================================================================
-- Widget class
-- ============================================================================

local EditMenuWidget = Widget:Extend("EditMenu")

function EditMenuWidget:Init(props)
    props = props or {}
    props.width = 0
    props.height = 0
    Widget.Init(self, props)

    self.focusable = false

    self.items_ = nil
    self.owner_ = nil
    self.menuX_ = 0
    self.menuY_ = 0
    self.menuW_ = 0
    self.menuH_ = 0
    self.itemWidths_ = nil
    self.pressedIndex_ = nil
    self.justOpened_ = false
    self.delayTimer_ = nil
    self.delayAction_ = nil
    self.anchorAbove_ = true
end

-- ============================================================================
-- Layout
-- ============================================================================

function EditMenuWidget:UpdateLayout(anchorX, anchorY, anchorH)
    -- 菜单始终按 DPI 缩放，不跟游戏设计分辨率。
    -- 内部全部用 DPI base pixels 计算（常量原样使用），
    -- Render 时 nvgScale 一次搞定，absoluteLayout 转回游戏坐标给 hit test。
    local gameScale = UI.GetScale()
    local defaultScale = UI.Scale.DEFAULT()
    local g2d = gameScale / defaultScale  -- game base pixels → default base pixels

    -- 锚点转到 DPI base pixels
    local ax = anchorX * g2d
    local ay = anchorY * g2d
    local ah = anchorH * g2d

    local fontSize = Theme.FontSize(FONT_SIZE)
    local totalW = 0
    local widths = {}
    for i, item in ipairs(self.items_) do
        local w = UI.MeasureTextWidth(item.label, fontSize) + PAD_H * 2
        widths[i] = w
        totalW = totalW + w
        if i < #self.items_ then totalW = totalW + 1 end
    end

    local mx = ax - totalW / 2
    local my = ay - HEIGHT - ARROW - GAP

    local viewW = graphics.width / defaultScale
    local pad = 4
    if mx < pad then mx = pad end
    if mx + totalW > viewW - pad then mx = viewW - pad - totalW end

    self.anchorAbove_ = true
    if my < pad then
        my = ay + ah + ARROW + GAP
        self.anchorAbove_ = false
    end

    self.menuX_ = mx
    self.menuY_ = my
    self.menuW_ = totalW
    self.menuH_ = HEIGHT
    self.itemWidths_ = widths
    self.nvgScale_ = defaultScale / gameScale
    self.defaultScale_ = defaultScale
    -- absoluteLayout 转回游戏 base pixels 给 hit test
    local d2g = defaultScale / gameScale
    self.absoluteLayout = { x = mx * d2g, y = my * d2g, w = totalW * d2g, h = HEIGHT * d2g }
end

-- ============================================================================
-- Hit testing
-- ============================================================================

function EditMenuWidget:GetItemIndexAt(screenX, screenY)
    if not self.items_ then return nil end
    -- event 坐标是游戏 base pixels，转到 default base pixels
    local g2d = 1 / (self.nvgScale_ or 1)
    local px, py = screenX * g2d, screenY * g2d

    local mx, my, mw, mh = self.menuX_, self.menuY_, self.menuW_, self.menuH_
    if px < mx or px > mx + mw or py < my or py > my + mh then
        return nil
    end
    local cx = mx
    for i = 1, #self.items_ do
        if i > 1 then cx = cx + 1 end
        if px >= cx and px <= cx + self.itemWidths_[i] then
            return i
        end
        cx = cx + self.itemWidths_[i]
    end
    return nil
end

-- ============================================================================
-- Event handlers (self-contained, no owner delegation needed)
-- ============================================================================

function EditMenuWidget:IsPointInMenuBounds(screenX, screenY)
    local g2d = 1 / (self.nvgScale_ or 1)
    local px, py = screenX * g2d, screenY * g2d
    local mx, my, mw, mh = self.menuX_, self.menuY_, self.menuW_, self.menuH_
    return px >= mx and px <= mx + mw and py >= my and py <= my + mh
end

function EditMenuWidget:OnPointerDown(event)
    self.justOpened_ = false
    local idx = self:GetItemIndexAt(event.x, event.y)
    self.pressedIndex_ = idx
end

function EditMenuWidget:OnPointerUp(event)
    if not self.delayTimer_ then
        self.pressedIndex_ = nil
    end
end

function EditMenuWidget:OnClick(event)
    if self.justOpened_ then
        self.justOpened_ = false
        return
    end

    local idx = self:GetItemIndexAt(event.x, event.y)
    if idx and self.items_[idx] then
        self.pressedIndex_ = idx
        self.delayTimer_ = 0.12
        self.delayAction_ = self.items_[idx].action
    elseif not self:IsPointInMenuBounds(event.x, event.y) then
        EditMenu.Hide()
    end
end

function EditMenuWidget:Update(dt)
    if self.delayTimer_ then
        self.delayTimer_ = self.delayTimer_ - dt
        if self.delayTimer_ <= 0 then
            local action = self.delayAction_
            self.delayTimer_ = nil
            self.delayAction_ = nil
            if action then action() end
        end
    end
end

-- ============================================================================
-- Render
-- ============================================================================

function EditMenuWidget:Render(nvg)
    if not self.items_ then return end

    local mx, my, mw, mh = self.menuX_, self.menuY_, self.menuW_, self.menuH_
    local widths = self.itemWidths_
    local s = self.nvgScale_ or 1

    -- 切换到 default 坐标空间：一次 nvgScale 搞定，内部用原始常量
    nvgSave(nvg)
    nvgScale(nvg, s, s)

    -- 像素对齐：snap 到物理像素网格
    local pxUnit = 1 / (self.defaultScale_ or 1)
    mx = math.floor(mx / pxUnit + 0.5) * pxUnit
    my = math.floor(my / pxUnit + 0.5) * pxUnit
    mw = math.floor(mw / pxUnit + 0.5) * pxUnit
    mh = math.floor(mh / pxUnit + 0.5) * pxUnit

    -- 阴影
    for i = 3, 1, -1 do
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, mx - i, my + i, mw + i * 2, mh + i * 2, RADIUS + i)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 12 * i))
        nvgFill(nvg)
    end

    -- 背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, mx, my, mw, mh, RADIUS)
    nvgFillColor(nvg, nvgRGBA(43, 43, 43, 240))
    nvgFill(nvg)

    -- 箭头居中于菜单（对标 iOS）
    local arrowCx = mx + mw / 2
    if self.anchorAbove_ then
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, arrowCx - ARROW, my + mh)
        nvgLineTo(nvg, arrowCx, my + mh + ARROW)
        nvgLineTo(nvg, arrowCx + ARROW, my + mh)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(43, 43, 43, 240))
        nvgFill(nvg)
    else
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, arrowCx - ARROW, my)
        nvgLineTo(nvg, arrowCx, my - ARROW)
        nvgLineTo(nvg, arrowCx + ARROW, my)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(43, 43, 43, 240))
        nvgFill(nvg)
    end

    -- 菜单项：分隔线和高亮在 nvgScale 空间画，文字切回原始空间画（避免字体模糊）
    local pressedIdx = self.pressedIndex_
    local cx = mx
    local centerY = my + mh / 2
    for i, item in ipairs(self.items_) do
        local iw = widths[i]
        if i > 1 then
            local lx = math.floor(cx / pxUnit + 0.5) * pxUnit + pxUnit * 0.5
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, lx, my + 8)
            nvgLineTo(nvg, lx, my + mh - 8)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 40))
            nvgStrokeWidth(nvg, pxUnit)
            nvgStroke(nvg)
            cx = cx + 1
        end
        if pressedIdx == i then
            local hInset = 4
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cx + hInset, my + 3, iw - hInset * 2, mh - 6, RADIUS - 3)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 40))
            nvgFill(nvg)
        end
        cx = cx + iw
    end

    -- 文字：切回游戏坐标空间渲染（devicePixelRatio 匹配，字体清晰）
    nvgRestore(nvg)
    nvgSave(nvg)
    nvgFontFace(nvg, Theme.FontFace())
    nvgFontSize(nvg, Theme.FontSize(FONT_SIZE) * s)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    cx = mx * s
    local centerY_game = (my + mh / 2) * s
    for i, item in ipairs(self.items_) do
        local iw = widths[i] * s
        if i > 1 then cx = cx + s end
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, pressedIdx == i and 180 or 255))
        nvgText(nvg, cx + iw / 2, centerY_game, item.label)
        cx = cx + iw
    end

    nvgRestore(nvg)
end

-- ============================================================================
-- Static API (singleton pattern, used by TextField/TextArea)
-- ============================================================================

local EditMenu = {}

local function getInstance()
    if not instance_ then
        instance_ = EditMenuWidget {}
        UI.RegisterGlobalComponent("EditMenu", instance_)
    end
    return instance_
end

function EditMenu.Show(options)
    EditMenu.Hide()
    if not options.items or #options.items == 0 then return end

    local inst = getInstance()
    inst.items_ = options.items
    inst.owner_ = options.owner
    inst.justOpened_ = true
    inst.pressedIndex_ = nil
    inst:UpdateLayout(options.anchorX, options.anchorY, options.anchorH or 0)
    UI.PushOverlay(inst)
end

function EditMenu.Hide()
    local inst = instance_
    if not inst or not inst.items_ then return end
    -- pending action 在 Hide 时取消，不执行（用户已通过点击别处/输入表达了放弃意图）
    UI.PopOverlay(inst)
    inst.items_ = nil
    inst.owner_ = nil
    inst.itemWidths_ = nil
    inst.pressedIndex_ = nil
    inst.delayTimer_ = nil
    inst.delayAction_ = nil
    inst.justOpened_ = false
end

function EditMenu.IsVisible()
    return instance_ ~= nil and instance_.items_ ~= nil
end

function EditMenu.GetOwner()
    return instance_ and instance_.owner_
end

return EditMenu
