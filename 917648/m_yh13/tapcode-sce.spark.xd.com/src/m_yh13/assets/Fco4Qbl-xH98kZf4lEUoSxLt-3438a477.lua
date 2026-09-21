local Config = require("diggin.Config")

local AudioManager = {}
AudioManager.__index = AudioManager

function AudioManager.New(scene, state)
    local self = setmetatable({}, AudioManager)
    self.state = state
    self.node = scene:CreateChild("DigginAudio")
    self.musicSource = self.node:CreateComponent("SoundSource")
    self.drillSource = self.node:CreateComponent("SoundSource")
    self.sfxSources = {}
    for _ = 1, 8 do
        self.sfxSources[#self.sfxSources + 1] = self.node:CreateComponent("SoundSource")
    end
    self.nextSfx = 1
    self.currentMusic = nil
    self.drillingActive = false
    return self
end

function AudioManager:GetSound(path, looped)
    local sound = cache:GetResource("Sound", path)
    if sound then sound.looped = looped == true end
    return sound
end

function AudioManager:ApplyMute()
    local gain = self.state.muted and 0 or 1
    self.musicSource.gain = gain * 0.42
    local drillGain = self.state.drillSoundEnabled == false and 0 or gain
    self.drillSource.gain = drillGain * 0.35
    for _, source in ipairs(self.sfxSources) do source.gain = gain * 0.7 end
end

function AudioManager:PlayMusic(path)
    if self.currentMusic == path and self.musicSource.playing then return end
    self.currentMusic = path
    self.musicSource:Stop()
    local sound = self:GetSound(path, true)
    if sound then self.musicSource:Play(sound) end
    self:ApplyMute()
end

function AudioManager:PlayGameplayMusic(layerIndex)
    local index = math.max(1, math.min(#Config.Audio.gameplay, layerIndex or 1))
    self:PlayMusic(Config.Audio.gameplay[index])
end

function AudioManager:SetDrilling(active)
    self.drillingActive = active == true
    local shouldPlay = self.drillingActive and self.state.drillSoundEnabled ~= false
    if shouldPlay and not self.drillSource.playing then
        local sound = self:GetSound(Config.Audio.drill, true)
        if sound then self.drillSource:Play(sound) end
    elseif not shouldPlay and self.drillSource.playing then
        self.drillSource:Stop()
    end
    self:ApplyMute()
end

function AudioManager:PlaySfx(path, gain, pitch)
    if self.state.muted then return end
    local sound = self:GetSound(path, false)
    if not sound then return end
    local source = self.sfxSources[self.nextSfx]
    self.nextSfx = self.nextSfx % #self.sfxSources + 1
    source:Play(sound)
    source.gain = gain or 0.7
    if pitch then source.frequency = sound.frequency * pitch end
end

function AudioManager:PlayDrillSfx(path, gain, pitch)
    if self.state.drillSoundEnabled == false then return end
    self:PlaySfx(path, gain, pitch)
end

function AudioManager:ToggleMute()
    self.state.muted = not self.state.muted
    self.state:Save()
    self:ApplyMute()
end

function AudioManager:ToggleDrillSound()
    self.state.drillSoundEnabled = self.state.drillSoundEnabled == false
    self.state:Save()
    self:SetDrilling(self.drillingActive)
end

return AudioManager
