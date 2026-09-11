-- Example_Custom_LobbyRuntime.lua — 自定义大厅「完全自建」示例（参考用，复制到你的项目后修改）。
--
-- 用法：复制本文件到项目 scripts/ 下（例如 scripts/lobby_runtime.lua），在项目源配置
-- .project/settings.json 的 @runtime.multiplayer 中指定：
--     { "@runtime": { "multiplayer": { "lobby_runtime": "scripts/lobby_runtime.lua", "max_players": 4, ... } } }
-- 引擎引导层会选中它作为大厅入口，注入 ctx = { client, root } 调用本文件返回的函数。
--
-- 本文件只负责本地游戏与联机游戏的入口导航，不包含任何本地游戏实现。
-- 项目可另建 scripts/local_game.lua。本示例的模块契约为：
--   return function(gameCtx) ... return { stop = function() end } end
-- gameCtx = { root, onExit, onOnline }。stop 是本示例要求的清理回调；不需要本地游戏时可删除对应按钮与启动函数。
--
-- 与「模板换皮」路径（参考 Example_lobby_ui.lua 图片驱动 / DefaultLobbyUI.lua 纯控件树，两份都可借鉴）的区别：
--   · 模板换皮：用 Lobby.DefineScreen 在固定几屏上换皮，跑在受限沙箱里，专注外观。
--   · 完全自建（本文件）：拿 ctx.client 接平台 + 用完整引擎 UI 自己画任意界面与流程，不受固定屏约束。
--
-- 架构：入口导航与联机页面使用 state + render；本地游戏启动后独占 ctx.root，退出时归还入口。
-- 流程：游戏入口 → 本地游戏（项目独立模块）或联机游戏（加入/新建/房间/连服）。
-- 平台接口只用 ctx.client（方法与回调形状见类型提示文件 lobby_client.d.lua）。

local UI = require("urhox-libs.UI")
local SystemNotification = require("urhox-libs.System.SystemNotification")

-- ▼▼▼ 资源与文案：按你的项目改这里 ▼▼▼
local GAME_TITLE = _tr("t_8e3TQGql88dZEOQT")           -- 换成你的游戏名
local LOCAL_GAME_MODULE = "local_game"  -- 对应项目 scripts/local_game.lua，不由模板提供实现

-- 图片路径相对项目 assets/ 解析；留 nil 用纯色兜底——不填任何图也能跑出一个能用的大厅。
local IMG = {
    background = nil,   -- 例: "ui/lobby_bg.png"     全屏背景图
    userCard   = nil,   -- 例: "ui/user_card.png"    左上用户卡背景
    avatar     = nil,   -- 例: "ui/avatar_frame.png" 头像框（镂空 PNG 叠在底色圆上）
    logo       = nil,   -- 例: "ui/logo.png"         右上 logo（nil 则不显示）
}
-- 房间内玩家格的角色图（按座位取）；留空数组则用 PLAYER_COLORS 的纯色块兜底。
local PLAYER_IMAGES = {}  -- 例: { "ui/char_blue.png", "ui/char_green.png", "ui/char_red.png", "ui/char_yellow.png" }
local PLAYER_COLORS = { { 70, 130, 220, 255 }, { 70, 180, 110, 255 }, { 210, 90, 90, 255 }, { 220, 180, 70, 255 } }
-- ▲▲▲ 资源与文案 ▲▲▲

