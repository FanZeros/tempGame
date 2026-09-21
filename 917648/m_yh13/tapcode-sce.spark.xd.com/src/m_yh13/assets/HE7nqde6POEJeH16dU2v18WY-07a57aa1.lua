local Config = require("diggin.Config")
local Util = require("diggin.Util")

local Controls = {}

local function getLayout(app)
    if app and app.state and app.state.GetMobileControls then
        return app.state:GetMobileControls()
    end
    return Config.Controls
end

local function getMoveValue(app, x, y)
    local layout = getLayout(app)
    local dx = Util.Clamp(x - layout.moveX, -layout.moveRadius, layout.moveRadius)
    local magnitude = math.abs(dx)
    if magnitude <= layout.moveDeadzone then return 0 end
    local value = (magnitude - layout.moveDeadzone) /
        math.max(1, layout.moveRadius - layout.moveDeadzone)
    return (dx < 0 and -1 or 1) * Util.Clamp(value, 0, 1)
end

function Controls.UpdateAimFromPad(app, x, y)
    local layout = getLayout(app)
    local dx, dy = x - layout.aimX, y - layout.aimY
    local length = Util.Length(dx, dy)
    if length < 3 then dx, dy, length = 0, 1, 1 end
    app.mobileAimX, app.mobileAimY = dx / length, dy / length
    app.pointerX = 240 + app.player.x + app.mobileAimX * 100
    app.pointerY = 135 + app.mobileAimY * 100
end

function Controls.ToggleAutoDig(app)
    app.autoDigLocked = not app.autoDigLocked
    if app.autoDigLocked then
        app.mobileAimX, app.mobileAimY = 0, 1
        app.pointerX, app.pointerY = 240 + app.player.x, 235
        app:ShowToast("自动向下钻：开启 · 再点锁键停止", Config.Palette.gold, 3)
    else
        app:ShowToast("自动向下钻：已停止", Config.Palette.creamDim, 2)
    end
    app:RefreshHeldInputs()
end

function Controls.CancelAutoDigForMovement(app)
    if not app.autoDigLocked then return false end
    app.autoDigLocked = false
    if app.ShowToast then
        app:ShowToast("手动移动 · 已解除自动钻探", Config.Palette.creamDim, 1.4)
    end
    return true
end

function Controls.RefreshHeldInputs(app)
    local wasLeftHeld = app.leftHeld == true
    local touchDig, touchLaser = false, false
    app.mobileMove = 0
    for _, touch in pairs(app.touches) do
        if touch.action == "dig" or touch.action == "aim" then
            touchDig = true
        elseif touch.action == "laser" then
            touchLaser = true
        elseif touch.action == "move" then
            app.mobileMove = app.mobileMove + getMoveValue(app, touch.x, touch.y)
        end
    end
    app.mobileMove = Util.Clamp(app.mobileMove, -1, 1)
    -- Movement and auto drilling are independent: players may steer while the
    -- lock keeps drilling. Only pressing the lock button again disables it.
    app.leftHeld = app.mouseLeftHeld or app.autoDigLocked or touchDig
    app.rightHeld = app.mouseRightHeld or app.mouseLaserHeld or touchLaser
    app.touchHeld = touchDig
    -- Touch begin/end can both arrive between two Update events. Start the
    -- drilling action at the input edge so a ready active skill is never lost
    -- on a quick tap.
    if app.leftHeld and not wasLeftHeld and app.mode == "playing" then
        local aimWorldX = app.pointerX - Config.DESIGN_WIDTH * 0.5
        local aimWorldY = app.player.y + app.pointerY - Config.DESIGN_HEIGHT * 0.5
        app.aimAngle = math.atan(aimWorldY - app.player.y, aimWorldX - app.player.x)
        app:StartDrilling()
        app:UpdateActiveUpgrades(0)
    end
end

function Controls.GetTouchAction(app, x, y)
    local layout = getLayout(app)
    if Util.Length(x - layout.moveX, y - layout.moveY)
        <= layout.moveRadius + layout.moveTouchPadding then return "move" end
    if x >= layout.laserX and x <= layout.laserX + layout.laserW
        and y >= layout.laserY and y <= layout.laserY + layout.laserH
        and not app.isAbyssRun and app.state:IsNodeBought("Laser") then return "laser" end
    if Util.Length(x - layout.aimX, y - layout.aimY)
        <= layout.aimRadius + layout.aimTouchPadding then return "aim" end
    return "dig"
end

function Controls.UpdateTouchLaserAim(app)
    if not app.isAbyssRun or not app.abyss or not app.abyss.tower then return false end
    local heldByTouch = false
    for _, touch in pairs(app.touches or {}) do
        if touch.action == "laser" then heldByTouch = true; break end
    end
    if not heldByTouch then return false end

    local nearest, nearestDistance
    for _, enemy in ipairs(app.abyss.tower.enemies or {}) do
        if (enemy.hp or 0) > 0 then
            local distance = Util.Length(enemy.x - app.player.x, enemy.y - app.player.y)
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestDistance = enemy, distance
            end
        end
    end
    if not nearest then return false end
    app.pointerX = Config.DESIGN_WIDTH * 0.5 + nearest.x
    app.pointerY = Config.DESIGN_HEIGHT * 0.5 + nearest.y - app.player.y
    return true
end

return Controls
