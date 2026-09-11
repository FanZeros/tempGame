-- PathFollower.lua
-- 路径跟随组件（纯通用实现）
-- 来源：从 Mover.lua 重构，移除游戏特定逻辑

local PathFollower = ScriptObject()

--- 初始化
function PathFollower:Start()
    self.speed = 0.8           -- 移动速度
    self.path = {}             -- 路径点数组（Vector2）
    self.currentPathID = 1     -- 当前目标点索引（Lua 从 1 开始）
    self.loop = false          -- 是否循环
    self.reverse = true        -- 是否往返（不循环时）
    self.paused = false        -- 是否暂停
    
    -- 回调函数（可选）
    self.onReachWaypoint = nil    -- function(waypointIndex)
    self.onPathComplete = nil     -- function()
    self.onDirectionChange = nil  -- function(direction)
end

--- 加载（序列化）
function PathFollower:Load(deserializer)
    self:SetPathAttr(deserializer:ReadBuffer())
end

--- 保存（序列化）
function PathFollower:Save(serializer)
    serializer:WriteBuffer(self:GetPathAttr())
end

--- 设置路径（用于序列化）
function PathFollower:SetPathAttr(buffer)
    if buffer.size == 0 then
        return
    end
    
    self.path = {}
    while not buffer.eof do
        table.insert(self.path, buffer:ReadVector2())
    end
end

--- 获取路径（用于序列化）
function PathFollower:GetPathAttr()
    local ret = VectorBuffer()
    for i = 1, #self.path do
        ret:WriteVector2(self.path[i])
    end
    return ret
end

---设置路径
---@param path table Vector2 数组
function PathFollower:SetPath(path)
    self.path = path or {}
    if #self.path >= 2 then
        self.currentPathID = 2  -- 从第二个点开始（第一个点是起始位置）
    else
        self.currentPathID = 1
    end
end

---获取路径
---@return table Vector2 数组
function PathFollower:GetPath()
    return self.path
end

---设置速度
---@param speed number 正数向前，负数向后
function PathFollower:SetSpeed(speed)
    self.speed = speed
end

---获取速度
---@return number
function PathFollower:GetSpeed()
    return self.speed
end

---设置是否循环
---@param loop boolean
function PathFollower:SetLoop(loop)
    self.loop = loop
end

---设置是否往返（不循环时有效）
---@param reverse boolean
function PathFollower:SetReverse(reverse)
    self.reverse = reverse
end

---暂停/恢复
---@param paused boolean
function PathFollower:SetPaused(paused)
    self.paused = paused
end

---是否已暂停
---@return boolean
function PathFollower:IsPaused()
    return self.paused
end

--- 重置到起点
function PathFollower:Reset()
    if #self.path >= 2 then
        self.currentPathID = 2
        self.speed = math.abs(self.speed)
        if #self.path > 0 then
            self.node.position2D = self.path[1]
        end
    end
end

--- 更新（每帧调用）
function PathFollower:Update(timeStep)
    if #self.path < 2 or self.paused then
        return
    end
    
    local node = self.node
    
    -- 计算方向和移动
    local targetPos = self.path[self.currentPathID]
    local currentPos = node.position2D
    local dir = targetPos - currentPos
    local distance = dir:Length()
    
    if distance > 0.01 then
        -- 还未到达目标点：继续移动
        local dirNormal = dir:Normalized()
        local moveDistance = math.abs(self.speed) * timeStep
        
        if moveDistance < distance then
            -- 正常移动
            node:Translate(Vector3(dirNormal.x, dirNormal.y, 0) * moveDistance)
        else
            -- 直接到达目标点（避免抖动）
            node.position2D = targetPos
        end
        
        -- 触发方向改变回调
        if self.onDirectionChange then
            self.onDirectionChange(dir)
        end
    else
        -- 到达目标点
        if self.onReachWaypoint then
            self.onReachWaypoint(self.currentPathID)
        end
        
        -- 移动到下一个路径点
        self:_MoveToNextWaypoint()
    end
end

-- 内部方法：移动到下一个路径点
function PathFollower:_MoveToNextWaypoint()
    local pathLength = #self.path
    
    if self.speed > 0 then
        -- 向前移动
        if self.currentPathID + 1 <= pathLength then
            self.currentPathID = self.currentPathID + 1
        else
            -- 到达终点
            if self.loop then
                -- 循环：回到起点
                if self.path[pathLength] == self.path[1] then
                    self.currentPathID = 1
                else
                    self.currentPathID = 1
                    self.node.position2D = self.path[1]
                end
            elseif self.reverse then
                -- 往返：反向
                self.currentPathID = pathLength - 1
                self.speed = -self.speed
            else
                -- 停止
                self.paused = true
                if self.onPathComplete then
                    self.onPathComplete()
                end
            end
        end
    else
        -- 向后移动
        if self.currentPathID - 1 >= 1 then
            self.currentPathID = self.currentPathID - 1
        else
            -- 到达起点
            if self.reverse then
                -- 往返：反向
                self.currentPathID = 2
                self.speed = -self.speed
            else
                -- 停止
                self.paused = true
                if self.onPathComplete then
                    self.onPathComplete()
                end
            end
        end
    end
end

---获取当前目标点索引
---@return number
function PathFollower:GetCurrentWaypointIndex()
    return self.currentPathID
end

---获取当前目标点位置
---@return Vector2
function PathFollower:GetCurrentWaypoint()
    if self.currentPathID >= 1 and self.currentPathID <= #self.path then
        return self.path[self.currentPathID]
    end
    return Vector2.ZERO
end

---获取移动方向（归一化）
---@return Vector2
function PathFollower:GetDirection()
    if #self.path < 2 then
        return Vector2.ZERO
    end
    
    local targetPos = self.path[self.currentPathID]
    local currentPos = self.node.position2D
    local dir = targetPos - currentPos
    
    if dir:Length() > 0.01 then
        return dir:Normalized()
    end
    
    return Vector2.ZERO
end

return PathFollower

