-- DefaultLobbyUI.lua
-- 引擎默认大厅视觉模板（无项目大厅脚本时自动加载）。
-- 标准沙箱脚本：与制作人项目大厅脚本使用完全相同的 API（LobbyUI 控件代理 + Lobby 动作 + 回调）。
-- 视觉用 urhox-libs/UI 控件声明式构建：UI.Panel/Label/Button/ScrollView/Icon/GradientCard/PulsingCircles。

-- ============================================================================
-- 小工具：把常见组合（头像圆 / 图标按钮 / 空态）包成本地函数
-- ============================================================================

-- 头像：纯色圆 + 居中文字（emoji / 占位）
local function avatarCircle(o)
    o = o or {}
    local size = o.size or 56
    local panel = UI.Panel {
        width = size, height = size, borderRadius = size / 2,
        backgroundColor = o.bg or { 200, 220, 240, 255 },
        borderWidth = o.borderWidth, borderColor = o.borderColor,
        alignItems = "center", justifyContent = "center",
    }
    if o.text and o.text ~= " " then
        panel:AddChild(UI.Label {
            text = o.text, fontSize = o.fontSize or 28, fontWeight = o.fontWeight,
            fontColor = o.fontColor or { 60, 60, 80, 255 },
        })
    end
    return panel
end

-- 图标 + 文字 横排按钮
local function iconButton(o)
    o = o or {}
    local btn = UI.Button {
        flexDirection = "row", alignItems = "center", justifyContent = "center", gap = o.gap or 8,
        paddingLeft = o.paddingLeft, paddingRight = o.paddingRight,
        paddingTop = o.paddingTop, paddingBottom = o.paddingBottom,
        width = o.width, height = o.height, minWidth = o.minWidth, minHeight = o.minHeight,
        backgroundColor = o.backgroundColor or { 0, 0, 0, 0 }, borderRadius = o.borderRadius,
        borderWidth = o.borderWidth, borderColor = o.borderColor,
        onClick = o.onClick,
    }
    if o.icon then
        btn:AddChild(UI.Icon { name = o.icon, variant = "line",
            size = o.iconSize or 20, color = o.iconColor or { 255, 255, 255, 255 }, strokeWidth = o.strokeWidth or 2 })
    end
    if o.label then
        btn:AddChild(UI.Label { text = o.label, fontSize = o.fontSize or 16,
            fontWeight = o.fontWeight, fontColor = o.fontColor or { 255, 255, 255, 255 } })
    end
    return btn
end

-- 列表空态
local function emptyState(o)
    o = o or {}
    return UI.Panel {
        width = "100%", alignItems = "center", justifyContent = "center",
        paddingTop = 60, paddingBottom = 60, gap = 14,
        children = {
            UI.Icon { name = o.icon or "search", variant = "line", size = 48,
                color = { 120, 130, 150, 150 }, strokeWidth = 3 },
            UI.Label { text = o.text or "", fontSize = 18, fontColor = { 150, 160, 180, 200 } },
        },
    }
end

-- 匹配/搜索动画图标（低复用，就地绘制；时间由各屏 update 累加的 upvalue 驱动）
local function drawAnimatedSearch(nvg, cx, cy, size, color, sw, time)
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

local LobbySearchAnimation = UI.Panel:Extend("LobbySearchAnimation")

function LobbySearchAnimation:Init(props)
    props = props or {}
    props.width = props.width or 86
    props.height = props.height or 86
    self.color_ = props.color or { 255, 255, 255, 255 }
    self.strokeWidth_ = props.strokeWidth or 4
    self.elapsed_ = 0
    UI.Panel.Init(self, props)
end

function LobbySearchAnimation:Update(dt)
    self.elapsed_ = self.elapsed_ + dt
end

function LobbySearchAnimation:Render(nvg)
    UI.Panel.Render(self, nvg)
    local layout = self:GetAbsoluteLayout()
    drawAnimatedSearch(
        nvg,
        layout.x + layout.w / 2,
        layout.y + layout.h / 2,
        math.min(layout.w, layout.h),
        self.color_,
        self.strokeWidth_,
        self.elapsed_
    )
