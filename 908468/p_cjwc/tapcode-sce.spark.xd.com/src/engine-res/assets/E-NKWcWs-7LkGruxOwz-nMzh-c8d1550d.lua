-- ============================================================================
-- UrhoX UI Library
-- Yoga Flexbox + NanoVG
-- ============================================================================
--
-- ⚠️ LAYOUT NOTE: Uses Yoga (React Native) defaults, NOT CSS defaults!
--
--   flexShrink = 0 (elements don't auto-shrink, may overflow container)
--   flexDirection = column (vertical by default)
--
-- If children overflow parent, set flexShrink = 1 on children.
-- See Widget.lua header for detailed explanation.
--
-- ============================================================================

-- Core modules
local UI = require("urhox-libs/UI/Core/UI")
local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local Transition = require("urhox-libs/UI/Core/Transition")
local Input = require("urhox-libs/UI/Core/Input")
local InputAdapter = require("urhox-libs/UI/Core/InputAdapter")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")
local Gesture = require("urhox-libs/UI/Core/Gesture")
local GestureEvent = require("urhox-libs/UI/Core/GestureEvent")
local UILoader = require("urhox-libs/UI/Core/UILoader")
local UISerializer = require("urhox-libs/UI/Core/UISerializer")
local ok, UIInspector = pcall(require, "urhox-libs/UI/Core/UIInspector")
if not ok then
    if log then
        log:Write(LOG_ERROR, "Failed to load UIInspector: " .. tostring(UIInspector))
    else
        print("[UI] Failed to load UIInspector: " .. tostring(UIInspector))
    end
    UIInspector = nil
end

-- Widgets
local Panel = require("urhox-libs/UI/Widgets/Panel")
local Label = require("urhox-libs/UI/Widgets/Label")
local Button = require("urhox-libs/UI/Widgets/Button")
local TextField = require("urhox-libs/UI/Widgets/TextField")
local Checkbox = require("urhox-libs/UI/Widgets/Checkbox")
local Toggle = require("urhox-libs/UI/Widgets/Toggle")
local Slider = require("urhox-libs/UI/Widgets/Slider")
local ProgressBar = require("urhox-libs/UI/Widgets/ProgressBar")
local ScrollView = require("urhox-libs/UI/Widgets/ScrollView")
local Dropdown = require("urhox-libs/UI/Widgets/Dropdown")
local Modal = require("urhox-libs/UI/Widgets/Modal")
local Toast = require("urhox-libs/UI/Widgets/Toast")
local Tabs = require("urhox-libs/UI/Widgets/Tabs")
local Tooltip = require("urhox-libs/UI/Widgets/Tooltip")
local Badge = require("urhox-libs/UI/Widgets/Badge")
local Avatar = require("urhox-libs/UI/Widgets/Avatar")
local Card = require("urhox-libs/UI/Widgets/Card")
local List = require("urhox-libs/UI/Widgets/List")
local Divider = require("urhox-libs/UI/Widgets/Divider")
local Skeleton = require("urhox-libs/UI/Widgets/Skeleton")
local Chip = require("urhox-libs/UI/Widgets/Chip")
local Accordion = require("urhox-libs/UI/Widgets/Accordion")
local Stepper = require("urhox-libs/UI/Widgets/Stepper")
local Rating = require("urhox-libs/UI/Widgets/Rating")
local Breadcrumb = require("urhox-libs/UI/Widgets/Breadcrumb")
local Pagination = require("urhox-libs/UI/Widgets/Pagination")
local Alert = require("urhox-libs/UI/Widgets/Alert")
local Timeline = require("urhox-libs/UI/Widgets/Timeline")
local Menu = require("urhox-libs/UI/Widgets/Menu")
local Tree = require("urhox-libs/UI/Widgets/Tree")
local DatePicker = require("urhox-libs/UI/Widgets/DatePicker")
local TimePicker = require("urhox-libs/UI/Widgets/TimePicker")
local ColorPicker = require("urhox-libs/UI/Widgets/ColorPicker")
local Table = require("urhox-libs/UI/Widgets/Table")
local Carousel = require("urhox-libs/UI/Widgets/Carousel")
local Drawer = require("urhox-libs/UI/Widgets/Drawer")
local Popover = require("urhox-libs/UI/Widgets/Popover")
local Calendar = require("urhox-libs/UI/Widgets/Calendar")
local FileUpload = require("urhox-libs/UI/Widgets/FileUpload")
local RichText = require("urhox-libs/UI/Widgets/RichText")
local SafeAreaView = require("urhox-libs/UI/Widgets/SafeAreaView")
local SimpleGrid = require("urhox-libs/UI/Widgets/SimpleGrid")
local Spine = require("urhox-libs/UI/Widgets/Spine")
local SpriteSheet = require("urhox-libs/Sprite/SpriteSheet")  -- UI-agnostic core; re-exported as UI.SpriteSheet for convenience
local Sprite = require("urhox-libs/UI/Widgets/Sprite")

-- Components (advanced composite widgets)
local VirtualList = require("urhox-libs/UI/Components/VirtualList")
local DragDropContext = require("urhox-libs/UI/Components/DragDropContext")
local ItemSlot = require("urhox-libs/UI/Components/ItemSlot")
local InventoryManager = require("urhox-libs/UI/Components/InventoryManager")
local SkillTree = require("urhox-libs/UI/Components/SkillTree")
local ChatWindow = require("urhox-libs/UI/Components/ChatWindow")
local ItemTooltip = require("urhox-libs/UI/Components/ItemTooltip")

-- ============================================================================
-- Export widgets as UI.WidgetName
-- ============================================================================

UI.Widget = Widget
UI.Panel = Panel
UI.Label = Label
UI.Button = Button
UI.TextField = TextField
UI.Checkbox = Checkbox
UI.Toggle = Toggle
UI.Slider = Slider
UI.ProgressBar = ProgressBar
UI.ScrollView = ScrollView
UI.Dropdown = Dropdown
UI.Modal = Modal
UI.Toast = Toast
UI.Tabs = Tabs
UI.Tooltip = Tooltip
UI.Badge = Badge
UI.Avatar = Avatar
UI.Card = Card
UI.List = List
UI.Divider = Divider
UI.Skeleton = Skeleton
UI.Chip = Chip
UI.Accordion = Accordion
UI.Stepper = Stepper
UI.Rating = Rating
UI.Breadcrumb = Breadcrumb
UI.Pagination = Pagination
UI.Alert = Alert
UI.Timeline = Timeline
UI.Menu = Menu
UI.Tree = Tree
UI.DatePicker = DatePicker
UI.TimePicker = TimePicker
UI.ColorPicker = ColorPicker
UI.Table = Table
UI.Carousel = Carousel
UI.Drawer = Drawer
UI.Popover = Popover
UI.Calendar = Calendar
UI.FileUpload = FileUpload
UI.RichText = RichText
UI.SafeAreaView = SafeAreaView
UI.SimpleGrid = SimpleGrid
UI.Spine = Spine
UI.SpriteSheet = SpriteSheet
UI.Sprite = Sprite

-- Components (advanced)
UI.VirtualList = VirtualList
UI.DragDropContext = DragDropContext
UI.ItemSlot = ItemSlot
UI.InventoryManager = InventoryManager
UI.SkillTree = SkillTree
UI.ChatWindow = ChatWindow
UI.ItemTooltip = ItemTooltip

-- ============================================================================
-- Export utilities
-- ============================================================================

UI.Style = Style
UI.Theme = Theme
UI.Transition = Transition
UI.UILoader = UILoader
UI.UISerializer = UISerializer
-- Aliases for backward compatibility
UI.JSONLoader = UILoader
UI.JSONSerializer = UISerializer

-- ============================================================================
-- Export Input System
-- ============================================================================

UI.Input = Input
UI.InputAdapter = InputAdapter
UI.PointerEvent = PointerEvent
UI.Gesture = Gesture
UI.GestureEvent = GestureEvent
UI.Inspector = UIInspector

-- ============================================================================
-- Convenience: Make widgets callable directly from UI
-- UI.Panel { ... } instead of Panel { ... }
-- ============================================================================

setmetatable(UI, {
    __index = function(t, k)
        -- Return widget class if exists
        local widget = rawget(t, k)
        if widget then
            return widget
        end
        -- Fallback to theme access
        local theme = Theme.GetTheme()
        if theme and theme[k] then
            return theme[k]
        end
        return nil
    end
})

-- ============================================================================
-- Quick create helpers
-- ============================================================================

--- Create a horizontal layout panel (always row direction)
---@param props table
---@return Panel
function UI.Row(props)
    props = props or {}
    props.flexDirection = "row"
    return Panel(props)
end

--- Create a vertical layout panel (always column direction)
---@param props table
---@return Panel
function UI.Column(props)
    props = props or {}
    props.flexDirection = "column"
    return Panel(props)
end

--- Create a spacer widget (flex grow)
---@param flex number|nil Flex grow value (default 1)
---@return Widget
function UI.Spacer(flex)
    return Widget {
        flexGrow = flex or 1,
    }
end

--- Create a button group with automatic wrapping.
--- Buttons maintain their full text width and wrap to the next line when space runs out.
--- This is the recommended way to lay out multiple buttons (prevents text truncation).
--- Usage:
---   UI.ButtonGroup {
---       UI.Button { text = "Save", variant = "primary" },
---       UI.Button { text = "Cancel", variant = "secondary" },
---   }
---@param props table Props and child buttons (array part)
---@return Panel
function UI.ButtonGroup(props)
    props = props or {}
    props.gap = props.gap or 8
    props.flexDirection = "row"
    props.flexWrap = props.flexWrap or "wrap"
    props.alignItems = props.alignItems or "center"

    -- Extract array children before creating Panel
    local children = {}
    for i, child in ipairs(props) do
        children[i] = child
        props[i] = nil
    end

    local row = Panel(props)

    -- Add children as-is; buttons keep flexShrink=0 (won't truncate),
    -- and flexWrap="wrap" handles overflow by wrapping to the next line
    for _, child in ipairs(children) do
        row:AddChild(child)
    end

    return row
end

--- Create a fixed size box
---@param width number
---@param height number
---@return Widget
function UI.Box(width, height)
    return Widget {
        width = width,
        height = height,
    }
end

-- ============================================================================
-- Version
-- ============================================================================

UI.VERSION = "1.1.0"

return UI
