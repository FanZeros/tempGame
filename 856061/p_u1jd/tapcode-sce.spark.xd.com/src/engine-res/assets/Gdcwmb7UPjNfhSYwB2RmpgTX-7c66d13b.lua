-- TouchController.lua
-- 双指缩放、加速度计（体感）控制等触摸手势

---@class TouchController
local TouchController = {}

---@class TouchControllerConfig
---@field gyroscopeThreshold number
---@field cameraMinDist number
---@field cameraMaxDist number
---@field touchSensitivity number

---配置
---@type TouchControllerConfig
TouchController.config = {
    gyroscopeThreshold = 0.1,
    cameraMinDist = 1.0,
    cameraMaxDist = 20.0,
    touchSensitivity = 1.0
}

-- 状态
---@type boolean
TouchController.zoom = false
---@type boolean
TouchController.useGyroscope = false
---@type number
TouchController.cameraDistance = 5.0

--------------------------------------------------------------------------------
-- 加速度计底层
--------------------------------------------------------------------------------
-- 加速度计默认不注册；EnableAccelerometer() 时才在运行时注册成名为
-- "Android Accelerometer" / "iOS Accelerometer" 的虚拟 joystick（见 Input.cpp 的
-- Input::EnableAccelerometer），3 个 axis 对应重力分量 [-1, +1]。
--
-- 按 name 查找比 index 0 抗手柄抢占，但每帧查 + 字面量构造临时 String 有可观成本。
-- 命中后缓存到 accel_，热插拔时通过事件失效后重查。

---@type JoystickState|nil
local accel_ = nil

local function _invalidateAccel()
    accel_ = nil
end

-- 注：Urho3D 的 SDL_INIT_JOYSTICK 在 Lua 启动前完成，加速度计首次 JOYDEVICEADDED
-- 可能早于此订阅。但 accel_ 初值 nil，首次 _resolveAccel() 会通过 GetJoystickByName
-- 兜底找到；订阅主要兜后续热插拔。
SubscribeToEvent("JoystickConnected", _invalidateAccel)
SubscribeToEvent("JoystickDisconnected", _invalidateAccel)

---@return JoystickState|nil
local function _resolveAccel()
    if accel_ ~= nil then return accel_ end
    if input.numJoysticks <= 0 then return nil end
    accel_ = input:GetJoystickByName("Android Accelerometer")
         or input:GetJoystickByName("iOS Accelerometer")
    return accel_
end

--- 启用加速度计（懒加载）。加速度计默认不注册，使用前必须先调用本函数，
--- 否则 ReadAccelerometer / IsAccelerometerAvailable 一直返回空。幂等。
--- 设备需一帧后才注册成 joystick，故 Enable 后首帧读取可能仍返回 (0, 0)。
--- 桌面 / Web 无传感器，本函数为安全的空操作。
function TouchController.EnableAccelerometer()
    input:EnableAccelerometer()
end

--- 关闭加速度计，注销其虚拟 joystick。幂等。
function TouchController.DisableAccelerometer()
    input:DisableAccelerometer()
    accel_ = nil
end

--- 读加速度计原始模拟量。无设备 / 无传感器 / 未授权 / 未 EnableAccelerometer 时返回 (0, 0)。
--- 默认水平向上时 (0, 0)；不做死区，由调用方按场景设阈值。
--- 轴向跨平台不一致：Android 已按屏幕旋转归一化（见 SDLActivity.onSensorChanged），
--- iOS 为 SDL 原始设备轴向，两端符号可能不同。跨端请用调用方的反转/灵敏度参数补偿。
---@return number ax -- 横向倾斜，-1..+1
---@return number ay -- 纵向倾斜，-1..+1
function TouchController.ReadAccelerometer()
    local j = _resolveAccel()
    if not j or j.numAxes < 2 then return 0, 0 end
    return j:GetAxisPosition(0), j:GetAxisPosition(1)
end

--- 加速度计是否可用。反映"已 EnableAccelerometer 且设备已注册"，而非纯硬件能力；
--- 未 Enable（或 Enable 后首帧设备尚未注册）时返回 false。用于设置菜单灰显选项。
---@return boolean
function TouchController.IsAccelerometerAvailable()
    local j = _resolveAccel()
    return j ~= nil and j.numAxes >= 2
end

