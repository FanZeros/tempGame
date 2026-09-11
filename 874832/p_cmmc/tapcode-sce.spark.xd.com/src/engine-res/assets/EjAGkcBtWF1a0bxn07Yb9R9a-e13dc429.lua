-- ============================================================================
-- UrhoX UI Gallery
-- Elegant showcase of all 42 UI widgets with interactive demos
-- Designed for AI style-skinning: all colors via Theme API, no hardcoding
-- ============================================================================

local UI = require("urhox-libs/UI")

-- Sweetopia theme from ai-dev-kit/.claude/skills/ui-sweetopia.
local CANDY_BUTTON_GLOW = {
    alpha = { default = 255, hover = 255 },
    blur = { default = 0, hover = 0 },
    offset = { default = { 0, 5 }, hover = { 0, 5 } },
    pressed = { color = { 0, 0, 0, 255 }, blur = 0, offset = { 0, 5 } },
}

local SOFT_SHADOW = {
    { x = 4, y = 4, blur = 3, color = { 0, 0, 0, 26 } },
}

local MENU_SHADOW = {
    { x = 3, y = 3, blur = 3, color = { 0, 0, 0, 26 } },
}

local LIST_SHADOW = {
    { x = 3, y = 3, blur = 4, color = { 0, 0, 0, 51 } },
}

local PANEL_SHADOW = {
    { x = 4, y = 4, blur = 4, color = { 0, 0, 0, 51 } },
}

local TIMELINE_DOT_SHADOW = {
    { x = 1, y = 1, blur = 2, color = { 0, 0, 0, 38 } },
}

local SweetopiaTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
    colors = {
        primary = { 255, 160, 33, 255 },
        primaryHover = { 255, 177, 74, 255 },
        primaryPressed = { 245, 152, 27, 255 },
        primaryShadow = { 220, 112, 71, 255 },
        secondary = { 52, 197, 221, 255 },
        secondaryHover = { 88, 218, 238, 255 },
        secondaryPressed = { 42, 187, 208, 255 },
        secondaryShadow = { 63, 148, 198, 255 },

        background = { 255, 249, 199, 255 },
        backgroundAlt = { 234, 245, 247, 255 },
        surface = { 255, 255, 255, 255 },
        surfaceTint = { 255, 247, 255, 255 },
        surfaceCream = { 255, 249, 224, 255 },
        surfaceHover = { 231, 247, 255, 255 },
        surfaceAlt = { 255, 249, 224, 255 },
        disabled = { 225, 225, 225, 255 },

        text = { 91, 91, 91, 255 },
        textSecondary = { 173, 173, 173, 255 },
        textDisabled = { 191, 191, 191, 255 },

        border = { 52, 197, 221, 255 },
        borderFocus = { 255, 159, 33, 255 },
        rewardFocus = { 255, 221, 78, 255 },

        success = { 142, 217, 72, 255 },
        successHover = { 170, 239, 106, 255 },
        successPressed = { 134, 208, 64, 255 },
        successShadow = { 76, 173, 150, 255 },
        warning = { 255, 200, 102, 255 },
        warningHover = { 255, 215, 143, 255 },
        error = { 255, 120, 99, 255 },
        errorHover = { 255, 167, 154, 255 },
        errorPressed = { 219, 70, 70, 255 },
        errorShadow = { 219, 70, 70, 255 },
        info = { 98, 214, 255, 255 },
        avatarCyan = { 99, 214, 255, 255 },
        avatarCyanBorder = { 164, 228, 255, 255 },
        avatarPink = { 253, 148, 199, 255 },
        avatarPinkBorder = { 255, 211, 232, 255 },
        avatarYellow = { 255, 192, 109, 255 },
        avatarYellowBorder = { 255, 212, 71, 255 },

        disabled = { 225, 225, 225, 255 },
        disabledText = { 191, 191, 191, 255 },
        overlay = { 58, 58, 106, 64 },
        highlight = { 255, 255, 255, 184 },
        hover = { 231, 247, 255, 180 },
        transparent = { 0, 0, 0, 0 },
    },

    spacing = {
        xs = 4,
        sm = 8,
        md = 12,
        lg = 16,
        xl = 24,
        xxl = 32,
    },

    radius = {
        none = 0,
        sm = 5,
        md = 10,
        lg = 15,
        xl = 20,
        full = 9999,
    },

    typography = {
        fontFamily = "sans",
        h1 = { fontSize = 21 },
        h2 = { fontSize = 16.5 },
        h3 = { fontSize = 13.5 },
        body = { fontSize = 10.5 },
        bodySmall = { fontSize = 9 },
        caption = { fontSize = 7.5 },
    },

    componentDefaults = {
        borderRadius = 12,
        fontFamily = "sans",
    },

    components = {
        Button = {
            height = 44,
            paddingHorizontal = 18,
            fontSize = 16.5,
            fontWeight = "700",
            textColor = { 255, 255, 255, 255 },
            borderRadius = { 5, 15, 5, 15 },
            glowShadow = CANDY_BUTTON_GLOW,
        },

        TextField = {
            height = 40,
            paddingHorizontal = 12,
            fontSize = 12,
            fontWeight = "normal",
            borderRadius = { 0, 10, 0, 10 },
            borderWidth = 0,
            focusedBorderColor = { 255, 159, 33, 255 },
            focusedBorderWidth = 2,
            filledBorderColor = { 255, 195, 100, 255 },
            filledBorderWidth = 2,
            errorBorderColor = { 255, 123, 116, 255 },
            errorBorderWidth = 2,
            disabledBorderColor = { 191, 191, 191, 255 },
            disabledBorderWidth = 2,
        },

        Checkbox = {
            size = 22,
            borderRadius = 12,
            borderWidth = 2,
            uncheckedBorderColor = { 255, 159, 33, 255 },
            uncheckedHoverBorderColor = { 255, 159, 33, 255 },
            checkedBgColor = { 255, 160, 33, 255 },
            checkedBorderColor = { 255, 229, 182, 255 },
            checkedHoverBorderColor = { 208, 118, 0, 255 },
            disabledBorderColor = { 191, 191, 191, 255 },
            checkmarkColor = { 255, 255, 255, 255 },
            hoverBorderColor = { 255, 160, 33, 255 },
        },

        Toggle = {
            trackWidth = 48,
            trackHeight = 26,
            thumbSize = 18,
            borderRadius = 12,
            borderWidth = 3,
            trackBorderColor = { 52, 197, 221, 255 },
            trackHoverBgColor = { 223, 242, 245, 255 },
            trackHoverBorderColor = { 52, 197, 221, 255 },
            trackCheckedBgColor = { 255, 255, 255, 255 },
            trackCheckedHoverBgColor = { 255, 229, 181, 255 },
            trackCheckedBorderColor = { 255, 159, 33, 255 },
            trackCheckedHoverBorderColor = { 255, 159, 33, 255 },
            trackDisabledBorderColor = { 191, 191, 191, 255 },
            thumbColor = { 52, 197, 221, 255 },
            thumbHoverColor = { 52, 197, 221, 255 },
            thumbCheckedColor = { 255, 159, 33, 255 },
        },

        Slider = {
            trackHeight = 4,
            thumbSize = 18,
            borderRadius = 12,
            trackBgColor = { 52, 197, 221, 255 },
            trackFillColor = { 255, 160, 33, 255 },
            thumbColor = { 255, 160, 33, 255 },
            thumbBorderWidth = 2,
            thumbBorderColor = { 255, 255, 255, 255 },
        },

        FileUpload = {
            borderWidth = 4,
            borderColor = { 52, 197, 221, 255 },
            borderRadius = { 5, 15, 5, 15 },
            dropzoneBgColor = { 255, 255, 255, 255 },
            iconColor = { 52, 197, 221, 255 },
            fontWeight = "700",
        },

        Card = {
            borderRadius = { 5, 30, 5, 30 },
            backgroundColor = { 255, 255, 255, 255 },
            elevatedBoxShadow = SOFT_SHADOW,
            outlinedBorderWidth = 4,
            outlinedBorderColor = { 51, 197, 221, 255 },
            fontWeight = "700",
        },

        Badge = {
            borderWidth = 2,
            borderColor = { 255, 255, 255, 255 },
            borderRadius = 12,
            fontSize = 9.75,
            fontWeight = "700",
        },

        Alert = {
            borderWidth = 2,
            standardBgColor = { 255, 255, 255, 255 },
            borderRadius = { 5, 15, 5, 15 },
            fontWeight = "700",
        },

        Avatar = {
            showBorder = true,
        },

        Chip = {
            borderWidth = 2,
            borderColor = { 255, 255, 255, 255 },
            borderRadius = 12,
            fontWeight = "700",
        },

        ProgressBar = {
            height = 16,
            borderWidth = 2,
            borderRadius = 12,
        },

        Skeleton = {
            borderWidth = 4,
            borderColor = { 52, 197, 221, 255 },
            borderRadius = { 5, 15, 5, 15 },
        },

        Tabs = {
            borderWidth = 0,
            borderColor = { 54, 197, 221, 255 },
            lineBorderWidth = 2,
            lineBorderColor = { 54, 197, 221, 255 },
            indicatorThickness = 2,
            activeBorderColor = { 242, 156, 59, 255 },
            activeTextColor = { 242, 156, 59, 255 },
            inactiveTextColor = { 173, 173, 173, 255 },
            variantActiveBgColor = {
                pills = { 255, 159, 33, 255 },
                enclosed = { 255, 159, 33, 255 },
            },
            variantInactiveBgColor = {
                pills = { 54, 197, 221, 255 },
            },
            variantContainerBgColor = {
                enclosed = { 54, 197, 221, 255 },
            },
            variantActiveTextColor = {
                line = { 242, 156, 59, 255 },
                pills = { 255, 255, 255, 255 },
                enclosed = { 255, 255, 255, 255 },
            },
            variantInactiveTextColor = {
                line = { 54, 197, 221, 255 },
                pills = { 255, 255, 255, 255 },
                enclosed = { 255, 255, 255, 255 },
            },
            variantActiveBorderColor = {
                line = { 242, 156, 59, 255 },
                pills = { 255, 159, 33, 255 },
                enclosed = { 255, 255, 255, 255 },
            },
            variantBorderRadius = {
                pills = { 5, 15, 5, 15 },
                enclosed = { 5, 15, 5, 15 },
            },
            variantContainerBorderRadius = {
                enclosed = { 5, 15, 5, 15 },
            },
            variantTabGap = {
                line = 0,
                pills = 8,
                enclosed = 0,
            },
            activeFontWeight = "700",
            tabGap = 0,
        },

        Menu = {
            variant = "outlined",
            borderWidth = 4,
            borderRadius = { 5, 15, 5, 15 },
            borderColor = { 52, 197, 221, 255 },
            backgroundColor = { 255, 255, 255, 255 },
            boxShadow = MENU_SHADOW,
            itemHoverBgColor = { 215, 241, 255, 255 },
            itemHoverTextColor = { 51, 197, 221, 255 },
            itemHoverFontWeight = "600",
            itemHoverInset = 0,
            itemHoverRadius = 0,
            itemVerticalInset = 0,
            padding = 6,
        },

        Breadcrumb = {
            size = "lg",
            fontWeight = "700",
            linkColor = { 52, 197, 221, 255 },
            hoverColor = { 52, 197, 221, 255 },
            currentColor = { 118, 118, 118, 255 },
            separatorColor = { 112, 112, 112, 255 },
        },

        Stepper = {
            borderWidth = 2,
            borderRadius = 12,
            completedBgColor = { 52, 197, 221, 255 },
            completedBorderColor = { 255, 255, 255, 255 },
            completedTextColor = { 255, 255, 255, 255 },
            completedBoxShadow = {
                { x = 1, y = 1, blur = 2, color = { 0, 0, 0, 38 } },
            },
            activeBgColor = { 52, 197, 221, 255 },
            activeBorderColor = { 255, 255, 255, 255 },
            activeTextColor = { 255, 255, 255, 255 },
            activeBoxShadow = {
                { x = 1, y = 1, blur = 2, color = { 0, 0, 0, 38 } },
            },
            pendingBgColor = { 255, 255, 255, 255 },
            pendingBorderColor = { 255, 255, 255, 255 },
            pendingTextColor = { 44, 113, 181, 255 },
            pendingBoxShadow = {
                { x = 1, y = 1, blur = 2, color = { 0, 0, 0, 38 } },
            },
            errorBgColor = { 255, 106, 114, 255 },
            errorBorderColor = { 255, 106, 114, 255 },
            errorTextColor = { 255, 255, 255, 255 },
            errorBoxShadow = {
                { x = 1, y = 1, blur = 2, color = { 0, 0, 0, 38 } },
            },
            connectorColor = { 99, 214, 255, 255 },
            completedConnectorColor = { 99, 214, 255, 255 },
            pendingConnectorColor = { 99, 214, 255, 255 },
            connectorWidth = 2,
        },

        Pagination = {
            buttonBorderWidth = 2,
            hoverBorderColor = { 52, 197, 221, 255 },
            activeBgColor = { 52, 197, 221, 255 },
            activeBorderColor = { 52, 197, 221, 255 },
            activeTextColor = { 255, 255, 255, 255 },
            activeFontWeight = "700",
        },

        Carousel = {
            backgroundColor = { 255, 255, 255, 255 },
            borderWidth = 4,
            borderAlign = "inside",
            borderColor = { 51, 197, 221, 255 },
            borderRadius = { 5, 15, 5, 15 },
            arrowSize = 44,
            indicatorGap = 12,
            arrowBgColor = { 170, 225, 255, 255 },
            arrowHoverBgColor = { 129, 222, 255, 255 },
            dotColor = { 133, 207, 246, 255 },
            activeDotColor = { 170, 225, 255, 255 },
        },

        Modal = {
            borderWidth = 4,
            borderRadius = { 5, 20, 5, 20 },
            borderColor = { 255, 255, 255, 255 },
            boxShadow = SOFT_SHADOW,
            headerBorderRadius = { 5, 20, 0, 0 },
            headerBgColor = { 52, 197, 221, 255 },
            headerBorderWidth = 0,
            headerStripeColor = { 129, 223, 255, 255 },
            headerStripeHeight = 9,
            titleTextColor = { 255, 255, 255, 255 },
            footerBorderWidth = 0,
            contentPadding = 16,
            footerPadding = { 12, 16 },
            titleFontWeight = "700",
        },

        Drawer = {
            borderWidth = 4,
            borderRadius = { 5, 15, 5, 15 },
            borderColor = { 255, 255, 255, 255 },
            boxShadow = SOFT_SHADOW,
            contentPadding = 12,
            headerPadding = { 12, 16 },
        },

        Toast = {
            borderWidth = 0,
            borderRadius = { 5, 15, 5, 15 },
            boxShadow = MENU_SHADOW,
            toastBgColor = { 255, 255, 255, 255 },
            accentBarWidth = 4,
            accentBarHeight = 32,
            accentBarInset = 12,
            showIcon = false,
            fontWeight = "700",
        },

        Tooltip = {
            borderWidth = 4,
            borderColor = { 255, 200, 102, 255 },
            borderRadius = { 5, 12, 0, 12 },
            tooltipBgColor = { 255, 255, 255, 240 },
            textColor = { 238, 157, 18, 255 },
            fontSize = 12,
            fontWeight = "700",
        },

        Popover = {
            borderWidth = 4,
            borderRadius = { 5, 12, 5, 12 },
            borderColor = { 52, 197, 221, 255 },
            boxShadow = MENU_SHADOW,
        },

        Dropdown = {
            borderWidth = 3,
            borderRadius = 12,
            boxShadow = false,
            borderColor = { 51, 197, 221, 0 },
            hoverBorderColor = { 51, 197, 221, 255 },
            openBorderColor = { 51, 197, 221, 255 },
            hoverBorderWidth = 3,
            openBorderWidth = 3,
            disabledBorderWidth = 3,
            popupBorderColor = { 177, 226, 245, 255 },
            arrowColor = { 109, 199, 252, 255 },
            itemHoverBgColor = { 219, 240, 255, 255 },
            itemHoverTextColor = { 54, 197, 221, 255 },
            itemSelectedColor = { 219, 240, 255, 255 },
            itemSelectedTextColor = { 54, 197, 221, 255 },
            selectedFontWeight = "600",
            itemHeight = 36,
            itemVerticalInset = 0,
            itemHoverInset = 0,
            itemHoverRadius = 0,
        },

        Table = {
            variant = "striped",
            borderWidth = 5,
            borderColor = { 255, 255, 255, 255 },
            backgroundColor = { 255, 255, 255, 255 },
            borderRadius = { 5, 12, 5, 12 },
            headerBorderRadius = { 5, 12, 0, 0 },
            lastRowBorderRadius = { 0, 0, 5, 15 },
            boxShadow = { { x = 4, y = 4, blur = 4, color = { 0, 0, 0, 26 } } },
            headerBgColor = { 52, 197, 221, 255 },
            headerBorderWidth = 2,
            headerFontWeight = "700",
            rowBorderWidth = 0,
            rowOddBgColor = { 255, 249, 224, 255 },
            rowEvenBgColor = { 255, 254, 253, 255 },
            rowHoverBgColor = { 231, 247, 255, 255 },
            fontWeight = "700",
        },

        List = {
            borderWidth = 4,
            borderColor = { 255, 255, 255, 255 },
            backgroundColor = { 255, 255, 255, 255 },
            borderRadius = { 5, 15, 5, 15 },
            boxShadow = LIST_SHADOW,
            itemHoverBgColor = { 231, 247, 255, 255 },
            itemSelectedBgColor = { 255, 194, 33, 255 },
            itemHoverTextColor = { 51, 197, 221, 255 },
            itemSelectedTextColor = { 255, 255, 255, 255 },
            fontWeight = "700",
        },

        Accordion = {
            variant = "default",
            borderWidth = 4,
            borderColor = { 255, 255, 255, 255 },
            borderRadius = { 5, 15, 5, 15 },
            boxShadow = PANEL_SHADOW,
            bgColor = { 255, 249, 233, 255 },
            headerExpandedBgColor = { 255, 194, 33, 255 },
            expandedHeaderBorderRadius = { 5, 15, 0, 0 },
            lastHeaderBorderRadius = { 0, 0, 5, 15 },
            expandedTextColor = { 255, 255, 255, 255 },
            collapsedTextColor = { 213, 182, 105, 255 },
            indicatorExpandedColor = { 255, 160, 33, 255 },
            contentBgColor = { 255, 255, 255, 255 },
            contentTextColor = { 91, 91, 91, 255 },
            contentFontSize = 11.25,
            contentFontWeight = "700",
            headerFontWeight = "700",
        },

        Rating = {
            activeColor = { 255, 200, 102, 255 },
            inactiveColor = { 191, 191, 191, 255 },
            hoverColor = { 255, 215, 143, 255 },
        },

        Calendar = {
            borderWidth = 4,
            borderColor = { 51, 197, 221, 255 },
            backgroundColor = { 255, 255, 255, 255 },
            borderRadius = 24,
            boxShadow = SOFT_SHADOW,
            primaryColor = { 52, 197, 221, 255 },
            selectedBgColor = false,
            selectedBorderColor = { 51, 197, 221, 255 },
            selectedBorderWidth = 4,
            selectedTextColor = { 51, 197, 221, 255 },
            navBtnBgColor = { 255, 194, 33, 255 },
            navBtnRadius = 10,
            weekdayFontWeight = "700",
            monthFontWeight = "700",
        },

        DatePicker = {
            borderWidth = 4,
            borderRadius = 24,
            primaryColor = { 52, 197, 221, 255 },
            selectedBgColor = false,
            selectedBorderColor = { 51, 197, 221, 255 },
            selectedBorderWidth = 4,
            selectedTextColor = { 51, 197, 221, 255 },
            navBtnBgColor = { 255, 194, 33, 255 },
            navBtnRadius = 10,
            popupBgColor = { 255, 255, 255, 255 },
            popupBorderRadius = 20,
            fieldBorderColor = { 52, 197, 221, 0 },
            fieldBorderRadius = 14,
            todayBtnBgColor = { 130, 226, 241, 255 },
            todayBtnTextColor = { 255, 255, 255, 255 },
        },

        TimePicker = {
            borderWidth = 4,
            borderRadius = 10,
            primaryColor = { 52, 197, 221, 255 },
            selectedBgColor = { 51, 197, 221, 255 },
            selectedBorderWidth = 0,
            selectedTextColor = { 255, 255, 255, 255 },
            popupBgColor = { 255, 255, 255, 255 },
            popupBorderRadius = 20,
            fieldBorderColor = { 52, 197, 221, 0 },
            fieldBorderRadius = 14,
            selectedItemBorderRadius = 10,
        },

        ColorPicker = {
            borderWidth = 4,
            borderRadius = 24,
            primaryColor = { 52, 197, 221, 255 },
            fieldBorderColor = { 52, 197, 221, 0 },
            fieldBorderRadius = 14,
            fieldSwatchRadius = 8,
            popupBorderRadius = 20,
            sliderRadius = 9,
            presetRadius = 8,
        },

        Timeline = {
            borderWidth = 4,
            borderColor = { 51, 197, 221, 255 },
            backgroundColor = { 255, 255, 255, 255 },
            borderRadius = { 5, 15, 5, 15 },
            boxShadow = false,
            padding = 16,
            dotColor = { 51, 197, 221, 255 },
            lineColor = { 143, 213, 215, 255 },
            dotSize = 16,
            lineWidth = 2,
            fontSize = 16,
            titleSize = 15,
            titleFontWeight = "700",
            titleColor = { 51, 197, 221, 255 },
            descriptionColor = { 169, 169, 169, 255 },
            timeColor = { 169, 169, 169, 255 },
            hoverTitleColor = { 255, 159, 33, 255 },
            dotBorderColor = { 255, 255, 255, 255 },
            dotBorderWidth = 2,
            dotBoxShadow = TIMELINE_DOT_SHADOW,
        },

        Tree = {
            borderWidth = 4,
            borderColor = { 51, 197, 221, 255 },
            backgroundColor = { 255, 255, 255, 255 },
            borderRadius = { 5, 15, 5, 15 },
            padding = 16,
            hoverRadius = 12,
            selectedBgColor = { 217, 239, 255, 255 },
            selectedTextColor = { 91, 91, 91, 255 },
            fontWeight = "700",
        },
    },
})