end

-- ============================================================================
-- 主界面
-- ============================================================================

local main_nickname = nil
local main_statusDot = nil
local main_statusLabel = nil

local function buildMain()
    local config = Lobby.config or {}
    local userId = Lobby.GetMyUserId()

    -- 需在 update 回调访问的引用：单独构建后嵌入树
    main_nickname = UI.Label { text = _tr("t_19DCzy20319fRYubAY"), fontSize = 15, fontWeight = "bold", fontColor = { 255, 255, 255, 255 } }
    main_statusDot = UI.Panel { width = 8, height = 8, borderRadius = 4, backgroundColor = { 50, 220, 100, 255 } }
    main_statusLabel = UI.Label { text = _tr("t_QXpKdJYYQPYgvCTz"), fontSize = 11, fontColor = { 80, 220, 130, 255 } }

    local nicknameLabel = main_nickname
    local nicknameScreen = LobbyState.screen
    Lobby.GetUserNickname({
        userIds = { userId },
        onSuccess = function(nicknames)
            if LobbyState.screen ~= nicknameScreen or not nicknameLabel.node then return end
            if nicknames and #nicknames > 0 then
                local nn = nicknames[1].nickname or ""
                if nn == "" then nn = _tr("t_18zuRw7Pt18rnE6t2m") end
                nicknameLabel:SetText(nn)
            end
        end,
        onError = function()
            if LobbyState.screen ~= nicknameScreen or not nicknameLabel.node then return end
            nicknameLabel:SetText(_tr("t_18zuRw7Pt18rnE6t2m"))
        end,
    })

    -- ===== 卡片区域（按 config 过滤启用项，动态生成）=====
    local cardConfigs = {
        { text = _tr("t_3oLGvfnU4GMMCbw1"), description = _tr("t_a4k9RVz3Zc3QWCtY"), colorScheme = "blue",   enabled = config.allowQuickMatch,  action = Lobby.QuickMatch },
        { text = _tr("t_oOFMYbK1oFxYSyYu"), description = _tr("t_YLzALCVKYpx0Vx95"),    colorScheme = "cyan",   enabled = config.allowBrowseRooms, action = Lobby.BrowseRooms },
        { text = _tr("t_1DSgBSUmlo9AcDt"), description = _tr("t_XaPZdHvhX6y0KoVY"),    colorScheme = "orange", enabled = config.allowCreateRoom,  action = Lobby.CreateRoom },
    }

    local cardWidth, cardGap, padH = 300, 30, 144
    local enabledCnt = 0
    for _, c in ipairs(cardConfigs) do if c.enabled then enabledCnt = enabledCnt + 1 end end
    local maxW = enabledCnt * cardWidth + math.max(0, enabledCnt - 1) * cardGap + padH * 2

    local contentArea = UI.Panel {
        width = "100%", maxWidth = maxW, minHeight = 100, maxHeight = 400, flexGrow = 1,
        flexDirection = "row", flexWrap = "wrap", alignItems = "stretch",
        justifyContent = "center", alignContent = "stretch", gap = cardGap,
        paddingLeft = padH, paddingRight = padH, paddingTop = cardGap * 0.5, paddingBottom = cardGap * 0.5,
    }
    for _, cc in ipairs(cardConfigs) do
        if cc.enabled then
            local action = cc.action
            contentArea:AddChild(UI.Panel {
                width = 300, minWidth = 300, flexGrow = 1, flexShrink = 1, justifyContent = "center",
                children = {
                    UI.GradientCard {
                        width = "100%", flexGrow = 1, flexShrink = 1, maxHeight = 360,
                        colorScheme = cc.colorScheme, borderRadius = 24,
                        flexDirection = "column", alignItems = "flex-start",
                        paddingLeft = 24, paddingRight = 24, overflow = "hidden",
                        onClick = function() if action then action() end end,
                        children = {
                            UI.Panel { minHeight = 4, flexGrow = 1, flexShrink = 1 },
                            UI.Label { text = cc.text, fontSize = 22, fontWeight = "bold", fontColor = { 255, 255, 255, 255 } },
                            UI.Panel { minHeight = 2, maxHeight = 8, flexGrow = 1, flexShrink = 1 },
                            UI.Label { text = cc.description, fontSize = 13, fontColor = { 255, 255, 255, 160 } },
                            UI.Panel { minHeight = 4, maxHeight = 24, flexGrow = 1, flexShrink = 1 },
                        },
                    },
                },
            })
        end
    end

    local view = UI.Panel {
        width = "100%", height = "100%", flexDirection = "column", alignItems = "center", backgroundColor = { 32, 36, 48, 255 },
        children = {
            -- 顶部：Logo + 用户信息卡片
            UI.Panel {
                width = "100%", maxHeight = "40%", minHeight = 220, flexShrink = 1,
                flexDirection = "column", alignItems = "center", justifyContent = "flex-end", paddingTop = 60, gap = 4,
                children = {
                    UI.Panel { width = 400, height = 200, backgroundImage = "Textures/LogoLarge.png", backgroundFit = "contain" },
                    -- 用户信息卡片（胶囊形）
                    UI.Panel {
                        flexDirection = "row", width = 280, height = 80, alignItems = "center",
                        backgroundColor = { 40, 45, 60, 180 }, borderColor = { 80, 100, 140, 80 },
                        borderWidth = 1, borderRadius = 40, paddingLeft = 10, paddingRight = 16, gap = 12,
                        children = {
                            avatarCircle { size = 56, text = " ", fontSize = 28, fontWeight = "bold",
                                bg = { 200, 220, 240, 255 }, borderWidth = 3, borderColor = { 80, 160, 255, 255 } },
                            UI.Panel {
                                flexDirection = "column", gap = 1,
                                children = {
                                    main_nickname,
                                    UI.Label { text = "ID: " .. FormatInt(userId), fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center", gap = 4,
                                        children = { main_statusDot, main_statusLabel },
                                    },
                                },
                            },
                        },
                    },
                },
            },
            -- 卡片区域
            UI.Panel {
                width = "100%", flexGrow = 1, alignItems = "center", justifyContent = "center",
                children = { contentArea },
            },
            -- 退出按钮
            UI.Panel {
                width = "100%", flexShrink = 1, flexDirection = "column",
                alignItems = "center", justifyContent = "flex-end", paddingTop = 8, paddingBottom = 32,
                children = {
                    iconButton {
                        icon = "exit", iconSize = 18, iconColor = { 255, 80, 80, 255 }, strokeWidth = 2,
                        label = _tr("t_lQr2vOEgkyF2NQ6R"), fontSize = 14, fontColor = { 255, 255, 255, 255 }, gap = 8,
                        paddingLeft = 24, paddingRight = 24, paddingBottom = 12, borderRadius = 8,
                        backgroundColor = { 0, 0, 0, 0 }, onClick = function() Lobby.Exit() end,
                    },
                },
            },
        },
    }

    LobbyUI.main.background:addChild(view)