return function(ctx)
    local client, root = ctx.client, ctx.root
    local input = GetInput and GetInput()
    if input then input.mouseVisible = true end

    -- ====================================================================
    -- 响应式核心：单一 state + setState + render
    -- ====================================================================
    local state = {
        screen    = "main",                    -- main | local_game | online | join | room | connecting
        user      = { id = client:GetMyUserId(), nickname = nil, online = client:IsOnline() },
        room      = nil,                       -- { id, players = {}, masterId }
        match     = { progress = 0, statusText = "" },
        joinInput = "",                        -- 房间号输入缓存（onChange 静默写入，不触发重渲）
        dialog    = nil,                       -- { title, message, buttonText, exitOnClose }
        toast     = nil,                       -- { msg, ttl }
        tick      = 0,                          -- 连服动画相位
    }

    -- 置空哨兵：Lua 表字面量丢弃 nil（{x=nil} 是空表），故用 NIL 显式表达“把字段置 nil”
    local NIL = {}
    local render
    local function setState(patch)
        for k, v in pairs(patch) do
            if v == NIL then state[k] = nil else state[k] = v end
        end
        if state.screen ~= "local_game" then render() end
    end
    local function toast(msg) setState { toast = { msg = msg, ttl = 3 } } end

    local updateSubs = {}
    local function clearUpdates()
        for _, s in ipairs(updateSubs) do UnsubscribeFromEvent(s) end
        updateSubs = {}
    end

    -- ====================================================================
    -- 平台动作（唯一入口 client）；回调一律 setState。
    -- 注意：房间/匹配参数（mapName/maxPlayers/mode）由运行时 settings.json 自动补齐，这里不必传。
    -- ====================================================================
    local function onProgress(p, s)
        -- 取较大值：真实进度不被自动爬升回拉，也防止 onMatchFound 的 0 把进度清零
        local prog = math.max(state.match.progress or 0, p or 0)
        setState { match = { progress = prog, statusText = (s and s ~= "") and s or state.match.statusText } }
    end

    -- 房间人员变化：注册一次，跨重渲染存活，统一投影到 state.room
    local function onRoomPlayers(players, masterId)
        setState { room = { id = state.room and state.room.id, players = players or {}, masterId = masterId } }
    end
    local function onRoomKicked() setState { screen = "main", room = NIL } end

    -- 房主开始游戏 → 连服
    local function startGame()
        setState { screen = "connecting", match = { progress = 0, statusText = _tr("t_NftTXXj1NFEvJOsn") } }
        client:StartGame {
            onMatchFound = function() onProgress(0, _tr("t_cVysLRTMcOgUAMes")) end,
            onProgress   = onProgress,
            onError      = function(code) setState { screen = "room", toast = { msg = _tr("t_18iFQY2cx198pKfXEf", tostring(code)), ttl = 3 } } end,
        }
    end

    -- 本地游戏只通过项目模块入口启动；模板不依赖任何具体玩法实现。
    local activeLocalGame
    local leaveLocalGame

    local function clearRootChildren()
        local children = {}
        for _, child in ipairs(root.children or {}) do children[#children + 1] = child end
        for _, child in ipairs(children) do
            if child.Destroy then child:Destroy() end
        end
    end

    local function invokeLocalGameStop(instance)
        if type(instance) ~= "table" or type(instance.stop) ~= "function" then return true end
        return pcall(instance.stop)
    end

    local function stopLocalGameInstance()
        local instance = activeLocalGame
        activeLocalGame = nil
        if instance then
            local ok, err = invokeLocalGameStop(instance)
            if not ok then toast(_tr("t_kzJ3Nv2plBRWfgyT", tostring(err))) end
        end
    end

    local function failLocalGame(message, instance)
        if instance then
            local ok, err = invokeLocalGameStop(instance)
            if not ok then message = _tr("t_hIJxPf07hPXeyVtl", message, tostring(err)) end
        end
        activeLocalGame = nil
        clearRootChildren()
        state.screen = "main"
        render()
        toast(message)
    end

    leaveLocalGame = function(nextScreen)
        stopLocalGameInstance()
        state.screen = nextScreen or "main"
        render()
    end

    local function startLocalGame()
        if activeLocalGame then return end

        local loaded, entry = pcall(require, LOCAL_GAME_MODULE)
        if not loaded then
            toast(_tr("t_yYvPYzTVy3VSuDrD", tostring(entry)))
            return
        end
        if type(entry) ~= "function" then
            toast(_tr("t_lWJEhyq1lwxmaKYp"))
            return
        end

        -- 本地游戏独占 root：先销毁入口导航树，避免不透明背景和联机按钮残留。
        clearRootChildren()
        state.screen = "local_game"
        local started, instance = pcall(entry, {
            root = root,
            onExit = function() leaveLocalGame("main") end,
            onOnline = function() leaveLocalGame("online") end,
        })
        if not started then
            failLocalGame(_tr("t_CMlH7dQABwBP3jVM", tostring(instance)))
            return
        end
        if type(instance) ~= "table" or type(instance.stop) ~= "function" then
            failLocalGame(_tr("t_15BWAKXsB14zSPsHGf"), instance)
            return
        end
        -- 模块初始化期间同步调用了 onExit/onOnline 导航离开：停掉实例、不记为活动，
        -- 否则实例成孤儿，且 activeLocalGame 会永久挡住再次进入本地游玩。
        if state.screen ~= "local_game" then
            local ok, err = invokeLocalGameStop(instance)
            if not ok then toast(_tr("t_kzJ3Nv2plBRWfgyT", tostring(err))) end
            return
        end
        activeLocalGame = instance
    end

    -- 新建房间并进房
    local function createRoomAndEnter()
        client:CreateRoom {
            onCreated        = function(roomId) setState { screen = "room", room = { id = roomId, players = {}, masterId = nil } } end,
            onError          = function(code) toast(_tr("t_MwEjXAuFMk6GQBsH", tostring(code))) end,
            onPlayersChanged = onRoomPlayers,
            onKicked         = onRoomKicked,
        }
    end

    -- 加入房间：按房号直接加入。不存在走 onError（大厅 AJ_TARGET_TEAM_NOT_VALID=3）。
    local function confirmJoin()
        local num = tonumber(state.joinInput)
        if not num then
            setState { dialog = { title = _tr("t_899P3xa08eZLgSXa"), message = _tr("t_Vj34TidTVIOWZRZh"), buttonText = _tr("t_cSW0UEgXcGNXTr6B") } }
            return
        end
        client:JoinRoom {
            roomId           = num,
            onJoined         = function() setState { screen = "room", room = { id = num, players = {}, masterId = nil } } end,
            onError          = function(code)
                if code == 3 then
                    setState { dialog = { title = _tr("t_xnwaqJQvxNI2urux"), message = _tr("t_kAlXjdG1AkdflHE", tostring(num)), buttonText = _tr("t_cSW0UEgXcGNXTr6B") } }
                else
                    toast(_tr("t_Bkjj2xkABFJmrgM0", tostring(code)))
                end
            end,
            onPlayersChanged = onRoomPlayers,
            onKicked         = onRoomKicked,
        }
    end

    local function leaveRoom()
        client:LeaveRoom {
            onLeft  = function() setState { screen = "main", room = NIL } end,
            onError = function() setState { screen = "main", room = NIL } end,
        }
    end

    -- ====================================================================
    -- 纯视图构件（输入 state，输出控件树；不持有可变引用）
    -- ====================================================================
    local function label(text, size, color, opts)
        local t = { text = text, fontSize = size or 22, fontColor = color or { 255, 255, 255, 255 } }
        for k, v in pairs(opts or {}) do t[k] = v end
        return UI.Label(t)
    end

    local function pill(text, color, onClick, opts)
        opts = opts or {}
        local btn = UI.Button {
            height = opts.height or 76, minWidth = opts.minWidth or 280,
            paddingLeft = 30, paddingRight = 30,
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            backgroundColor = color, borderRadius = 38,
            borderWidth = 2, borderColor = { 255, 255, 255, 70 }, onClick = onClick,
        }
        btn:AddChild(label(text, opts.fontSize or 28, { 255, 255, 255, 255 }, { fontWeight = "bold" }))
        return btn
    end

    -- 居中弹出卡（联机 / 加入面板用，体现“弹出”+ 可返回）
    local function popupCard(children)
        local card = UI.Panel {
            minWidth = 520, paddingTop = 44, paddingBottom = 40, paddingLeft = 48, paddingRight = 48,
            flexDirection = "column", alignItems = "center", gap = 22,
            backgroundColor = { 28, 32, 56, 240 }, borderRadius = 28,
            borderWidth = 2, borderColor = { 120, 150, 240, 150 },
        }
        for _, c in ipairs(children) do card:AddChild(c) end
        return card
    end

    -- 全屏底：纯色打底 + 可选背景图（IMG.background 为 nil 时只显示底色，照样能用）。
    -- opts.scrim：叠半透明暗色蒙层（alpha 0..255），让各子屏与主界面区分。
    local function fullBg(opts)
        opts = opts or {}
        local view = UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = { 16, 20, 38, 255 },
            backgroundImage = IMG.background, backgroundFit = "cover",
            flexDirection = "column", alignItems = "center",
            justifyContent = opts.justify or "center",
            paddingTop = opts.paddingTop or 0, paddingBottom = opts.paddingBottom or 0, gap = opts.gap or 0,
        }
        if opts.scrim then
            view:AddChild(UI.Panel { position = "absolute", top = 0, left = 0, right = 0, bottom = 0, backgroundColor = { 10, 14, 28, opts.scrim } })
        end
        return view
    end

    local function userBadge()
        local card = UI.Panel {
            position = "absolute", top = 36, left = 40,
            flexDirection = "row", alignItems = "center", gap = 16,
            minWidth = 360, height = 110, paddingLeft = 14, paddingRight = 28,
            backgroundColor = { 28, 32, 56, 220 }, borderRadius = 24,
            backgroundImage = IMG.userCard, backgroundFit = "fill",
        }
        -- 头像：底色圆 + emoji 占位（平台只透出 id/昵称，不给头像图）；有 IMG.avatar 则叠镂空头像框
        local avatarBox = UI.Panel { width = 86, height = 86 }
        local disc = UI.Panel {
            position = "absolute", top = 13, left = 13, width = 60, height = 60, borderRadius = 30,
            backgroundColor = { 70, 90, 140, 255 }, alignItems = "center", justifyContent = "center",
        }
        disc:AddChild(label("👤", 32, { 230, 235, 250, 255 }))
        avatarBox:AddChild(disc)
        if IMG.avatar then
            avatarBox:AddChild(UI.Panel { position = "absolute", top = 0, left = 0, width = 86, height = 86, backgroundImage = IMG.avatar, backgroundFit = "contain" })
        end
        card:AddChild(avatarBox)
        local info = UI.Panel { flexDirection = "column", gap = 4 }
        info:AddChild(label(state.user.nickname or (_tr("t_1FORcyq8G1EswzfvFm", tostring(state.user.id))), 26, { 255, 255, 255, 255 }, { fontWeight = "bold" }))
        info:AddChild(label("ID: " .. tostring(state.user.id), 18, { 200, 210, 235, 255 }))
        card:AddChild(info)
        return card
    end

    -- ---- P0 游戏入口：本地游戏 / 联机游戏 / 退出 -----------------------
    local function renderMain()
        local view = fullBg()
        view:AddChild(userBadge())
        if IMG.logo then
            view:AddChild(UI.Panel { position = "absolute", top = 28, right = 36, width = 360, height = 140, backgroundImage = IMG.logo, backgroundFit = "contain" })
        end
        local menu = UI.Panel { flexDirection = "column", alignItems = "center", gap = 26 }
        menu:AddChild(label(GAME_TITLE, 56, { 255, 255, 255, 255 }, { fontWeight = "bold", marginBottom = 16 }))
        menu:AddChild(pill(_tr("t_uEckxB73uk7MKCP9"), { 90, 170, 90, 255 }, function() startLocalGame() end, { minWidth = 360, height = 90, fontSize = 32 }))
        menu:AddChild(pill(_tr("t_eSRduVege1n5jjey"), { 80, 140, 240, 255 }, function() setState { screen = "online" } end, { minWidth = 360, height = 90, fontSize = 32 }))
        menu:AddChild(pill(_tr("t_lQr2vOEgkyF2NQ6R"), { 120, 90, 90, 255 }, function() if engine then engine:Exit() end end, { minWidth = 220, height = 60, fontSize = 22 }))
        view:AddChild(menu)
        return view
    end

    -- ---- P1 联机面板：加入 / 新建 / 返回 -------------------------------
    local function renderOnline()
        local view = fullBg { scrim = 120 }
        view:AddChild(popupCard {
            label(_tr("t_2WDXS5r331dToA8x"), 36, { 255, 255, 255, 255 }, { fontWeight = "bold" }),
            pill(_tr("t_VRTbPiKKVYhKtMcM"), { 80, 160, 240, 255 }, function() setState { screen = "join", joinInput = "" } end, { minWidth = 360 }),
            pill(_tr("t_yDF2CF0uyPIorFSU"), { 90, 200, 120, 255 }, function() createRoomAndEnter() end, { minWidth = 360 }),
            pill(_tr("t_qNlgG5bPpwC8vWgM"), { 80, 86, 120, 255 }, function() setState { screen = "main" } end, { minWidth = 200, height = 60, fontSize = 22 }),
        })
        return view
    end

    -- ---- P2 加入房间：输入房号 + 校验 ----------------------------------
    local function renderJoin()
        local field = UI.TextField {
            width = 360, height = 64, fontSize = 28,
            value = state.joinInput, placeholder = _tr("t_ww2Ose2Rx8Aq0EMz"),
            backgroundColor = { 18, 22, 40, 255 }, borderRadius = 14,
            borderWidth = 2, borderColor = { 90, 120, 200, 180 }, padding = 14,
            onChange = function(_, v) state.joinInput = v end, -- 静默缓存，不触发重渲（保住输入焦点）
        }
        local view = fullBg { scrim = 120 }
        view:AddChild(popupCard {
            label(_tr("t_VRTbPiKKVYhKtMcM"), 36, { 255, 255, 255, 255 }, { fontWeight = "bold" }),
            label(_tr("t_178fKYEG316wbXvUSz"), 20, { 200, 210, 235, 255 }),
            field,
            pill(_tr("t_1HaGSa5dU1HhU9m7ju"), { 90, 200, 120, 255 }, function() confirmJoin() end, { minWidth = 360 }),
            pill(_tr("t_qNlgG5bPpwC8vWgM"), { 80, 86, 120, 255 }, function() setState { screen = "online" } end, { minWidth = 200, height = 60, fontSize = 22 }),
        })
        return view
    end

    -- ---- P3 房间面板：房号 + 玩家 + 离开 + 开始 ------------------------
    local function playerCell(player, idx, isMaster)
        local cell = UI.Panel {
            width = 200, height = 250, flexDirection = "column", alignItems = "center", justifyContent = "center", gap = 12,
            backgroundColor = { 30, 36, 62, 220 }, borderRadius = 18, borderWidth = 2,
            borderColor = isMaster and { 255, 210, 120, 220 } or { 90, 110, 180, 120 },
        }
        -- 角色图（有就用图，没有用纯色块兜底）
        local img = PLAYER_IMAGES[((idx - 1) % math.max(#PLAYER_IMAGES, 1)) + 1]
        cell:AddChild(UI.Panel {
            width = 120, height = 150, borderRadius = 12,
            backgroundColor = PLAYER_COLORS[((idx - 1) % #PLAYER_COLORS) + 1],
            backgroundImage = (#PLAYER_IMAGES > 0) and img or nil, backgroundFit = "contain",
        })
        cell:AddChild(label((player.nickname and player.nickname ~= "") and player.nickname or (_tr("t_1FORcyq8G1EswzfvFm", tostring(player.userId))), 20, { 255, 255, 255, 255 }, { fontWeight = "bold" }))
        if isMaster then cell:AddChild(label(_tr("t_7hcHOnaS7rhgP4E5"), 16, { 255, 210, 120, 255 })) end
        return cell
    end

    local function renderRoom()
        local room = state.room or { id = 0, players = {}, masterId = nil }
        local view = fullBg { justify = "flex-start", paddingTop = 36, paddingBottom = 40, gap = 24, scrim = 150 }

        local header = UI.Panel { width = "86%", flexDirection = "row", alignItems = "center", justifyContent = "space-between" }
        header:AddChild(pill(_tr("t_1FeXFS4xM1FnFysAo5"), { 200, 80, 80, 255 }, function() leaveRoom() end, { minWidth = 140, height = 60, fontSize = 22 }))
        header:AddChild(label(_tr("t_3FPxzsoD3fzq3mSN", tostring(room.id)), 36, { 255, 255, 255, 255 }, { fontWeight = "bold" }))
        header:AddChild(UI.Panel { width = 140 })
        view:AddChild(header)

        local grid = UI.Panel { flexGrow = 1, width = "86%", flexDirection = "row", flexWrap = "wrap", justifyContent = "center", alignItems = "center", gap = 28 }
        if #(room.players or {}) == 0 then
            grid:AddChild(label(_tr("t_HofNsgPxHhRe8GPn"), 24, { 220, 230, 255, 230 }))
        else
            for i, p in ipairs(room.players) do
                grid:AddChild(playerCell(p, i, room.masterId ~= nil and p.userId == room.masterId))
            end
        end
        view:AddChild(grid)

        -- 只有房主显示开始（masterId 为空时默认本人是房主）——可见性由 state 推导
        local isMaster = (room.masterId == nil) or (room.masterId == state.user.id)
        if isMaster then
            view:AddChild(pill(_tr("t_OAaPAePAO1rLaxpB"), { 90, 200, 120, 255 }, function() startGame() end, { height = 84, minWidth = 340, fontSize = 32 }))
        else
            view:AddChild(label(_tr("t_4A90iVzb42qd80gD"), 24, { 220, 230, 255, 230 }))
        end
        return view
    end

    -- ---- P4 连服进度 ---------------------------------------------------
    local function renderConnecting()
        local pct = math.floor((state.match.progress or 0) * 100 + 0.5)
        local dots = string.rep(".", state.tick % 4)
        local view = fullBg { gap = 26, scrim = 140 }
        view:AddChild(label((state.match.statusText ~= "" and state.match.statusText or _tr("t_cwlbP4KWd3zLU2kI")) .. dots, 36, { 255, 255, 255, 255 }, { fontWeight = "bold" }))
        local barBg = UI.Panel { width = 560, height = 22, backgroundColor = { 20, 24, 44, 235 }, borderRadius = 11, borderWidth = 1, borderColor = { 120, 140, 220, 120 } }
        barBg:AddChild(UI.Panel { width = tostring(pct) .. "%", height = "100%", backgroundColor = { 100, 200, 250, 255 }, borderRadius = 11 })
        view:AddChild(barBg)
        view:AddChild(label(pct .. "%", 22, { 200, 220, 255, 255 }))
        return view
    end

    -- ---- 叠层：弹窗 / toast --------------------------------------------
    local function renderDialog()
        local d = state.dialog
        local overlay = UI.Panel { position = "absolute", top = 0, left = 0, right = 0, bottom = 0, backgroundColor = { 0, 0, 0, 180 }, alignItems = "center", justifyContent = "center" }
        overlay:AddChild(popupCard {
            label(d.title or _tr("t_KMa0oWeOKAWHE5Mk"), 32, { 255, 230, 160, 255 }, { fontWeight = "bold" }),
            label(d.message or "", 22, { 210, 220, 240, 255 }, { textAlign = "center" }),
            pill(d.buttonText or _tr("t_cSW0UEgXcGNXTr6B"), { 80, 140, 240, 255 }, function()
                local exit = d.exitOnClose
                setState { dialog = NIL }
                if exit and engine then engine:Exit() end
            end, { minWidth = 240 }),
        })
        return overlay
    end

    local function renderToast()
        local box = UI.Panel { position = "absolute", top = 40, left = "50%", marginLeft = -260, width = 520, paddingTop = 18, paddingBottom = 18, paddingLeft = 24, paddingRight = 24, backgroundColor = { 20, 20, 40, 235 }, borderRadius = 16, borderWidth = 1, borderColor = { 120, 140, 220, 120 }, alignItems = "center", justifyContent = "center" }
        box:AddChild(label(state.toast.msg, 22, { 255, 235, 180, 255 }))
        return box
    end

    -- ====================================================================
    -- render：state 的纯投影（销毁旧树再重建，释放 Yoga 节点）
    -- ====================================================================
    local SCREENS = { main = renderMain, online = renderOnline, join = renderJoin, room = renderRoom, connecting = renderConnecting }
    render = function()
        if state.screen == "local_game" then return end
        clearRootChildren()

        root:AddChild((SCREENS[state.screen] or renderMain)())
        if state.dialog then root:AddChild(renderDialog()) end
        if state.toast then root:AddChild(renderToast()) end
    end

    -- ====================================================================
    -- 平台主动推送（无触发动作）：系统弹窗 + 全局错误
    -- ====================================================================
    client:OnError(function(_errorType, errorCode) toast(_tr("t_18NHjeVXq18B9GJ9hw", tostring(errorCode))) end)
    -- 优先用新版 RegisterHandler 按 id 换皮；旧项目仍可改回 client:OnSystemDialog。
    SystemNotification.RegisterHandler(function(info)
        local view = SystemNotification.Resolve(info)
        local message = view.message
        if view.reason then
            message = _tr("t_Lo69xEfaLNWIRMpI", view.reason)
        end
        if view.kind == "error" then
            toast(message or "")
        else
            setState {
                dialog = {
                    title = view.title or _tr("t_KMa0oWeOKAWHE5Mk"),
                    message = message,
                    buttonText = _tr("t_cSW0UEgXcGNXTr6B"),
                    exitOnClose = view.exitOnClose,
                },
            }
        end
        return true
    end)

    -- 异步取昵称：拿到后投影进 state.user → 自动重渲
    client:GetUserNickname {
        userIds = { state.user.id },
        onSuccess = function(ns)
            local n = ns and ns[1] and ns[1].nickname
            setState { user = { id = state.user.id, online = state.user.online, nickname = (n and n ~= "") and n or nil } }
        end,
        onError = function() end,
    }

    -- 动画 / toast 计时：唯一逐帧驱动，仅在需要时重渲（仍走 state）
    local accum = 0
    updateSubs[#updateSubs + 1] = SubscribeToEvent("Update", function(_, data)
        local dt = data["TimeStep"]:GetFloat()
        local dirty = false
        if state.toast then
            state.toast.ttl = state.toast.ttl - dt
            if state.toast.ttl <= 0 then state.toast = nil; dirty = true end
        end
        if state.screen == "connecting" then
            accum = accum + dt
            if accum >= 0.4 then accum = 0; state.tick = state.tick + 1; dirty = true end
            -- 平台可能不连续下发中间进度：让进度条平滑爬升到 90%，
            -- 真实进度到达时由 onProgress 取较大值顶上去，连服完成即切联机游戏脚本。
            local cur = state.match.progress or 0
            if cur < 0.9 then
                state.match.progress = math.min(0.9, cur + dt * 0.35)
                dirty = true
            end
        end
        if dirty then render() end
    end)

    render()

    return {
        stop = function()
            stopLocalGameInstance()
            SystemNotification.UnregisterHandler()
            client:OnError(nil)
            clearUpdates()
        end,
    }
end
