-- Example_lobby_ui.lua — 自定义大厅「模板换皮」示例（参考用，复制到你的项目后修改）。
--
-- 路径一（本文件）：用 Lobby.DefineScreen / Lobby.DefineDialog 在内置的 5 屏 + 系统弹窗上换皮，
--   专注外观（背景/配色/布局/动画），匹配·房间·连服等流程由引擎托管。本脚本接管全部 5 屏（含 connecting）。
--   动态内容（房间卡/玩家格/连服状态条/弹窗）用 urhox-libs/UI 控件声明式构建；
--   图片合成场景（各屏背景 + 主角立绘 + 按钮皮肤等定制美术）用大厅内局部 Panel 子类绘制。
--   用法：复制本文件到项目 scripts/lobby_ui.lua，引擎固定加载该文件；把下面的资源路径换成自己的图片即可。
--   只想改部分屏/弹窗时，删掉不需要的 DefineScreen/DefineDialog，
--   未覆盖的自动沿用引擎默认模板。
--   另一份同路径参考：DefaultLobbyUI.lua（纯控件树范式 / 即引擎默认模板）——本文件是图片驱动范式，
--   两种风格都可借鉴，别只盯一份。
--
-- 路径二（完全自建）：若要脱离固定屏、自己画任意界面与流程，见 Example_Custom_LobbyRuntime.lua
--   （配 multiplayer.lobby_runtime，用 ctx.client + 完整引擎 UI 自建）。

local DESIGN_W, DESIGN_H = 1920, 1080

-- 资源（换成自己的图片路径；相对项目 assets/ 解析）
local BG           = "UI/lobby_bg.png"        -- 大厅背景（建议 16:9 整图，cover 铺满）
local PROFILE_BG   = "UI/profile_card.png"    -- 用户卡底图
local AVATAR_FRAME = "UI/avatar_frame.png"    -- 头像框
local LOGO         = "UI/logo.png"            -- Logo 整图
local HERO         = "UI/hero.png"            -- 主角立绘
local CONNECT_BG   = "UI/connecting_bg.png"   -- 连服进度背景（可选，缺图时回退大厅背景）

-- 主题色（按自己游戏的配色改）
local C_INK    = { 16, 20, 34, 255 }      -- 兜底底色
local C_PANEL  = { 30, 38, 66, 235 }      -- 卡片底
local C_ACCENT = { 74, 178, 255, 255 }    -- 强调蓝
local C_WARN   = { 255, 96, 84, 255 }     -- 退出/取消红
local C_OK     = { 68, 217, 142, 255 }    -- 开始绿
local C_TEXT   = { 255, 255, 255, 255 }
local C_MUTED  = { 190, 198, 222, 220 }

-- 右侧三张功能卡（ctrl = 框架提供的功能 Button；bg/char = 卡片底图/角色图）
local CARDS = {
    { ctrl = "quick_match_button", bg = "UI/card_quick.png",  char = "UI/char_quick.png",  title = _tr("t_3oLGvfnU4GMMCbw1"), desc = _tr("t_a4k9RVz3Zc3QWCtY"), tint = { 74, 178, 255 } },
    { ctrl = "browse_button",      bg = "UI/card_browse.png", char = "UI/char_browse.png", title = _tr("t_oOFMYbK1oFxYSyYu"), desc = _tr("t_YLzALCVKYpx0Vx95"),   tint = { 68, 217, 142 } },
    { ctrl = "create_button",      bg = "UI/card_create.png", char = "UI/char_create.png", title = _tr("t_1DSgBSUmlo9AcDt"), desc = _tr("t_XaPZdHvhX6y0KoVY"),   tint = { 255, 208, 66 } },
}

-- 卡片列布局（用 right 锚定屏幕右边缘，分辨率自适应）
local CARD_W, CARD_H, CARD_RIGHT = 690, 178, 80
local CARD_TOPS = { 286, 286 + 188, 286 + 188 * 2 }

-- ============================================================================
-- 图片合成场景的局部绘制工具与 Lobby 专属视觉控件。
-- 这些是本示例局部的画法集（不依赖任何外部绘制库），便于复制即用。
-- ============================================================================

local D = {}
local imageCache = {}   -- path → handle(>0) / false(失败)

function D.rgba(c)
    return nvgRGBA(c[1], c[2], c[3], c[4] or 255)
end

function D.load(vg, path)
    if imageCache[path] == false then return nil end
    if not imageCache[path] then
        local h = nvgCreateImage(vg, path, 0)
        if h and h > 0 then imageCache[path] = h else imageCache[path] = false return nil end
    end
    return imageCache[path]
end

function D.image(vg, path, x, y, w, h, alpha)
    local img = D.load(vg, path)
    if not img then return false end
    nvgBeginPath(vg) nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, nvgImagePattern(vg, x, y, w, h, 0, img, alpha or 1))
    nvgFill(vg)
    return true
end

function D.cover(vg, path, x, y, w, h, alpha)
    local img = D.load(vg, path)
    if not img then return false end
    local iw, ih = nvgImageSize(vg, img)
    if not iw or not ih or iw <= 0 or ih <= 0 then
        return D.image(vg, path, x, y, w, h, alpha)
    end
    local s = math.max(w / iw, h / ih)
    local dw, dh = iw * s, ih * s
    local dx, dy = x + (w - dw) * 0.5, y + (h - dh) * 0.5
    nvgBeginPath(vg) nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, nvgImagePattern(vg, dx, dy, dw, dh, 0, img, alpha or 1))
    nvgFill(vg)
    return true
end

