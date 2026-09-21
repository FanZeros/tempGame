--- engine-startup/loading_ui.lua
--- NanoVG Loading UI for Bootstrap Pipeline
--- Mode B: system logical resolution, responsive layout (landscape + portrait)
--- Visual parity with WASM web version (project-index.html + project-index.js)

local M = {}

------------ Layout Constants (logical pixels) ------------

-- Progress bar (web: height clamp(6px,1vh,10px), radius 999px)
local BAR_H         = 6
local BAR_R         = 3         -- corner radius (pill shape)

-- Typography
local STATUS_FONT_SIZE  = 18    -- web: clamp(14px, 2.5vw, 18px)
local PERCENT_FONT_SIZE = 14    -- web: clamp(12px, 2vw, 16px)
local DETAIL_FONT_SIZE  = 11
local DETAIL_SHOW_DELAY = 5.0   -- seconds before detail text appears

-- Dialog
local DIALOG_TITLE_SIZE   = 18
local DIALOG_MSG_SIZE     = 14
local DIALOG_BTN_SIZE     = 15
local DIALOG_WIDTH        = 400    -- web: min(400px, 85vw)
local DIALOG_RADIUS       = 16
local DIALOG_BTN_RADIUS   = 10
local DIALOG_BTN_H        = 44     -- button height
local DIALOG_BTN_GAP      = 12

-- Animation
local FADE_DURATION      = 0.3
local FADE_OUT_DURATION  = 0.4
local FADE_OUT_DELAY     = 0.0     -- seconds to wait before fade-out starts
local MIN_PROGRESS_SPEED = 0.02    -- per second (slow creep)
local MAX_PROGRESS_SPEED = 3.5     -- per second (chase target)
local DIALOG_FADE_DURATION = 0.25  -- web: transition 0.25s

------------ State ------------

local vg        ---@type userdata  NVG context
local font      ---@type integer   font handle (-1 if failed)
local logoImg   ---@type integer   logo image handle (-1 if failed)
local logoW, logoH = 0, 0

-- Screen dimensions (logical pixels, Mode B)
local logW, logH = 0, 0
local dpr = 1.0

-- Progress
local targetProg  = 0.0
local displayProg = 0.0
local statusText  = ""
local detailText  = ""
local detailTimer = 0.0
local detailShow  = false

-- Loading screen fade (background is always full opacity; contentAlpha fades content elements)
local opacity      = 0.0
local fadingIn     = true
local fadeAnimating = false
local fadeProg     = 0.0
local fadeCallback  = nil
local fadeOutDelay  = 0.0   -- remaining delay before fade-out begins
local contentAlpha  = 0.0   -- separate fade for logo/bar/text (0..1)

-- Dialog state
local dialogVisible   = false
local dialogOpacity   = 0.0    -- 0..1 fade
local dialogFading    = false
local dialogFadeIn    = false
local dialogFadeProg  = 0.0
local dialogTitle     = ""
local dialogMessage   = ""
local dialogConfirmText = "OK"
local dialogCancelText  = ""
local dialogCallback  = nil    -- function(confirmed: boolean)

-- Dialog button hover/press state
local hoverConfirm = false
local hoverCancel  = false
local pressConfirm = false
local pressCancel  = false
-- Cached button rects for hit testing (set during render)
local confirmRect = { x = 0, y = 0, w = 0, h = 0 }
local cancelRect  = { x = 0, y = 0, w = 0, h = 0 }

-- Lifecycle
local alive = false

------------ Resolution (DPR_DENSITY_ADAPTIVE, same as UI.Scale.DEFAULT) ------------

local PC_REF = 720  -- PC reference short side (CSS pixels)

local function CalcScale()
    local rawDpr = graphics:GetDPR()
    local shortSide = math.min(graphics:GetWidth(), graphics:GetHeight()) / rawDpr
    local densityFactor = math.sqrt(shortSide / PC_REF)
    densityFactor = math.max(0.625, math.min(densityFactor, 1.0))
    return rawDpr * densityFactor
end

local function RecalcLayout()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    dpr = CalcScale()
    logW = physW / dpr
    logH = physH / dpr