-- ============================================================================
-- Initialize UI System
-- ============================================================================

local function initUI()
    UI.Init({
        theme = SweetopiaTheme,
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/NRO_v8-Medium.ttf",
                bold = "Fonts/NRO_v8-Medium.ttf",
            }},
            { family = "mono", weights = {
                normal = "Fonts/NRO_v8-Medium.ttf",
                bold = "Fonts/NRO_v8-Medium.ttf",
            }},
        },
        scale = UI.Scale.DEFAULT,
    })
end

-- ============================================================================
-- Shared State
-- ============================================================================

local state = {
    sliderValue = 50,
    progressValue = 0.3,
    textValue = "",
    isChecked = false,
    isToggled = true,
    dropdownValue = nil,
    ratingValue = 3,
    stepperStep = 1,
    paginationPage = 3,
}

-- Widgets that need per-frame update
local animatedWidgets = {
    progressBars = {},
}

-- ============================================================================
-- Helper: Demo Card — wraps each widget demo in a styled card
-- ============================================================================

local function demoCard(title, description, contentChildren, opts)
    opts = opts or {}
    local card = UI.Panel {
        width = "100%",
        padding = 16,
        gap = 10,
        backgroundColor = "#00000000",
        borderRadius = opts.borderRadius or { 5, 20, 5, 20 },
        borderWidth = 3,
        borderColor = UI.Theme.Color("border"),
        boxShadow = SOFT_SHADOW,
        marginBottom = 4,
        overflow = opts.overflow,
    }

    card:AddChild(UI.Label {
        text = title,
        fontWeight = "bold",
        fontSize = 15,
        fontColor = UI.Theme.Color("text"),
    })

    if description then
        card:AddChild(UI.Label {
            text = description,
            fontSize = 12,
            fontColor = UI.Theme.Color("textSecondary"),
            marginBottom = 4,
        })
    end

    if contentChildren then
        for _, child in ipairs(contentChildren) do
            card:AddChild(child)
        end
    end

    return card