function D.contain(vg, path, x, y, w, h, alpha)
    local img = D.load(vg, path)
    if not img then return false end
    local iw, ih = nvgImageSize(vg, img)
    if not iw or not ih or iw <= 0 or ih <= 0 then return false end
    local s = math.min(w / iw, h / ih)
    local dw, dh = iw * s, ih * s
    local dx, dy = x + (w - dw) * 0.5, y + (h - dh) * 0.5
    nvgBeginPath(vg) nvgRect(vg, dx, dy, dw, dh)
    nvgFillPaint(vg, nvgImagePattern(vg, dx, dy, dw, dh, 0, img, alpha or 1))
    nvgFill(vg)
    return true
end

function D.rounded(vg, path, x, y, w, h, r, alpha)
    local img = D.load(vg, path)
    if not img then return false end
    nvgBeginPath(vg) nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillPaint(vg, nvgImagePattern(vg, x, y, w, h, 0, img, alpha or 1))
    nvgFill(vg)
    return true
end

function D.roundRect(vg, x, y, w, h, r, color)
    nvgBeginPath(vg) nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, D.rgba(color)) nvgFill(vg)
end

function D.charPlaceholder(vg, x, y, w, h, tint)
    tint = tint or { 120, 140, 200 }
    local CW = NVG_CW or 1
    local r = math.min(w, h) * 0.12
    nvgBeginPath(vg) nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, nvgRGBA(tint[1], tint[2], tint[3], 60)) nvgFill(vg)
    nvgBeginPath(vg) nvgRoundedRect(vg, x + 1, y + 1, w - 2, h - 2, r)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 70)) nvgStrokeWidth(vg, 2) nvgStroke(vg)
    local cx = x + w * 0.5
    local headR = math.min(w, h) * 0.16
    local headCy = y + h * 0.34
    nvgBeginPath(vg) nvgCircle(vg, cx, headCy, headR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 150)) nvgFill(vg)
    nvgBeginPath(vg)
    nvgArc(vg, cx, headCy + headR * 2.4, headR * 1.7, math.pi, math.pi * 2, CW)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 150)) nvgFill(vg)
end

function D.charImage(vg, path, x, y, w, h, tint)
    if not D.contain(vg, path, x, y, w, h, 1) then
        D.charPlaceholder(vg, x, y, w, h, tint)
    end
end

function D.text(vg, x, y, str, opts)
    opts = opts or {}
    nvgFontFace(vg, opts.face or "sans")
    nvgFontSize(vg, opts.size or 18)
    nvgFillColor(vg, D.rgba(opts.color or { 255, 255, 255, 255 }))
    nvgTextAlign(vg, opts.align or (NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE))
    nvgText(vg, x, y, str, nil)
end

-- 矢量图标（区域 (x,y,size,size)）
function D.icon(vg, kind, x, y, size, color)
    local col = D.rgba(color or { 255, 255, 255, 200 })
    local cx, cy = x + size * 0.5, y + size * 0.5
    local CW = NVG_CW or 1
    nvgLineCap(vg, NVG_ROUND) nvgLineJoin(vg, NVG_ROUND)
    if kind == "lightning" then
        local s = size * 0.42
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 0.08, cy - s)   nvgLineTo(vg, cx - s * 0.55, cy + s * 0.02)
        nvgLineTo(vg, cx - s * 0.08, cy + s * 0.02) nvgLineTo(vg, cx - s * 0.32, cy + s)
        nvgLineTo(vg, cx + s * 0.55, cy - s * 0.14) nvgLineTo(vg, cx + s * 0.08, cy - s * 0.14)
        nvgClosePath(vg) nvgFillColor(vg, col) nvgFill(vg)
    elseif kind == "search" then
        local r = size * 0.24
        nvgBeginPath(vg) nvgCircle(vg, cx - size * 0.05, cy - size * 0.05, r)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.4) nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + r * 0.55, cy + r * 0.55) nvgLineTo(vg, x + size * 0.82, y + size * 0.82)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.5) nvgStroke(vg)
    elseif kind == "plus" then
        local r = size * 0.30
        nvgBeginPath(vg) nvgCircle(vg, cx, cy, r)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.16) nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - r * 0.55, cy) nvgLineTo(vg, cx + r * 0.55, cy)
        nvgMoveTo(vg, cx, cy - r * 0.55) nvgLineTo(vg, cx, cy + r * 0.55)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.18) nvgStroke(vg)
    elseif kind == "exit" or kind == "back" then
        local s = size * 0.42
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, math.max(2, size * 0.07))
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 0.12, cy - s) nvgLineTo(vg, cx - s, cy - s)
        nvgLineTo(vg, cx - s, cy + s)        nvgLineTo(vg, cx + s * 0.12, cy + s)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.15, cy)        nvgLineTo(vg, cx + s * 0.82, cy)
        nvgMoveTo(vg, cx + s * 0.42, cy - s * 0.35) nvgLineTo(vg, cx + s * 0.82, cy)
        nvgLineTo(vg, cx + s * 0.42, cy + s * 0.35)
        nvgStroke(vg)
    elseif kind == "cancel" then
        local s = size * 0.30
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, math.max(2, size * 0.09))
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s, cy - s) nvgLineTo(vg, cx + s, cy + s)
        nvgMoveTo(vg, cx + s, cy - s) nvgLineTo(vg, cx - s, cy + s)
        nvgStroke(vg)
    elseif kind == "refresh" then
        local r = size * 0.30
        nvgBeginPath(vg) nvgArc(vg, cx, cy, r, -math.pi * 0.2, math.pi * 1.5, CW)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.22) nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + r * 0.55, cy - r * 0.75) nvgLineTo(vg, cx + r * 0.55, cy - r * 0.2)
        nvgLineTo(vg, cx + r * 1.05, cy - r * 0.5)
        nvgFillColor(vg, col) nvgFill(vg)
    end
