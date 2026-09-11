local Theme = require("urhox-libs/UI/Core/Theme")
local DefaultDark = require("urhox-libs/UI/Theme/DefaultDark")

local PIXEL_SHADOW = {
    { x = 4, y = 4, blur = 0, color = { 5, 5, 16, 210 } },
}

return Theme.ExtendTheme(DefaultDark, {
    fonts = {
        { family = "sans", weights = {
            normal = "Fonts/FusionPixel-12px-Prop-zh_hans.ttf",
            bold = "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf",
        }},
    },
    colors = {
        primary = { 33, 189, 174, 255 },
        primaryHover = { 55, 222, 204, 255 },
        primaryPressed = { 24, 145, 136, 255 },
        primaryDeep = { 17, 102, 98, 255 },
        primaryShadow = { 11, 82, 78, 255 },
        secondary = { 108, 92, 231, 255 },
        secondaryHover = { 137, 123, 255, 255 },
        secondaryPressed = { 77, 63, 190, 255 },
        secondaryDeep = { 48, 39, 119, 255 },
        secondaryShadow = { 48, 39, 119, 255 },
        background = { 15, 15, 35, 255 },
        surface = { 27, 27, 58, 245 },
        surfaceAlt = { 35, 33, 70, 255 },
        text = { 244, 239, 222, 255 },
        textSecondary = { 194, 188, 205, 255 },
        textMuted = { 137, 133, 160, 255 },
        border = { 82, 74, 115, 255 },
        borderStrong = { 132, 111, 170, 255 },
        warning = { 255, 198, 73, 255 },
        error = { 255, 71, 87, 255 },
        errorHover = { 255, 102, 116, 255 },
        errorPressed = { 190, 42, 57, 255 },
        errorShadow = { 126, 24, 36, 255 },
        overlay = { 5, 5, 16, 220 },
    },
    radius = { xs = 0, sm = 0, md = 0, lg = 0, full = 0 },
    componentDefaults = { borderRadius = 0 },
    components = {
        Button = {
            height = 46,
            borderRadius = 0,
            borderWidth = 2,
            borderColor = { 169, 149, 202, 255 },
            fontSize = 14,
            fontWeight = "bold",
            glowShadow = {
                color = { 5, 5, 16, 220 },
                alpha = { default = 220, hover = 220 },
                blur = { default = 0, hover = 0 },
                offset = { default = { 0, 4 }, hover = { 0, 4 } },
                inset = true,
                side = "bottom",
                pressed = { color = { 0, 0, 0, 0 }, blur = 0, offset = { 0, 0 }, inset = true, side = "bottom" },
            },
            padding = { 0, 8, 4, 8 },
            pressedPadding = 0,
        },
        ProgressBar = {
            height = 12,
            borderRadius = 0,
            borderWidth = 2,
            borderColor = { 82, 74, 115, 255 },
        },
        Card = {
            borderRadius = 0,
            borderWidth = 2,
            boxShadow = PIXEL_SHADOW,
        },
    },
})