end

local function updateMainStatus()
    if not main_statusDot then return end
    local isOnline = Lobby.IsOnline()
    if isOnline then
        main_statusDot.backgroundColor = { 50, 220, 100, 255 }
        main_statusLabel:SetStyle({ fontColor = { 80, 220, 130, 255 } })
    else
        main_statusDot.backgroundColor = { 255, 80, 80, 255 }
        main_statusLabel:SetStyle({ fontColor = { 255, 80, 80, 255 } })
    end
    local parts = {}
    table.insert(parts, isOnline and _tr("t_QXpKdJYYQPYgvCTz") or _tr("t_Rr1DCfnQRgKalIOL"))
    if Lobby.IsInRoom() then table.insert(parts, _tr("t_oaiAoxPHp4i2BKLK")) end
    if Lobby.IsMatching() then table.insert(parts, _tr("t_WP2RNoJGVwrMSVxD")) end
    main_statusLabel:SetText(table.concat(parts, " | "))
end

-- ============================================================================
-- 快速匹配等待界面
-- ============================================================================

local DESIGN_W, DESIGN_H = 600, 850
local qm_view = nil
local qm_searchLabel = nil
local qm_timerLabel = nil
local qm_topBarUpdate = nil
local qm_elapsed = 0
local qm_dotTimer = 0
local qm_dotCount = 1
local qm_dots = { ".", "..", "..." }