end

function D.pulsingCircles(nvg, cx, cy, maxRadius, color, ringCount, time)
    color = color or { 51, 153, 255 }
    ringCount = ringCount or 3
    time = time or 0
    for i = 1, ringCount do
        local phase = (i - 1) / ringCount
        local progress = (time * 0.15 + phase) % 1.0
        local radius = maxRadius * 0.3 + maxRadius * 0.7 * progress
        local alpha = (1.0 - progress) * 0.6
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, radius)
        nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], alpha * 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end
end

function D.animatedSearchIcon(nvg, cx, cy, size, color, sw, time)
    color = color or { 255, 255, 255, 255 }
    sw = sw or 4
    time = time or 0
    local orbitAngle = time * 0.8
    local orbitRadius = size * 0.08
    local magCx = cx + math.cos(orbitAngle) * orbitRadius
    local magCy = cy + math.sin(orbitAngle) * orbitRadius
    local r = size * 0.3
    local handleLen = size * 0.28
    local handleAngle = 0.785
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgLineCap(nvg, NVG_ROUND)
    nvgBeginPath(nvg)
    nvgCircle(nvg, magCx, magCy, r)
    nvgStrokeWidth(nvg, sw * 1.5)
    nvgStroke(nvg)
    local hx1 = magCx + r * 0.75 * math.cos(handleAngle)
    local hy1 = magCy + r * 0.75 * math.sin(handleAngle)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, hx1, hy1)
    nvgLineTo(nvg, hx1 + handleLen * math.cos(handleAngle), hy1 + handleLen * math.sin(handleAngle))
    nvgStrokeWidth(nvg, sw * 2)
    nvgStroke(nvg)
end

local Panel = UI.Panel

local function visualProps(props, zIndex)
    props = props or {}
    props.position = props.position or "absolute"
    props.left = props.left == nil and 0 or props.left
    props.top = props.top == nil and 0 or props.top
    props.right = props.right == nil and 0 or props.right
    props.bottom = props.bottom == nil and 0 or props.bottom
    props.pointerEvents = "none"
    props.zIndex = props.zIndex == nil and (zIndex or 0) or props.zIndex
    return props
end

-- 前向声明：connecting 屏背景 Render 在 safeProgress 定义（下方）之前就会调用
local safeProgress

local function beginVisual(self, nvg)
    Panel.Render(self, nvg)
    local layout = self:GetAbsoluteLayout()
    nvgSave(nvg)
    nvgTranslate(nvg, layout.x, layout.y)
    nvgIntersectScissor(nvg, 0, 0, layout.w, layout.h)
    return layout
end

local function endVisual(nvg)
    nvgRestore(nvg)
end

local MainBackgroundVisual = Panel:Extend("LobbyExampleMainBackground")

function MainBackgroundVisual:Init(props)
    props = visualProps(props, -1000)
    self.userId_ = props.userId or 0
    Panel.Init(self, props)
end

function MainBackgroundVisual:Render(nvg)
    local layout = beginVisual(self, nvg)
    local w, h = layout.w, layout.h
    if not D.cover(nvg, BG, 0, 0, w, h, 1) then
        D.roundRect(nvg, 0, 0, w, h, 0, { 28, 35, 64, 255 })
    end

    local scale = math.max(w / DESIGN_W, h / DESIGN_H)
    local ox, oy = (w - DESIGN_W * scale) * 0.5, (h - DESIGN_H * scale) * 0.5
    local function px(v) return ox + v * scale end
    local function py(v) return oy + v * scale end
    local function ps(v) return v * scale end
    D.charImage(nvg, HERO, px(250), py(380), ps(680), ps(600), { 220, 80, 70 })
    D.contain(nvg, LOGO, px(250 + (680 - 460) / 2), py(380 - 156 - 20), ps(460), ps(156), 1)

    local cw, ch = 386, 106
    local cx, cy = w - (CARD_RIGHT + CARD_W / 2) - cw / 2, CARD_TOPS[1] - ch - 24
    if not D.rounded(nvg, PROFILE_BG, cx, cy, cw, ch, 53, 0.98) then
        D.roundRect(nvg, cx, cy, cw, ch, 53, { 42, 42, 52, 220 })
    end
    D.image(nvg, AVATAR_FRAME, cx + 16, cy + 13, 80, 80, 1)

    local tx = cx + 116
    local nick = (LobbyState.self.nickname ~= "" and LobbyState.self.nickname) or _tr("t_18zuRw7Pt18rnE6t2m")
    D.text(nvg, tx, cy + 14, nick, { size = 25, align = NVG_ALIGN_LEFT + NVG_ALIGN_TOP })
    D.text(nvg, tx, cy + 48, "ID: " .. tostring(self.userId_), { size = 18, color = { 205, 205, 218, 220 }, align = NVG_ALIGN_LEFT + NVG_ALIGN_TOP })
    local online = (not Lobby.IsOnline) or Lobby.IsOnline()
    local onlineColor = online and { 60, 216, 112, 255 } or { 255, 90, 90, 255 }
    nvgBeginPath(nvg)
    nvgCircle(nvg, tx + 6, cy + 86, 5)
    nvgFillColor(nvg, D.rgba(onlineColor))
    nvgFill(nvg)
    D.text(nvg, tx + 18, cy + 78, online and _tr("t_QXpKdJYYQPYgvCTz") or _tr("t_Rr1DCfnQRgKalIOL"), { size = 16, color = onlineColor, align = NVG_ALIGN_LEFT + NVG_ALIGN_TOP })
    endVisual(nvg)
