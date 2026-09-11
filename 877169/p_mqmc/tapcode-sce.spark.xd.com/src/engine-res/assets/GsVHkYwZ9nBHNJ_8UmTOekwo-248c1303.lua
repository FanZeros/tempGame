-- CommandLineParser.lua
-- 命令行参数解析（网络配置等）
-- 来源：从 Network.lua 改进

---@class CommandLineParser
local CommandLineParser = {}

---解析网络相关的命令行参数
---@return table 解析结果 { runServer, runClient, serverAddress, serverPort, userName, nobgm }
function CommandLineParser.ParseNetworkArgs()
    local result = {
        runServer = false,
        runClient = false,
        serverAddress = '',
        serverPort = 1234,
        userName = '',
        nobgm = false
    }
    
    local arguments = GetArguments()
    local skipNext = false
    
    for i, argument in ipairs(arguments) do
        if not skipNext and string.sub(argument, 1, 1) == '-' then
            local arg = string.lower(argument)
            
            if arg == "-server" or arg == "--server" then
                result.runServer = true
                result.runClient = false
                
            elseif arg == "-address" or arg == "--address" then
                result.runClient = true
                result.runServer = false
                if arguments[i + 1] then
                    result.serverAddress = arguments[i + 1]
                    skipNext = true
                end
                
            elseif arg == "-username" or arg == "--username" then
                if arguments[i + 1] then
                    result.userName = arguments[i + 1]
                    skipNext = true
                end
                
            elseif arg == "-port" or arg == "--port" then
                if arguments[i + 1] then
                    result.serverPort = tonumber(arguments[i + 1]) or 1234
                    skipNext = true
                end
                
            elseif arg == "-nobgm" or arg == "--nobgm" then
                result.nobgm = true
            end
        else
            skipNext = false
        end
    end
    
    return result
end

---通用命令行参数解析器
---@param definitions table 参数定义 { { name, hasValue, alias }, ... }
---@return table 解析结果
function CommandLineParser.Parse(definitions)
    local result = {}
    local arguments = GetArguments()
    local skipNext = false
    
    -- 初始化结果
    for _, def in ipairs(definitions) do
        result[def.name] = def.default or false
    end
    
    -- 解析参数
    for i, argument in ipairs(arguments) do
        if not skipNext and string.sub(argument, 1, 1) == '-' then
            local arg = string.lower(argument)
            
            -- 查找匹配的定义
            for _, def in ipairs(definitions) do
                local matches = false
                
                -- 检查主名称
                if arg == "-" .. string.lower(def.name) or arg == "--" .. string.lower(def.name) then
                    matches = true
                end
                
                -- 检查别名
                if def.alias then
                    if type(def.alias) == "table" then
                        for _, alias in ipairs(def.alias) do
                            if arg == "-" .. string.lower(alias) or arg == "--" .. string.lower(alias) then
                                matches = true
                                break
                            end
                        end
                    else
                        if arg == "-" .. string.lower(def.alias) or arg == "--" .. string.lower(def.alias) then
                            matches = true
                        end
                    end
                end
                
                if matches then
                    if def.hasValue then
                        -- 需要值
                        if arguments[i + 1] then
                            local value = arguments[i + 1]
                            
                            -- 类型转换
                            if def.type == "number" then
                                result[def.name] = tonumber(value) or def.default
                            elseif def.type == "boolean" then
                                result[def.name] = (value == "true" or value == "1")
                            else
                                result[def.name] = value
                            end
                            
                            skipNext = true
                        end
                    else
                        -- 布尔标志
                        result[def.name] = true
                    end
                    break
                end
            end
        else
            skipNext = false
        end
    end
    
    return result
end

---获取所有原始参数
---@return table 参数数组
function CommandLineParser.GetRawArguments()
    return GetArguments()
end

---检查是否存在指定参数
---@param argName string 参数名称（不含 - 或 --）
---@return boolean
function CommandLineParser.HasArgument(argName)
    local arguments = GetArguments()
    argName = string.lower(argName)
    
    for _, argument in ipairs(arguments) do
        if string.sub(argument, 1, 1) == '-' then
            local arg = string.lower(argument)
            if arg == "-" .. argName or arg == "--" .. argName then
                return true
            end
        end
    end
    
    return false
end

return CommandLineParser