local function buildQuickMatchWaiting()
    qm_elapsed = 0
    qm_dotTimer = 0
    qm_dotCount = 1

    local topBar, updateStatus = CreateTopBar({ hideRightButton = true, pageTitle = _tr("t_3oLGvfnU4GMMCbw1") })
    qm_topBarUpdate = updateStatus

    qm_searchLabel = UI.Label { text = _tr("t_NFfPZLRDNh5KF8qw"), fontSize = 28, fontWeight = "bold", fontColor = { 255, 255, 255, 255 }, marginBottom = 12 }
    qm_timerLabel = UI.Label { text = _tr("t_eyO5PiGSemgl2xkz"), fontSize = 13, fontColor = { 150, 150, 170, 180 }, marginBottom = 50 }

    local searchAnim = LobbySearchAnimation {
        width = 86,
        height = 86,
        color = { 255, 255, 255, 255 },
        strokeWidth = 4,
    }

    qm_view = UI.Panel {
        width = DESIGN_W, height = DESIGN_H, flexDirection = "column", backgroundColor = { 45, 47, 53, 255 },
        children = {
            topBar,
            UI.Panel {
                width = "100%", flexGrow = 1, flexDirection = "column", alignItems = "center", justifyContent = "center", padding = 20,
                children = {
                    UI.Panel {
                        width = 280, height = 280, alignItems = "center", justifyContent = "center", marginBottom = 30,
                        children = {
                            UI.PulsingCircles { position = "absolute", width = 280, height = 280, color = { 51, 153, 255 }, ringCount = 4 },
                            searchAnim,
                        },
                    },
                    qm_searchLabel,
                    UI.Label { text = _tr("t_1H7XjE0OC1GykZJnzZ"), fontSize = 14, fontColor = { 180, 180, 200, 200 }, marginBottom = 16 },
                    qm_timerLabel,
                    iconButton {
                        icon = "cancel", iconSize = 22, iconColor = { 255, 255, 255, 255 }, strokeWidth = 2.5,
                        label = _tr("t_An9ovnM5AwRAZ5y8"), fontSize = 18, fontWeight = "bold", fontColor = { 255, 255, 255, 255 }, gap = 10,
                        width = 260, height = 60, backgroundColor = { 200, 70, 70, 255 },
                        borderRadius = 30, borderWidth = 2, borderColor = { 160, 50, 50, 200 },
                        onClick = function() Lobby.CancelMatch() end,
                    },
                },
            },
        },
    }

    local wrapper = UI.Panel {
        width = "100%", height = "100%", alignItems = "center", justifyContent = "center", backgroundColor = { 45, 47, 53, 255 },
        children = { qm_view },
    }

    LobbyUI.quick_match_waiting.background:addChild(wrapper)
end

local function updateQuickMatch(dt)
    if not qm_view then return end

    -- 计时（最重要，最先更新，避免被后续调用打断）
    qm_elapsed = qm_elapsed + dt
    if qm_timerLabel then
        local e = math.floor(qm_elapsed)
        qm_timerLabel:SetText(string.format(_tr("t_14uJHLlOS15NfcD7LV"), math.floor(e / 60), e % 60))
    end

    -- 点点动画
    qm_dotTimer = qm_dotTimer + dt
    if qm_dotTimer >= 0.5 then
        qm_dotTimer = 0
        qm_dotCount = qm_dotCount + 1
        if qm_dotCount > 3 then qm_dotCount = 0 end
        if qm_searchLabel then
            qm_searchLabel:SetText(_tr("t_GlBMWTKsGIQXGTgh", (qm_dots[qm_dotCount] or "")))
        end
    end

    -- 顶栏状态刷新（防御性：出错不影响计时/动画）
    if qm_topBarUpdate then pcall(qm_topBarUpdate) end

    -- contain 缩放（防御性）
    if UI.GetWidth and UI.GetHeight then
        pcall(function()
            local baseW, baseH = UI.GetWidth(), UI.GetHeight()
            if baseW and baseH and baseW > 0 and baseH > 0 then
                local s = math.min(baseW / DESIGN_W, baseH / DESIGN_H, 1.0)
                qm_view:SetStyle({ scale = s })
            end
        end)
    end
