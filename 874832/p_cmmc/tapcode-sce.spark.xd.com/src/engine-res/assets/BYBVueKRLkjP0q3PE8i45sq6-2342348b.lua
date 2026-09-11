-- ScriptSwitcher.lua
-- Script switcher panel for HostSandbox
-- Provides a floating button to open a panel with directory tree and recent scripts

local UI = require("urhox-libs/UI/init")

local ScriptSwitcher = {}
ScriptSwitcher.__index = ScriptSwitcher

-- Configuration
local CONFIG_FILE = "script_switcher_config.txt"
local MAX_RECENT_SCRIPTS = 10
local SEARCH_DIRS = { "Data", "AgentProject" }
local SCRIPT_EXTENSIONS = { ".lua", ".luc" }

-- Create a new ScriptSwitcher instance
function ScriptSwitcher.new()
    local self = setmetatable({}, ScriptSwitcher)
    self.isOpen = false
    self.recentScripts = {}
    self.currentScript = ""
    self.treeNodes = {}
    self.panel = nil
    self.fab = nil
    self.tree = nil
    self.recentList = nil
    return self
end

-- Initialize the script switcher
function ScriptSwitcher:Initialize(root)
    self.root = root
    self:LoadConfig()
    self:CreateFAB()
end

-- Trim whitespace from string
local function trim(s)
    return s:match("^%s*(.-)%s*$") or ""
end

-- Load configuration from file (simple text format)
-- Line 1: current script path
-- Line 2+: recent scripts (one per line)
function ScriptSwitcher:LoadConfig()
    local fs = GetFileSystem()
    local configPath = fs:GetAppPreferencesDir("urho3d", "config") .. CONFIG_FILE

    if fs:FileExists(configPath) then
        local file = File(configPath, FILE_READ)
        if file:IsOpen() then
            local lineNum = 0
            while not file:IsEof() do
                local line = trim(file:ReadLine())
                if line ~= "" then
                    if lineNum == 0 then
                        self.currentScript = line
                    else
                        table.insert(self.recentScripts, line)
                    end
                    lineNum = lineNum + 1
                end
            end
            file:Close()
        end
    end
end

-- Save configuration to file (simple text format)
function ScriptSwitcher:SaveConfig()
    local fs = GetFileSystem()
    local configDir = fs:GetAppPreferencesDir("urho3d", "config")
    fs:CreateDir(configDir)

    local configPath = configDir .. CONFIG_FILE

    local file = File(configPath, FILE_WRITE)
    if file:IsOpen() then
        -- Line 1: current script
        file:WriteLine(self.currentScript)
        -- Line 2+: recent scripts
        for _, path in ipairs(self.recentScripts) do
            file:WriteLine(path)
        end
        file:Close()
    end
end

-- Add script to recent list
function ScriptSwitcher:AddToRecent(scriptPath)
    -- Remove if already exists
    for i, path in ipairs(self.recentScripts) do
        if path == scriptPath then
            table.remove(self.recentScripts, i)
            break
        end
    end

    -- Add to front
    table.insert(self.recentScripts, 1, scriptPath)

    -- Trim to max size
    while #self.recentScripts > MAX_RECENT_SCRIPTS do
        table.remove(self.recentScripts)
    end

    self:SaveConfig()
end

-- Scan directories for Lua scripts
function ScriptSwitcher:ScanScripts()
    local fs = GetFileSystem()
    local cache = GetCache()
    local nodes = {}

    -- Script directories that should be used as path prefix when they are resource roots
    local scriptDirNames = { LuaScripts = true, Scripts = true }

    -- Get resource directories from cache
    local resourceDirs = cache.resourceDirs
    for i = 1, #resourceDirs do
        local resourceDir = resourceDirs[i]
        -- Ensure trailing slash for proper relative path calculation
        if not resourceDir:match("[/\\]$") then
            resourceDir = resourceDir .. "/"
        end
        -- Get display name (last part of path)
        local displayName = resourceDir:match("([^/\\]+)[/\\]$") or resourceDir

        -- If resource dir itself is a script directory (e.g., LuaScripts),
        -- use its name as the starting relativePath so keys include the directory name
        local startRelPath = ""
        if scriptDirNames[displayName] then
            startRelPath = displayName
        end

        local dirNode = self:ScanDirectory(resourceDir, startRelPath, displayName)
        if dirNode and #dirNode.children > 0 then
            table.insert(nodes, dirNode)
        end
    end

    return nodes
