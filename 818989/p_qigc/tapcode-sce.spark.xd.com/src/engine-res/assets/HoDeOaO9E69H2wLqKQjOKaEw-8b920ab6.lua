--[[
================================================================================
  VirtualControls.lua - 虚拟摇杆/按钮库
================================================================================

【用途】
  基于 NanoVG 的自定义虚拟摇杆库，支持：
  - 360° 任意方向的摇杆
  - 虚拟按钮（支持冷却显示）
  - 技能轮盘
  - DPI 自适应
  - 角色控制切换
  - 键盘和鼠标绑定
  - 加速度计输入（Android/iOS 倾斜手机控制摇杆）

【使用方法】
  require "urhox-libs.UI.VirtualControls"

  -- 方式一：简化模式（推荐） - 直接传入 Controls 对象
  function Start()
      local joystick = VirtualControls.CreateJoystick({
          position = Vector2(200, -200),
          alignment = {HA_LEFT, VA_BOTTOM},
      })

      -- 设置控制目标，摇杆输入自动转换为 CTRL_FORWARD/BACK/LEFT/RIGHT
      VirtualControls.SetControls(character.controls)

      -- 切换角色时只需：
      -- VirtualControls.SetControls(anotherCharacter.controls)
  end

  -- 方式二：回调模式（传统方式）
  function Start()
      local joystick = VirtualControls.CreateJoystick({
          position = Vector2(200, -200),
          alignment = {HA_LEFT, VA_BOTTOM},
      })

      joystick.on_move = function(x, y, percent)
          character:Move(x, y, percent)
      end
  end

  -- 方式三：自定义 Controller（高级模式）
  function Start()
      local joystick = VirtualControls.CreateJoystick({...})

      VirtualControls.SetController({
          move = function(self, x, y, percent)
              -- 自定义控制逻辑
          end,
          onMoveEnd = function(self)
              -- 移动结束
          end,
      })
  end

  -- 注意：Initialize() 会自动订阅 Update 和 NanoVG 渲染事件
  -- 无需手动调用 VirtualControls.Update() 和 VirtualControls.Render()

【按钮绑定】
  -- 键盘绑定 (keyBinding)
  VirtualControls.CreateButton({
      keyBinding = KEY_SPACE,           -- 方式1: KEY_* 常量
      keyBinding = "SPACE",             -- 方式2: 字符串 (自动转为 KEY_SPACE)
      keyBinding = {key = KEY_E, label = "E"},  -- 方式3: 表形式
  })

  -- 鼠标绑定 (mouseBinding)
  VirtualControls.CreateButton({
      mouseBinding = MOUSEB_LEFT,       -- 方式1: MOUSEB_* 常量
      mouseBinding = "LMB",             -- 方式2: 字符串 ("LMB", "RMB", "MMB")
      mouseBinding = {button = MOUSEB_LEFT, label = "LMB"},  -- 方式3: 表形式
  })

  -- 同时绑定键盘和鼠标
  VirtualControls.CreateButton({
      label = "Shoot",
      keyBinding = "F",
      mouseBinding = "LMB",  -- 显示为 [F/LMB]
  })

【加速度计输入（仅 Android/iOS 生效）】
  -- 模式："none"(默认禁用) | "only"(替换触摸/键盘) | "both"(与触摸/键盘逐轴组合)
  VirtualControls.CreateJoystick({
      keyBinding = "WASD",
      accelerometerMode        = "both",  -- 触摸+倾斜共存，逐轴取较大者
      accelerometerDeadZone    = 0.1,     -- 倾斜小于 10% 视为静止
      accelerometerSensitivity = 1.5,     -- 灵敏度乘数
      accelerometerInvertX     = false,
      accelerometerInvertY     = false,
  })

  -- "only" 模式会自动隐藏摇杆 UI 并关闭触摸响应；倾斜手机即操控
  -- 桌面端无传感器，运行时自动旁路（无需手动判平台）
  -- 检测设备是否可用：require("urhox-libs.Input.TouchController").IsAccelerometerAvailable()

================================================================================
--]]

--------------------------------------------------------------------------------
-- 依赖
--------------------------------------------------------------------------------

local TouchController = require "urhox-libs.Input.TouchController"

--------------------------------------------------------------------------------
-- 模块定义
--------------------------------------------------------------------------------

---@class VirtualControls
VirtualControls = {}

-- 内部状态
local _initialized = false
local _nvgContext = nil
local _fontId = -1

-- 设计分辨率（用于 UI 布局计算）
local _designWidth = 1920
local _designHeight = 1080
local _designShortSide = 1080  -- 设计分辨率短边（用于 UI 缩放基准）

-- 屏幕尺寸（实际像素）
local _screenWidth = 0
local _screenHeight = 0

-- 缩放因子和偏移（短边缩放模式）
local _scaleFactor = 1.0
local _offsetX = 0
local _offsetY = 0

-- 平台检测
local _isMobile = false

-- 组件容器
local _joysticks = {}
local _buttons = {}
local _wheels = {}
local _touchLookAreas = {}

-- 触摸状态追踪
local _touchOwners = {}  -- touchId -> component

-- 全局 Controller（用于统一控制角色）
local _globalController = nil

-- 全局 Controls2D（用于 2D 游戏角色控制）
local _globalControls2D = nil

-- 鼠标模拟触摸开关（仅用于开发调试）
local _mouseEmulationEnabled = false

-- 安全区边距（像素，用于避开刘海/圆角）
local _safeAreaInsets = { left = 0, top = 0, right = 0, bottom = 0 }

--- 获取安全区边距（参考 SafeAreaView.lua）
local function getSafeAreaInsets()
    -- GetSafeAreaInsets 返回 Rect: min.x=left, min.y=top, max.x=right, max.y=bottom
    -- 参数 false 表示不使用 cutout 模式
    if GetSafeAreaInsets then
        local rect = GetSafeAreaInsets(false)
        return {
            left = rect.min.x,
            top = rect.min.y,
            right = rect.max.x,
            bottom = rect.max.y
        }
    end
    return { left = 0, top = 0, right = 0, bottom = 0 }
end

--------------------------------------------------------------------------------
-- Controls2D 类（2D 游戏角色控制器）
--------------------------------------------------------------------------------

---@class Controls2D
---@field x number 当前 X 位置
---@field y number 当前 Y 位置
---@field speed number 移动速度
---@field bounds table|nil 移动边界 {minX, maxX, minY, maxY}
---@field _inputX number 方向输入 X (-1 到 1)
---@field _inputY number 方向输入 Y (-1 到 1)
---@field _targetX number 目标位置 X (全屏触控模式)
---@field _targetY number 目标位置 Y (全屏触控模式)
---@field _hasTarget boolean 是否有目标位置
local Controls2D = {}
Controls2D.__index = Controls2D

function Controls2D:new(config)
    -- 兼容 Controls2D:new(config) 和 Controls2D.new(config) 两种调用方式
    if self ~= Controls2D then
        config = self  -- 用 . 调用时，self 其实是 config
    end

    local ins = setmetatable({}, Controls2D)

    -- 位置
    ins.x = config.x or 0
    ins.y = config.y or 0

    -- 移动速度
    ins.speed = config.speed or 300

    -- 移动边界
    ins.bounds = config.bounds  -- {minX, maxX, minY, maxY}

    -- 内部状态（由摇杆写入）
    ins._inputX = 0          -- 方向输入 -1 到 1
    ins._inputY = 0
    ins._targetX = 0         -- 目标位置（全屏触控模式）
    ins._targetY = 0
    ins._hasTarget = false   -- 是否有目标位置

    return ins
end

function Controls2D:update(dt)
    if self._hasTarget then
        -- 目标追踪模式：向目标位置移动
        local dx = self._targetX - self.x
        local dy = self._targetY - self.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist > 2 then
            -- 移动量 = min(距离, 速度 * dt)
            local moveAmount = math.min(dist, self.speed * dt)
            self.x = self.x + (dx / dist) * moveAmount
            self.y = self.y + (dy / dist) * moveAmount
        end
    else
        -- 方向输入模式：方向 * 速度 * dt
        self.x = self.x + self._inputX * self.speed * dt
        self.y = self.y + self._inputY * self.speed * dt
    end

    -- 边界限制
    if self.bounds then
        self.x = math.max(self.bounds.minX, math.min(self.bounds.maxX, self.x))
        self.y = math.max(self.bounds.minY, math.min(self.bounds.maxY, self.y))
    end
end

-- 导出 Controls2D 类
VirtualControls.Controls2D = Controls2D

--------------------------------------------------------------------------------
-- 工具函数
--------------------------------------------------------------------------------

local function clamp(value, minVal, maxVal)
    return math.max(minVal, math.min(maxVal, value))
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- 加速度计 "both" 模式逐轴组合：同号取绝对值大者（不叠加避免双倍）；异号相加
local function _combineAxis(a, b)
    if a * b >= 0 then
        return (math.abs(a) >= math.abs(b)) and a or b
    else
        return a + b
    end
end

local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function normalize(x, y)
    local len = math.sqrt(x * x + y * y)
    if len > 0 then
        return x / len, y / len, len
    end
    return 0, 0, 0
end

--- 将设计坐标转换为屏幕坐标
local function designToScreen(x, y)
    return x * _scaleFactor + _offsetX, y * _scaleFactor + _offsetY
end

--- 将屏幕坐标转换为设计坐标
--- 用于将触摸输入转换到设计坐标系
local function screenToDesign(x, y)
    return (x - _offsetX) / _scaleFactor, (y - _offsetY) / _scaleFactor
end

