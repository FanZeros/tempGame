-- ============================================================================
-- UIInspector - Component Property Schema
-- Each component declares its own prop metadata as an ordered array.
-- Inspector walks the component hierarchy to collect all available props.
-- Properties belong to components; lookups walk Widget → component inheritance.
-- ============================================================================

local Schema = {}

-- Built by Schema.apply()
Schema._propOrder = nil    -- key → number (definition order for sorting)
Schema._tabProps = nil     -- tab → { key = true, ... }
Schema._labelMap = nil     -- key → label (first-seen label for getPropLabel without widget)
Schema._resolved = nil     -- className → { key → def } (预算的完整属性表，含继承)

Schema.COMPONENTS = {
    Widget = {
        propDefs = {
            -- common
            { key = "id",              label = "ID",         type = "string",  tab = { "common" } },
            { key = "visible",         label = _tr("t_16xQwGT5i179Ui8jcG"),       type = "boolean", tab = { "common" } },
            -- layout: size
            { key = "width",           label = _tr("t_vCCAG54Pv03j8DxT"),       type = "layout",  tab = { "common", "layout" } },
            { key = "height",          label = _tr("t_1G5Cqc5QE1GahRfJBt"),       type = "layout",  tab = { "common", "layout" } },
            { key = "minWidth",        label = _tr("t_1GBlJL4Fo1GcLCrETC"),   type = "layout",  tab = { "layout" } },
            { key = "maxWidth",        label = _tr("t_11hdNIVhw12D80ejBG"),   type = "layout",  tab = { "layout" } },
            { key = "minHeight",       label = _tr("t_TvBCm2ZYTUbIj9nm"),   type = "layout",  tab = { "layout" } },
            { key = "maxHeight",       label = _tr("t_1AcG8UB5y1AoJupNkO"),   type = "layout",  tab = { "layout" } },
            { key = "flex",            label = _tr("t_b7yvtHf0bFHJV5gi"),     type = "number",  tab = { "layout" } },
            { key = "flexBasis",       label = _tr("t_orp4Ajtioz2oHzES"), type = "layout", tab = { "layout" } },
            { key = "aspectRatio",     label = _tr("t_babMeruOc1BGoYdj"),     type = "number",  tab = { "common", "layout" } },
            -- layout: position
            { key = "position",        label = _tr("t_vvl9oF5cvVBFQFXy"),   type = "enum",    tab = { "layout" }, options = {
                { value = "relative", label = _tr("t_1E2iEkZXn1Dc8KJYjF") },
                { value = "absolute", label = _tr("t_zFLPZxgrzfzznEBX") },
            } },
            { key = "left",            label = _tr("t_69Spezel5dyFC8L7"),     type = "layout",  tab = { "layout" } },
            { key = "top",             label = _tr("t_Ysh85vLOYNHBP1KW"),     type = "layout",  tab = { "layout" } },
            { key = "right",           label = _tr("t_WGYytRuKW9LEpVQc"),     type = "layout",  tab = { "layout" } },
            { key = "bottom",          label = _tr("t_AwfBnMUJApRRjQ0f"),     type = "layout",  tab = { "layout" } },
            -- layout: margin
            { key = "margin",          label = _tr("t_RMbqgBARQrBw1lef"),     type = "spacing", tab = { "layout" } },
            { key = "marginTop",       label = _tr("t_1DnqZBgtZ1DzuL0vcJ"),   type = "layout",  tab = { "layout" } },
            { key = "marginRight",     label = _tr("t_B3x6fwyQArofwYwu"),   type = "layout",  tab = { "layout" } },
            { key = "marginBottom",    label = _tr("t_VgMYYSj9VUIlsM5J"),   type = "layout",  tab = { "layout" } },
            { key = "marginLeft",      label = _tr("t_ETafyiFrEz0cbHkP"),   type = "layout",  tab = { "layout" } },
            { key = "marginHorizontal", label = _tr("t_8dohEaJT88Okaz9d"), type = "layout",  tab = { "layout" } },
            { key = "marginVertical",   label = _tr("t_dkDi9kC3dcvHfxG1"), type = "layout",  tab = { "layout" } },
            -- layout: padding
            { key = "padding",         label = _tr("t_KGejhJ3nKNx7tPo9"),     type = "spacing", tab = { "layout" } },
            { key = "paddingTop",      label = _tr("t_VFBFkRmEVkbCecOi"),   type = "layout",  tab = { "layout" } },
            { key = "paddingRight",    label = _tr("t_19iSzfxlf19CyMqoQT"),   type = "layout",  tab = { "layout" } },
            { key = "paddingBottom",   label = _tr("t_Scj5QpqXS7J94Yln"),   type = "layout",  tab = { "layout" } },
            { key = "paddingLeft",     label = _tr("t_U1qtHVJLUSQkcNCf"),   type = "layout",  tab = { "layout" } },
            { key = "paddingHorizontal", label = _tr("t_pkJYHaUmpEtbbmwU"), type = "layout",  tab = { "layout" } },
            { key = "paddingVertical",   label = _tr("t_wYtJU8Gfw8EjHcet"), type = "layout",  tab = { "layout" } },
            -- layout: container (only shown for widgets with children)
            { key = "flexDirection",   label = _tr("t_1034n2Vm310AIWpxJZ"),   type = "enum",    tab = { "layout" }, container = true, options = {
                { value = "row", label = _tr("t_uHdRYbKJun3Lg0hd") },
                { value = "column", label = _tr("t_16chbxD9116C33mAMf") },
                { value = "row-reverse", label = _tr("t_1CcdWTqBs1CVL7xreg") },
                { value = "column-reverse", label = _tr("t_17aiFaH2717i0e70S9") },
            } },
            { key = "justifyContent",  label = _tr("t_sxeNLWXztT4JWWcf"),   type = "enum",    tab = { "layout" }, container = true, options = {
                { value = "flex-start", label = _tr("t_UJjrXK1LUCW82dnR") },
                { value = "center", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "flex-end", label = _tr("t_EeX8IvWLElpWDEM3") },
                { value = "space-between", label = _tr("t_8Y1nSYYL8LtKQFcd") },
                { value = "space-around", label = _tr("t_1Da3y6Qz71E5YasHjn") },
                { value = "space-evenly", label = _tr("t_JVQDvjFjJw4lq4Zh") },
            } },
            { key = "alignItems",      label = _tr("t_MxvMYmf1MXLSgh3R"), type = "enum",    tab = { "layout" }, container = true, options = {
                { value = "stretch", label = _tr("t_140rCp2pM13onSvyDW") },
                { value = "flex-start", label = _tr("t_UJjrXK1LUCW82dnR") },
                { value = "center", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "flex-end", label = _tr("t_EeX8IvWLElpWDEM3") },
                { value = "baseline", label = _tr("t_1HC9GWImE1GgedfmSe") },
            } },
            { key = "alignSelf",       label = _tr("t_jE8jfTRIjQHACl30"),   type = "enum",    tab = { "layout" }, options = {
                { value = "auto", label = _tr("t_wlIJmfEJxBsBgSKT") },
                { value = "stretch", label = _tr("t_140rCp2pM13onSvyDW") },
                { value = "flex-start", label = _tr("t_UJjrXK1LUCW82dnR") },
                { value = "center", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "flex-end", label = _tr("t_EeX8IvWLElpWDEM3") },
                { value = "baseline", label = _tr("t_1HC9GWImE1GgedfmSe") },
            } },
            { key = "alignContent",    label = _tr("t_adR84iGmaWDO2yBa"),   type = "enum",    tab = { "layout" }, container = true, options = {
                { value = "stretch", label = _tr("t_140rCp2pM13onSvyDW") },
                { value = "flex-start", label = _tr("t_UJjrXK1LUCW82dnR") },
                { value = "center", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "flex-end", label = _tr("t_EeX8IvWLElpWDEM3") },
                { value = "space-between", label = _tr("t_8Y1nSYYL8LtKQFcd") },
                { value = "space-around", label = _tr("t_1Da3y6Qz71E5YasHjn") },
            } },
            { key = "flexGrow",        label = _tr("t_SfWhe9fkSEs9R71i"), type = "number",  tab = { "layout" } },
            { key = "flexShrink",      label = _tr("t_bGfaN2Hib9Rr7Pkq"), type = "number",  tab = { "layout" } },
            { key = "flexWrap",        label = _tr("t_PBtAVJOjPJ6tlgoZ"), type = "enum",   tab = { "layout" }, container = true, options = {
                { value = "nowrap", label = _tr("t_OQoYQLKoOwJ9VyHQ") },
                { value = "wrap", label = _tr("t_15nWC7wQb15bNj5dV9") },
                { value = "wrap-reverse", label = _tr("t_5WIGeq4J50nfWwSr") },
            } },
            { key = "gap",             label = _tr("t_XeAt7dkuXDb1LcI2"),       type = "number",  tab = { "layout" }, container = true },
            { key = "rowGap",          label = _tr("t_Si1pqcTGZYWyE3"),     type = "number",  tab = { "layout" }, container = true },
            { key = "columnGap",       label = _tr("t_10MDX3LRrzqnaiAZ3"),     type = "number",  tab = { "layout" }, container = true },
            -- appearance
            { key = "backgroundColor", label = _tr("t_1FCbGjAYi1F5NXUeE2"),     type = "color",   tab = { "common", "appearance" } },
            { key = "backgroundImage", label = _tr("t_9s5Tsud99RQvQGij"),     type = "path",    tab = { "appearance" } },
            { key = "backgroundFit",   label = _tr("t_ORNC634LOwn8Yinf"),   type = "enum",    tab = { "appearance" }, options = {
                { value = "cover", label = _tr("t_WsI4u9ULWl4NfANK") },
                { value = "contain", label = _tr("t_kXrR67FhkQdjGU6h") },
                { value = "fill", label = _tr("t_1DwbfTziw1DkTCDNyq") },
                { value = "none", label = _tr("t_9gVGN3qK9ZCpaMne") },
            } },
            { key = "imageTint",       label = _tr("t_Ew0sERX4EVR0Nx0y"),   type = "color",   tab = { "appearance" } },
            { key = "borderColor",     label = _tr("t_1GfrRH1yc1GAMnvyxo"),   type = "color",   tab = { "common", "appearance" } },
            { key = "borderWidth",     label = _tr("t_Ta9cbGGOTmI5yTBG"),   type = "number",  tab = { "common", "appearance" } },
            { key = "borderRadius",    label = _tr("t_5EXmx8EX5QgDPwnL"),       type = "number",  tab = { "common", "appearance" } },
            { key = "opacity",         label = _tr("t_VN7jfX58Vnhe6XtU"),     type = "number",  tab = { "common", "appearance" } },
            { key = "zIndex",          label = _tr("t_16GXqfL2z16NlXxckN"), type = "number", tab = { "appearance" } },
            -- interaction
            { key = "overflow",        label = _tr("t_185146wpC18VfccgWu"),       type = "enum",    tab = { "interaction" }, options = {
                { value = "visible", label = _tr("t_16xQwGT5i179Ui8jcG") },
                { value = "hidden", label = _tr("t_R0nuwFL0RCwLl3oi") },
                { value = "scroll", label = _tr("t_Nk7Es69pOFXBs2o3") },
            } },
            { key = "pointerEvents",   label = _tr("t_14pXDIpE715Kx7DNZR"),   type = "enum",    tab = { "interaction" }, options = {
                { value = "auto", label = _tr("t_wlIJmfEJxBsBgSKT") },
                { value = "none", label = _tr("t_fWPOWJGIfdhovhPU") },
                { value = "box-none", label = _tr("t_pytf9mjQqPYDzb0g") },
            } },
            { key = "cursor",          label = _tr("t_14p5rubk915KVoXS1P"), type = "enum", tab = { "interaction" }, options = {
                { value = "default", label = _tr("t_15kfV7WTm15dRlJncG") },
                { value = "pointer", label = _tr("t_MwdrSyfjMka7zCp3") },
                { value = "move", label = _tr("t_1C1JGJr2U1Bu0rn3MG") },
                { value = "text", label = _tr("t_WXvWUqIrWyVO0e9n") },
                { value = "grab", label = _tr("t_tTCUIrhHsxhqhFU9") },
                { value = "grabbing", label = _tr("t_tBYCsMHctNgd6wZ0") },
                { value = "not-allowed", label = _tr("t_hsqomR4Ii4uZ7Lsu") },
            } },
            { key = "scale",           label = _tr("t_nQYge31Hnw3HBaAS"),       type = "number",  tab = { "interaction" } },
            { key = "rotate",          label = _tr("t_Fz9I4FApFn0pKHzM"),       type = "number",  tab = { "interaction" } },
            { key = "translateX",      label = _tr("t_obAfC1Zyp6aZHJ5w"),   type = "number",  tab = { "interaction" } },
            { key = "translateY",      label = _tr("t_LqKurAETLKqI2q2p"),   type = "number",  tab = { "interaction" } },
        },
    },

    Panel = {},
    Card = {},
    SafeAreaView = {},
    ScrollView = {
        propDefs = {
            { key = "scrollX",             label = _tr("t_5VLUbrjO4zvZtsqS"),   type = "boolean", tab = { "interaction" } },
            { key = "scrollY",             label = _tr("t_Wg8HAK8WWnQhgWFi"),   type = "boolean", tab = { "interaction" } },
            { key = "showScrollbar",       label = _tr("t_rW0goBslrJwx1iRF"), type = "boolean", tab = { "interaction" } },
            { key = "scrollbarInteractive", label = _tr("t_13C4kit0a13O8WY7zy"), type = "boolean", tab = { "interaction" } },
            { key = "allowOverflow",       label = _tr("t_UDFzfCJcUPJjVFOI"),   type = "boolean", tab = { "interaction" } },
        },
    },

    Label = {
        propDefs = {
            { key = "text",            label = _tr("t_1HRuAhjj51HsYiw55o"),       type = "string",  tab = { "common", "content" } },
            { key = "placeholder",     label = _tr("t_ZNHaZkKnZFzC59JH"),   type = "string",  tab = { "content" } },
            { key = "fontSize",        label = _tr("t_6fLzSTox6Y3bTZPp"),       type = "number",  tab = { "common", "content" } },
            { key = "fontFamily",      label = _tr("t_lUPbPuWylzuEEESV"),       type = "string",  tab = { "content" } },
            { key = "fontWeight",      label = _tr("t_3LSgiez03SgObFP6"),   type = "string",  tab = { "content" } },
            { key = "fontColor",       label = _tr("t_18XQZJiHR181vvh099"),   type = "color",   tab = { "common", "content" } },
            { key = "color",           label = _tr("t_1DTF8JjRD1CxpBu5FI"),       type = "color",   tab = { "common", "content" } },
            { key = "lineHeight",      label = _tr("t_g8fMUxgVgFxkO5nN"),       type = "number",  tab = { "content" } },
            { key = "letterSpacing",   label = _tr("t_OXv1cBwsOk3RpxLc"),     type = "number",  tab = { "content" } },
            { key = "textAlign",       label = _tr("t_DUrKhkfADInasjWH"),   type = "enum",    tab = { "content" }, options = {
                { value = "left", label = _tr("t_16mwPw2qZ17IR3IBn3") },
                { value = "center", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "right", label = _tr("t_PdhV9WEsQ97RDAWS") },
            } },
            { key = "verticalAlign",   label = _tr("t_MGXOKjR3M9JeX56l"),   type = "enum",    tab = { "content" }, options = {
                { value = "top", label = _tr("t_SHY7cxD8STgaS8Jw") },
                { value = "middle", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "bottom", label = _tr("t_1G7HcS0Jy1GXrW01M0") },
            } },
            { key = "whiteSpace",      label = _tr("t_GF1UGCfRGkRREyal"),   type = "enum",    tab = { "content" }, options = {
                { value = "nowrap", label = _tr("t_OQoYQLKoOwJ9VyHQ") },
                { value = "normal", label = _tr("t_1B3yqZ5QC1BZTTvEd8") },
            } },
            { key = "textColor",       label = _tr("t_xjuCgTqexcbm9BXe"),   type = "color",   tab = { "common", "content" } },
            { key = "maxLines",        label = _tr("t_SadN8mBMS9ypB8H8"),    type = "number",  tab = { "content" } },
            { key = "wordBreak",       label = _tr("t_MetUQOVoMqxEEEvq"), type = "enum", tab = { "content" }, options = {
                { value = "normal", label = _tr("t_mReHRPgZmFVoLSr7") },
                { value = "break-word", label = _tr("t_K4gQSz3cKa6N6eTq") },
            } },
            { key = "textDecoration",  label = _tr("t_1GNt7dPRQ1GGfO8SAo"), type = "enum", tab = { "content" }, options = {
                { value = "none", label = _tr("t_BX9yinSOBeNiBY4Y") },
                { value = "underline", label = _tr("t_j8bJIE2ljKjm7bwb") },
                { value = "line-through", label = _tr("t_Yc2aOu1oYoB2vebG") },
            } },
            { key = "textTransform",   label = _tr("t_VAwV6aKeUkHwdsAI"), type = "enum", tab = { "content" }, options = {
                { value = "none", label = _tr("t_BX9yinSOBeNiBY4Y") },
                { value = "uppercase", label = _tr("t_J1VIrGrNJ8j2u2sl") },
                { value = "lowercase", label = _tr("t_VL87Yi6AVli12Kbw") },
                { value = "capitalize", label = _tr("t_podZv1zopJ8x4R9W") },
            } },
        },
    },
    RichText = {
        propDefs = {
            { key = "text", label = _tr("t_1HRuAhjj51HsYiw55o"), type = "string", tab = { "common", "content" } },
        },
    },
    Button = {
        propDefs = {
            { key = "text",            label = _tr("t_1HRuAhjj51HsYiw55o"),       type = "string",  tab = { "common", "content" } },
            { key = "fontSize",        label = _tr("t_6fLzSTox6Y3bTZPp"),       type = "number",  tab = { "common", "content" } },
            { key = "fontFamily",      label = _tr("t_lUPbPuWylzuEEESV"),       type = "string",  tab = { "content" } },
            { key = "fontWeight",      label = _tr("t_3LSgiez03SgObFP6"),   type = "string",  tab = { "content" } },
            { key = "textAlign",       label = _tr("t_DUrKhkfADInasjWH"),   type = "enum",    tab = { "content" }, options = {
                { value = "left", label = _tr("t_16mwPw2qZ17IR3IBn3") },
                { value = "center", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "right", label = _tr("t_PdhV9WEsQ97RDAWS") },
            } },
            { key = "verticalAlign",   label = _tr("t_MGXOKjR3M9JeX56l"),   type = "enum",    tab = { "content" }, options = {
                { value = "top", label = _tr("t_SHY7cxD8STgaS8Jw") },
                { value = "middle", label = _tr("t_FLdglqVSF9Zwhlw8") },
                { value = "bottom", label = _tr("t_1G7HcS0Jy1GXrW01M0") },
            } },
            { key = "variant",         label = _tr("t_xme8PdtPxaVfwFu5"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "primary", label = "primary" },
                { value = "secondary", label = "secondary" },
                { value = "danger", label = "danger" },
                { value = "success", label = "success" },
                { value = "outline", label = "outline" },
                { value = "ghost", label = "ghost" },
            } },
            { key = "size",            label = _tr("t_geMBA1zTgqUeDiAO"),       type = "enum",    tab = { "common", "appearance" }, options = {
                { value = "xs", label = "xs" }, { value = "sm", label = "sm" },
                { value = "md", label = "md" }, { value = "lg", label = "lg" }, { value = "xl", label = "xl" },
            } },
            { key = "disabled",        label = _tr("t_GrLzk1HEHMluV1he"),       type = "boolean", tab = { "common", "interaction" } },
            { key = "textColor",       label = _tr("t_xjuCgTqexcbm9BXe"),   type = "color",   tab = { "common", "content" } },
            { key = "icon",            label = _tr("t_G0pEKrUgFtWpo8LM"),   type = "path",    tab = { "content" } },
            { key = "iconSize",        label = _tr("t_izgSmyVKjVB3oHCS"),   type = "number",  tab = { "content" } },
            { key = "hoverBackgroundColor",   label = _tr("t_YuFUVJvzYTatxz8L"), type = "color", tab = { "interaction" } },
            { key = "pressedBackgroundColor", label = _tr("t_bH5pMHaxb4xOFrzN"), type = "color", tab = { "interaction" } },
            { key = "disabledBackgroundColor", label = _tr("t_1hXgFaKt1VPFU4BF"), type = "color", tab = { "interaction" } },
            { key = "hoverBorderColor", label = _tr("t_yudpp0HwynQ62iwI"), type = "color", tab = { "interaction" } },
        },
    },
    TextField = {
        propDefs = {
            { key = "value",           label = _tr("t_T7oOHVY1T0VyJc1X"),     type = "string",  tab = { "common", "content" } },
            { key = "placeholder",     label = _tr("t_ZNHaZkKnZFzC59JH"),   type = "string",  tab = { "content" } },
            { key = "fontSize",        label = _tr("t_6fLzSTox6Y3bTZPp"),       type = "number",  tab = { "common", "content" } },
            { key = "disabled",        label = _tr("t_GrLzk1HEHMluV1he"),       type = "boolean", tab = { "common", "interaction" } },
            { key = "readOnly",        label = _tr("t_ppgpZnH0qL6lxF4e"),       type = "boolean", tab = { "interaction" } },
            { key = "password",        label = _tr("t_13LHmin0n13DzP1l3T"),   type = "boolean", tab = { "interaction" } },
            { key = "maxLength",       label = _tr("t_mbPt1Gghm5vFQovz"),   type = "number",  tab = { "interaction" } },
            { key = "placeholderColor", label = _tr("t_JopINRneJclYahJE"), type = "color",  tab = { "interaction" } },
            { key = "selectionColor",  label = _tr("t_jHerQ0eGjAMTWWxq"),   type = "color",  tab = { "interaction" } },
            { key = "cursorColor",     label = _tr("t_1CdJF7wnA1CW5VvxtW"),   type = "color",  tab = { "interaction" } },
        },
    },
    Dropdown = {
        propDefs = {
            { key = "value",           label = _tr("t_1FbcIjluE1Fng4XuhQ"),     type = "string",  tab = { "common", "content" } },
            { key = "placeholder",     label = _tr("t_ZNHaZkKnZFzC59JH"),   type = "string",  tab = { "content" } },
            { key = "disabled",        label = _tr("t_GrLzk1HEHMluV1he"),       type = "boolean", tab = { "common", "interaction" } },
            { key = "maxVisibleItems", label = _tr("t_FLUivZ88F9QwZGHC"), type = "number",  tab = { "interaction" } },
            { key = "itemHeight",      label = _tr("t_qppiqQlxqdlySUQ7"),   type = "number",  tab = { "interaction" } },
            { key = "triggerBgColor",  label = _tr("t_1EG3voUjC1EgdpgJHQ"), type = "color", tab = { "interaction" } },
            { key = "arrowColor",      label = _tr("t_Dge0yFudDG49PQnF"),   type = "color",  tab = { "interaction" } },
            { key = "itemHoverBgColor", label = _tr("t_457RPhTq3xtkSEy0"), type = "color", tab = { "interaction" } },
            { key = "itemHoverTextColor", label = _tr("t_RjCSk8y1RvKw11kt"), type = "color", tab = { "interaction" } },
            { key = "itemSelectedColor", label = _tr("t_3PbZ9xRI3WtzvYYo"), type = "color", tab = { "interaction" } },
            { key = "itemSelectedTextColor", label = _tr("t_kLAZ5Pupklp9tJuD"), type = "color", tab = { "interaction" } },
            { key = "popupBorderColor", label = _tr("t_4izMcd9i4WqtaJxY"), type = "color", tab = { "interaction" } },
        },
    },

    Checkbox = {
        propDefs = {
            { key = "label",    label = _tr("t_wTPr84RdwM7QzFUY"),     type = "string",  tab = { "common", "content" } },
            { key = "checked",  label = _tr("t_152ZPEXFJ159n6BAbn"),     type = "boolean", tab = { "common", "interaction" } },
            { key = "disabled", label = _tr("t_GrLzk1HEHMluV1he"),     type = "boolean", tab = { "common", "interaction" } },
            { key = "fontSize", label = _tr("t_6fLzSTox6Y3bTZPp"),     type = "number",  tab = { "common", "content" } },
            { key = "fontColor", label = _tr("t_18XQZJiHR181vvh099"), type = "color",  tab = { "content" } },
        },
    },
    Toggle = {
        propDefs = {
            { key = "label",    label = _tr("t_wTPr84RdwM7QzFUY"),     type = "string",  tab = { "common", "content" } },
            { key = "checked",  label = _tr("t_152ZPEXFJ159n6BAbn"),     type = "boolean", tab = { "common", "interaction" } },
            { key = "disabled", label = _tr("t_GrLzk1HEHMluV1he"),     type = "boolean", tab = { "common", "interaction" } },
            { key = "fontSize", label = _tr("t_6fLzSTox6Y3bTZPp"),     type = "number",  tab = { "common", "content" } },
            { key = "fontColor", label = _tr("t_18XQZJiHR181vvh099"), type = "color",  tab = { "content" } },
        },
    },
    Slider = {
        propDefs = {
            { key = "value",    label = _tr("t_h6Q7QI3ShbukDJGC"),   type = "number",  tab = { "common", "interaction" } },
            { key = "min",      label = _tr("t_14ywUKoGV15B0GyRCL"), type = "number",  tab = { "interaction" } },
            { key = "max",      label = _tr("t_gILqkWpug6I45ni8"), type = "number",  tab = { "interaction" } },
            { key = "step",     label = _tr("t_uNAOqRt9uZIrqcgr"),   type = "number",  tab = { "interaction" } },
            { key = "disabled", label = _tr("t_GrLzk1HEHMluV1he"),   type = "boolean", tab = { "common", "interaction" } },
        },
    },
    Stepper = {
        propDefs = {
            { key = "value",    label = _tr("t_h6Q7QI3ShbukDJGC"),   type = "number",  tab = { "common", "interaction" } },
            { key = "min",      label = _tr("t_14ywUKoGV15B0GyRCL"), type = "number",  tab = { "interaction" } },
            { key = "max",      label = _tr("t_gILqkWpug6I45ni8"), type = "number",  tab = { "interaction" } },
            { key = "step",     label = _tr("t_uNAOqRt9uZIrqcgr"),   type = "number",  tab = { "interaction" } },
            { key = "disabled", label = _tr("t_GrLzk1HEHMluV1he"),   type = "boolean", tab = { "common", "interaction" } },
        },
    },
    ProgressBar = {
        propDefs = {
            { key = "value",    label = _tr("t_1Ew9SNTot1FMo0K1X0"),     type = "number",  tab = { "common", "interaction" } },
            { key = "min",      label = _tr("t_14ywUKoGV15B0GyRCL"), type = "number",  tab = { "interaction" } },
            { key = "max",      label = _tr("t_gILqkWpug6I45ni8"), type = "number",  tab = { "interaction" } },
            { key = "progress", label = _tr("t_gHKEHg0Rg5BlBnAj"),   type = "number",  tab = { "interaction" } },
        },
    },
    Rating = {
        propDefs = {
            { key = "value",    label = _tr("t_ELvSc2EdDqVYRK0L"),   type = "number",  tab = { "common", "interaction" } },
            { key = "max",      label = _tr("t_gILqkWpug6I45ni8"), type = "number",  tab = { "interaction" } },
            { key = "disabled", label = _tr("t_GrLzk1HEHMluV1he"),   type = "boolean", tab = { "common", "interaction" } },
        },
    },

    Alert = {
        propDefs = {
            { key = "title",   label = _tr("t_kO5wef0Oka9h0g0w"), type = "string", tab = { "common", "content" } },
            { key = "message", label = _tr("t_FK3AdDjRFCpR7RJL"), type = "string", tab = { "common", "content" } },
            { key = "variant", label = _tr("t_xme8PdtPxaVfwFu5"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "primary", label = "primary" }, { value = "secondary", label = "secondary" },
                { value = "danger", label = "danger" }, { value = "success", label = "success" },
            } },
            { key = "icon",    label = _tr("t_G0pEKrUgFtWpo8LM"), type = "path", tab = { "content" } },
        },
    },
    Badge = {
        propDefs = {
            { key = "text",      label = _tr("t_1HRuAhjj51HsYiw55o"), type = "string", tab = { "common", "content" } },
            { key = "label",     label = _tr("t_wTPr84RdwM7QzFUY"), type = "string", tab = { "common", "content" } },
            { key = "variant",   label = _tr("t_xme8PdtPxaVfwFu5"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "primary", label = "primary" }, { value = "secondary", label = "secondary" },
                { value = "danger", label = "danger" }, { value = "success", label = "success" },
            } },
            { key = "size",      label = _tr("t_geMBA1zTgqUeDiAO"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "xs", label = "xs" }, { value = "sm", label = "sm" },
                { value = "md", label = "md" }, { value = "lg", label = "lg" },
            } },
            { key = "fontSize",  label = _tr("t_6fLzSTox6Y3bTZPp"), type = "number", tab = { "common", "content" } },
            { key = "fontColor", label = _tr("t_18XQZJiHR181vvh099"), type = "color", tab = { "content" } },
        },
    },
    Chip = {
        propDefs = {
            { key = "text",      label = _tr("t_1HRuAhjj51HsYiw55o"), type = "string", tab = { "common", "content" } },
            { key = "label",     label = _tr("t_wTPr84RdwM7QzFUY"), type = "string", tab = { "common", "content" } },
            { key = "variant",   label = _tr("t_xme8PdtPxaVfwFu5"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "primary", label = "primary" }, { value = "secondary", label = "secondary" },
                { value = "outline", label = "outline" },
            } },
            { key = "size",      label = _tr("t_geMBA1zTgqUeDiAO"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "sm", label = "sm" }, { value = "md", label = "md" }, { value = "lg", label = "lg" },
            } },
            { key = "disabled",  label = _tr("t_GrLzk1HEHMluV1he"), type = "boolean", tab = { "common", "interaction" } },
            { key = "fontSize",  label = _tr("t_6fLzSTox6Y3bTZPp"), type = "number", tab = { "common", "content" } },
            { key = "fontColor", label = _tr("t_18XQZJiHR181vvh099"), type = "color", tab = { "content" } },
        },
    },
    Toast = {
        propDefs = {
            { key = "title",   label = _tr("t_kO5wef0Oka9h0g0w"), type = "string", tab = { "common", "content" } },
            { key = "message", label = _tr("t_FK3AdDjRFCpR7RJL"), type = "string", tab = { "common", "content" } },
            { key = "variant", label = _tr("t_xme8PdtPxaVfwFu5"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "info", label = "info" }, { value = "success", label = "success" },
                { value = "warning", label = "warning" }, { value = "error", label = "error" },
            } },
            { key = "icon",    label = _tr("t_G0pEKrUgFtWpo8LM"), type = "path", tab = { "content" } },
        },
    },
    Tooltip = {
        propDefs = {
            { key = "title",   label = _tr("t_kO5wef0Oka9h0g0w"), type = "string", tab = { "common", "content" } },
            { key = "message", label = _tr("t_FK3AdDjRFCpR7RJL"), type = "string", tab = { "common", "content" } },
        },
    },
    Modal = {
        propDefs = {
            { key = "title",   label = _tr("t_kO5wef0Oka9h0g0w"), type = "string", tab = { "common", "content" } },
            { key = "message", label = _tr("t_FK3AdDjRFCpR7RJL"), type = "string", tab = { "common", "content" } },
        },
    },
    Popover = {
        propDefs = {
            { key = "title",   label = _tr("t_kO5wef0Oka9h0g0w"), type = "string", tab = { "common", "content" } },
            { key = "message", label = _tr("t_FK3AdDjRFCpR7RJL"), type = "string", tab = { "common", "content" } },
        },
    },
    Avatar = {
        propDefs = {
            { key = "icon", label = _tr("t_G0pEKrUgFtWpo8LM"), type = "path", tab = { "content" } },
            { key = "size", label = _tr("t_geMBA1zTgqUeDiAO"), type = "enum", tab = { "common", "appearance" }, options = {
                { value = "sm", label = "sm" }, { value = "md", label = "md" }, { value = "lg", label = "lg" },
            } },
        },
    },
    Pagination = {
        propDefs = {
            { key = "current",  label = _tr("t_2dTlvS3O343dn2lI"), type = "number", tab = { "common", "interaction" } },
            { key = "total",    label = _tr("t_1E4b4UJjB1DZB7qiId"), type = "number", tab = { "common", "interaction" } },
            { key = "disabled", label = _tr("t_GrLzk1HEHMluV1he"),   type = "boolean", tab = { "common", "interaction" } },
        },
    },
}