end

------------ Responsive helpers ------------

--- Progress bar width: 60% of screen width, clamped [200, 600] (web: clamp(300px, 60vw, 600px))
local function GetBarWidth()
    return math.max(200, math.min(logW * 0.6, 600))
end

--- Logo max dimension (logical pixels), orientation-aware.
--- Landscape: 30% width [200, 400]  (web: clamp(300px, 30vw, 400px))
--- Portrait:  50% width [280, 400]  to keep logo readable on narrow screens
local function GetLogoMaxWidth()
    if logH > logW then
        return math.max(280, math.min(logW * 0.6, 400))
    end
    return math.max(200, math.min(logW * 0.3, 400))
end

--- Dialog width: min(400, 85% of screen width) (web: min(400px, 85vw))
local function GetDialogWidth()
    return math.min(DIALOG_WIDTH, logW * 0.85)
end

------------ Hit testing ------------

local function PointInRect(px, py, r)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

------------ Rendering: Loading Screen ------------

local function RenderLoading()
    if opacity <= 0 then return end

    ---- Background: solid black ----
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg)

    ---- Content elements use contentAlpha for fade-in/out ----
    local a = contentAlpha
    if a <= 0 then return end

    local barW = GetBarWidth()
    local barX = (logW - barW) / 2
    local barY = logH * 0.5

    if logoImg and logoImg >= 0 and logoW > 0 then
        local maxW = GetLogoMaxWidth()
        local natW = logoW / dpr
        local natH = logoH / dpr
        local s = math.min(maxW / natW, 1.0)
        local drawW = natW * s
        local drawH = natH * s
        local drawX = (logW - drawW) / 2
        local drawY = barY - 6 - drawH

        local paint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, logoImg, a)
        nvgBeginPath(vg)
        nvgRect(vg, drawX, drawY, drawW, drawH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- Bar background
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, BAR_H, BAR_R)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(25 * a)))
    nvgFill(vg)

    -- Bar foreground
    if displayProg > 0.001 then
        local fgW = barW * displayProg

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX - 4, barY - 4, fgW + 8, BAR_H + 8, BAR_R + 2)
        nvgFillColor(vg, nvgRGBA(78, 158, 255, math.floor(50 * a)))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, fgW, BAR_H, BAR_R)
        local grad = nvgLinearGradient(vg,
            barX, barY, barX + fgW, barY,
            nvgRGBA(74, 158, 255, math.floor(255 * a)),
            nvgRGBA(110, 181, 255, math.floor(255 * a)))
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    -- Status Text
    if font and font >= 0 and statusText ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, STATUS_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(230 * a)))
        nvgText(vg, logW / 2, barY + BAR_H + 16, statusText, nil)
    end

    -- Percent Text
    if font and font >= 0 then
        local pct = math.floor(displayProg * 100)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, PERCENT_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(178 * a)))
        nvgText(vg, logW / 2, barY + BAR_H + 16 + STATUS_FONT_SIZE + 8, tostring(pct) .. "%", nil)
    end

    -- Detail Text
    if font and font >= 0 and detailShow and detailText ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DETAIL_FONT_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(102, 102, 102, math.floor(255 * a)))
        nvgText(vg, 10, logH - 10, detailText, nil)
    end

end

------------ Rendering: Dialog ------------

