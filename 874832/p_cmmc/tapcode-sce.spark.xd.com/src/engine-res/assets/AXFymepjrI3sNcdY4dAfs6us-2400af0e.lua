--[[
    SkillTreeExample.lua

    Demo of SkillTree component with zoom/pan and node unlocking.

    Features:
    - Skill tree with parent-child connections
    - State-based coloring (unlocked/locked/unlockable)
    - Unlockable nodes pulse with animation
    - Mouse wheel zoom, middle-button pan
    - Click to unlock available skills

    Usage:
        require("LuaScripts/SkillTreeExample")
        -- Just call Start() or run directly via UrhoX runtime
]]

local UI = require("urhox-libs/UI/init")

local SkillTreeExample = {}

--------------------------------------------------------------------------------
-- Sample Skill Tree Data (like a JSON config)
--------------------------------------------------------------------------------

local function CreateSkillTreeData()
    --[[
        Tree structure:
                    [Basic Attack]
                    /      \
            [Heavy Strike] [Quick Slash]
                |              |
            [Crushing Blow] [Blade Dance]
                    \      /
                [Ultimate: Storm of Steel]
    ]]
    return {
        -- Root node (already unlocked)
        {
            id = 1,
            parentId = nil,
            x = 200,
            y = 50,
            name = "Basic",
            icon = "⚔️",
            unlocked = true,
            description = "Basic attack skill",
        },

        -- Tier 2 - Left branch
        {
            id = 2,
            parentId = 1,
            x = 100,
            y = 150,
            name = "Heavy",
            icon = "💥",
            unlocked = false,
            description = "Heavy strike deals 2x damage",
        },

        -- Tier 2 - Right branch
        {
            id = 3,
            parentId = 1,
            x = 300,
            y = 150,
            name = "Quick",
            icon = "💨",
            unlocked = false,
            description = "Quick slash attacks twice",
        },

        -- Tier 3 - Left branch
        {
            id = 4,
            parentId = 2,
            x = 100,
            y = 250,
            name = "Crush",
            icon = "🔨",
            unlocked = false,
            description = "Crushing blow stuns enemy",
        },

        -- Tier 3 - Right branch
        {
            id = 5,
            parentId = 3,
            x = 300,
            y = 250,
            name = "Dance",
            icon = "🌀",
            unlocked = false,
            description = "Blade dance hits all enemies",
        },

        -- Tier 4 - Ultimate (requires both branches)
        -- Note: For simplicity, we only track single parent.
        -- A real implementation might support multiple parents.
        {
            id = 6,
            parentId = 4,  -- Connected to left branch
            x = 200,
            y = 350,
            name = "Ultimate",
            icon = "⚡",
            unlocked = false,
            description = "Storm of Steel - Ultimate attack",
        },

        -- Additional connection line (visual only, from node 5 to 6)
        -- We'll handle this specially or just accept single-parent for now
    }
end

--------------------------------------------------------------------------------
-- Global State
--------------------------------------------------------------------------------

local root = nil
local skillTree = nil
local statusLabel = nil
local skillPoints = 5  -- Available skill points

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

local function UpdateStatus()
    if statusLabel then
        statusLabel:SetText(string.format("Skill Points: %d | Scroll to zoom, Middle-drag to pan, Click to unlock", skillPoints))
    end
end

local function OnNodeClick(node)
    print(string.format("[SkillTree] Clicked: %s (id=%d, unlocked=%s)",
        node.name or "?", node.id, tostring(node.unlocked)))
end

local function OnNodeUnlock(node)
    if skillPoints > 0 then
        skillPoints = skillPoints - 1
        print(string.format("[SkillTree] Unlocked: %s! Remaining points: %d", node.name or "?", skillPoints))
        UpdateStatus()
    else
        -- Revert unlock if no skill points
        node.unlocked = false
        print("[SkillTree] Not enough skill points!")
    end
end

local function OnNodeLock(node)
    -- Refund skill point
    skillPoints = skillPoints + 1
    print(string.format("[SkillTree] Refunded: %s! Remaining points: %d", node.name or "?", skillPoints))
    UpdateStatus()
end

local function CreateUI()
    -- Create root container
    root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 25, 28, 35, 255 },
        flexDirection = "column",
        padding = 20,
        gap = 16,
    }

    -- Title
    root:AddChild(UI.Label {
        text = "Skill Tree Demo",
        fontSize = 24,
        fontColor = { 255, 255, 255, 255 },
    })

    -- Status label
    statusLabel = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 150, 150, 180, 255 },
    }
    root:AddChild(statusLabel)
    UpdateStatus()

    -- Create skill tree
    skillTree = UI.SkillTree {
        width = "100%",
        flexGrow = 1,
        nodes = CreateSkillTreeData(),
        nodeSize = 64,
        lineWidth = 3,
        onNodeClick = OnNodeClick,
        onNodeUnlock = OnNodeUnlock,
        onNodeLock = OnNodeLock,
        minZoom = 0.5,
        maxZoom = 2.0,
    }
    root:AddChild(skillTree)

    -- Control buttons
    local controls = UI.Panel {
        flexDirection = "row",
        gap = 10,
        justifyContent = "center",
    }

    controls:AddChild(UI.Button {
        text = "Reset Tree",
        width = 100,
        height = 36,
        onClick = function()
            -- Reset all nodes except root
            local nodes = skillTree.props.nodes
            for _, node in ipairs(nodes) do
                if node.id ~= 1 then
                    node.unlocked = false
                end
            end
            skillPoints = 5
            UpdateStatus()
            print("[SkillTree] Tree reset!")
        end,
    })

    controls:AddChild(UI.Button {
        text = "Add Points",
        width = 100,
        height = 36,
        onClick = function()
            skillPoints = skillPoints + 3
            UpdateStatus()
            print("[SkillTree] Added 3 skill points!")
        end,
    })

    controls:AddChild(UI.Button {
        text = "Zoom In",
        width = 80,
        height = 36,
        onClick = function()
            skillTree:SetZoom(skillTree:GetZoom() * 1.2)
        end,
    })

    controls:AddChild(UI.Button {
        text = "Zoom Out",
        width = 80,
        height = 36,
        onClick = function()
            skillTree:SetZoom(skillTree:GetZoom() / 1.2)
        end,
    })

    controls:AddChild(UI.Button {
        text = "Center",
        width = 80,
        height = 36,
        onClick = function()
            skillTree:CenterOnNode(1)  -- Center on root node
        end,
    })

    root:AddChild(controls)

    -- Instructions footer
    local footer = UI.Panel {
        flexDirection = "column",
        alignItems = "center",
        gap = 4,
    }
    footer:AddChild(UI.Label {
        text = "Green = Unlocked | Gold (pulsing) = Unlockable | Gray = Locked",
        fontSize = 11,
        fontColor = { 100, 100, 130, 255 },
    })
    root:AddChild(footer)

    return root
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function SkillTreeExample.Init()
    UI.Init({
        fonts = {
            { name = "sans", path = "Fonts/MiSans-Regular.ttf" },
        },
        autoEvents = true,
        designSize = 1080,
    })

    UI.SetRoot(CreateUI())

    print("[SkillTreeExample] Initialized")
    print("[SkillTreeExample] Click gold (pulsing) nodes to unlock skills")
    print("[SkillTreeExample] Use mouse wheel to zoom, middle-drag to pan")
end

function SkillTreeExample.Shutdown()
    UI.Shutdown()
end

-- Direct execution
function Start()
    SkillTreeExample.Init()
end

return SkillTreeExample
