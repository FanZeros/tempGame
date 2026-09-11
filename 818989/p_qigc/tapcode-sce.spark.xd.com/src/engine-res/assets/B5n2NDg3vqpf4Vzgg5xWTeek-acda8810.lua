-- LobbyUISandbox: 大厅模板脚本的执行环境 + 屏/弹窗注册中枢。
-- env 透传完整引擎能力（__index = _G），
-- 只额外注入大厅模板 API：Lobby.DefineScreen/DefineDialog、LobbyState、Timer、控件代理（LobbyUI）。
local LobbyUISandbox = {}
LobbyUISandbox.__index = LobbyUISandbox

-- 统一错误日志：走引擎规范的 log:Write(LOG_ERROR, ...)，不可用时回退 print。
-- 前缀含 "Lua"：让 validate 日志分类器把制作人脚本错误归入 category="lua"。
local function logErr(msg)
    msg = "[lobby_ui] Lua: " .. tostring(msg)
    if log and LOG_ERROR then
        log:Write(LOG_ERROR, msg)
    else
        print(msg)
    end
end

-- ============================================================================
-- Constructor
-- ============================================================================

function LobbyUISandbox.New()
    local self = setmetatable({}, LobbyUISandbox)
    -- screenName → { controlId → Widget }
    self._screens   = {}
    -- 沙箱内部状态（LobbyState 只读代理读这张表）
    self._state     = {
        screen      = nil,
        matchmaking = { status = "idle", elapsed = 0.0 },
        room        = { players = {} },
        connecting  = { progress = 0.0, status = "" },
        self_       = { nickname = "" },
    }
    -- Timer: handle(int) → { remaining, interval|nil, fn }
    self._timers    = {}
    self._timerNext = 0
    -- 沙箱 _ENV 表（Init 时构建一次，RunFile 复用）
    self._env       = nil
    -- 界面注册表：screenName → { enter, update, onRoomList, onRoomPlayers, onMatchmaking, onServerProgress }
    -- 默认模板先注册全部 5 屏，制作人脚本随后覆盖子集；未覆盖的沿用默认。
    self._screenDefs = {}
    -- 弹窗注册表：kind → function(ctx) 或 { show=function(ctx) }。弹窗是叠层，不属于整屏切换。
    self._dialogDefs = {}
    -- 错误信息：加载失败 / 运行时回调失败，供框架判断兜底 + 自测断言读取
    self._loadError = nil   -- 编译/初始执行错误（致命，沙箱不可用）
    self._lastError = nil   -- 运行时回调错误
    self._errors    = {}    -- 有界错误历史（供自测断言），cap 16
    return self
end

