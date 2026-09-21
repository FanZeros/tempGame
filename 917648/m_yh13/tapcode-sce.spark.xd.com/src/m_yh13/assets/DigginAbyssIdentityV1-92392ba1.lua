local Config = require("diggin.Config")
local Identity = {}

function Identity.Clean(value)
    value = tostring(value or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not utf8.len(value) then return "" end
    local ending = utf8.offset(value, 13)
    return ending and value:sub(1, ending - 1) or value
end

function Identity.Open(app, runMode)
    if Identity.Clean(app.state.abyssCallsign) ~= "" then
        app:StartRun(false, true, runMode)
        return
    end
    app.abyssIdentity = { text = Identity.Clean(app.state.abyssCallsign), runMode = runMode }
    if input and input.SetScreenKeyboardVisible then input:SetScreenKeyboardVisible(true) end
end

function Identity.Text(app, text)
    if not app.abyssIdentity then return false end
    app.abyssIdentity.text = Identity.Clean(app.abyssIdentity.text .. tostring(text or ""))
    return true
end

function Identity.Close(app, confirm)
    local dialog = app.abyssIdentity
    if not dialog then return end
    if confirm then
        local value = Identity.Clean(dialog.text)
        if value == "" then value = "无名矿工" end
        app.state.abyssCallsign = value
        app.state:Save()
    end
    app.abyssIdentity = nil
    if input and input.SetScreenKeyboardVisible then input:SetScreenKeyboardVisible(false) end
    if confirm then app:StartRun(false, true, dialog.runMode) end
end

function Identity.Key(app, key)
    local dialog = app.abyssIdentity
    if not dialog then return false end
    if key == KEY_BACKSPACE then
        local last = utf8.offset(dialog.text, -1)
        if last then dialog.text = dialog.text:sub(1, last - 1) end
    elseif key == KEY_RETURN then Identity.Close(app, true)
    elseif key == KEY_ESCAPE then Identity.Close(app, false) end
    return true
end

function Identity.Pointer(app, x, y)
    if not app.abyssIdentity then return false end
    if y >= 167 and y <= 194 then
        if x >= 94 and x <= 224 then Identity.Close(app, false)
        elseif x >= 254 and x <= 384 then Identity.Close(app, true) end
    elseif y >= 113 and y <= 142 and input and input.SetScreenKeyboardVisible then
        input:SetScreenKeyboardVisible(true)
    end
    return true
end

function Identity.Draw(renderer, app)
    local dialog = app.abyssIdentity
    if not dialog then return end
    renderer:FillRect(0, 0, 480, 270, { 0, 0, 0, 220 })
    renderer:DrawPanel(70, 70, 340, 139, "深渊矿工命名")
    renderer:FillRect(94, 113, 290, 29, Config.Palette.ink)
    renderer:StrokeRect(94, 113, 290, 29, Config.Palette.cyan, 1)
    renderer:Text(dialog.text .. "_", 103, 121, 11, Config.Palette.cream)
    renderer:Text("最多12字；个人代号，榜单仍显示TapTap昵称", 94, 149, 7, Config.Palette.creamDim)
    renderer:DrawButton("identity_cancel", "返回", 94, 167, 130, 27, true, false, {})
    renderer:DrawButton("identity_confirm", "确认下潜", 254, 167, 130, 27, true, false, {})
end

return Identity
