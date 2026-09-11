---@meta
-- EmmyLua 类型定义：lobby_ui.lua 沙箱 API
-- 仅在 IDE 侧生效，不在运行时加载。

-- ============================================================================
-- Control style
-- ============================================================================

---@class LobbyControlStyle
---@field background string|table  背景色（十六进制字符串或 {r,g,b,a} 表）
---@field color string|table       文字色
---@field borderColor string|table 边框色
---@field fontSize number          字号（基础像素）
---@field fontWeight string        字重（"normal"/"bold"）
---@field fontColor string|table   字体颜色
---@field width number             宽（基础像素）
---@field height number            高（基础像素）
---@field padding number           内边距（四边统一）
---@field paddingTop number
---@field paddingBottom number
---@field paddingLeft number
---@field paddingRight number
---@field margin number            外边距（四边统一）
---@field marginTop number
---@field marginBottom number
---@field marginLeft number
---@field marginRight number
---@field borderRadius number      圆角半径
---@field borderWidth number       边框宽
---@field opacity number           透明度（0~1）
---@field flexDirection string     "row"/"column"
---@field alignItems string        "flex-start"/"center"/"flex-end"/"stretch"
---@field justifyContent string    "flex-start"/"center"/"flex-end"/"space-between"/"space-around"
---@field gap number               子控件间距

-- ============================================================================
-- Control proxy
-- ============================================================================

---@class LobbyControl
---@field text string              控件主文案（Button 标签、Label 文本等）
---@field icon string              图标路径，相对于 assets/（如 "assets/ui/icons/search.png"）
---@field visible boolean          是否可见
---@field opacity number           透明度（0~1）
---@field style LobbyControlStyle  样式代理（写入触发 Widget:SetStyle）

--- 添加子控件（urhox-libs/UI 控件，如 UI.Panel / UI.Label / UI.Button）。
---@param child any
function LobbyControl:addChild(child) end

--- 清空全部子控件。
function LobbyControl:clearChildren() end

-- ============================================================================
-- Screen proxies
-- ============================================================================

---@class LobbyMainScreen
---@field background LobbyControl
---@field browse_button LobbyControl
---@field create_button LobbyControl
---@field quick_match_button LobbyControl

---@class LobbyRoomListScreen
---@field background LobbyControl
---@field refresh_button LobbyControl
---@field back_button LobbyControl

---@class LobbyRoomWaitingScreen
---@field background LobbyControl
---@field start_button LobbyControl
---@field leave_button LobbyControl

---@class LobbyQuickMatchWaitingScreen
---@field background LobbyControl
---@field status_text LobbyControl
---@field cancel_button LobbyControl

-- ============================================================================
-- LobbyUI global
-- ============================================================================

---@class LobbyUITable
---@field main LobbyMainScreen
---@field room_list LobbyRoomListScreen
---@field room_waiting LobbyRoomWaitingScreen
---@field quick_match_waiting LobbyQuickMatchWaitingScreen

---@type LobbyUITable
LobbyUI = {}

-- ============================================================================
-- LobbyState global
-- ============================================================================

---@class LobbyMatchmakingState
---@field status "idle"|"searching"|"found"
---@field elapsed number  当前匹配已等待时长（秒，仅 searching 状态累加）

---@class LobbyRoomState
---@field players { nickname: string, avatar: string }[]
---@field title string|nil 房间标题（"#id 名称" 格式，进入 room_waiting 时由框架写入）

---@class LobbySelfState
---@field nickname string

---@class LobbyStateTable
---@field screen "main"|"room_list"|"room_waiting"|"quick_match_waiting"|"connecting"|nil
---@field matchmaking LobbyMatchmakingState
---@field room LobbyRoomState
---@field self LobbySelfState
---@field connecting { progress: number, status: string }

--- 只读视图状态：直接写 `LobbyState.x = v` 或 `LobbyState.room.title = v` 都会报错。
--- 状态随大厅事件刷新；需要改变大厅行为时请调用 `Lobby.*` 动作，而不是改状态表。
---@type LobbyStateTable
LobbyState = {}

-- ============================================================================
-- Lobby：动作 + 界面注册
-- ============================================================================

