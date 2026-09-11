--[[
NetworkUtils.lua - 网络辅助工具模块

提供简化网络开发的辅助函数，但不改变引擎原生 API 的语义。
设计原则：AI Agent 友好，最小封装。

用法:
    local NetworkUtils = require("urhox-libs.Network.NetworkUtils")
    
    -- 简化 VariantMap 构建
    local eventData = NetworkUtils.ToVariantMap({
        x = 10.5,
        y = 0,
        action = "move"
    })
    connection:SendRemoteEvent("PlayerMove", true, eventData)
    
    -- 合并注册和订阅
    NetworkUtils.OnRemoteEvent("GameState", "HandleGameState")
]]

local NetworkUtils = {}

--- 将 Lua table 转换为 VariantMap
--- 支持的类型：number, string, boolean, Vector3, Vector2, Color
--- @param tbl table Lua table
--- @return VariantMap
function NetworkUtils.ToVariantMap(tbl)
    if type(tbl) ~= "table" then
        error("NetworkUtils.ToVariantMap: expected table, got " .. type(tbl))
    end
    
    local vm = VariantMap()
    for k, v in pairs(tbl) do
        local vtype = type(v)
        
        if vtype == "number" then
            -- 区分整数和浮点数
            if math.floor(v) == v and math.abs(v) < 2147483647 then
                vm[k] = Variant(math.floor(v))  -- int
            else
                vm[k] = Variant(v)  -- float/double
            end
        elseif vtype == "string" then
            vm[k] = Variant(v)
        elseif vtype == "boolean" then
            vm[k] = Variant(v)
        elseif vtype == "table" then
            -- 尝试识别特殊类型
            if v.x ~= nil and v.y ~= nil and v.z ~= nil then
                -- Vector3
                vm[k] = Variant(Vector3(v.x, v.y, v.z))
            elseif v.x ~= nil and v.y ~= nil and v.z == nil then
                -- Vector2
                vm[k] = Variant(Vector2(v.x, v.y))
            elseif v.r ~= nil and v.g ~= nil and v.b ~= nil then
                -- Color
                local a = v.a or 1.0
                vm[k] = Variant(Color(v.r, v.g, v.b, a))
            else
                -- 其他 table 类型暂不支持，打印警告
                print(string.format("NetworkUtils.ToVariantMap: unsupported table type for key '%s'", tostring(k)))
            end
        elseif vtype == "userdata" then
            -- 直接使用 userdata（如 Vector3、Quaternion 等 Urho3D 对象）
            vm[k] = Variant(v)
        else
            print(string.format("NetworkUtils.ToVariantMap: unsupported type '%s' for key '%s'", vtype, tostring(k)))
        end
    end
    
    return vm
end

--- 从 VariantMap 提取数据到 Lua table
--- 简化从远程事件中读取数据的过程
--- @param eventData VariantMap 事件数据
--- @param keys table 要提取的键和类型 { key = "type" }
--- @return table 提取的数据
--- @example
---     local data = NetworkUtils.FromVariantMap(eventData, {
---         x = "float",
---         y = "float", 
---         action = "string",
---         score = "int"
---     })
---     print(data.x, data.action)
function NetworkUtils.FromVariantMap(eventData, keys)
    local result = {}
    
    for key, valueType in pairs(keys) do
        local variant = eventData[key]
        if variant then
            if valueType == "int" or valueType == "integer" then
                result[key] = variant:GetInt()
            elseif valueType == "int64" then
                result[key] = variant:GetInt64()
            elseif valueType == "float" or valueType == "number" then
                result[key] = variant:GetFloat()
            elseif valueType == "double" then
                result[key] = variant:GetDouble()
            elseif valueType == "string" then
                result[key] = variant:GetString()
            elseif valueType == "bool" or valueType == "boolean" then
                result[key] = variant:GetBool()
            elseif valueType == "vector3" then
                result[key] = variant:GetVector3()
            elseif valueType == "vector2" then
                result[key] = variant:GetVector2()
            else
                -- 尝试作为字符串获取
                result[key] = variant:GetString()
            end
        end
    end
    
    return result
end

--- 合并 RegisterRemoteEvent + SubscribeToEvent
--- 简化远程事件的注册和订阅
--- @param eventName string 事件名称
--- @param handler function|string 处理函数或函数名
function NetworkUtils.OnRemoteEvent(eventName, handler)
    network:RegisterRemoteEvent(eventName)
    SubscribeToEvent(eventName, handler)
end

--- 发送远程事件的便捷封装
--- 自动构建 VariantMap 并发送
--- @param eventName string 事件名称
--- @param data table Lua table 数据
--- @param reliable boolean 是否可靠发送，默认 true
--- @return boolean 是否发送成功
function NetworkUtils.SendToServer(eventName, data, reliable)
    local connection = network:GetServerConnection()
    if not connection then
        print("NetworkUtils.SendToServer: Not connected to server")
        return false
    end
    
    if reliable == nil then
        reliable = true
    end
    
    local eventData = NetworkUtils.ToVariantMap(data or {})
    connection:SendRemoteEvent(eventName, reliable, eventData)
    return true
end

--- 广播远程事件的便捷封装（服务器端使用）
--- @param eventName string 事件名称
--- @param data table Lua table 数据
--- @param reliable boolean 是否可靠发送，默认 true
function NetworkUtils.BroadcastToClients(eventName, data, reliable)
    if reliable == nil then
        reliable = true
    end
    
    local eventData = NetworkUtils.ToVariantMap(data or {})
    network:BroadcastRemoteEvent(eventName, reliable, eventData)
end

--- 检查是否已连接到服务器
--- @return boolean
function NetworkUtils.IsConnectedToServer()
    local connection = network:GetServerConnection()
    return connection ~= nil and connection:IsConnected()
end

--- 获取连接延迟（RTT）
--- @return number 往返时间（毫秒），未连接返回 -1
function NetworkUtils.GetLatency()
    local connection = network:GetServerConnection()
    if connection then
        return connection:GetRoundTripTime() * 1000  -- 转换为毫秒
    end
    return -1
end

return NetworkUtils

