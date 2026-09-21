--- engine-startup/startup_ui.lua
--- Review-mode startup login page (NanoVG). Visual-only UI; login logic stays in main.lua.
local M = {}

------------ Design Constants ------------

local TAP_BLUE = { r = 0, g = 217, b = 197 }
local BG = { r = 10, g = 10, b = 10 }
local LANDSCAPE_BG_IMAGE = "Textures/startup_login_bg.png"

local DISCLAIMER =
    "本公司积极履行《网络游戏行业防沉迷自律公约》 抵制不良游戏，拒绝盗版游戏。注意自我保护，谨防受骗上当。 适度游戏益脑，沉迷游戏伤身。合理安排时间，享受健康生活。"
local DISCLAIMER_LINES = {
    "本公司积极履行《网络游戏行业防沉迷自律公约》",
    "抵制不良游戏，拒绝盗版游戏。注意自我保护，谨防受骗上当。",
    "适度游戏益脑，沉迷游戏伤身。合理安排时间，享受健康生活。",
}

local LANDSCAPE_LAYOUT = {
    designW = 2040,
    designH = 1080,
    logoCenterX = 1020,
    logoBaselineY = 446,
    logoTargetW = 506,
    btnW = 299.6,
    btnH = 71.4,
    btnR = 35.7,
    btnY = 600,
    loginFontSize = 26,
    loginGap = 12,
    tapLogoMaxH = 0.45,
    agreementY = 724,
    agreementFontSize = 22,
    agreementAlpha = 153,
    checkBoxSize = 24,
    checkBoxR = 4,
    agreementGap = 12,
    ageX = 24,
    ageY = 24,
    ageW = 64,
    bottomY = 1022,
    bottomH = 48,
    bottomFontSize = 16,
    dialogCardW = 560,
    dialogPad = 40,
    dialogTopPad = 40,
    dialogTitleSize = 32,
    dialogTitleH = 47,
    dialogTitleGap = 32,
    dialogContentMinH = 32,
    dialogSegmentContentH = 128,
    dialogLineH = 32,
    dialogMessageSize = 20,
    dialogActionGap = 32,
    dialogBtnW = 200,
    dialogBtnH = 62,
    dialogBtnR = 12,
    dialogBtnGap = 16,
    dialogBottomPad = 40,
    dialogCornerR = 24,
    dialogShadowOffset = 12,
    realNameCardW = 560,
    realNameCardY = 165.5,
    realNamePadX = 56,
    realNameHeaderOffsetY = 52,
    realNameTitleH = 40,
    realNameTitleSize = 32,
    realNameCloseSize = 40,
    realNameBodyOffsetY = 150,
    realNameBodySize = 20,
    realNameLineH = 28,
    realNameInputTopGap = 40,
    realNameFieldH = 70,
    realNameFieldGap = 24,
    realNameSubmitTopGap = 40,
    realNameSubmitH = 74,
    realNameBottomPad = 56,
    realNameInputTextSize = 22,
    realNameErrorSize = 18,
    realNameButtonTextSize = 26,
    realNameCornerR = 20,
}

local PORTRAIT_LAYOUT = {
    designW = 1080,
    designH = 2040,
    logoCenterX = 540,
    logoBaselineY = 980,
    logoTargetW = 720,
    btnW = 480,
    btnH = 112,
    btnR = 56,
    btnY = 1140,
    loginFontSize = 36,
    loginGap = 20,
    tapLogoMaxH = 37 / 112,
    agreementY = 1316,
    agreementFontSize = 30,
    agreementAlpha = 204,
    checkBoxSize = 32,
    checkBoxR = 6,
    agreementGap = 16,
    ageX = 48,
    ageY = 32,
    ageW = 100,
    bottomLines = DISCLAIMER_LINES,
    bottomMargin = 60,
    bottomFontSize = 24,
    bottomLineH = 42,
    dialogCardW = 920,
    dialogPad = 76,
    dialogTopPad = 76,
    dialogTitleSize = 48,
    dialogTitleH = 68,
    dialogTitleGap = 48,
    dialogContentMinH = 132,
    dialogSegmentContentH = 280,
    dialogLineH = 52,
    dialogMessageSize = 34,
    dialogActionGap = 54,
    dialogBtnW = 360,
    dialogBtnH = 104,
    dialogBtnR = 22,
    dialogBtnGap = 32,
    dialogBottomPad = 76,
    dialogCornerR = 36,
    dialogShadowOffset = 14,
    realNameCardW = 860,
    realNamePadX = 64,
    realNameHeaderOffsetY = 64,
    realNameTitleH = 56,
    realNameTitleSize = 40,
    realNameCloseSize = 48,
    realNameBodyOffsetY = 164,
    realNameBodySize = 26,
    realNameLineH = 40,
    realNameInputTopGap = 48,
    realNameFieldH = 96,
    realNameFieldGap = 32,
    realNameSubmitTopGap = 52,
    realNameSubmitH = 96,
    realNameBottomPad = 72,
    realNameInputTextSize = 30,
    realNameErrorSize = 22,
    realNameButtonTextSize = 34,
    realNameCornerR = 28,
}

