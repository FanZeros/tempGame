-- LobbyBootstrap.lua — Runtime 侧锁死核心引导（C++ 固定入口）。
--
-- C++ 在多人大厅阶段于 Runtime state 跑 require('urhox-libs.GameLobby.Runtime-hide.LobbyBootstrap').start()；
-- 返回大厅（ReturnToLobby）经脚本切换走全局 Start()。两条路都进 M.start。
--
-- 职责（结构护栏，见 docs/design/custom-lobby-isolation.md §6）：
--   1. 桥私有化：把全局 lobbyBridge 收为 local 并置 nil，注入 LobbyClient；
--      同时清掉 systemNotificationBridge 原始句柄，仅保留 SystemNotification 模块封装。
--   2. 建专属大厅 UI root，挂到 UI 根，切脚本或退出时整树回收。
--   3. 读 settings.json 的 multiplayer.lobby_runtime 选入口脚本（默认内置 LobbyRuntimeUI）。
--   4. pcall 加载入口并注入 ctx={client, root}；失败回退默认入口。
--
-- 入口契约：入口脚本 return function(ctx)，ctx={client, root}，返回 { stop=fun()|nil }。
-- 默认入口（模板路径）与项目自定义入口（完全自建）同一套契约。

local UI = require("urhox-libs.UI")
local LobbyClient = require("urhox-libs.GameLobby.Runtime-hide.LobbyClient")
local LegacyGate = require("urhox-libs.GameLobby.Runtime-hide.LegacyGate")
local SystemNotification = require("urhox-libs.System.SystemNotification")

local M = {}

-- 内置默认入口（模板路径）：未配 / 配置无效 / 自定义入口崩溃时的兜底。
local DEFAULT_ENTRY = "urhox-libs/GameLobby/Runtime/Template/LobbyRuntimeUI.lua"

local function logError(msg)
    msg = "[LobbyBootstrap] " .. tostring(msg)
    if log and LOG_ERROR then log:Write(LOG_ERROR, msg) else print(msg) end
end

-- 规范化用户配置的入口脚本路径，返回 cache 查找路径（去 scripts/ 前缀）；非法返回 nil。
-- 支持 scripts/ 前缀或相对脚本目录；禁止 ..、绝对路径和含冒号路径，且必须是 .lua。
local function normalizeEntryPath(path)
    if type(path) ~= "string" then return nil end
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then return nil end
    path = path:gsub("\\", "/")
    while path:sub(1, 2) == "./" do path = path:sub(3) end

    local hasParentSegment = path == ".." or path:match("^%.%./") ~= nil or
        path:match("/%.%./") ~= nil or path:match("/%.%.$") ~= nil
    local invalid =
        path:sub(1, 1) == "/" or
        path:find(":", 1, true) ~= nil or
        hasParentSegment or
        path:sub(-4) ~= ".lua"
    if invalid then
        logError(_tr("t_y8dmEVkYyKhW6UAe", tostring(path)))
        return nil
    end

    if path:sub(1, 8) == "scripts/" then return path:sub(9) end
    return path
end

-- 读 settings.json 的 multiplayer.lobby_runtime（Runtime state 经 cache 同步读）。
local function readLobbyRuntimeSetting()
    if not (cache and cache.GetFile and cjson) then return nil end
    local f = cache:GetFile("settings.json")
    if not f then return nil end
    local lines = {}
    while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
    f:Close()
    local ok, j = pcall(cjson.decode, table.concat(lines, "\n"))
    if ok and type(j) == "table" and type(j.multiplayer) == "table" then
        return j.multiplayer.lobby_runtime
    end
    return nil
end

