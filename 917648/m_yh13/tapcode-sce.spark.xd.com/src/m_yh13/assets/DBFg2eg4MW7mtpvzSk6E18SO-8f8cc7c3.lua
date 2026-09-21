local Config = require("diggin.Config")
local App = require("diggin.App")
local AbyssIdentity = require("diggin.AbyssIdentity")

---@type table
local vg_ = nil
---@type Scene
local scene_ = nil
---@type table
local app_ = nil
local startupError_ = nil
local bootFontId_ = nil

local dpr_ = 1.0
local logicalWidth_ = Config.DESIGN_WIDTH
local logicalHeight_ = Config.DESIGN_HEIGHT
local renderScale_ = 1.0
local offsetX_ = 0.0
local offsetY_ = 0.0
local physicalWidth_ = 0
local physicalHeight_ = 0
local measuredDpr_ = 0

local function UpdateResolutionMetrics()
    local graphics = GetGraphics()
    local physicalWidth = math.max(1, graphics:GetWidth())
    local physicalHeight = math.max(1, graphics:GetHeight())
    local reportedDpr = tonumber(graphics:GetDPR()) or 1
    if reportedDpr ~= reportedDpr or reportedDpr <= 0 then reportedDpr = 1 end
    dpr_ = math.max(0.01, reportedDpr)
    physicalWidth_, physicalHeight_, measuredDpr_ = physicalWidth, physicalHeight, dpr_
    logicalWidth_ = physicalWidth / dpr_
    logicalHeight_ = physicalHeight / dpr_
    renderScale_ = math.max(0.01, math.min(
        logicalWidth_ / Config.DESIGN_WIDTH,
        logicalHeight_ / Config.DESIGN_HEIGHT
    ))
    offsetX_ = (logicalWidth_ / renderScale_ - Config.DESIGN_WIDTH) * 0.5
    offsetY_ = (logicalHeight_ / renderScale_ - Config.DESIGN_HEIGHT) * 0.5
end

local function EnsureResolutionMetrics()
    local graphics = GetGraphics()
    local currentWidth = math.max(1, graphics:GetWidth())
    local currentHeight = math.max(1, graphics:GetHeight())
    local currentDpr = tonumber(graphics:GetDPR()) or 1
    if currentDpr ~= currentDpr or currentDpr <= 0 then currentDpr = 1 end
    if currentWidth ~= physicalWidth_ or currentHeight ~= physicalHeight_
        or math.abs(currentDpr - measuredDpr_) > 0.001 then
        UpdateResolutionMetrics()
    end
end

local function PhysicalToDesign(x, y)
    EnsureResolutionMetrics()
    return x / dpr_ / renderScale_ - offsetX_,
        y / dpr_ / renderScale_ - offsetY_
end

function Start()
    -- This is a production NanoVG game, not an engine sample.  Initializing
    -- LuaScripts/Utilities/Sample creates debug UI/console infrastructure;
    -- in Maker preview that infrastructure requests the new UI Inspector,
    -- which cannot attach to this raw NanoVG-only UI and logs an error.
    input.mouseMode = MM_FREE
    input.mouseVisible = true

    scene_ = Scene()
    vg_ = nvgCreate(0)
    if vg_ == nil then
        print("ERROR: Diggin failed to create the NanoVG context")
        return
    end

    UpdateResolutionMetrics()
    bootFontId_ = nvgCreateFont(vg_, "boot", "Fonts/MiSans-Regular.ttf")
    local ok, result = xpcall(function() return App.New(vg_, scene_) end, function(err)
        local trace = debug and debug.traceback and debug.traceback() or ""
        return tostring(err) .. "\n" .. trace
    end)
    if ok then
        app_ = result
    else
        startupError_ = result
        print("ERROR: Diggin startup failed: " .. tostring(result))
    end

    SubscribeToEvent(vg_, "NanoVGRender", "HandleDigginRender")
    SubscribeToEvent("Update", "HandleDigginUpdate")
    SubscribeToEvent("ScreenMode", "HandleDigginScreenMode")
    SubscribeToEvent("MouseMove", "HandleDigginMouseMove")
    SubscribeToEvent("MouseButtonDown", "HandleDigginMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleDigginMouseUp")
    SubscribeToEvent("MouseWheel", "HandleDigginMouseWheel")
    SubscribeToEvent("TouchBegin", "HandleDigginTouchBegin")
    SubscribeToEvent("TouchMove", "HandleDigginTouchMove")
    SubscribeToEvent("TouchEnd", "HandleDigginTouchEnd")
    SubscribeToEvent("KeyDown", "HandleDigginKeyDown")
    SubscribeToEvent("TextInput", "HandleDigginTextInput")
end