local activeLayout = LANDSCAPE_LAYOUT
local DESIGN_W = LANDSCAPE_LAYOUT.designW
local DESIGN_H = LANDSCAPE_LAYOUT.designH
local LOGO_CENTER_X = LANDSCAPE_LAYOUT.logoCenterX
local LOGO_BASELINE_Y = LANDSCAPE_LAYOUT.logoBaselineY
local LOGO_TARGET_W = LANDSCAPE_LAYOUT.logoTargetW
local BTN_W = LANDSCAPE_LAYOUT.btnW
local BTN_H = LANDSCAPE_LAYOUT.btnH
local BTN_R = LANDSCAPE_LAYOUT.btnR
local BTN_X = (DESIGN_W - BTN_W) * 0.5
local BTN_Y = LANDSCAPE_LAYOUT.btnY
local LOGIN_FONT_SIZE = LANDSCAPE_LAYOUT.loginFontSize
local LOGIN_GAP = LANDSCAPE_LAYOUT.loginGap
local TAP_LOGO_MAX_H = LANDSCAPE_LAYOUT.tapLogoMaxH
local AGREEMENT_Y = LANDSCAPE_LAYOUT.agreementY
local AGREEMENT_FONT_SIZE = LANDSCAPE_LAYOUT.agreementFontSize
local AGREEMENT_ALPHA = LANDSCAPE_LAYOUT.agreementAlpha
local CHECKBOX_SIZE = LANDSCAPE_LAYOUT.checkBoxSize
local CHECKBOX_R = LANDSCAPE_LAYOUT.checkBoxR
local AGREEMENT_GAP = LANDSCAPE_LAYOUT.agreementGap
local AGE_X = LANDSCAPE_LAYOUT.ageX
local AGE_Y = LANDSCAPE_LAYOUT.ageY
local AGE_W = LANDSCAPE_LAYOUT.ageW
local BOTTOM_Y = LANDSCAPE_LAYOUT.bottomY
local BOTTOM_H = LANDSCAPE_LAYOUT.bottomH
local BOTTOM_FONT_SIZE = LANDSCAPE_LAYOUT.bottomFontSize
local BOTTOM_LINE_H = LANDSCAPE_LAYOUT.bottomLineH
local BOTTOM_MARGIN = LANDSCAPE_LAYOUT.bottomMargin
local BOTTOM_LINES = LANDSCAPE_LAYOUT.bottomLines
local DIALOG_CARD_W = LANDSCAPE_LAYOUT.dialogCardW
local DIALOG_PAD = LANDSCAPE_LAYOUT.dialogPad
local DIALOG_TOP_PAD = LANDSCAPE_LAYOUT.dialogTopPad
local DIALOG_TITLE_SIZE = LANDSCAPE_LAYOUT.dialogTitleSize
local DIALOG_TITLE_H = LANDSCAPE_LAYOUT.dialogTitleH
local DIALOG_TITLE_GAP = LANDSCAPE_LAYOUT.dialogTitleGap
local DIALOG_CONTENT_MIN_H = LANDSCAPE_LAYOUT.dialogContentMinH
local DIALOG_SEGMENT_CONTENT_H = LANDSCAPE_LAYOUT.dialogSegmentContentH
local DIALOG_LINE_H = LANDSCAPE_LAYOUT.dialogLineH
local DIALOG_MESSAGE_SIZE = LANDSCAPE_LAYOUT.dialogMessageSize
local DIALOG_ACTION_GAP = LANDSCAPE_LAYOUT.dialogActionGap
local DIALOG_BTN_W = LANDSCAPE_LAYOUT.dialogBtnW
local DIALOG_BTN_H = LANDSCAPE_LAYOUT.dialogBtnH
local DIALOG_BTN_R = LANDSCAPE_LAYOUT.dialogBtnR
local DIALOG_BTN_GAP = LANDSCAPE_LAYOUT.dialogBtnGap
local DIALOG_BOTTOM_PAD = LANDSCAPE_LAYOUT.dialogBottomPad
local DIALOG_CORNER_R = LANDSCAPE_LAYOUT.dialogCornerR
local DIALOG_SHADOW_OFFSET = LANDSCAPE_LAYOUT.dialogShadowOffset
local REAL_NAME_CARD_W = LANDSCAPE_LAYOUT.realNameCardW
local REAL_NAME_CARD_Y = LANDSCAPE_LAYOUT.realNameCardY
local REAL_NAME_PAD_X = LANDSCAPE_LAYOUT.realNamePadX
local REAL_NAME_HEADER_OFFSET_Y = LANDSCAPE_LAYOUT.realNameHeaderOffsetY
local REAL_NAME_TITLE_H = LANDSCAPE_LAYOUT.realNameTitleH
local REAL_NAME_TITLE_SIZE = LANDSCAPE_LAYOUT.realNameTitleSize
local REAL_NAME_CLOSE_SIZE = LANDSCAPE_LAYOUT.realNameCloseSize
local REAL_NAME_BODY_OFFSET_Y = LANDSCAPE_LAYOUT.realNameBodyOffsetY
local REAL_NAME_BODY_SIZE = LANDSCAPE_LAYOUT.realNameBodySize
local REAL_NAME_LINE_H = LANDSCAPE_LAYOUT.realNameLineH
local REAL_NAME_INPUT_TOP_GAP = LANDSCAPE_LAYOUT.realNameInputTopGap
local REAL_NAME_FIELD_H = LANDSCAPE_LAYOUT.realNameFieldH
local REAL_NAME_FIELD_GAP = LANDSCAPE_LAYOUT.realNameFieldGap
local REAL_NAME_SUBMIT_TOP_GAP = LANDSCAPE_LAYOUT.realNameSubmitTopGap
local REAL_NAME_SUBMIT_H = LANDSCAPE_LAYOUT.realNameSubmitH
local REAL_NAME_BOTTOM_PAD = LANDSCAPE_LAYOUT.realNameBottomPad
local REAL_NAME_INPUT_TEXT_SIZE = LANDSCAPE_LAYOUT.realNameInputTextSize
local REAL_NAME_ERROR_SIZE = LANDSCAPE_LAYOUT.realNameErrorSize
local REAL_NAME_BUTTON_TEXT_SIZE = LANDSCAPE_LAYOUT.realNameButtonTextSize
local REAL_NAME_CORNER_R = LANDSCAPE_LAYOUT.realNameCornerR

------------ Persistent Agreement State ------------

-- Mirror AppBox: desktop uses program dir, other platforms use user documents dir.
local function GetAgreementRootDir()
    if not fileSystem then return "" end
    local plat = GetPlatform and GetPlatform() or ""
    if plat == "Windows" or plat == "macOS" then
        return fileSystem:GetProgramDir()
    end
    return fileSystem:GetUserDocumentsDir()
end

local AGREEMENT_ROOT_DIR = GetAgreementRootDir()
local SENTINEL_DIR = AGREEMENT_ROOT_DIR ~= "" and (AGREEMENT_ROOT_DIR .. "User/") or ""
local SENTINEL_PATH = SENTINEL_DIR ~= "" and (SENTINEL_DIR .. "agreement_accepted") or ""

local function HasAgreementSentinel()
    return fileSystem and SENTINEL_PATH ~= "" and fileSystem:FileExists(SENTINEL_PATH)
end

local function WriteAgreementSentinel()
    if not fileSystem or SENTINEL_DIR == "" then return end
    if not fileSystem:DirExists(SENTINEL_DIR) then
        fileSystem:CreateDir(SENTINEL_DIR)
    end
    local f = io.open(SENTINEL_PATH, "w")
    if f then
        f:write("1")
        f:close()
    end
end

------------ State ------------

local vg        ---@type userdata
local fontRegular = -1
local fontBold = -1
local imgTapLogo = -1
local imgAgeRating = -1
local imgLandscapeBg = -1
local imgTapLogoW, imgTapLogoH = 0, 0
local imgAgeRatingW, imgAgeRatingH = 0, 0
local imgLandscapeBgW, imgLandscapeBgH = 0, 0

local logW, logH = 0, 0
local dpr = 1.0
local designScale = 1.0
local designX, designY = 0, 0

local hover = false
local press = false
local btnRect = { x = 0, y = 0, w = 0, h = 0 }
local agreementChecked = false
local agreementHotRect = { x = 0, y = 0, w = 0, h = 0 }

local modal = nil
local hoverConfirm = false
local hoverCancel = false
local pressConfirm = false
local pressCancel = false
local confirmRect = { x = 0, y = 0, w = 0, h = 0 }
local cancelRect = { x = 0, y = 0, w = 0, h = 0 }

local linkRects = {}  -- { {x,y,w,h,url}, ... } 协议链接点击区域

-- 实名认证输入状态
local realNameInput = ""
local idCardInput = ""
local focusedField = nil  -- "name" | "id" | nil
local nameFieldRect = { x = 0, y = 0, w = 0, h = 0 }
local idFieldRect = { x = 0, y = 0, w = 0, h = 0 }
local cursorBlinkTime = 0
local realNameSubmitting = false
local realNameError = ""

