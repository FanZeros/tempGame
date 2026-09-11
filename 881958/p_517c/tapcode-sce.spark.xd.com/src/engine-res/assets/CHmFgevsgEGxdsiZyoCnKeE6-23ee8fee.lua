-- UILoader.lua
-- Declarative UI loader for .ui.json layout files.
-- Supports component reuse via $prop substitution + Slot.

local UILoader = {}

-- Lazy reference to UI module (set during first load to avoid circular dependency)
local UI_ = nil

-- Component registry: { typeName = resourceId }
local componentRegistry_ = {}

-- Template cache: { resourceId = decoded JSON table }
local templateCache_ = {}

-- ============================================================================
-- Animation Format Conversion
-- ============================================================================

--- Convert JSON animation format to Widget:Animate() format.
--- JSON uses: { frames: [{ at: "0%", opacity: 0 }, ...], duration: 0.6 }
--- Widget:Animate expects: { keyframes: { [0] = { opacity = 0 }, ... }, duration: 0.6 }
---@param anim table JSON animation config
---@return table Config compatible with Widget:Animate()
local function convertAnimation(anim)
    if not anim or not anim.frames then return nil end

    local keyframes = {}
    for _, frame in ipairs(anim.frames) do
        -- Parse "0%" / "50%" / "100%" → 0 / 0.5 / 1.0
        local atStr = frame.at
        if not atStr then goto continue end
        local pct = tonumber(atStr:match("([%d%.]+)"))
        if not pct then goto continue end
        local t = pct / 100

        -- Extract props (everything except "at")
        local props = {}
        for k, v in pairs(frame) do
            if k ~= "at" then
                props[k] = v
            end
        end
        keyframes[t] = props

        ::continue::
    end

    -- Build config, pass through all non-frames fields
    local config = { keyframes = keyframes }
    for k, v in pairs(anim) do
        if k ~= "frames" then
            config[k] = v
        end
    end

    return config
end

-- ============================================================================
-- Component Expansion ($prop + Slot)
-- ============================================================================

--- Load a component template JSON (with caching).
---@param resourceId string Component .ui.json file path
---@return table|nil Decoded JSON table
local function loadTemplate(resourceId)
    if templateCache_[resourceId] then
        return templateCache_[resourceId]
    end
    local file = cache:GetFile(resourceId)
    if not file then return nil end
    local content = file:ReadString()
    file:Close()
    if not content or content == "" then return nil end
    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then return nil end
    templateCache_[resourceId] = data
    return data
end

--- Expand $prop references in a single value.
--- "$title" → callerProps.title (or nil if not present)
--- "$title:Default" → callerProps.title or "Default"
--- Non-string or non-$ values pass through unchanged.
---@param value any The value to expand
---@param callerProps table Props from the caller node
---@return any Expanded value, or nil to skip this property
---@return boolean skip True if the property should be omitted entirely
local function expandPropValue(value, callerProps)
    if type(value) ~= "string" then return value, false end
    if value:sub(1, 1) ~= "$" then return value, false end

    -- Parse "$name" or "$name:default"
    local ref = value:sub(2)  -- strip leading $
    local name, default = ref:match("^([^:]+):(.*)$")
    if not name then
        -- No default: "$name"
        name = ref
        default = nil
    end

    local callerValue = callerProps[name]
    if callerValue ~= nil then
        return callerValue, false
    elseif default ~= nil then
        -- Try to convert default to number/boolean for JSON compatibility
        if default == "true" then return true, false end
        if default == "false" then return false, false end
        local num = tonumber(default)
        if num then return num, false end
        return default, false
    else
        -- No caller value, no default → skip this property
        return nil, true
    end
end

