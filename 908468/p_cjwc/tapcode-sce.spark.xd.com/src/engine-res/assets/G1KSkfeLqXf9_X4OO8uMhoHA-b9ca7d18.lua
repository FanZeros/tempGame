-- ============================================================================
-- UrhoX UI Gallery — Astroon Cosmic Cartoon Edition
-- Dark cosmic-themed game UI: pill buttons, gradient glows, gold primary CTA
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- Astroon Cosmic Theme
-- ============================================================================

local COSMIC_SHADOW = {
    { x = 0, y = 0, blur = 15, color = {0, 0, 0, 51} },
}

local AstroonTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
    colors = {
        primary = {255, 213, 79, 255},            -- #FFD54F Gold
        primaryHover = {255, 224, 102, 255},       -- #FFE066
        primaryPressed = {240, 160, 48, 255},      -- #F0A030
        secondary = {74, 139, 245, 255},           -- #4A8BF5 Blue
        secondaryHover = {91, 156, 246, 255},      -- #5B9CF6
        secondaryPressed = {51, 102, 204, 255},    -- #3366CC
        background = {26, 17, 64, 255},            -- #1A1140 Deep cosmic
        surface = {42, 31, 94, 255},               -- #2A1F5E
        surfaceHover = {61, 42, 138, 255},         -- #3D2A8A
        text = {255, 255, 255, 255},               -- #FFFFFF
        textSecondary = {255, 255, 255, 170},      -- #FFFFFFAA
        textDisabled = {255, 255, 255, 64},        -- #FFFFFF40
        border = {255, 255, 255, 24},              -- #FFFFFF18 subtle white-alpha
        borderFocus = {74, 139, 245, 255},         -- #4A8BF5
        disabled = {61, 42, 138, 255},             -- #3D2A8A
        disabledText = {255, 255, 255, 85},        -- #FFFFFF55
        success = {46, 204, 113, 255},             -- #2ECC71
        successHover = {61, 216, 138, 255},        -- #3DD88A
        warning = {255, 217, 61, 255},             -- #FFD93D
        warningHover = {255, 224, 102, 255},       -- #FFE066
        error = {255, 71, 87, 255},                -- #FF4757
        errorHover = {255, 107, 122, 255},         -- #FF6B7A
        info = {61, 214, 232, 255},                -- #3DD6E8 Cyan
        overlay = {0, 0, 0, 180},                  -- #000000B4
    },
    radius = {
        sm = 6, md = 10, lg = 16, xl = 20, full = 9999,
    },
    componentDefaults = {
        borderRadius = 10,
    },
    components = {
        Button = {
            borderRadius = 9999, height = 48, fontSize = 13.5,
            fontWeight = "bold",                     -- Button text always bold
            glowShadow = {
                alpha = { default = 96, hover = 128 },
                blur = { default = 12, hover = 16 },
                offset = { default = {0, 4}, hover = {0, 4} },
                pressed = { color = {0, 0, 0, 64}, blur = 6, offset = {0, 2} },
            },
        },
        TextField = { borderWidth = 1.5, borderRadius = 6, bgColor = {26, 17, 64, 255} },
        Checkbox = {
            borderRadius = 4, borderWidth = 1.5,
            checkedBgColor = {74, 139, 245, 255},
            checkedBorderColor = {74, 139, 245, 255},
            checkmarkColor = {255, 255, 255, 255},
            hoverBorderColor = {74, 139, 245, 255},
        },
        Toggle = {
            borderRadius = 9999, thumbSize = 22,
            thumbColor = {255, 255, 255, 85},
            thumbCheckedColor = {255, 255, 255, 255},
            thumbHoverColor = {255, 255, 255, 170},
            trackBg = {61, 42, 138, 255},
            trackHoverBorderColor = {74, 139, 245, 255},
            trackCheckedBgColor = {46, 204, 113, 255},
            trackCheckedHoverBgColor = {61, 216, 138, 255},
        },
        Slider = {
            height = 20, borderRadius = 9999, borderWidth = 0,
            thumbBorderWidth = 0, thumbBorderRadius = 9999,
            trackBgColor = {26, 17, 64, 255},
            trackFillGradient = { direction = "to-right", from = {61, 214, 232, 255}, to = {74, 139, 245, 255} },
            thumbColor = {255, 255, 255, 255},
        },
        Card = { borderRadius = 16, boxShadow = COSMIC_SHADOW },
        Modal = {
            borderWidth = 1, boxShadow = COSMIC_SHADOW, borderRadius = 20,
            headerBorderWidth = 0,
            footerBorderWidth = 0,
            contentPadding = {16, 24, 16, 24},                   -- top=16 (below header), right/left=24, bottom=16
            contentGap = 16,
            footerPadding = {12, 24, 16, 24},                    -- top=12, right=24, bottom=16, left=24
        },
        Drawer = {
            borderWidth = 1.5, boxShadow = COSMIC_SHADOW, borderRadius = 20,
            contentPadding = {8, 6},                             -- top/bottom=8, left/right=6
            headerPadding = {14, 16},                            -- top=14, left/right=16
        },
        Menu = {
            variant = "outlined", borderWidth = 1, boxShadow = COSMIC_SHADOW, borderRadius = 10,
            itemHoverBgColor = {61, 42, 138, 255},
            itemHoverTextColor = {255, 255, 255, 255},
            itemHoverInset = 0, itemHoverRadius = 0,
            itemHoverFontWeight = "bold",                        -- hover item 600→bold
            itemVerticalInset = 0,                               -- items flush to panel edges
        },
        Dropdown = {
            height = 35, borderWidth = 1, borderRadius = 6,
            triggerBgColor = {26, 17, 64, 255},                  -- $background
            arrowColor = {255, 255, 255, 85},                    -- $textMuted
            boxShadow = { { x = 0, y = 0, blur = 8, color = {0, 0, 0, 64} } },
            hoverBorderColor = {61, 214, 232, 255},              -- $accent cyan
            openBorderColor = {61, 214, 232, 255},               -- $accent cyan
            popupBorderColor = {48, 39, 83, 255},               -- #302753 dark purple
            itemHoverBgColor = {61, 42, 138, 255},
            itemHoverTextColor = {61, 214, 232, 255},
            itemHoverInset = 0, itemHoverRadius = 0,
            itemSelectedTextColor = {61, 214, 232, 255},         -- $accent cyan (NOT gold)
            selectedFontWeight = "bold",                         -- selected item 600→bold
            itemVerticalInset = 0,                               -- items flush to popup edges
        },
        List = {
            borderWidth = 1.5, borderRadius = 10,
            itemHoverBgColor = {61, 42, 138, 255},
            itemSelectedBgColor = {61, 42, 138, 255},
            itemHoverTextColor = {61, 214, 232, 255},
            itemSelectedTextColor = {61, 214, 232, 255},
        },
        Table = {
            variant = "striped", borderWidth = 1.5, borderRadius = 10,
            headerFontWeight = "bold",                           -- header 700
            headerBgColor = {61, 42, 138, 255},
            rowOddBgColor = {28, 19, 70, 255},
            rowEvenBgColor = {38, 28, 81, 255},
            rowHoverBgColor = {74, 139, 245, 31},
        },
        Toast = {
            borderWidth = 1, boxShadow = COSMIC_SHADOW, borderRadius = 10,
            accentBarHeight = 0, accentBarWidth = 0,
            showIcon = true,
        },
        Tooltip = {
            borderWidth = 1, boxShadow = COSMIC_SHADOW, borderRadius = 8,
            tooltipBgColor = {42, 31, 94, 255},
            borderColor = {255, 255, 255, 24},
        },
        Popover = { borderWidth = 1, boxShadow = COSMIC_SHADOW, borderRadius = 10 },
        Alert = { borderWidth = 1, borderRadius = 10, borderOpacity = 0.19 },
        ProgressBar = {
            height = 10, borderWidth = 0, borderRadius = 9999,
            fillGradient = { direction = "to-right", from = {61, 214, 232, 255}, to = {74, 139, 245, 255} },
        },
        Badge = { borderRadius = 9999, fontWeight = "bold", borderWidth = 0 },
        Chip = { borderRadius = 9999, fontWeight = "bold" },
        Tabs = {
            activeFontWeight = "bold",                           -- active tab 700/600→bold
            activeBorderColor = {61, 214, 232, 255},
            activeTextColor = {255, 255, 255, 255},
            activeBgColor = {61, 42, 138, 255},
            inactiveTextColor = {255, 255, 255, 85},             -- $textMuted
            enclosedPadding = 3,
            tabGap = 3,
            variantBorderRadius = { pills = 9999, enclosed = 6 },
        },
        Accordion = {
            variant = "outlined", borderWidth = 1.5, borderRadius = 10,
            headerFontWeight = "bold",                           -- header 600→bold
            headerExpandedBgColor = {61, 42, 138, 255},
            contentBgColor = {26, 17, 64, 255},
            indicatorExpandedColor = {61, 214, 232, 255},
        },
        Timeline = {
            dotColor = {61, 214, 232, 255},
            lineColor = {61, 214, 232, 255},
            hoverTitleColor = {61, 214, 232, 255},
            titleFontWeight = "bold",                            -- title 700
            titleSize = 12,                                      -- 16px = 12pt
        },
        Breadcrumb = {
            linkColor = {61, 214, 232, 255},                     -- $accent cyan
            hoverColor = {255, 255, 255, 255},                   -- $text white
            currentColor = {255, 255, 255, 170},                 -- $textSecondary
            separatorColor = {255, 255, 255, 85},                -- $textMuted
        },
        Stepper = {
            borderWidth = 1.5, borderRadius = 9999,
            fontWeight = "bold",                                 -- step numbers always bold
            activeBgColor = {100, 76, 194, 255},
        },
        Calendar = {
            borderRadius = 9999,
            navBtnBgColor = {82, 64, 150, 255},
            navBtnRadius = 6,
            primaryColor = {61, 214, 232, 255},
            monthFontWeight = "bold",                            -- month title 700
            weekdayFontWeight = "bold",                          -- weekday labels 600→bold
            selectedFontWeight = "bold",                         -- selected day 700
            selectedBgColor = false,
            selectedBorderColor = {61, 214, 232, 255},
            selectedBorderWidth = 2,
            selectedTextColor = {61, 214, 232, 255},
            todayBorderColor = {61, 214, 232, 255},
            todayTextColor = {61, 214, 232, 255},
        },
        DatePicker = {
            borderRadius = 9999,
            popupBorderRadius = 16,
            navBtnBgColor = {82, 64, 150, 255},
            navBtnRadius = 6,
            popupBgColor = {61, 42, 138, 255},
            fieldBgColor = {33, 21, 77, 255},
            fieldBorderColor = {63, 53, 109, 255},
            fieldFontSize = 13.5,                                 -- 18px = 13.5pt
            monthFontWeight = "bold",                            -- month title 700
            weekdayFontWeight = "bold",                          -- weekday labels 600→bold
            selectedFontWeight = "bold",                         -- selected day 600→bold
            todayBtnRadius = 12,                                 -- Today button radius (≠ navBtnRadius 6)
            primaryColor = {61, 214, 232, 255},
            selectedBgColor = false,
            selectedBorderColor = {61, 214, 232, 255},
            selectedBorderWidth = 2,
            selectedTextColor = {61, 214, 232, 255},
            todayBorderColor = {61, 214, 232, 255},
            todayTextColor = {61, 214, 232, 255},
        },
        ColorPicker = {
            primaryColor = {61, 214, 232, 255},
            fieldBgColor = {33, 21, 77, 255},
            fieldBorderColor = {63, 53, 109, 255},
            fieldFontSize = 13.5,                                -- 18px = 13.5pt
            cursorWidth = 12, cursorRadius = 3,
            cursorBorderColor = {209, 213, 219, 255},
            sliderRadius = 4,                                    -- hue/alpha track radius
            presetRadius = 6,                                    -- preset swatch radius
        },
        FileUpload = {
            borderRadius = 10, borderWidth = 1.5,
            showHeader = true,
            dropzoneHeight = 116,
            dropzoneBgColor = {42, 31, 94, 255},                 -- $surface
            dropzoneBorderStyle = "solid",
            iconSize = 46,
            iconBgColor = {26, 17, 64, 255},                     -- $background
            iconColor = {74, 139, 245, 255},                      -- $secondary
            iconRadius = 12,
            labelFontWeight = "bold",                             -- 600→bold
        },
        Carousel = {
            borderRadius = 9999,                                 -- arrow btn = circle (engine clamps)
            arrowBgColor = {71, 63, 112, 255},                   -- #473F70 dark purple
            arrowHoverBgColor = {67, 54, 133, 255},              -- #433685 bluer purple
            dotColor = {255, 255, 255, 85},                      -- $textMuted
        },
        TimePicker = {
            primaryColor = {61, 214, 232, 255},
            popupBgColor = {61, 42, 138, 255},
            popupBorderRadius = 16,                              -- popup container corners
            fieldBgColor = {33, 21, 77, 255},
            fieldBorderColor = {63, 53, 109, 255},
            fieldFontSize = 13.5,                                -- 18px = 13.5pt
            selectedFontWeight = "bold",                         -- selected time 700
            selectedFontSize = 15,                               -- 20px = 15pt (larger than normal 18px)
            selectedBgColor = {255, 255, 255, 26},
            selectedTextColor = {61, 214, 232, 255},
        },
        Pagination = {
            buttonBorderWidth = 1,
            activeFontWeight = "bold",                           -- active page 700→bold
            activeBgColor = {100, 76, 194, 255},
            activeBorderColor = {100, 76, 194, 255},
            activeTextColor = {255, 255, 255, 255},
            hoverBorderColor = {61, 214, 232, 255},               -- $accent cyan
            hoverBgColor = false,                                -- no hover bg highlight, border only
        },
        Tree = {
            borderRadius = 16, borderWidth = 1.5,
            backgroundColor = {42, 31, 94, 255},                 -- $surface
            padding = 18,
            fontSize = 12,                                       -- 16px = 12pt
            iconSize = 24,
            indent = 24,
            fontWeight = "bold",                                 -- root 700, children 600 → all bold
            folderIcon = "📁",
            folderOpenIcon = "📂",
            leafIcon = "📄",
            nodeGap = 10,                                          -- item vertical spacing
            hoverBgColor = {61, 48, 125, 255},                   -- #3D307D
            hoverRadius = 8,
            selectedBgColor = {61, 42, 138, 255},                -- $surfaceHover
            iconColor = {255, 255, 255, 85},                     -- $textMuted
            selectedTextColor = {61, 214, 232, 255},              -- $accent cyan
        },
    },
})

