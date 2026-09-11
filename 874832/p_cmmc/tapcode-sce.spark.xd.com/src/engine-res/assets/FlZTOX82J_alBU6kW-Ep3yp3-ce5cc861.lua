--[[
PlayerSessions.lua - 玩家会话生命周期编排（服务端单表 + 客户端等权威快照）

把引擎四个 PlayerSession* 事件、以及「等客户端就绪再设 scene / 再推快照」的时序，
封装成可直接抄的骨架。快照内容与序列化仍由游戏决定，本模块只做编排。

为什么需要它：四个事件按认证 user_id 关联，但正确用法有若干不显然的时序约束
（见下方「三条容易写错的地方」）。仓内 8 处早期联机实现全部把玩家主键写成
Connection* / address:port / GUID，并在 ClientDisconnected 里立即销毁玩家状态。

用法（服务端，必须在 StartServer() 的同步执行流里调用 Setup）:
    local PlayerSessions = require("urhox-libs.Network.PlayerSessions")

    function StartServer()
        scene_ = Scene()
        scene_:CreateComponent("Octree", LOCAL)

        PlayerSessions.Server.Setup({
            scene = scene_,
            onCreatePlayer = function(userId, connection)
                return { score = 0 }
            end,
            onBuildSnapshot = function(entry, isRestore, snapshot)
                snapshot["Score"] = Variant(entry.state.score)
            end,
            onDisposePlayer = function(entry, reason) end,
        })
    end

用法（客户端，必须在 Start() 的同步执行流里调用 Setup）:
    local PlayerSessions = require("urhox-libs.Network.PlayerSessions")

    function Start()
        scene_ = Scene()
        scene_:CreateComponent("Octree", LOCAL)

        PlayerSessions.Client.Setup({
            scene = scene_,   -- 交给 helper 在上报就绪之前 assign 给服务器连接
            onRestoreBegin  = function() ShowRestoringOverlay() end,
            onFreshStart    = function(data) InitFreshGame(data) end,
            onApplySnapshot = function(data) ApplyScore(data["Score"]:GetInt()) end,
        })
    end

生命周期时序（服务端 S / 客户端 C，回调按此顺序触发）:

    引擎 PlayerSessionJoined ──→ S: onCreatePlayer(userId, conn) → 返回 state
      （或 Reconnected：不再建，直接重绑，isRestore=true）
    C: Setup ──就绪──→ S: [assign conn.scene] → onBuildSnapshot(entry,isRestore,snap)
                          → 下发快照 → onActivated(entry, isRestore)
    快照抵达 C ──→ isRestore ? onApplySnapshot(data) : onFreshStart(data)   ← 二者只调一个
    掉线 ──→ S: onDisconnected(entry, timeout)   ← 只暂存，别销毁
    宽限内重连 ──→ 回到上面第 2 行（isRestore=true，走 onApplySnapshot）
    宽限超时/主动退出/被踢 ──→ S: onDisposePlayer(entry, reason)   ← 这里才销毁

    客户端另有兜底：等快照超时 → onRestoreTimeout(elapsed)；
    UI 提示（非权威）→ onRestoreBegin()

三条容易写错的地方（本模块已代为处理）:

1. **单表，不要双表。** 顶号（新连接替换同一用户的活跃连接）**也**触发
   PlayerSessionReconnected，而那个玩家从未进过「已断线」集合。用
   players + disconnectedPlayers 双表时，顶号会静默跳过重绑与快照重推；更糟的是
   被顶号的旧连接断开时**不再发** PlayerSessionDisconnected，没有任何事件会清掉那个
   陈旧的 Connection 引用，后续 SendRemoteEvent 就是野指针访问。
   判据必须是「表里有没有这个 userId」，而不是「它在不在断线集合里」。

2. **不能在收到 start 事件时就设 connection.scene / 推快照。** 客户端脚本可能还没就绪，
   过早赋值会得到 "Can not handle LoadScene message without an assigned scene"。
   本模块自带 SessionReady/SessionSnapshot 握手，等客户端说就绪再激活。

3. **首次/重连的权威判定在服务端。** 客户端 Network:IsReconnectSession() 是大厅的本地
   推断，只能用于 UI 文案：客户端以为在重连、而服务端宽限期已过时，服务端发的是
   PlayerSessionJoined。所以状态是恢复还是重建，一律看 onApplySnapshot / onFreshStart
   哪个被调用。

本模块不做的事（有意留给游戏 / 引擎）:
  - 不定义快照内容、不做序列化（游戏在 onBuildSnapshot / onApplySnapshot 里自己决定）
  - 不做宽限期计时：到期由引擎判定并发 PlayerSessionLeft
  - 不做持久化、增量同步、插值预测
  - 不据 ClientConnected / ClientDisconnected 建立或销毁玩家（后者仅用作悬空引用保险）
  - 不替客户端决定恢复失败后怎么办（不自动返回大厅、不自动重建局面）
]]

