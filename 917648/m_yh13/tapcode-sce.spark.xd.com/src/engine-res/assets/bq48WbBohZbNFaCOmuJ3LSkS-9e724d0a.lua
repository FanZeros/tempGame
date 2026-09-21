-- SystemNotification.lua - Lobby / Game Runtime system-notification registration API.
--
-- A Runtime registers one handler and dispatches different notifications by info.id. Returning
-- true means the Runtime accepted responsibility for displaying the notification. Missing
-- handlers, false/nil returns, and handler errors are reported as unhandled so HostSandbox
-- can use its Host-side fallback UI. Runtime-hide installs the legacy OnSystemDialog adapter
-- as the initial handler; a user RegisterHandler call replaces that adapter.

---@alias SystemNotificationId
---| "DisconnectChecking"
---| "Reconnecting"
---| "ConnectFailedRetry"
---| "ConnectInitiateFailed"
---| "MiddleGameJoinFailed"
---| "DuplicateLogin"
---| "ResourceExceeded"
---| "GameOpsKick"
---| "Kicked"
---| "VersionTooLow"
---| "PlayerBanned"

---@class SystemNotificationInfo
---@field id SystemNotificationId
---@field reason string|nil Only for Kicked: operator-supplied kick text.
---@field exitOnClose boolean|nil Optional caller-owned close behavior for dialogs.

local M = {
    ---@type table<string, SystemNotificationId>
    Id = {
        DisconnectChecking = "DisconnectChecking",
        Reconnecting = "Reconnecting",
        ConnectFailedRetry = "ConnectFailedRetry",
        ConnectInitiateFailed = "ConnectInitiateFailed",
        MiddleGameJoinFailed = "MiddleGameJoinFailed",
        DuplicateLogin = "DuplicateLogin",
        ResourceExceeded = "ResourceExceeded",
        GameOpsKick = "GameOpsKick",
        Kicked = "Kicked",
        VersionTooLow = "VersionTooLow",
        PlayerBanned = "PlayerBanned",
    },
}

-- 与 id 一一对应的默认展示。Dispatch 不传这些字段。
-- kind: error=Toast，kicked=被踢窗，dialog=普通模态。
M.Default = {
    DisconnectChecking = {
        kind = "error",
        title = _tr("t_TPUpz0Q6TsBETGpE"),
        message = _tr("t_16fskayFN16BpvrdU8"),
    },
    Reconnecting = {
        kind = "error",
        title = _tr("t_UHBCdqeLUOTaGp8N"),
        message = _tr("t_4t4FTKWN4R42yEb8"),
    },
    ConnectFailedRetry = {
        kind = "error",
        title = _tr("t_1BQcH3mid1BETnljTN"),
        message = _tr("t_1BjsfhBO01CDKZQdPZ"),
    },
    ConnectInitiateFailed = {
        kind = "error",
        title = _tr("t_KjFOoDMFL9tzHDtx"),
        message = _tr("t_wNkidD49wUyQSZ9v"),
    },
    MiddleGameJoinFailed = {
        kind = "error",
        title = _tr("t_sfvjFktLsYhz78Jd"),
        message = _tr("t_axnZJO1PbSNSsWfN"),
    },
    DuplicateLogin = {
        kind = "kicked",
        title = _tr("t_hF2C5hH2hQxc9Z1y"),
        message = _tr("t_OGvsHNbNNlsLKYwt"),
    },
    ResourceExceeded = {
        kind = "kicked",
        title = _tr("t_tX3RnT6dt6Otrp4D"),
        message = _tr("t_h9xNSvRqhabw0roi"),
    },
    GameOpsKick = {
        kind = "kicked",
        title = _tr("t_BKCWQCBWBpcQJeb6"),
        message = _tr("t_1fuqLApu1Yh8UVlE"),
    },
    Kicked = {
        kind = "kicked",
        title = _tr("t_TPUpz0Q6TsBETGpE"),
        message = _tr("t_QPwrRVA0QXOnlh98"),
    },
    VersionTooLow = {
        kind = "dialog",
        title = _tr("t_nWNYw5ZIndv2Qass"),
        message = _tr("t_15flMrxkP15rgSmPjH"),
        exitOnClose = true,
    },
    PlayerBanned = {
        kind = "dialog",
        title = _tr("t_169MBn8PQ16em6Gp1K"),
        message = _tr("t_8fBGgKN08EbME96K"),
    },
}

--- 用 id 还原默认 title / message。Kicked.reason 原样带回，文案由 UI 拼。
---@param info SystemNotificationInfo|nil
---@return table
function M.Resolve(info)
    info = info or {}
    local spec = M.Default[info.id] or {}
    local reason = info.reason
    if type(reason) ~= "string" or reason == "" then
        reason = nil
    end
    return {
        id = info.id,
        kind = spec.kind,
        title = spec.title,
        message = spec.message,
        reason = reason,
        exitOnClose = info.exitOnClose == true or spec.exitOnClose == true,
    }
end

local bridge_ = rawget(_G, "systemNotificationBridge")
local handler_ = nil

local function writeError(message)
    if log and LOG_ERROR then
        log:Write(LOG_ERROR, "[SystemNotification] " .. tostring(message))
    else
        print("[SystemNotification] " .. tostring(message))
    end
end

local function dispatch(payloadJson)
    local decodeOk, info = pcall(cjson.decode, payloadJson or "")
    if not decodeOk or type(info) ~= "table" then
        writeError("invalid payload: " .. tostring(info))
        return false
    end

    if not handler_ then
        return false
    end

    local callOk, handled = pcall(handler_, info)
    if not callOk then
        writeError("handler failed: " .. tostring(handled))
        return false
    end
    return handled == true
end

--- Register the only system-notification handler for the current Game Runtime.
---@param handler fun(info:SystemNotificationInfo):boolean|nil
function M.RegisterHandler(handler)
    assert(type(handler) == "function", "SystemNotification handler must be a function")
    handler_ = handler
    if bridge_ and bridge_.setHandler then
        bridge_:setHandler(dispatch)
    else
        writeError("bridge is unavailable; Runtime binary may be older than this urhox-libs")
    end
end

function M.UnregisterHandler()
    handler_ = nil
    if bridge_ and bridge_.setHandler then
        bridge_:setHandler(nil)
    end
end

--- Dispatch a system notification to the currently registered handler.
--- Both HostSandbox and Game Runtime may produce notifications through this API.
---@param info SystemNotificationInfo
---@return boolean handled
function M.Dispatch(info)
    if not (bridge_ and bridge_.dispatch) then
        return false
    end

    local encodeOk, payloadJson = pcall(cjson.encode, info or {})
    if not encodeOk then
        writeError("encode failed: " .. tostring(payloadJson))
        return false
    end

    local dispatchOk, handled = pcall(bridge_.dispatch, bridge_, payloadJson)
    if not dispatchOk then
        writeError("dispatch failed: " .. tostring(handled))
        return false
    end
    return handled == true
end

return M
