-- UILayoutExample.lua
-- Comprehensive Layout system examples for AI coding reference
-- Covers all common patterns: vertical/horizontal layouts, nested layouts, flexScale, fixed sizes

require "LuaScripts/Utilities/Sample"

function Start()
    SampleStart()
    CreateUI()
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    -- Show mouse cursor
    input.mouseVisible = true
end

function CreateUI()
    -- Root UI element
    local root = ui.root
    root:SetDefaultStyle(cache:GetResource("XMLFile", "UI/DefaultStyle.xml"))

    -- Example 1: Vertical Layout (Header + Content + Footer)
    CreateVerticalLayoutExample(root)

    -- Example 2: Horizontal Layout (Sidebar + Content)
    CreateHorizontalLayoutExample(root)

    -- Example 3: Nested Layout (Toolbar with buttons)
    CreateNestedLayoutExample(root)

    -- Example 4: Grid Layout (Button grid)
    CreateGridLayoutExample(root)
end

-- ========================================
-- Example 1: Vertical Layout (Header + Content + Footer)
-- Pattern: Fixed top + Flexible middle + Fixed bottom
-- ========================================
function CreateVerticalLayoutExample(parent)
    local win = parent:CreateChild("Window")
    win:SetStyleAuto()
    win:SetPosition(20, 20)
    win:SetSize(360, 420)

    -- ✅ NO manual SetMinSize() needed!
    -- Layout system automatically calculates win.layoutMinSize_ from children
    -- This is the RECOMMENDED approach for AI coding

    win:SetLayout(LM_VERTICAL, 0, IntRect(0, 0, 0, 0))
    win:SetMovable(true)
    win:SetResizable(true)
    win.name = "LayoutExample"

    -- Title (fixed height within layout)
    local titleBar = win:CreateChild("UIElement")
    titleBar:SetFixedHeight(30)

    -- Title text
    local winTitle = titleBar:CreateChild("Text")
    winTitle:SetStyleAuto()
    winTitle:SetPosition(10, 5)
    winTitle.text = "Example 1: Vertical Layout"
    winTitle:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)

    -- Header (fixed height)
    local header = win:CreateChild("BorderImage")
    header:SetStyle("Button")
    header:SetFixedHeight(60)

    local headerText = header:CreateChild("Text")
    headerText:SetStyleAuto()
    headerText.text = "Fixed Header (60px)\nSetFixedHeight(60)"
    headerText:SetAlignment(HA_CENTER, VA_CENTER)
    headerText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 11)

    -- Content area (flexible - fills remaining space)
    local content = win:CreateChild("BorderImage")
    content:SetStyle("BorderImage")
    content:SetMinSize(0, 180)  -- ✅ Width flexible, height at least 180
    content:SetLayoutFlexScale(Vector2(1, 1))  -- ✅ Expands to fill remaining space
    content:SetClipChildren(true) -- ⚠️ 多行文本的layout容器建议设置ClipChildren，防止子元素（如Text）内容超出容器显示区域

    local contentText = content:CreateChild("Text")
    contentText:SetStyleAuto()
    contentText.text = [[Flexible Content

SetMinSize(0, 180)
SetLayoutFlexScale(Vector2(1, 1))

Declares: width=any, height>=180

✅ AUTOMATIC minSize propagation:
  titleBar(30) + header(60) + content(180)
  + middle(40) + footer(30)
  = win.layoutMinSize_ = (0, 340)

Try shrinking: Stops at 340px height!

NO manual win:SetMinSize() needed!]]
    contentText:SetAlignment(HA_CENTER, VA_CENTER)
    contentText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 10)
    contentText:SetWordwrap(true)

    -- Middle bar (fixed height)
    local middleBar = win:CreateChild("BorderImage")
    middleBar:SetStyle("Button")
    middleBar:SetFixedHeight(40)

    local middleText = middleBar:CreateChild("Text")
    middleText:SetStyleAuto()
    middleText.text = "Fixed Middle (40px)"
    middleText:SetAlignment(HA_CENTER, VA_CENTER)
    middleText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 11)

    -- Footer / Status bar (fixed height)
    local footer = win:CreateChild("BorderImage")
    footer:SetStyle("Button")
    footer:SetFixedHeight(30)

    statusText = footer:CreateChild("Text")
    statusText:SetStyleAuto()
    statusText.text = "Fixed Footer (30px) - Always at bottom"
    statusText:SetAlignment(HA_CENTER, VA_CENTER)
    statusText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 10)

    -- Store reference for resize handling
    win.contentArea = content

    -- Handle resize to update status text
    local statusTextRef = statusText
    SubscribeToEvent(win, "Resized", function(eventType, eventData)
        local newSize = win:GetSize()
        -- ⚠️ NOTE: Do NOT update minSize here!
        -- win:SetMinSize(newSize.x, newSize.y)  -- ❌ This would lock window size (can only grow, not shrink)
        statusTextRef.text = string.format("Footer - Window: %dx%d", newSize.x, newSize.y)
    end)

    return win
