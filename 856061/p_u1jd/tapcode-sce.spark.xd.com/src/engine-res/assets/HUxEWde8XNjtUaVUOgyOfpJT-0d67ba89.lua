-- TilemapPhysics.lua
-- TMX 瓦片地图碰撞形状生成器
-- 来源：从 Sample2D.lua 提取

---@class TilemapPhysics
local TilemapPhysics = {}

---从 TMX 对象层创建碰撞形状
---@param tileMapNode Node 瓦片地图节点
---@param tileMapLayer TileMapLayer2D 包含物理对象的层
---@param info table|nil 瓦片地图信息（可选，自动获取）
---@param options table|nil 可选配置 { defaultFriction, bodyType }
function TilemapPhysics.CreateCollisionShapes(tileMapNode, tileMapLayer, info, options)
    if not tileMapNode or not tileMapLayer then
        log:Write(LOG_ERROR, "TilemapPhysics: Invalid node or layer")
        return
    end
    
    options = options or {}
    local defaultFriction = options.defaultFriction or 0.8
    local bodyType = options.bodyType or BT_STATIC
    
    -- 获取瓦片地图信息（如果未提供）
    if not info then
        local tileMap = tileMapNode:GetComponent("TileMap2D")
        if tileMap then
            info = tileMap.info
        else
            log:Write(LOG_ERROR, "TilemapPhysics: Cannot get TileMap2D info")
            return
        end
    end
    
    -- 创建或获取刚体组件
    local body = tileMapNode:GetComponent("RigidBody2D")
    if not body then
        body = tileMapNode:CreateComponent("RigidBody2D")
        body.bodyType = bodyType
    end
    
    -- 遍历层中的所有对象
    local objectCount = tileMapLayer:GetNumObjects()
    log:Write(LOG_INFO, "TilemapPhysics: Processing " .. objectCount .. " objects from layer")

    -- Note: TileMapLayer:GetObject() uses 0-based indexing (C++ API)
    for i = 0, objectCount - 1 do
        local tileMapObject = tileMapLayer:GetObject(i)
        if not tileMapObject then
            log:Write(LOG_ERROR, "TilemapPhysics: Failed to get object at index " .. i)
            break
        end

        local objectType = tileMapObject.objectType
        local shape = nil
        
        -- 根据对象类型创建碰撞形状
        if objectType == OT_RECTANGLE then
            shape = TilemapPhysics._CreateBoxShape(tileMapNode, tileMapObject, info)
            
        elseif objectType == OT_ELLIPSE then
            shape = TilemapPhysics._CreateCircleShape(tileMapNode, tileMapObject, info)
            
        elseif objectType == OT_POLYGON then
            shape = TilemapPhysics._CreatePolygonShape(tileMapNode, tileMapObject)
            
        elseif objectType == OT_POLYLINE then
            shape = TilemapPhysics._CreateChainShape(tileMapNode, tileMapObject)
        end
        
        -- 设置摩擦力
        if shape then
            -- 优先使用对象自定义的摩擦力
            if tileMapObject:HasProperty("Friction") then
                shape.friction = tonumber(tileMapObject:GetProperty("Friction"))
            else
                shape.friction = defaultFriction
            end
            
            -- 支持其他物理属性
            if tileMapObject:HasProperty("Restitution") then
                shape.restitution = tonumber(tileMapObject:GetProperty("Restitution"))
            end
            if tileMapObject:HasProperty("Density") then
                shape.density = tonumber(tileMapObject:GetProperty("Density"))
            end
            if tileMapObject:HasProperty("IsTrigger") then
                local isTrigger = tileMapObject:GetProperty("IsTrigger")
                shape.trigger = (isTrigger == "true" or isTrigger == "1")
            end
        end
    end
    
    log:Write(LOG_INFO, "TilemapPhysics: Created collision shapes successfully")
end

