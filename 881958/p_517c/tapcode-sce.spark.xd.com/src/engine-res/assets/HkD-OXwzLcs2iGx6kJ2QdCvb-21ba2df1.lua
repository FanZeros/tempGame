-- InputExtensions.lua
-- Input subsystem extensions: Web platform mouse mode handling

if _G.IsServerMode and _G.IsServerMode() then
    return
end

local input_ = GetInput()
local Input_meta = getmetatable(input_)
if not Input_meta then return end
local Input_newindex = Input_meta.__newindex
local Input_SetMouseMode = input_.SetMouseMode
local Input_SetMouseVisible = input_.SetMouseVisible
local Input_SetMouseGrabbed = input_.SetMouseGrabbed

-- Expected values (what user wants, may differ from actual on Web)
local expectedMouseMode_ = MM_ABSOLUTE
local expectedMouseVisible_ = true
local expectedMouseGrabbed_ = false

--------------------------------------------------------------------------------
-- Input API Override
--------------------------------------------------------------------------------

-- Override SetMouseMode method
input_.SetMouseMode = function(self, mode, suppressEvent)
    if not suppressEvent then
        expectedMouseMode_ = mode
    end
    return Input_SetMouseMode(self, mode, suppressEvent)
end

-- Override SetMouseVisible method
input_.SetMouseVisible = function(self, enable, suppressEvent)
    if not suppressEvent then
        expectedMouseVisible_ = enable
    end
    return Input_SetMouseVisible(self, enable, suppressEvent)
end

-- Override SetMouseGrabbed method
input_.SetMouseGrabbed = function(self, grab, suppressEvent)
    if not suppressEvent then
        expectedMouseGrabbed_ = grab
    end
    return Input_SetMouseGrabbed(self, grab, suppressEvent)
end

-- Override __newindex for property setters
Input_meta.__newindex = (function()
    local setters_ = {
        mouseMode = function(self, value)
            expectedMouseMode_ = value
            Input_newindex(self, "mouseMode", value)
        end,
        mouseVisible = function(self, value)
            expectedMouseVisible_ = value
            Input_newindex(self, "mouseVisible", value)
        end,
        mouseGrabbed = function(self, value)
            expectedMouseGrabbed_ = value
            Input_newindex(self, "mouseGrabbed", value)
        end,
    }

    return function(self, key, value)
        local setter = setters_[key]
        if setter then
            setter(self, value)
        else
            Input_newindex(self, key, value)
        end
    end
end)()

--------------------------------------------------------------------------------
-- Web Platform Event Handlers
--------------------------------------------------------------------------------
---
---@class InputExtensions_EventReceiver : LuaScriptObject     
InputExtensions_EventReceiver = ScriptObject()

function InputExtensions_EventReceiver:Start()

    local platform = GetPlatform()
    local desktopPlatforms = {
        ["Windows"] = true,
        ["macOS"] = true,
        ["Linux"] = true,
        ["Raspberry Pi"] = true,
        ["Web"] = true,
    }
    if not desktopPlatforms[platform] then
        return
    end

    -- Desktop and Web: ESC to exit mouse lock, click to restore
    self:SubscribeToEvent("MouseButtonDown", function(_, eventType, eventData)
        self:HandleMouseButtonDown(eventType, eventData)
    end)
    self:SubscribeToEvent("MouseModeChanged", function(_, eventType, eventData)
        self:HandleMouseModeChange(eventType, eventData)
    end)
    self:SubscribeToEvent("KeyUp", function(_, eventType, eventData)
        self:HandleKeyUp(eventType, eventData)
    end)
end

---comment
---@param eventType string
---@param eventData MouseButtonDownEventData
function InputExtensions_EventReceiver:HandleMouseButtonDown(eventType, eventData)
    input_.mouseMode = expectedMouseMode_
    input_.mouseVisible = expectedMouseVisible_
    -- print("HandleMouseButtonDown")
end

---comment
---@param eventType string
---@param eventData MouseModeEventData
function InputExtensions_EventReceiver:HandleMouseModeChange(eventType, eventData)
    input_.mouseVisible = expectedMouseVisible_

    local mode = eventData["Mode"]:GetInt()
    local mouseLocked = eventData["MouseLocked"]:GetBool()
    log:Write(LOG_INFO, string.format("HandleMouseModeChange: mode=%d, locked=%s, input.mouseMode=%d",
        mode, tostring(mouseLocked), input_.mouseMode))
end

---comment
---@param eventType string
---@param eventData KeyUpEventData
function InputExtensions_EventReceiver:HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        Input_SetMouseVisible(input_, true, true);
        Input_SetMouseMode(input_, MM_FREE, true);
        -- print("HandleKeyUp ESC")
    end
end


--------------------------------------------------------------------------------
-- Init Node And ScriptObject
--------------------------------------------------------------------------------

local node_ = Node()
local receiver_ = node_:CreateScriptObject("InputExtensions_EventReceiver")


function InputExtensions_Uninstall()
    log:Write(LOG_INFO, "InputExtensions_Uninstall called")
    Input_meta.__newindex = Input_newindex
    input_.SetMouseMode = Input_SetMouseMode
    input_.SetMouseVisible = Input_SetMouseVisible
    input_.SetMouseGrabbed = Input_SetMouseGrabbed
    receiver_:UnsubscribeFromAllEvents()
    receiver_ = nil
    node_ = nil
end