--- 计算组件的设计坐标位置（基于对齐方式）
--- 混合策略：
---   - 边缘对齐（LEFT/RIGHT/TOP/BOTTOM）：使用实际屏幕边缘 + 安全区边距
---   - 中心对齐（CENTER）：使用设计分辨率中心
---   - 偏移值：按设计分辨率缩放
---@param position Vector2 设计分辨率下的偏移
---@param alignment table {横向对齐, 纵向对齐}
---@return number, number 设计坐标
local function calculateScreenPosition(position, alignment)
    local hAlign = alignment[1] or HA_LEFT
    local vAlign = alignment[2] or VA_TOP
    
    local x, y = position.x, position.y
    
    -- 计算实际屏幕边缘在设计坐标系中的位置
    -- 由于 NanoVG 变换: screenPos = offsetX + designPos * scaleFactor
    -- 反推: designPos = (screenPos - offsetX) / scaleFactor
    local screenLeftInDesign = -_offsetX / _scaleFactor
    local screenRightInDesign = (_screenWidth - _offsetX) / _scaleFactor
    local screenTopInDesign = -_offsetY / _scaleFactor
    local screenBottomInDesign = (_screenHeight - _offsetY) / _scaleFactor
    
    -- 将安全区边距转换到设计坐标系
    local safeLeft = _safeAreaInsets.left / _scaleFactor
    local safeRight = _safeAreaInsets.right / _scaleFactor
    local safeTop = _safeAreaInsets.top / _scaleFactor
    local safeBottom = _safeAreaInsets.bottom / _scaleFactor
    
    -- 横向对齐
    if hAlign == HA_LEFT then
        -- 边缘对齐：使用实际屏幕左边缘 + 安全区左边距
        x = screenLeftInDesign + safeLeft + x
    elseif hAlign == HA_CENTER then
        -- 中心对齐：使用设计分辨率中心（保持不变）
        x = _designWidth / 2 + x
    elseif hAlign == HA_RIGHT then
        -- 边缘对齐：使用实际屏幕右边缘 - 安全区右边距
        x = screenRightInDesign - safeRight + x
    end
    
    -- 纵向对齐
    if vAlign == VA_TOP then
        -- 边缘对齐：使用实际屏幕上边缘 + 安全区上边距
        y = screenTopInDesign + safeTop + y
    elseif vAlign == VA_CENTER then
        -- 中心对齐：使用设计分辨率中心（保持不变）
        y = _designHeight / 2 + y
    elseif vAlign == VA_BOTTOM then
        -- 边缘对齐：使用实际屏幕下边缘 - 安全区下边距
        y = screenBottomInDesign - safeBottom + y
    end
    
    return x, y
end

--------------------------------------------------------------------------------
-- VirtualJoystick 类
--------------------------------------------------------------------------------

---@class VirtualJoystick
---@field x number 方向 X (-1 到 1)
---@field y number 方向 Y (-1 到 1)
---@field angle number 角度 (弧度)
---@field magnitude number 力度 (0-1)
---@field isActive boolean 是否激活
---@field on_press function|nil
---@field on_release function|nil
---@field on_move_start function|nil
---@field on_move function|nil
---@field on_move_end function|nil
---@field position Vector2 设计坐标位置
---@field alignment table 对齐方式 {横向, 纵向}
---@field baseRadius number 底盘半径
---@field knobRadius number 摇杆头半径
---@field moveRadius number 移动范围半径
---@field deadZone number 死区 (0-1)
---@field isPressCenter boolean 按下时是否以按下位置为中心
---@field isReleaseReset boolean 释放时是否重置位置
---@field pressRegionRadius number 可点击区域半径
---@field opacity number 默认透明度
---@field activeOpacity number 激活时透明度
---@field visible boolean 是否渲染摇杆
---@field fullscreenTouch boolean 是否全屏触控模式
---@field keyBinding string|table|nil 键盘绑定
---@field showKeyHints boolean 是否显示按键提示
---@field alwaysShow boolean|nil 非移动端是否显示
---@field accelerometerMode string 加速度计模式 "none"|"only"|"both"
---@field accelerometerDeadZone number 加速度计独立死区 (0-1)
---@field accelerometerSensitivity number 加速度计灵敏度
---@field accelerometerInvertX boolean 加速度计 X 轴反转
---@field accelerometerInvertY boolean 加速度计 Y 轴反转
---@field keyBindingMap table|nil 解析后的键盘绑定映射
---@field keyLabels table|nil 按键标签
---@field keyStates table 按键状态
---@field centerX number 中心 X
---@field centerY number 中心 Y
---@field pressStartX number 按下起始 X
---@field pressStartY number 按下起始 Y
---@field knobX number 摇杆头 X
---@field knobY number 摇杆头 Y
---@field touchId number|nil 触摸 ID
---@field currentOpacity number 当前透明度
---@field currentScale number 当前缩放
---@field wasMoving boolean 上一帧是否移动
---@field isKeyboardActive boolean 键盘是否激活
---@field isAccelActive boolean 加速度计是否在驱动
---@field playerX number 玩家位置 X (全屏触控模式)
---@field playerY number 玩家位置 Y (全屏触控模式)
---@field offsetX number 偏移 X (全屏触控模式)
---@field offsetY number 偏移 Y (全屏触控模式)
---@field targetX number 目标位置 X (全屏触控模式)
---@field targetY number 目标位置 Y (全屏触控模式)
---@field hasTarget boolean 是否有目标 (全屏触控模式)
---@field _controller table|nil 专属 Controller
---@field _shouldShow boolean 是否应该显示
---@field _shouldHandleTouch boolean 是否应该处理触摸
local VirtualJoystick = {}
VirtualJoystick.__index = VirtualJoystick

function VirtualJoystick.new(config)
    local self = setmetatable({}, VirtualJoystick)
    
    -- 配置
    self.position = config.position or Vector2(150, -150)
    self.alignment = config.alignment or {HA_LEFT, VA_BOTTOM}
    self.baseRadius = config.baseRadius or 80
    self.knobRadius = config.knobRadius or 30
    self.moveRadius = config.moveRadius or 50
    self.deadZone = config.deadZone or 0.15
    self.isPressCenter = config.isPressCenter ~= false  -- 默认 true
    self.isReleaseReset = config.isReleaseReset ~= false  -- 默认 true
    self.opacity = config.opacity or 0.5
    self.activeOpacity = config.activeOpacity or 0.85
    self.pressRegionRadius = config.pressRegionRadius or 150  -- 可点击区域半径

    -- 2D 游戏适配配置
    self.visible = config.visible ~= false           -- 是否渲染摇杆，默认 true
    self.fullscreenTouch = config.fullscreenTouch or false  -- 是否全屏触控（自动启用偏移跟随模式），默认 false

    -- 键盘绑定 (WASD 或自定义)
    -- keyBinding = "WASD" 或 keyBinding = {up=KEY_W, down=KEY_S, left=KEY_A, right=KEY_D}
    self.keyBinding = config.keyBinding
    self.showKeyHints = config.showKeyHints ~= false  -- 是否显示按键提示，默认 true
    self.alwaysShow = config.alwaysShow  -- 非移动端是否显示摇杆，nil 表示自动（有键盘绑定时不显示）

    -- 加速度计配置。模式："none" | "only" | "both"
    -- 平台判断推迟到运行时（_isMobile 可能晚于构造才设置）
    self.accelerometerMode        = config.accelerometerMode or "none"
    self.accelerometerDeadZone    = math.min(config.accelerometerDeadZone or 0.1, 0.3)
    self.accelerometerSensitivity = config.accelerometerSensitivity or 1.0
    self.accelerometerInvertX     = config.accelerometerInvertX or false
    self.accelerometerInvertY     = config.accelerometerInvertY or false

    -- 用到加速度计才显式开启传感器（懒加载）。幂等，多个摇杆调多次无害；
    -- 设备需一帧后才注册成 joystick，故首帧 ReadAccelerometer 可能返回 (0,0)。
    if self.accelerometerMode ~= "none" then
        input:EnableAccelerometer()
    end

    -- 状态
    self.x = 0
    self.y = 0
    self.angle = 0
    self.magnitude = 0
    self.isActive = false
    self.wasMoving = false  -- 用于检测 move_start/move_end
    self.isKeyboardActive = false  -- 键盘是否激活
    self.isAccelActive = false  -- 加速度计是否在驱动（移动端 both/only 模式的统一边沿状态）
    self.keyStates = {up = false, down = false, left = false, right = false}

    -- 全屏触控模式状态（偏移跟随）
    self.offsetX = 0            -- 初始偏移 X（角色位置 - 手指位置）
    self.offsetY = 0            -- 初始偏移 Y
    self.targetX = 0            -- 目标位置 X（手指位置 + 偏移）
    self.targetY = 0            -- 目标位置 Y
    self.hasTarget = false      -- 是否有有效目标
    
    -- 渲染位置
    self.centerX, self.centerY = calculateScreenPosition(self.position, self.alignment)
    self.pressStartX = self.centerX
    self.pressStartY = self.centerY
    self.knobX = self.centerX
    self.knobY = self.centerY
    
    -- 触摸 ID
    self.touchId = nil
    
    -- 动画
    self.currentOpacity = self.opacity
    self.currentScale = 1.0
    
    -- 回调
    self.on_press = config.on_press
    self.on_release = config.on_release
    self.on_move_start = config.on_move_start
    self.on_move = config.on_move
    self.on_move_end = config.on_move_end
    
    -- 专属 Controller（优先于全局 Controller）
    self._controller = nil
    
    -- 解析键盘绑定
    if self.keyBinding == "WASD" then
        self.keyBindingMap = {up = KEY_W, down = KEY_S, left = KEY_A, right = KEY_D}
        self.keyLabels = {up = "W", down = "S", left = "A", right = "D"}
    elseif self.keyBinding == "ARROWS" then
        self.keyBindingMap = {up = KEY_UP, down = KEY_DOWN, left = KEY_LEFT, right = KEY_RIGHT}
        self.keyLabels = {up = "↑", down = "↓", left = "←", right = "→"}
    elseif type(self.keyBinding) == "table" then
        self.keyBindingMap = self.keyBinding
        self.keyLabels = config.keyLabels or {up = "↑", down = "↓", left = "←", right = "→"}
    else
        self.keyBindingMap = nil
        self.keyLabels = nil
    end
    
    -- 全屏触控模式需要的玩家位置（由游戏脚本每帧更新）
    self.playerX = 0
    self.playerY = 0

    -- 初始化显示状态
    self:_updateShouldShow()

    return self
end

--- 更新摇杆的显示状态（用于动态切换模式）
function VirtualJoystick:_updateShouldShow()
    -- only 模式：accel 是唯一输入源，触摸 UI / 响应全关。非移动端无传感器，旁路。
    if self.accelerometerMode == "only" and _isMobile then
        self._shouldShow = false
        self._shouldHandleTouch = false
        return
    end

    -- 计算是否应该显示摇杆（用于渲染）
    -- visible=false 强制不显示
    -- PC 端：有键盘绑定时默认不显示，除非 alwaysShow = true
    -- 移动端：始终显示（除非 visible=false）
    if not self.visible then
        self._shouldShow = false
    elseif not _isMobile then
        if self.keyBindingMap then
            -- 有键盘绑定
            self._shouldShow = (self.alwaysShow == true)
        else
            self._shouldShow = true
        end
    else
        self._shouldShow = true
    end

    -- 计算是否应该响应触摸
    -- fullscreenTouch=true 或 _shouldShow=true 时响应触摸
    self._shouldHandleTouch = self.fullscreenTouch or self._shouldShow
end

--- 设置玩家当前位置（全屏触控模式需要）
function VirtualJoystick:setPlayerPosition(x, y)
    self.playerX = x
    self.playerY = y
end