local AGREEMENT_URL = "https://icni6xijhzyf.feishu.cn/wiki/BcSdwv0JWiREERkmGvdcFPMZn1d"
local PRIVACY_URL = "https://icni6xijhzyf.feishu.cn/wiki/UpQrwlgoqiJ2yKkiWuRcW3AFnxb"

local onClickCallback = nil
local alive = false

------------ Helpers ------------

local function Color(c, a)
    return nvgRGBA(c.r, c.g, c.b, a or 255)
end

local function Rgba(r, g, b, a)
    return nvgRGBA(r, g, b, a)
end

local function CalcScale()
    local rawDpr = graphics:GetDPR()
    local shortSide = math.min(graphics:GetWidth(), graphics:GetHeight()) / rawDpr
    local densityFactor = math.max(0.625, math.min(math.sqrt(shortSide / 720), 1.0))
    return rawDpr * densityFactor
end

local function ApplyLayout(layout)
    activeLayout = layout
    DESIGN_W = layout.designW
    DESIGN_H = layout.designH
    LOGO_CENTER_X = layout.logoCenterX
    LOGO_BASELINE_Y = layout.logoBaselineY
    LOGO_TARGET_W = layout.logoTargetW
    BTN_W = layout.btnW
    BTN_H = layout.btnH
    BTN_R = layout.btnR
    BTN_X = (DESIGN_W - BTN_W) * 0.5
    BTN_Y = layout.btnY
    LOGIN_FONT_SIZE = layout.loginFontSize
    LOGIN_GAP = layout.loginGap
    TAP_LOGO_MAX_H = layout.tapLogoMaxH
    AGREEMENT_Y = layout.agreementY
    AGREEMENT_FONT_SIZE = layout.agreementFontSize
    AGREEMENT_ALPHA = layout.agreementAlpha
    CHECKBOX_SIZE = layout.checkBoxSize
    CHECKBOX_R = layout.checkBoxR
    AGREEMENT_GAP = layout.agreementGap
    AGE_X = layout.ageX
    AGE_Y = layout.ageY
    AGE_W = layout.ageW
    BOTTOM_Y = layout.bottomY
    BOTTOM_H = layout.bottomH
    BOTTOM_FONT_SIZE = layout.bottomFontSize
    BOTTOM_LINE_H = layout.bottomLineH
    BOTTOM_MARGIN = layout.bottomMargin
    BOTTOM_LINES = layout.bottomLines
    DIALOG_CARD_W = layout.dialogCardW
    DIALOG_PAD = layout.dialogPad
    DIALOG_TOP_PAD = layout.dialogTopPad
    DIALOG_TITLE_SIZE = layout.dialogTitleSize
    DIALOG_TITLE_H = layout.dialogTitleH
    DIALOG_TITLE_GAP = layout.dialogTitleGap
    DIALOG_CONTENT_MIN_H = layout.dialogContentMinH
    DIALOG_SEGMENT_CONTENT_H = layout.dialogSegmentContentH
    DIALOG_LINE_H = layout.dialogLineH
    DIALOG_MESSAGE_SIZE = layout.dialogMessageSize
    DIALOG_ACTION_GAP = layout.dialogActionGap
    DIALOG_BTN_W = layout.dialogBtnW
    DIALOG_BTN_H = layout.dialogBtnH
    DIALOG_BTN_R = layout.dialogBtnR
    DIALOG_BTN_GAP = layout.dialogBtnGap
    DIALOG_BOTTOM_PAD = layout.dialogBottomPad
    DIALOG_CORNER_R = layout.dialogCornerR
    DIALOG_SHADOW_OFFSET = layout.dialogShadowOffset
    REAL_NAME_CARD_W = layout.realNameCardW
    REAL_NAME_CARD_Y = layout.realNameCardY
    REAL_NAME_PAD_X = layout.realNamePadX
    REAL_NAME_HEADER_OFFSET_Y = layout.realNameHeaderOffsetY
    REAL_NAME_TITLE_H = layout.realNameTitleH
    REAL_NAME_TITLE_SIZE = layout.realNameTitleSize
    REAL_NAME_CLOSE_SIZE = layout.realNameCloseSize
    REAL_NAME_BODY_OFFSET_Y = layout.realNameBodyOffsetY
    REAL_NAME_BODY_SIZE = layout.realNameBodySize
    REAL_NAME_LINE_H = layout.realNameLineH
    REAL_NAME_INPUT_TOP_GAP = layout.realNameInputTopGap
    REAL_NAME_FIELD_H = layout.realNameFieldH
    REAL_NAME_FIELD_GAP = layout.realNameFieldGap
    REAL_NAME_SUBMIT_TOP_GAP = layout.realNameSubmitTopGap
    REAL_NAME_SUBMIT_H = layout.realNameSubmitH
    REAL_NAME_BOTTOM_PAD = layout.realNameBottomPad
    REAL_NAME_INPUT_TEXT_SIZE = layout.realNameInputTextSize
    REAL_NAME_ERROR_SIZE = layout.realNameErrorSize
    REAL_NAME_BUTTON_TEXT_SIZE = layout.realNameButtonTextSize
    REAL_NAME_CORNER_R = layout.realNameCornerR
end

local function UpdateButtonRect()
    btnRect.x = designX + BTN_X * designScale
    btnRect.y = designY + BTN_Y * designScale
    btnRect.w = BTN_W * designScale
    btnRect.h = BTN_H * designScale
end

local function RecalcLayout()
    dpr = CalcScale()
    logW = graphics:GetWidth() / dpr
    logH = graphics:GetHeight() / dpr
    ApplyLayout(logH > logW and PORTRAIT_LAYOUT or LANDSCAPE_LAYOUT)
    designScale = math.min(logW / DESIGN_W, logH / DESIGN_H)
    designX = (logW - DESIGN_W * designScale) * 0.5
    designY = (logH - DESIGN_H * designScale) * 0.5
    UpdateButtonRect()
end

local function SetRealNameInputVisible(visible)
    if input and input.SetScreenKeyboardVisible then
        input:SetScreenKeyboardVisible(visible)
    end
end

local function PointInRect(px, py, r)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

local function ScreenToDesign(px, py)
    return (px - designX) / designScale, (py - designY) / designScale
end

local function CheckLinkClick(dx, dy)
    for _, link in ipairs(linkRects) do
        if PointInRect(dx, dy, link) then
            if OpenUrl then
                OpenUrl(link.url)
            end
            return true
        end
    end
    return false
end

local function UseFont(bold, size)
    local id = bold and fontBold or fontRegular
    if id and id >= 0 then
        nvgFontFaceId(vg, id)
        nvgFontSize(vg, size)
        nvgTextLetterSpacing(vg, 0)
        return true
    end
    return false
end

local function DrawText(x, y, text, size, color, align, bold)
    if not UseFont(bold, size) then return 0 end
    nvgTextAlign(vg, align)
    nvgFillColor(vg, color)
    return nvgText(vg, x, y, text, nil) or 0
end

local function TextWidth(text, size, bold)
    if not UseFont(bold, size) then return 0 end
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    return nvgTextBounds(vg, 0, 0, text) or 0
end