-- ============================================================================
-- Initialize UI System
-- ============================================================================

local function initUI()
    UI.Init({
        theme = AstroonTheme,
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/Inter-Regular.ttf",
                bold = "Fonts/Inter-Bold.ttf",
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
        borderRadius = 10,
        borderWidth = 1,
        borderColor = UI.Theme.Color("border"),
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
        r:AddChild(UI.Button {
            text = "Primary", variant = "primary",
            textColor = {26, 17, 64, 255},
            backgroundGradient = { direction = 180, from = {255, 213, 79, 255}, to = {240, 160, 48, 255} },
            onClick = function() UI.Toast.Show({ message = "Primary clicked!", variant = "success" }) end,
        })
        r:AddChild(UI.Button {
            text = "Secondary", variant = "secondary",
            backgroundGradient = { direction = 180, from = {74, 139, 245, 255}, to = {51, 102, 204, 255} },
        })
        r:AddChild(UI.Button {
            text = "Danger", variant = "danger",
            backgroundGradient = { direction = 180, from = {255, 71, 87, 255}, to = {220, 53, 69, 255} },
        })
        r:AddChild(UI.Button {
            text = "Success", variant = "success",
            backgroundGradient = { direction = 180, from = {46, 204, 113, 255}, to = {29, 168, 85, 255} },
        })
        r:AddChild(UI.Button { text = "Disabled", disabled = true })

        page:AddChild(demoCard("Button", "Pill buttons with gradient fills and color-matched glow shadows", { r }))
    end

    -- Button with custom colors & shadows
    do
        local r = row({ gap = 16 })
        r:AddChild(UI.Button {
            text = "Cosmic Gradient",
            backgroundGradient = {
                type = "linear", direction = "to-right",
                from = {100, 76, 194, 255},
                to = {61, 214, 232, 255},
            },
            textColor = {255, 255, 255, 255},
            transition = "scale 0.2s easeOut",
        })
        r:AddChild(UI.Button {
            text = "Nebula Purple",
            backgroundGradient = {
                type = "linear", direction = "to-right",
                from = {168, 85, 247, 255},
                to = {100, 76, 194, 255},
            },
            textColor = {255, 255, 255, 255},
        })
        r:AddChild(UI.Button {
            text = "Cyan Glow",
            backgroundGradient = {
                type = "linear", direction = "to-bottom",
                from = {61, 214, 232, 255},
                to = {74, 139, 245, 255},
            },
            textColor = {255, 255, 255, 255},
        })

        page:AddChild(demoCard("Button Styles", "Cosmic gradients, nebula purple, cyan-to-blue glow", { r }))
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
                from = {100, 76, 194, 255},
                to = {61, 214, 232, 255},
            },
            borderRadius = 12,
        })
        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundColor = UI.Theme.Color("surface"),
            borderRadius = { 20, 4, 20, 4 },
            borderWidth = 1,
            borderColor = UI.Theme.Color("border"),
        })
        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundColor = UI.Theme.Color("surface"),
            borderRadius = 12,
            boxShadow = COSMIC_SHADOW,
        })
        r:AddChild(UI.Panel {
            width = 70, height = 70,
            backgroundColor = UI.Theme.Color("primary"),
            clipPath = "circle",
        })

        page:AddChild(demoCard("Panel", "Cosmic gradient, layered surfaces, cosmic shadow, clip-path", { r }))
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
                value = { 61, 214, 232, 255 },
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
            children = {
                UI.Label { text = "Elevated Card", fontWeight = "bold", fontSize = 14 },
                UI.Label { text = "With cosmic shadow depth.", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") },
            },
        })
        r:AddChild(UI.Card {
            width = 180,
            variant = "outlined",
            children = {
                UI.Label { text = "Outlined Card", fontWeight = "bold", fontSize = 14 },
                UI.Label { text = "Subtle white-alpha border.", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") },
            },
        })
        r:AddChild(UI.Card {
            width = 180,
            variant = "filled",
            children = {
                UI.Label { text = "Filled Card", fontWeight = "bold", fontSize = 14 },
                UI.Label { text = "Layered surface.", fontSize = 12, fontColor = UI.Theme.Color("textSecondary") },
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
        r:AddChild(UI.Avatar { initials = "A", size = "xs" })
        r:AddChild(UI.Avatar { initials = "BC", size = "sm", status = "online" })
        r:AddChild(UI.Avatar { name = "John Doe", size = "md", status = "away" })
        r:AddChild(UI.Avatar { initials = "XY", size = "lg", shape = "rounded" })
        r:AddChild(UI.Avatar { initials = "Z", size = "xl", shape = "square" })

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
                    UI.Button { text = "Hover me for tooltip", variant = "secondary",
                        backgroundGradient = { direction = 180, from = {74, 139, 245, 255}, to = {51, 102, 204, 255} },
                    },
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
                from = {61, 214, 232, 255},
                to = {74, 139, 245, 255},
            },
            height = 12,
        })

        col:AddChild(UI.ProgressBar {
            value = 0, width = "100%",
            variant = "warning",
            indeterminate = true,
        })

        page:AddChild(demoCard("ProgressBar", "Determinate with cyan-to-blue gradient, and indeterminate loading mode", { col }))
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
            },
        }))
    end

    -- Timeline (no per-item color — Astroon theme controls all dot colors uniformly via cyan)
    do
        page:AddChild(demoCard("Timeline", "Chronological event display", {
            UI.Timeline {
                items = {
                    { title = "Project Created", description = "Initial repository setup", time = "Jan 2024" },
                    { title = "Alpha Release", description = "Core features completed", time = "Jun 2024" },
                    { title = "Beta Testing", description = "Community feedback phase", time = "Dec 2024" },
                    { title = "v1.0 Release", description = "Stable release planned", time = "2025" },
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
            flexDirection = "row", gap = 12, width = "100%",
        }
        footerPanel:AddChild(UI.Button { text = "Cancel", variant = "secondary", flexGrow = 1, flexShrink = 1, flexBasis = 0,
            backgroundGradient = { direction = 180, from = {74, 139, 245, 255}, to = {51, 102, 204, 255} },
            onClick = function() footerModal:Close() end,
        })
        footerPanel:AddChild(UI.Button { text = "Confirm", variant = "primary", flexGrow = 1, flexShrink = 1, flexBasis = 0,
            textColor = {26, 17, 64, 255},
            backgroundGradient = { direction = 180, from = {255, 213, 79, 255}, to = {240, 160, 48, 255} },
            onClick = function()
                footerModal:Close()
                UI.Toast.Show({ message = "Action confirmed!", variant = "success" })
            end,
        })
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
        local interactiveFooter = UI.Panel {
            flexDirection = "row", gap = 12, width = "100%",
        }
        interactiveFooter:AddChild(UI.Button { text = "Cancel", variant = "secondary", flexGrow = 1, flexShrink = 1, flexBasis = 0,
            backgroundGradient = { direction = 180, from = {74, 139, 245, 255}, to = {51, 102, 204, 255} },
            onClick = function() interactiveModal:Close() end,
        })
        interactiveFooter:AddChild(UI.Button { text = "Save", variant = "primary", flexGrow = 1, flexShrink = 1, flexBasis = 0,
            textColor = {26, 17, 64, 255},
            backgroundGradient = { direction = 180, from = {255, 213, 79, 255}, to = {240, 160, 48, 255} },
            onClick = function()
                interactiveModal:Close()
                UI.Toast.Show({ message = "Profile saved!", variant = "success" })
            end,
        })
        interactiveModal:SetFooter(interactiveFooter)
        table.insert(overlayWidgets, interactiveModal)

        -- Delete confirm modal (manual footer, not Modal.Confirm)
        local deleteModal = UI.Modal {
            title = "Delete Item?",
            size = "md",
        }
        deleteModal:AddContent(UI.Label { text = "This cannot be undone.", fontColor = UI.Theme.Color("textSecondary") })
        local deleteFooter = UI.Panel {
            flexDirection = "row", gap = 12, width = "100%",
        }
        deleteFooter:AddChild(UI.Button { text = "Cancel", variant = "secondary", flexGrow = 1, flexShrink = 1, flexBasis = 0,
            backgroundGradient = { direction = 180, from = {74, 139, 245, 255}, to = {51, 102, 204, 255} },
            onClick = function() deleteModal:Close() end,
        })
        deleteFooter:AddChild(UI.Button { text = "Delete", variant = "primary", flexGrow = 1, flexShrink = 1, flexBasis = 0,
            textColor = {26, 17, 64, 255},
            backgroundGradient = { direction = 180, from = {255, 213, 79, 255}, to = {240, 160, 48, 255} },
            onClick = function()
                deleteModal:Close()
                UI.Toast.Show({ message = "Item deleted", variant = "error" })
            end,
        })
        deleteModal:SetFooter(deleteFooter)
        table.insert(overlayWidgets, deleteModal)

        local r = row({ gap = 8 })
        r:AddChild(UI.Button { text = "Basic Modal", variant = "secondary", onClick = function() basicModal:Open() end })
        r:AddChild(UI.Button { text = "With Footer", variant = "secondary", onClick = function() footerModal:Open() end })
        r:AddChild(UI.Button { text = "Interactive", variant = "secondary", onClick = function() interactiveModal:Open() end })
        r:AddChild(UI.Button { text = "Quick Confirm", variant = "danger",
            onClick = function() deleteModal:Open() end,
        })

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
                    text = "Astroon v1.0",
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
                    UI.Button { text = "Click for Popover", variant = "secondary",
                        backgroundGradient = { direction = 180, from = {74, 139, 245, 255}, to = {51, 102, 204, 255} },
                    },
                },
            },
        }))
    end

    -- Toast
    do
        local r = row({ gap = 8 })
        r:AddChild(UI.Button { text = "Info", variant = "primary",
            textColor = {26, 17, 64, 255},
            backgroundGradient = { direction = 180, from = {255, 213, 79, 255}, to = {240, 160, 48, 255} },
            onClick = function() UI.Toast.Show({ message = "Information message", variant = "info" }) end,
        })
        r:AddChild(UI.Button { text = "Success", variant = "success",
            backgroundGradient = { direction = 180, from = {46, 204, 113, 255}, to = {29, 168, 85, 255} },
            onClick = function() UI.Toast.Show({ message = "Operation successful!", variant = "success" }) end,
        })
        r:AddChild(UI.Button { text = "Warning",
            onClick = function() UI.Toast.Show({ message = "Warning: check your input", variant = "warning" }) end,
        })
        r:AddChild(UI.Button { text = "Error", variant = "danger",
            backgroundGradient = { direction = 180, from = {255, 71, 87, 255}, to = {220, 53, 69, 255} },
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
            {255, 213, 79, 255},     -- gold (primary)
            {46, 204, 113, 255},     -- green (success)
            {61, 214, 232, 255},     -- cyan (info/accent)
            {255, 71, 87, 255},      -- red (error)
            {168, 85, 247, 255},     -- epic purple
            {100, 76, 194, 255},     -- cosmic purple
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
            { 100, 76, 194 },    -- cosmic purple
            { 255, 213, 79 },    -- gold
            { 61, 214, 232 },    -- cyan
            { 255, 71, 87 },     -- red
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

    -- Root container — cosmic gradient background (Rule #1: never solid flat fill)
    local root = UI.Panel {
        id = "gallery-root",
        width = "100%",
        height = "100%",
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom",
            from = {26, 17, 64, 255},
            to = {45, 27, 105, 255},
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
            from = {42, 31, 94, 255},
            to = {100, 76, 194, 255},
        },
    }

    topBar:AddChild(UI.Label {
        text = "Astroon Cosmic Gallery",
        fontSize = 18,
        fontWeight = "bold",
        fontColor = {255, 213, 79, 255},
    })

    topBar:AddChild(UI.Spacer())

    -- Theme color swatches
    local swatchRow = UI.Row { gap = 6 }
    local swatchColors = { "primary", "secondary", "success", "error" }
    for _, name in ipairs(swatchColors) do
        swatchRow:AddChild(UI.Panel {
            width = 16, height = 16,
            backgroundColor = UI.Theme.Color(name),
            borderRadius = 9999,
            borderWidth = 1,
            borderColor = {255, 255, 255, 60},
        })
    end
    topBar:AddChild(swatchRow)

    topBar:AddChild(UI.Label {
        text = "v" .. UI.VERSION,
        fontSize = 12,
        fontColor = {255, 255, 255, 120},
    })

    root:AddChild(topBar)

    -- ── Body: Sidebar + Content ─────────────────────────────────────────────

    local body = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexDirection = "row",
    }

    -- Sidebar nav tabs (vertical pills)
    local sidebarTabs = UI.Tabs {
        tabs = {},
        variant = "pills",
        orientation = "vertical",
        tabWidth = 100,
        width = 100,
        height = "100%",
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
        borderTopWidth = 1,
        borderTopColor = UI.Theme.Color("border"),
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