function VirtualJoystick:handleTouchBegin(touchId, x, y)
    -- 如果不应该处理触摸，直接返回
    if not self._shouldHandleTouch then
        return false
    end

    -- 转换到设计坐标
    local designX, designY = screenToDesign(x, y)

    -- 计算当前中心位置
    local centerX, centerY = calculateScreenPosition(self.position, self.alignment)

    -- 全屏触控模式：跳过区域检查
    if not self.fullscreenTouch then
        -- 检查是否在可点击区域内
        local dist = distance(designX, designY, centerX, centerY)
        if dist > self.pressRegionRadius then
            return false
        end
    end
    
    -- 占用此触摸
    self.touchId = touchId
    self.isActive = true
    
    -- 设置中心位置
    if self.isPressCenter then
        self.pressStartX = designX
        self.pressStartY = designY
    else
        self.pressStartX = centerX
        self.pressStartY = centerY
    end
    
    self.knobX = designX
    self.knobY = designY

    -- 全屏触控模式：记录初始偏移（偏移跟随）
    if self.fullscreenTouch then
        -- 获取玩家位置：优先从 Controls2D 读取，否则使用手动设置的 playerX/Y
        local playerX = _globalControls2D and _globalControls2D.x or self.playerX
        local playerY = _globalControls2D and _globalControls2D.y or self.playerY
        -- 偏移 = 角色位置 - 手指位置
        self.offsetX = playerX - designX
        self.offsetY = playerY - designY
        -- 初始目标就是当前角色位置
        self.targetX = playerX
        self.targetY = playerY
        self.hasTarget = true
    else
        -- 传统摇杆模式：计算初始方向
        self:updateDirection()
    end

    -- 触发回调
    self:_firePress(self.x, self.y, self.magnitude)

    return true
end

function VirtualJoystick:handleTouchMove(touchId, x, y)
    if self.touchId ~= touchId then
        return false
    end

    local designX, designY = screenToDesign(x, y)

    if self.fullscreenTouch then
        -- 全屏触控模式：更新目标位置 = 手指位置 + 初始偏移
        self.targetX = designX + self.offsetX
        self.targetY = designY + self.offsetY
        self.hasTarget = true
        -- 方向和力度由游戏脚本根据目标位置计算
        return true
    else
        -- 传统摇杆模式：计算相对于中心的偏移
        local dx = designX - self.pressStartX
        local dy = designY - self.pressStartY
        local dist = math.sqrt(dx * dx + dy * dy)

        -- 限制在移动范围内
        if dist > self.moveRadius then
            local scale = self.moveRadius / dist
            dx = dx * scale
            dy = dy * scale
        end

        self.knobX = self.pressStartX + dx
        self.knobY = self.pressStartY + dy

        -- 更新方向
        self:updateDirection()
    end

    -- 检测移动状态变化
    local isMoving = self.magnitude > self.deadZone

    if isMoving and not self.wasMoving and not self.isAccelActive then
        -- 开始移动（加速度计已在驱动时不重发 start，由统一边沿管理）
        self:_fireMoveStart(self.x, self.y, self.magnitude)
    end

    if isMoving then
        -- 移动中
        self:_fireMove(self.x, self.y, self.magnitude)
    end

    self.wasMoving = isMoving
    
    return true
end

function VirtualJoystick:handleTouchEnd(touchId)
    if self.touchId ~= touchId then
        return false
    end

    -- 检测移动结束（加速度计仍在驱动时不发 end，待其归零后由 accel 块收尾）
    if self.wasMoving and not self.isAccelActive then
        self:_fireMoveEnd(self.x, self.y, self.magnitude)
    end

    -- 触发释放回调
    self:_fireRelease(self.x, self.y, self.magnitude)

    -- 重置状态
    self.touchId = nil
    self.isActive = false
    self.wasMoving = false

    if self.isReleaseReset then
        local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
        self.pressStartX = centerX
        self.pressStartY = centerY
        self.knobX = centerX
        self.knobY = centerY
    end

    -- 清零方向
    self.x = 0
    self.y = 0
    self.magnitude = 0

    -- 全屏触控模式：清除目标
    if self.fullscreenTouch then
        self.hasTarget = false
    end

    return true
end

function VirtualJoystick:updateDirection()
    local dx = self.knobX - self.pressStartX
    local dy = self.knobY - self.pressStartY
    
    local normX, normY, len = normalize(dx, dy)
    
    -- 计算力度百分比
    self.magnitude = clamp(len / self.moveRadius, 0, 1)
    
    -- 应用死区
    if self.magnitude < self.deadZone then
        self.x = 0
        self.y = 0
        self.magnitude = 0
    else
        -- 重新映射死区外的值到 0-1
        local adjustedMag = (self.magnitude - self.deadZone) / (1 - self.deadZone)
        self.x = normX * adjustedMag
        self.y = normY * adjustedMag
        self.magnitude = adjustedMag
    end
    
    -- 计算角度
    if len > 0 then
        self.angle = math.atan2(dy, dx)
    end
end

--- 设置专属 Controller（优先于全局 Controller）
---@param controller table|nil Controller 对象，传 nil 恢复使用全局
function VirtualJoystick:setController(controller)
    self._controller = controller
end

--- 获取当前使用的 Controller（专属或全局）
---@return table|nil
function VirtualJoystick:getController()
    return self._controller or _globalController
end

--------------------------------------------------------------------------------
-- 便捷输入获取方法
--------------------------------------------------------------------------------

--- 获取已应用死区的原始输入值
--- 当摇杆在死区内时返回 0，否则返回 -1 到 1 的值
---@return number x, number y  范围 -1 到 1
function VirtualJoystick:getInput()
    local deadZone = self.deadZone or 0.1
    local x = math.abs(self.x) > deadZone and self.x or 0
    local y = math.abs(self.y) > deadZone and self.y or 0
    return x, y
end

--- 获取移动向量（通用方法）
--- 
--- 关于 invertY 参数：
---   - true  = 摇杆向上推时返回正值（默认，适用于大多数游戏）
---            3D游戏：前进方向是 Z+
---            2D游戏：使用数学坐标系（Y+ 向上）
---   - false = 摇杆向上推时返回负值（屏幕坐标系，Y+ 向下）
---
--- 示例：
---   local x, z = joystick:getMovement()       -- 3D游戏（默认反转）
---   local x, y = joystick:getMovement()       -- 2D数学坐标系
---   local x, y = joystick:getMovement(false)  -- 2D屏幕坐标系（不反转）
---
---@param invertY boolean|nil 是否反转Y轴（默认 true）
---@return number x, number y  已处理的移动值
function VirtualJoystick:getMovement(invertY)
    local x, y = self:getInput()
    -- 默认反转Y轴（大多数游戏需要：向上推=正值）
    if invertY == nil or invertY then
        y = -y
    end
    return x, y
end

--- 触发 move 事件（内部使用）
function VirtualJoystick:_fireMove(x, y, percent)
    local ctrl = self._controller or _globalController
    if ctrl and ctrl.move then
        ctrl:move(x, y, percent)
    elseif self.on_move then
        self.on_move(x, y, percent)
    end
end

--- 触发 moveStart 事件（内部使用）
function VirtualJoystick:_fireMoveStart(x, y, percent)
    local ctrl = self._controller or _globalController
    if ctrl and ctrl.onMoveStart then
        ctrl:onMoveStart(x, y, percent)
    elseif self.on_move_start then
        self.on_move_start(x, y, percent)
    end
end

--- 触发 moveEnd 事件（内部使用）
function VirtualJoystick:_fireMoveEnd(x, y, percent)
    local ctrl = self._controller or _globalController
    if ctrl and ctrl.onMoveEnd then
        ctrl:onMoveEnd(x, y, percent)
    elseif self.on_move_end then
        self.on_move_end(x, y, percent)
    end
end

--- 触发 press 事件（内部使用）
function VirtualJoystick:_firePress(x, y, percent)
    local ctrl = self._controller or _globalController
    if ctrl and ctrl.onPress then
        ctrl:onPress(x, y, percent)
    elseif self.on_press then
        self.on_press(x, y, percent)
    end
end

--- 触发 release 事件（内部使用）
function VirtualJoystick:_fireRelease(x, y, percent)
    local ctrl = self._controller or _globalController
    if ctrl and ctrl.onRelease then
        ctrl:onRelease(x, y, percent)
    elseif self.on_release then
        self.on_release(x, y, percent)
    end
end

