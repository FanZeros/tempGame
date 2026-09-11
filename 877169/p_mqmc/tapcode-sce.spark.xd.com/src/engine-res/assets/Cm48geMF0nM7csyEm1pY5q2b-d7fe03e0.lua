--[[
    ChatWindowExample.lua

    Demo of MMO-style chat window with rich text support.

    Features:
    - Custom tag parsing: <item id=X>, <link>, <emoji>
    - Inline images/emojis (图文混排)
    - Auto-height message bubbles
    - Item tooltips on click
    - Scrollable message list

    Usage:
        require("LuaScripts/ChatWindowExample")
        -- Just call Start() or run directly via UrhoX runtime
]]

local UI = require("urhox-libs/UI/init")

local ChatWindowExample = {}

--------------------------------------------------------------------------------
-- Sample Item Database
--------------------------------------------------------------------------------

local ITEM_DATABASE = {
    [101] = {
        name = "Excalibur",
        icon = "⚔",
        rarity = "legendary",
        description = "The legendary sword of King Arthur",
    },
    [102] = {
        name = "Health Potion",
        icon = "🧪",
        rarity = "common",
        description = "Restores 100 HP",
    },
    [103] = {
        name = "Dragon Scale Armor",
        icon = "🛡",
        rarity = "epic",
        description = "Armor forged from dragon scales",
    },
    [104] = {
        name = "Mystic Ring",
        icon = "💍",
        rarity = "rare",
        description = "+50 Magic Power",
    },
    [105] = {
        name = "Gold Coins",
        icon = "🪙",
        rarity = "common",
        description = "1000 Gold",
    },
    [106] = {
        name = "Phoenix Feather",
        icon = "🪶",
        rarity = "legendary",
        description = "Revives the user once",
    },
}

--------------------------------------------------------------------------------
-- Sample Messages
--------------------------------------------------------------------------------

local function CreateSampleMessages()
    return {
        {
            sender = "System",
            content = "Welcome to the World of UrhoX! <emoji name=star>",
            isSystem = true,
        },
        {
            sender = "PlayerOne",
            content = "Hey everyone! I just found <item id=101> in the dungeon!",
            isSelf = false,
        },
        {
            sender = "You",
            content = "Wow, that's amazing! <emoji name=fire> I only got <item id=102>",
            isSelf = true,
        },
        {
            sender = "GuildMaster",
            content = "Nice find! Check out our guild website: <link url=\"https://example.com/guild\">Guild Portal</link>",
            isSelf = false,
        },
        {
            sender = "Trader",
            content = "WTS: <item id=103> and <item id=104> - PM me!",
            isSelf = false,
        },
        {
            sender = "You",
            content = "How much for the <item id=104>?",
            isSelf = true,
        },
        {
            sender = "Trader",
            content = "<item id=105> x5 for the ring, deal? <emoji name=thumbsup>",
            isSelf = false,
        },
        {
            sender = "System",
            content = "Server maintenance in 30 minutes. Please save your progress!",
            isSystem = true,
        },
        {
            sender = "Healer",
            content = "LFG for Dragon Raid! Need tank and DPS. I have <item id=106> for emergency!",
            isSelf = false,
        },
        {
            sender = "You",
            content = "I can join as DPS! <emoji name=smile>",
            isSelf = true,
        },
    }
end

--------------------------------------------------------------------------------
-- Global State
--------------------------------------------------------------------------------

local root = nil
local chatWindow = nil
local inputField = nil
local statusLabel = nil

--------------------------------------------------------------------------------
-- Item Resolver
--------------------------------------------------------------------------------

local function ResolveItem(id)
    return ITEM_DATABASE[tonumber(id)]
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

local function OnItemClick(item)
    print(string.format("[Chat] Item clicked: %s (%s)", item.name or "?", item.rarity or "?"))
    if statusLabel then
        statusLabel:SetText("Clicked: " .. (item.name or "Unknown Item"))
    end
end

local function OnLinkClick(url, text)
    print(string.format("[Chat] Link clicked: %s (%s)", text or "?", url or "?"))
    if statusLabel then
        statusLabel:SetText("Link: " .. (url or "Unknown URL"))
    end
end