end

-- Recursively scan a directory
-- baseDir: resource directory root (e.g., "C:/path/to/Data/")
-- relativePath: path relative to baseDir (e.g., "LuaScripts/Utilities")
-- displayName: name to display in tree
function ScriptSwitcher:ScanDirectory(baseDir, relativePath, displayName)
    local fs = GetFileSystem()
    local fullPath = baseDir .. relativePath

    local node = {
        key = relativePath,  -- Use relative path as key for script loading
        label = displayName or relativePath:match("([^/\\]+)$") or relativePath,
        icon = "D",
        children = {},
        expanded = false
    }

    -- Scan subdirectories
    local dirs = fs:ScanDir(fullPath, "*", SCAN_DIRS, false)
    for _, dirName in ipairs(dirs) do
        -- Skip hidden directories (starting with .)
        if not string.match(dirName, "^%.") then
            local childRelPath = relativePath == "" and dirName or (relativePath .. "/" .. dirName)
            local childNode = self:ScanDirectory(baseDir, childRelPath, dirName)
            if childNode and (#childNode.children > 0) then
                table.insert(node.children, childNode)
            end
        end
    end

    -- Scan Lua files
    for _, ext in ipairs(SCRIPT_EXTENSIONS) do
        local files = fs:ScanDir(fullPath, "*" .. ext, SCAN_FILES, false)
        for _, fileName in ipairs(files) do
            -- Skip hidden files
            if not string.match(fileName, "^%.") then
                local fileRelPath = relativePath == "" and fileName or (relativePath .. "/" .. fileName)
                table.insert(node.children, {
                    key = fileRelPath,  -- Use relative path as key
                    label = fileName,
                    icon = "f",
                    children = nil
                })
            end
        end
    end

    return node
end

-- Create the floating action button
function ScriptSwitcher:CreateFAB()
    local switcher = self
    self.fab = UI.Button {
        position = "absolute",
        right = 20,
        top = 100,
        width = 56,
        height = 56,
        backgroundColor = UI.Theme.Color("primary"),
        hoverBackgroundColor = UI.Theme.Color("primaryHover"),
        borderRadius = 28,
        justifyContent = "center",
        alignItems = "center",
        zIndex = 9999,
        text = "Debug",
        fontSize = 12,
        onClick = function()
            switcher:TogglePanel()
        end,
    }

    self.root:AddChild(self.fab)
end

-- Toggle the panel visibility
function ScriptSwitcher:TogglePanel()
    if self.isOpen then
        self:ClosePanel()
    else
        self:OpenPanel()
    end
end

-- Open the script switcher panel
function ScriptSwitcher:OpenPanel()
    if self.isOpen then return end
    self.isOpen = true

    -- Scan scripts
    self.treeNodes = self:ScanScripts()

    -- Create panel
    self.panel = UI.Panel {
        position = "absolute",
        right = 80,
        top = 50,
        width = 400,
        height = 500,
        backgroundColor = UI.Theme.Color("surface"),
        borderColor = UI.Theme.Color("border"),
        borderWidth = 1,
        borderRadius = 8,
        flexDirection = "column",
        padding = 12,
        gap = 8,
        zIndex = 9998,
        overflow = "hidden",
    }

    -- Header
    local header = UI.Row {
        width = "100%",
        justifyContent = "space-between",
        alignItems = "center",
        height = 32,
        flexShrink = 0,
    }

    header:AddChild(UI.Label {
        text = "Script Switcher",
        fontSize = 16,
        fontWeight = "bold",
        color = UI.Theme.Color("text"),
    })

    -- Reload button
    local reloadBtn = UI.Button {
        text = "Reload",
        variant = "secondary",
        width = 70,
        height = 28,
        fontSize = 12,
        onClick = function()
            self:ReloadCurrentScript()
        end,
    }
    header:AddChild(reloadBtn)

    -- Close button
    local closeBtn = UI.Button {
        text = "X",
        variant = "secondary",
        width = 28,
        height = 28,
        fontSize = 12,
        onClick = function()
            self:ClosePanel()
        end,
    }
    header:AddChild(closeBtn)

    self.panel:AddChild(header)

    -- Tabs
    local tabs = UI.Tabs {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        tabs = {
            { id = "tree", label = "Browse" },
            { id = "recent", label = "Recent" },
        },
        defaultTab = "tree",
    }

    -- Tree tab content
    local treeContent = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
    }

    self.tree = UI.Tree {
        nodes = self.treeNodes,
        size = "sm",
        selectable = true,
        showIcons = true,
        showLines = true,
        expandOnClick = true,
        defaultExpandedKeys = {},

        onNodeDoubleClick = function(tree, node, key)
            -- Check if it's a file (no children)
            if not node.children then
                self:SwitchToScript(key)
            end
        end,
    }
    treeContent:AddChild(self.tree)
    tabs:SetTabContent("tree", treeContent)

    -- Recent tab content
    local recentContent = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
    }

    local recentItems = {}
    for i, path in ipairs(self.recentScripts) do
        table.insert(recentItems, {
            id = i,
            text = GetFileNameAndExtension(path),
            secondaryText = path,
        })
    end

    self.recentList = UI.List {
        items = recentItems,
        variant = "simple",
        selectable = false,
        showDividers = true,
        onItemDoubleClick = function(list, item)
            local scriptPath = self.recentScripts[item.id]
            if scriptPath then
                self:SwitchToScript(scriptPath)
            end
        end,
    }
    recentContent:AddChild(self.recentList)
    tabs:SetTabContent("recent", recentContent)

    self.panel:AddChild(tabs)

    -- Current script info
    local currentInfo = UI.Panel {
        width = "100%",
        height = 40,
        flexShrink = 0,
        backgroundColor = UI.Theme.Color("background"),
        borderRadius = 4,
        padding = 8,
        justifyContent = "center",
    }
    currentInfo:AddChild(UI.Label {
        text = "Current: " .. (self.currentScript ~= "" and self.currentScript or "(none)"),
        fontSize = 11,
        color = UI.Theme.Color("textSecondary"),
    })
    self.panel:AddChild(currentInfo)

    self.root:AddChild(self.panel)
end

-- Close the panel
function ScriptSwitcher:ClosePanel()
    if not self.isOpen then return end
    self.isOpen = false

    if self.panel then
        self.root:RemoveChild(self.panel)
        self.panel = nil
    end
end

-- Switch to a new script
function ScriptSwitcher:SwitchToScript(scriptPath)
    self.currentScript = scriptPath
    self:AddToRecent(scriptPath)

    -- Send event to C++ to switch script
    local eventData = VariantMap()
    eventData["ScriptPath"] = scriptPath
    SendEvent("RequestSwitchScript", eventData)
end

-- Reload the current script
function ScriptSwitcher:ReloadCurrentScript()
    if self.currentScript == "" then
        return
    end

    -- Send event to C++ to reload script
    SendEvent("RequestReloadScript", VariantMap())
end

-- Cleanup
function ScriptSwitcher:Cleanup()
    self:ClosePanel()

    if self.fab then
        self.root:RemoveChild(self.fab)
        self.fab = nil
    end
end

return ScriptSwitcher