function VirtualJoystick:update(dt)
    -- 检测键盘输入
    if self.keyBindingMap and not self.isActive then
        local keyUp = input:GetKeyDown(self.keyBindingMap.up)
        local keyDown = input:GetKeyDown(self.keyBindingMap.down)
        local keyLeft = input:GetKeyDown(self.keyBindingMap.left)
        local keyRight = input:GetKeyDown(self.keyBindingMap.right)
        
        self.keyStates.up = keyUp
        self.keyStates.down = keyDown
        self.keyStates.left = keyLeft
        self.keyStates.right = keyRight
        
        local anyKey = keyUp or keyDown or keyLeft or keyRight
        local wasKeyboardActive = self.isKeyboardActive
        
        if anyKey then
            -- 计算键盘方向
            local kx, ky = 0, 0
            if keyUp then ky = ky - 1 end
            if keyDown then ky = ky + 1 end
            if keyLeft then kx = kx - 1 end
            if keyRight then kx = kx + 1 end
            
            -- 归一化
            local len = math.sqrt(kx * kx + ky * ky)
            if len > 0 then
                self.x = kx / len
                self.y = ky / len
                self.magnitude = 1.0
                self.angle = math.atan2(ky, kx)
            end
            
            -- 更新摇杆位置用于渲染
            local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
            self.knobX = centerX + self.x * self.moveRadius
            self.knobY = centerY + self.y * self.moveRadius
            
            -- 触发回调
            if not wasKeyboardActive then
                -- 刚开始按键
                self.isKeyboardActive = true
                self:_fireMoveStart(self.x, self.y, self.magnitude)
            end
            -- 持续按键时触发 move
            self:_fireMove(self.x, self.y, self.magnitude)
        else
            if wasKeyboardActive then
                -- 键盘释放
                self:_fireMoveEnd(self.x, self.y, self.magnitude)
                
                self.x = 0
                self.y = 0
                self.magnitude = 0
                self.isKeyboardActive = false
                
                -- 重置摇杆位置
                local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
                self.knobX = centerX
                self.knobY = centerY
            end
        end
    end

    -- 加速度计输入（仅移动端）。与触摸统一边沿：任一源活跃即发一次 moveStart，
    -- 两者都归零才发 moveEnd。only：替换触摸；both：触摸移动时逐轴组合，否则独占。
    -- 注：键盘绑定仅 PC 端使用，移动端不与传感器并存，故此处只协调触摸 ↔ 加速度。
    if self.accelerometerMode ~= "none" and _isMobile then
        local ax, ay = TouchController.ReadAccelerometer()
        if self.accelerometerInvertX then ax = -ax end
        if self.accelerometerInvertY then ay = -ay end
        ax = ax * self.accelerometerSensitivity
        ay = ay * self.accelerometerSensitivity
        if ax >  1 then ax =  1 elseif ax < -1 then ax = -1 end
        if ay >  1 then ay =  1 elseif ay < -1 then ay = -1 end

        local accelMag = math.sqrt(ax * ax + ay * ay)
        if accelMag < self.accelerometerDeadZone then
            ax, ay, accelMag = 0, 0, 0
        else
            -- 死区外重映射到 [0,1]
            local adjusted = (accelMag - self.accelerometerDeadZone) / (1 - self.accelerometerDeadZone)
            if adjusted > 1 then adjusted = 1 end
            local scale = adjusted / accelMag
            ax, ay, accelMag = ax * scale, ay * scale, adjusted
        end

        -- 触摸是否在移动：唯一可能与传感器并存的输入源
        local touchMoving = self.wasMoving

        if accelMag > 0 then
            -- 合成方向：both 模式且触摸移动时逐轴组合（同号取大、异号相加），否则加速度独占
            local newX, newY
            if self.accelerometerMode == "both" and touchMoving then
                newX = _combineAxis(self.x, ax)
                newY = _combineAxis(self.y, ay)
                if newX >  1 then newX =  1 elseif newX < -1 then newX = -1 end
                if newY >  1 then newY =  1 elseif newY < -1 then newY = -1 end
            else
                newX, newY = ax, ay
            end

            self.x, self.y = newX, newY
            self.magnitude = math.min(math.sqrt(newX * newX + newY * newY), 1)
            if self.magnitude > 0 then
                self.angle = math.atan2(newY, newX)
            end

            -- 同步摇杆头位置用于渲染
            local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
            self.knobX = centerX + self.x * self.moveRadius
            self.knobY = centerY + self.y * self.moveRadius

            -- 边沿：加速度首次活跃且触摸未在移动时发统一 moveStart（触摸已活跃则其已发过）
            if not self.isAccelActive then
                self.isAccelActive = true
                if not touchMoving then
                    self:_fireMoveStart(self.x, self.y, self.magnitude)
                end
            end
            self:_fireMove(self.x, self.y, self.magnitude)
        elseif self.isAccelActive then
            -- 加速度跌回死区
            self.isAccelActive = false
            if not touchMoving then
                -- 加速度是最后一个活跃源：发统一 moveEnd 并归零
                self:_fireMoveEnd(self.x, self.y, self.magnitude)
                self.x, self.y, self.magnitude = 0, 0, 0
                local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
                self.knobX = centerX
                self.knobY = centerY
            end
            -- 触摸仍在移动时，x/y 交回触摸管理，不在此清零
        end
    end

    -- 平滑动画
    local isActiveOrKeyboard = self.isActive or self.isKeyboardActive or self.isAccelActive
    local targetOpacity = isActiveOrKeyboard and self.activeOpacity or self.opacity
    self.currentOpacity = lerp(self.currentOpacity, targetOpacity, dt * 10)

    local targetScale = isActiveOrKeyboard and 1.05 or 1.0
    self.currentScale = lerp(self.currentScale, targetScale, dt * 10)

    -- 更新全局 Controls2D
    if _globalControls2D then
        if self.hasTarget then
            -- 触控目标追踪模式：写入目标位置
            _globalControls2D._hasTarget = true
            _globalControls2D._targetX = self.targetX
            _globalControls2D._targetY = self.targetY
        else
            -- 普通摇杆/键盘模式：写入方向输入
            _globalControls2D._inputX = self.x
            _globalControls2D._inputY = self.y
            _globalControls2D._hasTarget = false
        end
    end
end

function VirtualJoystick:render(ctx)
    -- 如果摇杆不显示，直接返回
    if not self._shouldShow then
        return
    end
    
    local alpha = math.floor(self.currentOpacity * 255)
    local scale = self.currentScale
    
    -- 底盘中心（如果按下时移动中心，使用按下位置）
    local baseX = self.isActive and self.pressStartX or self.centerX
    local baseY = self.isActive and self.pressStartY or self.centerY
    
    if not self.isActive then
        baseX, baseY = calculateScreenPosition(self.position, self.alignment)
    end
    
    local baseRadius = self.baseRadius * scale
    local knobRadius = self.knobRadius * scale
    
    -- PC端有键盘绑定时，只显示WASD按键提示，不显示摇杆圆盘
    local showJoystickGraphics = _isMobile or not self.keyBindingMap
    
    if showJoystickGraphics then
        -- 绘制底盘外圈
        nvgBeginPath(ctx)
        nvgCircle(ctx, baseX, baseY, baseRadius)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(alpha * 0.3)))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 0.15)))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
        
        -- 绘制内圈指示线
        nvgBeginPath(ctx)
        nvgCircle(ctx, baseX, baseY, baseRadius * 0.5)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 0.2)))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
    end
    
    -- 绘制键盘按键提示（仅 PC 端、有键盘绑定、显示提示）
    if self.keyLabels and self.showKeyHints and not _isMobile then
        -- 键盘样式两行布局：
        --     第一行:     [W]
        --     第二行:  [A][S][D]
        -- 使用固定尺寸和透明度（不跟随摇杆动画）
        local fixedBaseRadius = self.baseRadius
        local keySize = fixedBaseRadius * 0.26
        local rowGap = keySize * 1.15   -- 行间距
        local colGap = keySize * 1.1    -- 列间距
        local fontSize = keySize * 0.55
        
        -- 使用固定透明度，不受摇杆整体高亮影响
        local keyAlpha = math.floor(self.opacity * 255)
        
        -- WASD 位置：独立于摇杆配置，贴近左下角
        -- 计算实际屏幕边缘在设计坐标系中的位置（含安全区）
        local screenLeftInDesign = -_offsetX / _scaleFactor
        local screenBottomInDesign = (_screenHeight - _offsetY) / _scaleFactor
        local safeLeft = _safeAreaInsets.left / _scaleFactor
        local safeBottom = _safeAreaInsets.bottom / _scaleFactor
        
        -- WASD 中心位置（S键位置）
        local leftOffset = 150   -- 距离左边缘（安全区外）
        local bottomOffset = 100 -- 距离底边缘（比右侧按钮更贴近底部）
        local keysCenterX = screenLeftInDesign + safeLeft + leftOffset
        local row2Y = screenBottomInDesign - safeBottom - bottomOffset  -- ASD 行
        local row1Y = row2Y - rowGap  -- W 行（在 ASD 上方）
        
        -- 键盘样式布局（使用独立的X位置）
        local keys = {
            {key = "up",    x = keysCenterX,              y = row1Y},  -- W
            {key = "left",  x = keysCenterX - colGap,     y = row2Y},  -- A
            {key = "down",  x = keysCenterX,              y = row2Y},  -- S
            {key = "right", x = keysCenterX + colGap,     y = row2Y},  -- D
        }
        
        nvgFontFace(ctx, "vcfont")
        nvgFontSize(ctx, fontSize)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        
        for _, k in ipairs(keys) do
            local kx = k.x
            local ky = k.y
            local label = self.keyLabels[k.key]
            local isPressed = self.keyStates[k.key]
            
            -- 按键背景（只有按下的键高亮）
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, kx - keySize/2, ky - keySize/2, keySize, keySize, keySize * 0.2)
            
            if isPressed then
                -- 按下状态：高亮蓝色
                nvgFillColor(ctx, nvgRGBA(100, 180, 255, 230))
            else
                -- 未按下状态：非常透明（弱化）
                nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(keyAlpha * 0.4)))
            end
            nvgFill(ctx)
            
            -- 按键边框
            if isPressed then
                nvgStrokeColor(ctx, nvgRGBA(150, 200, 255, 230))
            else
                nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(keyAlpha * 0.6)))
            end
            nvgStrokeWidth(ctx, 1)
            nvgStroke(ctx)
            
            -- 按键文字
            if isPressed then
                nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
            else
                nvgFillColor(ctx, nvgRGBA(255, 255, 255, keyAlpha))
            end
            nvgText(ctx, kx, ky, label)
        end
    end
    
    -- 绘制摇杆头（仅移动端或无键盘绑定时显示）
    if showJoystickGraphics then
        local knobX = (self.isActive or self.isKeyboardActive or self.isAccelActive) and self.knobX or baseX
        local knobY = (self.isActive or self.isKeyboardActive or self.isAccelActive) and self.knobY or baseY
        local knobAlpha = math.floor(alpha * 0.6)  -- 摇杆头整体更淡
        
        -- 摇杆头外发光
        local glowGrad = nvgRadialGradient(ctx, knobX, knobY, knobRadius * 0.5, knobRadius * 1.5,
            nvgRGBA(255, 255, 255, math.floor(alpha * 0.2)),
            nvgRGBA(255, 255, 255, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, knobX, knobY, knobRadius * 1.5)
        nvgFillPaint(ctx, glowGrad)
        nvgFill(ctx)
        
        -- 摇杆头实心
        local knobGrad = nvgRadialGradient(ctx, knobX, knobY - knobRadius * 0.3, knobRadius * 0.1, knobRadius,
            nvgRGBA(255, 255, 255, knobAlpha),
            nvgRGBA(200, 200, 200, knobAlpha))
        nvgBeginPath(ctx)
        nvgCircle(ctx, knobX, knobY, knobRadius)
        nvgFillPaint(ctx, knobGrad)
        nvgFill(ctx)
        
        -- 摇杆头边框
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 0.4)))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
    end
end

--------------------------------------------------------------------------------
-- VirtualButton 类
--------------------------------------------------------------------------------

---@class VirtualButton
---@field position Vector2 设计坐标位置
---@field alignment table 对齐方式 {横向, 纵向}
---@field radius number 按钮半径
---@field label string 按钮标签
---@field iconPath string|nil 图标路径
---@field cooldown number 冷却时间
---@field opacity number 默认透明度
---@field activeOpacity number 激活时透明度
---@field color table 颜色 {r, g, b}
---@field pressedColor table 按下时颜色 {r, g, b}
---@field keyBinding number|string|table|nil 键盘绑定
---@field mouseBinding number|string|table|nil 鼠标绑定
---@field showKeyHint boolean 是否显示按键提示
---@field alwaysShow boolean|nil 非移动端是否显示
---@field keyLabel string|nil 按键标签
---@field mouseLabel string|nil 鼠标标签
---@field mouseButton number|nil 鼠标按钮
---@field keyCodes table 键码数组
---@field keyCode number|nil 主键码
---@field toggle boolean 是否为切换模式
---@field isToggled boolean 切换状态
---@field _togglePending boolean 待切换标志
---@field isPressed boolean 是否按下
---@field isTouchPressed boolean 触摸是否按下
---@field isKeyPressed boolean 键盘是否按下
---@field isMousePressed boolean 鼠标是否按下
---@field pressTime number 按下时长
---@field cooldownRemaining number 剩余冷却时间
---@field touchId number|nil 触摸 ID
---@field currentOpacity number 当前透明度
---@field currentScale number 当前缩放
---@field _shouldShow boolean 是否应该显示
---@field on_press function|nil 按下回调
---@field on_release function|nil 释放回调
---@field on_hold function|nil 长按回调
---@field on_toggle function|nil 切换回调
local VirtualButton = {}
VirtualButton.__index = VirtualButton