end

local MainCardVisual = Panel:Extend("LobbyExampleMainCard")

function MainCardVisual:Init(props)
    props = visualProps(props)
    self.spec_ = props.spec or {}
    Panel.Init(self, props)
end

function MainCardVisual:Render(nvg)
    local layout = beginVisual(self, nvg)
    local w, h = layout.w, layout.h
    local spec = self.spec_
    if not D.image(nvg, spec.bg, 0, 0, w, h, 1) then
        D.roundRect(nvg, 0, 0, w, h, 14, { 40, 50, 90, 235 })
    end
    D.charImage(nvg, spec.char, 24, (h - 150) / 2, 210, 150, spec.tint)
    local tx = 24 + 210 + 24
    D.text(nvg, tx, h * 0.40, spec.title, { size = 36 })
    D.text(nvg, tx, h * 0.66, spec.desc, { size = 19, color = { 255, 255, 255, 220 } })
    endVisual(nvg)
end

local ScreenBackgroundVisual = Panel:Extend("LobbyExampleScreenBackground")

function ScreenBackgroundVisual:Init(props)
    props = visualProps(props, -1000)
    self.kind_ = props.kind
    Panel.Init(self, props)
end

function ScreenBackgroundVisual:Render(nvg)
    local layout = beginVisual(self, nvg)
    local w, h = layout.w, layout.h
    if self.kind_ == "quick_match" then
        if not D.cover(nvg, BG, 0, 0, w, h, 1) then D.roundRect(nvg, 0, 0, w, h, 0, C_INK) end
        local t = LobbyState.matchmaking.elapsed or 0
        local cx, cy = w * 0.5, h * 0.40
        for i = 0, 2 do
            local phase = (t * 0.7 + i / 3) % 1
            nvgBeginPath(nvg)
            nvgCircle(nvg, cx, cy, 70 + phase * 110)
            nvgStrokeColor(nvg, nvgRGBA(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], math.floor((1 - phase) * 150)))
            nvgStrokeWidth(nvg, 4)
            nvgStroke(nvg)
        end
        D.icon(nvg, "search", cx - 30, cy - 30, 60, C_TEXT)
        local dots = string.rep(".", math.floor(t * 2) % 4)
        D.text(nvg, cx, cy + 150, _tr("t_GlBMWTKsGIQXGTgh", dots), { size = 34, align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE })
        local e = math.floor(t)
        D.text(nvg, cx, cy + 200, string.format(_tr("t_14uJHLlOS15NfcD7LV"), math.floor(e / 60), e % 60), { size = 20, color = C_MUTED, align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE })
    elseif self.kind_ == "room_list" then
        if not D.cover(nvg, BG, 0, 0, w, h, 1) then D.roundRect(nvg, 0, 0, w, h, 0, C_INK) end
        D.text(nvg, w * 0.5, 70, _tr("t_oOFMYbK1oFxYSyYu"), { size = 40, align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE })
    elseif self.kind_ == "room_waiting" then
        if not D.cover(nvg, BG, 0, 0, w, h, 1) then D.roundRect(nvg, 0, 0, w, h, 0, C_INK) end
        local title = (LobbyState.room and LobbyState.room.title) or _tr("t_1IM9xJuv1iw43RHH")
        D.text(nvg, w * 0.5, 70, title, { size = 40, align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE })
    elseif self.kind_ == "connecting" then
        if not D.cover(nvg, CONNECT_BG, 0, 0, w, h, 1) and not D.cover(nvg, BG, 0, 0, w, h, 1) then
            D.roundRect(nvg, 0, 0, w, h, 0, C_INK)
        end
        D.roundRect(nvg, 0, 0, w, h, 0, { 8, 12, 26, 168 })
        local scale = math.max(w / DESIGN_W, h / DESIGN_H)
        local ox, oy = (w - DESIGN_W * scale) * 0.5, (h - DESIGN_H * scale) * 0.5
        local function px(v) return ox + v * scale end
        local function py(v) return oy + v * scale end
        local function ps(v) return v * scale end
        D.contain(nvg, LOGO, px(80), py(70), ps(260), ps(88), 0.92)
        D.charImage(nvg, HERO, px(90), py(360), ps(520), ps(560), { 80, 180, 255 })
        for i = 0, 7 do
            local x = w * 0.38 + i * 116
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x, h * 0.18)
            nvgLineTo(nvg, x + 210, h * 0.82)
            nvgStrokeColor(nvg, nvgRGBA(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 46))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
        end
        local p = safeProgress((LobbyState.connecting and LobbyState.connecting.progress) or 0)
        local cx, cy = w - 270, h * 0.43
        D.pulsingCircles(nvg, cx, cy, 118, C_ACCENT, 4, p * 3.0)
        D.animatedSearchIcon(nvg, cx, cy, 82, C_TEXT, 4, p * 5.0)
        D.text(nvg, w - 90, 86, "SERVER LINK",
            { size = 46, color = C_TEXT, align = NVG_ALIGN_RIGHT + NVG_ALIGN_TOP })
        D.text(nvg, w - 92, 142, _tr("t_XosFd71jYKI9ntFh"),
            { size = 18, color = C_MUTED, align = NVG_ALIGN_RIGHT + NVG_ALIGN_TOP })
    end
    endVisual(nvg)
end

local LobbyActionVisual = Panel:Extend("LobbyExampleAction")

function LobbyActionVisual:Init(props)
    props = visualProps(props)
    self.kind_ = props.kind
    self.icon_ = props.icon
    self.label_ = props.label or ""
    self.iconColor_ = props.iconColor or C_TEXT
    Panel.Init(self, props)
end