local function FillRoundedRect(x, y, w, h, r, color)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgFillColor(vg, color)
    nvgFill(vg)
end

local function StrokeRoundedRect(x, y, w, h, r, color, width)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
    nvgStrokeColor(vg, color)
    nvgStrokeWidth(vg, width)
    nvgStroke(vg)
end

local function ShowCommonDialog(config)
    modal = config or {}
    hoverConfirm = false
    hoverCancel = false
    pressConfirm = false
    pressCancel = false
end

local function CloseDialog(confirmed)
    local current = modal
    modal = nil
    hoverConfirm = false
    hoverCancel = false
    pressConfirm = false
    pressCancel = false
    if current and current.kind == "real_name" then
        SetRealNameInputVisible(false)
    end
    if current and current.onClose then
        current.onClose(confirmed)
    end
end

local function ShowReadAgreementFirstDialog()
    ShowCommonDialog({
        title = "提示",
        message = "请先阅读并勾选同意协议",
        confirmText = "确认",
        align = "center",
        contentH = 32,
        onClose = function() end,
    })
end

local function ShowAgreementDialog()
    ShowCommonDialog({
        title = "温馨提示",
        confirmText = "同意",
        cancelText = "退出",
        align = "left",
        contentH = 128,
        segments = {
            { text = "开始游戏前请仔细阅读", color = Rgba(160, 160, 160, 255), bold = false },
            { text = "《服务协议》", color = Color(TAP_BLUE, 255), bold = true },
            { text = "、", color = Rgba(160, 160, 160, 255), bold = false },
            { text = "《逸派玩游戏隐私保护指引》", color = Color(TAP_BLUE, 255), bold = true },
            { text = "，您阅读并认可该条款内容后，点击同意，该条款内容将保护您的个人权益且对您产生法律约束力。", color = Rgba(160, 160, 160, 255), bold = false },
        },
        onClose = function(confirmed)
            if confirmed then
                agreementChecked = true
                WriteAgreementSentinel()
            elseif engine then
                engine:Exit()
            elseif GetEngine then
                GetEngine():Exit()
            end
        end,
    })
end

------------ Drawing ------------