local function RenderDialog()
    if dialogOpacity <= 0 then return end

    local da = dialogOpacity  -- 0..1

    ---- Overlay (web: rgba(0,0,0,0.6), backdrop-filter blur(8px)) ----
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(153 * da)))
    nvgFill(vg)

    ---- Dialog card ----
    -- web: background rgba(30,30,45,0.95), border 1px rgba(255,255,255,0.08),
    --       border-radius 16px, padding 32px 28px 24px, box-shadow
    local dw = GetDialogWidth()
    local padX, padTop, padBot = 28, 32, 24

    -- Calculate content height
    local titleH = DIALOG_TITLE_SIZE + 4
    local msgH = DIALOG_MSG_SIZE * 2.5  -- approximate 2 lines with line-height 1.6
    local btnAreaH = DIALOG_BTN_H
    local gapTitle = 16
    local gapMsg = 16
    local gapBtn = 8
    local contentH = padTop + titleH + gapTitle + msgH + gapMsg + gapBtn + btnAreaH + padBot

    local dx = (logW - dw) / 2
    local dy = (logH - contentH) / 2

    -- Card shadow (web: box-shadow 0 24px 80px rgba(0,0,0,0.5))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx - 2, dy - 2, dw + 4, contentH + 4, DIALOG_RADIUS + 1)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(80 * da)))
    nvgFill(vg)

    -- Card background (web: rgba(30,30,45,0.95))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx, dy, dw, contentH, DIALOG_RADIUS)
    nvgFillColor(vg, nvgRGBA(30, 30, 45, math.floor(242 * da)))
    nvgFill(vg)

    -- Card border (web: 1px solid rgba(255,255,255,0.08))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx, dy, dw, contentH, DIALOG_RADIUS)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(20 * da)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- Inner highlight (web: box-shadow inset 0 0 0 1px rgba(255,255,255,0.05))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx + 1, dy + 1, dw - 2, contentH - 2, DIALOG_RADIUS - 1)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(13 * da)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local curY = dy + padTop

    ---- Title (web: color rgba(255,255,255,0.95), 18px, font-weight 600) ----
    if font and font >= 0 and dialogTitle ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DIALOG_TITLE_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(242 * da)))
        nvgText(vg, logW / 2, curY, dialogTitle, nil)
        curY = curY + titleH + gapTitle
    end

    ---- Message (web: color rgba(255,255,255,0.6), 14px, line-height 1.6, word-break) ----
    if font and font >= 0 and dialogMessage ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DIALOG_MSG_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(153 * da)))
        -- Use nvgTextBox for word wrapping
        nvgTextBox(vg, dx + padX, curY, dw - padX * 2, dialogMessage, nil)
        curY = curY + msgH + gapMsg + gapBtn
    end

    ---- Buttons (web: flex row, gap 12px, full width) ----
    local hasCancelBtn = dialogCancelText ~= ""
    local btnAreaX = dx + padX
    local btnAreaW = dw - padX * 2

    if hasCancelBtn then
        -- Two buttons: cancel (left) + confirm (right)
        local btnW = (btnAreaW - DIALOG_BTN_GAP) / 2

        -- Cancel button (web: background rgba(255,255,255,0.08), color rgba(255,255,255,0.7))
        local cBg = hoverCancel and 30 or 20
        if pressCancel then cBg = 30 end
        cancelRect = { x = btnAreaX, y = curY, w = btnW, h = DIALOG_BTN_H }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelRect.x, cancelRect.y, cancelRect.w, cancelRect.h, DIALOG_BTN_RADIUS)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(cBg * da)))
        nvgFill(vg)

        if font and font >= 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, DIALOG_BTN_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(178 * da)))
            nvgText(vg, cancelRect.x + cancelRect.w / 2, cancelRect.y + cancelRect.h / 2, dialogCancelText, nil)
        end

        -- Confirm button (web: gradient #5b6af0 -> #7c5bf0, color #fff)
        local cA = (pressConfirm and 217) or 255
        confirmRect = { x = btnAreaX + btnW + DIALOG_BTN_GAP, y = curY, w = btnW, h = DIALOG_BTN_H }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmRect.x, confirmRect.y, confirmRect.w, confirmRect.h, DIALOG_BTN_RADIUS)
        local btnGrad = nvgLinearGradient(vg,
            confirmRect.x, confirmRect.y,
            confirmRect.x + confirmRect.w, confirmRect.y + confirmRect.h,
            nvgRGBA(91, 106, 240, math.floor(cA * da)),
            nvgRGBA(124, 91, 240, math.floor(cA * da)))
        nvgFillPaint(vg, btnGrad)
        nvgFill(vg)

        if font and font >= 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, DIALOG_BTN_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * da)))
            nvgText(vg, confirmRect.x + confirmRect.w / 2, confirmRect.y + confirmRect.h / 2, dialogConfirmText, nil)
        end
    else
        -- Single confirm button (full width)
        local cA = (pressConfirm and 217) or 255
        confirmRect = { x = btnAreaX, y = curY, w = btnAreaW, h = DIALOG_BTN_H }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmRect.x, confirmRect.y, confirmRect.w, confirmRect.h, DIALOG_BTN_RADIUS)
        local btnGrad = nvgLinearGradient(vg,
            confirmRect.x, confirmRect.y,
            confirmRect.x + confirmRect.w, confirmRect.y + confirmRect.h,
            nvgRGBA(91, 106, 240, math.floor(cA * da)),
            nvgRGBA(124, 91, 240, math.floor(cA * da)))
        nvgFillPaint(vg, btnGrad)
        nvgFill(vg)

        if font and font >= 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, DIALOG_BTN_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * da)))
            nvgText(vg, confirmRect.x + confirmRect.w / 2, confirmRect.y + confirmRect.h / 2, dialogConfirmText, nil)
        end

        cancelRect = { x = 0, y = 0, w = 0, h = 0 }
    end
