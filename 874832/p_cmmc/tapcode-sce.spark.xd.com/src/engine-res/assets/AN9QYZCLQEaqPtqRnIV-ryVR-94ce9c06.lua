--[[
urhox-libs/Lobby - 游戏大厅库

提供开箱即用的游戏大厅功能：
- 完整的 UI 组件（一行代码启动）
- 房间创建、加入、离开
- 自动匹配系统
- 游戏启动和连接
- 统一的事件回调管理

用法1 - 完整 UI（推荐）:
    local LobbyUI = require("urhox-libs.Lobby.LobbyUI")
    LobbyUI.Show()

用法2 - 使用 API:
    local Lobby = require("urhox-libs.Lobby")
    local lobbyMgr = Lobby.new()

用法3 - 直接使用 LobbyManager:
    local LobbyManager = require("urhox-libs.Lobby.LobbyManager")
    local lobbyMgr = LobbyManager.new()
]]

local LobbyManager = require("urhox-libs.Lobby.LobbyManager")

-- 默认导出 LobbyManager（保持向后兼容）
return LobbyManager