local function DrawLandscapeBackground()
    if activeLayout ~= LANDSCAPE_LAYOUT then return end
    if imgLandscapeBg < 0 or imgLandscapeBgW <= 0 or imgLandscapeBgH <= 0 then return end

    local scale = math.max(DESIGN_W / imgLandscapeBgW, DESIGN_H / imgLandscapeBgH)
    local drawW = imgLandscapeBgW * scale
    local drawH = imgLandscapeBgH * scale
    local x = (DESIGN_W - drawW) * 0.5
    local y = (DESIGN_H - drawH) * 0.5

    local paint = nvgImagePattern(vg, x, y, drawW, drawH, 0, imgLandscapeBg, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    local overlay = nvgLinearGradient(vg, 0, 0, 0, DESIGN_H, Rgba(0, 0, 0, 48), Rgba(0, 0, 0, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillPaint(vg, overlay)
    nvgFill(vg)
end

local function DrawAgeRating()
    if imgAgeRating < 0 then return end
    local drawW = AGE_W
    local drawH = imgAgeRatingH * (drawW / imgAgeRatingW)
    local paint = nvgImagePattern(vg, AGE_X, AGE_Y, drawW, drawH, 0, imgAgeRating, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, AGE_X, AGE_Y, drawW, drawH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local function DrawLoginButton()
    local alpha = press and 215 or (hover and 245 or 255)
    FillRoundedRect(BTN_X, BTN_Y, BTN_W, BTN_H, BTN_R, Color(TAP_BLUE, alpha))

    if imgTapLogo >= 0 then
        local maxH = BTN_H * TAP_LOGO_MAX_H
        local scale = maxH / imgTapLogoH
        local drawW = imgTapLogoW * scale
        local drawH = imgTapLogoH * scale

        local loginText = "登录"
        local loginSize = LOGIN_FONT_SIZE
        local loginW = TextWidth(loginText, loginSize, true)
        local gap = LOGIN_GAP
        local totalW = drawW + gap + loginW
        local startX = BTN_X + (BTN_W - totalW) * 0.5
        local cy = BTN_Y + BTN_H * 0.5

        local imgX = startX
        local imgY = cy - drawH * 0.5
        local paint = nvgImagePattern(vg, imgX, imgY, drawW, drawH, 0, imgTapLogo, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, imgX, imgY, drawW, drawH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)

        DrawText(startX + drawW + gap, cy, loginText, loginSize, Rgba(255, 255, 255, 255),
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, true)
    end
end

local function DrawCheckbox(x, y, checked)
    StrokeRoundedRect(x + 0.75, y + 0.75, CHECKBOX_SIZE - 1.5, CHECKBOX_SIZE - 1.5, CHECKBOX_R,
        Rgba(255, 255, 255, 76), 1.5)
    if not checked then return end

    FillRoundedRect(x, y, CHECKBOX_SIZE, CHECKBOX_SIZE, CHECKBOX_R, Color(TAP_BLUE, 255))

    local s = CHECKBOX_SIZE / 24
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 6 * s, y + 12.5 * s)
    nvgLineTo(vg, x + 10 * s, y + 16.5 * s)
    nvgLineTo(vg, x + 18 * s, y + 7.5 * s)
    nvgStrokeColor(vg, Rgba(255, 255, 255, 255))
    nvgStrokeWidth(vg, 2.8 * s)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)
end

local function DrawAgreement()
    local fontSize = AGREEMENT_FONT_SIZE
    local segments = {
        { text = "我已详细阅读并同意", color = Rgba(255, 255, 255, AGREEMENT_ALPHA), bold = false },
        { text = "《服务协议》", color = Color(TAP_BLUE, 255), bold = false, url = AGREEMENT_URL },
        { text = "和", color = Rgba(255, 255, 255, AGREEMENT_ALPHA), bold = false },
        { text = "《逸派玩游戏隐私保护指引》", color = Color(TAP_BLUE, 255), bold = false, url = PRIVACY_URL },
    }

    local textW = 0
    for _, seg in ipairs(segments) do
        textW = textW + TextWidth(seg.text, fontSize, seg.bold)
    end

    local rowW = CHECKBOX_SIZE + AGREEMENT_GAP + textW
    local x = (DESIGN_W - rowW) * 0.5
    local boxY = AGREEMENT_Y + 1
    agreementHotRect.x = x - 16
    agreementHotRect.y = boxY - 16
    agreementHotRect.w = CHECKBOX_SIZE + 32
    agreementHotRect.h = CHECKBOX_SIZE + 32
    DrawCheckbox(x, boxY, agreementChecked)

    linkRects = {}
    local curX = x + CHECKBOX_SIZE + AGREEMENT_GAP
    local textY = AGREEMENT_Y + CHECKBOX_SIZE * 0.5
    for _, seg in ipairs(segments) do
        local w = TextWidth(seg.text, fontSize, seg.bold)
        DrawText(curX, textY, seg.text, fontSize, seg.color,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, seg.bold)
        if seg.url then
            linkRects[#linkRects + 1] = {
                x = curX, y = AGREEMENT_Y - 4,
                w = w, h = CHECKBOX_SIZE + 8,
                url = seg.url
            }
        end
        curX = curX + w
    end
end

local function DrawBottomBanner()
    if BOTTOM_LINES then
        local lineH = BOTTOM_LINE_H or 28
        local y = DESIGN_H - (BOTTOM_MARGIN or 0) - #BOTTOM_LINES * lineH
        for i, line in ipairs(BOTTOM_LINES) do
            DrawText(DESIGN_W * 0.5, y + (i - 1) * lineH, line, BOTTOM_FONT_SIZE,
                Rgba(255, 255, 255, 179), NVG_ALIGN_CENTER + NVG_ALIGN_TOP, false)
        end
    else
        DrawText(DESIGN_W * 0.5, BOTTOM_Y + BOTTOM_H * 0.5, DISCLAIMER, BOTTOM_FONT_SIZE,
            Rgba(255, 255, 255, 179), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, false)
    end
end

local function DrawRichTextBox(x, y, width, lineHeight, size, segments)
    local curX = x
    local curY = y

    for _, seg in ipairs(segments or {}) do
        local text = seg.text or ""
        local chunk = ""
        local chunkW = 0
        for _, code in utf8.codes(text) do
            local ch = utf8.char(code)
            local chW = TextWidth(ch, size, seg.bold)
            if chunk ~= "" and curX + chunkW + chW > x + width then
                DrawText(curX, curY, chunk, size, seg.color, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, seg.bold)
                curX = x
                curY = curY + lineHeight
                chunk = ""
                chunkW = 0
            end
            chunk = chunk .. ch
            chunkW = chunkW + chW
        end

        if chunk ~= "" then
            DrawText(curX, curY, chunk, size, seg.color, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, seg.bold)
            curX = curX + chunkW
        end
    end
end

local function WrapTextLines(text, width, size, bold)
    local lines = {}
    local chunk = ""
    local chunkW = 0

    for _, code in utf8.codes(text or "") do
        local ch = utf8.char(code)
        local chW = TextWidth(ch, size, bold)
        if chunk ~= "" and chunkW + chW > width then
            lines[#lines + 1] = chunk
            chunk = ""
            chunkW = 0
        end
        chunk = chunk .. ch
        chunkW = chunkW + chW
    end

    if chunk ~= "" then
        lines[#lines + 1] = chunk
    end
    if #lines == 0 then
        lines[1] = ""
    end

    return lines
end

local function MeasureWrappedTextHeight(text, width, lineHeight, size, bold)
    return #WrapTextLines(text, width, size, bold) * lineHeight
end

local function DrawWrappedText(text, x, y, width, lineHeight, size, color, bold)
    local lines = WrapTextLines(text, width, size, bold)
    for i, line in ipairs(lines) do
        DrawText(x, y + (i - 1) * lineHeight, line, size, color, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, bold)
    end
    return #lines * lineHeight
end

local function DrawCloseIcon(x, y, size, alpha)
    local pad = size * 0.32
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + pad, y + pad)
    nvgLineTo(vg, x + size - pad, y + size - pad)
    nvgMoveTo(vg, x + size - pad, y + pad)
    nvgLineTo(vg, x + pad, y + size - pad)
    nvgStrokeColor(vg, Rgba(26, 26, 26, alpha or 255))
    nvgStrokeWidth(vg, 2)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
end

local function DrawRealNameDialog()
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, Rgba(0, 0, 0, 184))
    nvgFill(vg)

    local cardW = REAL_NAME_CARD_W
    local cardX = (DESIGN_W - cardW) * 0.5
    local cardY = REAL_NAME_CARD_Y or 0
    local padX = REAL_NAME_PAD_X
    local contentW = cardW - padX * 2
    local headerY = cardY + REAL_NAME_HEADER_OFFSET_Y
    local titleH = REAL_NAME_TITLE_H
    local closeSize = REAL_NAME_CLOSE_SIZE
    local bodyY = cardY + REAL_NAME_BODY_OFFSET_Y
    local bodyText =
        "根据国家新闻出版署《关于防止未成年人沉迷网络游戏的通知》《关于进一步严格管理 切实防止未成年人沉迷网络游戏的通知》，游戏用户须通过国家网络游戏防沉迷实名认证系统的身份认证。您提供的真实身份信息将受到严格保护，仅用于防沉迷及未成年人限制充值功能的实现，不会用于其他用途，请放心填写，身份信息提交后不可进行更改。"

    local lineH = REAL_NAME_LINE_H
    local bodyH = MeasureWrappedTextHeight(bodyText, contentW, lineH, REAL_NAME_BODY_SIZE, false)

    local fieldH = REAL_NAME_FIELD_H
    local fieldGap = REAL_NAME_FIELD_GAP
    local inputY = bodyY + bodyH + REAL_NAME_INPUT_TOP_GAP
    local submitH = REAL_NAME_SUBMIT_H
    local submitY = inputY + fieldH + fieldGap + fieldH + REAL_NAME_SUBMIT_TOP_GAP
    local cardH = submitY + submitH + REAL_NAME_BOTTOM_PAD - cardY
    if not REAL_NAME_CARD_Y then
        cardY = (DESIGN_H - cardH) * 0.5
        headerY = cardY + REAL_NAME_HEADER_OFFSET_Y
        bodyY = cardY + REAL_NAME_BODY_OFFSET_Y
        inputY = bodyY + bodyH + REAL_NAME_INPUT_TOP_GAP
        submitY = inputY + fieldH + fieldGap + fieldH + REAL_NAME_SUBMIT_TOP_GAP
    end

    FillRoundedRect(cardX, cardY + DIALOG_SHADOW_OFFSET, cardW, cardH, REAL_NAME_CORNER_R, Rgba(0, 0, 0, 60))
    FillRoundedRect(cardX, cardY, cardW, cardH, REAL_NAME_CORNER_R, Rgba(255, 255, 255, 255))

    DrawText(cardX + cardW * 0.5, headerY + titleH * 0.5, "游戏实名认证", REAL_NAME_TITLE_SIZE,
        Rgba(26, 26, 26, 255), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, true)

    cancelRect.x = cardX + cardW - padX - closeSize
    cancelRect.y = headerY
    cancelRect.w = closeSize
    cancelRect.h = closeSize
    DrawCloseIcon(cancelRect.x, cancelRect.y, closeSize, hoverCancel and 255 or 210)

    DrawWrappedText(bodyText, cardX + padX, bodyY, contentW, lineH, REAL_NAME_BODY_SIZE,
        Rgba(26, 26, 26, 255), false)

    local function DrawInputField(y, placeholder, value, focused, rect)
        rect.x = cardX + padX
        rect.y = y
        rect.w = contentW
        rect.h = fieldH

        local fieldR = math.max(12, REAL_NAME_CORNER_R * 0.5)
        FillRoundedRect(rect.x, rect.y, rect.w, rect.h, fieldR, Rgba(245, 245, 245, 255))
        local borderColor = focused and Color(TAP_BLUE, 255) or Rgba(204, 204, 204, 255)
        local borderW = focused and 2 or 1.5
        StrokeRoundedRect(rect.x + 0.75, rect.y + 0.75, rect.w - 1.5, rect.h - 1.5, fieldR,
            borderColor, borderW)

        local textSize = REAL_NAME_INPUT_TEXT_SIZE
        local cursorH = textSize * 1.2
        local textX = rect.x + math.max(28, REAL_NAME_PAD_X * 0.5)
        local textY = rect.y + rect.h * 0.5
        if value and value ~= "" then
            DrawText(textX, textY, value, textSize, Rgba(26, 26, 26, 255),
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, false)
            if focused then
                local w = TextWidth(value, textSize, false)
                if (cursorBlinkTime % 1.0) < 0.5 then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, textX + w + 2, textY - cursorH * 0.5)
                    nvgLineTo(vg, textX + w + 2, textY + cursorH * 0.5)
                    nvgStrokeColor(vg, Rgba(26, 26, 26, 220))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end
            end
        else
            DrawText(textX, textY, placeholder, textSize, Rgba(160, 160, 160, 255),
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, false)
            if focused and (cursorBlinkTime % 1.0) < 0.5 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, textX, textY - cursorH * 0.5)
                nvgLineTo(vg, textX, textY + cursorH * 0.5)
                nvgStrokeColor(vg, Rgba(26, 26, 26, 220))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            end
        end
    end

    DrawInputField(inputY, "真实姓名", realNameInput, focusedField == "name", nameFieldRect)
    DrawInputField(inputY + fieldH + fieldGap, "真实身份证号码", idCardInput,
        focusedField == "id", idFieldRect)

    if realNameError ~= "" then
        DrawText(cardX + padX, submitY - REAL_NAME_ERROR_SIZE - 8, realNameError, REAL_NAME_ERROR_SIZE,
            Rgba(220, 60, 60, 255), NVG_ALIGN_LEFT + NVG_ALIGN_TOP, false)
    end

    confirmRect.x = cardX + padX
    confirmRect.y = submitY
    confirmRect.w = contentW
    confirmRect.h = submitH
    local submitAlpha
    if realNameSubmitting then
        submitAlpha = 150
    else
        submitAlpha = pressConfirm and 210 or (hoverConfirm and 240 or 255)
    end
    FillRoundedRect(confirmRect.x, confirmRect.y, confirmRect.w, confirmRect.h,
        math.max(12, REAL_NAME_CORNER_R * 0.5), Color(TAP_BLUE, submitAlpha))
    local btnText = realNameSubmitting and "提交中..." or "提交"
    DrawText(confirmRect.x + confirmRect.w * 0.5, confirmRect.y + confirmRect.h * 0.5, btnText,
        REAL_NAME_BUTTON_TEXT_SIZE,
        Rgba(255, 255, 255, 255), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, true)