function LobbyActionVisual:Render(nvg)
    local layout = beginVisual(self, nvg)
    local w, h = layout.w, layout.h
    if self.kind_ == "exit" then
        D.roundRect(nvg, 0, 0, w, h, 28, { 55, 48, 50, 210 })
        D.icon(nvg, "exit", 36, h / 2 - 12, 24, { 255, 84, 58, 255 })
        D.text(nvg, 76, h * 0.5, self.label_, { size = 18 })
    elseif self.kind_ == "nav" then
        D.roundRect(nvg, 0, 0, w, h, 30, C_PANEL)
        D.icon(nvg, self.icon_, 22, h / 2 - 13, 26, self.iconColor_)
        D.text(nvg, 64, h * 0.5, self.label_, { size = 20, align = NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE })
    elseif self.kind_ == "cancel" then
        D.roundRect(nvg, 0, 0, w, h, 32, C_WARN)
        D.icon(nvg, "cancel", 60, h / 2 - 13, 26, self.iconColor_)
        D.text(nvg, w * 0.5 + 18, h * 0.5, self.label_, { size = 20, align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE })
    elseif self.kind_ == "start" then
        D.roundRect(nvg, 0, 0, w, h, 32, C_OK)
        D.text(nvg, w * 0.5, h * 0.5, self.label_, { size = 22, color = { 20, 40, 28, 255 }, align = NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE })
    end
    endVisual(nvg)
end

-- ============================================================================
-- 控件小工具：头像圆 / 空态（动态内容用 urhox-libs/UI 控件）
-- ============================================================================

local function avatarCircle(o)
    o = o or {}
    local size = o.size or 56
    local panel = UI.Panel {
        width = size, height = size, borderRadius = size / 2,
        backgroundColor = o.bg or { 70, 90, 140, 255 },
        borderWidth = o.borderWidth, borderColor = o.borderColor,
        alignItems = "center", justifyContent = "center",
    }
    if o.text and o.text ~= " " then
        panel:AddChild(UI.Label { text = o.text, fontSize = o.fontSize or 28, fontColor = o.fontColor or { 235, 240, 250, 255 } })
    end
    return panel
end

local function emptyState(o)
    o = o or {}
    return UI.Panel {
        width = "100%", alignItems = "center", justifyContent = "center",
        paddingTop = 60, paddingBottom = 60, gap = 14, backgroundColor = o.backgroundColor,
        borderRadius = o.backgroundColor and 18 or nil,
        children = {
            UI.Icon { name = o.icon or "search", variant = "line", size = 48, color = { 120, 130, 150, 150 }, strokeWidth = 3 },
            UI.Label { text = o.text or "", fontSize = 18, fontColor = C_MUTED },
        },
    }
end

-- 把框架功能按钮变成一块干净画布：定位 + 清空默认内容 + 挂载视觉子控件
local function skinButton(ctrl, pos, visual)
    ctrl:clearChildren()
    ctrl.style.position   = "absolute"
    ctrl.style.background  = { 0, 0, 0, 0 }
    for k, v in pairs(pos) do ctrl.style[k] = v end
    ctrl:addChild(visual)
end

local function skinBackground(ctrl, visual)
    ctrl.style.background = C_INK
    ctrl:addChild(visual)
end

-- ============================================================================
-- 主界面
-- ============================================================================

local function buildMain()
    local myId = (Lobby.GetMyUserId and Lobby.GetMyUserId()) or 0

    skinBackground(LobbyUI.main.background, MainBackgroundVisual { userId = myId })

    -- 三张卡片：定位 + 绘制（底图含右侧图标 + 左侧角色 + 中间文字）
    for i, c in ipairs(CARDS) do
        local ctrl = LobbyUI.main[c.ctrl]
        skinButton(ctrl, {
            right = CARD_RIGHT,
            top = CARD_TOPS[i],
            width = CARD_W,
            height = CARD_H,
        }, MainCardVisual { spec = c })
    end

    -- 退出按钮
    local EXIT_W, EXIT_H = 210, 56
    local ex = LobbyUI.main.exit_button
    skinButton(ex,
        { right = CARD_RIGHT + (CARD_W - EXIT_W) / 2, top = CARD_TOPS[3] + CARD_H + 40, width = EXIT_W, height = EXIT_H },
        LobbyActionVisual { kind = "exit", label = _tr("t_lQr2vOEgkyF2NQ6R") })
end

-- ============================================================================
-- 快速匹配等待界面
-- ============================================================================

local function buildQuickMatchWaiting()
    skinBackground(LobbyUI.quick_match_waiting.background, ScreenBackgroundVisual { kind = "quick_match" })

    -- 取消按钮：屏幕底部居中
    skinButton(LobbyUI.quick_match_waiting.cancel_button,
        { left = "50%", marginLeft = -150, bottom = 90, width = 300, height = 64 },
        LobbyActionVisual { kind = "cancel", label = _tr("t_An9ovnM5AwRAZ5y8") })
end

-- ============================================================================
-- 浏览房间界面（背景图 + 返回/刷新按钮 + onRoomList 动态房间卡）
-- ============================================================================

local rl_container = nil