end

------------ Main Render Entry ------------

local function Render()
    if not alive or not vg then return end
    if opacity <= 0 and dialogOpacity <= 0 then return end

    nvgBeginFrame(vg, logW, logH, dpr)

    RenderLoading()
    RenderDialog()

    nvgEndFrame(vg)
end

------------ Update Logic ------------

local function Update(dt)
    if not alive then return end

    -- Content elements fade-in (ease-out quadratic)
    if contentAlpha < 1.0 and opacity >= 1.0 and not (fadeAnimating and not fadingIn) then
        contentAlpha = math.min(contentAlpha + dt / FADE_DURATION, 1.0)
    end

    -- Fade-out delay countdown
    if fadeOutDelay > 0 then
        fadeOutDelay = fadeOutDelay - dt
        if fadeOutDelay <= 0 then
            fadeOutDelay = 0
            fadeAnimating = true
            fadeProg = 0
        end
    end

    -- Loading screen fade-out animation (ease-out quadratic)
    if fadeAnimating then
        local dur = FADE_OUT_DURATION
        fadeProg = fadeProg + dt / dur
        if fadeProg >= 1.0 then
            fadeProg = 1.0
            fadeAnimating = false
            opacity = 0.0
            contentAlpha = 0.0
            if fadeCallback then
                local cb = fadeCallback
                fadeCallback = nil
                cb()
            end
        else
            local t = 1.0 - fadeProg
            opacity = t * t  -- ease-out (reverse)
            contentAlpha = t * t
        end
    end

    -- Dialog fade animation
    if dialogFading then
        dialogFadeProg = dialogFadeProg + dt / DIALOG_FADE_DURATION
        if dialogFadeProg >= 1.0 then
            dialogFadeProg = 1.0
            dialogFading = false
            dialogOpacity = dialogFadeIn and 1.0 or 0.0
            if not dialogFadeIn then
                dialogVisible = false
            end
        else
            local t = dialogFadeIn and dialogFadeProg or (1.0 - dialogFadeProg)
            dialogOpacity = t  -- linear for short duration
        end
    end

    -- Progress smoothing
    local minD = MIN_PROGRESS_SPEED * dt
    local maxD = MAX_PROGRESS_SPEED * dt
    local delta = targetProg - displayProg

    if delta > 0 then
        displayProg = displayProg + math.max(minD, math.min(delta, maxD))
        displayProg = math.min(displayProg, targetProg)
    else
        -- Slow creep: limit to small margin beyond actual progress
        -- Prevents display from reaching 99% when real progress is much lower
        local maxCreep = targetProg > 0 and math.min(targetProg + 0.05, 0.99) or 0.0
        if displayProg < maxCreep then
            displayProg = math.min(displayProg + minD, maxCreep)
        end
    end

    -- Snap to 100% when close enough
    if targetProg >= 1.0 and displayProg > 0.95 then
        displayProg = 1.0
    end

    -- Detail text delay
    if detailText ~= "" then
        detailTimer = detailTimer + dt
        if detailTimer >= DETAIL_SHOW_DELAY then
            detailShow = true
        end
    end

    -- Dialog button hover tracking
    if dialogVisible and dialogOpacity > 0 then
        local pos = input:GetMousePosition()
        local mx = pos.x / dpr
        local my = pos.y / dpr
        hoverConfirm = PointInRect(mx, my, confirmRect)
        hoverCancel  = PointInRect(mx, my, cancelRect)
    else
        hoverConfirm = false
        hoverCancel = false
    end
