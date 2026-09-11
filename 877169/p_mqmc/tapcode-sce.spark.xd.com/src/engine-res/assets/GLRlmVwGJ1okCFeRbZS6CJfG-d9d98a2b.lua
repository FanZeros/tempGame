-- ============================================================================
-- UrhoX UI Gallery — BrawlForge Sci-Fi HUD Style
-- Sharp-edged dark-blue combat HUD theme with neon accents
-- All colors via BrawlForge Theme, zero-blur shadows, borderRadius=0
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- BrawlForge Theme Setup
-- ============================================================================

-- BrawlForge HUD shadow: sharp drop, zero blur
local HUD_SHADOW = {
    { x = 6, y = 6, blur = 0, color = {0, 0, 0, 64} },
}

-- Button shadow: .pen offset (10,10) from inner frame, minus border overhang (right=4,bottom=4)
local BTN_SHADOW = {
    { x = 6, y = 6, blur = 0, color = {0, 0, 0, 51} },
}

-- Toast shadow
local TOAST_SHADOW = {
    { x = 8, y = 8, blur = 0, color = {0, 0, 0, 64} },
}

local function initUI()
    local BrawlForgeTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        colors = {
            -- Primary: bright cyan-blue
            primary = {31, 162, 255, 255},
            primaryHover = {70, 183, 255, 255},
            primaryPressed = {13, 126, 230, 255},

            -- Secondary: vivid purple
            secondary = {214, 53, 255, 255},
            secondaryHover = {224, 97, 255, 255},
            secondaryPressed = {181, 35, 232, 255},

            -- Background: deep blue layers
            background = {34, 89, 183, 255},
            surface = {33, 69, 138, 255},
            surfaceHover = {45, 102, 200, 255},

            -- Text
            text = {255, 255, 255, 255},
            textSecondary = {213, 226, 255, 255},
            textDisabled = {157, 166, 198, 255},

            -- Border
            border = {10, 16, 32, 255},
            borderFocus = {111, 231, 255, 255},

            -- Disabled
            disabled = {57, 71, 107, 255},
            disabledText = {139, 150, 184, 255},

            -- Semantic
            success = {67, 213, 44, 255},
            successHover = {98, 232, 78, 255},
            warning = {255, 198, 26, 255},
            warningHover = {255, 215, 85, 255},
            error = {245, 50, 45, 255},
            errorHover = {255, 90, 71, 255},
            info = {70, 199, 255, 255},

            -- Overlay
            overlay = {7, 16, 28, 187},

            -- Hover
            hover = {255, 255, 255, 25},
        },
        radius = {
            none = 0,
            sm = 4,
            md = 6,
            lg = 10,
            xl = 14,
            full = 9999,
        },
        componentDefaults = {
            borderRadius = 0,
            fontWeight = "bold",
        },
        components = {
            Button = {
                borderWidth = {2, 4, 4, 2},
                borderRadius = 0, fontWeight = "bold",
                height = 50, fontSize = 15,
                padding = {4, 6, 10, 4},
                boxShadow = BTN_SHADOW,
                decorations = {
                    primary = {
                        { position = "absolute", top = 2, left = 2, right = 4, bottom = 4,
                          borderWidth = {2, 2, 6, 2}, borderColor = {27, 115, 227, 255},
                          hoverBorderColor = {43, 143, 240, 255},
                          pressedBorderColor = {8, 79, 146, 255} },
                    },
                    secondary = {
                        { position = "absolute", top = 2, left = 2, right = 4, bottom = 4,
                          borderWidth = {2, 2, 6, 2}, borderColor = {142, 45, 226, 255},
                          hoverBorderColor = {163, 71, 244, 255},
                          pressedBorderColor = {101, 16, 171, 255} },
                    },
                    danger = {
                        { position = "absolute", top = 2, left = 2, right = 4, bottom = 4,
                          borderWidth = {2, 2, 6, 2}, borderColor = {169, 27, 23, 255},
                          hoverBorderColor = {196, 42, 38, 255},
                          pressedBorderColor = {132, 17, 14, 255} },
                    },
                    success = {
                        { position = "absolute", top = 2, left = 2, right = 4, bottom = 4,
                          borderWidth = {2, 2, 6, 2}, borderColor = {35, 116, 24, 255},
                          hoverBorderColor = {53, 181, 33, 255},
                          pressedBorderColor = {22, 111, 9, 255} },
                    },
                },
            },
            TextField = { borderWidth = 3, borderRadius = 0, fontWeight = "bold" },
            Checkbox = {
                borderWidth = 3, borderRadius = 0,
                checkedBgColor = {31, 162, 255, 255},
                checkedBorderColor = {10, 100, 183, 255},
                hoverBorderColor = {31, 162, 255, 255},
                checkmarkColor = {255, 255, 255, 255},
            },
            Toggle = {
                borderWidth = 3, borderRadius = 0,
                thumbColor = {213, 226, 255, 255},
                thumbCheckedColor = {255, 255, 255, 255},
                thumbHoverColor = {255, 255, 255, 255},
                trackBg = {33, 69, 138, 255},
                trackBorderColor = {10, 16, 32, 255},
                trackHoverBgColor = {45, 102, 200, 255},
                trackHoverBorderColor = {31, 162, 255, 255},
                trackCheckedBgColor = {31, 162, 255, 255},
                trackCheckedBorderColor = {10, 100, 183, 255},
                trackCheckedHoverBgColor = {70, 183, 255, 255},
            },
            Slider = {
                borderRadius = 0, trackHeight = 4,
                trackBgColor = {33, 69, 138, 255},
                trackFillColor = {31, 162, 255, 255},
                thumbColor = {31, 162, 255, 255},
                thumbSize = 18,
                thumbBorderWidth = 3,
                thumbBorderColor = {10, 100, 183, 255},
                thumbBorderRadius = 0,
            },
            FileUpload = {
                showHeader = false,
                dropzoneHeight = 104,
                dropzoneBgColor = {18, 63, 127, 255},
                dropzoneBorderStyle = "solid",
                iconSize = 28,
                iconColor = {63, 169, 255, 255},
                labelFontWeight = "bold",
            },
            Card = {
                borderWidth = 2, borderRadius = 0,
                boxShadow = { { x = 4, y = 4, blur = 0, color = {0, 0, 0, 64} } },
            },
            Badge = { borderWidth = 2, borderRadius = 0 },
            Alert = { borderWidth = 3, borderRadius = 0 },
            Chip = { borderWidth = 3, borderRadius = 0 },
            Avatar = { showBorder = true },
            ProgressBar = { borderRadius = 0, height = 8 },
            Tabs = {
                borderWidth = 3, borderRadius = 0,
                lineBorderWidth = 3,
                lineBorderColor = {0, 0, 0, 255},
                activeBorderColor = {30, 163, 255, 255},
                activeBgColor = {30, 163, 255, 255},
                inactiveTextColor = {213, 226, 255, 255},
                pillMargin = 0,
                variantTabGap = {
                    pills = 8,
                },
                variantTabHeight = { line = 40, pills = 36, enclosed = 44 },
                variantBorderRadius = { pills = 0, enclosed = 0 },
                variantActiveBorderColor = { pills = {10, 100, 183, 255} },
                variantActiveBgColor = { enclosed = {30, 163, 255, 255} },
                variantBoxShadow = { enclosed = { { x = 0, y = 0, blur = 0, color = {12, 100, 184, 255} } } },
                enclosedPadding = 0,
                tabGap = 0,
            },
            Menu = {
                variant = "outlined",
                borderWidth = 3, borderRadius = 0,
                boxShadow = HUD_SHADOW,
                itemHoverBgColor = {31, 84, 190, 255},
                itemHoverTextColor = {31, 162, 255, 255},
                itemHoverInset = 0,
                itemHoverRadius = 0,
                itemVerticalInset = 0,
            },
            Stepper = {
                borderWidth = 3, borderRadius = 0,
                stepBorderWidth = 3,
                hoverBorderColor = {31, 162, 255, 255},
                activeBgColor = {31, 162, 255, 255},
            },
            Breadcrumb = {
                linkColor = {31, 162, 255, 255},
                hoverColor = {70, 183, 255, 255},
                currentColor = {255, 255, 255, 255},
                separatorColor = {213, 226, 255, 255},
            },
            Pagination = {
                variant = "outlined",
                buttonBorderWidth = 2,
                borderRadius = 0,
                activeBgColor = {31, 162, 255, 255},
                activeBorderColor = {10, 100, 183, 255},
                activeTextColor = {255, 255, 255, 255},
                hoverBgColor = {45, 102, 200, 255},
            },
            Carousel = {
                borderWidth = 3, borderRadius = 0,
                arrowBgColor = {33, 69, 139, 255},
                arrowHoverBgColor = {31, 84, 190, 255},
                arrowBorderWidth = 0,
                dotColor = {114, 119, 132, 255},
            },
            Toast = {
                borderWidth = 2, borderRadius = 0,
                boxShadow = TOAST_SHADOW,
                accentBarWidth = 4,
                accentBarHeight = 32,
                accentBarInset = 12,
                showIcon = false,
            },
            Tooltip = {
                borderWidth = 2, borderRadius = 0,
                boxShadow = HUD_SHADOW,
                tooltipBgColor = {254, 160, 2, 255},
                borderColor = {249, 95, 3, 255},
            },
            Popover = {
                borderWidth = 2, borderRadius = 0,
                boxShadow = HUD_SHADOW,
            },
            Modal = {
                borderWidth = 3, borderRadius = 0,
                boxShadow = HUD_SHADOW,
                headerBgColor = {14, 137, 255, 255},
                contentBgColor = {33, 69, 139, 255},
                headerBorderWidth = 5,
                footerBorderWidth = 0,
                headerFullWidthBorder = true,
            },
            Drawer = {
                borderWidth = 3, borderRadius = 0,
                boxShadow = HUD_SHADOW,
                contentPadding = 12,
                headerPadding = {0, 16},
            },
            Dropdown = {
                borderWidth = 2, borderRadius = 0,
                boxShadow = { { x = 8, y = 8, blur = 0, color = {0, 0, 0, 64} } },
                triggerBgColor = {33, 69, 138, 255},
                arrowColor = {31, 162, 255, 255},
                openBorderColor = {30, 163, 255, 255},
                itemHoverBgColor = {12, 44, 109, 255},
                itemHoverInset = 0,
                itemHoverRadius = 0,
                itemVerticalInset = 0,
            },
            Table = {
                variant = "striped", borderWidth = 3, borderRadius = 0,
                headerBgColor = {14, 137, 255, 255},
                headerFontWeight = "bold",
                headerBorderWidth = 5,
                rowOddBgColor = {11, 44, 109, 255},
                rowEvenBgColor = {32, 69, 141, 255},
                rowHoverBgColor = {20, 64, 153, 255},
            },
            List = {
                borderWidth = 3, borderRadius = 0,
                itemBgColor = {248, 210, 39, 255},
                itemTextColor = {0, 0, 0, 255},
                itemSelectedBgColor = {255, 146, 3, 255},
                itemSelectedTextColor = {255, 255, 255, 255},
                itemHoverBgColor = {255, 212, 46, 255},
                itemHoverTextColor = {0, 0, 0, 255},
            },
            Accordion = {
                variant = "default", borderWidth = 3, borderRadius = 0,
                headerExpandedBgColor = {157, 0, 198, 255},
                collapsedTextColor = {213, 226, 255, 255},
                contentBgColor = {30, 40, 57, 255},
                bgColor = {74, 38, 82, 255},
                headerFontWeight = "bold",
            },
            Rating = { borderRadius = 0 },
            DatePicker = {
                borderWidth = 2, borderRadius = 0,
                fieldBorderRadius = 0,
                fieldBorderColor = {10, 16, 32, 255},
                fieldBgColor = {33, 69, 138, 255},
                primaryColor = {31, 162, 255, 255},
                popupBgColor = {47, 52, 80, 242},
                popupBorderRadius = 0,
                navBtnBgColor = {31, 162, 255, 255},
                navBtnRadius = 0,
                todayBtnRadius = 0, todayBtnHeight = 30,
                todayBtnBgColor = {45, 102, 200, 255},
                todayBtnBorderColor = {31, 162, 255, 255},
                todayBtnBorderWidth = 2,
                todayBtnTextColor = {213, 226, 255, 255},
                monthFontWeight = "bold",
                weekdayFontWeight = "bold",
            },
            TimePicker = {
                borderWidth = 2, borderRadius = 0,
                fieldBorderRadius = 0,
                fieldBorderColor = {10, 16, 32, 255},
                fieldBgColor = {33, 69, 138, 255},
                primaryColor = {31, 162, 255, 255},
                popupBgColor = {47, 52, 80, 242},
                selectedBgColor = {31, 162, 255, 255},
            },
            Calendar = {
                borderWidth = 3, borderRadius = 0,
                primaryColor = {31, 162, 255, 255},
                selectedBgColor = {31, 162, 255, 255},
                navBtnBgColor = {31, 162, 255, 255},
                navBtnRadius = 0,
                monthFontWeight = "bold",
                weekdayFontWeight = "bold",
            },
            ColorPicker = {
                borderWidth = 2, borderRadius = 0,
                fieldBorderRadius = 0,
                fieldBorderColor = {10, 16, 32, 255},
                fieldBgColor = {33, 69, 138, 255},
                primaryColor = {31, 162, 255, 255},
                sliderRadius = 4,
                sliderBorderWidth = 2,
                presetRadius = 0,
                cursorWidth = 18,
                cursorHeight = 24,
                cursorRadius = 0,
                cursorBorderWidth = 3,
                cursorBorderColor = {10, 100, 183, 255},
            },
            Timeline = {
                borderRadius = 0,
                hoverTitleColor = {252, 211, 28, 255},
                titleFontWeight = "bold",
            },
            Tree = {
                borderRadius = 0,
                backgroundColor = {21, 59, 135, 255},
                padding = 16,
                nodeGap = 10,
                hoverBgColor = {38, 81, 166, 255},
                hoverRadius = 0,
                iconColor = {191, 197, 208, 255},
            },
        },
    })

    UI.Init({
        theme = BrawlForgeTheme,
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/NotoSansSC-Black.ttf",
                bold = "Fonts/NotoSansSC-Black.ttf",
            }}
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
-- Helper: Demo Card — BrawlForge sharp panel with black border
-- ============================================================================