end

-- ============================================================================
-- 浏览房间界面
-- ============================================================================

local rl_container = nil
local rl_topBarUpdate = nil

local function createRoomCard(room)
    local status = room.status or 1
    local statusText = status == 1 and _tr("t_vwj0n2iavS7u0c7B") or (status == 2 and _tr("t_WP2RNoJGVwrMSVxD") or _tr("t_GXG2Rc9bGg458sW2"))

    return UI.Button {
        flexBasis = "31%", flexGrow = 1, minWidth = 400, maxWidth = "32%", height = 248,
        flexDirection = "column", backgroundColor = { 35, 37, 42, 255 },
        borderRadius = 16, borderWidth = 1, borderColor = { 60, 62, 68, 255 },
        padding = 30, alignItems = "center",
        onClick = function()
            if status == 1 then Lobby.JoinRoom(room.id or 0, room.maxPlayers) end
        end,
        children = {
            -- 第一行：房间ID+名称 / 状态标签
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between", marginBottom = 12, pointerEvents = "none",
                children = {
                    UI.Label { text = string.format("#%d %s", room.id or 0, room.name or _tr("t_dKPVAF3ecqMQG9od")), fontSize = 32, fontWeight = "bold", color = { 255, 255, 255, 255 }, marginLeft = 32 },
                    UI.Panel {
                        backgroundColor = '#174245', width = 120, height = 36, borderRadius = 18, alignItems = "center", justifyContent = "center", marginRight = 32,
                        children = { UI.Label { text = statusText, fontSize = 22, fontWeight = "bold", fontColor = '#10B67E' } },
                    },
                },
            },
            -- 第二行：房主
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "flex-start", gap = 10, marginBottom = 16, pointerEvents = "none", marginLeft = 32,
                children = {
                    avatarCircle { size = 32, text = " ", fontSize = 16, bg = { 255, 180, 100, 255 } },
                    UI.Label { text = _tr("t_nLTVGjzcnomcrqp7", FormatInt(room.ownerId or 0)), fontSize = 22, fontColor = '#7E86B5' },
                },
            },
            -- 分隔线
            UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 82, 88, 255 }, marginBottom = 16, pointerEvents = "none" },
            -- 第三行：玩家数 / 延迟
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between", pointerEvents = "none",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8, pointerEvents = "none", marginLeft = 32,
                        children = {
                            UI.Label { text = "👥", fontSize = 20 },
                            UI.Label { text = string.format("%d/%d", room.playerCount or 0, room.maxPlayers or 4), fontSize = 22, fontColor = '#7E86B5' },
                        },
                    },
                    UI.Label { text = string.format(_tr("t_sMsIN5drss0VPyyQ"), room.latency or 30), fontSize = 20, fontColor = '#7E86B5', marginRight = 32 },
                },
            },
        },
    }
end

local function updateRoomList(rooms)
    if not rl_container then return end
    rl_container:ClearChildren()

    if not rooms or #rooms == 0 then
        rl_container:AddChild(emptyState { icon = "search", text = _tr("t_YN7UjUprYp7Pv13W") })
        return
    end

    for _, room in ipairs(rooms) do
        rl_container:AddChild(createRoomCard(room))
    end
end