local PlayerSessions = {}

--- 本模块自有的两个远程事件与一个保留字段。三者都可经 Setup 覆盖。
--- 另有两个**不可配置**的保留键（SessionRerequest / SessionUserId，见下），
--- 快照与就绪载荷里以 "Session" 开头的键一律为本模块保留，游戏请避开这个前缀。
PlayerSessions.PROTOCOL = {
    readyEvent = "SessionReady",       -- client -> server：脚本已就绪，可以收快照
    snapshotEvent = "SessionSnapshot", -- server -> client：权威激活 + 快照载荷
    restoreField = "SessionRestore",   -- snapshotEvent 内的保留字段（bool，服务端权威）
}

--- 就绪载荷里的保留键：**重推请求的单调 id**（整数），仅由 Client.RequestSnapshot 递增。
--- 为什么是 id 而不是 bool：一次逻辑请求会被重传多次（重传必须沿用同一个 id，否则首发
--- 丢失时客户端会冻到 timeoutSec），而 bool 分辨不出「同一条请求的重传」与「新请求」，
--- 服务端会对每次重传各推一份快照 → onApplySnapshot 被调 1 + floor(RTT/retrySec) 次，
--- 而 helper 从未要求它幂等。有 id 才能在服务端去重。
--- **故意不做成可配置项**：restoreField 曾因「客户端归一了、服务端没归一」而静默降级，
--- 多一个可配置字段就多一次同样的机会；这个键纯属握手内部约定。
local RE_REQUEST_FIELD = "SessionRerequest"

--- 快照里的保留键：服务端下发本连接对应的**认证** user_id（字符串上 wire，避免 int64
--- 丢精度）。客户端读不到 identity，这是它得知「我是谁」的唯一途径，而没有这个就无法
--- 对广播做归属判断 —— 以前要求每个游戏自己往快照里塞一份，忘了就静默串号。
--- 同样故意不可配置，理由见 RE_REQUEST_FIELD。取值请用 Client.GetUserId()。
local USER_ID_FIELD = "SessionUserId"

--- retrySec 下限。低于 RTT 的重发间隔只会制造重发风暴。
local MIN_RETRY_SEC = 0.5

PlayerSessions.Server = {}
PlayerSessions.Client = {}

--- 配置表的合法键。写错一个回调名（AI 很容易发明 onPlayerJoin 这种像真的名字）
--- 在旧版本里是**静默无操作**：不报错、不生效、没有任何信号。这里改成立刻失败。
local SERVER_KEYS = {
    onCreatePlayer = true, onBuildSnapshot = true, onDisposePlayer = true,
    onDisconnected = true, onActivated = true,
    scene = true, log = true,
    readyEvent = true, snapshotEvent = true, restoreField = true,
}
local CLIENT_KEYS = {
    onApplySnapshot = true, onFreshStart = true,
    onRestoreBegin = true, onRestoreTimeout = true,
    scene = true, log = true,
    readyEvent = true, snapshotEvent = true, restoreField = true,
    timeoutSec = true, retrySec = true,
}

---@param config table
---@param allowed table<string, boolean>
---@param who string
local function rejectUnknownKeys(config, allowed, who)
    local bad = {}
    for k in pairs(config) do
        if not allowed[k] then
            table.insert(bad, tostring(k))
        end
    end
    if #bad == 0 then
        return
    end
    table.sort(bad)
    local names = {}
    for k in pairs(allowed) do table.insert(names, k) end
    table.sort(names)
    error(string.format("%s 收到未知配置项：%s。可用项：%s",
        who, table.concat(bad, ", "), table.concat(names, ", ")), 3)
end

-- ---------------------------------------------------------------------------
-- 共用
-- ---------------------------------------------------------------------------

--- int64 userId 归一。
--- Lua 5.4 的整数是精确 64 位，作 table 键无精度问题；但经某些绑定路径取到的
--- int64 会是 float（VAR_INT64 在部分推栈路径走 lua_Number），此时 tostring 会得到
--- "123.0"、string.format("%d", ...) 会抛 "number has no integer representation"。
--- 这里统一归一，避免日志与拼接出岔。
---@param userId integer|number
---@return integer
local function normalizeUserId(userId)
    -- 整值 float 转整数；非整值属上游 bug，向下取整收敛，避免 float 键混进单表。
    -- math.tointeger 在 Lua 5.1 构建（URHO3D_LUA_EX=OFF）下不存在，故有兜底。
    if math.tointeger then
        return math.tointeger(userId) or math.floor(userId)
    end
    return math.floor(userId)