end

-- ========================================
-- Example 2: Horizontal Layout (Sidebar + Content)
-- Pattern: Fixed left + Flexible right
-- ========================================
function CreateHorizontalLayoutExample(parent)
    local win = parent:CreateChild("Window")
    win:SetStyleAuto()
    win:SetPosition(400, 20)
    win:SetSize(600, 420)

    -- ⚠️ This example has manually positioned title, so we use nested layout
    -- Win itself uses Layout to auto-manage minSize
    win:SetLayout(LM_VERTICAL, 0, IntRect(0, 0, 0, 0))
    win:SetMovable(true)
    win:SetResizable(true)

    -- Title (fixed height within layout)
    local titleBar = win:CreateChild("UIElement")
    titleBar:SetFixedHeight(30)

    local winTitle = titleBar:CreateChild("Text")
    winTitle:SetStyleAuto()
    winTitle:SetPosition(10, 5)
    winTitle.text = "Example 2: Horizontal Layout"
    winTitle:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)

    -- Container for horizontal layout (flexible)
    local container = win:CreateChild("UIElement")
    container:SetLayoutFlexScale(Vector2(1, 1))
    container:SetLayout(LM_HORIZONTAL, 0, IntRect(0, 0, 0, 0))

    -- Sidebar (fixed width, minimum height)
    local sidebar = container:CreateChild("BorderImage")
    sidebar:SetStyle("BorderImage")
    sidebar:SetFixedWidth(200)  -- ✅ Fixed width (like File Explorer)
    sidebar:SetMinHeight(200)   -- ✅ Minimum height

    local sidebarText = sidebar:CreateChild("Text")
    sidebarText:SetStyleAuto()
    sidebarText.text = [[Fixed Sidebar

SetFixedWidth(200)
SetMinHeight(200)

Pattern:
- Width: FIXED (never changes)
- Height: minimum constraint

Use when:
- Sidebar should stay same width
- Like File Explorer navigation]]
    sidebarText:SetPosition(10, 40)
    sidebarText:SetWordwrap(true)
    sidebarText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 10)

    -- Main content (flexible)
    local mainContent = container:CreateChild("BorderImage")
    mainContent:SetStyle("Button")
    mainContent:SetMinSize(400, 300)  -- ✅ Minimum width AND height
    mainContent:SetLayoutFlexScale(Vector2(1, 1))  -- Fills remaining space
    mainContent:SetClipChildren(true) -- ⚠️ 多行文本的layout容器建议设置ClipChildren，防止子元素（如Text）内容超出容器显示区域

    local contentText = mainContent:CreateChild("Text")
    contentText:SetStyleAuto()
    contentText.text = [[Flexible Main Content

SetMinSize(400, 300)
SetLayoutFlexScale(Vector2(1, 1))

✅ Declares BOTH dimensions
(prevents shrinking in both directions)

✅ Auto propagation:
  container.layoutMinSize_ =
    width: 200 + 400 = 600
    height: max(200, 300) = 300

  win.layoutMinSize_ =
    (600, 330) (30 title + 300 container)

Window stops at 600x330!]]
    contentText:SetAlignment(HA_CENTER, VA_CENTER)
    contentText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 11)
    contentText:SetWordwrap(true)

    return win
