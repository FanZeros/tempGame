-- SystemDialog.lua — Host 侧系统弹窗渲染器。
--
-- 终态弹窗（被踢 / 被封 / 资源不足 / 版本过低）在游戏运行期由本模块就地渲染；Game Runtime
-- 未处理的连接类 SystemNotification 也使用本模块的 Toast 兜底。Host state 不随脚本切换销毁，
-- 是覆盖游戏运行期的最终显示落点。
--
-- UI 库按需加载：大厅阶段（Runtime 渲染）不拉起，仅在需要就地渲染时才 require + Init。
-- 独立 NanoVG 上下文的渲染顺序高于游戏 UI，故弹窗恒画在最上层。
--
-- 输入范围：root 不拦截指针事件、遮罩拦截，两者都只作用于 Host 自己这棵 UI 树。跨 lua_State
-- 拦不住——Runtime state 的 UI 与游戏各自直接订阅引擎原始输入事件（MouseButtonDown /
-- TouchBegin），彼此没有「已消费」语义，故弹窗挂起期间游戏照样收到点击。局内的输入隔离
-- 不由本模块负责。
--
-- 依赖 HostSandbox 全局：graphics、log、LOG_*、nvgSetRenderOrder。

local M = {}

-- 游戏 UI 用 999990（UI.Init 默认值），系统弹窗须恒在其上
local RENDER_ORDER = 999995

-- 与 GameLobby/Runtime/Template/LobbyUI.lua 的 THEMES.dark 取值一致，两侧弹窗观感统一
local THEME = {
    primary = { 77, 179, 255, 255 },
    surface = { 51, 51, 51, 255 },
    text = { 242, 242, 242, 255 },
    textSecondary = { 179, 179, 179, 255 },
    error = { 255, 102, 102, 255 },
}

local UI = nil
local Toast = nil
local root_ = nil
local overlay_ = nil
local dialogQueue_ = {}
local loadModule_ = require

local function write(level, msg)
    if log and level then
        log:Write(level, msg)
    else
        print(msg)
    end
end

-- 拉起 Host 侧 UI（幂等）。失败原因已在本函数内记录，调用方统一降级为已消费。
local function ensureUI()
    if root_ then return true end
    if not graphics then
        write(LOG_WARNING, _tr("t_vnXgetSEvgFFvQjc"))
        return false
    end

    local ok, err = pcall(function()
        UI = loadModule_("urhox-libs.UI")
        Toast = loadModule_("urhox-libs.UI.Widgets.Toast")

        if not UI.GetNVGContext() then
            UI.Init({ scale = function() return math.max(graphics.height / 1080, 0.4) end })
            -- 只给自己建的上下文定层级：复用本 state 已有的上下文时不动它的渲染顺序
            nvgSetRenderOrder(UI.GetNVGContext(), RENDER_ORDER)
        end

        local root = UI.SafeAreaView {
            width = "100%",
            height = "100%",
            pointerEvents = "box-none", -- 无弹窗时不拦截游戏输入
        }
        -- 本 state 已有 UI 根时挂上去，不抢占（与 LobbyBootstrap 建专属根同一写法）
        local uiRoot = UI.GetRoot()
        if uiRoot then uiRoot:AddChild(root) else UI.SetRoot(root) end
        root_ = root
    end)

    if not ok then
        write(LOG_ERROR, _tr("t_KRs0k5ixKFoEaA4f", tostring(err)))
        UI, Toast, root_ = nil, nil, nil
        return false
    end
    return true
end

--- 模态弹窗：遮罩 + 居中卡片（icon / 标题 / 正文 / 单个确认按钮）。
--- 同时只展示一个：终态提示先到先留，后续提示排队等待。
--- @param options table { icon, title, message, buttonText, onClose }
--- @return boolean consumed 已展示、已排队，或 Host UI 不可用时已降级为日志
function M.Show(options)
    options = options or {}
    local title = tostring(options.title or "")
    local message = tostring(options.message or "")

    if not ensureUI() then
        -- 玩家看不到也点不到弹窗，此处不代替玩家执行 onClose（那会在无人值守环境里直接退出进程），
        -- 只留下日志供排查玩家反馈
        write(LOG_WARNING, string.format("[SystemDialog] %s - %s", title, message))
        return true
    end

    if overlay_ then
        dialogQueue_[#dialogQueue_ + 1] = options
        write(LOG_INFO, string.format(_tr("t_1Ci3KnpEl1CapdWMgb"), title, message))
        return true
    end

    local overlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = { 0, 0, 0, 220 }, -- 底下是运行中的游戏画面，遮罩比大厅内更实以保证可读
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",             -- 拦截 Host 自身 UI 树内的命中（跨 state 拦不住游戏输入）
    }

    local dialog = UI.Panel {
        width = "85%",
        maxWidth = 380,
        flexDirection = "column",
        backgroundColor = THEME.surface,
        borderRadius = 16,
        padding = 32,
        gap = 16,
        alignItems = "center",
    }

    dialog:AddChild(UI.Label {
        text = options.icon or "⚠",
        fontSize = 48,
        color = THEME.error,
    })

    dialog:AddChild(UI.Label {
        text = title,
        fontSize = 22,
        fontWeight = "bold",
        color = THEME.text,
        textAlign = "center",
    })

    dialog:AddChild(UI.Label {
        text = message,
        fontSize = 14,
        color = THEME.textSecondary,
        textAlign = "center",
        marginBottom = 8,
    })

    local btn = UI.Button {
        width = "100%",
        height = 44,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = THEME.primary,
        borderRadius = 8,
        onClick = function()
            if overlay_ then
                overlay_:Destroy()
                overlay_ = nil
            end
            if options.onClose then options.onClose() end

            local nextOptions = table.remove(dialogQueue_, 1)
            if nextOptions then M.Show(nextOptions) end
        end,
    }
    btn:AddChild(UI.Label {
        text = options.buttonText or _tr("t_JJMNFId6IoqaIkhF"),
        fontSize = 16,
        fontWeight = "bold",
        color = { 255, 255, 255, 255 },
    })
    dialog:AddChild(btn)

    overlay:AddChild(dialog)
    root_:AddChild(overlay)
    overlay_ = overlay
    write(LOG_INFO, string.format(_tr("t_XJQPWQrJXQe735dH"), title, message))
    return true
end

--- 非阻塞错误提示（连接失败 / 重试中一类，可连续触发，由 Toast 自行排队）。
--- @param message string
--- @return boolean consumed 已展示，或 Host UI 不可用时已降级为日志
function M.ShowError(message)
    if not ensureUI() then
        write(LOG_WARNING, _tr("t_12pNTYknA12JsqmpmY", tostring(message)))
        return true
    end

    Toast.Show({
        message = tostring(message or ""),
        variant = "error",
        duration = 4,
        showClose = true,
    })
    write(LOG_INFO, "[SystemDialog] Toast: " .. tostring(message))
    return true
end

--- 注入渲染依赖，跳过真实 UI 初始化（结构自测用）。
--- @param deps table { UI, Toast, root, loadModule }
function M._injectDeps(deps)
    UI = deps.UI
    Toast = deps.Toast
    root_ = deps.root
    overlay_ = nil
    dialogQueue_ = {}
    loadModule_ = deps.loadModule or require
end

return M