end

---@param log nil|fun(message: string)
---@return fun(message: string)
local function makeLogger(log)
    if log then
        return log
    end
    return function(message)
        print("[PlayerSessions] " .. message)
    end
end

-- ---------------------------------------------------------------------------
-- 服务端
-- ---------------------------------------------------------------------------

---@class PlayerSessionEntry
---@field userId integer 认证后的 user_id
---@field connection Connection|nil 当前活跃连接；宽限期内为 nil
---@field state any 游戏自己的玩家对象（onCreatePlayer 的返回值）
---@field online boolean connection ~= nil 的镜像
---@field awaitingReady boolean 已收到 start 事件、尚未收到客户端就绪
---@field isRestore boolean 本次待激活是恢复(true)还是首次(false)
---@field reconnectTimeout number 最近一次断线携带的宽限秒数；未断线过为 0

local players_ = {}
local serverCfg_ = nil
local serverNode_ = nil
local serverSO_ = nil
local serverLog_ = nil

---@param userId integer
---@param connection Connection
---@return PlayerSessionEntry
local function newEntry(userId, connection)
    return {
        userId = userId,
        connection = connection,
        state = nil,
        online = true,
        awaitingReady = true,
        isRestore = false,
        reconnectTimeout = 0,
    }
end

--- 构建快照：先填本模块的保留字段，再交给游戏补业务字段。
--- 约定是「往传入的 map 里填」而不是「返回一个 map」：Lua 侧没有 VariantMap setter 能把
--- 游戏返回的 map 与保留字段合并。而「return snapshot」恰是绝大多数 API 的直觉写法，
--- 以前这么写会**静默**发出只有保留字段的空快照、零诊断信息，所以这里主动抓。
---@param entry PlayerSessionEntry
---@param isRestore boolean
---@return table snapshot
local function buildSnapshot(entry, isRestore)
    local snapshot = VariantMap()
    snapshot[serverCfg_.restoreField] = Variant(isRestore)
    -- 客户端读不到 identity，靠这个字段才知道「我是谁」（Client.GetUserId()）。
    -- 字符串上 wire，避免 int64 丢精度。
    snapshot[USER_ID_FIELD] = Variant(tostring(entry.userId))
    local returned = serverCfg_.onBuildSnapshot(entry, isRestore, snapshot)
    if returned ~= nil then
        error("onBuildSnapshot 不要 return —— 请往传入的第三个参数 snapshot 里填字段，"
            .. _tr("t_16zglL9re176uVDDF6")
            .. _tr("t_MOhdPUJGLtHhL19A"), 0)
    end
    return snapshot
end

--- 激活：设 scene（若配置了）+ 构建并下发快照。仅在客户端就绪后调用。
---@param entry PlayerSessionEntry
local function activate(entry)
    local connection = entry.connection
    if not connection then
        return
    end

    if serverCfg_.scene and connection.scene ~= serverCfg_.scene then
        connection.scene = serverCfg_.scene
    end

    connection:SendRemoteEvent(serverCfg_.snapshotEvent, true,
        buildSnapshot(entry, entry.isRestore))

    entry.awaitingReady = false
    if serverCfg_.onActivated then
        serverCfg_.onActivated(entry, entry.isRestore)
    end
end

--- start 事件（Joined / Reconnected）走同一条路径。
--- 引擎的 Joined-first 契约：未介绍过的用户即使内部是宽限期回归或顶号，也以 Joined
--- 形式派发；所以 isRestore 由「表里是否已有该 userId」决定，而不是由事件名决定。
---@param userId integer
---@param connection Connection
local function handleStart(userId, connection)
    local entry = players_[userId]
    if entry then
        -- 宽限期回归与顶号在此**共用同一条代码路径**：都是重绑 + 待激活。
        entry.connection = connection
        entry.online = true
        entry.awaitingReady = true
        entry.isRestore = true
        -- 重推请求的去重范围是**一条连接**，不是 entry 的整个生命周期：新连接意味着
        -- 新的客户端实例，而 clientReqId_ 随 Lua 状态重建从 0 重数。不清零的话，
        -- 上一次会话里点过一次「重试」（id 1）会让新会话的第一次重试也被判成重复，
        -- 客户端又冻满 timeoutSec —— 那正是 RequestSnapshot 那条 bug 换了个入口。
        entry.lastRerequestId = nil
    else
        entry = newEntry(userId, connection)
        players_[userId] = entry
        entry.state = serverCfg_.onCreatePlayer(userId, connection)
    end
