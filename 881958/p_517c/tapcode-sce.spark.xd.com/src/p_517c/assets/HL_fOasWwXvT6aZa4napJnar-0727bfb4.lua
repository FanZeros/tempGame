-- 弹射 4096 的视觉主题。
-- 与微信版 PALETTE / RETRO / COMIC / FLOOR / VALUE_COLORS 保持一致。

local PALETTE = {
    blue = { 0, 79, 166, 255 },
    green = { 0, 171, 116, 255 },
    red = { 255, 72, 70, 255 },
    yellow = { 255, 203, 36, 255 },
    cream = { 255, 249, 223, 255 },
}

local RETRO = {
    charcoal = PALETTE.blue,
    ink = PALETTE.blue,
    forest = PALETTE.blue,
    teal = PALETTE.green,
    aqua = PALETTE.green,
    mint = PALETTE.green,
    mustard = PALETTE.yellow,
    straw = PALETTE.cream,
    blood = PALETTE.red,
    burgundy = PALETTE.red,
    cream = PALETTE.cream,
    brown = PALETTE.blue,
    plum = PALETTE.blue,
}

return {
    PALETTE = PALETTE,
    RETRO = RETRO,
    COMIC = {
        background = PALETTE.cream,
        yellow = PALETTE.yellow,
        orange = PALETTE.red,
        blue = PALETTE.blue,
        cream = PALETTE.cream,
        ink = PALETTE.blue,
    },
    FLOOR = {
        base = PALETTE.cream,
        plankLight = { 255, 244, 204, 255 },
        plankWarm = { 255, 239, 182, 255 },
        plankGold = { 255, 232, 156, 255 },
        gutter = { 255, 222, 115, 255 },
        seam = { 255, 217, 92, 255 },
        marker = PALETTE.yellow,
        boundary = { 169, 107, 80, 255 },
    },
    BACKGROUND_BLUE = { 46, 110, 176, 255 },
    DOODLE_COLORS = {
        PALETTE.red,
        PALETTE.yellow,
        PALETTE.green,
        { 107, 150, 190, 255 },
    },
    VALUE_COLORS = {
        [2] = PALETTE.red,
        [4] = PALETTE.yellow,
        [8] = PALETTE.green,
        [16] = PALETTE.blue,
        [32] = { 255, 105, 62, 255 },
        [64] = { 255, 219, 100, 255 },
        [128] = { 56, 188, 140, 255 },
        [256] = { 51, 113, 177, 255 },
        [512] = { 209, 73, 87, 255 },
        [1024] = { 179, 193, 60, 255 },
        [2048] = { 0, 145, 130, 255 },
        [4096] = { 0, 97, 156, 255 },
        [8192] = { 255, 114, 107, 255 },
    },
}