-- 单张房间卡（urhox-libs/UI 控件；整卡可点击 → 加入房间）
local function makeRoomCard(room)
    local status = room.status or 1
    local statusText = status == 1 and _tr("t_vwj0n2iavS7u0c7B") or (status == 2 and _tr("t_WP2RNoJGVwrMSVxD") or _tr("t_GXG2Rc9bGg458sW2"))
    local statusColor = status == 1 and C_OK or { 230, 180, 80, 255 }

    return UI.Button {
        width = 440, height = 150, flexDirection = "column", justifyContent = "center",
        backgroundColor = C_PANEL, borderRadius = 18, borderWidth = 2, borderColor = { 70, 110, 180, 160 },
        paddingLeft = 26, paddingRight = 26, gap = 10,
        onClick = function() if status == 1 then Lobby.JoinRoom(room.id or 0, room.maxPlayers) end end,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", justifyContent = "space-between", pointerEvents = "none",
                children = {
                    UI.Label { text = string.format("#%d %s", room.id or 0, room.name or _tr("t_dKPVAF3ecqMQG9od")), fontSize = 28, fontWeight = "bold", fontColor = C_TEXT },
                    UI.Panel {
                        backgroundColor = { 0, 0, 0, 80 }, borderRadius = 14, paddingLeft = 14, paddingRight = 14, paddingTop = 5, paddingBottom = 5,
                        children = { UI.Label { text = statusText, fontSize = 18, fontWeight = "bold", fontColor = statusColor } },
                    },
                },
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", justifyContent = "space-between", pointerEvents = "none",
                children = {
                    UI.Label { text = _tr("t_nLTVGjzcnomcrqp7", FormatInt(room.ownerId or 0)), fontSize = 18, fontColor = C_MUTED },
                    UI.Label { text = string.format("👥 %d/%d", room.playerCount or 0, room.maxPlayers or 4), fontSize = 20, fontColor = C_ACCENT },
                },
            },
        },
    }
end

local function buildRoomList()
    skinBackground(LobbyUI.room_list.background, ScreenBackgroundVisual { kind = "room_list" })

    -- 返回（左上）+ 刷新（右上）
    skinButton(LobbyUI.room_list.back_button,
        { left = 40, top = 44, width = 130, height = 60 },
        LobbyActionVisual { kind = "nav", icon = "back", label = _tr("t_qNlgG5bPpwC8vWgM") })
    skinButton(LobbyUI.room_list.refresh_button,
        { right = 40, top = 44, width = 130, height = 60 },
        LobbyActionVisual { kind = "nav", icon = "refresh", label = _tr("t_GljWIQSeGGJbvGlS") })

    -- 房间卡滚动区
    rl_container = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 28,
        justifyContent = "center", alignContent = "flex-start",
    }
    LobbyUI.room_list.background:addChild(UI.ScrollView {
        position = "absolute", left = 40, right = 40, top = 140, bottom = 40, paddingTop = 10, scrollY = true,
        children = { rl_container },
    })

    Lobby.RefreshRoomList()
end

local function onRoomList(rooms)
    if not rl_container then return end
    rl_container:ClearChildren()
    if not rooms or #rooms == 0 then
        rl_container:AddChild(emptyState { icon = "search", text = _tr("t_YN7UjUprYp7Pv13W"), backgroundColor = C_PANEL })
        return
    end
    for _, room in ipairs(rooms) do
        rl_container:AddChild(makeRoomCard(room))
    end
end

-- ============================================================================
-- 等待房间界面（背景图 + 离开/开始按钮 + onRoomPlayers 玩家格）
-- ============================================================================

local rw_grid = nil
local rw_maxPlayers = 4
local rw_myUserId = 0

local function makePlayerCard(player, isHost, slot)
    if player then
        local name = player.nickname or (_tr("t_1FORcyq8G1EswzfvFm", FormatInt(slot)))
        if #name > 12 then name = string.sub(name, 1, 10) .. ".." end
        local nameLabel = UI.Label { text = name, fontSize = 16, fontColor = C_TEXT }

        if not player.nickname and player.userId then
            local playerScreen = LobbyState.screen
            Lobby.GetUserNickname({
                userIds = { player.userId },
                onSuccess = function(ns)
                    if LobbyState.screen ~= playerScreen or not nameLabel.node then return end
                    if ns and #ns > 0 then
                        local nn = ns[1].nickname or (_tr("t_1FORcyq8G1EswzfvFm", FormatInt(player.userId)))
                        if #nn > 12 then nn = string.sub(nn, 1, 10) .. ".." end
                        nameLabel:SetText(nn)
                    end
                end,
                onError = function()
                    if LobbyState.screen ~= playerScreen or not nameLabel.node then return end
                    nameLabel:SetText(_tr("t_1FORcyq8G1EswzfvFm", FormatInt(player.userId)))
                end,
            })
        end

        local card = UI.Panel {
            width = 200, height = 190, flexDirection = "column", alignItems = "center", justifyContent = "center",
            backgroundColor = C_PANEL, borderRadius = 18, borderWidth = 2,
            borderColor = isHost and { 255, 208, 66, 220 } or { 70, 110, 180, 160 }, gap = 12,
            children = {
                isHost and UI.Panel {
                    position = "absolute", top = 12, left = 12, backgroundColor = { 255, 208, 66, 255 },
                    borderRadius = 6, paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                    children = { UI.Label { text = _tr("t_7hcHOnaS7rhgP4E5"), fontSize = 12, fontWeight = "bold", fontColor = { 40, 35, 20, 255 } } },
                } or false,
                avatarCircle { size = 76, text = "👤", fontSize = 38, bg = { 70, 90, 140, 255 }, borderWidth = 2, borderColor = C_ACCENT },
                nameLabel,
                UI.Label { text = _tr("t_AuY7uRNnB3u9vugo", FormatInt(slot)), fontSize = 12, fontColor = C_MUTED },
            },
        }
        return card
    else
        return UI.Panel {
            width = 200, height = 190, flexDirection = "column", alignItems = "center", justifyContent = "center",
            backgroundColor = { 24, 30, 52, 200 }, borderRadius = 18, borderWidth = 2,
            borderColor = { 60, 80, 120, 120 }, borderStyle = "dashed", gap = 10,
            children = {
                avatarCircle { size = 50, text = "+", fontSize = 30, bg = { 0, 0, 0, 0 }, borderWidth = 2, borderColor = { 90, 110, 150, 150 } },
                UI.Label { text = _tr("t_bruDxYVibjAKQly3"), fontSize = 13, fontColor = C_MUTED },
            },
        }
    end
