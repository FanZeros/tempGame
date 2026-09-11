local UI = require("urhox-libs/UI")

local SettingsPage = {}

local WHITE = { 241, 236, 220, 255 }
local MUTED = { 172, 157, 172, 255 }
local GOLD = { 226, 161, 40, 255 }
local TRANSPARENT = { 0, 0, 0, 0 }
local TEAL = { 33, 189, 174, 255 }
local TEAL_DARK = { 27, 176, 161, 255 }
local GRAY_BUTTON = "image/nightgate/ui/1_gray_button_s.png"
local ORANGE_BUTTON = "image/nightgate/ui/1_orange_button_s.png"

function SettingsPage.SetVolume(app, kind, percent)
    percent = math.max(0, math.min(100, math.floor(tonumber(percent) or 0)))
    local value = percent / 100
    if kind == "music" then
        app.battle:SetMusicVolume(value)
        if app.audioManager then app.audioManager:SetMusicVolume(value) end
        if app.settingsMusicValue then app.settingsMusicValue:SetText(tostring(percent) .. "%") end
    else
        app.battle:SetSfxVolume(value)
        if app.audioManager then app.audioManager:SetSfxVolume(value) end
        if app.settingsSfxValue then app.settingsSfxValue:SetText(tostring(percent) .. "%") end
    end
end

function SettingsPage.Refresh(app)
    if not app.settingsMusicSlider then return end
    local musicPercent = math.floor(app.battle:GetMusicVolume() * 100 + 0.5)
    local sfxPercent = math.floor(app.battle:GetSfxVolume() * 100 + 0.5)
    app.settingsMusicSlider:SetValue(musicPercent)
    app.settingsSfxSlider:SetValue(sfxPercent)
    app.settingsMusicValue:SetText(tostring(musicPercent) .. "%")
    app.settingsSfxValue:SetText(tostring(sfxPercent) .. "%")
end

function SettingsPage.Open(app)
    SettingsPage.Refresh(app)
    app.settingsModal:SetVisible(true)
end

function SettingsPage.Close(app)
    if app.settingsModal then app.settingsModal:SetVisible(false) end
end

function SettingsPage.Build(app)
    local p = function(v) return app:P(v) end
    app.settingsMusicValue = UI.Label {
        text = "100%", position = "absolute", left = p(475), top = p(112), width = p(130), height = p(45),
        fontSize = p(27), fontWeight = "bold", fontColor = GOLD, textAlign = "right",
    }
    app.settingsSfxValue = UI.Label {
        text = "100%", position = "absolute", left = p(475), top = p(245), width = p(130), height = p(45),
        fontSize = p(27), fontWeight = "bold", fontColor = GOLD, textAlign = "right",
    }
    app.settingsMusicSlider = UI.Slider {
        value = 100, min = 0, max = 100, step = 1,
        position = "absolute", left = p(70), top = p(160), width = p(540), height = p(65),
        trackHeight = p(14), thumbSize = p(46), trackBgColor = { 27, 27, 58, 255 },
        trackFillColor = TEAL, thumbColor = TEAL, thumbBorderWidth = p(2), thumbBorderColor = TEAL_DARK,
        onChange = function(_, value) SettingsPage.SetVolume(app, "music", value) end,
    }
    app.settingsSfxSlider = UI.Slider {
        value = 100, min = 0, max = 100, step = 1,
        position = "absolute", left = p(70), top = p(293), width = p(540), height = p(65),
        trackHeight = p(14), thumbSize = p(46), trackBgColor = { 27, 27, 58, 255 },
        trackFillColor = TEAL, thumbColor = TEAL, thumbBorderWidth = p(2), thumbBorderColor = TEAL_DARK,
        onChange = function(_, value) SettingsPage.SetVolume(app, "sfx", value) end,
        onChangeEnd = function()
            if app.audioManager then app.audioManager:Play("upgrade") end
        end,
    }
    app.settingsModal = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080),
        backgroundColor = { 0, 0, 0, 215 },
        children = {
            UI.Panel {
                position = "absolute", left = p(620), top = p(270), width = p(680), height = p(540),
                backgroundImage = "image/nightgate/ui/popup_window.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT,
                children = {
                    UI.Label { text = "声音设置", position = "absolute", left = p(115), top = p(42), width = p(450), height = p(58), fontSize = p(38), fontWeight = "bold", fontColor = WHITE, textAlign = "center" },
                    UI.Label { text = "音乐音量", position = "absolute", left = p(70), top = p(112), width = p(260), height = p(45), fontSize = p(28), fontWeight = "bold", fontColor = WHITE },
                    app.settingsMusicValue, app.settingsMusicSlider,
                    UI.Label { text = "音效音量", position = "absolute", left = p(70), top = p(245), width = p(260), height = p(45), fontSize = p(28), fontWeight = "bold", fontColor = WHITE },
                    app.settingsSfxValue, app.settingsSfxSlider,
                    UI.Label { text = "拖动滑块即可试听，设置会自动保存", position = "absolute", left = p(95), top = p(365), width = p(490), height = p(40), fontSize = p(21), fontColor = MUTED, textAlign = "center" },
                    app:ImageButton("关闭", 105, 430, 215, 70, GRAY_BUTTON, function() SettingsPage.Close(app) end),
                    app:ImageButton("恢复默认", 360, 430, 215, 70, ORANGE_BUTTON, function()
                        app.settingsMusicSlider:SetValue(100)
                        app.settingsSfxSlider:SetValue(100)
                        if app.audioManager then app.audioManager:Play("upgrade") end
                    end),
                },
            },
        },
    }
    SettingsPage.Refresh(app)
    return app.settingsModal
end

return SettingsPage