end

local function onSessionJoined(self, eventType, eventData)
    local userId = normalizeUserId(eventData["UserId"]:GetInt64())
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then
        serverLog_(_tr("t_ifGqZsRCiY371ca0", tostring(userId)))
        return
    end
    handleStart(userId, connection)
end

local function onSessionReconnected(self, eventType, eventData)
    local userId = normalizeUserId(eventData["UserId"]:GetInt64())
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then
        serverLog_(_tr("t_1BUKOgbL21BIBvJ36w", tostring(userId)))
        return
    end
    if not players_[userId] then
        -- 按 Joined-first 契约不该发生；补建并记一笔，避免玩家凭空消失。
        serverLog_(_tr("t_4AWQPEh243E2onuE", tostring(userId)))
    end
    handleStart(userId, connection)
end

local function onSessionDisconnected(self, eventType, eventData)
    local userId = normalizeUserId(eventData["UserId"]:GetInt64())
    local entry = players_[userId]
    if not entry then
        return
    end
    local timeout = eventData["ReconnectTimeout"]:GetFloat()
    entry.connection = nil
    entry.online = false
    entry.reconnectTimeout = timeout
    -- 不清 awaitingReady：重连后会重新置位并改走恢复路径。
    if serverCfg_.onDisconnected then
        serverCfg_.onDisconnected(entry, timeout)
    end
end

local function onSessionLeft(self, eventType, eventData)
    local userId = normalizeUserId(eventData["UserId"]:GetInt64())
    local entry = players_[userId]
    if not entry then
        return
    end
    local reason = eventData["Reason"]:GetString()
    -- **先摘表再回调**：回调里 Count()/ForEach 看到的就是「该玩家已离开」的一致视图，
    -- 于是「最后一人离开」写 Count() == 0 而不是反直觉的 <= 1。
    -- entry 仍作参数传入，回调不需要再查表。
    -- 摘表同时也清掉了待激活状态（awaitingReady 挂在 entry 上），无需第二处清理。
    players_[userId] = nil
    if serverCfg_.onDisposePlayer then
        serverCfg_.onDisposePlayer(entry, reason)
    end
end