local function buildRoomList()
    local topBar, updateStatus = CreateTopBar({
        showBackButton = true, buttonText = _tr("t_qNlgG5bPpwC8vWgM"), ghostStyle = true, pageTitle = _tr("t_oOFMYbK1oFxYSyYu"),
        onBack = function() Lobby.GotoMain() end,
    })
    rl_topBarUpdate = updateStatus

    rl_container = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 35,
        justifyContent = "flex-start", alignContent = "flex-start",
    }

    local view = UI.Panel {
        width = "100%", height = "100%", flexDirection = "column", backgroundColor = { 45, 47, 53, 255 },
        children = {
            topBar,
            UI.ScrollView {
                width = "100%", flexGrow = 1, flexShrink = 1, scrollY = true, backgroundColor = { 45, 47, 53, 255 },
                paddingLeft = 50, paddingRight = 50, paddingTop = 20, paddingBottom = 83,
                children = { rl_container },
            },
        },
    }

    LobbyUI.room_list.background:addChild(view)

    -- 首次加载（框架拉取 → Lobby.onRoomList 回填）
    Lobby.RefreshRoomList()
end

-- ============================================================================
-- 等待房间界面
-- ============================================================================

local rw_playerGrid = nil
local rw_startBtn = nil
local rw_maxPlayers = 4
local rw_myUserId = 0

local CARD_W, CARD_H = 220, 200

local function createPlayerCard(playerData, isHost, slotIndex)
    if playerData then
        local displayName = playerData.nickname or _tr("t_19DCzy20319fRYubAY")
        if #displayName > 12 then displayName = string.sub(displayName, 1, 10) .. ".." end
        local nameLabel = UI.Label { text = displayName, fontSize = 14, fontColor = { 255, 255, 255, 255 } }

        local card = UI.Panel {
            width = CARD_W, height = CARD_H, flexDirection = "column",
            alignItems = "center", justifyContent = "center",
            backgroundColor = { 40, 50, 70, 255 }, borderRadius = 14, borderWidth = 2,
            borderColor = isHost and { 200, 160, 100, 200 } or { 80, 130, 200, 150 }, gap = 12,
            children = {
                -- 房主角标（仅房主）
                isHost and UI.Panel {
                    position = "absolute", top = 10, left = 10, backgroundColor = { 255, 180, 50, 255 },
                    borderRadius = 4, paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                    children = { UI.Label { text = _tr("t_7hcHOnaS7rhgP4E5"), fontSize = 11, fontWeight = "bold", fontColor = { 40, 35, 20, 255 } } },
                } or false,
                avatarCircle { size = 70, text = "👤", fontSize = 36, bg = { 200, 180, 160, 255 },
                    borderWidth = isHost and 3 or 2,
                    borderColor = isHost and { 200, 160, 100, 200 } or { 100, 150, 200, 150 } },
                nameLabel,
                UI.Label { text = _tr("t_AuY7uRNnB3u9vugo", FormatInt(slotIndex)), fontSize = 11, fontColor = { 130, 140, 160, 180 } },
            },
        }

        if not playerData.nickname and playerData.userId then
            local playerScreen = LobbyState.screen
            Lobby.GetUserNickname({
                userIds = { playerData.userId },
                onSuccess = function(nicknames)
                    if LobbyState.screen ~= playerScreen or not nameLabel.node then return end
                    if nicknames and #nicknames > 0 then
                        local nn = nicknames[1].nickname or ""
                        if nn == "" then nn = "Player_" .. FormatInt(playerData.userId) end
                        playerData.nickname = nn
                        if #nn > 12 then nn = string.sub(nn, 1, 10) .. ".." end
                        nameLabel:SetText(nn)
                    end
                end,
                onError = function()
                    if LobbyState.screen ~= playerScreen or not nameLabel.node then return end
                    nameLabel:SetText("Player_" .. FormatInt(playerData.userId))
                end,
            })
        end

        return card
    else
        return UI.Panel {
            width = CARD_W, height = CARD_H, flexDirection = "column",
            alignItems = "center", justifyContent = "center",
            backgroundColor = { 35, 40, 50, 200 }, borderRadius = 14, borderWidth = 1,
            borderColor = { 70, 80, 100, 120 }, borderStyle = "dashed", gap = 10,
            children = {
                UI.Panel {
                    width = 50, height = 50, borderRadius = 25, borderWidth = 2, borderColor = { 100, 115, 140, 150 },
                    backgroundColor = { 0, 0, 0, 0 }, alignItems = "center", justifyContent = "center",
                    children = { UI.Label { text = "+", fontSize = 28, fontColor = { 100, 115, 140, 150 } } },
                },
                UI.Label { text = _tr("t_bruDxYVibjAKQly3"), fontSize = 12, fontColor = { 110, 120, 145, 180 } },
                UI.Label { text = _tr("t_Cj6I0g85CulbTpu0", FormatInt(slotIndex)), fontSize = 10, fontColor = { 90, 100, 120, 140 } },
            },
        }
    end
