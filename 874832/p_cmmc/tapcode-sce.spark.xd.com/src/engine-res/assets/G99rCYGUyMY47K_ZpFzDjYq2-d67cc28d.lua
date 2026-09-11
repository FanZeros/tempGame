-- LuaScripts/Utilities/Previews/Scene.lua
-- Hook Scene methods to support resource URIs (e.g., uuid://) on old C++ binaries

-- Skip if C++ already supports resource URIs
if SCENE_SUPPORTS_RESOURCE_URI then
    return
end

local Scene_Load = Scene.Load
local Scene_LoadXML = Scene.LoadXML
local Scene_LoadJSON = Scene.LoadJSON
local Scene_LoadAsync = Scene.LoadAsync
local Scene_LoadAsyncXML = Scene.LoadAsyncXML
local Scene_Instantiate = Scene.Instantiate
local Scene_InstantiateXML = Scene.InstantiateXML
local Scene_InstantiateJSON = Scene.InstantiateJSON

Scene.Load = function(self, fileOrName)
    if type(fileOrName) ~= "string" then
        return Scene_Load(self, fileOrName)
    end
    local file = cache:GetFile(fileOrName)
    if file then
        return Scene_Load(self, file)
    end
    return Scene_Load(self, fileOrName)
end

Scene.LoadXML = function(self, fileOrName)
    if type(fileOrName) ~= "string" then
        return Scene_LoadXML(self, fileOrName)
    end
    local file = cache:GetFile(fileOrName)
    if file then
        return Scene_LoadXML(self, file)
    end
    return Scene_LoadXML(self, fileOrName)
end

Scene.LoadJSON = function(self, fileOrName)
    if type(fileOrName) ~= "string" then
        return Scene_LoadJSON(self, fileOrName)
    end
    local file = cache:GetFile(fileOrName)
    if file then
        return Scene_LoadJSON(self, file)
    end
    return Scene_LoadJSON(self, fileOrName)
end

Scene.LoadAsync = function(self, fileOrName, mode)
    mode = mode or LOAD_SCENE_AND_RESOURCES
    if type(fileOrName) ~= "string" then
        return Scene_LoadAsync(self, fileOrName, mode)
    end
    local file = cache:GetFile(fileOrName)
    if file then
        return Scene_LoadAsync(self, file, mode)
    end
    return Scene_LoadAsync(self, fileOrName, mode)
end

Scene.LoadAsyncXML = function(self, fileOrName, mode)
    mode = mode or LOAD_SCENE_AND_RESOURCES
    if type(fileOrName) ~= "string" then
        return Scene_LoadAsyncXML(self, fileOrName, mode)
    end
    local file = cache:GetFile(fileOrName)
    if file then
        return Scene_LoadAsyncXML(self, file, mode)
    end
    return Scene_LoadAsyncXML(self, fileOrName, mode)
end

Scene.Instantiate = function(self, fileOrName, position, rotation, mode)
    mode = mode or REPLICATED
    if type(fileOrName) ~= "string" then
        return Scene_Instantiate(self, fileOrName, position, rotation, mode)
    end
    local file = cache:GetFile(fileOrName)
    if file then
        -- Peek first byte to detect format
        local firstByte = file:ReadUByte()
        file:Seek(0)

        if firstByte == 60 then  -- '<' = XML
            return Scene_InstantiateXML(self, file, position, rotation, mode)
        elseif firstByte == 123 then  -- '{' = JSON
            -- Old C++ has no InstantiateJSON(File*), uuid:// JSON prefab not supported on old C++
            return Scene_InstantiateJSON(self, fileOrName, position, rotation, mode)
        else
            return Scene_Instantiate(self, file, position, rotation, mode)
        end
    end
    return Scene_Instantiate(self, fileOrName, position, rotation, mode)
end

Scene.InstantiateXML = function(self, fileOrName, position, rotation, mode)
    mode = mode or REPLICATED
    if type(fileOrName) ~= "string" then
        return Scene_InstantiateXML(self, fileOrName, position, rotation, mode)
    end
    local file = cache:GetFile(fileOrName)
    if file then
        return Scene_InstantiateXML(self, file, position, rotation, mode)
    end
    return Scene_InstantiateXML(self, fileOrName, position, rotation, mode)
end

-- InstantiateJSON: Old C++ has no File* version, cannot fully support uuid://
-- Just pass through, uuid:// will fail on old C++
Scene.InstantiateJSON = function(self, fileOrName, position, rotation, mode)
    mode = mode or REPLICATED
    return Scene_InstantiateJSON(self, fileOrName, position, rotation, mode)
end