end

------------ Dialog dismiss ------------

local function DismissDialog(confirmed)
    if not dialogVisible then return end

    -- Start fade out
    dialogFading = true
    dialogFadeIn = false
    dialogFadeProg = 0

    if dialogCallback then
        local cb = dialogCallback
        dialogCallback = nil
        cb(confirmed)
    end
end

------------ Global Event Handlers ------------

function __LoadingUI_Render(eventType, eventData)
    Render()
end

function __LoadingUI_Update(eventType, eventData)
    Update(eventData["TimeStep"]:GetFloat())
end

function __LoadingUI_ScreenMode(eventType, eventData)
    RecalcLayout()
end

function __LoadingUI_MouseButtonUp(eventType, eventData)
    if not dialogVisible or dialogOpacity <= 0 then return end

    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr

    if PointInRect(mx, my, confirmRect) then
        pressConfirm = false
        DismissDialog(true)
    elseif PointInRect(mx, my, cancelRect) then
        pressCancel = false
        DismissDialog(false)
    end
end

function __LoadingUI_MouseButtonDown(eventType, eventData)
    if not dialogVisible or dialogOpacity <= 0 then return end

    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr

    pressConfirm = PointInRect(mx, my, confirmRect)
    pressCancel  = PointInRect(mx, my, cancelRect)
end

function __LoadingUI_TouchEnd(eventType, eventData)
    if not dialogVisible or dialogOpacity <= 0 then return end

    local tx = eventData["X"]:GetInt() / dpr
    local ty = eventData["Y"]:GetInt() / dpr

    if PointInRect(tx, ty, confirmRect) then
        DismissDialog(true)
    elseif PointInRect(tx, ty, cancelRect) then
        DismissDialog(false)
    end
end

------------ Public API ------------