-- 记录一条错误：进有界历史 + 走引擎日志（_lastError/_loadError 由调用方按语义设置）。
function LobbyUISandbox:_recordError(msg)
    msg = tostring(msg)
    local errs = self._errors
    errs[#errs + 1] = msg
    if #errs > 16 then table.remove(errs, 1) end   -- 超上限丢最旧
    logErr(msg)
end

--- 最近一条运行时回调错误（无则 nil）。
function LobbyUISandbox:GetLastError()
    return self._lastError
end

--- 错误历史副本（含加载/运行时），按发生顺序。
function LobbyUISandbox:GetErrors()
    local out = {}
    for i, e in ipairs(self._errors) do out[i] = e end
    return out
end

-- ============================================================================
-- Load & init
-- ============================================================================

--- 构建模板脚本的执行 env（仅一次）。extras：调用方注入的额外全局（UI / FormatInt / CreateTopBar / ParseRoomList 等）。
function LobbyUISandbox:Init(extras)
    self._env = self:_BuildSandboxEnv(extras)
end

--- 在已建好的 _ENV 内编译执行一个脚本（可多次叠加：默认模板 → 制作人脚本）。
--- 成功返回 true；失败记 _loadError 并返回 false（默认模板已先注册，调用方据此兜底）。
function LobbyUISandbox:RunFile(path)
    if not self._env then self:Init(nil) end
    if not cache:Exists(path) then
        self._loadError = "script not found: " .. tostring(path)
        self:_recordError(self._loadError)
        return false
    end

    local file = cache:GetFile(path)
    if not file then
        self._loadError = "cache:GetFile failed: " .. tostring(path)
        self:_recordError(self._loadError)
        return false
    end
    local lines = {}
    while not file:IsEof() do
        lines[#lines + 1] = file:ReadLine()
    end
    file:Close()
    local source = table.concat(lines, "\n")

    -- 编译（chunk 名用实际路径，方便调试时定位报错行）
    local chunk, compileErr = load(source, "@" .. path, "t", self._env)
    if not chunk then
        self._loadError = "compile error in " .. path .. ": " .. tostring(compileErr)
        self:_recordError(self._loadError)
        return false
    end

    local ok, runErr = pcall(chunk)
    if not ok then
        self._loadError = "runtime error in " .. path .. ": " .. tostring(runErr)
        self:_recordError(self._loadError)
        return false
    end

    return true
end

--- 安全调用一个界面 def 字段（pcall 包裹 + 错误捕获）。
function LobbyUISandbox:_invoke(fn, label, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        self._lastError = label .. ": " .. tostring(err)
        self:_recordError(self._lastError)
    end
end

-- ============================================================================
-- Screen registration (called by LobbyUI.lua)
-- ============================================================================

--- 注册当前界面的控件映射。
--- @param screenName string 界面 ID（"main"/"room_list"/"room_waiting"/"quick_match_waiting"）
--- @param controls table  { controlId → Widget }
function LobbyUISandbox:RegisterScreen(screenName, controls)
    self._screens[screenName] = controls
end

--- 注销界面（界面销毁时调用）。
function LobbyUISandbox:UnregisterScreen(screenName)
    self._screens[screenName] = nil
end

-- ============================================================================
-- Lifecycle callbacks (called by LobbyUI.lua)
-- ============================================================================

--- 界面切换通知。在新界面控件注册完成后调用 → 触发该界面 def.enter。
function LobbyUISandbox:OnScreenChanged(prev, next)
    self._state.screen = next
    local d = self._screenDefs[next]
    if d then self:_invoke(d.enter, "screen[" .. tostring(next) .. "].enter") end
end

--- 匹配状态变化通知 → 触发 quick_match_waiting def.onMatchmaking。
function LobbyUISandbox:OnMatchmakingChanged(status)
    self._state.matchmaking.status  = status
    self._state.matchmaking.elapsed = 0.0
    local d = self._screenDefs["quick_match_waiting"]
    if d then self:_invoke(d.onMatchmaking, "screen[quick_match_waiting].onMatchmaking", status) end
end

--- 连服进度通知 → 触发 connecting def.onServerProgress。progress 为 0..1，status 为描述文本。
function LobbyUISandbox:OnServerProgress(progress, status)
    self._state.connecting.progress = progress or 0.0
    self._state.connecting.status   = status or ""
    local d = self._screenDefs["connecting"]
    if d then self:_invoke(d.onServerProgress, "screen[connecting].onServerProgress", progress, status) end
end

--- 房间列表更新通知 → 触发 room_list def.onRoomList。rooms 为 ParseRoomList 结果数组。
function LobbyUISandbox:OnRoomList(rooms)
    local d = self._screenDefs["room_list"]
    if d then self:_invoke(d.onRoomList, "screen[room_list].onRoomList", rooms) end
end

--- 房间人员变化通知 → 触发 room_waiting def.onRoomPlayers。players 仅含 {nickname, avatar, userId}。
function LobbyUISandbox:OnRoomPlayers(players, masterId)
    self._state.room.players = players or {}
    local d = self._screenDefs["room_waiting"]
    if d then self:_invoke(d.onRoomPlayers, "screen[room_waiting].onRoomPlayers", players, masterId) end
end

function LobbyUISandbox:SetSelfNickname(nickname)
    self._state.self_.nickname = nickname or ""
end

function LobbyUISandbox:SetRoomTitle(title)
    self._state.room.title = title
end

--- 每帧更新。由大厅 Update 事件驱动 → 推进 Timer + 当前界面 def.update。
function LobbyUISandbox:OnUpdate(dt)
    -- 推进 Timer：先快照句柄，避免回调里 Timer.after/every 向 self._timers
    -- 插入新键、在 pairs 遍历途中触发 Lua 未定义行为（本帧新建的 timer 下一帧才处理）
    local handles = {}
    for h in pairs(self._timers) do handles[#handles + 1] = h end
    local toRemove = nil
    for _, h in ipairs(handles) do
        local t = self._timers[h]
        if t then   -- 回调里可能已 cancel 掉，取不到则跳过
            t.remaining = t.remaining - dt
            if t.remaining <= 0 then
                self:_invoke(t.fn, "Timer callback")
                if t.interval then
                    t.remaining = t.interval
                else
                    if not toRemove then toRemove = {} end
                    toRemove[#toRemove + 1] = h
                end
            end
        end
    end
    if toRemove then
        for _, h in ipairs(toRemove) do self._timers[h] = nil end
    end

    -- 累加 matchmaking.elapsed（仅 searching 状态）
    if self._state.matchmaking.status == "searching" then
        self._state.matchmaking.elapsed = self._state.matchmaking.elapsed + dt
    end

    -- 当前界面每帧回调
    local d = self._screenDefs[self._state.screen]
    if d then self:_invoke(d.update, "screen[" .. tostring(self._state.screen) .. "].update", dt) end
end

--- 尝试用制作人注册的弹窗渲染。返回 true 表示已处理；返回 false 时调用方应走默认弹窗。
--- @param kind string "dialog"|"kicked"|"error"|"system" 等
--- @param context table 弹窗上下文，含 title/message/buttonText/icon/mount/close
function LobbyUISandbox:ShowDialog(kind, context)
    local def = self._dialogDefs[kind]
    if not def then return false end

    local fn = type(def) == "function" and def or (type(def) == "table" and def.show or nil)
    if type(fn) ~= "function" then return false end

    local ok, handled = pcall(fn, context or {})
    if not ok then
        self._lastError = "dialog[" .. tostring(kind) .. "].show: " .. tostring(handled)
        self:_recordError(self._lastError)
        return false
    end
    return handled ~= false
end

-- ============================================================================
-- Internal: sandbox environment
-- ============================================================================

function LobbyUISandbox:_BuildSandboxEnv(extras)
    -- env 透传完整引擎能力（__index = _G：nvg* / 基础库 / require 等真全局直接可用），
    -- 只在其上注入大厅模板 API。
    local env = setmetatable({}, {
        __index = function(_, key)
            if key == "lobby" then return nil end
            return _G[key]
        end,
    })

    env.LobbyUI    = self:_BuildLobbyUIProxy()
    env.LobbyState = self:_BuildLobbyStateProxy()
    env.Timer      = self:_BuildTimer()

    -- Lobby：界面 / 弹窗注册入口（动作集由框架在加载后填充 config/QuickMatch/...）
    local sandbox = self
    env.Lobby = {
        --- 注册/覆盖一个界面的视觉与回调。整屏替换：定义即完全拥有该界面。
        --- def: { enter=fn, update=fn(dt), onRoomList=fn(rooms),
        ---        onRoomPlayers=fn(players,masterId), onMatchmaking=fn(status),
        ---        onServerProgress=fn(progress,status) }
        DefineScreen = function(name, def)
            sandbox._screenDefs[name] = def
        end,
        --- 注册/覆盖一种弹窗。弹窗是当前界面的叠层，不触发 screen 切换。
        --- def 可以是 function(ctx)，也可以是 { show=function(ctx) }。
        DefineDialog = function(kind, def)
            sandbox._dialogDefs[kind] = def
        end,
    }

    -- UI 工具由调用方经 extras 注入（UI / FormatInt / CreateTopBar 等是 LobbyUI 的 local，不在 _G）。
    if extras then
        for k, v in pairs(extras) do
            env[k] = v
        end
    end

    return env
end

-- ============================================================================
-- Internal: LobbyUI proxy
-- ============================================================================

function LobbyUISandbox:_BuildLobbyUIProxy()
    local ui = {}
    local screenNames = { "main", "room_list", "room_waiting", "quick_match_waiting", "connecting" }
    for _, sname in ipairs(screenNames) do
        local screen = {}
        local sname_ = sname  -- 闭包捕获
        setmetatable(screen, {
            __metatable = "locked",
            __index = function(_, key)
                local reg = self._screens[sname_]
                if not reg then
                    error(
                        ("LobbyUI.%s: screen '%s' is not active (current screen: %s)")
                        :format(sname_, sname_, tostring(self._state.screen)), 2)
                end
                local widget = reg[key]
                if widget == nil then
                    error(
                        ("LobbyUI.%s.%s: control '%s' does not exist")
                        :format(sname_, key, key), 2)
                end
                return self:_MakeControlProxy(widget)
            end,
            __newindex = function()
                error("LobbyUI." .. sname_ .. " is read-only", 2)
            end,
        })
        ui[sname] = screen
    end
    return ui
end

function LobbyUISandbox:_MakeControlProxy(widget)
    local proxy = {}
    local styleMemo = nil   -- StyleProxy 缓存

    setmetatable(proxy, {
        __metatable = "locked",
        __index = function(_, key)
            if key == "style" then
                if not styleMemo then
                    styleMemo = self:_MakeStyleProxy(widget)
                end
                return styleMemo
            elseif key == "addChild" then
                return function(_, child)
                    widget:AddChild(child)
                end
            elseif key == "clearChildren" then
                return function(_)
                    widget:ClearChildren()
                end
            elseif key == "text"    then return widget.props and widget.props.text
            elseif key == "visible" then return widget:IsVisible()
            elseif key == "opacity" then return widget.props and widget.props.opacity
            elseif key == "icon"    then return widget.props and widget.props.backgroundImage
            else
                error("LobbyUI control has no readable field: '" .. tostring(key) .. "'", 2)
            end
        end,
        __newindex = function(_, key, val)
            if key == "text" then
                widget:SetStyle({ text = val })
            elseif key == "visible" then
                widget:SetVisible(val)
            elseif key == "opacity" then
                widget:SetStyle({ opacity = val })
            elseif key == "icon" then
                if type(val) ~= "string" or val == "" or val:find(":", 1, true) or val:sub(1, 1) == "/" or val:find("%.%.", 1, true) then
                    error("icon path must be a relative resource path (got: " .. tostring(val) .. ")", 2)
                end
                widget:SetStyle({ backgroundImage = val })
            else
                error("LobbyUI control: cannot set field '" .. tostring(key) .. "'", 2)
            end
        end,
    })
    return proxy
end

function LobbyUISandbox:_MakeStyleProxy(widget)
    local proxy = {}

    -- 样式属性名 → Widget SetStyle key（与 urhox-libs/UI 的 props 体系一致）
    local styleMap = {
        background    = "backgroundColor",
        color         = "color",
        borderColor   = "borderColor",
        fontSize      = "fontSize",
        width         = "width",
        height        = "height",
        padding       = "padding",
        paddingTop    = "paddingTop",
        paddingBottom = "paddingBottom",
        paddingLeft   = "paddingLeft",
        paddingRight  = "paddingRight",
        margin        = "margin",
        marginTop     = "marginTop",
        marginBottom  = "marginBottom",
        marginLeft    = "marginLeft",
        marginRight   = "marginRight",
        flexDirection = "flexDirection",
        alignItems    = "alignItems",
        justifyContent= "justifyContent",
        borderRadius  = "borderRadius",
        borderWidth   = "borderWidth",
        opacity       = "opacity",
        gap           = "gap",
        fontWeight    = "fontWeight",
        fontColor     = "fontColor",
        -- 定位：制作人在自定义模式下用这些属性重定位透明功能 Button
        position      = "position",
        left          = "left",
        top           = "top",
        right         = "right",
        bottom        = "bottom",
    }

    setmetatable(proxy, {
        __metatable = "locked",
        __index = function(_, key)
            local prop = styleMap[key]
            if prop then
                return widget.props and widget.props[prop]
            end
            error("LobbyUI style has no property: '" .. tostring(key) .. "'", 2)
        end,
        __newindex = function(_, key, val)
            local prop = styleMap[key]
            if prop then
                widget:SetStyle({ [prop] = val })
                return
            end
            error("LobbyUI style: cannot set property '" .. tostring(key) .. "'", 2)
        end,
    })
    return proxy
end

-- ============================================================================
-- Internal: LobbyState read-only proxy
-- ============================================================================

local readOnlyStateProxyCache = setmetatable({}, { __mode = "k" })

local function MakeReadOnlyStateView(source, label)
    if type(source) ~= "table" then
        return source
    end
    local cached = readOnlyStateProxyCache[source]
    if cached then
        return cached
    end

    local proxy = {}
    readOnlyStateProxyCache[source] = proxy
    setmetatable(proxy, {
        __metatable = "locked",
        __index = function(_, key)
            return MakeReadOnlyStateView(source[key], label .. "." .. tostring(key))
        end,
        __newindex = function()
            error(label .. " is read-only", 2)
        end,
        __pairs = function()
            local function iter(_, key)
                local nextKey, value = next(source, key)
                if nextKey ~= nil then
                    value = MakeReadOnlyStateView(value, label .. "." .. tostring(nextKey))
                end
                return nextKey, value
            end
            return iter, nil, nil
        end,
        __len = function()
            return #source
        end,
    })
    return proxy
end

function LobbyUISandbox:_BuildLobbyStateProxy()
    local state = self._state
    local matchmaking = MakeReadOnlyStateView(state.matchmaking, "LobbyState.matchmaking")
    local room = MakeReadOnlyStateView(state.room, "LobbyState.room")
    local connecting = MakeReadOnlyStateView(state.connecting, "LobbyState.connecting")
    local selfState = MakeReadOnlyStateView(state.self_, "LobbyState.self")
    local proxy = {}
    setmetatable(proxy, {
        __metatable = "locked",
        __index = function(_, key)
            if key == "screen"      then return state.screen
            elseif key == "matchmaking" then return matchmaking
            elseif key == "room"        then return room
            elseif key == "connecting"  then return connecting
            elseif key == "self"        then return selfState
            end
            return nil
        end,
        __newindex = function()
            error("LobbyState is read-only", 2)
        end,
    })
    return proxy
end

-- ============================================================================
-- Internal: Timer
-- ============================================================================

function LobbyUISandbox:_BuildTimer()
    local timers  = self._timers

    local function nextHandle()
        self._timerNext = self._timerNext + 1
        return self._timerNext
    end

    return {
        --- 一次性定时器。
        after = function(ms, fn)
            assert(type(ms) == "number" and ms >= 0, "Timer.after: ms must be a non-negative number")
            assert(type(fn) == "function", "Timer.after: fn must be a function")
            local h = nextHandle()
            timers[h] = { remaining = ms / 1000.0, interval = nil, fn = fn }
            return h
        end,
        --- 重复定时器。
        every = function(ms, fn)
            assert(type(ms) == "number" and ms > 0, "Timer.every: ms must be a positive number")
            assert(type(fn) == "function", "Timer.every: fn must be a function")
            local h = nextHandle()
            timers[h] = { remaining = ms / 1000.0, interval = ms / 1000.0, fn = fn }
            return h
        end,
        --- 取消定时器。
        cancel = function(h)
            timers[h] = nil
        end,
    }
end

return LobbyUISandbox