-- 加载入口脚本（完整引擎环境，非沙箱），返回它 return 的 function(ctx)；失败返回 nil, err。
local function loadEntry(path)
    if not (cache and cache.Exists and cache:Exists(path)) then
        return nil, "entry not found: " .. tostring(path)
    end
    local f = cache:GetFile(path)
    if not f then return nil, "cache:GetFile failed: " .. tostring(path) end
    local lines = {}
    while not f:IsEof() do lines[#lines + 1] = f:ReadLine() end
    f:Close()
    local chunk, err = load(table.concat(lines, "\n"), "@" .. path, "t")
    if not chunk then return nil, "compile error in " .. path .. ": " .. tostring(err) end
    local ok, ret = pcall(chunk)
    if not ok then return nil, "runtime error in " .. path .. ": " .. tostring(ret) end
    if type(ret) ~= "function" then
        return nil, "entry did not return function(ctx): " .. tostring(path)
    end
    return ret
end

-- 建专属大厅 UI root（挂到 UI 根；I5 整树回收）。
local function buildRoot()
    if not UI.GetNVGContext() then
        UI.Init({ scale = function() return math.max(graphics.height / 1080, 0.4) end })
    end
    local root = UI.SafeAreaView {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0, edges = "all",
    }
    local uiRoot = UI.GetRoot()
    if uiRoot then uiRoot:AddChild(root) else UI.SetRoot(root) end
    return root
end

--- 启动 Runtime 大厅引导。
--- @param deps table|nil 测试注入：{ bridge, client, root, entryPath, makeEntry, makeDefaultEntry }
--- @return table client
function M.start(deps)
    deps = deps or {}

    -- 旧版大厅整体跑在 Host 侧（origin/main 行为）：Runtime 不建 UI、不接桥，直接退出。
    if deps.legacy == true or LegacyGate.IsLegacyEnabled() then
        lobbyBridge = nil  -- I4：legacy 空转也不在 Runtime 侧留桥全局
        systemNotificationBridge = nil
        return nil
    end

    -- 桥私有化（I4）：捞成 local 后置 nil，注入 client；制作人脚本运行前全局已清空。
    local bridge = deps.bridge or lobbyBridge
    lobbyBridge = nil
    systemNotificationBridge = nil

    local client = deps.client or LobbyClient.New(bridge)
    local root = deps.root or buildRoot()
    local ctx = { client = client, root = root }

    -- 先注册旧 OnSystemDialog 的兼容 handler。
    -- 用户随后调用 SystemNotification.RegisterHandler 时，单槽注册会覆盖它。
    SystemNotification.RegisterHandler(function(info)
        if type(client._DispatchLegacySystemDialog) ~= "function" then
            return false
        end
        return client:_DispatchLegacySystemDialog(info)
    end)

    local runtimeReadySent = false
    local function markRuntimeReady()
        if runtimeReadySent then return end
        runtimeReadySent = true
        if SendEvent and VariantMap then
            SendEvent("LobbyRuntimeReady", VariantMap())
        end
    end

    -- 调用一个入口函数：pcall 兜底，成功存实例并返回 true。
    local function dispatch(entryFn, label)
        local ok, inst = pcall(entryFn, ctx)
        if ok then
            M._instance = inst
            return true
        end
        logError(_tr("t_PEPIW61KPQXikt5Y", tostring(label), tostring(inst)))
        return false
    end

    -- 解析主入口：deps.makeEntry（测试）> deps.entryPath > settings.json > 默认入口。
    local primaryFn, primaryLabel
    if deps.makeEntry then
        primaryFn, primaryLabel = deps.makeEntry, "<inject>"
    else
        local path = deps.entryPath or normalizeEntryPath(readLobbyRuntimeSetting()) or DEFAULT_ENTRY
        local fn, err = loadEntry(path)
        primaryLabel = path
        if fn then
            primaryFn = fn
        else
            logError(_tr("t_US1AngW2U1MZxvRc", tostring(err)))
        end
    end

    local dispatched = primaryFn and dispatch(primaryFn, primaryLabel) or false

    -- 回退默认入口（I3）：主入口加载 / 运行失败、且它本就不是默认入口时。
    if not dispatched and primaryLabel ~= DEFAULT_ENTRY then
        local defFn, err = deps.makeDefaultEntry, nil
        if not defFn then defFn, err = loadEntry(DEFAULT_ENTRY) end
        if defFn then
            if not dispatch(defFn, DEFAULT_ENTRY) then
                logError(_tr("t_5alwoDyM55M06yeS"))
            end
        else
            logError(_tr("t_esGNAoDKezYlLXiu", tostring(err)))
        end
    end

    -- 无论主入口 / 默认入口成功还是失败，Host 都必须获得一次最终通知机会。
    markRuntimeReady()

    M._client = client
    M._root = root
    return client
end

-- 脚本入口：C++ 切脚本（ReturnToLobby）重建 Runtime VM 后调全局 Start。
function Start()
    M.start()
end

function Stop()
    local instance = M._instance
    M._instance = nil
    if type(instance) ~= "table" or type(instance.stop) ~= "function" then return end

    local ok, err = pcall(instance.stop)
    if not ok then logError(_tr("t_biqWgQKgbuuJOf6C", tostring(err))) end
end

return M