function VirtualButton.new(config)
    local self = setmetatable({}, VirtualButton)
    
    -- 配置
    self.position = config.position or Vector2(-80, -80)
    self.alignment = config.alignment or {HA_RIGHT, VA_BOTTOM}
    self.radius = config.radius or 40
    self.label = config.label or ""
    self.iconPath = config.iconPath
    self.cooldown = config.cooldown or 0
    self.opacity = config.opacity or 0.5
    self.activeOpacity = config.activeOpacity or 0.9
    
    -- 颜色
    self.color = config.color or {255, 255, 255}
    self.pressedColor = config.pressedColor or {200, 220, 255}
    
    -- 键盘绑定
    -- keyBinding = KEY_SPACE 或 keyBinding = "SPACE" 或 keyBinding = {key = KEY_SPACE, label = "Space"}
    self.keyBinding = config.keyBinding
    -- 鼠标绑定（独立于键盘绑定）
    -- mouseBinding = MOUSEB_LEFT 或 mouseBinding = "LMB" 或 mouseBinding = {button = MOUSEB_LEFT, label = "LMB"}
    self.mouseBinding = config.mouseBinding
    self.showKeyHint = config.showKeyHint ~= false  -- 是否显示按键提示，默认 true
    self.alwaysShow = config.alwaysShow                  -- 非移动端是否显示按钮，nil 表示自动（有键盘绑定时不显示）
    self.keyLabel = nil  -- 按键显示标签

    -- 解析键盘绑定
    self.keyCodes = {}  -- 支持多个键码
    if self.keyBinding then
        if type(self.keyBinding) == "number" then
            -- 直接传入 KEY_* 常量
            self.keyCode = self.keyBinding
            table.insert(self.keyCodes, self.keyBinding)
            self.keyLabel = config.keyLabel  -- 需要手动指定标签
        elseif type(self.keyBinding) == "string" then
            -- 字符串形式，如 "SPACE", "E", "F"
            self.keyLabel = self.keyBinding
            -- 尝试转换为 KEY_* 常量
            local keyName = "KEY_" .. string.upper(self.keyBinding)
            self.keyCode = _G[keyName]
            if self.keyCode then
                table.insert(self.keyCodes, self.keyCode)
            end
        elseif type(self.keyBinding) == "table" then
            -- 表形式 {key = KEY_SPACE, label = "Space"}
            self.keyCode = self.keyBinding.key
            self.keyLabel = self.keyBinding.label
            if self.keyCode then
                table.insert(self.keyCodes, self.keyCode)
            end
        end
    end

    -- 解析 keyBindings（数组形式，支持多个键）
    if config.keyBindings then
        for _, kb in ipairs(config.keyBindings) do
            if type(kb) == "number" then
                table.insert(self.keyCodes, kb)
            elseif type(kb) == "string" then
                local keyName = "KEY_" .. string.upper(kb)
                if _G[keyName] then
                    table.insert(self.keyCodes, _G[keyName])
                end
            end
        end
    end

    -- 解析鼠标绑定
    if self.mouseBinding then
        if type(self.mouseBinding) == "number" then
            -- 直接传入 MOUSEB_* 常量
            self.mouseButton = self.mouseBinding
            -- 设置默认标签
            if self.mouseButton == MOUSEB_LEFT then
                self.mouseLabel = "LMB"
            elseif self.mouseButton == MOUSEB_RIGHT then
                self.mouseLabel = "RMB"
            elseif self.mouseButton == MOUSEB_MIDDLE then
                self.mouseLabel = "MMB"
            end
        elseif type(self.mouseBinding) == "string" then
            -- 字符串形式，如 "LMB", "RMB", "MMB"
            local upperBinding = string.upper(self.mouseBinding)
            if upperBinding == "LMB" or upperBinding == "LEFT" then
                self.mouseButton = MOUSEB_LEFT
                self.mouseLabel = "LMB"
            elseif upperBinding == "RMB" or upperBinding == "RIGHT" then
                self.mouseButton = MOUSEB_RIGHT
                self.mouseLabel = "RMB"
            elseif upperBinding == "MMB" or upperBinding == "MIDDLE" then
                self.mouseButton = MOUSEB_MIDDLE
                self.mouseLabel = "MMB"
            end
        elseif type(self.mouseBinding) == "table" then
            -- 表形式 {button = MOUSEB_LEFT, label = "LMB"}
            self.mouseButton = self.mouseBinding.button
            self.mouseLabel = self.mouseBinding.label
        end
    end
    
    -- 状态
    self.isPressed = false
    self.isTouchPressed = false   -- 触摸按下
    self.isKeyPressed = false     -- 键盘按下
    self.isMousePressed = false   -- 鼠标按下
    self.pressTime = 0
    self.cooldownRemaining = 0
    self.touchId = nil

    -- Toggle 模式：点击切换状态
    self.toggle = config.toggle or false
    self.isToggled = config.defaultToggled or false  -- 切换状态（toggle 模式下有效）
    self._togglePending = false  -- 等待释放时切换

    -- 动画
    self.currentOpacity = self.opacity
    self.currentScale = 1.0

    -- 回调
    self.on_press = config.on_press
    self.on_release = config.on_release
    self.on_hold = config.on_hold
    self.on_toggle = config.on_toggle  -- toggle 模式专用回调：function(isToggled)

    -- 初始化显示状态
    self:_updateShouldShow()
    
    return self
end

--- 更新按钮的显示状态（用于动态切换模式）
function VirtualButton:_updateShouldShow()
    -- 计算是否应该显示按钮
    -- 移动端：始终显示
    -- PC 端：
    --   alwaysShow = true  → 显示
    --   alwaysShow = false → 不显示
    --   alwaysShow = nil   → 有绑定时不显示，无绑定时显示（智能默认）
    if _isMobile then
        self._shouldShow = true
    else
        if self.alwaysShow == true then
            self._shouldShow = true
        elseif self.alwaysShow == false then
            self._shouldShow = false
        else
            -- nil：智能默认 - 有绑定就不显示（用户可以用键盘/鼠标）
            local hasBinding = (self.keyCodes and #self.keyCodes > 0) or self.mouseButton
            self._shouldShow = not hasBinding
        end
    end
end

function VirtualButton:handleTouchBegin(touchId, x, y)
    -- 如果按钮不显示，不处理触摸
    if not self._shouldShow then
        return false
    end
    
    if self.cooldownRemaining > 0 then
        return false
    end
    
    local designX, designY = screenToDesign(x, y)
    local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
    
    local dist = distance(designX, designY, centerX, centerY)
    if dist > self.radius * 1.2 then  -- 略大的点击区域
        return false
    end
    
    self.touchId = touchId
    self.isTouchPressed = true

    -- Toggle 模式：标记待切换
    if self.toggle then
        self._togglePending = true
    end

    -- 如果之前没有按下（键盘也没按），触发 on_press
    if not self.isPressed then
        self.isPressed = true
        self.pressTime = 0
        if self.on_press then
            self.on_press()
        end
    end

    return true
end

function VirtualButton:handleTouchMove(touchId, x, y)
    if self.touchId ~= touchId then
        return false
    end
    return true
end

function VirtualButton:handleTouchEnd(touchId)
    if self.touchId ~= touchId then
        return false
    end

    self.touchId = nil
    self.isTouchPressed = false

    -- Toggle 模式：切换状态
    if self.toggle and self._togglePending then
        self._togglePending = false
        self.isToggled = not self.isToggled
        self.isPressed = self.isToggled  -- toggle 模式下 isPressed 反映 isToggled
        if self.on_toggle then
            self.on_toggle(self.isToggled)
        end
        -- 开始冷却
        if self.cooldown > 0 then
            self.cooldownRemaining = self.cooldown
        end
        return true
    end

    -- 只有当键盘和鼠标都没按下时，才真正释放
    if not self.isKeyPressed and not self.isMousePressed then
        if self.on_release then
            self.on_release()
        end

        -- 开始冷却
        if self.cooldown > 0 then
            self.cooldownRemaining = self.cooldown
        end

        self.isPressed = false
    end

    return true
end

function VirtualButton:update(dt)
    -- 键盘输入检测（支持多个键）
    if #self.keyCodes > 0 and self.cooldownRemaining <= 0 then
        local keyDown = false
        for _, code in ipairs(self.keyCodes) do
            if input:GetKeyDown(code) then
                keyDown = true
                break
            end
        end

        if keyDown and not self.isKeyPressed then
            -- 键盘按下
            self.isKeyPressed = true

            -- Toggle 模式：标记待切换
            if self.toggle then
                self._togglePending = true
            end

            -- 如果触摸和鼠标都没按下，触发 on_press
            if not self.isTouchPressed and not self.isMousePressed then
                self.isPressed = true
                self.pressTime = 0
                if self.on_press then
                    self.on_press()
                end
            end
        elseif not keyDown and self.isKeyPressed then
            -- 键盘释放
            self.isKeyPressed = false

            -- Toggle 模式：切换状态
            if self.toggle and self._togglePending then
                self._togglePending = false
                self.isToggled = not self.isToggled
                self.isPressed = self.isToggled
                if self.on_toggle then
                    self.on_toggle(self.isToggled)
                end
                if self.cooldown > 0 then
                    self.cooldownRemaining = self.cooldown
                end
            -- 非 toggle 模式：只有当触摸和鼠标都没按下时，才真正释放
            elseif not self.toggle and not self.isTouchPressed and not self.isMousePressed then
                if self.on_release then
                    self.on_release()
                end

                -- 开始冷却
                if self.cooldown > 0 then
                    self.cooldownRemaining = self.cooldown
                end

                self.isPressed = false
            end
        end
    end

    -- 鼠标输入检测（鼠标模拟模式下禁用，避免与触摸模拟冲突）
    if self.mouseButton and self.cooldownRemaining <= 0 and not _mouseEmulationEnabled then
        local mouseDown = input:GetMouseButtonDown(self.mouseButton)

        if mouseDown and not self.isMousePressed then
            -- 鼠标按下
            self.isMousePressed = true

            -- Toggle 模式：标记待切换
            if self.toggle then
                self._togglePending = true
            end

            -- 如果触摸和键盘都没按下，触发 on_press
            if not self.isTouchPressed and not self.isKeyPressed then
                self.isPressed = true
                self.pressTime = 0
                if self.on_press then
                    self.on_press()
                end
            end
        elseif not mouseDown and self.isMousePressed then
            -- 鼠标释放
            self.isMousePressed = false

            -- Toggle 模式：切换状态
            if self.toggle and self._togglePending then
                self._togglePending = false
                self.isToggled = not self.isToggled
                self.isPressed = self.isToggled
                if self.on_toggle then
                    self.on_toggle(self.isToggled)
                end
                if self.cooldown > 0 then
                    self.cooldownRemaining = self.cooldown
                end
            -- 非 toggle 模式：只有当触摸和键盘都没按下时，才真正释放
            elseif not self.toggle and not self.isTouchPressed and not self.isKeyPressed then
                if self.on_release then
                    self.on_release()
                end

                -- 开始冷却
                if self.cooldown > 0 then
                    self.cooldownRemaining = self.cooldown
                end

                self.isPressed = false
            end
        end
    end

    -- 长按检测
    if self.isPressed then
        self.pressTime = self.pressTime + dt
        if self.on_hold then
            self.on_hold(self.pressTime)
        end
    end
    
    -- 冷却计时
    if self.cooldownRemaining > 0 then
        self.cooldownRemaining = self.cooldownRemaining - dt
    end
    
    -- 动画
    local targetOpacity = self.isPressed and self.activeOpacity or self.opacity
    self.currentOpacity = lerp(self.currentOpacity, targetOpacity, dt * 15)
    
    local targetScale = self.isPressed and 0.9 or 1.0
    self.currentScale = lerp(self.currentScale, targetScale, dt * 15)
end

function VirtualButton:render(ctx)
    -- 如果按钮不显示，直接返回
    if not self._shouldShow then
        return
    end
    
    local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
    local alpha = math.floor(self.currentOpacity * 255)
    local radius = self.radius * self.currentScale
    
    local r, g, b = self.color[1], self.color[2], self.color[3]
    if self.isPressed then
        r, g, b = self.pressedColor[1], self.pressedColor[2], self.pressedColor[3]
    end
    
    -- 按钮背景
    nvgBeginPath(ctx)
    nvgCircle(ctx, centerX, centerY, radius)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(alpha * 0.4)))
    nvgFill(ctx)
    
    -- 按钮边框
    nvgStrokeColor(ctx, nvgRGBA(r, g, b, alpha))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
    
    -- 冷却遮罩
    if self.cooldownRemaining > 0 and self.cooldown > 0 then
        local progress = self.cooldownRemaining / self.cooldown
        local startAngle = -math.pi / 2
        local endAngle = startAngle + progress * math.pi * 2
        
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, centerX, centerY)
        nvgArc(ctx, centerX, centerY, radius, startAngle, endAngle, NVG_CW)
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
        nvgFill(ctx)
    end
    
    -- 构建按键/鼠标提示文本
    local hintLabel = nil
    if self.showKeyHint and not _isMobile then
        if self.keyLabel and self.mouseLabel then
            hintLabel = self.keyLabel .. "/" .. self.mouseLabel
        elseif self.keyLabel then
            hintLabel = self.keyLabel
        elseif self.mouseLabel then
            hintLabel = self.mouseLabel
        end
    end

    -- 按钮标签
    if self.label ~= "" and _fontId ~= -1 then
        nvgFontFaceId(ctx, _fontId)
        nvgFontSize(ctx, radius * 0.55)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(r, g, b, alpha))

        -- 如果有按键提示，标签上移，按键显示在下方
        if hintLabel then
            nvgText(ctx, centerX, centerY - radius * 0.15, self.label, nil)

            -- 绘制按键提示（小字，在下方）
            nvgFontSize(ctx, radius * 0.35)
            nvgFillColor(ctx, nvgRGBA(r, g, b, math.floor(alpha * 0.7)))
            nvgText(ctx, centerX, centerY + radius * 0.30, "[" .. hintLabel .. "]", nil)
        else
            nvgText(ctx, centerX, centerY, self.label, nil)
        end
    elseif hintLabel and _fontId ~= -1 then
        -- 没有标签但有按键/鼠标提示
        nvgFontFaceId(ctx, _fontId)
        nvgFontSize(ctx, radius * 0.6)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(r, g, b, alpha))
        nvgText(ctx, centerX, centerY, hintLabel, nil)
    end