end

-- ========================================
-- Example 3: Nested Layout (Toolbar with buttons)
-- Pattern: Horizontal layout with flexible spacer
-- ========================================
function CreateNestedLayoutExample(parent)
    local win = parent:CreateChild("Window")
    win:SetStyleAuto()
    win:SetPosition(20, 460)
    win:SetSize(520, 240)

    -- ✅ NO manual SetMinSize - using AUTO mode
    win:SetLayout(LM_VERTICAL, 0, IntRect(0, 0, 0, 0))
    win:SetMovable(true)
    win:SetResizable(true)

    -- Title bar (fixed height within layout)
    local titleBar = win:CreateChild("UIElement")
    titleBar:SetFixedHeight(30)

    local winTitle = titleBar:CreateChild("Text")
    winTitle:SetStyleAuto()
    winTitle:SetPosition(10, 5)
    winTitle.text = "Example 3: Nested Layout (Toolbar)"
    winTitle:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)

    -- Toolbar (horizontal layout with fixed height)
    local toolbar = win:CreateChild("BorderImage")
    toolbar:SetStyle("BorderImage")
    toolbar:SetFixedHeight(40)
    toolbar:SetLayout(LM_HORIZONTAL, 5, IntRect(5, 5, 5, 5))

    -- Left buttons (fixed width)
    for _, label in ipairs({"New", "Open", "Save"}) do
        local btn = toolbar:CreateChild("Button")
        btn:SetStyleAuto()
        btn:SetFixedSize(60, 30)

        local btnText = btn:CreateChild("Text")
        btnText:SetStyleAuto()
        btnText.text = label
        btnText:SetAlignment(HA_CENTER, VA_CENTER)
        btnText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 10)
    end

    -- Spacer (flexible - pushes remaining buttons to right)
    -- ✅ This is a common pattern for right-aligned toolbar items
    local spacer = toolbar:CreateChild("UIElement")
    spacer:SetLayoutFlexScale(Vector2(1, 0))  -- Expands horizontally only

    -- Right buttons (fixed width)
    for _, label in ipairs({"Settings", "Help"}) do
        local btn = toolbar:CreateChild("Button")
        btn:SetStyleAuto()
        btn:SetFixedSize(70, 30)

        local btnText = btn:CreateChild("Text")
        btnText:SetStyleAuto()
        btnText.text = label
        btnText:SetAlignment(HA_CENTER, VA_CENTER)
        btnText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 10)
    end

    -- Content area (flexible)
    local content = win:CreateChild("BorderImage")
    content:SetStyle("Button")
    content:SetMinSize(0, 120)  -- ✅ Minimum height
    content:SetLayoutFlexScale(Vector2(1, 1))
    content:SetClipChildren(true) -- ⚠️ 多行文本的layout容器建议设置ClipChildren，防止子元素（如Text）内容超出容器显示区域

    local contentText = content:CreateChild("Text")
    contentText:SetStyleAuto()
    contentText.text = [[Nested Layout Pattern

Toolbar uses LM_HORIZONTAL:
- Fixed-width buttons (SetFixedSize)
- Flexible spacer (SetLayoutFlexScale(1, 0))
- Pushes "Settings" and "Help" to right

✅ Auto: win.layoutMinSize_ calculated
from titleBar(30) + toolbar(40) + content(120)
= (0, 190)

Common for: Toolbars, status bars, navigation]]
    contentText:SetAlignment(HA_CENTER, VA_CENTER)
    contentText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 10)
    contentText:SetWordwrap(true)

    return win
end