end

local function updatePlayerGrid(players, masterId)
    if not rw_playerGrid then return end
    rw_playerGrid:ClearChildren()

    local function setStartVisible(mid)
        if rw_startBtn then
            local isMaster = (mid == nil) or (mid == rw_myUserId)
            rw_startBtn:SetVisible(isMaster)
        end
    end

    if not players or #players == 0 then
        rw_playerGrid:AddChild(createPlayerCard({ userId = rw_myUserId, name = "Player_" .. FormatInt(rw_myUserId) }, true, 1))
        for i = 2, rw_maxPlayers do
            rw_playerGrid:AddChild(createPlayerCard(nil, false, i))
        end
        setStartVisible(nil)
        return
    end

    local slotIndex = 1
    for _, player in ipairs(players) do
        local isHost = masterId and player.userId == masterId
        rw_playerGrid:AddChild(createPlayerCard(player, isHost, slotIndex))
        slotIndex = slotIndex + 1
    end
    for i = slotIndex, rw_maxPlayers do
        rw_playerGrid:AddChild(createPlayerCard(nil, false, i))
    end
    setStartVisible(masterId)
end

local function buildRoomWaiting()
    local config = Lobby.config or {}
    rw_myUserId = Lobby.GetMyUserId()
    rw_maxPlayers = config.maxPlayers
    if not rw_maxPlayers or rw_maxPlayers <= 0 then
        local m = Lobby.GetMaxPlayers()
        rw_maxPlayers = (m and m > 0) and m or 4
    end

    rw_playerGrid = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", justifyContent = "center", gap = 20,
    }
    rw_startBtn = UI.Button {
        width = 320, height = 60, fontSize = 20, fontWeight = "bold",
        backgroundColor = { 80, 200, 120, 255 }, fontColor = { 255, 255, 255, 255 },
        borderRadius = 30, text = _tr("t_OAaPAePAO1rLaxpB"),
        onClick = function() Lobby.StartGame() end,
    }

    local roomTitle = (LobbyState.room and LobbyState.room.title) or _tr("t_dKPVAF3ecqMQG9od")

    local view = UI.Panel {
        width = "100%", height = "100%", flexDirection = "column", backgroundColor = { 45, 47, 53, 255 },
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%", height = 120, flexDirection = "row", alignItems = "center",
                justifyContent = "space-between", paddingLeft = 43, paddingRight = 43, paddingTop = 34,
                children = {
                    iconButton {
                        icon = "back", iconSize = 24, iconColor = { 180, 180, 200, 220 }, strokeWidth = 3,
                        label = _tr("t_1FeXFS4xM1FnFysAo5"), fontSize = 20, fontColor = { 180, 180, 200, 220 }, gap = 10,
                        paddingLeft = 16, paddingRight = 24, paddingTop = 12, paddingBottom = 12,
                        minWidth = 120, minHeight = 50, backgroundColor = { 0, 0, 0, 0 }, borderRadius = 12,
                        onClick = function() Lobby.LeaveRoom() end,
                    },
                    UI.Panel {
                        flexGrow = 1, height = "100%", flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 12,
                        children = {
                            UI.Panel {
                                width = 30, height = 34, flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 3,
                                children = {
                                    UI.Panel { width = 6, height = 34, backgroundColor = { 100, 180, 255, 255 }, borderRadius = 2 },
                                    UI.Panel { width = 6, height = 24, backgroundColor = { 100, 180, 255, 255 }, borderRadius = 2 },
                                },
                            },
                            UI.Label { text = roomTitle, fontSize = 24, fontWeight = "bold", fontColor = { 255, 255, 255, 255 } },
                        },
                    },
                    UI.Panel { width = 120, height = 50 },
                },
            },
            -- 玩家网格滚动区
            UI.ScrollView {
                width = "100%", flexGrow = 1, flexShrink = 1, scrollY = true, backgroundColor = { 45, 47, 53, 255 },
                paddingLeft = 40, paddingRight = 40, paddingTop = 20, paddingBottom = 20,
                children = { rw_playerGrid },
            },
            -- 底部开始按钮
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "center", paddingTop = 20, paddingBottom = 50,
                children = { rw_startBtn },
            },
        },
    }

    LobbyUI.room_waiting.background:addChild(view)

    -- 初始显示（仅当前用户为房主）
    updatePlayerGrid(nil, nil)