local function demoCard(title, description, contentChildren, opts)
    opts = opts or {}
    local card = UI.Panel {
        width = "100%",
        padding = 16,
        gap = 10,
        borderRadius = 0,
        borderWidth = 2,
        borderColor = {10, 16, 32, 255},
        backgroundColor = "#2f333eff",
        marginBottom = 4,
        overflow = opts.overflow,
        boxShadow = { { x = 4, y = 4, blur = 0, color = {0, 0, 0, 64} } },
    }

    card:AddChild(UI.Label {
        text = title,
        fontWeight = "bold",
        fontSize = 15,
        fontColor = {255, 255, 255, 255},
    })

    if description then
        card:AddChild(UI.Label {
            text = description,
            fontSize = 12,
            fontColor = {213, 226, 255, 255},
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
        r:AddChild(UI.Button { text = "PRIMARY", variant = "primary", onClick = function() UI.Toast.Show({ message = "Primary clicked!", variant = "success" }) end })
        r:AddChild(UI.Button { text = "SECONDARY", variant = "secondary" })
        r:AddChild(UI.Button { text = "DANGER", variant = "danger" })
        r:AddChild(UI.Button { text = "SUCCESS", variant = "success" })
        r:AddChild(UI.Button { text = "DISABLED", disabled = true })

        page:AddChild(demoCard("Button", "Interactive buttons with variant styles and bottom accent bars", { r }))
    end

    -- Button with gradient (only override that makes sense per-instance)
    do
        local r = row({ gap = 16 })
        r:AddChild(UI.Button {
            text = "GRADIENT",
            backgroundGradient = {
                type = "linear", direction = "to-right",
                from = {31, 162, 255, 255},
                to = {214, 53, 255, 255},
            },
            textColor = {255, 255, 255, 255},
        })
        r:AddChild(UI.Button { text = "SECONDARY", variant = "secondary" })
        r:AddChild(UI.Button { text = "DANGER", variant = "danger" })

        page:AddChild(demoCard("Button Styles", "Gradient override and variant accent bars", { r }))
    end

    -- Label text features
    do
        local col = UI.Panel { width = "100%", gap = 8 }
        col:AddChild(UI.Label {
            text = "BOLD TITLE",
            fontSize = 20,
            fontWeight = "bold",
            fontColor = {255, 255, 255, 255},
        })
        col:AddChild(UI.Label {
            text = "TACTICAL READOUT",
            fontSize = 13,
            textTransform = "uppercase",
            letterSpacing = 3,
            fontColor = {31, 162, 255, 255},
        })
        col:AddChild(UI.Label {
            text = "Underline decoration & secondary color",
            fontSize = 13,
            textDecoration = "underline",
            fontColor = {213, 226, 255, 255},
        })
        col:AddChild(UI.Label {
            text = "Multiline wrapping text: The BrawlForge HUD system delivers angular, bold, battle-ready interfaces. Every panel is stamped metal with zero-blur shadows.",
            fontSize = 13,
            whiteSpace = "normal",
            lineHeight = 1.5,
            fontColor = {255, 255, 255, 255},
        })

        page:AddChild(demoCard("Label", "Typography: bold weight, uppercase transform, neon accents", { col }))
    end

    -- Panel visual features — BrawlForge style
    do
        local r = row({ gap = 14 })

        -- Cyan-to-purple gradient, sharp edges
        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundGradient = {
                type = "linear", direction = "to-bottom-right",
                from = {31, 162, 255, 255},
                to = {214, 53, 255, 255},
            },
            borderRadius = 0,
        })
        -- Asymmetric accent border
        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundColor = {33, 69, 138, 255},
            borderRadius = 0,
            borderWidth = 2,
            borderColor = {31, 162, 255, 255},
        })
        -- Zero-blur HUD shadow
        r:AddChild(UI.Panel {
            width = 100, height = 70,
            backgroundColor = {33, 69, 138, 255},
            borderRadius = 0,
            borderWidth = 2,
            borderColor = {10, 16, 32, 255},
            boxShadow = {
                { x = 6, y = 6, blur = 0, color = {0, 0, 0, 64} },
            },
        })
        -- Clipped circle on blue surface
        r:AddChild(UI.Panel {
            width = 70, height = 70,
            backgroundColor = {31, 162, 255, 255},
            clipPath = "circle",
        })

        page:AddChild(demoCard("Panel", "Gradients, sharp edges, zero-blur shadows, clip-path", { r }))
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
        local statusLabel = UI.Label { text = "Type something...", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
        local statusLabel = UI.Label { text = "Checkbox: false | Toggle: true", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
        local statusLabel = UI.Label { text = "Value: 50", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
        local statusLabel = UI.Label { text = "Active step: 1", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
        local statusLabel = UI.Label { text = "Rating: 3 / 5", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
        local statusLabel = UI.Label { text = "Selected: none", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
                value = {31, 162, 255, 255},
                onChange = function(_, color) end,
            },
        }))
    end

    -- Calendar
    do
        local statusLabel = UI.Label { text = "No date selected", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
                UI.Label { text = "Sharp HUD panel.", fontSize = 12, fontColor = {213, 226, 255, 255} },
            },
        })
        r:AddChild(UI.Card {
            width = 180,
            variant = "outlined",
            children = {
                UI.Label { text = "Outlined Card", fontWeight = "bold", fontSize = 14 },
                UI.Label { text = "Black border frame.", fontSize = 12, fontColor = {213, 226, 255, 255} },
            },
        })
        r:AddChild(UI.Card {
            width = 180,
            variant = "filled",
            children = {
                UI.Label { text = "Filled Card", fontWeight = "bold", fontSize = 14 },
                UI.Label { text = "Surface blue.", fontSize = 12, fontColor = {213, 226, 255, 255} },
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
        col:AddChild(UI.Alert { severity = "info", title = "Info", message = "Tactical data incoming." })
        col:AddChild(UI.Alert { severity = "success", title = "Success", message = "Mission objective completed." })
        col:AddChild(UI.Alert { severity = "warning", title = "Warning", message = "Shield integrity low." })
        col:AddChild(UI.Alert { severity = "error", title = "Error", message = "System breach detected.", closable = true })

        page:AddChild(demoCard("Alert", "Notification banners with severity levels", { col }))
    end

    -- Tooltip
    do
        page:AddChild(demoCard("Tooltip", "Hover to reveal contextual information (gold/orange style)", {
            UI.Tooltip {
                content = "This is a helpful tooltip!",
                position = "top",
                children = {
                    UI.Button { text = "HOVER ME", variant = "secondary" },
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
                UI.Skeleton { variant = "rectangular", width = 180, height = 40, borderRadius = 0 },
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

        -- HUD bar style: cyan-to-purple gradient
        col:AddChild(UI.ProgressBar {
            value = 0.65, width = "100%",
            fillGradient = {
                direction = "to-right",
                from = {31, 162, 255, 255},
                to = {214, 53, 255, 255},
            },
            borderRadius = 0,
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
        local statusLabel = UI.Label { text = "Page: 3", fontSize = 12, fontColor = {213, 226, 255, 255} }
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
        page:AddChild(demoCard("Accordion", "Expandable content sections (purple header when expanded)", {
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

    -- Timeline
    do
        page:AddChild(demoCard("Timeline", "Chronological event display", {
            UI.Timeline {
                items = {
                    { title = "Recon Phase", description = "Initial scan complete", time = "00:00", color = "success" },
                    { title = "Deployment", description = "Forces mobilized", time = "01:30", color = "primary" },
                    { title = "Engagement", description = "Contact established", time = "03:45", color = "warning" },
                    { title = "Extraction", description = "Mission wrap-up", time = "06:00", color = "error" },
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
            title = "INCOMING TRANSMISSION",
            size = "md",
        }
        basicModal:AddContent(UI.Label { text = "This is a basic modal dialog." })
        basicModal:AddContent(UI.Label { text = "It supports title, content, and footer sections." })
        table.insert(overlayWidgets, basicModal)

        -- Modal with footer
        local footerModal = UI.Modal {
            title = "CONFIRM ACTION",
            size = "md",
        }
        footerModal:AddContent(UI.Label { text = "Are you sure you want to proceed?" })
        footerModal:AddContent(UI.Label { text = "This action may have consequences.", fontColor = {213, 226, 255, 255} })
        local footerPanel = UI.Panel {
            flexDirection = "row", justifyContent = "flex-end", gap = 8, width = "100%",
        }
        footerPanel:AddChild(UI.Button { text = "CANCEL", variant = "secondary", onClick = function() footerModal:Close() end })
        footerPanel:AddChild(UI.Button { text = "CONFIRM", variant = "primary", onClick = function()
            footerModal:Close()
            UI.Toast.Show({ message = "Action confirmed!", variant = "success" })
        end })
        footerModal:SetFooter(footerPanel)
        table.insert(overlayWidgets, footerModal)

        -- Interactive modal
        local interactiveModal = UI.Modal {
            title = "EDIT PROFILE",
            size = "lg",
        }
        interactiveModal:AddContent(UI.TextField { placeholder = "Your callsign...", width = "100%" })
        interactiveModal:AddContent(UI.TextField { placeholder = "Comm channel...", width = "100%" })
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
        r:AddChild(UI.Button { text = "BASIC MODAL", onClick = function() basicModal:Open() end })
        r:AddChild(UI.Button { text = "WITH FOOTER", onClick = function() footerModal:Open() end })
        r:AddChild(UI.Button { text = "INTERACTIVE", onClick = function() interactiveModal:Open() end })
        r:AddChild(UI.Button { text = "QUICK CONFIRM", variant = "danger", onClick = function()
            local m = UI.Modal.Confirm {
                title = "DELETE ITEM?",
                message = "This cannot be undone.",
                confirmText = "DELETE",
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
                    fontColor = {213, 226, 255, 255},
                    paddingHorizontal = 12,
                },
            },
        }

        local drawer = UI.Drawer {
            position = "left",
            size = 280,
            header = "COMMAND CENTER",
            showCloseButton = true,
            content = drawerContent,
        }
        table.insert(overlayWidgets, drawer)

        page:AddChild(demoCard("Drawer", "Sliding side panel from screen edge", {
            UI.Button { text = "OPEN DRAWER", onClick = function() drawer:Open() end },
        }))
    end

    -- Popover
    do
        page:AddChild(demoCard("Popover", "Floating content anchored to an element", {
            UI.Popover {
                content = "This popover floats above the button.\nIt can contain any content.",
                placement = "bottom",
                trigger = "click",
                title = "Intel Report",
                children = {
                    UI.Button { text = "CLICK FOR POPOVER", variant = "secondary" },
                },
            },
        }))
    end

    -- Toast
    do
        local r = row({ gap = 8 })
        r:AddChild(UI.Button { text = "INFO", variant = "primary",
            onClick = function() UI.Toast.Show({ message = "Information message", variant = "info" }) end,
        })
        r:AddChild(UI.Button { text = "SUCCESS", variant = "success",
            onClick = function() UI.Toast.Show({ message = "Operation successful!", variant = "success" }) end,
        })
        r:AddChild(UI.Button { text = "WARNING",
            onClick = function() UI.Toast.Show({ message = "Warning: check your input", variant = "warning" }) end,
        })
        r:AddChild(UI.Button { text = "ERROR", variant = "danger",
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

    -- SimpleGrid — BrawlForge rarity colors
    do
        local gridChildren = {}
        local gridColors = {
            {31, 162, 255, 255},     -- primary (cyan-blue)
            {67, 213, 44, 255},      -- success (green)
            {255, 198, 26, 255},     -- warning (gold)
            {245, 50, 45, 255},      -- error (red)
            {214, 53, 255, 255},     -- secondary (purple)
            {61, 214, 232, 255},     -- accent (cyan)
        }
        for i = 1, 6 do
            local c = gridColors[i]
            table.insert(gridChildren, UI.Panel {
                height = 60,
                backgroundColor = { c[1], c[2], c[3], 200 },
                borderRadius = 0,
                borderWidth = 2,
                borderColor = {10, 16, 32, 255},
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "ITEM " .. i, fontColor = {255, 255, 255, 255}, fontSize = 13, fontWeight = "bold" },
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

    -- Carousel — BrawlForge colors
    do
        local carouselColors = {
            {31, 162, 255},    -- primary
            {245, 50, 45},    -- error/danger
            {67, 213, 44},    -- success
            {214, 53, 255},   -- secondary/purple
        }
        local carouselItems = {}
        for i, c in ipairs(carouselColors) do
            table.insert(carouselItems, {
                content = "SLIDE " .. i,
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

    -- Root container — deep blue background
    local root = UI.Panel {
        id = "gallery-root",
        width = "100%",
        height = "100%",
        backgroundColor = {34, 89, 183, 255},
    }

    -- ── Top Bar — BrawlForge HUD header ────────────────────────────────────

    local topBar = UI.Panel {
        width = "100%",
        height = 56,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 20,
        gap = 12,
        backgroundColor = {14, 137, 255, 255},
        borderBottomWidth = 5,
        borderBottomColor = {10, 100, 183, 255},
        boxShadow = { { x = 0, y = 6, blur = 0, color = {0, 0, 0, 64} } },
    }

    topBar:AddChild(UI.Label {
        text = "BRAWLFORGE UI GALLERY",
        fontSize = 18,
        fontWeight = "bold",
        fontColor = {255, 255, 255, 255},
        letterSpacing = 2,
    })

    topBar:AddChild(UI.Spacer())

    -- Theme color swatches — BrawlForge palette
    local swatchRow = UI.Row { gap = 6 }
    local swatchColors = {
        {31, 162, 255, 255},   -- primary
        {214, 53, 255, 255},   -- secondary
        {67, 213, 44, 255},    -- success
        {245, 50, 45, 255},    -- error
    }
    for _, c in ipairs(swatchColors) do
        swatchRow:AddChild(UI.Panel {
            width = 16, height = 16,
            backgroundColor = c,
            borderRadius = 0,
            borderWidth = 2,
            borderColor = {10, 16, 32, 255},
        })
    end
    topBar:AddChild(swatchRow)

    topBar:AddChild(UI.Label {
        text = "v" .. UI.VERSION,
        fontSize = 12,
        fontColor = {213, 226, 255, 255},
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

    -- ── Footer — BrawlForge stamped bar ─────────────────────────────────────

    local footer = UI.Panel {
        width = "100%",
        height = 32,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 6,
        borderTopWidth = 2,
        borderTopColor = {10, 16, 32, 255},
        backgroundColor = {33, 69, 138, 255},
    }

    footer:AddChild(UI.Label {
        text = "UrhoX UI v" .. UI.VERSION,
        fontSize = 11,
        fontColor = {213, 226, 255, 255},
    })

    footer:AddChild(UI.Label {
        text = " | ",
        fontSize = 11,
        fontColor = {10, 16, 32, 255},
    })

    footer:AddChild(UI.Label {
        text = "42 Widgets",
        fontSize = 11,
        fontColor = {213, 226, 255, 255},
    })

    footer:AddChild(UI.Label {
        text = " | ",
        fontSize = 11,
        fontColor = {10, 16, 32, 255},
    })

    footer:AddChild(UI.Label {
        text = "BrawlForge HUD",
        fontSize = 11,
        fontColor = {111, 231, 255, 255},
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
