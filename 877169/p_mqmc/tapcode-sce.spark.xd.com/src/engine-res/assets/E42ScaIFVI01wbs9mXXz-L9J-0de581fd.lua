-- TouchCamera.lua
-- 触摸相机控制（3D）
-- 来源：从 Sample.lua 提取

---@class TouchCamera
local TouchCamera = {}

---@class TouchCameraConfig
---@field touchSensitivity number
---@field enabled boolean

---配置
---@type TouchCameraConfig
TouchCamera.config = {
    touchSensitivity = 2,
    enabled = false
}

-- 状态
---@type Node|nil
TouchCamera.cameraNode = nil
---@type number
TouchCamera.yaw = 0
---@type number
TouchCamera.pitch = 0

---初始化触摸相机控制
---@param cameraNode Node 相机节点
---@param options? {touchSensitivity?: number, initialYaw?: number, initialPitch?: number, useNodeRotation?: boolean} 配置选项
function TouchCamera.Initialize(cameraNode, options)
    options = options or {}
    
    TouchCamera.cameraNode = cameraNode
    TouchCamera.config.enabled = true
    
    if options.touchSensitivity then
        TouchCamera.config.touchSensitivity = options.touchSensitivity
    end
    
    -- 初始角度
    if options.initialYaw then
        TouchCamera.yaw = options.initialYaw
    end
    if options.initialPitch then
        TouchCamera.pitch = options.initialPitch
    end
    
    -- 从相机节点获取初始旋转
    if cameraNode and options.useNodeRotation then
        local rotation = cameraNode.rotation
        TouchCamera.yaw = rotation.yawAngle
        TouchCamera.pitch = rotation.pitchAngle
    end
end

---更新触摸相机（在 SceneUpdate 或 Update 中调用）
---@param touchEnabled boolean 是否启用触摸（通常来自 InputManager.IsTouchEnabled()）
function TouchCamera.Update(touchEnabled)
    if not TouchCamera.config.enabled then
        return
    end

    if not touchEnabled then
        return
    end

    if not TouchCamera.cameraNode then
        log:Write(LOG_WARNING, "TouchCamera.Update: Camera node is nil, did you call Initialize()?")
        return
    end

    local camera = TouchCamera.cameraNode:GetComponent("Camera")
    if not camera then
        log:Write(LOG_ERROR, "TouchCamera.Update: Camera component not found on camera node")
        return
    end

    -- 处理所有触摸点
    -- Note: input:GetTouch() uses 0-based indexing (C++ API)
    for i = 0, input:GetNumTouches() - 1 do
        local state = input:GetTouch(i)
        
        -- 仅处理空白区域的触摸（不在 UI 元素上）
        if not state.touchedElement then
            if state.delta.x ~= 0 or state.delta.y ~= 0 then
                -- 根据触摸移动旋转相机
                local sensitivity = TouchCamera.config.touchSensitivity
                local fov = camera.fov
                local height = graphics.height
                
                TouchCamera.yaw = TouchCamera.yaw + sensitivity * fov / height * state.delta.x
                TouchCamera.pitch = TouchCamera.pitch + sensitivity * fov / height * state.delta.y
                
                -- 限制俯仰角（避免翻转）
                TouchCamera.pitch = Clamp(TouchCamera.pitch, -89, 89)
                
                -- 应用旋转（roll 固定为 0）
                TouchCamera.cameraNode:SetRotation(Quaternion(TouchCamera.pitch, TouchCamera.yaw, 0))
            else
                -- 没有拖动：将光标移动到触摸位置
                local cursor = ui:GetCursor()
                if cursor and cursor:IsVisible() then
                    cursor:SetPosition(state.position)
                end
            end
        end
    end
end

---设置相机节点
---@param cameraNode Node
function TouchCamera.SetCameraNode(cameraNode)
    TouchCamera.cameraNode = cameraNode
end

---获取相机节点
---@return Node|nil
function TouchCamera.GetCameraNode()
    return TouchCamera.cameraNode
end

---设置偏航角
---@param yaw number
function TouchCamera.SetYaw(yaw)
    TouchCamera.yaw = yaw
    TouchCamera._UpdateRotation()
end

---设置俯仰角
---@param pitch number
function TouchCamera.SetPitch(pitch)
    TouchCamera.pitch = Clamp(pitch, -89, 89)
    TouchCamera._UpdateRotation()
end

---获取偏航角
---@return number
function TouchCamera.GetYaw()
    return TouchCamera.yaw
end

---获取俯仰角
---@return number
function TouchCamera.GetPitch()
    return TouchCamera.pitch
end

---重置旋转
---@param yaw? number 默认 0
---@param pitch? number 默认 0
function TouchCamera.Reset(yaw, pitch)
    TouchCamera.yaw = yaw or 0
    TouchCamera.pitch = pitch or 0
    TouchCamera._UpdateRotation()
end

---启用/禁用触摸相机
---@param enabled boolean
function TouchCamera.SetEnabled(enabled)
    TouchCamera.config.enabled = enabled
end

---是否已启用
---@return boolean
function TouchCamera.IsEnabled()
    return TouchCamera.config.enabled
end

-- 内部方法：更新旋转
function TouchCamera._UpdateRotation()
    if TouchCamera.cameraNode then
        TouchCamera.cameraNode:SetRotation(Quaternion(TouchCamera.pitch, TouchCamera.yaw, 0))
    end
end

return TouchCamera

