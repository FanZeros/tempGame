---@meta
-- EmmyLua 类型定义：自定义大厅制作人接口（LobbyClient）。
-- 仅在 IDE 侧生效，不在运行时加载。
--
-- 入口约定（完全自建路径）：项目自定义 Runtime 入口脚本（由 settings.json 的
-- multiplayer.lobby_runtime 指定）返回一个函数，引擎引导层注入 ctx 调用它：
--   return function(ctx)
--       local client = ctx.client   -- LobbyClient，本文件全部接口都在它上面
--       local root   = ctx.root     -- 引擎托管的大厅 UI 根：UI 挂这里，退出 / 切游戏自动整树回收
--       return { stop = function() end }   -- stop 可选，主动清理
--   end

-- ============================================================================
-- 数据形状（回调载荷）
-- ============================================================================

---@class LobbyPlayer
---@field userId integer
---@field nickname string
---@field avatar string

---@class LobbyRoomInfo
---@field id integer          房间号（JoinRoom 用它）
---@field name string         房间名
---@field status integer      1=等待中 2=匹配中 3=游戏中
---@field ownerId integer     房主 id
---@field playerCount integer 当前人数
---@field maxPlayers integer  最大人数
---@field latency integer     延迟(ms)

---@class LobbyNickname
---@field userId integer
---@field nickname string

---@class LobbySystemDialog
---@field kind "error"|"kicked"|"dialog" 平台弹窗类型
---@field title string|nil
---@field message string|nil
---@field buttonText string|nil
---@field icon string|nil

-- ============================================================================
-- 动作 opts（内联回调：一个动作会引发的后续事件，回调都写在这里）
-- ============================================================================

---@class LobbyMatchOpts
---@field onStarted fun()|nil                          已开始匹配（回执）
---@field onError fun(code:integer, message:string|nil)|nil                发起失败 / 匹配失败
---@field onMatchFound fun(serverInfo:table)|nil       匹配成功 → 切「连接中」界面
---@field onProgress fun(progress:number, status:string)|nil  之后平台自动连服的进度，progress 0..1

---@class LobbyStartGameOpts
---@field onStarted fun()|nil                          已开始（回执）
---@field onError fun(code:integer, message:string|nil)|nil
---@field onMatchFound fun(serverInfo:table)|nil
---@field onProgress fun(progress:number, status:string)|nil

---@class LobbyCreateRoomOpts
---@field onCreated fun(roomId:integer)|nil            房间已创建（回执）
---@field onError fun(code:integer, message:string|nil)|nil
---@field onPlayersChanged fun(players:LobbyPlayer[], masterId:integer)|nil 进房后人员变化（持续）
---@field onKicked fun()|nil                           房间非主动结束（被踢 / 解散）

---@class LobbyJoinRoomOpts
---@field roomId integer                               要加入的房间号
---@field onJoined fun()|nil                           已加入房间（回执）
---@field onError fun(code:integer, message:string|nil)|nil
---@field onPlayersChanged fun(players:LobbyPlayer[], masterId:integer)|nil
---@field onKicked fun()|nil

---@class LobbyLeaveRoomOpts
---@field onLeft fun()|nil                             已离开房间（回执）
---@field onError fun(code:integer, message:string|nil)|nil

---@class LobbyRoomListOpts
---@field onSuccess fun(rooms:LobbyRoomInfo[])|nil      房间列表返回（纯查询）
---@field onError fun(code:integer, message:string|nil)|nil

---@class LobbyNicknameOpts
---@field userIds integer[]                            要查的 userId 列表
---@field onSuccess fun(nicknames:LobbyNickname[])|nil  昵称返回（纯查询）
---@field onError fun(code:integer, message:string|nil)|nil

-- ============================================================================
-- LobbyClient
-- ============================================================================

---@class LobbyClient
local LobbyClient = {}

-- ---- 同步只读（即时返回）----

---@return integer
function LobbyClient:GetMyUserId() end
---@return integer
function LobbyClient:GetMaxPlayers() end
---@return string
function LobbyClient:GetProjectId() end
---@return boolean
function LobbyClient:IsOnline() end
---@return boolean 缓存（由平台 state 推送更新）
function LobbyClient:IsInRoom() end
---@return boolean 缓存
function LobbyClient:IsMatching() end

-- ---- 动作（发起即返回，结果走 opts 里的回调）----

--- 快速匹配。
---@param opts LobbyMatchOpts
function LobbyClient:StartMatch(opts) end

--- 房主开始游戏（链路同 StartMatch）。
---@param opts LobbyStartGameOpts
function LobbyClient:StartGame(opts) end

--- 创建房间。
---@param opts LobbyCreateRoomOpts
function LobbyClient:CreateRoom(opts) end

--- 加入房间。
---@param opts LobbyJoinRoomOpts
function LobbyClient:JoinRoom(opts) end

--- 离开房间。
---@param opts LobbyLeaveRoomOpts|nil
function LobbyClient:LeaveRoom(opts) end

--- 取消匹配（无回执；IsMatching() 随后转 false）。
function LobbyClient:CancelMatch() end

--- 拉取房间列表。
---@param opts LobbyRoomListOpts
function LobbyClient:GetRoomList(opts) end

--- 异步查询昵称。
---@param opts LobbyNicknameOpts
function LobbyClient:GetUserNickname(opts) end

-- ---- 平台主动推送（独立订阅，无触发动作；cb=nil 即注销）----

--- 平台错误兜底（与某次调用无关的异步错误）。
---@param cb fun(errorType:string, errorCode:integer)|nil
function LobbyClient:OnError(cb) end

--- 旧版系统弹窗订阅。新项目请优先 `urhox-libs.System.SystemNotification.RegisterHandler`。
--- 未注册新版 handler 时，平台仍会把未接管的弹窗以旧载荷推到这里。
---@param cb fun(dialog:LobbySystemDialog)|nil
function LobbyClient:OnSystemDialog(cb) end

-- ============================================================================
-- 入口 ctx
-- ============================================================================

---@class LobbyCtx
---@field client LobbyClient 大厅客户端
---@field root any          引擎托管的大厅 UI 根（挂 UI；退出 / 切游戏自动回收）

---@class LobbyEntryResult
---@field stop fun()|nil    主动清理（可选；不写引擎也会回收 root）