end

-- ============================================================================
-- Helper: Horizontal row with wrapping
-- ============================================================================

local function row(opts)
    opts = opts or {}
    return UI.Row {
        gap = opts.gap or 10,
        flexWrap = "wrap",
        alignItems = opts.alignItems or "center",
    }
end

-- ============================================================================
-- Category: Basics (Button, Label, Panel)
-- ============================================================================

local function buildBasics()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- Buttons
    do
        local r = row()
        r:AddChild(UI.Button { text = "Primary", variant = "primary", onClick = function() UI.Toast.Show({ message = "Primary clicked!", variant = "success" }) end })
        r:AddChild(UI.Button { text = "Secondary", variant = "secondary" })
        r:AddChild(UI.Button { text = "Error", variant = "error" })
        r:AddChild(UI.Button { text = "Success", variant = "success" })
        r:AddChild(UI.Button { text = "Disabled", disabled = true })

        page:AddChild(demoCard("Button", "Interactive buttons with variant styles and states", { r }))
    end

    -- Button with custom colors & shadows
    do
        local r = row({ gap = 16 })
        r:AddChild(UI.Button {
            text = "Candy Glow",
            backgroundGradient = {
                type = "linear", direction = "to-right",
                from = UI.Theme.Color("primary"),
                to = UI.Theme.Color("warning"),
            },
            textColor = { 255, 255, 255, 255 },
            transition = "scale 0.2s easeOut",
        })
        r:AddChild(UI.Button {
            text = "Soft Shadow",
            shadowX = 0, shadowY = 4, shadowBlur = 14,
            shadowColor = { 52, 197, 221, 90 },
        })
        r:AddChild(UI.Button {
            text = "Elevated",
            shadowX = 0, shadowY = 8, shadowBlur = 24,
            shadowColor = { 255, 160, 33, 80 },
        })

        page:AddChild(demoCard("Button Styles", "Gradients, shadows, and transitions", { r }))
    end

    -- Label text features
    do
        local col = UI.Panel { width = "100%", gap = 8 }
        col:AddChild(UI.Label {
            text = "Bold Title",
            fontSize = 20,
            fontWeight = "bold",
            fontColor = UI.Theme.Color("text"),
        })
        col:AddChild(UI.Label {
            text = "UPPERCASE TRANSFORM",
            fontSize = 13,
            textTransform = "uppercase",
            letterSpacing = 3,
            fontColor = UI.Theme.Color("primary"),
        })
        col:AddChild(UI.Label {
            text = "Underline decoration & secondary color",
            fontSize = 13,
            textDecoration = "underline",
            fontColor = UI.Theme.Color("textSecondary"),
        })
        col:AddChild(UI.Label {
            text = "Multiline wrapping text: Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore.",
            fontSize = 13,
            whiteSpace = "normal",
            lineHeight = 1.5,
            fontColor = UI.Theme.Color("text"),
        })

        page:AddChild(demoCard("Label", "Typography: weight, transform, decoration, multiline", { col }))
    end

    -- Panel visual features
    do
        local r = row({ gap = 14 })

        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundGradient = {
                type = "linear", direction = "to-bottom-right",
                from = UI.Theme.Color("primary"),
                to = UI.Theme.Color("warning"),
            },
            borderRadius = 12,
        })
        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundColor = UI.Theme.Color("surface"),
            borderRadius = { 5, 30, 5, 30 },
            borderWidth = 2,
            borderColor = UI.Theme.Color("secondary"),
        })
        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundColor = UI.Theme.Color("surface"),
            borderRadius = 12,
            boxShadow = PANEL_SHADOW,
        })
        r:AddChild(UI.Panel {
            width = 70, height = 70,
            backgroundColor = UI.Theme.Color("secondary"),
            clipPath = "circle",
        })

        page:AddChild(demoCard("Panel", "Gradients, per-corner radius, box-shadow, clip-path", { r }))
    end

    return page
end

-- ============================================================================
-- Category: Input (TextField, Checkbox, Toggle, Slider, Stepper, Rating, FileUpload)
-- ============================================================================