-- ========================================
-- Example 4: Grid Layout (Calculator-style button grid)
-- Pattern: Nested vertical + horizontal layouts
-- ========================================
function CreateGridLayoutExample(parent)
    local win = parent:CreateChild("Window")
    win:SetStyleAuto()
    win:SetPosition(1020, 20)
    win:SetSize(340, 420)

    -- ✅ NO manual SetMinSize - using AUTO mode
    win:SetLayout(LM_VERTICAL, 0, IntRect(0, 0, 0, 0))
    win:SetMovable(true)
    win:SetResizable(true)

    -- Title bar (fixed height within layout)
    local titleBar = win:CreateChild("UIElement")
    titleBar:SetFixedHeight(30)

    local winTitle = titleBar:CreateChild("Text")
    winTitle:SetStyleAuto()
    winTitle:SetPosition(10, 5)
    winTitle.text = "Example 4: Grid Layout"
    winTitle:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)

    -- Display area (fixed height)
    local display = win:CreateChild("BorderImage")
    display:SetStyle("BorderImage")
    display:SetFixedHeight(60)

    local displayText = display:CreateChild("Text")
    displayText:SetStyleAuto()
    displayText.text = "Grid Layout (4x4)"
    displayText:SetAlignment(HA_CENTER, VA_CENTER)
    displayText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 14)

    -- Button grid area (flexible, fills remaining space)
    local gridArea = win:CreateChild("UIElement")
    gridArea:SetLayoutFlexScale(Vector2(1, 1))
    gridArea:SetLayout(LM_VERTICAL, 4, IntRect(6, 6, 6, 6))

    -- Create 4 rows
    for row = 1, 4 do
        local rowElement = gridArea:CreateChild("UIElement")
        rowElement:SetLayoutFlexScale(Vector2(1, 1))  -- Equal height distribution
        rowElement:SetLayout(LM_HORIZONTAL, 4, IntRect(0, 0, 0, 0))

        -- Create 4 buttons per row
        for col = 1, 4 do
            local btn = rowElement:CreateChild("Button")
            btn:SetStyleAuto()
            btn:SetLayoutFlexScale(Vector2(1, 1))  -- Equal width distribution
            btn:SetMinSize(50, 50)  -- Minimum size for buttons

            local btnText = btn:CreateChild("Text")
            btnText:SetStyleAuto()
            btnText.text = tostring((row - 1) * 4 + col)
            btnText:SetAlignment(HA_CENTER, VA_CENTER)
            btnText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 16)
        end
    end

    return win
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE then
        engine:Exit()
    end
end

-- Create the instructions overlay
function CreateInstructions()
    local instructionText = ui.root:CreateChild("Text")
    instructionText:SetText(
        "UI Layout System - Best Practices for AI\n\n" ..
        "Four common layout patterns demonstrated:\n\n" ..
        "1️⃣  VERTICAL: Auto minSize propagation\n" ..
        "2️⃣  HORIZONTAL: Nested layouts\n" ..
        "3️⃣  TOOLBAR: Flexible spacer pattern\n" ..
        "4️⃣  GRID: Button grid layout\n\n" ..
        "✅ RECOMMENDED APPROACH (Auto):\n" ..
        "  1. win:SetLayout(LM_VERTICAL/HORIZONTAL, 0)\n" ..
        "  2. Child: SetFixedHeight() for fixed elements\n" ..
        "  3. Child: SetMinSize(w,h) + SetLayoutFlexScale()\n" ..
        "  4. NO manual win:SetMinSize() needed!\n\n" ..
        "✅ How it works:\n" ..
        "  • Children use SetMinSize(w,h) to declare needs\n" ..
        "  • Layout calculates win.layoutMinSize_\n" ..
        "  • SetSize() respects layoutMinSize_\n" ..
        "  • Window auto-protected in BOTH dimensions\n\n" ..
        "⚠️  Always use SetMinSize(w,h) not SetMinWidth/Height!\n" ..
        "⚠️  Only manual win:SetMinSize() if win is LM_FREE\n\n" ..
        "Try resizing windows - they stop at minimum!\n\n" ..
        "ESC: Exit"
    )
    instructionText:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 10)
    instructionText:SetPosition(560, 460)
    instructionText:SetSize(680, 240)
    instructionText:SetTextAlignment(HA_LEFT)
    instructionText:SetWordwrap(true)
    instructionText:SetColor(Color(1, 1, 1, 0.9))
end

-- Optional: Create instructions after UI is ready
CreateInstructions()