end

local function DrawCommonDialog()
    if not modal then return end
    if modal.kind == "real_name" then
        DrawRealNameDialog()
        return
    end

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(vg, Rgba(0, 0, 0, 153))
    nvgFill(vg)

    local cardW = DIALOG_CARD_W
    local pad = DIALOG_PAD
    local contentW = cardW - pad * 2
    local contentH = modal.contentH or DIALOG_CONTENT_MIN_H
    if modal.segments then
        contentH = math.max(contentH, DIALOG_SEGMENT_CONTENT_H)
    elseif modal.align ~= "center" and modal.message then
        contentH = math.max(contentH,
            MeasureWrappedTextHeight(modal.message, contentW, DIALOG_LINE_H, DIALOG_MESSAGE_SIZE, false))
    else
        contentH = math.max(contentH, DIALOG_CONTENT_MIN_H)
    end

    local cardH = DIALOG_TOP_PAD + DIALOG_TITLE_H + DIALOG_TITLE_GAP + contentH +
        DIALOG_ACTION_GAP + DIALOG_BTN_H + DIALOG_BOTTOM_PAD
    local cardX = (DESIGN_W - cardW) * 0.5
    local cardY = (DESIGN_H - cardH) * 0.5

    FillRoundedRect(cardX, cardY + DIALOG_SHADOW_OFFSET, cardW, cardH, DIALOG_CORNER_R, Rgba(0, 0, 0, 70))
    FillRoundedRect(cardX, cardY, cardW, cardH, DIALOG_CORNER_R, Rgba(42, 42, 42, 255))

    DrawText(cardX + pad, cardY + DIALOG_TOP_PAD, modal.title or "", DIALOG_TITLE_SIZE,
        Rgba(255, 255, 255, 255),
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, true)

    local contentX = cardX + pad
    local contentY = cardY + DIALOG_TOP_PAD + DIALOG_TITLE_H + DIALOG_TITLE_GAP
    if modal.segments then
        DrawRichTextBox(contentX, contentY, contentW, DIALOG_LINE_H, DIALOG_MESSAGE_SIZE, modal.segments)
    elseif modal.align == "center" then
        DrawText(cardX + cardW * 0.5, contentY + contentH * 0.5, modal.message or "", DIALOG_MESSAGE_SIZE,
            Rgba(160, 160, 160, 255), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, false)
    else
        DrawWrappedText(modal.message or "", contentX, contentY, contentW, DIALOG_LINE_H, DIALOG_MESSAGE_SIZE,
            Rgba(160, 160, 160, 255), false)
    end

    local actionsY = contentY + contentH + DIALOG_ACTION_GAP
    local btnW = DIALOG_BTN_W
    local btnH = DIALOG_BTN_H
    local btnR = DIALOG_BTN_R

    if modal.cancelText then
        local groupW = btnW * 2 + DIALOG_BTN_GAP
        local actionsX = cardX + (cardW - groupW) * 0.5
        cancelRect.x = actionsX
        cancelRect.y = actionsY
        cancelRect.w = btnW
        cancelRect.h = btnH
        local strokeA = pressCancel and 150 or (hoverCancel and 120 or 76)
        StrokeRoundedRect(cancelRect.x, cancelRect.y, btnW, btnH, btnR, Rgba(255, 255, 255, strokeA), 1)
        DrawText(cancelRect.x + btnW * 0.5, cancelRect.y + btnH * 0.5, modal.cancelText, DIALOG_MESSAGE_SIZE,
            Rgba(255, 255, 255, 255), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, false)

        confirmRect.x = actionsX + btnW + DIALOG_BTN_GAP
    else
        cancelRect.x = 0
        cancelRect.y = 0
        cancelRect.w = 0
        cancelRect.h = 0
        confirmRect.x = cardX + (cardW - btnW) * 0.5
    end

    confirmRect.y = actionsY
    confirmRect.w = btnW
    confirmRect.h = btnH
    local confirmAlpha = pressConfirm and 210 or (hoverConfirm and 240 or 255)
    FillRoundedRect(confirmRect.x, confirmRect.y, btnW, btnH, btnR, Color(TAP_BLUE, confirmAlpha))
    DrawText(confirmRect.x + btnW * 0.5, confirmRect.y + btnH * 0.5, modal.confirmText or "确认",
        DIALOG_MESSAGE_SIZE,
        Rgba(255, 255, 255, 255), NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, true)
