local Audio = {}
Audio.__index = Audio

local BASE_MUSIC_GAIN = 0.34
local BASE_SFX_GAIN = 0.62

local function normalizeVolume(value)
    return math.max(0, math.min(1, tonumber(value) or 1))
end

local PATHS = {
    bow = "audio/nightgate/bow.wav",
    hit = "audio/nightgate/bullet_impact_body_flesh_05.wav",
    kill = "audio/nightgate/exp.wav",
    coin = "audio/nightgate/coin.wav",
    wall_hit = "audio/nightgate/sword.wav",
    cast_volley = "audio/nightgate/tower_1.wav",
    cast_frost = "audio/nightgate/tower_20_ice.wav",
    cast_ward = "audio/nightgate/ability.wav",
    upgrade = "audio/nightgate/upgradesuccess.wav",
    deny = "audio/nightgate/clickybutton5b.wav",
    wave = "audio/nightgate/exp.wav",
    win = "audio/nightgate/win.wav",
    defeat = "audio/nightgate/defeat.wav",
}

local MUSIC_PATHS = {
    home = "audio/nightgate/02-home_town_orchestral.wav",
    battle = "audio/nightgate/04_mountaingstrongholdbattle_orchestral.wav",
}

local MIN_INTERVAL = {
    bow = 0.08,
    hit = 0.06,
    kill = 0.08,
    coin = 0.05,
    wall_hit = 0.12,
}

function Audio.New(settings)
    local self = setmetatable({}, Audio)
    settings = type(settings) == "table" and settings or {}
    self.musicVolume = normalizeVolume(settings.musicVolume)
    self.sfxVolume = normalizeVolume(settings.sfxVolume)
    self.scene = Scene()
    self.root = self.scene:CreateChild("NightgateAudio")
    self.sources = {}
    self.sourceIndex = 0
    self.cooldowns = {}
    self.sounds = {}
    self.music = {}
    self.currentMusic = nil
    local musicNode = self.root:CreateChild("Music")
    self.musicSource = musicNode:CreateComponent("SoundSource")
    self.musicSource.soundType = SOUND_MUSIC
    self.musicSource.gain = BASE_MUSIC_GAIN * self.musicVolume
    for index = 1, 10 do
        local node = self.root:CreateChild("Sfx" .. tostring(index))
        local source = node:CreateComponent("SoundSource")
        source.soundType = SOUND_EFFECT
        source.gain = BASE_SFX_GAIN * self.sfxVolume
        self.sources[index] = source
    end
    for id, path in pairs(PATHS) do
        self.sounds[id] = cache:GetResource("Sound", path)
    end
    for id, path in pairs(MUSIC_PATHS) do
        local sound = cache:GetResource("Sound", path)
        if sound then sound.looped = true end
        self.music[id] = sound
    end
    return self
end

function Audio:SetMusicVolume(value)
    self.musicVolume = normalizeVolume(value)
    self.musicSource.gain = BASE_MUSIC_GAIN * self.musicVolume
end

function Audio:GetMusicVolume()
    return self.musicVolume
end

function Audio:SetSfxVolume(value)
    self.sfxVolume = normalizeVolume(value)
    for index = 1, #self.sources do
        self.sources[index].gain = BASE_SFX_GAIN * self.sfxVolume
    end
end

function Audio:GetSfxVolume()
    return self.sfxVolume
end

function Audio:SetMusic(id)
    if self.currentMusic == id then return end
    local sound = self.music[id]
    if not sound then return end
    self.musicSource:Stop()
    self.musicSource:Play(sound)
    self.currentMusic = id
end

function Audio:Update(dt)
    for id, value in pairs(self.cooldowns) do
        self.cooldowns[id] = math.max(0, value - dt)
    end
end

function Audio:Play(id)
    local sound = self.sounds[id]
    if not sound or (self.cooldowns[id] or 0) > 0 then
        return
    end
    self.cooldowns[id] = MIN_INTERVAL[id] or 0.02
    self.sourceIndex = self.sourceIndex % #self.sources + 1
    self.sources[self.sourceIndex]:Play(sound)
end

return Audio