local function buildInput()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- TextField
    do
        local statusLabel = UI.Label { text = "Type something...", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        local r = row()
        r:AddChild(UI.TextField {
            placeholder = "Enter text...",
            width = 200,
            onChange = function(_, v) statusLabel:SetText("Value: " .. v) end,
        })
        r:AddChild(UI.TextField { placeholder = "Password", password = true, width = 160 })
        r:AddChild(UI.TextField { placeholder = "Disabled", disabled = true, width = 160 })

        page:AddChild(demoCard("TextField", "Text input with placeholder, password mode, and disabled state", { r, statusLabel }))
    end

    -- Checkbox & Toggle
    do
        local statusLabel = UI.Label { text = "Checkbox: false | Toggle: true", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        local r = row({ gap = 24 })
        r:AddChild(UI.Checkbox {
            label = "Accept terms",
            checked = state.isChecked,
            onChange = function(_, checked)
                state.isChecked = checked
                statusLabel:SetText("Checkbox: " .. tostring(state.isChecked) .. " | Toggle: " .. tostring(state.isToggled))
            end,
        })
        r:AddChild(UI.Checkbox {
            label = "Disabled",
            checked = true,
            disabled = true,
        })
        r:AddChild(UI.Toggle {
            label = "Dark Mode",
            value = state.isToggled,
            onChange = function(_, value)
                state.isToggled = value
                statusLabel:SetText("Checkbox: " .. tostring(state.isChecked) .. " | Toggle: " .. tostring(state.isToggled))
            end,
        })
        r:AddChild(UI.Toggle {
            label = "Disabled",
            value = false,
            disabled = true,
        })

        page:AddChild(demoCard("Checkbox & Toggle", "Boolean selection controls with labels", { r, statusLabel }))
    end

    -- Slider
    do
        local statusLabel = UI.Label { text = "Value: 50", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        page:AddChild(demoCard("Slider", "Range value input with step control", {
            UI.Slider {
                value = state.sliderValue,
                min = 0, max = 100,
                width = 320,
                onChange = function(_, v)
                    state.sliderValue = v
                    statusLabel:SetText("Value: " .. math.floor(v))
                end,
            },
            statusLabel,
        }))
    end

    -- Stepper
    do
        local statusLabel = UI.Label { text = "Active step: 1", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        page:AddChild(demoCard("Stepper", "Step-by-step progress indicator (clickable)", {
            UI.Stepper {
                steps = {
                    { id = 1, label = "Account", description = "Create account" },
                    { id = 2, label = "Profile", description = "Set up profile" },
                    { id = 3, label = "Review", description = "Review & submit" },
                },
                activeStep = state.stepperStep,
                clickable = true,
                onChange = function(_, step)
                    state.stepperStep = step
                    statusLabel:SetText("Active step: " .. (step + 1))
                end,
            },
            statusLabel,
        }))
    end

    -- Rating
    do
        local statusLabel = UI.Label { text = "Rating: 3 / 5", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        local r = row({ gap = 24 })
        r:AddChild(UI.Rating {
            value = state.ratingValue,
            max = 5,
            icon = "star",
            size = "lg",
            onChange = function(_, v)
                state.ratingValue = v
                statusLabel:SetText("Rating: " .. v .. " / 5")
            end,
        })
        r:AddChild(UI.Rating {
            value = 4,
            max = 5,
            icon = "heart",
            size = "md",
            readOnly = true,
        })

        page:AddChild(demoCard("Rating", "Star and heart icons, interactive and read-only modes", { r, statusLabel }))
    end

    -- FileUpload
    do
        page:AddChild(demoCard("FileUpload", "Drag-and-drop file upload zone", {
            UI.FileUpload {
                variant = "dropzone",
                multiple = true,
                onFileSelect = function(_, file) print("File: " .. file.name) end,
            },
        }))
    end

    return page
end

-- ============================================================================
-- Category: Select (Dropdown, DatePicker, TimePicker, ColorPicker, Calendar, Menu, Tree)
-- ============================================================================

local function buildSelect()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- Dropdown
    do
        local statusLabel = UI.Label { text = "Selected: none", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        page:AddChild(demoCard("Dropdown", "Floating option list with search", {
            UI.Dropdown {
                placeholder = "Choose a framework...",
                options = {
                    { value = "react", label = "React" },
                    { value = "vue", label = "Vue" },
                    { value = "angular", label = "Angular" },
                    { value = "svelte", label = "Svelte" },
                    { value = "solid", label = "SolidJS" },
                },
                width = 220,
                onChange = function(_, v) statusLabel:SetText("Selected: " .. tostring(v)) end,
            },
            statusLabel,
        }))
    end

    -- DatePicker & TimePicker
    do
        local r = row({ gap = 16 })
        r:AddChild(UI.DatePicker {
            placeholder = "Pick a date...",
            onChange = function(_, date)
                if date then
                    print("Date: " .. date.year .. "-" .. date.month .. "-" .. date.day)
                end
            end,
        })
        r:AddChild(UI.TimePicker {
            placeholder = "Pick a time...",
            onChange = function(_, time)
                if time then print("Time: " .. tostring(time)) end
            end,
        })

        page:AddChild(demoCard("DatePicker & TimePicker", "Calendar and scrollwheel-style time selection", { r }))
    end

    -- ColorPicker
    do
        page:AddChild(demoCard("ColorPicker", "HSV color selector with alpha support", {
            UI.ColorPicker {
                value = UI.Theme.Color("primary"),
                onChange = function(_, color) end,
            },
        }))
    end

    -- Calendar
    do
        local statusLabel = UI.Label { text = "No date selected", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        page:AddChild(demoCard("Calendar", "Full month calendar with date selection", {
            UI.Calendar {
                onDateSelect = function(_, date)
                    statusLabel:SetText("Selected: " .. date.year .. "-" .. date.month .. "-" .. date.day)
                end,
            },
            statusLabel,
        }))
    end

    -- Menu
    do
        page:AddChild(demoCard("Menu", "Context menu with dividers and actions", {
            UI.Menu {
                items = {
                    { label = "Cut", onClick = function() UI.Toast.Show({ message = "Cut!", variant = "info" }) end },
                    { label = "Copy", onClick = function() UI.Toast.Show({ message = "Copied!", variant = "info" }) end },
                    { label = "Paste", onClick = function() UI.Toast.Show({ message = "Pasted!", variant = "success" }) end },
                    { type = "divider" },
                    { label = "Delete", onClick = function() UI.Toast.Show({ message = "Deleted!", variant = "error" }) end },
                },
            },
        }))
    end

    -- Tree
    do
        page:AddChild(demoCard("Tree", "Hierarchical tree view with expand/collapse", {
            UI.Tree {
                nodes = {
                    {
                        label = "Project",
                        expanded = true,
                        children = {
                            { label = "src", children = {
                                { label = "main.lua" },
                                { label = "utils.lua" },
                            }},
                            { label = "assets", children = {
                                { label = "textures" },
                                { label = "sounds" },
                            }},
                            { label = "README.md" },
                        },
                    },
                },
                showLines = true,
            },
        }))
    end

    return page
end

-- ============================================================================
-- Category: Display (Card, Badge, Chip, Avatar, Alert, Tooltip, Skeleton, RichText, ProgressBar)
-- ============================================================================

local function buildDisplay()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- Cards
    do
        local r = row({ gap = 14 })
        r:AddChild(UI.Card {
            width = 180,
            variant = "elevated",
            elevation = 2,
            hoverable = true,
            children = {
                UI.Label { text = "Elevated Card", fontWeight = "bold", fontSize = 14 },
                UI.Label { text = "With soft shadow depth.", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") },
            },
        })
        r:AddChild(UI.Card {
            width = 180,
            variant = "outlined",
            backgroundColor = { 255, 252, 241, 255 },
            borderColor = UI.Theme.Color("warning"),
            boxShadow = false,
            children = {
                UI.Label { text = "Outlined Card", fontWeight = "bold", fontSize = 14 },
                UI.Label { text = "Clean border style.", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") },
            },
        })
        r:AddChild(UI.Card {
            width = 180,
            variant = "filled",
            backgroundGradient = {
                type = "linear",
                direction = "to-bottom-right",
                from = UI.Theme.Color("primary"),
                to = UI.Theme.Color("warning"),
            },
            borderColor = UI.Theme.Color("secondary"),
            boxShadow = false,
            children = {
                UI.Label { text = "Filled Card", fontWeight = "bold", fontSize = 14, fontColor = { 255, 255, 255, 255 } },
                UI.Label { text = "Solid background.", fontSize = 12, fontColor = { 255, 255, 255, 230 } },
            },
        })

        page:AddChild(demoCard("Card", "Container with elevated, outlined, and filled variants", { r }))
    end

    -- Badges
    do
        local r = row({ gap = 14 })
        r:AddChild(UI.Badge { content = "5", variant = "primary" })
        r:AddChild(UI.Badge { content = "New", variant = "success" })
        r:AddChild(UI.Badge { content = "99+", variant = "error" })
        r:AddChild(UI.Badge { dot = true, variant = "warning", pulse = true })

        page:AddChild(demoCard("Badge", "Notification badges with content, dot mode, and pulse animation", { r }))
    end

    -- Chips
    do
        local r = row({ gap = 8 })
        r:AddChild(UI.Chip { label = "Default", variant = "filled", color = "default" })
        r:AddChild(UI.Chip { label = "Primary", variant = "filled", color = "primary" })
        r:AddChild(UI.Chip { label = "Success", variant = "soft", color = "success" })
        r:AddChild(UI.Chip { label = "Outlined", variant = "outlined", color = "error" })
        r:AddChild(UI.Chip { label = "Deletable", variant = "filled", color = "primary", deletable = true,
            onDelete = function() UI.Toast.Show({ message = "Chip deleted", variant = "info" }) end,
        })

        page:AddChild(demoCard("Chip", "Compact tags with variants: filled, outlined, soft; colors and delete", { r }))
    end

    -- Avatars
    do
        local r = row({ gap = 12 })
        r:AddChild(UI.Avatar {
            initials = "A",
            size = "xs",
            backgroundColor = UI.Theme.Color("avatarCyan"),
            borderColor = UI.Theme.Color("avatarCyanBorder"),
        })
        r:AddChild(UI.Avatar {
            initials = "BC",
            size = "sm",
            status = "online",
            backgroundColor = UI.Theme.Color("avatarCyan"),
            borderColor = UI.Theme.Color("avatarCyanBorder"),
        })
        r:AddChild(UI.Avatar {
            name = "John Doe",
            size = "md",
            status = "away",
            backgroundColor = UI.Theme.Color("avatarCyan"),
            borderColor = UI.Theme.Color("avatarCyanBorder"),
        })
        r:AddChild(UI.Avatar {
            initials = "XY",
            size = "lg",
            shape = "rounded",
            backgroundColor = UI.Theme.Color("avatarPink"),
            borderColor = UI.Theme.Color("avatarPinkBorder"),
        })
        r:AddChild(UI.Avatar {
            initials = "Z",
            size = "xl",
            shape = "square",
            backgroundColor = UI.Theme.Color("avatarYellow"),
            borderColor = UI.Theme.Color("avatarYellowBorder"),
        })

        page:AddChild(demoCard("Avatar", "User avatars: sizes xs-xl, shapes, online status indicator", { r }))
    end

    -- Alerts
    do
        local col = UI.Panel { width = "100%", gap = 8 }
        col:AddChild(UI.Alert { severity = "info", title = "Info", message = "Helpful information for the user." })
        col:AddChild(UI.Alert { severity = "success", title = "Success", message = "Operation completed successfully." })
        col:AddChild(UI.Alert { severity = "warning", title = "Warning", message = "Please review before proceeding." })
        col:AddChild(UI.Alert { severity = "error", title = "Error", message = "Something went wrong.", closable = true })

        page:AddChild(demoCard("Alert", "Notification banners with severity levels", { col }))
    end

    -- Tooltip
    do
        page:AddChild(demoCard("Tooltip", "Hover to reveal contextual information", {
            UI.Tooltip {
                content = "This is a helpful tooltip!",
                position = "top",
                children = {
                    UI.Button { text = "Hover me for tooltip", variant = "secondary" },
                },
            },
        }))
    end

    -- Skeleton
    do
        local r = row({ gap = 12 })
        r:AddChild(UI.Skeleton { variant = "circular", width = 48, height = 48 })
        r:AddChild(UI.Column {
            gap = 8,
            children = {
                UI.Skeleton { variant = "text", width = 180, height = 16 },
                UI.Skeleton { variant = "text", width = 120, height = 14 },
                UI.Skeleton { variant = "rectangular", width = 180, height = 40, borderRadius = 6 },
            },
        })

        page:AddChild(demoCard("Skeleton", "Loading placeholders with pulse animation", { r }))
    end

    -- RichText
    do
        page:AddChild(demoCard("RichText", "Markdown-style rich text rendering", {
            UI.RichText {
                content = "# Heading\n## Subheading\n\nThis is **bold** and *italic* text.\n\n- List item 1\n- List item 2\n\n> A blockquote\n\n`inline code`",
            },
        }))
    end

    -- ProgressBar
    do
        local col = UI.Panel { width = "100%", gap = 10 }

        local pb1 = UI.ProgressBar {
            value = 0.3, width = "100%",
            variant = "primary",
            transition = "value 0.3s easeOut",
        }
        table.insert(animatedWidgets.progressBars, pb1)
        col:AddChild(pb1)

        col:AddChild(UI.ProgressBar {
            value = 0.65, width = "100%",
            fillGradient = {
                direction = "to-right",
                from = UI.Theme.Color("success"),
                to = UI.Theme.Color("info"),
            },
            borderRadius = 6,
            height = 12,
        })

        col:AddChild(UI.ProgressBar {
            value = 0, width = "100%",
            variant = "warning",
            indeterminate = true,
        })

        page:AddChild(demoCard("ProgressBar", "Determinate with gradient, and indeterminate loading mode", { col }))
    end

    return page
end

-- ============================================================================
-- Category: Navigation (Tabs, Breadcrumb, Pagination)
-- ============================================================================

local function buildNavigation()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- Tabs variants
    do
        local col = UI.Panel { width = "100%", gap = 16 }

        -- Line variant
        local lineTabs = UI.Tabs {
            tabs = {
                { id = "home", label = "Home" },
                { id = "explore", label = "Explore" },
                { id = "settings", label = "Settings" },
            },
            activeTab = "home",
            variant = "line",
            width = "100%",
            height = 150,
        }
        lineTabs:SetTabContent("home", UI.Label { text = "Home content area", textAlign = "center", verticalAlign = "middle" })
        lineTabs:SetTabContent("explore", UI.Label { text = "Explore content area", textAlign = "center", verticalAlign = "middle" })
        lineTabs:SetTabContent("settings", UI.Label { text = "Settings content area", textAlign = "center", verticalAlign = "middle" })
        col:AddChild(lineTabs)

        -- Pills variant
        col:AddChild(UI.Tabs {
            tabs = {
                { id = "all", label = "All" },
                { id = "active", label = "Active" },
                { id = "completed", label = "Completed" },
            },
            activeTab = "all",
            variant = "pills",
            width = "100%",
        })

        -- Enclosed variant
        col:AddChild(UI.Tabs {
            tabs = {
                { id = "overview", label = "Overview" },
                { id = "members", label = "Members" },
                { id = "logs", label = "Logs" },
            },
            activeTab = "overview",
            variant = "enclosed",
            width = "100%",
        })

        page:AddChild(demoCard("Tabs", "Tab navigation: line, pills, and enclosed variants", { col }))
    end

    -- Breadcrumb
    do
        page:AddChild(demoCard("Breadcrumb", "Hierarchical navigation path", {
            UI.Breadcrumb {
                items = {
                    { label = "Home", onClick = function() print("Home") end },
                    { label = "Products", onClick = function() print("Products") end },
                    { label = "Electronics", onClick = function() print("Electronics") end },
                    { label = "Smartphones" },
                },
                width = "100%",
            },
        }))
    end

    -- Pagination
    do
        local statusLabel = UI.Label { text = "Page: 3", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") }
        page:AddChild(demoCard("Pagination", "Page navigation with numbered buttons", {
            UI.Pagination {
                currentPage = state.paginationPage,
                totalPages = 12,
                onChange = function(_, p)
                    state.paginationPage = p
                    statusLabel:SetText("Page: " .. p)
                end,
            },
            statusLabel,
        }))
    end

    return page
end

-- ============================================================================
-- Category: Data (Table, List, Accordion, Timeline)
-- ============================================================================

local function buildData()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- Table
    do
        page:AddChild(demoCard("Table", "Data table with striped rows and hover highlight", {
            UI.Table {
                columns = {
                    { key = "name", label = "Name", width = 140 },
                    { key = "role", label = "Role", width = 120 },
                    { key = "status", label = "Status", width = 100 },
                    { key = "email", label = "Email", width = 200 },
                },
                data = {
                    { name = "Alice Chen", role = "Engineer", status = "Active", email = "alice@example.com" },
                    { name = "Bob Smith", role = "Designer", status = "Away", email = "bob@example.com" },
                    { name = "Carol Wu", role = "Manager", status = "Active", email = "carol@example.com" },
                    { name = "David Kim", role = "DevOps", status = "Offline", email = "david@example.com" },
                },
                variant = "striped",
                hoverable = true,
            },
        }))
    end

    -- List
    do
        page:AddChild(demoCard("List", "Structured list with primary/secondary text and dividers", {
            UI.List {
                items = {
                    { id = "inbox", text = "Inbox", secondaryText = "3 unread messages" },
                    { id = "sent", text = "Sent", secondaryText = "Last sent yesterday" },
                    { id = "drafts", text = "Drafts", secondaryText = "2 drafts pending" },
                    { id = "archive", text = "Archive", secondaryText = "Empty" },
                },
                showDividers = true,
                selectable = true,
                onSelect = function(_, selected) print("Selected: " .. tostring(selected)) end,
            },
        }))
    end

    -- Accordion
    do
        page:AddChild(demoCard("Accordion", "Expandable content sections", {
            UI.Accordion {
                items = {
                    { id = "faq1", title = "What is UrhoX?", content = "UrhoX is a modern game engine based on Urho3D with AI-friendly development tools." },
                    { id = "faq2", title = "What layout engine is used?", content = "Yoga (from React Native) powers the Flexbox layout system. Note: defaults differ from CSS!" },
                    { id = "faq3", title = "How many widgets are available?", content = "42 base widgets plus 7 advanced components, covering most UI needs." },
                },
                width = "100%",
                height = 220,
                variant = "separated",
            },
        }))
    end

    -- Timeline
    do
        page:AddChild(demoCard("Timeline", "Chronological event display", {
            UI.Timeline {
                items = {
                    { title = "Project Created", description = "Initial repository setup", time = "Jan 2024" },
                    { title = "Alpha Release", description = "Core features completed", time = "Jun 2024" },
                    {
                        title = "Beta Testing",
                        description = "Community feedback phase",
                        time = "Dec 2024",
                        color = { 169, 169, 169, 255 },
                        titleColor = { 130, 130, 130, 255 },
                        dotBoxShadow = false,
                    },
                    {
                        title = "v1.0 Release",
                        description = "Stable release planned",
                        time = "2025",
                        color = { 169, 169, 169, 255 },
                        titleColor = { 130, 130, 130, 255 },
                        dotBoxShadow = false,
                    },
                },
                size = "md",
            },
        }))
    end

    return page
end

-- ============================================================================
-- Category: Overlay (Modal, Drawer, Popover, Toast)
-- ============================================================================

-- These overlay widgets need to be attached to root
local overlayWidgets = {}

local function buildOverlay()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- Modal
    do
        -- Basic modal
        local basicModal = UI.Modal {
            title = "Welcome",
            size = "md",
        }
        basicModal:AddContent(UI.Label { text = "This is a basic modal dialog." })
        basicModal:AddContent(UI.Label { text = "It supports title, content, and footer sections." })
        table.insert(overlayWidgets, basicModal)

        -- Modal with footer
        local footerModal = UI.Modal {
            title = "Confirm Action",
            size = "md",
        }
        footerModal:AddContent(UI.Label { text = "Are you sure you want to proceed?" })
        footerModal:AddContent(UI.Label { text = "This action may have consequences.", fontColor = UI.Theme.Color("textSecondary") })
        local footerPanel = UI.Panel {
            flexDirection = "row", justifyContent = "flex-end", gap = 8, width = "100%",
        }
        footerPanel:AddChild(UI.Button { text = "Cancel", variant = "secondary", onClick = function() footerModal:Close() end })
        footerPanel:AddChild(UI.Button { text = "Confirm", variant = "primary", onClick = function()
            footerModal:Close()
            UI.Toast.Show({ message = "Action confirmed!", variant = "success" })
        end })
        footerModal:SetFooter(footerPanel)
        table.insert(overlayWidgets, footerModal)

        -- Interactive modal
        local interactiveModal = UI.Modal {
            title = "Edit Profile",
            size = "lg",
        }
        interactiveModal:AddContent(UI.TextField { placeholder = "Your name...", width = "100%" })
        interactiveModal:AddContent(UI.TextField { placeholder = "Email address...", width = "100%" })
        interactiveModal:AddContent(UI.Dropdown {
            placeholder = "Select role...",
            options = {
                { value = "dev", label = "Developer" },
                { value = "design", label = "Designer" },
                { value = "pm", label = "Product Manager" },
            },
            width = 200,
        })
        table.insert(overlayWidgets, interactiveModal)

        local r = row({ gap = 8 })
        r:AddChild(UI.Button { text = "Basic Modal", onClick = function() basicModal:Open() end })
        r:AddChild(UI.Button { text = "With Footer", onClick = function() footerModal:Open() end })
        r:AddChild(UI.Button { text = "Interactive", onClick = function() interactiveModal:Open() end })
        r:AddChild(UI.Button { text = "Quick Confirm", variant = "error", onClick = function()
            local m = UI.Modal.Confirm {
                title = "Delete Item?",
                message = "This cannot be undone.",
                confirmText = "Delete",
                onConfirm = function() UI.Toast.Show({ message = "Item deleted", variant = "error" }) end,
            }
            table.insert(overlayWidgets, m)
        end })

        page:AddChild(demoCard("Modal", "Dialog overlays: basic, with footer, interactive content, confirm dialog", { r }))
    end

    -- Drawer
    do
        local drawerContent = UI.Panel {
            width = "100%",
            gap = 4,
            children = {
                UI.Menu {
                    items = {
                        { label = "Dashboard", onClick = function() UI.Toast.Show({ message = "Dashboard", variant = "info" }) end },
                        { label = "Analytics", onClick = function() UI.Toast.Show({ message = "Analytics", variant = "info" }) end },
                        { label = "Projects", onClick = function() UI.Toast.Show({ message = "Projects", variant = "info" }) end },
                        { type = "divider" },
                        { label = "Settings", onClick = function() UI.Toast.Show({ message = "Settings", variant = "info" }) end },
                        { label = "Help & Support", onClick = function() UI.Toast.Show({ message = "Help", variant = "info" }) end },
                    },
                },
                UI.Panel { height = 8 },
                UI.Divider {},
                UI.Panel { height = 4 },
                UI.Label {
                    text = "UrhoX UI v" .. UI.VERSION,
                    fontSize = 10,
                    fontColor = UI.Theme.Color("textSecondary"),
                    paddingHorizontal = 12,
                },
            },
        }

        local drawer = UI.Drawer {
            position = "left",
            size = 280,
            header = "Menu",
            showCloseButton = true,
            content = drawerContent,
        }
        table.insert(overlayWidgets, drawer)

        page:AddChild(demoCard("Drawer", "Sliding side panel from screen edge", {
            UI.Button { text = "Open Drawer", onClick = function() drawer:Open() end },
        }))
    end

    -- Popover
    do
        page:AddChild(demoCard("Popover", "Floating content anchored to an element", {
            UI.Popover {
                content = "This popover floats above the button.\nIt can contain any content.",
                placement = "bottom",
                trigger = "click",
                title = "Popover Title",
                children = {
                    UI.Button { text = "Click for Popover", variant = "secondary" },
                },
            },
        }))
    end

    -- Toast
    do
        local r = row({ gap = 8 })
        r:AddChild(UI.Button { text = "Info", variant = "primary",
            onClick = function() UI.Toast.Show({ message = "Information message", variant = "info" }) end,
        })
        r:AddChild(UI.Button { text = "Success", variant = "success",
            onClick = function() UI.Toast.Show({ message = "Operation successful!", variant = "success" }) end,
        })
        r:AddChild(UI.Button { text = "Warning",
            onClick = function() UI.Toast.Show({ message = "Warning: check your input", variant = "warning" }) end,
        })
        r:AddChild(UI.Button { text = "Error", variant = "error",
            onClick = function() UI.Toast.Show({ message = "Something went wrong!", variant = "error" }) end,
        })

        page:AddChild(demoCard("Toast", "Temporary notification messages with auto-dismiss", { r }))
    end

    return page
end

-- ============================================================================
-- Category: Layout (ScrollView, SimpleGrid, Divider, Carousel, SafeAreaView)
-- ============================================================================

local function buildLayout()
    local page = UI.Panel { width = "100%", gap = 12 }

    -- Divider
    do
        local col = UI.Panel { width = "100%", gap = 8 }
        col:AddChild(UI.Label { text = "Above solid divider", fontSize = 13 })
        col:AddChild(UI.Divider {})
        col:AddChild(UI.Label { text = "Between dividers", fontSize = 13 })
        col:AddChild(UI.Divider { variant = "dashed" })
        col:AddChild(UI.Label { text = "Below dashed divider", fontSize = 13 })
        col:AddChild(UI.Divider.WithLabel("OR"))
        col:AddChild(UI.Label { text = "After labeled divider", fontSize = 13 })

        page:AddChild(demoCard("Divider", "Horizontal separators: solid, dashed, and with label", { col }))
    end

    -- SimpleGrid
    do
        local gridChildren = {}
        local gridColors = {
            UI.Theme.Color("primary"),
            UI.Theme.Color("success"),
            UI.Theme.Color("warning"),
            UI.Theme.Color("error"),
            UI.Theme.Color("secondary"),
            UI.Theme.Color("info"),
        }
        for i = 1, 6 do
            local c = gridColors[i]
            table.insert(gridChildren, UI.Panel {
                height = 60,
                backgroundColor = { c[1], c[2], c[3], 180 },
                borderRadius = 8,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "Item " .. i, fontColor = { 255, 255, 255, 255 }, fontSize = 13, fontWeight = "bold" },
                },
            })
        end

        page:AddChild(demoCard("SimpleGrid", "Equal-width column grid layout (3 columns)", {
            UI.SimpleGrid {
                columns = 3,
                gap = 10,
                children = gridChildren,
            },
        }))
    end

    -- Carousel
    do
        local carouselColors = {
            { 255, 160, 33 },
            { 52, 197, 221 },
            { 142, 217, 72 },
            { 255, 200, 102 },
        }
        local carouselItems = {}
        for i, c in ipairs(carouselColors) do
            table.insert(carouselItems, {
                content = "Slide " .. i,
                backgroundColor = string.format("#%02x%02x%02x", c[1], c[2], c[3]),
            })
        end

        page:AddChild(demoCard("Carousel", "Auto-playing slide carousel with navigation", {
            UI.Carousel {
                items = carouselItems,
                width = "100%",
                height = 180,
                autoPlay = true,
                autoPlayInterval = 4,
                showArrows = true,
                showIndicators = true,
            },
        }))
    end

    -- ScrollView demo (nested)
    do
        local scrollContent = UI.Panel { width = "100%", gap = 4 }
        for i = 1, 15 do
            scrollContent:AddChild(UI.Label {
                text = "Scrollable item #" .. i,
                fontSize = 13,
                paddingVertical = 6,
                paddingHorizontal = 10,
            })
        end

        page:AddChild(demoCard("ScrollView", "Scrollable container with inertia and scrollbar", {
            UI.ScrollView {
                width = "100%",
                height = 160,
                scrollY = true,
                showScrollbar = true,
                children = { scrollContent },
            },
        }))
    end

    return page
end

-- ============================================================================
-- Category Builders Map
-- ============================================================================

local categories = {
    { id = "basics",  label = "Basics",  builder = buildBasics },
    { id = "input",   label = "Input",   builder = buildInput },
    { id = "select",  label = "Select",  builder = buildSelect },
    { id = "display", label = "Display", builder = buildDisplay },
    { id = "nav",     label = "Nav",     builder = buildNavigation },
    { id = "data",    label = "Data",    builder = buildData },
    { id = "overlay", label = "Overlay", builder = buildOverlay },
    { id = "layout",  label = "Layout",  builder = buildLayout },
}

-- ============================================================================
-- Build Main Layout
-- ============================================================================

function Start()
    initUI()

    -- Root container
    local root = UI.Panel {
        id = "gallery-root",
        width = "100%",
        height = "100%",
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom-right",
            from = UI.Theme.Color("background"),
            to = UI.Theme.Color("backgroundAlt"),
        },
    }

    -- ── Top Bar ──────────────────────────────────────────────────────────────

    local topBar = UI.Panel {
        width = "100%",
        height = 56,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 20,
        gap = 12,
        backgroundGradient = {
            type = "linear",
            direction = "to-right",
            from = UI.Theme.Color("secondary"),
            to = UI.Theme.Color("info"),
        },
        borderBottomWidth = 4,
        borderBottomColor = UI.Theme.Color("borderFocus"),
    }

    topBar:AddChild(UI.Label {
        text = "Sweetopia UI Gallery",
        fontSize = 18,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
    })

    topBar:AddChild(UI.Spacer())

    -- Theme color swatches
    local swatchRow = UI.Row { gap = 6 }
    local swatchColors = { "primary", "success", "warning", "error" }
    for _, name in ipairs(swatchColors) do
        swatchRow:AddChild(UI.Panel {
            width = 16, height = 16,
            backgroundColor = UI.Theme.Color(name),
            borderRadius = 4,
            borderWidth = 2,
            borderColor = { 255, 255, 255, 100 },
        })
    end
    topBar:AddChild(swatchRow)

    topBar:AddChild(UI.Label {
        text = "v" .. UI.VERSION,
        fontSize = 12,
        fontColor = { 255, 255, 255, 180 },
    })

    root:AddChild(topBar)

    -- ── Body: Sidebar + Content ─────────────────────────────────────────────

    local body = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexDirection = "row",
        padding = 12,
        gap = 12,
    }

    -- Sidebar nav tabs (vertical pills)
    local sidebarTabs = UI.Tabs {
        tabs = {},
        variant = "pills",
        orientation = "vertical",
        tabWidth = 100,
        width = 100,
        height = "100%",
        backgroundColor = UI.Theme.Color("surfaceCream"),
        borderRadius = 12,
        borderWidth = 3,
        borderColor = UI.Theme.Color("border"),
        paddingVertical = 6,
        activeTextColor = { 255, 255, 255, 255 },
        inactiveTextColor = UI.Theme.Color("textSecondary"),
    }

    for _, cat in ipairs(categories) do
        table.insert(sidebarTabs.props.tabs, { id = cat.id, label = cat.label })
    end
    sidebarTabs.props.activeTab = categories[1].id

    body:AddChild(sidebarTabs)

    -- Content area
    local contentArea = UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        height = "100%",
        borderRadius = { 5, 30, 5, 30 },
        borderWidth = 0,
        borderColor = UI.Theme.Color("border"),
        boxShadow = PANEL_SHADOW,
        overflow = "hidden",
    }

    local contentScroll = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        padding = 16,
    }
    contentArea:AddChild(contentScroll)

    -- Build initial content
    local currentContent = nil

    local function switchCategory(catId)
        -- Clear old content
        if currentContent then
            contentScroll:RemoveChild(currentContent)
            currentContent:Destroy()
            currentContent = nil
        end

        -- Clear animated widgets
        animatedWidgets.progressBars = {}

        -- Build new content
        local prevCount = #overlayWidgets
        for _, cat in ipairs(categories) do
            if cat.id == catId then
                currentContent = cat.builder()
                contentScroll:AddChild(currentContent)
                contentScroll:ScrollToTop()
                break
            end
        end

        -- Attach any new overlay widgets created by the builder
        for i = prevCount + 1, #overlayWidgets do
            root:AddChild(overlayWidgets[i])
        end
    end

    -- Wire up tab change
    sidebarTabs.props.onChange = function(_, tabId)
        switchCategory(tabId)
    end

    body:AddChild(contentArea)
    root:AddChild(body)

    -- ── Footer ──────────────────────────────────────────────────────────────

    local footer = UI.Panel {
        width = "100%",
        height = 32,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 6,
        backgroundColor = UI.Theme.Color("surfaceCream"),
        borderTopWidth = 3,
        borderTopColor = UI.Theme.Color("borderFocus"),
    }

    footer:AddChild(UI.Label {
        text = "UrhoX UI v" .. UI.VERSION,
        fontSize = 11,
        fontColor = UI.Theme.Color("textSecondary"),
    })

    footer:AddChild(UI.Label {
        text = " | ",
        fontSize = 11,
        fontColor = UI.Theme.Color("border"),
    })

    footer:AddChild(UI.Label {
        text = "42 Widgets",
        fontSize = 11,
        fontColor = UI.Theme.Color("textSecondary"),
    })

    footer:AddChild(UI.Label {
        text = " | ",
        fontSize = 11,
        fontColor = UI.Theme.Color("border"),
    })

    footer:AddChild(UI.Label {
        text = "Yoga + NanoVG",
        fontSize = 11,
        fontColor = UI.Theme.Color("textSecondary"),
    })

    root:AddChild(footer)

    -- ============================================================================
    -- Set Root & Initialize
    -- ============================================================================

    UI.SetRoot(root)

    -- Build initial category
    switchCategory(categories[1].id)

    -- Attach overlay widgets to root
    for _, w in ipairs(overlayWidgets) do
        root:AddChild(w)
    end

    -- ============================================================================
    -- Update Loop (progress bar animation)
    -- ============================================================================

    local eventNode = Node()
    local eventHandler = eventNode:CreateScriptObject("LuaScriptObject")
    eventHandler:SubscribeToEvent("Update", function(self, eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()

        for _, pb in ipairs(animatedWidgets.progressBars) do
            local val = pb:GetValue() + dt * 0.08
            if val > 1 then val = 0 end
            pb:SetValue(val)
        end
    end)

end -- Start()