end

--------------------------------------------------------------------------------
-- VirtualWheel 类
--------------------------------------------------------------------------------

---@class VirtualWheel
---@field position Vector2 设计坐标位置
---@field alignment table 对齐方式 {横向, 纵向}
---@field radius number 外圈半径
---@field innerRadius number 内圈半径
---@field segments number 分段数量
---@field labels table 分段标签数组
---@field opacity number 默认透明度
---@field activeOpacity number 激活时透明度
---@field isActive boolean 是否激活
---@field selectedIndex number 选中的分段索引 (-1 为未选中)
---@field touchId number|nil 触摸 ID
---@field currentOpacity number 当前透明度
---@field on_select function|nil 选择回调
local VirtualWheel = {}
VirtualWheel.__index = VirtualWheel

function VirtualWheel.new(config)
    local self = setmetatable({}, VirtualWheel)
    
    -- 配置
    self.position = config.position or Vector2(-180, -180)
    self.alignment = config.alignment or {HA_RIGHT, VA_BOTTOM}
    self.radius = config.radius or 80
    self.innerRadius = config.innerRadius or 30
    self.segments = config.segments or 4
    self.labels = config.labels or {}
    self.opacity = config.opacity or 0.5
    self.activeOpacity = config.activeOpacity or 0.9
    
    -- 状态
    self.isActive = false
    self.selectedIndex = -1
    self.touchId = nil
    
    -- 动画
    self.currentOpacity = self.opacity
    
    -- 回调
    self.on_select = config.on_select
    
    return self
end

function VirtualWheel:handleTouchBegin(touchId, x, y)
    local designX, designY = screenToDesign(x, y)
    local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
    
    local dist = distance(designX, designY, centerX, centerY)
    if dist > self.radius or dist < self.innerRadius then
        return false
    end
    
    self.touchId = touchId
    self.isActive = true
    self:updateSelection(designX, designY)
    
    return true
end

function VirtualWheel:handleTouchMove(touchId, x, y)
    if self.touchId ~= touchId then
        return false
    end
    
    local designX, designY = screenToDesign(x, y)
    self:updateSelection(designX, designY)
    
    return true
end

function VirtualWheel:handleTouchEnd(touchId)
    if self.touchId ~= touchId then
        return false
    end
    
    if self.selectedIndex >= 0 and self.on_select then
        local label = self.labels[self.selectedIndex + 1] or ""
        self.on_select(self.selectedIndex, label)
    end
    
    self.touchId = nil
    self.isActive = false
    self.selectedIndex = -1
    
    return true
end

function VirtualWheel:updateSelection(x, y)
    local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
    
    local dx = x - centerX
    local dy = y - centerY
    local angle = math.atan2(dy, dx)
    
    -- 转换到 0-2π
    if angle < 0 then
        angle = angle + math.pi * 2
    end
    
    -- 计算选中的分段
    local segmentAngle = math.pi * 2 / self.segments
    self.selectedIndex = math.floor(angle / segmentAngle)
end

function VirtualWheel:update(dt)
    local targetOpacity = self.isActive and self.activeOpacity or self.opacity
    self.currentOpacity = lerp(self.currentOpacity, targetOpacity, dt * 10)
end

function VirtualWheel:render(ctx)
    local centerX, centerY = calculateScreenPosition(self.position, self.alignment)
    local alpha = math.floor(self.currentOpacity * 255)
    
    local segmentAngle = math.pi * 2 / self.segments
    
    for i = 0, self.segments - 1 do
        local startAngle = i * segmentAngle - math.pi / 2
        local endAngle = startAngle + segmentAngle
        
        local isSelected = (i == self.selectedIndex)
        local segAlpha = isSelected and alpha or math.floor(alpha * 0.6)
        
        -- 绘制分段
        nvgBeginPath(ctx)
        nvgArc(ctx, centerX, centerY, self.radius, startAngle, endAngle, NVG_CW)
        nvgArc(ctx, centerX, centerY, self.innerRadius, endAngle, startAngle, NVG_CCW)
        nvgClosePath(ctx)
        
        if isSelected then
            nvgFillColor(ctx, nvgRGBA(100, 150, 255, segAlpha))
        else
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(segAlpha * 0.4)))
        end
        nvgFill(ctx)
        
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(segAlpha * 0.6)))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
        
        -- 绘制标签
        if self.labels[i + 1] and _fontId ~= -1 then
            local midAngle = startAngle + segmentAngle / 2
            local labelRadius = (self.radius + self.innerRadius) / 2
            local labelX = centerX + math.cos(midAngle) * labelRadius
            local labelY = centerY + math.sin(midAngle) * labelRadius
            
            nvgFontFaceId(ctx, _fontId)
            nvgFontSize(ctx, 18)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, segAlpha))
            nvgText(ctx, labelX, labelY, self.labels[i + 1], nil)
        end
    end
end

--------------------------------------------------------------------------------
-- TouchLookArea 类（触摸视角控制区域）
--------------------------------------------------------------------------------

--- 获取当前时间（毫秒）
--- time 是 Urho3D Lua 的全局子系统对象
local function getTimeMs()
    return time:GetElapsedTime() * 1000
end

---@class TouchLookArea
---@field region table 矩形区域 {minX, maxX, minY, maxY}（设计坐标）
---@field sensitivity number 灵敏度
---@field invertY boolean 是否反转Y轴
---@field tapMaxDistance number Tap 判定最大移动距离（设计像素）
---@field tapMaxDuration number Tap 判定最大时长（毫秒）
---@field touchId number|nil 当前触摸 ID
---@field startX number 触摸起始 X（设计坐标）
---@field startY number 触摸起始 Y（设计坐标）
---@field startTime number 触摸起始时间（毫秒）
---@field lastX number 上次触摸 X（设计坐标）
---@field lastY number 上次触摸 Y（设计坐标）
---@field isDrag boolean 是否已判定为拖动
---@field totalDistance number 累计移动距离
---@field on_look function|nil 视角回调 function(deltaYaw, deltaPitch)
---@field on_tap function|nil 点击回调 function()
local TouchLookArea = {}
TouchLookArea.__index = TouchLookArea