--- 客户端上报就绪。
--- identity 是**客户端上报值**（ProcessIdentity 在校验前就整体存下），所以只用于
--- 反查已登记玩家，绝不用于创建；再叠一道 entry.connection == connection 校验。
local function onClientReady(self, eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then
        return
    end
    local idVariant = eventData[RE_REQUEST_FIELD]
    PlayerSessions.Server.NotifyClientReady(connection, idVariant and idVariant:GetInt() or nil)
end

--- 悬空引用保险。正常路径由 PlayerSessionDisconnected 先处理完；顶号旧连接的延迟断开
--- 走到这里时 entry.connection 已是新连接，比较不相等、无副作用。
local function onClientDisconnected(self, eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    if not connection then
        return
    end
    for _, entry in pairs(players_) do
        if entry.connection == connection then
            entry.connection = nil
            entry.online = false
        end
    end
end

--- 注册四个会话事件与就绪握手，接管单表维护。
--- ⚠️ 必须在 StartServer() 的同步执行流里调用：脚本就绪前产生的会话事件由引擎在
--- StartServer() 返回后一次性状态压缩回放，晚于此刻建立的订阅拿不到首批玩家。
---@param config table
function PlayerSessions.Server.Setup(config)
    assert(type(config) == "table", _tr("t_dC00UK9BclQ9Bzh1"))
    assert(type(config.onCreatePlayer) == "function", _tr("t_TcxJCeVwTkFj8chG"))
    assert(type(config.onBuildSnapshot) == "function", _tr("t_CK3ZWamUC7v6XF7g"))
    -- 归一化会往 config 里写键，所以校验必须在那之前
    rejectUnknownKeys(config, SERVER_KEYS, "PlayerSessions.Server.Setup")

    serverCfg_ = config
    serverCfg_.readyEvent = config.readyEvent or PlayerSessions.PROTOCOL.readyEvent
    serverCfg_.snapshotEvent = config.snapshotEvent or PlayerSessions.PROTOCOL.snapshotEvent
    serverCfg_.restoreField = config.restoreField or PlayerSessions.PROTOCOL.restoreField
    serverLog_ = makeLogger(config.log)

    -- allowlist 只在接收路径生效，所以服务端只注册自己要收的那个。
    network:RegisterRemoteEvent(serverCfg_.readyEvent)

    -- 必须自持接收者：Object::SubscribeToEvent 对同一 (receiver, eventType) 是**替换**
    -- 语义，用全局 SubscribeToEvent 会在游戏顺手订阅同名事件时被静默顶掉。
    serverNode_ = Node()
    serverSO_ = serverNode_:CreateScriptObject("LuaScriptObject")
    serverSO_:SubscribeToEvent("PlayerSessionJoined", onSessionJoined)
    serverSO_:SubscribeToEvent("PlayerSessionReconnected", onSessionReconnected)
    serverSO_:SubscribeToEvent("PlayerSessionDisconnected", onSessionDisconnected)
    serverSO_:SubscribeToEvent("PlayerSessionLeft", onSessionLeft)
    serverSO_:SubscribeToEvent(serverCfg_.readyEvent, onClientReady)
    serverSO_:SubscribeToEvent("ClientDisconnected", onClientDisconnected)

    return PlayerSessions
end

--- 游戏已有自己的就绪握手时，在自己的 handler 里调一次即可（与内置握手等价、幂等）。
---@param connection Connection
---@param rerequestId integer|nil 客户端显式重推请求的单调 id（内置握手由 RequestSnapshot
---       给出）。省略时，已激活连接的就绪会被丢弃——那是重试回声，应答它会让首次进入的
---       玩家把 onFreshStart 与 onApplySnapshot 都跑一遍。
---       同一个 id 重复到达只应答一次：一次逻辑请求会被重传多次，每次各推一份快照会让
---       onApplySnapshot 被调 1 + floor(RTT/retrySec) 次，而它不要求幂等。
---@return boolean handled true = 已激活 / 已重推 / 已识别为重复请求；false = 未找到玩家或丢弃回声
function PlayerSessions.Server.NotifyClientReady(connection, rerequestId)
    if not connection or not serverCfg_ then
        return false
    end
    for _, entry in pairs(players_) do
        if entry.connection == connection then
            if entry.awaitingReady then
                -- 被 activate 消耗掉的那个 id 也要记住：否则它的重传（或同一次等待里
                -- 玩家再点一次重试）会被当成**新**请求而再推一份快照，而客户端只有一个
                -- 等待位 —— 先到的那份清零，第二份就走「激活后重推」分支调
                -- onApplySnapshot，首次进入的玩家于是把两个回调都跑了一遍。
                entry.lastRerequestId = rerequestId
                activate(entry)
                return true
            end
            -- 已激活的连接又发来就绪，有两个来源，语义相反，只能靠客户端标记区分：
            --   1. RequestSnapshot()（isRerequest=true）—— 显式请求重推，必须应答。
            --      不应答的话客户端已把自己推回等待态，会一直等到 timeoutSec
            --      （默认 30s）才超时，而 IsWaiting() 是游戏收发增量的总闸，那段
            --      窗口里连接明明健康却双向停摆。
            --   2. onClientUpdate 的重试回声（isRerequest=false）—— 客户端只是还没
            --      收到快照#1（RTT > retrySec 时必然发生）。这一支**必须丢弃**：应答
            --      它会下发快照#2，而客户端收快照#1 时 clientWaiting_ 已置 false，
            --      快照#2 于是走「激活后重推」分支调 onApplySnapshot —— 同一个首次
            --      进入的玩家把 onFreshStart 与 onApplySnapshot 都跑了一遍，正好破坏
            --      本模块「两者只调一个」的契约。丢弃是安全的：快照#1 已在路上。
            if rerequestId then
                -- 同一条逻辑请求的重传带着同一个 id，只应答第一次。返回 true 而不是 false：
                -- 重复到达不是错误，客户端只是还没收到快照。
                if entry.lastRerequestId ~= rerequestId then
                    entry.lastRerequestId = rerequestId
                    -- 走 PushSnapshot 而不是 activate：不重复触发 onActivated、不重设 scene。
                    PlayerSessions.Server.PushSnapshot(entry.userId)
                end
                return true
            end
            return false
        end
    end
    return false
end

---@param userId integer
---@return PlayerSessionEntry|nil
function PlayerSessions.Server.Get(userId)
    return players_[normalizeUserId(userId)]
end

---@param userId integer
---@return any|nil
function PlayerSessions.Server.GetState(userId)
    local entry = players_[normalizeUserId(userId)]
    return entry and entry.state or nil
end

--- 用连接反查玩家。只做 lookup，绝不创建（identity 是客户端上报值）。
---@param connection Connection
---@return PlayerSessionEntry|nil
function PlayerSessions.Server.FromConnection(connection)
    if not connection then
        return nil
    end
    for _, entry in pairs(players_) do
        if entry.connection == connection then
            return entry
        end
    end
    return nil
end

--- 遍历全部玩家（含宽限期内的离线玩家）。顺序不保证。
---@param fn fun(entry: PlayerSessionEntry)
function PlayerSessions.Server.ForEach(fn)
    for _, entry in pairs(players_) do
        fn(entry)
    end
end

--- 只遍历在线玩家。**广播一律用这个**——宽限期内 connection 为 nil。
---@param fn fun(entry: PlayerSessionEntry, connection: Connection)
function PlayerSessions.Server.ForEachOnline(fn)
    for _, entry in pairs(players_) do
        if entry.connection then
            fn(entry, entry.connection)
        end
    end
end

---@return integer
function PlayerSessions.Server.Count()
    local n = 0
    for _ in pairs(players_) do
        n = n + 1
    end
    return n
end

---@return integer
function PlayerSessions.Server.CountOnline()
    local n = 0
    for _, entry in pairs(players_) do
        if entry.connection then
            n = n + 1
        end
    end
    return n
end

--- 主动重推快照（游戏改了权威状态、需要强制同步）。
--- 玩家离线或尚未就绪时返回 false，不排队。
---@param userId integer
---@return boolean sent
function PlayerSessions.Server.PushSnapshot(userId)
    local entry = players_[normalizeUserId(userId)]
    if not entry or not entry.connection or entry.awaitingReady then
        return false
    end
    entry.connection:SendRemoteEvent(serverCfg_.snapshotEvent, true, buildSnapshot(entry, true))
    return true
end

--- 解订阅 + 清表。给单测与脚本热切换用，正常游戏不需要调。
function PlayerSessions.Server.Shutdown()
    if serverSO_ then
        serverSO_:UnsubscribeFromAllEvents()
    end
    serverNode_ = nil
    serverSO_ = nil
    serverCfg_ = nil
    players_ = {}
end

-- ---------------------------------------------------------------------------
-- 客户端
-- ---------------------------------------------------------------------------

local clientCfg_ = nil
local clientNode_ = nil
local clientSO_ = nil
local clientLog_ = nil
local clientWaiting_ = false
local clientStartedAt_ = 0
local clientLastRetryAt_ = 0
local clientTimedOut_ = false
--- 当前待应答的逻辑消息是「重推请求」而非「就绪通知」。重发要沿用它，否则重发会被
--- 服务端当回声丢弃。收到快照即清零。
local clientRerequest_ = false
--- 当前待应答的重推请求 id（0 = 当前待应答的是就绪通知而非重推请求）。
--- 只在 RequestSnapshot 里 +1；重传沿用同一个值，服务端据此去重。
local clientReqId_ = 0
--- 服务端下发的本机认证 user_id（字符串）。首份快照抵达前为 nil。
local clientUserId_ = nil

-- 客户端必须先把 scene assign 给服务器连接，再上报就绪：服务端激活时会
-- connection.scene = scene 触发 LoadScene，客户端若尚未 assign scene，引擎会报
-- "Can not handle LoadScene message without an assigned scene"。
-- 这一步与上报就绪绑在一起、每次重发都做（幂等），不能只在 Setup 里做一次——
-- 连接晚于 Setup 建立时，一次性 assign 会永久丢失，而就绪重发照旧生效，
-- 于是服务端激活了一个没有 scene 的客户端，且不会自愈。
local function ensureSceneAssigned(connection)
    if not clientCfg_.scene then
        return
    end
    if connection.scene ~= clientCfg_.scene then
        connection.scene = clientCfg_.scene
    end
end

--- @param isRerequest boolean|nil 标记「正在（重）传的是哪条逻辑消息」，不是「是不是
---        第一次发」：Setup 发的是就绪通知，RequestSnapshot 发的是重推请求，而重发
---        必须沿用**当前那条**（见 clientRerequest_ / clientReqId_）。
---        写成「只有第一次 RequestSnapshot 带标记」会留个洞：那一发没送出去时，后续
---        重发变成未标记 → 被服务端当回声丢弃 → 客户端仍冻到 timeoutSec。
---        载荷里带的是**请求 id 而非 bool**，服务端才能把重传与新请求区分开去重。
local function sendReady(isRerequest)
    local connection = network:GetServerConnection()
    if not connection then
        return false
    end
    ensureSceneAssigned(connection)
    local payload = VariantMap()
    if isRerequest then
        payload[RE_REQUEST_FIELD] = Variant(clientReqId_)
    end
    connection:SendRemoteEvent(clientCfg_.readyEvent, true, payload)
    return true
end

local function onSnapshot(self, eventType, eventData)
    -- 身份要在最前面记：激活后的重推走下面的提前返回，也应刷新它。
    local uid = eventData[USER_ID_FIELD]
    if uid then
        clientUserId_ = uid:GetString()
    elseif not clientUserId_ then
        -- 只会在服务端用了旧版 helper（不下发该字段）时发生。记一笔而不是让游戏在
        -- GetUserId() 返回 nil 之后崩在 players[nil] 这类下游位置。
        clientLog_(_tr("t_jqbgHBtnk2k7KJBZ", USER_ID_FIELD)
            .. _tr("t_R5kgiqdcRHt7Vk2Q"))
    end

    if not clientWaiting_ then
        -- 激活后收到的重推：直接交给游戏，不再走首次/恢复分支。
        if clientCfg_.onApplySnapshot then
            clientCfg_.onApplySnapshot(eventData)
        end
        return
    end

    clientWaiting_ = false
    clientRerequest_ = false   -- 已收到快照，下一次重发（若有）不再是重推请求
    -- 保留字段缺失时按「首次」处理并记一笔：宁可让玩家走一次干净初始化，
    -- 也不要在 helper 里对 nil 取 :GetBool() 崩掉整个客户端。
    local restoreVariant = eventData[clientCfg_.restoreField]
    local isRestore = false
    if restoreVariant then
        isRestore = restoreVariant:GetBool()
    else
        clientLog_(_tr("t_s6mZfOfXrzYqTPlx", tostring(clientCfg_.restoreField)))
    end
    if isRestore then
        clientCfg_.onApplySnapshot(eventData)
    elseif clientCfg_.onFreshStart then
        -- 首次进入也把整个快照交给游戏：服务端在 isRestore=false 时同样跑了
        -- onBuildSnapshot，载荷里可能带首次才需要的权威分配（队伍、出生点、随机种子）。
        -- 早期版本这里不传参，导致游戏必须为「首次分配」另开一条远程事件。
        clientCfg_.onFreshStart(eventData)
    end
end

local function onClientUpdate(self, eventType, eventData)
    if not clientWaiting_ or clientTimedOut_ then
        return
    end
    local now = time.elapsedTime
    if now - clientStartedAt_ >= clientCfg_.timeoutSec then
        clientTimedOut_ = true
        if clientCfg_.onRestoreTimeout then
            clientCfg_.onRestoreTimeout(now - clientStartedAt_)
        else
            clientLog_(_tr("t_UQ4rlglRUE155eNv", string.format("%.0f", now - clientStartedAt_)))
        end
        return
    end
    -- 远程事件没有缓冲：服务端脚本就绪前抵达的就绪通知会被直接丢弃，所以要重发。
    -- 沿用 clientRerequest_：重发的是**当前那条**逻辑消息，标记不能在重发时丢掉。
    if now - clientLastRetryAt_ >= clientCfg_.retrySec then
        clientLastRetryAt_ = now
        sendReady(clientRerequest_)
    end
end

--- 注册快照事件、上报就绪、启动重试与超时兜底。
--- ⚠️ 必须在 Start() 的同步执行流里调用。
---@param config table
function PlayerSessions.Client.Setup(config)
    assert(type(config) == "table", _tr("t_LldWn8rQLG8wLJjy"))
    assert(type(config.onApplySnapshot) == "function", _tr("t_OWMdIoTOOiQMs5Ie"))
    -- 归一化会往 config 里写键，所以校验必须在那之前
    rejectUnknownKeys(config, CLIENT_KEYS, "PlayerSessions.Client.Setup")
    if network and network.serverRunning then
        error("PlayerSessions.Client 不能在服务端使用，请用 PlayerSessions.Server")
    end

    clientCfg_ = config
    clientCfg_.readyEvent = config.readyEvent or PlayerSessions.PROTOCOL.readyEvent
    clientCfg_.snapshotEvent = config.snapshotEvent or PlayerSessions.PROTOCOL.snapshotEvent
    clientCfg_.restoreField = config.restoreField or PlayerSessions.PROTOCOL.restoreField
    clientCfg_.timeoutSec = config.timeoutSec or 30.0
    -- 钳到下限：retrySec 低于 RTT 时会产生重发风暴，服务端每条都要去重，而历史上
    -- 「回声被当成新请求」的两个 bug 触发条件都是它被调到 RTT 以下。
    clientCfg_.retrySec = math.max(config.retrySec or 1.0, MIN_RETRY_SEC)
    clientLog_ = makeLogger(config.log)

    network:RegisterRemoteEvent(clientCfg_.snapshotEvent)

    -- config.scene 的 assign 由 sendReady() 负责（见 ensureSceneAssigned），
    -- 所以这里不做——连接可以晚于 Setup 建立，重试循环会一并补上。

    clientNode_ = Node()
    clientSO_ = clientNode_:CreateScriptObject("LuaScriptObject")
    clientSO_:SubscribeToEvent(clientCfg_.snapshotEvent, onSnapshot)
    clientSO_:SubscribeToEvent("Update", onClientUpdate)

    clientWaiting_ = true
    clientTimedOut_ = false
    clientRerequest_ = false   -- Setup 发的是就绪通知，不是重推请求
    clientStartedAt_ = time.elapsedTime
    clientLastRetryAt_ = clientStartedAt_

    -- 仅 UI 提示：这是大厅的本地推断，权威判定看服务端下发的 restoreField。
    if config.onRestoreBegin and network:IsReconnectSession() then
        config.onRestoreBegin()
    end

    sendReady()
    return PlayerSessions
end

---@return boolean 尚未收到服务端权威激活
function PlayerSessions.Client.IsWaiting()
    return clientWaiting_
end

--- ⚠️ 仅供 UI 文案：大厅的本地推断，可能与服务端判定分叉。
--- 玩家状态是恢复还是重建，一律看 onApplySnapshot / onFreshStart 哪个被调用。
---@return boolean
function PlayerSessions.Client.IsReconnectHint()
    return network:IsReconnectSession()
end

---@return string 后台匹配下可能为空串，不要用它判断是否重连
function PlayerSessions.Client.GetSessionId()
    return network:GetSessionId()
end

--- 本机的**认证** user_id（字符串）。服务端在每份快照里下发，首份快照抵达前为 nil。
--- 广播必须靠它做归属判断：服务端把任意玩家的变化发给所有在线玩家，无条件应用会把
--- 别人的状态写进自己的显示。客户端读不到 identity，这是唯一途径。
---@return string|nil
function PlayerSessions.Client.GetUserId()
    return clientUserId_
end

--- 立刻重发一次就绪，请求服务端重推权威快照（例如 UI 上的「重试」按钮）。
--- 已激活后调用也有效：服务端 NotifyClientReady 会走 PushSnapshot 应答，
--- 客户端随后照常收到快照并触发 onApplySnapshot。
--- 若超时（onRestoreTimeout）后快照仍然抵达，onApplySnapshot / onFreshStart 会照常
--- 触发——重试 UI 可以在那里收回，helper 不代为管理它。
---@return boolean sent 仅表示「就绪已发出」（连接存在）；不代表服务端已重推快照
function PlayerSessions.Client.RequestSnapshot()
    if not clientCfg_ then
        return false
    end
    -- 不变式：**同时最多一条未应答的消息**——它可能是 Setup 发出的就绪通知，也可能是
    -- 一条重推请求；clientWaiting_ 跟踪这唯一的等待位，clientReqId_ 只命名后者。
    -- 所以只在「等待位为空」时才开新请求；等待中再调一律算**重传当前那条**：
    -- 超时后玩家连点重试（超时分支只置 clientTimedOut_、不清 clientWaiting_）、
    -- 以及 Setup 后一个 RTT 内调本函数，都走这条路。
    -- 判据不能写成「没有未应答的**重推请求**」：Setup 结束时恰好是 clientWaiting_=true
    -- 且 clientRerequest_=false，那样会放行并开出第二条消息。两条都是 RELIABLE_ORDERED，
    -- 服务端必然先处理无 id 那条（awaitingReady → activate → 快照#1），随后带 id 那条
    -- 因 awaitingReady 已假而走重推分支 → 快照#2；客户端只有一个等待位，快照#1 清零后
    -- 快照#2 落到非等待分支 → 首次进入的玩家把 onFreshStart 与 onApplySnapshot 都跑一遍。
    if not clientWaiting_ then
        clientReqId_ = clientReqId_ + 1
        -- 置位而不是只在这一发带上标记：这一发可能因当下无连接而没送出去（sendReady
        -- 返回 false），后续重发必须仍然带标记，否则会被服务端当回声丢弃。
        clientRerequest_ = true
    end
    clientTimedOut_ = false
    clientStartedAt_ = time.elapsedTime
    clientLastRetryAt_ = clientStartedAt_
    clientWaiting_ = true
    return sendReady(clientRerequest_)
end

--- 解订阅。大厅级重连会重建整个 Lua 状态，通常不必手动调。
function PlayerSessions.Client.Shutdown()
    if clientSO_ then
        clientSO_:UnsubscribeFromAllEvents()
    end
    clientNode_ = nil
    clientSO_ = nil
    clientCfg_ = nil
    clientWaiting_ = false
    clientRerequest_ = false
    clientUserId_ = nil
end

return PlayerSessions