--- Initialize NVG loading UI
--- @param ctx BootstrapContext  pipeline context
--- @return boolean success
function M.Init(ctx)
    vg = nvgCreate(1)  -- 1 = edge anti-alias
    if not vg then
        print("[LoadingUI] Failed to create NVG context")
        return false
    end

    -- Render at lowest layer (below game NVG)
    nvgSetRenderOrder(vg, 999999)

    font = nvgCreateFont(vg, "sans", "Fonts/Anonymous Pro.ttf")

    -- Load logo image
    local logoPath = ctx.logoTexture
    if logoPath and logoPath ~= "" then
        logoImg = nvgCreateImage(vg, logoPath, 1)
        if logoImg and logoImg >= 0 then
            logoW, logoH = nvgImageSize(vg, logoImg)
        end
    end

    RecalcLayout()

    -- C++ LoadingUI renders on top of NVG, so fade-in is not visible.
    -- Show Lua UI at full opacity immediately, then hide C++ UI.
    ctx:HideNativeLoadingUI()

    -- Override progress callback
    -- totalProgress: C++ 归一化的全局进度 0-1（含 RecalculateWeights 平滑后的值）
    -- stageProgress: 当前步骤内局部进度 0-1（不用于进度条）
    ctx:SetProgressCallback(function(stageProgress, totalProgress, step, detail, incrementSpeed)
        local newTarget = math.max(0, math.min(1, totalProgress))

        -- 加载完成时关闭残留的错误弹窗（宿主端已响应但弹窗仍在显示）
        if dialogVisible and newTarget >= 1.0 then M.HideDialog() end

        -- 只向前不向后（C++ 侧已保证单调，这里做最后防线）
        if newTarget > targetProg then
            targetProg = newTarget
        end

        -- C++ 传入的 speed（0-1/s），覆盖本地 creep 速度
        if incrementSpeed and incrementSpeed > 0 then
            MIN_PROGRESS_SPEED = incrementSpeed
        elseif incrementSpeed and incrementSpeed < 0 then
            MIN_PROGRESS_SPEED = 0.02  -- 恢复默认
        end

        statusText = step or ""

        if detail and detail ~= detailText then
            detailText = detail
            detailTimer = 0
            detailShow = false
        end
    end)

    -- i18n helper (same keys as C++ BootstrapManager)
    local l10n = localization
    local function Tr(key) return l10n and l10n:Get(key) or key end

    -- Override message callback (single-button notification)
    -- C++ passes (message, callbackId) — resolve via ctx:ResolveDialogCallback
    ctx:SetShowMessageCallback(function(message, callbackId)
        M.ShowDialog(Tr("Warning"), message, Tr("OK"), nil, function()
            ctx:ResolveDialogCallback(callbackId, true)
        end)
    end)

    -- Override confirm-retry callback (two-button retry/cancel dialog)
    -- C++ passes (message, callbackId) — resolve with true (retry) or false (cancel)
    ctx:SetConfirmRetryCallback(function(message, callbackId)
        M.ShowDialog(Tr("Loading Failed"), message, Tr("Retry"), Tr("Exit"), function(confirmed)
            ctx:ResolveDialogCallback(callbackId, confirmed)
        end)
    end)

    -- Subscribe events (after HideNativeLoadingUI to avoid re-entrant calls)
    SubscribeToEvent(vg, "NanoVGRender", "__LoadingUI_Render")
    SubscribeToEvent("Update", "__LoadingUI_Update")
    SubscribeToEvent("ScreenMode", "__LoadingUI_ScreenMode")
    SubscribeToEvent("MouseButtonUp", "__LoadingUI_MouseButtonUp")
    SubscribeToEvent("MouseButtonDown", "__LoadingUI_MouseButtonDown")
    SubscribeToEvent("TouchEnd", "__LoadingUI_TouchEnd")

    -- Background visible immediately; content elements fade in via contentAlpha
    alive = true
    fadeAnimating = false
    fadingIn = false
    fadeProg = 1.0
    opacity = 1.0
    contentAlpha = 0.0

    return true
end

--- Start fade-out animation
--- @param callback function?  called after fade-out completes
function M.FadeOut(callback)
    fadeCallback = callback
    fadingIn = false
    if FADE_OUT_DELAY > 0 then
        fadeOutDelay = FADE_OUT_DELAY
        fadeAnimating = false
    else
        fadeOutDelay = 0
        fadeAnimating = true
        fadeProg = 0
    end
end

--- Show a dialog on the loading screen
--- Matches WASM web version UrhoX.showDialog() behavior
--- @param title string       dialog title
--- @param message string     dialog message body
--- @param confirmText string confirm button text (default "OK")
--- @param cancelText string? cancel button text (nil or "" to hide)
--- @param callback function? function(confirmed: boolean) called on dismiss
function M.ShowDialog(title, message, confirmText, cancelText, callback)
    dialogTitle = title or ""
    dialogMessage = message or ""
    dialogConfirmText = confirmText or "OK"
    dialogCancelText = cancelText or ""
    dialogCallback = callback

    dialogVisible = true
    dialogFading = true
    dialogFadeIn = true
    dialogFadeProg = 0

    hoverConfirm = false
    hoverCancel = false
    pressConfirm = false
    pressCancel = false
end

--- Hide the dialog (with fade animation)
function M.HideDialog()
    if dialogVisible then
        DismissDialog(false)
    end
end

--- Check if dialog is currently visible
--- @return boolean
function M.IsDialogVisible()
    return dialogVisible
end

--- Destroy NVG resources and unsubscribe events
function M.Destroy()
    alive = false

    if vg then
        if logoImg and logoImg >= 0 then
            nvgDeleteImage(vg, logoImg)
            logoImg = -1
        end
        nvgDelete(vg)
        vg = nil
    end
end

return M