function TouchLookArea.new(config)
    local self = setmetatable({}, TouchLookArea)
    
    -- 矩形区域配置（设计坐标）
    self.region = config.region or {
        minX = 960, maxX = 1920,  -- 默认右半屏
        minY = 0, maxY = 1080,
    }
    
    -- 预设区域
    if config.regionPreset == "right_half" then
        self.region = { minX = 960, maxX = 1920, minY = 0, maxY = 1080 }
    elseif config.regionPreset == "left_half" then
        self.region = { minX = 0, maxX = 960, minY = 0, maxY = 1080 }
    elseif config.regionPreset == "full_screen" then
        self.region = { minX = 0, maxX = 1920, minY = 0, maxY = 1080 }
    end
    
    self.sensitivity = config.sensitivity or 0.15
    self.invertY = config.invertY or false
    
    -- Tap/Drag 判定配置
    self.tapMaxDistance = config.tapMaxDistance or 10
    self.tapMaxDuration = config.tapMaxDuration or 300
    
    -- 状态
    self.touchId = nil
    self.startX = 0
    self.startY = 0
    self.startTime = 0
    self.lastX = 0
    self.lastY = 0
    self.isDrag = false
    self.totalDistance = 0
    
    -- 回调
    self.on_look = config.on_look      -- function(deltaYaw, deltaPitch)
    self.on_tap = config.on_tap        -- function() - 短点击（攻击）
    
    return self
end

--- 检查坐标是否在区域内
---@param x number 屏幕坐标 X
---@param y number 屏幕坐标 Y
---@return boolean
function TouchLookArea:isInRegion(x, y)
    local designX, designY = screenToDesign(x, y)
    local r = self.region
    return designX >= r.minX and designX <= r.maxX
       and designY >= r.minY and designY <= r.maxY
end

--- 处理触摸开始
---@param touchId number 触摸 ID
---@param x number 屏幕坐标 X
---@param y number 屏幕坐标 Y
---@return boolean 是否处理了此触摸
function TouchLookArea:handleTouchBegin(touchId, x, y)
    -- 仅移动端生效
    if not _isMobile then
        return false
    end
    
    if not self:isInRegion(x, y) then
        return false
    end
    
    self.touchId = touchId
    self.startX, self.startY = screenToDesign(x, y)
    self.lastX, self.lastY = self.startX, self.startY
    self.startTime = getTimeMs()
    self.isDrag = false
    self.totalDistance = 0
    
    return true
end

--- 处理触摸移动
---@param touchId number 触摸 ID
---@param x number 屏幕坐标 X
---@param y number 屏幕坐标 Y
---@return boolean 是否处理了此触摸
function TouchLookArea:handleTouchMove(touchId, x, y)
    if self.touchId ~= touchId then return false end
    
    local designX, designY = screenToDesign(x, y)
    local dx = designX - self.lastX
    local dy = designY - self.lastY
    
    self.totalDistance = self.totalDistance + math.sqrt(dx * dx + dy * dy)
    
    -- 超过阈值，判定为 Drag
    if self.totalDistance >= self.tapMaxDistance then
        self.isDrag = true
    end
    
    -- 如果是 Drag，触发视角控制
    if self.isDrag and self.on_look then
        local deltaYaw = dx * self.sensitivity
        local deltaPitch = dy * self.sensitivity
        if self.invertY then deltaPitch = -deltaPitch end
        self.on_look(deltaYaw, deltaPitch)
    end
    
    self.lastX, self.lastY = designX, designY
    return true
end

--- 处理触摸结束
---@param touchId number 触摸 ID
---@return boolean 是否处理了此触摸
function TouchLookArea:handleTouchEnd(touchId)
    if self.touchId ~= touchId then return false end
    
    local elapsed = getTimeMs() - self.startTime
    
    -- 如果是 Tap（短点击），触发攻击回调
    if not self.isDrag and elapsed < self.tapMaxDuration then
        if self.on_tap then
            self.on_tap()
        end
    end
    
    self.touchId = nil
    return true
end

--- 更新（每帧调用）
function TouchLookArea:update(dt)
    -- TouchLookArea 不需要每帧更新
end

--- 渲染（每帧调用）
--- TouchLookArea 是透明区域，不渲染任何内容
function TouchLookArea:render(ctx)
    -- 透明区域，不渲染
end

--------------------------------------------------------------------------------
-- 公共 API
--------------------------------------------------------------------------------

--- 初始化虚拟控制系统
--- 使用设计分辨率进行布局，短边缩放模式（保证 UI 元素大小在不同宽高比设备上一致）
---@param designWidth number|nil 设计宽度（可选，默认 1920）
---@param designHeight number|nil 设计高度（可选，默认 1080）
function VirtualControls.Initialize(designWidth, designHeight)
    -- 检测平台
    local platform = GetNativePlatform()
    _isMobile = (platform == "Android" or platform == "iOS" or platform == "HarmonyOS" or input.touchEmulation)
    
    -- 设置设计分辨率
    _designWidth = designWidth or 1920
    _designHeight = designHeight or 1080
    _designShortSide = math.min(_designWidth, _designHeight)
    
    -- 获取屏幕尺寸
    local graphics = GetGraphics()
    _screenWidth = graphics:GetWidth()
    _screenHeight = graphics:GetHeight()
    
    -- 计算缩放因子（短边缩放：保证 UI 元素在不同宽高比设备上大小一致）
    _scaleFactor = math.min(_screenWidth, _screenHeight) / _designShortSide
    
    -- 计算偏移（居中显示）
    local scaledWidth = _designWidth * _scaleFactor
    local scaledHeight = _designHeight * _scaleFactor
    _offsetX = (_screenWidth - scaledWidth) / 2
    _offsetY = (_screenHeight - scaledHeight) / 2
    
    -- 获取安全区边距（刘海/圆角等）
    _safeAreaInsets = getSafeAreaInsets()
    
    -- 创建 NanoVG 上下文（如果还没创建）
    if not _nvgContext then
        _nvgContext = nvgCreate(1)
        if _nvgContext == nil then
            print("ERROR: VirtualControls - Failed to create NanoVG context")
            return false
        end

        -- 设置超高渲染优先级，确保虚拟控件始终在最上层
        nvgSetRenderOrder(_nvgContext, 999999)

        -- 加载字体
        _fontId = nvgCreateFont(_nvgContext, "vcfont", "Fonts/MiSans-Regular.ttf")
        if _fontId == -1 then
            print("WARNING: VirtualControls - Failed to load font, labels will not be displayed")
        end
    end
    
    _initialized = true
    print(string.format("[VirtualControls] Initialized: design=%dx%d, screen=%dx%d, scale=%.3f, offset=(%.0f,%.0f), mobile=%s",
        _designWidth, _designHeight, _screenWidth, _screenHeight, _scaleFactor, _offsetX, _offsetY, tostring(_isMobile)))
    if _safeAreaInsets.left > 0 or _safeAreaInsets.top > 0 or _safeAreaInsets.right > 0 or _safeAreaInsets.bottom > 0 then
        print(string.format("[VirtualControls] Safe area insets: left=%.0f, top=%.0f, right=%.0f, bottom=%.0f",
            _safeAreaInsets.left, _safeAreaInsets.top, _safeAreaInsets.right, _safeAreaInsets.bottom))
    end

    -- Update 在帧开始时调用，减少输入延迟
    SubscribeToEvent("BeginFrame", "_VirtualControls_HandleUpdate")
    -- Render 在 NanoVG 渲染时调用
    SubscribeToEvent(_nvgContext, "NanoVGRender", "_VirtualControls_HandleRender")

    return true
end

--- 内部 Update 事件处理（BeginFrame）
function _VirtualControls_HandleUpdate(eventType, eventData)
    VirtualControls.Update()
end

--- 内部 NanoVG Render 事件处理
function _VirtualControls_HandleRender(eventType, eventData)
    VirtualControls.Render()
end

--- 销毁虚拟控制系统
function VirtualControls.Shutdown()
    if _nvgContext then
        nvgDelete(_nvgContext)
        _nvgContext = nil
    end

    _joysticks = {}
    _buttons = {}
    _wheels = {}
    _touchLookAreas = {}
    _touchOwners = {}
    _globalController = nil
    _initialized = false
end

--- 自动初始化（内部使用）
local function _autoInitialize()
    if _initialized then return true end
    return VirtualControls.Initialize()
end

--- 创建摇杆
---@param config table 配置
---@return VirtualJoystick
function VirtualControls.CreateJoystick(config)
    _autoInitialize()
    local joystick = VirtualJoystick.new(config or {})
    table.insert(_joysticks, joystick)
    return joystick
end

--- 创建按钮
---@param config table 配置
---@return VirtualButton
function VirtualControls.CreateButton(config)
    _autoInitialize()
    local button = VirtualButton.new(config or {})
    table.insert(_buttons, button)
    return button
end

--- 创建技能轮盘
---@param config table 配置
---@return VirtualWheel
function VirtualControls.CreateWheel(config)
    _autoInitialize()
    local wheel = VirtualWheel.new(config or {})
    table.insert(_wheels, wheel)
    return wheel
end

--- 创建触摸视角控制区域
--- 仅在移动端生效，PC 端由鼠标控制视角
---@param config table 配置
---  - region: {minX, maxX, minY, maxY} 矩形区域（设计坐标）
---  - regionPreset: "right_half" | "left_half" | "full_screen" 预设区域
---  - sensitivity: number 灵敏度（默认 0.15）
---  - invertY: boolean 是否反转Y轴（默认 false）
---  - tapMaxDistance: number Tap 判定最大移动距离（默认 10）
---  - tapMaxDuration: number Tap 判定最大时长毫秒（默认 300）
---  - on_look: function(deltaYaw, deltaPitch) 视角回调
---  - on_tap: function() 点击回调
---@return TouchLookArea
function VirtualControls.CreateTouchLookArea(config)
    _autoInitialize()
    local touchLookArea = TouchLookArea.new(config or {})
    table.insert(_touchLookAreas, touchLookArea)
    return touchLookArea
end

--- 移除触摸视角控制区域
---@param touchLookArea TouchLookArea 要移除的实例
function VirtualControls.RemoveTouchLookArea(touchLookArea)
    for i, area in ipairs(_touchLookAreas) do
        if area == touchLookArea then
            -- 清理触摸所有权
            for touchId, owner in pairs(_touchOwners) do
                if owner == touchLookArea then
                    _touchOwners[touchId] = nil
                end
            end
            table.remove(_touchLookAreas, i)
            return true
        end
    end
    return false
end