function Stop()
    if app_ and app_.Shutdown then app_:Shutdown() end
    app_ = nil
    scene_ = nil
    if vg_ ~= nil then
        nvgDelete(vg_)
        vg_ = nil
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleDigginUpdate(eventType, eventData)
    if app_ and app_.abyssIdentity then return end
    if app_ then app_:Update(eventData:GetFloat("TimeStep")) end
end

function HandleDigginScreenMode(eventType, eventData)
    UpdateResolutionMetrics()
end

function HandleDigginRender(eventType, eventData)
    if vg_ == nil then return end
    EnsureResolutionMetrics()

    nvgBeginFrame(vg_, logicalWidth_, logicalHeight_, dpr_)
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, logicalWidth_, logicalHeight_)
    nvgFillColor(vg_, nvgRGBA(7, 5, 15, 255))
    nvgFill(vg_)

    nvgSave(vg_)
    nvgScale(vg_, renderScale_, renderScale_)
    nvgTranslate(vg_, offsetX_, offsetY_)
    nvgScissor(vg_, 0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT)
    if app_ then
        app_:Render()
        AbyssIdentity.Draw(app_.renderer, app_)
    else
        nvgBeginPath(vg_)
        nvgRect(vg_, 70, 82, 340, 106)
        nvgFillColor(vg_, nvgRGBA(36, 29, 42, 245))
        nvgFill(vg_)
        if bootFontId_ and bootFontId_ >= 0 then nvgFontFaceId(vg_, bootFontId_) end
        nvgFontSize(vg_, 16)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg_, nvgRGBA(235, 248, 215, 255))
        nvgText(vg_, 240, 105, "资源加载失败，请重新进入")
        nvgFontSize(vg_, 9)
        nvgFillColor(vg_, nvgRGBA(225, 59, 62, 255))
        nvgTextBox(vg_, 95, 139, 290, tostring(startupError_ or "startup error"), nil)
    end
    nvgRestore(vg_)
    nvgEndFrame(vg_)
end

---@param eventType string
---@param eventData MouseMoveEventData
function HandleDigginMouseMove(eventType, eventData)
    if not app_ then return end
    if app_.abyssIdentity then return end
    local x, y = PhysicalToDesign(eventData:GetInt("X"), eventData:GetInt("Y"))
    app_:HandlePointerMove(x, y)
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleDigginMouseDown(eventType, eventData)
    if not app_ then return end
    local x, y = PhysicalToDesign(eventData:GetInt("X"), eventData:GetInt("Y"))
    if AbyssIdentity.Pointer(app_, x, y) then return end
    app_:HandlePointerDown(eventData:GetInt("Button"), x, y, false)
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function HandleDigginMouseUp(eventType, eventData)
    if not app_ then return end
    if app_.abyssIdentity then return end
    local x, y = PhysicalToDesign(eventData:GetInt("X"), eventData:GetInt("Y"))
    app_:HandlePointerUp(eventData:GetInt("Button"), x, y, false)
end

---@param eventType string
---@param eventData MouseWheelEventData
function HandleDigginMouseWheel(eventType, eventData)
    if app_ and app_.abyssIdentity then return end
    if app_ then
        app_:HandleWheel(eventData:GetInt("Wheel"), app_.pointerX, app_.pointerY)
    end
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleDigginTouchBegin(eventType, eventData)
    if not app_ then return end
    local x, y = PhysicalToDesign(eventData:GetInt("X"), eventData:GetInt("Y"))
    if AbyssIdentity.Pointer(app_, x, y) then return end
    app_:HandlePointerDown(MOUSEB_LEFT, x, y, true, eventData:GetInt("TouchID"))
end

---@param eventType string
---@param eventData TouchMoveEventData
function HandleDigginTouchMove(eventType, eventData)
    if not app_ then return end
    if app_.abyssIdentity then return end
    local x, y = PhysicalToDesign(eventData:GetInt("X"), eventData:GetInt("Y"))
    app_:HandlePointerMove(x, y, eventData:GetInt("TouchID"))
end

---@param eventType string
---@param eventData TouchEndEventData
function HandleDigginTouchEnd(eventType, eventData)
    if not app_ then return end
    if app_.abyssIdentity then return end
    local x, y = PhysicalToDesign(eventData:GetInt("X"), eventData:GetInt("Y"))
    app_:HandlePointerUp(MOUSEB_LEFT, x, y, true, eventData:GetInt("TouchID"))
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleDigginKeyDown(eventType, eventData)
    if app_ and not eventData:GetBool("Repeat") then
        if AbyssIdentity.Key(app_, eventData:GetInt("Key")) then return end
        app_:HandleKeyDown(eventData:GetInt("Key"))
    end
end

function HandleDigginTextInput(eventType, eventData)
    if app_ then AbyssIdentity.Text(app_, eventData:GetString("Text")) end
end
