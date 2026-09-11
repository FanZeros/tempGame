-- LobbyRuntimeUI.lua — Runtime 侧默认大厅入口（模板路径）。
--
-- 由 引擎引导层 选中并注入 ctx={client, root} 调用——未配 multiplayer.lobby_runtime（或配置无效 /
-- 自定义入口崩溃回退）时的内置默认入口。职责：把 client 注入 LobbyUI 框架、复用引擎专属 root、
-- 向引擎平台要一次 UI 配置后 Show 渲染。
--
-- 完全自建路径不走本文件：项目用 multiplayer.lobby_runtime 指定自己的入口脚本，直接拿 ctx 自造 UI。
--
-- 入口契约：return function(ctx)，ctx={client, root}，返回 { stop=fun()|nil }（见 lobby_client.d.lua）。

local function logError(msg)
    msg = "[LobbyRuntimeUI] " .. tostring(msg)
    if log and LOG_ERROR then log:Write(LOG_ERROR, msg) else print(msg) end
end

local function defaultConfig()
    return {
        debugMode = false,
        theme = "dark",
        allowCreateRoom = true,
        allowQuickMatch = true,
        allowBrowseRooms = true,
    }
end

return function(ctx)
    local ui = require("urhox-libs.GameLobby.Runtime.Template.LobbyUI")
    ui.SetLobbyClient(ctx.client)
    ui.SetRoot(ctx.root)  -- 复用引擎引导层建好的专属 root

    local shown = false
    -- shown 表达「已成功渲染」而非「已尝试」：ui.Show 同步构建 Widget / 跑 lobby_ui.lua，可能抛 Lua 错。
    -- pcall 包裹，仅成功后置 shown，失败保持 false 以允许后续 uiConfig 重推重试。
    local function show(config)
        if shown then return end
        local ok, err = pcall(ui.Show, config or defaultConfig())
        if ok then
            shown = true
        else
            logError(_tr("t_JfAgCboXJmT6Qw19", tostring(err)))
        end
    end

    -- settings.json 由引擎平台侧统一读取；Runtime 主动请求一次 UI 配置后再渲染。
    if ctx.client.RequestUIConfig then
        -- 当前 LobbyBridge 的 call → Host requestUIConfig → emit("uiConfig") → Runtime 回调
        -- 是同步嵌套调用；show(cfg) 执行结束后 RequestUIConfig 才返回，不存在回调晚于入口返回的时序窗口。
        ctx.client:RequestUIConfig(function(cfg) show(cfg) end)
    else
        show(nil)
    end

    return {
        stop = function() ui.Hide() end,
    }
end