end

local function onRoomPlayers(players, masterId)
    if not rw_grid then return end
    rw_grid:ClearChildren()

    local isMaster = (masterId == nil) or (masterId == rw_myUserId)
    LobbyUI.room_waiting.start_button.visible = isMaster

    local slot = 1
    if players and #players > 0 then
        for _, p in ipairs(players) do
            rw_grid:AddChild(makePlayerCard(p, masterId and p.userId == masterId, slot))
            slot = slot + 1
        end
    else
        rw_grid:AddChild(makePlayerCard({ userId = rw_myUserId }, true, 1))
        slot = 2
    end
    for i = slot, rw_maxPlayers do
        rw_grid:AddChild(makePlayerCard(nil, false, i))
    end
end

local function buildRoomWaiting()
    rw_myUserId = (Lobby.GetMyUserId and Lobby.GetMyUserId()) or 0
    rw_maxPlayers = (Lobby.config and Lobby.config.maxPlayers) or (Lobby.GetMaxPlayers and Lobby.GetMaxPlayers()) or 4
    if rw_maxPlayers <= 0 then rw_maxPlayers = 4 end

    skinBackground(LobbyUI.room_waiting.background, ScreenBackgroundVisual { kind = "room_waiting" })

    -- 离开（左上）
    skinButton(LobbyUI.room_waiting.leave_button,
        { left = 40, top = 44, width = 130, height = 60 },
        LobbyActionVisual { kind = "nav", icon = "back", label = _tr("t_1FeXFS4xM1FnFysAo5") })

    -- 开始（底部居中，仅房主可见）
    skinButton(LobbyUI.room_waiting.start_button,
        { left = "50%", marginLeft = -160, bottom = 80, width = 320, height = 64 },
        LobbyActionVisual { kind = "start", label = _tr("t_OAaPAePAO1rLaxpB") })

    -- 玩家格（居中网格）
    rw_grid = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", justifyContent = "center", alignContent = "center", gap = 24,
    }
    LobbyUI.room_waiting.background:addChild(UI.Panel {
        position = "absolute", left = 60, right = 60, top = 150, bottom = 170, flexDirection = "row", alignItems = "center", justifyContent = "center",
        children = { rw_grid },
    })

    onRoomPlayers(nil, nil)
end

-- ============================================================================
-- 连服界面（品牌化进度屏：背景图 + 传输通道 + 底部状态栏）
-- ============================================================================

local cn_percentLabel = nil
local cn_statusLabel = nil
local cn_barFill = nil
local cn_stepLabels = nil

function safeProgress(progress)
    progress = tonumber(progress) or 0
    if progress < 0 then return 0 end
    if progress > 1 then return 1 end
    return progress
end

local function buildConnectingStep(text, threshold)
    local label = UI.Label { text = text, fontSize = 13, fontWeight = "bold", fontColor = C_MUTED }
    cn_stepLabels[#cn_stepLabels + 1] = { label = label, threshold = threshold }
    return label
end

local function updateConnecting(progress, status)
    local p = safeProgress(progress)
    local pct = math.floor(p * 100)

    if cn_percentLabel then
        cn_percentLabel:SetText(FormatInt(pct) .. "%")
    end
    if cn_statusLabel and status and status ~= "" then
        cn_statusLabel:SetText(status)
    end
    if cn_barFill then
        cn_barFill:SetStyle({ width = FormatInt(pct) .. "%" })
    end
    if cn_stepLabels then
        for _, step in ipairs(cn_stepLabels) do
            local active = p >= step.threshold
            step.label:SetStyle({
                fontColor = active and C_ACCENT or C_MUTED,
                opacity = active and 1.0 or 0.62,
            })
        end
    end
end

local function buildConnecting()
    local conn = LobbyState.connecting or {}
    local progress = safeProgress(conn.progress)
    local status = (conn.status and conn.status ~= "") and conn.status or _tr("t_rhbBVYd0sD5onNJk")

    cn_stepLabels = {}
    cn_percentLabel = UI.Label { text = FormatInt(math.floor(progress * 100)) .. "%", fontSize = 44, fontWeight = "bold", fontColor = C_TEXT }
    cn_statusLabel = UI.Label { text = status, fontSize = 16, fontColor = C_MUTED }
    cn_barFill = UI.Panel {
        width = FormatInt(math.floor(progress * 100)) .. "%", height = "100%",
        backgroundColor = C_ACCENT, borderRadius = 6,
    }

    skinBackground(LobbyUI.connecting.background, ScreenBackgroundVisual { kind = "connecting" })

    local statusBand = UI.Panel {
        position = "absolute", left = 72, right = 72, bottom = 58, height = 150,
        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
        backgroundColor = { 14, 20, 38, 222 }, borderRadius = 20, borderWidth = 1,
        borderColor = { 110, 180, 255, 120 }, paddingLeft = 34, paddingRight = 34,
        children = {
            UI.Panel {
                width = 170, height = "100%", flexDirection = "column", justifyContent = "center", gap = 6,
                children = {
                    UI.Label { text = _tr("t_LjxJpgVhLESgmAd9"), fontSize = 14, fontColor = C_MUTED },
                    cn_percentLabel,
                },
            },
            UI.Panel {
                flex = 1, height = "100%", flexDirection = "column", justifyContent = "center", gap = 16,
                children = {
                    cn_statusLabel,
                    UI.Panel {
                        width = "100%", height = 12, backgroundColor = { 255, 255, 255, 36 }, borderRadius = 6, overflow = "hidden",
                        children = { cn_barFill },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            buildConnectingStep(_tr("t_d5HoXiHDct9M5dXh"), 0.05),
                            buildConnectingStep(_tr("t_axpZPwiQbOU7unHg"), 0.35),
                            buildConnectingStep(_tr("t_L4KYWkSoKsGmhRDY"), 0.68),
                            buildConnectingStep(_tr("t_ELQkVJczDpw7RWhf"), 0.95),
                        },
                    },
                },
            },
        },
    }
    LobbyUI.connecting.background:addChild(statusBand)
    updateConnecting(progress, status)
