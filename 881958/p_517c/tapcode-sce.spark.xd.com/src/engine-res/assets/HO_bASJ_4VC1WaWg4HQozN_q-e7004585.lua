-- ============================================================================
-- Default Dark Theme — Micro-Volume Dark Style
-- Steel cyan primary, deep navy background, bottom-stroke depth effect
-- ============================================================================

local Theme = require("urhox-libs/UI/Core/Theme")

-- Depth shadow (cards, modals, elevated panels)
local DEPTH_SHADOW = {
  { x = 0, y = 0, blur = 14, color = {0, 0, 0, 51} },
}

-- Toast shadow (lighter)
local TOAST_SHADOW = {
  { x = 0, y = 0, blur = 4, color = {0, 0, 0, 64} },
}

return Theme.ExtendTheme(Theme.defaultTheme, {
  fonts = {
    { family = "sans", weights = {
      normal = "Fonts/NotoSansSC-Regular.ttf",
      bold = "Fonts/NotoSansSC-Bold.ttf",
    }},
  },
  colors = {
    primary = {88, 196, 246, 255},              -- #58C4F6 Steel cyan
    primaryHover = {116, 212, 255, 255},         -- #74D4FF
    primaryPressed = {58, 167, 220, 255},        -- #3AA7DC
    primaryDeep = {33, 123, 168, 255},           -- #217BA8
    primarySoft = {79, 136, 193, 255},           -- #4F88C1
    primaryShadow = {33, 123, 168, 255},         -- #217BA8 Button depth shadow
    secondary = {69, 100, 127, 255},             -- #45647F
    secondaryHover = {85, 120, 148, 255},        -- #557894
    secondaryPressed = {51, 75, 97, 255},        -- #334B61
    secondaryDeep = {38, 58, 77, 255},           -- #263A4D
    secondaryShadow = {38, 58, 77, 255},         -- #263A4D Button depth shadow
    background = {11, 22, 33, 255},              -- #0B1621 Deep navy
    surface = {21, 35, 49, 255},                 -- #152331
    surfaceAlt = {28, 43, 58, 255},              -- #1C2B3A
    surfaceRaised = {44, 49, 65, 255},           -- #2C3141
    text = {244, 246, 251, 255},                 -- #F4F6FB
    textSecondary = {178, 184, 199, 255},        -- #B2B8C7
    textMuted = {138, 146, 166, 255},            -- #8A92A6
    textPlaceholder = {159, 176, 191, 255},      -- #9FB0BF
    textInverse = {255, 255, 255, 255},          -- #FFFFFF
    border = {49, 69, 85, 255},                  -- #314555
    borderStrong = {66, 88, 106, 255},           -- #42586A
    borderFocus = {88, 196, 246, 255},           -- #58C4F6 (= primary)
    divider = {49, 69, 85, 255},                 -- #314555
    disabled = {75, 86, 97, 255},                -- #4B5661
    disabledBorder = {89, 101, 115, 255},        -- #596573
    disabledText = {126, 135, 148, 255},         -- #7E8794
    success = {48, 199, 138, 255},               -- #30C78A
    successHover = {69, 217, 157, 255},          -- #45D99D
    successPressed = {32, 155, 108, 255},        -- #209B6C
    successShadow = {32, 155, 108, 255},         -- #209B6C Button depth shadow
    warning = {244, 200, 74, 255},               -- #F4C84A
    warningPressed = {169, 121, 24, 255},        -- #A97918
    error = {232, 93, 91, 255},                  -- #E85D5B
    errorHover = {255, 118, 115, 255},           -- #FF7673
    errorPressed = {179, 64, 66, 255},           -- #B34042
    errorShadow = {179, 64, 66, 255},            -- #B34042 Button depth shadow
    danger = {232, 93, 91, 255},                 -- #E85D5B
    dangerHover = {255, 118, 115, 255},          -- #FF7673
    dangerPressed = {179, 64, 66, 255},          -- #B34042
    overlay = {0, 0, 0, 180},                    -- #000000B4
    -- Soft backgrounds for alerts
    infoSoft = {16, 43, 63, 255},                -- #102B3F
    successSoft = {16, 43, 42, 255},             -- #102B2A
    warningSoft = {47, 41, 21, 255},             -- #2F2915
    dangerSoft = {44, 29, 34, 255},              -- #2C1D22
    -- Tooltip/popover specific
    surfaceTooltip = {47, 54, 67, 255},          -- #2F3643
    borderTooltip = {61, 67, 86, 255},           -- #3D4356
  },
  radius = {
    xs = 2,
    sm = 8,
    md = 12,
    lg = 16,
    full = 999,
  },
  componentDefaults = {
    borderRadius = 12,
  },
  components = {
    Button = {
      borderRadius = 12,
      height = 48,
      fontSize = 15,
      fontWeight = "bold",
      -- Depth = black 30% bottom inner glow shadow (3px) + padding (text up); collapses on press
      borderWidth = 0,
      glowShadow = {
        color = {0, 0, 0, 77},
        alpha = { default = 77, hover = 77 },
        blur = { default = 0, hover = 0 },
        offset = { default = {0, 3}, hover = {0, 3} },
        inset = true,
        side = "bottom",
        curve = "microVolume",
        pressed = { color = {0, 0, 0, 0}, blur = 0, offset = {0, 0}, inset = true, side = "bottom" },
      },
      pressedBorderWidth = 0,                     -- press: shadow disappears (flatten)
      padding = {0, 0, 4, 0},                    -- pen padding: bottom 4px keeps text on the "plate"
      pressedPadding = 0,                         -- press: text recenters
    },
    TextField = {
      borderWidth = 2, borderRadius = 8,
      height = 40,
      fontSize = 9.75,
      disabledBorderColor = {89, 101, 115, 255},
    },
    Checkbox = {
      borderRadius = 8, borderWidth = 2, size = 22,
      checkedBgColor = {88, 196, 246, 255},
      checkedBorderColor = {88, 196, 246, 255},
      uncheckedBorderColor = {66, 88, 106, 255},
      checkmarkColor = {255, 255, 255, 255},
    },
    Toggle = {
      borderRadius = 999, borderWidth = 2,
      trackWidth = 48, trackHeight = 28, thumbSize = 20,
      thumbColor = {244, 246, 251, 255},
      thumbCheckedColor = {244, 246, 251, 255},
      trackBg = {75, 86, 97, 255},
      trackBorderColor = {89, 101, 115, 255},
      trackHoverBgColor = {89, 101, 115, 255},
      trackHoverBorderColor = {89, 101, 115, 255},
      trackCheckedBgColor = {88, 196, 246, 255},
      trackCheckedBorderColor = {88, 196, 246, 255},
      trackCheckedHoverBgColor = {116, 212, 255, 255},
      trackCheckedHoverBorderColor = {116, 212, 255, 255},
    },
    Slider = {
      height = 18, borderRadius = 999, borderWidth = 0,
      trackBgColor = {49, 69, 85, 255},
      trackFillColor = {88, 196, 246, 255},
      trackHeight = 4,
      thumbColor = {88, 196, 246, 255},
      thumbSize = 16,
      thumbBorderColor = {116, 212, 255, 255},
      thumbBorderWidth = 2,
      thumbBorderRadius = 999,
    },
    ProgressBar = {
      height = 8, borderWidth = 0, borderRadius = 999,
      fillColor = {88, 196, 246, 255},
    },
    Card = {
      borderRadius = 16, borderWidth = 2,
      boxShadow = DEPTH_SHADOW,
    },
    Modal = {
      borderWidth = 2, borderRadius = 16,
      boxShadow = DEPTH_SHADOW,
      headerBorderWidth = 2,
      footerBorderWidth = 0,
      contentPadding = {16, 20, 16, 20},
      contentGap = 16,
      footerPadding = {0, 20, 20, 20},
      titleFontWeight = "bold",
      titleFontSize = 13.5,
    },
    Drawer = {
      borderWidth = 2, borderRadius = 16,
      boxShadow = DEPTH_SHADOW,
      contentPadding = {0, 0},
      headerPadding = {14, 16},
      headerBgColor = {28, 43, 58, 255},
    },
    Menu = {
      variant = "outlined",
      fontSize = 10.5,
      borderWidth = 2, borderRadius = 12,
      showDividers = true,
      itemHoverBgColor = {28, 43, 58, 255},
      itemHoverTextColor = {244, 246, 251, 255},
      itemHoverInset = 0, itemHoverRadius = 0,
      itemVerticalInset = 0,
    },
    Dropdown = {
      height = 40, borderWidth = 2, borderRadius = 8,
      triggerBgColor = {21, 35, 49, 255},
      arrowColor = {159, 176, 191, 255},
      hoverBorderColor = {88, 196, 246, 255},
      openBorderColor = {88, 196, 246, 255},
      openBorderWidth = 3,
      popupBorderColor = {49, 69, 85, 255},
      itemHoverBgColor = {28, 43, 58, 255},
      itemHoverTextColor = {244, 246, 251, 255},
      itemHoverInset = 0, itemHoverRadius = 0,
      itemVerticalInset = 0,
    },
    List = {
      backgroundColor = {21, 35, 49, 255},
      fontSize = 12,
      secondaryFontSize = 9,
      borderWidth = 2, borderRadius = 12,
      showDividers = true,
      itemHoverBgColor = {28, 43, 58, 255},
      itemSelectedBgColor = {28, 43, 58, 255},
      itemHoverTextColor = {244, 246, 251, 255},
      itemSelectedTextColor = {244, 246, 251, 255},
    },
    Table = {
      borderWidth = 2, borderRadius = 12,
      headerFontWeight = "bold",
      headerSize = 10.5,
      headerBgColor = {33, 123, 168, 255},
      headerTextColor = {244, 246, 251, 255},
      headerBorderRadius = {12, 12, 0, 0},
      cellTextColor = {178, 184, 199, 255},
      rowOddBgColor = {21, 35, 49, 255},
      rowEvenBgColor = {21, 35, 49, 255},
      rowHoverBgColor = {28, 43, 58, 255},
      rowBorderWidth = 1,
      lastRowBorderRadius = {0, 0, 12, 12},
      fontSize = 9,
    },
    Toast = {
      borderWidth = 2, borderRadius = 12,
      boxShadow = TOAST_SHADOW,
      showIcon = false,
      accentBarWidth = 4,
      accentBarHeight = 36,
      accentBarInset = 14,
    },
    Tooltip = {
      fontSize = 10.5,
      borderWidth = 2, borderRadius = 8,
      tooltipBgColor = {47, 54, 67, 255},
      borderColor = {61, 67, 86, 255},
    },
    Popover = {
      fontSize = 10.5,
      borderWidth = 2, borderRadius = 12,
      backgroundColor = {47, 54, 67, 255},
      borderColor = {61, 67, 86, 255},
    },
    Alert = {
      borderWidth = 2, borderRadius = 12,
    },
    Badge = { borderRadius = 999, fontWeight = "bold", borderWidth = 0 },
    Chip = { borderRadius = 999, borderWidth = 0, fontWeight = "bold" },
    Tabs = {
      fontSize = 9.75,
      activeFontWeight = "bold",
      activeBgColor = {88, 196, 246, 255},
      activeBorderColor = {88, 196, 246, 255},
      activeTextColor = {244, 246, 251, 255},
      inactiveTextColor = {138, 146, 166, 255},
      lineBorderWidth = 2,
      indicatorThickness = 2,
      tabHoverBgColor = {16, 43, 63, 255},
      tabHoverRadius = {12, 12, 0, 0},
      tabHoverTextColor = {138, 146, 166, 255},
      pillMargin = 0,
      enclosedPadding = 1,
      borderWidth = 2,
      variantTabGap = {
        pills = 8,
        enclosed = 3,
      },
      variantBorderRadius = {
        pills = 12,
        enclosed = 8,
      },
      variantTabHeight = {
        line = 40,
        enclosed = 41,
        pills = 35,
      },
      variantContainerBgColor = {21, 35, 49, 255},
      variantContainerBorderRadius = 12,
    },
    Accordion = {
      variant = "outlined",
      bgColor = {21, 35, 49, 255},
      borderWidth = 2, borderRadius = 12,
      headerFontSize = 12,
      headerExpandedBgColor = {28, 43, 58, 255},
      expandedHeaderBorderRadius = {12, 12, 0, 0},
      lastHeaderBorderRadius = {0, 0, 12, 12},
      contentTextColor = {159, 176, 191, 255},
      indicatorExpandedColor = {88, 196, 246, 255},
      showDividers = true,
    },
    Timeline = {
      backgroundColor = {21, 35, 49, 255},
      borderWidth = 2, borderRadius = 12,
      paddingTop = 18, paddingRight = 18, paddingBottom = 18, paddingLeft = 18,
      gap = 14,
      dotSize = 14,
      dotColor = {48, 199, 138, 255},
      lineColor = {32, 155, 108, 255},
      lineWidth = 2,
      titleFontWeight = "bold",
      titleSize = 12,
      hoverTitleColor = {88, 196, 246, 255},
      contentGap = 2,
    },
    Breadcrumb = {
      fontSize = 13.5,
      linkColor = {178, 184, 199, 255},
      hoverColor = {244, 246, 251, 255},
      currentColor = {159, 176, 191, 255},
      separatorColor = {138, 146, 166, 255},
    },
    Stepper = {
      borderRadius = 999,
      borderWidth = 0,
      connectorWidth = 2,
      fontWeight = "bold",
      activeBgColor = {88, 196, 246, 255},
      completedBgColor = {88, 196, 246, 255},
      pendingBgColor = {69, 100, 127, 255},
      connectorColor = {88, 196, 246, 255},
      pendingConnectorColor = {49, 69, 85, 255},
    },
    Pagination = {
      buttonBorderWidth = 2, borderRadius = 8,
      buttonSize = 39,
      gap = 10,
      fontSize = 12,
      activeFontWeight = "bold",
      activeBgColor = {88, 196, 246, 255},
      activeBorderColor = {33, 123, 168, 255},
      activeTextColor = {255, 255, 255, 255},
      hoverBgColor = false,
      hoverBorderColor = {88, 196, 246, 255},
      buttonBgColor = {21, 35, 49, 255},
      buttonBoxShadow = { { x = 0, y = 2, blur = 2, color = {38, 58, 77, 255} } },
      activeButtonBoxShadow = { { x = 0, y = 2, blur = 2, color = {33, 123, 168, 255} } },
    },
    Calendar = {
      borderRadius = 12,
      cellBorderRadius = 999,
      navBtnBgColor = {21, 35, 49, 255},
      navBtnRadius = 2,
      monthFontWeight = "bold",
      weekdayFontWeight = "bold",
      selectedFontWeight = "bold",
      selectedBgColor = {88, 196, 246, 255},
      selectedTextColor = {255, 255, 255, 255},
      todayBorderColor = {88, 196, 246, 255},
      todayTextColor = {88, 196, 246, 255},
      boxShadow = DEPTH_SHADOW,
    },
    DatePicker = {
      borderRadius = 12,
      cellBorderRadius = 999,
      popupBorderRadius = 12,
      navBtnBgColor = {21, 35, 49, 255},
      navBtnRadius = 2,
      fieldBgColor = {21, 35, 49, 255},
      fieldBorderColor = {49, 69, 85, 255},
      fieldBorderRadius = 8,
      fieldFontSize = 12,
      primaryColor = {88, 196, 246, 255},
      monthFontWeight = "bold",
      weekdayFontWeight = "bold",
      selectedFontWeight = "bold",
      selectedBgColor = {88, 196, 246, 255},
      selectedTextColor = {255, 255, 255, 255},
      todayBorderColor = {88, 196, 246, 255},
      todayTextColor = {88, 196, 246, 255},
      todayBtnRadius = 12,
    },
    TimePicker = {
      primaryColor = {88, 196, 246, 255},
      popupBorderRadius = 12,
      fieldBgColor = {21, 35, 49, 255},
      fieldBorderColor = {49, 69, 85, 255},
      fieldBorderRadius = 8,
      fieldFontSize = 12,
      fieldFontWeight = "bold",
      selectedFontWeight = "bold",
      selectedBgColor = {88, 196, 246, 255},
      selectedTextColor = {255, 255, 255, 255},
      selectedItemBorderRadius = 8,
      itemHoverBorderRadius = 8,
    },
    ColorPicker = {
      primaryColor = {88, 196, 246, 255},
      fieldBgColor = {21, 35, 49, 255},
      fieldBorderColor = {49, 69, 85, 255},
      fieldBorderRadius = 8,
      fieldFontSize = 10.5,
      fieldSwatchRadius = 2,
      fieldSwatchBorderWidth = 2,
      cursorWidth = 10,
      cursorRadius = 2,
      cursorBorderColor = {116, 212, 255, 255},
      sliderRadius = 0,
      presetRadius = 2,
    },
    FileUpload = {
      borderRadius = 12, borderWidth = 2,
      dropzoneHeight = 110,
      dropzoneBgColor = {28, 43, 58, 255},
      dropzoneBorderStyle = "solid",
      iconSize = 40,
      iconColor = {88, 196, 246, 255},
    },
    Carousel = {
      borderRadius = 999,
      arrowBgColor = {69, 100, 127, 255},
      arrowHoverBgColor = {85, 120, 148, 255},
      arrowBorderColor = {38, 58, 77, 255},
      arrowBorderWidth = 2,
      arrowSize = 36,
      dotColor = {138, 146, 166, 255},
      activeDotColor = {88, 196, 246, 255},
      indicatorSize = 10,
      indicatorGap = 8,
    },
    Divider = {
      color = {49, 69, 85, 255},
      thickness = 2,
    },
    Rating = {
      activeColor = {244, 200, 74, 255},
      inactiveColor = {244, 200, 74, 255},
    },
    Tree = {
      borderRadius = 12, borderWidth = 2,
      backgroundColor = {21, 35, 49, 255},
      padding = 16,
      fontSize = 10.5,
      iconSize = 16,
      indent = 23,
      iconColor = {88, 196, 246, 255},
      nodeGap = 15,
      hoverBgColor = {28, 43, 58, 255},
      hoverRadius = 8,
      selectedBgColor = {28, 43, 58, 255},
      selectedTextColor = {244, 246, 251, 255},
    },
    Skeleton = {
      borderRadius = 12,
    },
    ScrollView = {
      borderRadius = 12,
    },
  },
})