end

-- ============================================================================
-- 连服界面（匹配成功 → 连接游戏服务器 / 加载资源）
-- ============================================================================

local cn_percentLabel = nil
local cn_barFill = nil
local cn_statusLabel = nil

local CN_BAR_W = 360

local function buildConnecting()
    local conn = LobbyState.connecting or {}
    local pct = math.floor((conn.progress or 0) * 100)
    local status = (conn.status and conn.status ~= "") and conn.status or _tr("t_1Um2bSV91fOJ5pZS")

    cn_percentLabel = UI.Label { text = FormatInt(pct) .. "%", fontSize = 30, fontWeight = "bold", fontColor = { 255, 255, 255, 255 } }
    cn_statusLabel = UI.Label { text = status, fontSize = 14, fontColor = { 180, 180, 200, 200 } }
    cn_barFill = UI.Panel { width = FormatInt(pct) .. "%", height = "100%", backgroundColor = { 80, 160, 255, 255 }, borderRadius = 4 }

    local view = UI.Panel {
        width = "100%", height = "100%", flexDirection = "column",
        alignItems = "center", justifyContent = "center",
        backgroundColor = { 45, 47, 53, 255 }, padding = 20,
        children = {
            -- 脉冲动画 + 中心百分比
            UI.Panel {
                width = 220, height = 220, alignItems = "center", justifyContent = "center", marginBottom = 30,
                children = {
                    UI.PulsingCircles { position = "absolute", width = 220, height = 220, color = { 80, 160, 255 }, ringCount = 4 },
                    cn_percentLabel,
                },
            },
            UI.Label { text = _tr("t_mROCphnumJBiIlbn"), fontSize = 24, fontWeight = "bold", fontColor = { 255, 255, 255, 255 }, marginBottom = 10 },
            cn_statusLabel,
            -- 进度条（轨道 + 填充）
            UI.Panel {
                width = CN_BAR_W, height = 8, backgroundColor = { 60, 64, 76, 255 },
                borderRadius = 4, marginTop = 24, overflow = "hidden",
                children = { cn_barFill },
            },
        },
    }

    LobbyUI.connecting.background:addChild(view)
end

local function updateConnecting(progress, status)
    local pct = math.floor((progress or 0) * 100)
    if cn_percentLabel then cn_percentLabel:SetText(FormatInt(pct) .. "%") end
    if cn_barFill then cn_barFill:SetStyle({ width = FormatInt(pct) .. "%" }) end
    if status and status ~= "" and cn_statusLabel then cn_statusLabel:SetText(status) end
end

-- ============================================================================
-- 注册默认界面（5 屏各一份完整 def；制作人脚本可对任意界面再 DefineScreen 覆盖）
-- ============================================================================

Lobby.DefineScreen("main", {
    enter  = buildMain,
    update = updateMainStatus,
})

Lobby.DefineScreen("quick_match_waiting", {
    enter  = buildQuickMatchWaiting,
    update = updateQuickMatch,
})

Lobby.DefineScreen("room_list", {
    enter      = buildRoomList,
    onRoomList = updateRoomList,
})

Lobby.DefineScreen("room_waiting", {
    enter         = buildRoomWaiting,
    onRoomPlayers = updatePlayerGrid,
})

Lobby.DefineScreen("connecting", {
    enter            = buildConnecting,
    onServerProgress = updateConnecting,
})

print("[DefaultLobbyUI] 默认大厅模板已注册（5 屏）")
