-- Nightgate Defense mobile port: central summon gate, four-wall defense.
-- Battlefield custom drawing uses NanoVG; menus/HUD use urhox-libs/UI.

local UI = require("urhox-libs/UI")
local Battle = require("nightgate.Battle")
local Renderer = require("nightgate.Renderer")
local AppUI = require("nightgate.AppUI")
local Audio = require("nightgate.Audio")
local Save = require("nightgate.Save")
local SelfTest = require("nightgate.SelfTest")
local NightgateTheme = require("nightgate.NightgateTheme")
local UIData = require("nightgate.OriginalUIData")

---@type table|nil
local battle_ = nil
---@type table|nil
local battleRenderer_ = nil
---@type table|nil
local appUI_ = nil
---@type table|nil
local audioManager_ = nil
local saveTimer_ = 0

function Start()
    graphics.windowTitle = "夜门防线"
    math.randomseed(os.time())

    UI.Init({
        theme = NightgateTheme,
        scale = UI.Scale.DESIGN_RESOLUTION(UIData.designWidth, UIData.designHeight),
    })
    battle_ = Battle.New(Save.Load())
    battleRenderer_ = Renderer.New(battle_)
    audioManager_ = Audio.New({
        musicVolume = battle_:GetMusicVolume(),
        sfxVolume = battle_:GetSfxVolume(),
    })
    appUI_ = AppUI.New(battle_, audioManager_)

    local selfTestOk, selfTestResult = pcall(SelfTest.Run)
    print("NightgateSelfTest " .. (selfTestOk and selfTestResult or ("FAIL " .. tostring(selfTestResult))))

    SubscribeToEvent(battleRenderer_.context, "NanoVGRender", "HandleBattleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")

    print("=== Nightgate Defense · four-wall mobile port started ===")
end

function Stop()
    if battle_ and battle_.dirtySave then
        Save.Store(battle_)
    end
    UI.Shutdown()
    if battleRenderer_ then
        battleRenderer_:Destroy()
    end
end

local function setCursorFromPhysical(x, y)
    if not battle_ or not battleRenderer_ then
        return
    end
    local designX, designY = battleRenderer_:ScreenToDesign(x, y)
    battle_:SetCursor(designX, designY)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    audioManager_:SetMusic(battle_.state == "running" and "battle" or "home")
    audioManager_:Update(dt)
    if not appUI_:IsBlocking() then
        battle_:Update(dt)
    end
    appUI_:Update(dt)

    local events = battle_:DrainEvents()
    for index = 1, #events do
        audioManager_:Play(events[index])
    end

    if battle_.dirtySave then
        saveTimer_ = saveTimer_ + dt
        if saveTimer_ >= 0.8 then
            Save.Store(battle_)
            saveTimer_ = 0
        end
    else
        saveTimer_ = 0
    end
end

function HandleBattleRender(eventType, eventData)
    battleRenderer_:Render()
end

function HandleMouseMove(eventType, eventData)
    if battle_ and battle_.state == "running" then
        setCursorFromPhysical(input.mousePosition.x, input.mousePosition.y)
    end
end

function HandleMouseDown(eventType, eventData)
    if eventData["Button"]:GetInt() == MOUSEB_LEFT then
        setCursorFromPhysical(input.mousePosition.x, input.mousePosition.y)
    end
end

function HandleTouchBegin(eventType, eventData)
    setCursorFromPhysical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

function HandleTouchMove(eventType, eventData)
    setCursorFromPhysical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE and battle_.state == "running" then
        battle_:ReturnHome()
        appUI_:Refresh(true)
    elseif key == KEY_SPACE and battle_.state ~= "running" then
        if battle_:IsFinalNightUnlocked() then
            battle_:StartFinalNight(battle_.finalDifficultySelected)
        else
            battle_:StartNight()
        end
        appUI_:Refresh(true)
    end
end