end

-- ============================================================================
-- 自定义弹窗（可选）：系统弹窗 / 被踢提示 / 错误提示也能统一成项目美术风格
-- ============================================================================

local function showCustomModal(ctx)
    local accent = ctx.sourceKind == "kicked" and C_WARN or C_ACCENT
    local overlay = UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        alignItems = "center", justifyContent = "center",
        backgroundColor = { 5, 8, 18, 210 },
    }

    local card = UI.Panel {
        width = 560, maxWidth = "82%", flexDirection = "column", alignItems = "center",
        gap = 18, padding = 34, borderRadius = 24,
        backgroundColor = { 18, 26, 48, 245 },
        borderColor = { accent[1], accent[2], accent[3], 170 },
        borderWidth = 2,
    }

    card:AddChild(UI.Label {
        text = ctx.icon or (ctx.sourceKind == "kicked" and "!" or "i"),
        fontSize = 44, fontWeight = "bold", fontColor = accent,
    })
    card:AddChild(UI.Label {
        text = ctx.title or _tr("t_1BxwxT66D1C5FNhUZ5"),
        fontSize = 30, fontWeight = "bold", fontColor = C_TEXT,
        textAlign = "center",
    })
    card:AddChild(UI.Label {
        text = ctx.message or "",
        fontSize = 20, fontColor = C_MUTED, textAlign = "center",
    })

    local ok = UI.Button {
        width = 220, height = 56, borderRadius = 28,
        alignItems = "center", justifyContent = "center",
        backgroundColor = { accent[1], accent[2], accent[3], 235 },
        onClick = function() ctx.close() end,
    }
    ok:AddChild(UI.Label {
        text = ctx.buttonText or _tr("t_1HaGSa5dU1HhU9m7ju"),
        fontSize = 21, fontWeight = "bold", fontColor = { 255, 255, 255, 255 },
    })
    card:AddChild(ok)

    overlay:AddChild(card)
    ctx.mount(overlay)
    return true
end

local function showCustomError(ctx)
    local toast = UI.Panel {
        position = "absolute", right = 46, top = 46, width = 430, minHeight = 92,
        flexDirection = "row", alignItems = "center", gap = 16,
        paddingLeft = 22, paddingRight = 22, borderRadius = 20,
        backgroundColor = { 45, 18, 30, 245 },
        borderColor = { C_WARN[1], C_WARN[2], C_WARN[3], 180 },
        borderWidth = 2,
    }
    toast:AddChild(UI.Label {
        text = "!",
        fontSize = 30, fontWeight = "bold", fontColor = C_WARN,
    })
    toast:AddChild(UI.Label {
        text = ctx.message or "",
        flex = 1, fontSize = 18, fontColor = C_TEXT,
    })

    -- 手动关闭按钮（✕）：自动消失靠大厅每帧推进 Timer，大厅销毁/切场景时定时器停摆、
    -- 到不了期，故必须留手动兜底，否则 toast 会卡住关不掉。
    local closeBtn = UI.Button {
        width = 40, height = 40, borderRadius = 20,
        alignItems = "center", justifyContent = "center",
        backgroundColor = { 255, 255, 255, 28 },
        onClick = function() ctx.close() end,
    }
    -- ✕ 撑满按钮 + 显式居中：✕ 测量宽度为 0（走字体回退），不设宽则盒子塌成 0、
    -- 左对齐时字形从圆心往右画而偏移；故 width/height=100% + textAlign=center 锁定居中。
    closeBtn:AddChild(UI.Label {
        text = "✕", fontSize = 20, fontWeight = "bold", fontColor = C_TEXT,
        width = "100%", height = "100%", textAlign = "center", verticalAlign = "middle",
    })
    toast:AddChild(closeBtn)

    ctx.mount(toast)
    Timer.after(4000, function() ctx.close() end)
    return true
end

-- ============================================================================
-- 注册全部 5 屏 + 弹窗（全流程定制：均不落默认模板）
-- ============================================================================

Lobby.DefineScreen("main",                { enter = buildMain })
Lobby.DefineScreen("quick_match_waiting", { enter = buildQuickMatchWaiting })
Lobby.DefineScreen("room_list",           { enter = buildRoomList, onRoomList = onRoomList })
Lobby.DefineScreen("room_waiting",        { enter = buildRoomWaiting, onRoomPlayers = onRoomPlayers })
Lobby.DefineScreen("connecting",          { enter = buildConnecting, onServerProgress = updateConnecting })
Lobby.DefineDialog("system",              { show = showCustomModal })
Lobby.DefineDialog("dialog",              { show = showCustomModal })
Lobby.DefineDialog("kicked",              { show = showCustomModal })
Lobby.DefineDialog("error",               { show = showCustomError })

print("[lobby_ui] 全流程自定义大厅已注册（5 屏 + 系统弹窗）")
