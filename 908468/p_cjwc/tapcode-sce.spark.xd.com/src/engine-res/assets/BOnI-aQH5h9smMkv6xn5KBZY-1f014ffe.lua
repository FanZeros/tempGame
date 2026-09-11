-- HostSandbox/main.lua
-- Host sandbox main script
-- Runs in an independent LuaScript instance with LuaEnvironment::HostSandbox,
-- separate from the game's Lua environment. Used for official logic and debug systems.

local UI = require("urhox-libs/UI/init")
local ScriptSwitcher = require("LuaScripts/HostSandbox/ScriptSwitcher")

-- Global instances
local uiRoot = nil
local scriptSwitcher = nil

function Start()
    -- Initialize UI system (autoEvents = true by default, handles all input/render events)
    UI.Init({
        fonts = {
            { name = "sans", path = "Fonts/MiSans-Regular.ttf" },
        }
    })

    -- Create root panel (transparent, full screen, for overlay)
    uiRoot = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },  -- Transparent
    }
    UI.SetRoot(uiRoot)

    -- Create and initialize the script switcher
    scriptSwitcher = ScriptSwitcher.new()
    scriptSwitcher:Initialize(uiRoot)
end

function Stop()
    -- Cleanup script switcher
    if scriptSwitcher then
        scriptSwitcher:Cleanup()
        scriptSwitcher = nil
    end

    -- Shutdown UI
    UI.Shutdown()
    uiRoot = nil
end