end

------------ Render ------------

function __StartupUI_Render()
    if not alive or not vg then return end

    nvgBeginFrame(vg, logW, logH, dpr)

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, Color(BG, 255))
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, designX, designY)
    nvgScale(vg, designScale, designScale)

    DrawLandscapeBackground()
    DrawAgeRating()
    DrawLoginButton()
    DrawAgreement()
    DrawBottomBanner()
    DrawCommonDialog()

    nvgRestore(vg)
    nvgEndFrame(vg)
end

function __StartupUI_Update(eventType, eventData)
    if not alive then return end
    local dt = eventData["TimeStep"]:GetFloat()
    cursorBlinkTime = (cursorBlinkTime + dt) % 2.0

    local pos = input:GetMousePosition()
    local sx = pos.x / dpr
    local sy = pos.y / dpr
    if modal then
        local dx, dy = ScreenToDesign(sx, sy)
        hoverConfirm = PointInRect(dx, dy, confirmRect)
        hoverCancel = (modal.cancelText or modal.kind == "real_name") and PointInRect(dx, dy, cancelRect) or false
        hover = false
        return
    end

    hover = PointInRect(sx, sy, btnRect)
end

function __StartupUI_ScreenMode()
    if not alive then return end
    RecalcLayout()
end

function __StartupUI_MouseDown(eventType, eventData)
    if not alive then return end
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr
    if modal then
        local dx, dy = ScreenToDesign(mx, my)
        pressConfirm = PointInRect(dx, dy, confirmRect)
        pressCancel = (modal.cancelText or modal.kind == "real_name") and PointInRect(dx, dy, cancelRect) or false
        if modal.kind == "real_name" then
            if PointInRect(dx, dy, nameFieldRect) then
                focusedField = "name"
                cursorBlinkTime = 0
            elseif PointInRect(dx, dy, idFieldRect) then
                focusedField = "id"
                cursorBlinkTime = 0
            elseif not pressConfirm and not pressCancel then
                focusedField = nil
            end
        end
        return
    end

    press = PointInRect(mx, my, btnRect)
end

function __StartupUI_MouseUp(eventType, eventData)
    if not alive then return end
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr
    if modal then
        local dx, dy = ScreenToDesign(mx, my)
        if pressConfirm and PointInRect(dx, dy, confirmRect) then
            pressConfirm = false
            if modal.kind == "real_name" then
                if not realNameSubmitting and modal.onSubmit then
                    modal.onSubmit(realNameInput, idCardInput)
                end
            else
                CloseDialog(true)
            end
        elseif pressCancel and PointInRect(dx, dy, cancelRect) and (modal.cancelText or modal.kind == "real_name") then
            CloseDialog(false)
        else
            pressConfirm = false
            pressCancel = false
        end
        return
    end

    if press then
        if PointInRect(mx, my, btnRect) then
            if not agreementChecked then
                ShowReadAgreementFirstDialog()
            elseif onClickCallback then
                local cb = onClickCallback
                onClickCallback = nil
                cb()
            end
            press = false
            return
        end
        press = false
    end

    local dx, dy = ScreenToDesign(mx, my)
    if CheckLinkClick(dx, dy) then return end
    if PointInRect(dx, dy, agreementHotRect) then
        agreementChecked = not agreementChecked
    end
end

function __StartupUI_TextInput(eventType, eventData)
    if not alive or not modal or modal.kind ~= "real_name" then return end
    if not focusedField or realNameSubmitting then return end
    local text = eventData["Text"]:GetString()
    if not text or text == "" then return end
    -- 过滤空白，保持旧项目实名输入行为。
    text = string.gsub(text, "%s+", "")
    if focusedField == "name" then
        if #realNameInput < 64 then
            realNameInput = realNameInput .. text
            realNameError = ""
        end
    elseif focusedField == "id" then
        text = string.upper(text)
        if #idCardInput < 32 then
            idCardInput = idCardInput .. text
            realNameError = ""
        end
    end
end

local function PopUtf8Char(s)
    if s == "" then return s end
    -- 找到最后一个 UTF-8 字符的起始字节
    local i = #s
    while i > 1 do
        local b = string.byte(s, i)
        if b < 0x80 or b >= 0xC0 then break end
        i = i - 1
    end
    return s:sub(1, i - 1)
end

function __StartupUI_KeyDown(eventType, eventData)
    if not alive or not modal or modal.kind ~= "real_name" then return end
    if not focusedField or realNameSubmitting then return end
    local key = eventData["Key"]:GetInt()
    if key == KEY_BACKSPACE then
        if focusedField == "name" then
            realNameInput = PopUtf8Char(realNameInput)
        elseif focusedField == "id" then
            idCardInput = PopUtf8Char(idCardInput)
        end
        realNameError = ""
    elseif key == KEY_TAB then
        if focusedField == "name" then
            focusedField = "id"
        else
            focusedField = "name"
        end
        cursorBlinkTime = 0
    elseif (key == KEY_RETURN or key == KEY_RETURN2 or key == KEY_KP_ENTER) and modal.onSubmit and not realNameSubmitting then
        modal.onSubmit(realNameInput, idCardInput)
    end
end

function __StartupUI_TouchEnd(eventType, eventData)
    if not alive then return end
    local tx = eventData["X"]:GetInt() / dpr
    local ty = eventData["Y"]:GetInt() / dpr
    if modal then
        local dx, dy = ScreenToDesign(tx, ty)
        if PointInRect(dx, dy, confirmRect) then
            if modal.kind == "real_name" then
                if not realNameSubmitting and modal.onSubmit then
                    modal.onSubmit(realNameInput, idCardInput)
                end
            else
                CloseDialog(true)
            end
        elseif PointInRect(dx, dy, cancelRect) and (modal.cancelText or modal.kind == "real_name") then
            CloseDialog(false)
        elseif modal.kind == "real_name" then
            if PointInRect(dx, dy, nameFieldRect) then
                focusedField = "name"
                cursorBlinkTime = 0
            elseif PointInRect(dx, dy, idFieldRect) then
                focusedField = "id"
                cursorBlinkTime = 0
            end
        end
        return
    end

    if PointInRect(tx, ty, btnRect) then
        if not agreementChecked then
            ShowReadAgreementFirstDialog()
            return
        end
        local cb = onClickCallback
        if cb then
            onClickCallback = nil
            cb()
        end
        return
    end

    local dx, dy = ScreenToDesign(tx, ty)
    if CheckLinkClick(dx, dy) then return end
    if PointInRect(dx, dy, agreementHotRect) then
        agreementChecked = not agreementChecked
    end
end

------------ Public API ------------