---初始化触摸控制器
---@param options? {gyroscopeThreshold?: number, cameraMinDist?: number, cameraMaxDist?: number, touchSensitivity?: number, useGyroscope?: boolean, cameraDistance?: number} 配置选项
function TouchController.Initialize(options)
    options = options or {}

    -- 更新配置
    if options.gyroscopeThreshold then
        TouchController.config.gyroscopeThreshold = options.gyroscopeThreshold
    end
    if options.cameraMinDist then
        TouchController.config.cameraMinDist = options.cameraMinDist
    end
    if options.cameraMaxDist then
        TouchController.config.cameraMaxDist = options.cameraMaxDist
    end
    if options.touchSensitivity then
        TouchController.config.touchSensitivity = options.touchSensitivity
    end
    if options.useGyroscope ~= nil then
        TouchController.useGyroscope = options.useGyroscope
        -- 开启体感时确保加速度计已注册（引擎默认 hint=0 懒加载）。幂等。
        if options.useGyroscope then input:EnableAccelerometer() end
    end
    if options.cameraDistance then
        TouchController.cameraDistance = options.cameraDistance
    end
end

---更新触摸输入（在 HandleUpdate 中调用）
---@param controls? Controls 控制对象（可选，用于陀螺仪）
---@return {zoom: boolean, cameraDistance: number} 返回缩放状态和相机距离
function TouchController.Update(controls)
    TouchController.zoom = false -- 重置

    -- 双指缩放检测
    if input.numTouches == 2 then
        local touch1 = input:GetTouch(0)
        local touch2 = input:GetTouch(1)

        -- 检查缩放模式（两个触摸点反向移动，且不在 UI 元素上）
        if not touch1.touchedElement and not touch2.touchedElement then
            local oppositeDirection = (touch1.delta.y > 0 and touch2.delta.y < 0) or
                                     (touch1.delta.y < 0 and touch2.delta.y > 0)

            if oppositeDirection then
                TouchController.zoom = true

                -- 判断缩放方向（放大/缩小）
                local currentDist = Abs(touch1.position.y - touch2.position.y)
                local lastDist = Abs(touch1.lastPosition.y - touch2.lastPosition.y)
                local sens = (currentDist > lastDist) and -1 or 1

                -- 更新相机距离
                local deltaY = Abs(touch1.delta.y - touch2.delta.y)
                TouchController.cameraDistance = TouchController.cameraDistance +
                    deltaY * sens * TouchController.config.touchSensitivity / 50

                -- 限制范围
                TouchController.cameraDistance = Clamp(
                    TouchController.cameraDistance,
                    TouchController.config.cameraMinDist,
                    TouchController.config.cameraMaxDist
                )
            end
        end
    end

    -- 陀螺仪控制（通过加速度计虚拟摇杆模拟，量化成离散方向键）
    if TouchController.useGyroscope and controls then
        -- 兜底：直接置 useGyroscope=true（不经 setter）也确保加速度计已注册。幂等。
        input:EnableAccelerometer()
        local ax, ay = TouchController.ReadAccelerometer()
        local threshold = TouchController.config.gyroscopeThreshold

        if ax < -threshold then
            controls:Set(CTRL_LEFT, true)
        end
        if ax > threshold then
            controls:Set(CTRL_RIGHT, true)
        end
        if ay < -threshold then
            controls:Set(CTRL_FORWARD, true)
        end
        if ay > threshold then
            controls:Set(CTRL_BACK, true)
        end
    end

    return {
        zoom = TouchController.zoom,
        cameraDistance = TouchController.cameraDistance
    }
end

---获取当前相机距离
---@return number
function TouchController.GetCameraDistance()
    return TouchController.cameraDistance
end

---设置相机距离
---@param distance number
function TouchController.SetCameraDistance(distance)
    TouchController.cameraDistance = Clamp(
        distance,
        TouchController.config.cameraMinDist,
        TouchController.config.cameraMaxDist
    )
end

---是否正在缩放
---@return boolean
function TouchController.IsZooming()
    return TouchController.zoom
end

---启用/禁用陀螺仪
---@param enable boolean
function TouchController.SetGyroscopeEnabled(enable)
    TouchController.useGyroscope = enable
    -- 开启时确保加速度计已注册（默认 hint=0 懒加载）；关闭不注销，避免影响其它消费者
    if enable then input:EnableAccelerometer() end
end

---重置相机距离到默认值
function TouchController.ResetCameraDistance()
    TouchController.cameraDistance = 5.0
end

return TouchController