--- 设置全局 Controls 对象（简化模式）
--- 摇杆输入会自动转换为 CTRL_FORWARD/BACK/LEFT/RIGHT
---@param controls userdata Urho3D Controls 对象
---@param options table|nil 可选配置 {threshold = 0.1}
function VirtualControls.SetControls(controls, options)
    if controls == nil then
        _globalController = nil
        return
    end
    
    options = options or {}
    local threshold = options.threshold or 0.1
    
    -- 创建内置的 Controls 适配器
    _globalController = {
        controls = controls,
        threshold = threshold,

        move = function(self, x, y, percent)
            local c = self.controls
            -- 设置连续摇杆值到 extraData（用于 CharacterComponent 精确方向计算）
            c.extraData["joystickX"] = Variant(x)
            c.extraData["joystickY"] = Variant(y)
            -- 同时设置布尔控制标志（兼容老代码）
            -- 注意：摇杆 Y 轴向下为正，向上推（负 Y）对应前进
            c:Set(CTRL_FORWARD, y < -self.threshold)
            c:Set(CTRL_BACK, y > self.threshold)
            c:Set(CTRL_LEFT, x < -self.threshold)
            c:Set(CTRL_RIGHT, x > self.threshold)
        end,

        onMoveEnd = function(self)
            -- 移动结束时清除所有方向控制
            local c = self.controls
            c.extraData["joystickX"] = Variant()
            c.extraData["joystickY"] = Variant()
            c:Set(CTRL_FORWARD, false)
            c:Set(CTRL_BACK, false)
            c:Set(CTRL_LEFT, false)
            c:Set(CTRL_RIGHT, false)
        end,

        onRelease = function(self)
            -- 释放时也清除方向控制
            local c = self.controls
            c.extraData["joystickX"] = Variant()
            c.extraData["joystickY"] = Variant()
            c:Set(CTRL_FORWARD, false)
            c:Set(CTRL_BACK, false)
            c:Set(CTRL_LEFT, false)
            c:Set(CTRL_RIGHT, false)
        end,
    }
end

--- 设置全局 Controller（高级模式）
--- Controller 需要实现 move(x, y, percent) 方法
---@param controller table|nil Controller 对象
function VirtualControls.SetController(controller)
    _globalController = controller
end

--- 获取当前全局 Controller
---@return table|nil
function VirtualControls.GetController()
    return _globalController
end

--- 设置全局 Controls2D（2D 游戏模式）
--- 摇杆输入会自动更新 Controls2D 的位置
---@param controls2d Controls2D|nil Controls2D 对象
function VirtualControls.SetControls2D(controls2d)
    _globalControls2D = controls2d
end

--- 获取当前全局 Controls2D
---@return Controls2D|nil
function VirtualControls.GetControls2D()
    return _globalControls2D
end

--- 设置移动端模式（用于开发调试）
--- 切换后会重新计算所有组件的显示状态
---@param isMobile boolean 是否为移动端模式
function VirtualControls.SetMobileMode(isMobile)
    _isMobile = isMobile
    -- 更新所有摇杆的 _shouldShow
    for _, joystick in ipairs(_joysticks) do
        joystick:_updateShouldShow()
    end
    -- 更新所有按钮的 _shouldShow
    for _, button in ipairs(_buttons) do
        button:_updateShouldShow()
    end
    print("[VirtualControls] Mobile mode: " .. tostring(_isMobile))
end

--- 获取当前是否为移动端模式
---@return boolean
function VirtualControls.IsMobileMode()
    return _isMobile
end

--- 更新（每帧调用）
function VirtualControls.Update()
    if not _initialized then
        _autoInitialize()
    end
    if not _initialized then return end
    
    local dt = GetTime():GetElapsedTime() - (VirtualControls._lastTime or 0)
    VirtualControls._lastTime = GetTime():GetElapsedTime()
    dt = math.min(dt, 0.1)  -- 限制最大 dt
    
    -- 处理触摸事件
    VirtualControls._processTouchEvents()
    
    -- 更新所有组件
    for _, joystick in ipairs(_joysticks) do
        joystick:update(dt)
    end
    
    for _, button in ipairs(_buttons) do
        button:update(dt)
    end
    
    for _, wheel in ipairs(_wheels) do
        wheel:update(dt)
    end

    for _, touchLookArea in ipairs(_touchLookAreas) do
        touchLookArea:update(dt)
    end

    -- 更新全局 Controls2D（在所有组件更新后）
    if _globalControls2D then
        _globalControls2D:update(dt)
    end
end

--- 渲染（每帧调用，在 EndAllViewsRender 事件中）
function VirtualControls.Render()
    if not _initialized or not _nvgContext then return end
    
    -- 检查屏幕尺寸变化，重新计算缩放
    local graphics = GetGraphics()
    local newWidth = graphics:GetWidth()
    local newHeight = graphics:GetHeight()
    
    if newWidth ~= _screenWidth or newHeight ~= _screenHeight then
        _screenWidth = newWidth
        _screenHeight = newHeight
        
        -- 重新计算缩放因子和偏移（短边缩放）
        _scaleFactor = math.min(_screenWidth, _screenHeight) / _designShortSide
        
        local scaledWidth = _designWidth * _scaleFactor
        local scaledHeight = _designHeight * _scaleFactor
        _offsetX = (_screenWidth - scaledWidth) / 2
        _offsetY = (_screenHeight - scaledHeight) / 2
        
        -- 重新获取安全区边距（屏幕旋转时可能变化）
        _safeAreaInsets = getSafeAreaInsets()
    end
    
    -- 开始 NanoVG 帧
    nvgBeginFrame(_nvgContext, _screenWidth, _screenHeight, 1.0)
    
    -- 应用偏移和缩放变换（设计坐标 -> 屏幕坐标）
    nvgTranslate(_nvgContext, _offsetX, _offsetY)
    nvgScale(_nvgContext, _scaleFactor, _scaleFactor)
    
    -- 渲染所有组件（使用设计坐标）
    for _, joystick in ipairs(_joysticks) do
        joystick:render(_nvgContext)
    end
    
    for _, button in ipairs(_buttons) do
        button:render(_nvgContext)
    end
    
    for _, wheel in ipairs(_wheels) do
        wheel:render(_nvgContext)
    end

    for _, touchLookArea in ipairs(_touchLookAreas) do
        touchLookArea:render(_nvgContext)
    end
    
    -- 结束 NanoVG 帧
    nvgEndFrame(_nvgContext)
end

-- 鼠标模拟触摸的特殊 ID
local MOUSE_TOUCH_ID = -1

--- 启用/禁用鼠标模拟触摸（仅用于开发调试）
--- 启用后，鼠标左键会模拟触摸输入，同时禁用按钮的鼠标绑定检测
---@param enabled boolean
function VirtualControls.SetMouseEmulation(enabled)
    _mouseEmulationEnabled = enabled
    print("[VirtualControls] Mouse emulation: " .. tostring(enabled))
end

--- 获取鼠标模拟状态
---@return boolean
function VirtualControls.IsMouseEmulationEnabled()
    return _mouseEmulationEnabled
end

--- 处理触摸事件
function VirtualControls._processTouchEvents()
    local numTouches = input.numTouches
    local activeTouchIds = {}
    
    -- 处理真实触摸
    for i = 0, numTouches - 1 do
        local touch = input:GetTouch(i)
        local touchId = touch.touchID
        activeTouchIds[touchId] = true
        
        -- 跳过在 UI 元素上的触摸（避免与 Urho3D UI 系统冲突）
        if touch.touchedElement then
            -- 但仍需跟踪已有 owner 的触摸，以便正确结束
            goto continue
        end
        
        local x, y = touch.position.x, touch.position.y
        VirtualControls._handleTouchInput(touchId, x, y, activeTouchIds)
        
        ::continue::
    end
    
    -- 鼠标模拟触摸（仅在启用时生效，用于PC端调试移动端UI）
    if _mouseEmulationEnabled then
        local mouseDown = input:GetMouseButtonDown(MOUSEB_LEFT)
        local mousePos = input.mousePosition
        local x, y = mousePos.x, mousePos.y
        
        if mouseDown then
            activeTouchIds[MOUSE_TOUCH_ID] = true
            VirtualControls._handleTouchInput(MOUSE_TOUCH_ID, x, y, activeTouchIds)
        end
    end
    
    -- 检查结束的触摸
    for touchId, owner in pairs(_touchOwners) do
        if not activeTouchIds[touchId] then
            owner:handleTouchEnd(touchId)
            _touchOwners[touchId] = nil
        end
    end
end

--- 处理单个触摸/鼠标输入
--- 优先级顺序：按钮 > 摇杆 > 轮盘 > TouchLookArea（兜底）
function VirtualControls._handleTouchInput(touchId, x, y, activeTouchIds)
    -- 检查是否是新触摸
    if not _touchOwners[touchId] then
        -- 尝试分配给组件
        local handled = false

        -- 1. 优先检查按钮（按钮区域精确，应优先于全屏摇杆）
        for _, button in ipairs(_buttons) do
            -- toggle 模式允许在 isPressed 状态下再次点击
            local canHandle = not button.isTouchPressed and (button.toggle or not button.isPressed)
            if canHandle and button:handleTouchBegin(touchId, x, y) then
                _touchOwners[touchId] = button
                handled = true
                break
            end
        end

        -- 2. 然后检查摇杆
        if not handled then
            for _, joystick in ipairs(_joysticks) do
                if not joystick.isActive and joystick:handleTouchBegin(touchId, x, y) then
                    _touchOwners[touchId] = joystick
                    handled = true
                    break
                end
            end
        end

        -- 3. 然后检查轮盘
        if not handled then
            for _, wheel in ipairs(_wheels) do
                if not wheel.isActive and wheel:handleTouchBegin(touchId, x, y) then
                    _touchOwners[touchId] = wheel
                    handled = true
                    break
                end
            end
        end

        -- 4. 最后检查 TouchLookArea（最低优先级，作为大面积兜底）
        if not handled then
            for _, touchLookArea in ipairs(_touchLookAreas) do
                if not touchLookArea.touchId and touchLookArea:handleTouchBegin(touchId, x, y) then
                    _touchOwners[touchId] = touchLookArea
                    handled = true
                    break
                end
            end
        end
    else
        -- 已有所有者，发送移动事件
        local owner = _touchOwners[touchId]
        owner:handleTouchMove(touchId, x, y)
    end
end

--- 获取屏幕尺寸（实际像素）
---@return number, number
function VirtualControls.GetScreenSize()
    return _screenWidth, _screenHeight
end

--- 获取设计分辨率
---@return number, number
function VirtualControls.GetDesignSize()
    return _designWidth, _designHeight
end

--- 获取缩放因子
---@return number
function VirtualControls.GetScaleFactor()
    return _scaleFactor
end

--- 检查某个触摸 ID 是否被虚拟控件占用
---@param touchId number 触摸 ID
---@return boolean 是否被占用
function VirtualControls.IsTouchOccupied(touchId)
    return _touchOwners[touchId] ~= nil
end

--- 检查是否为移动平台
---@return boolean
function VirtualControls.IsMobile()
    if _initialized then
        return _isMobile
    end
    -- 未初始化时直接检测平台
    local platform = GetNativePlatform()
    return (platform == "Android" or platform == "iOS" or platform == "HarmonyOS" or (input and input.touchEmulation))
end

--- 清除所有组件
function VirtualControls.Clear()
    _joysticks = {}
    _buttons = {}
    _wheels = {}
    _touchLookAreas = {}
    _touchOwners = {}
    _globalController = nil
end

return VirtualControls