--- 显示登录页，用户点击登录按钮后调 callback。
function M.ShowLoginPage(callback)
    if alive then return end

    vg = nvgCreate(1)
    if not vg then
        print("[StartupUI] Failed to create NVG context")
        if callback then callback() end
        return
    end

    nvgSetRenderOrder(vg, 1000000)

    fontRegular = nvgCreateFont(vg, "startup-sans", "Fonts/MiSans-Regular.ttf")
    fontBold = nvgCreateFont(vg, "startup-sans-bold", "Fonts/MiSans-Bold.ttf")
    if not fontRegular or fontRegular < 0 then
        fontRegular = nvgCreateFont(vg, "startup-sans", "Fonts/Anonymous Pro.ttf")
    end
    if not fontBold or fontBold < 0 then
        fontBold = fontRegular
    end

    -- `or 1` 是 Lua fallback：NVG_IMAGE_GENERATE_MIPMAPS 未定义时用字面量 1（同一数值）
    imgTapLogo = nvgCreateImage(vg, "assets/taplogo.png", NVG_IMAGE_GENERATE_MIPMAPS or 1)
    if imgTapLogo and imgTapLogo >= 0 then
        imgTapLogoW, imgTapLogoH = nvgImageSize(vg, imgTapLogo)
    end
    imgAgeRating = nvgCreateImage(vg, "assets/12+.png", NVG_IMAGE_GENERATE_MIPMAPS or 1)
    if imgAgeRating and imgAgeRating >= 0 then
        imgAgeRatingW, imgAgeRatingH = nvgImageSize(vg, imgAgeRating)
    end
    imgLandscapeBg = nvgCreateImage(vg, LANDSCAPE_BG_IMAGE, NVG_IMAGE_GENERATE_MIPMAPS or 1)
    if imgLandscapeBg and imgLandscapeBg >= 0 then
        imgLandscapeBgW, imgLandscapeBgH = nvgImageSize(vg, imgLandscapeBg)
    end

    onClickCallback = callback
    alive = true
    modal = nil
    -- 已接受过协议的用户无需再次勾选
    agreementChecked = HasAgreementSentinel()

    RecalcLayout()

    if not agreementChecked then
        ShowAgreementDialog()
    end

    SubscribeToEvent(vg, "NanoVGRender", "__StartupUI_Render")
    SubscribeToEvent("Update", "__StartupUI_Update")
    SubscribeToEvent("ScreenMode", "__StartupUI_ScreenMode")
    SubscribeToEvent("MouseButtonDown", "__StartupUI_MouseDown")
    SubscribeToEvent("MouseButtonUp", "__StartupUI_MouseUp")
    SubscribeToEvent("TouchEnd", "__StartupUI_TouchEnd")
    SubscribeToEvent("TextInput", "__StartupUI_TextInput")
    SubscribeToEvent("KeyDown", "__StartupUI_KeyDown")
end

--- 显示实名认证对话框。
--- @param onSubmit fun(name: string, idcard: string) 用户点击提交时回调（外部负责验证 + 调用 SetRealNameSubmitting / Close 等）
--- @param onCancel fun() 用户点击关闭时回调
function M.ShowRealNameDialog(onSubmit, onCancel)
    if not alive then
        if onCancel then onCancel() end
        return
    end

    realNameInput = ""
    idCardInput = ""
    focusedField = "name"
    cursorBlinkTime = 0
    realNameSubmitting = false
    realNameError = ""
    SetRealNameInputVisible(true)

    ShowCommonDialog({
        kind = "real_name",
        confirmText = "提交",
        onSubmit = onSubmit,
        onClose = function()
            focusedField = nil
            realNameSubmitting = false
            if onCancel then onCancel() end
        end,
    })
end

--- 设置实名认证提交中状态（禁用按钮，显示"提交中..."）
function M.SetRealNameSubmitting(submitting)
    realNameSubmitting = submitting and true or false
end

--- 设置实名认证错误提示
-- 注意：err 为空字符串时只清除错误文本，不重置 realNameSubmitting。
-- 这是故意的：提交中途调 SetRealNameError("") 清旧错误时，按钮仍应保持禁用状态。
-- 若需同时解锁按钮，请先调 SetRealNameSubmitting(false)。
function M.SetRealNameError(err)
    realNameError = err or ""
    if realNameError ~= "" then
        realNameSubmitting = false
    end
end

--- 关闭实名认证对话框
function M.CloseRealNameDialog()
    if modal and modal.kind == "real_name" then
        modal = nil
        focusedField = nil
        realNameSubmitting = false
        realNameError = ""
        SetRealNameInputVisible(false)
    end
end

--- 显示防沉迷提示对话框
--- @param config { mode: "enter"|"exit", remainMin: integer, onEnter: fun()|nil, onExit: fun()|nil }
function M.ShowAntiAddictTips(config)
    if not alive then return end
    config = config or {}
    local mode = config.mode or "exit"
    local message
    if mode == "enter" then
        message = string.format(
            "你当前为未成年账号，已被纳入防沉迷系统。根据国家新闻出版署《关于防止未成年人沉迷网络游戏的通知》《关于进一步严格管理 切实防止未成年人沉迷网络游戏的通知》，网络游戏仅可在周五、周六、周日和法定节假日每日 20 时至 21 时向未成年人提供 60 分钟网络游戏服务。今日游戏时间还剩余 %d 分钟。",
            config.remainMin or 0)
    else
        message = "您当前为未成年账号，已被纳入防沉迷系统。根据国家新闻出版署《关于防止未成年人沉迷网络游戏的通知》《关于进一步严格管理 切实防止未成年人沉迷网络游戏的通知》，周五、周六、周日及法定节假日 20 点 - 21 点之外为健康保护时段。当前时间段无法游玩，请合理安排时间。"
    end

    ShowCommonDialog({
        kind = "anti_addict_tips",
        title = "游戏健康提醒",
        message = message,
        contentH = 260,
        align = "left",
        confirmText = (mode == "enter") and "进入游戏" or "退出游戏",
        onClose = function(confirmed)
            if mode == "enter" then
                if config.onEnter then config.onEnter() end
            else
                if config.onExit then config.onExit() end
            end
        end,
    })
end

--- Destroy NVG resources and unsubscribe events.
function M.Destroy()
    alive = false
    onClickCallback = nil
    modal = nil
    realNameInput = ""
    idCardInput = ""
    focusedField = nil
    realNameSubmitting = false
    realNameError = ""
    SetRealNameInputVisible(false)
    -- NanoVGRender 必须在 nvgDelete 之前解绑（按 sender 绑定，只移除 vg 上的订阅，安全），
    -- 否则 vg 释放后回调仍可能访问已销毁对象。
    if vg then
        UnsubscribeFromEvent(vg, "NanoVGRender")
        nvgDelete(vg)
        vg = nil
    end
    -- 注意：不解绑全局事件（Update/ScreenMode/输入事件）。Urho3D 的
    -- UnsubscribeFromEvent(eventName) 会移除当前 LuaScript 上该事件**所有**订阅，
    -- 而 anti_addict.WaitRejectTime 也注册了 Update（21:00 强制踢出定时器），
    -- 同 Startup VM 共享 LuaScript 实例，全局解绑会误杀防沉迷定时器违反合规。
    -- 8 个 handler 都已有 `if not alive then return end` 守卫，VM 销毁时统一清理。
    fontRegular = -1
    fontBold = -1
    imgTapLogo = -1
    imgAgeRating = -1
    imgLandscapeBg = -1
end

return M
