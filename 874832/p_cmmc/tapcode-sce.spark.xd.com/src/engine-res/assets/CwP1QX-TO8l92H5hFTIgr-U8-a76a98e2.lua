-- InputManager.lua
-- 统一输入初始化（自动平台检测）
-- 来源：从 Sample.lua 重构

local PlatformUtils = require "urhox-libs.Platform.PlatformUtils"

---@class InputManager
local InputManager = {}

---@class InputManagerConfig
---@field touchSensitivity number
---@field defaultJoystickLayout string
---@field defaultJoystickStyle string

-- 配置
---@type InputManagerConfig
InputManager.config = {
    touchSensitivity = 2,
    defaultJoystickLayout = "UI/ScreenJoystick_Samples.xml",
    defaultJoystickStyle = "UI/DefaultStyle.xml"
}

-- 状态
---@type boolean
InputManager.touchEnabled = false
---@type number
InputManager.screenJoystickIndex = M_MAX_UNSIGNED
---@type number
InputManager.screenJoystickSettingsIndex = M_MAX_UNSIGNED

---初始化输入系统（自动检测平台）
---@param options? {joystickLayout?: string, joystickStyle?: string, patchString?: string, touchSensitivity?: number}
function InputManager.Initialize(options)
    options = options or {}

    -- 更新配置
    if options.touchSensitivity then
        InputManager.config.touchSensitivity = options.touchSensitivity
    end
    if options.joystickLayout then
        InputManager.config.defaultJoystickLayout = options.joystickLayout
    end
    if options.joystickStyle then
        InputManager.config.defaultJoystickStyle = options.joystickStyle
    end

    -- 根据平台自动初始化
    if PlatformUtils.IsTouchSupported() then
        -- 移动平台：直接启用虚拟摇杆
        InputManager.EnableTouchInput(options.patchString)
    elseif input:GetNumJoysticks() == 0 then
        -- 桌面平台：动态检测触摸（如 Windows 触摸屏）
        SubscribeToEvent("TouchBegin", "InputManager_HandleTouchBegin")
    end
end

---启用触摸输入
---@param patchString? string 可选的 XML patch 字符串
---@return boolean 是否成功启用
function InputManager.EnableTouchInput(patchString)
    if InputManager.touchEnabled then
        return true -- 已启用
    end

    -- 加载虚拟摇杆布局
    local layout = cache:GetResource("XMLFile", InputManager.config.defaultJoystickLayout)
    if layout == nil then
        log:Write(LOG_WARNING, "Cannot load joystick layout: " .. InputManager.config.defaultJoystickLayout)
        return false
    end

    -- 应用 XML patch（如果提供）
    if patchString and patchString ~= "" then
        local patchFile = XMLFile()
        if patchFile:FromString(patchString) then
            layout:Patch(patchFile)
        end
    end

    -- 添加屏幕摇杆
    local style = cache:GetResource("XMLFile", InputManager.config.defaultJoystickStyle)
    InputManager.screenJoystickIndex = input:AddScreenJoystick(layout, style)
    input:SetScreenJoystickVisible(InputManager.screenJoystickIndex, true)

    -- 所有步骤成功后才设置标志
    InputManager.touchEnabled = true

    log:Write(LOG_INFO, "Touch input enabled (joystick index: " .. InputManager.screenJoystickIndex .. ")")
    return true
end

---禁用触摸输入（隐藏虚拟摇杆）
function InputManager.DisableTouchInput()
    if not InputManager.touchEnabled then
        return
    end

    if InputManager.screenJoystickIndex ~= M_MAX_UNSIGNED then
        input:SetScreenJoystickVisible(InputManager.screenJoystickIndex, false)
    end

    InputManager.touchEnabled = false
    log:Write(LOG_INFO, "Touch input disabled")
end

---切换触摸输入
function InputManager.ToggleTouchInput()
    if InputManager.touchEnabled then
        InputManager.DisableTouchInput()
    else
        InputManager.EnableTouchInput()
    end
end

---判断触摸输入是否已启用
---@return boolean
function InputManager.IsTouchEnabled()
    return InputManager.touchEnabled
end

---获取虚拟摇杆索引
---@return number
function InputManager.GetJoystickIndex()
    return InputManager.screenJoystickIndex
end

---添加设置摇杆（暂停菜单等）
---@param layoutPath? string 布局文件路径
---@return number 摇杆索引
function InputManager.AddSettingsJoystick(layoutPath)
    layoutPath = layoutPath or "UI/ScreenJoystickSettings_Samples.xml"
    local layout = cache:GetResource("XMLFile", layoutPath)
    local style = cache:GetResource("XMLFile", InputManager.config.defaultJoystickStyle)

    InputManager.screenJoystickSettingsIndex = input:AddScreenJoystick(layout, style)
    input:SetScreenJoystickVisible(InputManager.screenJoystickSettingsIndex, false)

    return InputManager.screenJoystickSettingsIndex
end

---显示/隐藏设置摇杆
---@param visible boolean
function InputManager.ShowSettingsJoystick(visible)
    if InputManager.screenJoystickSettingsIndex ~= M_MAX_UNSIGNED then
        input:SetScreenJoystickVisible(InputManager.screenJoystickSettingsIndex, visible)
    end
end

-- 内部事件处理：动态检测触摸
function InputManager_HandleTouchBegin(eventType, eventData)
    -- 在桌面平台上检测到触摸时，启用触摸输入
    local success = InputManager.EnableTouchInput()
    -- 只有成功启用后才取消订阅
    if success then
        UnsubscribeFromEvent("TouchBegin")
    end
end

return InputManager