--- 单个界面的视觉与回调定义（整屏替换：DefineScreen 后即完全拥有该界面）。
---@class LobbyScreenDef
---@field enter fun()                                   进入界面时构建视觉（必填）
---@field update fun(dt:number)                         每帧（可选）
---@field onRoomList fun(rooms:table[])                 仅 room_list：房间列表刷新（可选）
---@field onRoomPlayers fun(players:table[], masterId:integer)  仅 room_waiting：房间人员变化（可选）
---@field onMatchmaking fun(status:"idle"|"searching"|"found") 仅 quick_match_waiting：匹配状态（可选）
---@field onServerProgress fun(progress:number, status:string) 仅 connecting：连服进度变化（可选）

---@class Lobby
Lobby = {}

--- 注册/覆盖一个界面。未注册的界面沿用引擎默认模板。
---@param name "main"|"room_list"|"room_waiting"|"quick_match_waiting"|"connecting"
---@param def LobbyScreenDef
function Lobby.DefineScreen(name, def) end

---@class LobbyDialogContext
---@field kind "dialog"|"kicked"|"error"|"system"|string 当前弹窗类型
---@field sourceKind "dialog"|"kicked"|"error"|"system"|string 原始弹窗类型
---@field title string|nil 标题
---@field message string|nil 正文
---@field icon string|nil 图标/符号
---@field buttonText string|nil 按钮文案
---@field mount fun(widget:any):any 把自定义弹窗根控件挂到大厅 UI 根节点
---@field close fun() 关闭当前弹窗；若调用方提供了关闭回调，则在关闭后执行该回调

---@class LobbyDialogDef
--- 渲染弹窗；返回 false 可交回默认弹窗兜底。务必保证用户能触发 ctx.close()（按钮/✕）：
--- toast 类只靠 Timer 自动消失不可靠（大厅销毁/切场景时定时器停摆），需留手动关闭入口。
---@field show fun(ctx:LobbyDialogContext):boolean|nil

--- 注册/覆盖一种弹窗视觉。未注册或回调报错时沿用引擎默认弹窗。
---@param kind "dialog"|"kicked"|"error"|"system"|string
---@param def LobbyDialogDef|fun(ctx:LobbyDialogContext):boolean|nil
function Lobby.DefineDialog(kind, def) end

--- 运营配置，按只读对待：仅供读取展示（allowQuickMatch/allowBrowseRooms/allowCreateRoom/
--- maxPlayers/mapName/mode 等）。请勿写入——建房/匹配由框架用运营原值发起，写 config 不会
--- 改变实际建房/匹配行为；运营限制以服务端校验为准（客户端不可信）。
---@type table
Lobby.config = {}

---@return integer
function Lobby.GetMyUserId() end
--- 异步查询昵称。opts: { userIds=integer[], onSuccess=fun(nicknames), onError=fun(code) }
---@param opts table
function Lobby.GetUserNickname(opts) end
---@return integer
function Lobby.GetMaxPlayers() end
---@return string
function Lobby.GetProjectId() end
---@return boolean
function Lobby.IsOnline() end
---@return boolean
function Lobby.IsInRoom() end
---@return boolean
function Lobby.IsMatching() end

--- 导航 + 业务动作（触发引擎托管的大厅流程）。
function Lobby.QuickMatch() end
function Lobby.CancelMatch() end
function Lobby.BrowseRooms() end
function Lobby.CreateRoom() end
---@param roomId integer
---@param maxPlayers integer
function Lobby.JoinRoom(roomId, maxPlayers) end
function Lobby.LeaveRoom() end
function Lobby.StartGame() end
function Lobby.RefreshRoomList() end
function Lobby.GotoMain() end
function Lobby.Exit() end

-- ============================================================================
-- Timer global
-- ============================================================================

---@class TimerAPI
Timer = {}

--- 一次性定时器，ms 毫秒后调用 fn。返回 handle 可用于 cancel。
---@param ms number
---@param fn fun()
---@return integer handle
function Timer.after(ms, fn) end

--- 重复定时器，每 ms 毫秒调用一次 fn。返回 handle 可用于 cancel。
---@param ms number
---@param fn fun()
---@return integer handle
function Timer.every(ms, fn) end

--- 取消定时器。
---@param handle integer
function Timer.cancel(handle) end