-- 内部方法：创建矩形碰撞体
function TilemapPhysics._CreateBoxShape(node, object, info)
    local shape = node:CreateComponent("CollisionBox2D")
    local size = object.size
    shape.size = size
    
    -- 根据地图方向设置位置
    if info.orientation == O_ORTHOGONAL then
        shape.center = object.position + size / 2
    else
        -- 等距地图（菱形）
        shape.center = object.position + Vector2(info.tileWidth / 2, 0)
        shape.angle = 45
    end
    
    return shape
end

-- 内部方法：创建圆形碰撞体
function TilemapPhysics._CreateCircleShape(node, object, info)
    local shape = node:CreateComponent("CollisionCircle2D")
    local size = object.size
    shape.radius = size.x / 2
    
    -- 根据地图方向设置位置
    if info.orientation == O_ORTHOGONAL then
        shape.center = object.position + size / 2
    else
        -- 等距地图
        shape.center = object.position + Vector2(info.tileWidth / 2, 0)
    end
    
    return shape
end

-- 内部方法：创建多边形碰撞体
function TilemapPhysics._CreatePolygonShape(node, object)
    local shape = node:CreateComponent("CollisionPolygon2D")

    -- 设置顶点
    local numVertices = object.numPoints
    if numVertices < 3 then
        log:Write(LOG_WARNING, "TilemapPhysics: Polygon must have at least 3 vertices, got " .. numVertices)
        return nil
    end

    shape.vertexCount = numVertices
    -- Note: CollisionPolygon2D:SetVertex() uses 0-based indexing (C++ API)
    for i = 0, numVertices - 1 do
        shape:SetVertex(i, object:GetPoint(i))
    end

    return shape
end

-- 内部方法：创建链条碰撞体（边界）
function TilemapPhysics._CreateChainShape(node, object)
    local shape = node:CreateComponent("CollisionChain2D")

    -- 设置顶点
    local numVertices = object.numPoints
    if numVertices < 2 then
        log:Write(LOG_WARNING, "TilemapPhysics: Chain must have at least 2 vertices, got " .. numVertices)
        return nil
    end

    shape.vertexCount = numVertices
    -- Note: CollisionChain2D:SetVertex() uses 0-based indexing (C++ API)
    for i = 0, numVertices - 1 do
        shape:SetVertex(i, object:GetPoint(i))
    end

    return shape
end

---从路径对象创建路径表（用于 PathFollower 等）
---@param object TileMapObject2D 多段线对象
---@param offset Vector2|nil 可选偏移量
---@return table 路径点数组
function TilemapPhysics.CreatePathFromObject(object, offset)
    if not object then
        log:Write(LOG_ERROR, "TilemapPhysics.CreatePathFromObject: Invalid object")
        return {}
    end

    offset = offset or Vector2.ZERO

    local path = {}
    -- Note: TileMapObject:GetPoint() uses 0-based indexing (C++ API)
    for i = 0, object.numPoints - 1 do
        table.insert(path, object:GetPoint(i) + offset)
    end

    return path
end

---批量处理：从层名称自动创建碰撞
---@param tileMapNode Node 瓦片地图节点
---@param layerName string|nil 层名称（默认 "Physics"）
---@param options table|nil 可选配置
---@return boolean 是否成功
function TilemapPhysics.AutoCreateFromLayer(tileMapNode, layerName, options)
    layerName = layerName or "Physics"
    
    local tileMap = tileMapNode:GetComponent("TileMap2D")
    if not tileMap then
        log:Write(LOG_ERROR, "TilemapPhysics: No TileMap2D component found")
        return false
    end
    
    -- 查找物理层
    -- 注：这里接口对不上，按说是integer，特此标注
    local layer = tileMap:GetLayer(layerName)
    if not layer then
        log:Write(LOG_WARNING, "TilemapPhysics: Layer '" .. layerName .. "' not found")
        return false
    end
    
    -- 创建碰撞形状
    TilemapPhysics.CreateCollisionShapes(tileMapNode, layer, tileMap.info, options)
    return true
end

return TilemapPhysics

