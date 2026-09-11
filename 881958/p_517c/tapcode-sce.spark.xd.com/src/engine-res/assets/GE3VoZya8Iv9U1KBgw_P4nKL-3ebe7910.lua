-- MouseLockManager.lua
-- 鼠标模式管理（Web 平台兼容）
-- 来源：从 Sample.lua 重构

local PlatformUtils = require "urhox-libs.Platform.PlatformUtils"

---@class MouseLockManager
local MouseLockManager = {}

-- 当前鼠标模式
---@type number
MouseLockManager.currentMode = MM_ABSOLUTE
---@type number
MouseLockManager.desiredMode = MM_ABSOLUTE
---@type boolean
MouseLockManager.initialized = false

---初始化鼠标模式管理器
---@param mode? number 期望的鼠标模式（MM_ABSOLUTE, MM_RELATIVE, MM_WRAP, MM_FREE）
function MouseLockManager.Initialize(mode)
    MouseLockManager.desiredMode = mode or MM_ABSOLUTE
    MouseLockManager.initialized = true

    if PlatformUtils.IsWebPlatform() then
        -- Web 平台：需要用户交互才能锁定鼠标
        input.mouseVisible = true
        SubscribeToEvent("MouseButtonDown", "MouseLockManager_HandleMouseModeRequest")
        SubscribeToEvent("MouseModeChanged", "MouseLockManager_HandleMouseModeChange")
    else
        -- 桌面/移动平台：直接设置
        MouseLockManager.SetMouseMode(mode)
    end
end

---设置鼠标模式
---@param mode? number 鼠标模式
function MouseLockManager.SetMouseMode(mode)
    if not MouseLockManager.initialized then
        MouseLockManager.Initialize(mode)
        return
    end

    MouseLockManager.desiredMode = mode

    if PlatformUtils.IsWebPlatform() then
        -- Web 平台：等待用户点击
        if mode == MM_FREE then
            input.mouseVisible = true
        end
        -- 实际模式切换在用户点击时触发
    else
        -- 桌面/移动平台：直接设置
        if mode == MM_FREE then
            input.mouseVisible = true
        end

        if mode ~= MM_ABSOLUTE then
            input.mouseMode = mode

            -- 如果控制台可见，临时切换回绝对模式
            if console ~= nil and console.visible then
                input:SetMouseMode(MM_ABSOLUTE, true)
            end
        end

        MouseLockManager.currentMode = mode
    end
end

---获取当前鼠标模式
---@return number
function MouseLockManager.GetMouseMode()
    return MouseLockManager.currentMode
end

---释放鼠标锁定
function MouseLockManager.ReleaseMouse()
    input.mouseVisible = true

    if not PlatformUtils.IsWebPlatform() then
        if MouseLockManager.desiredMode ~= MM_ABSOLUTE then
            input.mouseMode = MM_FREE
        end
    else
        input.mouseMode = MM_FREE
    end

    MouseLockManager.currentMode = MM_FREE
end

---锁定鼠标（使用期望的模式）
function MouseLockManager.LockMouse()
    MouseLockManager.SetMouseMode(MouseLockManager.desiredMode)
end

---处理控制台显示/隐藏
---@param consoleVisible boolean 控制台是否可见
function MouseLockManager.HandleConsoleVisibility(consoleVisible)
    if consoleVisible then
        -- 控制台打开：临时释放鼠标
        input.mouseVisible = true
        input:SetMouseMode(MM_ABSOLUTE, true)
    else
        -- 控制台关闭：恢复期望的模式
        MouseLockManager.SetMouseMode(MouseLockManager.desiredMode)
    end
end

---处理 ESC 键（跨平台）
---@return boolean 是否已处理（Web 平台返回 true）
function MouseLockManager.HandleEscapeKey()
    if PlatformUtils.IsWebPlatform() then
        -- Web 平台：释放鼠标
        MouseLockManager.ReleaseMouse()
        return true
    else
        -- 桌面平台：返回 false，由调用者决定（通常是退出）
        return false
    end
end

-- 内部事件处理：Web 平台鼠标模式请求
function MouseLockManager_HandleMouseModeRequest(eventType, eventData)
    if console ~= nil and console.visible then
        return -- 控制台打开时不处理
    end

    if input.mouseMode == MM_ABSOLUTE then
        input.mouseVisible = false
    elseif MouseLockManager.desiredMode == MM_FREE then
        input.mouseVisible = true
    end

    input.mouseMode = MouseLockManager.desiredMode
end

-- 内部事件处理：Web 平台鼠标模式改变
function MouseLockManager_HandleMouseModeChange(eventType, eventData)
    local mouseLocked = eventData["MouseLocked"]:GetBool()
    input.mouseVisible = not mouseLocked

    if mouseLocked then
        MouseLockManager.currentMode = MouseLockManager.desiredMode
    else
        MouseLockManager.currentMode = MM_FREE
    end
end

return MouseLockManager