--- Deep-expand all $prop references in a JSON node tree.
--- Returns a new table (does not mutate the template).
---@param templateNode table Template JSON node
---@param callerProps table Props from the caller
---@param callerChildren table|nil Caller's children array
---@return table Expanded JSON node
local function expandTemplate(templateNode, callerProps, callerChildren)
    if type(templateNode) ~= "table" then return templateNode end

    local expanded = {}

    for k, v in pairs(templateNode) do
        if k == "children" then
            -- Process children: expand each child, handle Slot substitution
            local expandedChildren = {}
            for _, child in ipairs(v) do
                if type(child) == "table" and child.type == "Slot" then
                    -- Replace Slot with caller's children
                    if callerChildren then
                        local slotName = child.name
                        for _, callerChild in ipairs(callerChildren) do
                            if slotName then
                                -- Named slot: only insert children with matching "slot" attribute
                                if callerChild.slot == slotName then
                                    expandedChildren[#expandedChildren + 1] = callerChild
                                end
                            else
                                -- Default slot: insert children WITHOUT a "slot" attribute
                                if not callerChild.slot then
                                    expandedChildren[#expandedChildren + 1] = callerChild
                                end
                            end
                        end
                    end
                else
                    -- Recursively expand template child
                    expandedChildren[#expandedChildren + 1] = expandTemplate(child, callerProps, callerChildren)
                end
            end
            expanded.children = expandedChildren
        elseif k == "type" then
            expanded.type = v
        else
            -- Expand $prop references in property values
            if type(v) == "table" then
                -- Recursively expand nested objects (e.g., gradient, boxShadow)
                -- This also creates a fresh copy, preventing template cache corruption
                expanded[k] = expandTemplate(v, callerProps, callerChildren)
            else
                local expandedValue, skip = expandPropValue(v, callerProps)
                if not skip then
                    expanded[k] = expandedValue
                end
            end
        end
    end

    return expanded
end

-- ============================================================================
-- Widget Creation
-- ============================================================================

--- Recursively create a Widget tree from a JSON node.
---@param node table JSON node (decoded Lua table)
---@param resourceId string Resource identifier (file path or uuid://)
---@param path string JSON path for this node (e.g. "children[2].children[1]")
---@param idMap table Weak-value table for id → widget mapping
---@return Widget
local function createWidget(node, resourceId, path, idMap)
    local typeName = node.type
    if not typeName then
        error("JSON node missing 'type' field at path: " .. (path == "" and "root" or path))
    end

    local WidgetClass = UI_[typeName]

    -- 不是内置 Widget → 检查组件注册表
    if not WidgetClass then
        local componentPath = componentRegistry_[typeName]
        if componentPath then
            local template = loadTemplate(componentPath)
            if not template then
                error("Failed to load component template: '" .. componentPath
                    .. "' for type '" .. typeName .. "' at path: " .. (path == "" and "root" or path))
            end

            -- 收集调用者 props（排除 type/children/slot）
            local callerProps = {}
            for k, v in pairs(node) do
                if k ~= "type" and k ~= "children" and k ~= "slot" then
                    callerProps[k] = v
                end
            end

            -- 展开模板：$prop 替换 + Slot 填入
            local expanded = expandTemplate(template, callerProps, node.children)

            -- 调用者的非 $prop 属性合并到展开后的根节点（调用者优先）
            -- 这样 flex, width, margin 等布局属性可以从使用处传入，覆盖模板默认值
            for k, v in pairs(callerProps) do
                -- 跳过已作为 $prop 消费的属性（模板内有 $xxx 引用的）
                -- 简单策略：直接合并所有调用者属性到根节点（调用者优先覆盖模板）
                if k ~= "children" and k ~= "slot" then
                    expanded[k] = v
                end
            end

            -- 递归创建展开后的节点（现在是普通 Widget 节点了）
            return createWidget(expanded, resourceId, path, idMap)
        end

        error("Unknown widget type: '" .. tostring(typeName) .. "' at path: " .. (path == "" and "root" or path))
    end

    -- 提取 animation，其余全是 props
    -- 颜色字符串由 Widget:new → Style.NormalizeColorProps 自动处理
    -- 注意：table 类型值必须浅拷贝，否则 NormalizeColorProps 等就地修改会污染原始 JSON 数据
    local animConfig = node.animation
    local props = {}
    for k, v in pairs(node) do
        if k ~= "type" and k ~= "animation" then
            if type(v) == "table" and k ~= "children" then
                local copy = {}
                for ck, cv in pairs(v) do copy[ck] = cv end
                props[k] = copy
            else
                props[k] = v
            end
        end
    end

    -- 先递归创建子 Widget 实例，放进 props.children
    -- 这样组件构造函数（如 Tooltip/Popover）能在 Init 阶段访问 children
    if props.children then
        local childWidgets = {}
        for i, childNode in ipairs(props.children) do
            local childPath = path == "" and ("children[" .. i .. "]")
                or (path .. ".children[" .. i .. "]")
            childWidgets[i] = createWidget(childNode, resourceId, childPath, idMap)
        end
        props.children = childWidgets
    end

    -- 构造 Widget（props 含 children Widget 实例，构造函数通过 ProcessChildren 处理）
    local widget = WidgetClass(props)

    -- JSON 来源标记
    -- file: resource identifier（显示 + 定位用）
    -- path: JSON path（显示用）
    -- node: 直接引用 instance.json_ 中的 table（属性同步写入目标）
    widget._jsonSource = { file = resourceId, path = path, node = node }

    -- id 注册（同 HTML：重复 id 不报错，idMap 存第一个，warn 重复）
    if props.id then
        if idMap[props.id] then
            log:Warning("UILoader: Duplicate id '" .. props.id .. "' in " .. resourceId
                .. " at path: " .. path .. " (first occurrence kept)")
        else
            idMap[props.id] = widget
        end
    end

    -- 应用动画
    if animConfig then
        local converted = convertAnimation(animConfig)
        if converted then
            widget:Animate(converted)
        end
    end

    return widget
end

-- ============================================================================
-- Instance Object
-- ============================================================================

local Instance = {}
Instance.__index = Instance

--- Get root widget (nil if destroyed/GC'd).
---@return Widget|nil
function Instance:GetRoot()
    return self.rootRef_[1]
end

--- Find widget by id (O(1) lookup, nil if GC'd).
---@param id string
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function Instance:Find(id)
    return self.idMap_[id]
end

--- Find all widgets of a given type (DFS pre-order = document order).
---@param typeName string Widget class name (e.g. "Button", "Label")
---@return Widget[]
function Instance:FindAll(typeName)
    local result = {}
    local root = self:GetRoot()
    if not root then return result end

    local function collect(widget)
        if widget._className == typeName then
            result[#result + 1] = widget
        end
        if widget.children then
            for _, child in ipairs(widget.children) do
                collect(child)
            end
        end
    end
    collect(root)
    return result
end

--- Get JSON path for a widget.
---@param widget Widget
---@return string|nil JSON path, or nil if widget has no _jsonSource
function Instance:GetJSONPath(widget)
    return widget._jsonSource and widget._jsonSource.path
end

--- Serialize the JSON table to string.
--- Uses JSONSerializer to convert RGBA tables back to hex strings.
---@return string JSON string
function Instance:Serialize()
    local UISerializer = UI_.UISerializer
    if UISerializer then
        return UISerializer.Encode(self.json_)
    end
    -- Fallback: direct encode (colors will be arrays instead of hex strings)
    return cjson.encode(self.json_)
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Register a component type backed by a .ui.json template file.
---@param typeName string Component type name (e.g. "DemoCard", "FormField")
---@param resourceId string Path to the component .ui.json file
function UILoader.RegisterComponent(typeName, resourceId)
    componentRegistry_[typeName] = resourceId
end

--- Unregister a component type.
---@param typeName string
function UILoader.UnregisterComponent(typeName)
    local resourceId = componentRegistry_[typeName]
    componentRegistry_[typeName] = nil
    if resourceId then
        templateCache_[resourceId] = nil
    end
end

--- Clear the template cache (useful after component files are modified).
function UILoader.ClearTemplateCache()
    templateCache_ = {}
end

--- Load a widget tree from a decoded JSON table.
---@param data table Decoded JSON data (root node)
---@param resourceId string Resource identifier for tracking
---@return Instance
function UILoader.Load(data, resourceId)
    if not UI_ then
        UI_ = require("urhox-libs/UI")
    end

    -- 创建弱值 idMap
    local idMap = setmetatable({}, { __mode = "v" })

    -- 递归构建 Widget 树
    local root = createWidget(data, resourceId, "", idMap)

    -- 构造 Instance 对象
    local instance = setmetatable({
        rootRef_    = setmetatable({ root }, { __mode = "v" }),
        idMap_      = idMap,
        json_       = data,
        resourceId_ = resourceId,
    }, Instance)

    return instance
end

--- Load a widget tree from a .ui.json file.
--- If props is provided, the JSON is treated as a template and $prop values are expanded.
---@param resourceId string Resource identifier (relative path or uuid://)
---@param props table|nil Optional props for $prop expansion (component instantiation)
---@return Instance|nil instance, string|nil error
function UILoader.LoadFromFile(resourceId, props)
    if not UI_ then
        UI_ = require("urhox-libs/UI")
    end

    local data
    if props then
        -- Template mode: load with caching, expand $prop + Slot
        local template = loadTemplate(resourceId)
        if not template then
            return nil, "Failed to load template: " .. resourceId
        end
        data = expandTemplate(template, props, props.children)
        -- Caller's id overrides expanded root id
        if props.id then
            data.id = props.id
        end
    else
        -- Normal mode: load and decode
        local file = cache:GetFile(resourceId)
        if not file then
            return nil, "Failed to load file: " .. resourceId
        end
        local content = file:ReadString()
        file:Close()
        if not content or content == "" then
            return nil, "Empty file: " .. resourceId
        end
        local ok, decoded = pcall(cjson.decode, content)
        if not ok then
            return nil, "JSON decode error in " .. resourceId .. ": " .. tostring(decoded)
        end
        if type(decoded) ~= "table" then
            return nil, "JSON root must be an object in " .. resourceId
        end
        data = decoded
    end

    return UILoader.Load(data, resourceId)
end

return UILoader