-- ============================================================================
-- Internal Helpers
-- ============================================================================

local function isColorPropName(key)
    return type(key) == "string" and key:sub(-5):lower() == "color"
end

local function optionSignature(options)
    if not options then return "" end
    local parts = {}
    for _, option in ipairs(options) do
        parts[#parts + 1] = tostring(option.value)
    end
    return table.concat(parts, "|")
end

local function propDefSignature(def)
    if not def then return nil end
    return table.concat({
        tostring(def.type or "string"),
        tostring(def.editor or ""),
        optionSignature(def.options),
    }, "#")
end

local function valueMatchesDef(key, value, def)
    if value == nil or not def then return true end
    local valueType = type(value)
    local defType = def.type
    if defType == "layout" then
        return valueType == "number" or valueType == "string"
    elseif defType == "spacing" then
        return valueType == "number" or valueType == "string" or valueType == "table"
    elseif defType == "color" then
        return valueType == "table" or valueType == "string"
    elseif defType == "number" then
        return valueType == "number"
    elseif defType == "boolean" then
        return valueType == "boolean"
    elseif defType == "string" or defType == "path" or defType == "enum" then
        return valueType == "string"
    end
    return true
end

local function inferRuntimePropDef(key, value)
    local valueType = type(value)
    if valueType == "number" then
        return { label = key, type = "number", generic = true }
    elseif valueType == "boolean" then
        return { label = key, type = "boolean", generic = true }
    elseif valueType == "string" then
        return { label = key, type = isColorPropName(key) and "color" or "string", generic = true }
    elseif valueType == "table" and isColorPropName(key) and #value >= 3 then
        return { label = key, type = "color", generic = true }
    end
    return nil
end

-- ============================================================================
-- Public API
-- ============================================================================

function Schema.apply()
    Schema._propOrder = {}
    Schema._tabProps = {}
    Schema._labelMap = {}

    local orderCounter = 0

    -- Widget first (base props), then all other components sorted alphabetically
    local componentOrder = { "Widget" }
    local others = {}
    for name in pairs(Schema.COMPONENTS) do
        if name ~= "Widget" then
            others[#others + 1] = name
        end
    end
    table.sort(others)
    for _, name in ipairs(others) do
        componentOrder[#componentOrder + 1] = name
    end

    for _, componentName in ipairs(componentOrder) do
        local component = Schema.COMPONENTS[componentName]
        for _, entry in ipairs(component.propDefs or {}) do
            local key = entry.key
            if key then
                -- Assign ordering (first seen wins)
                if not Schema._propOrder[key] then
                    orderCounter = orderCounter + 1
                    Schema._propOrder[key] = orderCounter
                end

                -- Label map (first seen wins, for getPropLabel without widget)
                if not Schema._labelMap[key] and entry.label then
                    Schema._labelMap[key] = entry.label
                end

                -- Tab index
                for _, tab in ipairs(entry.tab or {}) do
                    Schema._tabProps[tab] = Schema._tabProps[tab] or {}
                    Schema._tabProps[tab][key] = true
                end
            end
        end
    end

    -- 预算每个组件的完整属性表（Widget 基础 + 组件自有，子覆盖父）
    Schema._resolved = {}
    local function buildEntryDef(entry)
        local def = {}
        for k, v in pairs(entry) do
            if k ~= "key" then def[k] = v end
        end
        return def
    end
    local widgetDefs = {}
    for _, entry in ipairs((Schema.COMPONENTS.Widget or {}).propDefs or {}) do
        if entry.key then
            widgetDefs[entry.key] = buildEntryDef(entry)
        end
    end
    Schema._resolved.Widget = widgetDefs
    for _, componentName in ipairs(others) do
        local merged = {}
        for k, v in pairs(widgetDefs) do merged[k] = v end
        for _, entry in ipairs((Schema.COMPONENTS[componentName] or {}).propDefs or {}) do
            if entry.key then
                merged[entry.key] = buildEntryDef(entry)
            end
        end
        Schema._resolved[componentName] = merged
    end
end

function Schema.getPropDef(key)
    local resolved = Schema._resolved and Schema._resolved.Widget
    return resolved and resolved[key] or nil
end

function Schema.getPropOrder(key)
    return Schema._propOrder and Schema._propOrder[key] or nil
end

function Schema.getPropLabel(key)
    if Schema._labelMap and Schema._labelMap[key] then
        return Schema._labelMap[key]
    end
    return key
end

function Schema.getWidgetPropDef(key, widget)
    local className = widget and widget._className or "Widget"
    local resolved = Schema._resolved and Schema._resolved[className]
    if not resolved then
        resolved = Schema._resolved and Schema._resolved.Widget
    end
    if resolved and resolved[key] then
        return resolved[key]
    end
    return widget and widget.props and inferRuntimePropDef(key, widget.props[key]) or nil
end

function Schema.getWidgetPropKeyMap(widget)
    local keys = {}
    local className = widget and widget._className or "Widget"
    local resolved = Schema._resolved and Schema._resolved[className]
    if not resolved then
        resolved = Schema._resolved and Schema._resolved.Widget
    end
    if not resolved then return keys end

    local hasChildren = widget and widget.children and #widget.children > 0
    for key, def in pairs(resolved) do
        if not def.container or hasChildren then
            keys[key] = true
        end
    end
    return keys
end

function Schema.getEditableProps(widgets, sortFn)
    if not widgets or #widgets == 0 then return {} end

    local result = Schema.getWidgetPropKeyMap(widgets[1])
    for i = 2, #widgets do
        local other = Schema.getWidgetPropKeyMap(widgets[i])
        for key in pairs(result) do
            if not other[key] then
                result[key] = nil
            end
        end
    end

    local keys = {}
    for key in pairs(result) do
        local _, conflict = Schema.getPropDefForWidgets(key, widgets)
        if not conflict then
            keys[#keys + 1] = key
        end
    end
    if sortFn then sortFn(keys) else table.sort(keys) end
    return keys
end

function Schema.getPropDefForWidgets(key, widgets)
    local chosen = nil
    local signature = nil
    for _, widget in ipairs(widgets or {}) do
        local def = Schema.getWidgetPropDef(key, widget)
        local value = widget and widget.props and widget.props[key] or nil
        if def then
            local currentSignature = propDefSignature(def)
            if signature and currentSignature ~= signature then
                return nil, true
            end
            signature = signature or currentSignature
            chosen = def
        elseif value ~= nil then
            return nil, true
        elseif chosen then
            return nil, true
        end

        if value ~= nil and def and not valueMatchesDef(key, value, def) then
            return nil, true
        end
    end

    return chosen, false
end

return Schema