local function SendMessage(text)
    if not text or #text == 0 then return end

    chatWindow:AddMessage({
        sender = "You",
        content = text,
        isSelf = true,
        timestamp = os.time(),
    })

    print("[Chat] Sent: " .. text)
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

local function CreateUI()
    -- Create root container
    root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 20, 22, 28, 255 },
        flexDirection = "column",
        padding = 16,
        gap = 12,
    }

    -- Title
    root:AddChild(UI.Label {
        text = "MMO Chat Window Demo",
        fontSize = 20,
        fontColor = { 255, 255, 255, 255 },
    })

    -- Status label
    statusLabel = UI.Label {
        text = "Click on [items] to see tooltips, click links to open",
        fontSize = 11,
        fontColor = { 120, 120, 150, 255 },
    }
    root:AddChild(statusLabel)

    -- Chat window
    chatWindow = UI.ChatWindow {
        width = "100%",
        flexGrow = 1,
        messages = CreateSampleMessages(),
        fontSize = 14,
        itemResolver = ResolveItem,
        onItemClick = OnItemClick,
        onLinkClick = OnLinkClick,
    }
    root:AddChild(chatWindow)

    -- Input area
    local inputArea = UI.Panel {
        flexDirection = "row",
        gap = 8,
        height = 40,
    }

    -- Text input
    inputField = UI.TextField {
        flexGrow = 1,
        height = 36,
        placeholder = "Type a message... (use <item id=101> for items)",
        fontSize = 14,
        onSubmit = function(field, text)
            SendMessage(text)
            field:Clear()
        end,
    }
    inputArea:AddChild(inputField)

    -- Send button
    inputArea:AddChild(UI.Button {
        text = "Send",
        width = 70,
        height = 36,
        onClick = function()
            local text = inputField:GetValue()
            SendMessage(text)
            inputField:Clear()
        end,
    })

    root:AddChild(inputArea)

    -- Quick message buttons
    local quickButtons = UI.Panel {
        flexDirection = "row",
        gap = 6,
        flexWrap = "wrap",
    }

    local quickMessages = {
        { label = "Item Link", msg = "Check out my <item id=101>!" },
        { label = "Emoji", msg = "Hello! <emoji name=smile><emoji name=heart>" },
        { label = "Link", msg = "Visit <link url=\"https://urho3d.io\">Urho3D</link>" },
        { label = "Mixed", msg = "<emoji name=fire> Got <item id=106>! <emoji name=star>" },
        { label = "Trade", msg = "WTS <item id=103> <item id=104> - 500g each" },
    }

    for _, qm in ipairs(quickMessages) do
        quickButtons:AddChild(UI.Button {
            text = qm.label,
            height = 28,
            fontSize = 11,
            onClick = function()
                SendMessage(qm.msg)
            end,
        })
    end

    root:AddChild(quickButtons)

    -- Instructions
    local footer = UI.Panel {
        flexDirection = "column",
        gap = 2,
    }
    footer:AddChild(UI.Label {
        text = "Tags: <item id=N> <emoji name=X> <link url=X>text</link>",
        fontSize = 10,
        fontColor = { 80, 80, 100, 255 },
    })
    footer:AddChild(UI.Label {
        text = "Scroll to view history | Click items for tooltip | Click links to activate",
        fontSize = 10,
        fontColor = { 80, 80, 100, 255 },
    })
    root:AddChild(footer)

    return root
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function ChatWindowExample.Init()
    UI.Init({
        fonts = {
            { name = "sans", path = "Fonts/MiSans-Regular.ttf" },
        },
        autoEvents = true,
        -- 推荐! DPR 缩放 + 小屏密度自适应（见 ui.md §10）
        -- 1 基准像素 ≈ 1 CSS 像素，尺寸遵循 CSS/Web 常识
        scale = UI.Scale.DEFAULT,
    })

    UI.SetRoot(CreateUI())

    print("[ChatWindowExample] Initialized")
    print("[ChatWindowExample] Click on [item names] to show tooltips")
    print("[ChatWindowExample] Use quick buttons to send test messages")
end

function ChatWindowExample.Shutdown()
    UI.Shutdown()
end

-- Direct execution
function Start()
    ChatWindowExample.Init()
end

return ChatWindowExample
