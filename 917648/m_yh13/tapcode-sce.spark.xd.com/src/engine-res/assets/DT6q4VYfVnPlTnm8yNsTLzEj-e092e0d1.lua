-- Basic Video Player Example
-- Demonstrates VideoPlayer UI component for WASM video playback

require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local Video = require("urhox-libs/Video")

-- Widget references
local videoPlayer = nil
local playPauseBtn = nil
local timeLabel = nil
local progressSlider = nil
local isUpdatingSlider = false  -- Flag to prevent Seek during programmatic slider update

function Start()
    SampleStart()

    -- Initialize UI system
    UI.Init({
        theme = "dark",
        fonts = {
            { name = "sans", path = "Fonts/MiSans-Regular.ttf" },
        },
        -- 推荐! DPR 缩放 + 小屏密度自适应（见 ui.md §10）
        -- 1 基准像素 ≈ 1 CSS 像素，尺寸遵循 CSS/Web 常识
        scale = UI.Scale.DEFAULT,
    })

    -- Check if video is supported
    if not Video.isSupported then
        print("[VideoExample] Video playback only supported on WASM platform")
    end

    -- Create UI
    CreateUI()

    -- Set mouse mode
    SampleInitMouseMode(MM_FREE)

    print("===========================================")
    print("  UrhoX Video Player Example")
    print("  (Video playback only works on WASM)")
    print("===========================================")
end

function CreateUI()
    -- Create VideoPlayer widget with UI overlays
    videoPlayer = Video.VideoPlayer {
        id = "videoPlayer",
        -- src: virtual path ("videos/intro.mp4"), uuid ("uuid://xxx"), or https URL
        src = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        width = "100%",
        flex = 1,
        textureWidth = 1280,
        textureHeight = 720,
        autoPlay = false,
        loop = false,
        muted = false,
        volume = 1.0,
        objectFit = "contain",
        backgroundColor = {0, 0, 0, 255},

        onReady = function(self)
            print("[VideoExample] Video ready")
        end,

        onPlay = function(self)
            print("[VideoExample] Playing")
            UpdatePlayPauseButton(true)
            -- Hide center play button when playing
            local centerBtn = self:FindById("centerPlayBtn")
            if centerBtn then centerBtn:SetVisible(false) end
        end,

        onPause = function(self)
            print("[VideoExample] Paused")
            UpdatePlayPauseButton(false)
            -- Show center play button when paused
            local centerBtn = self:FindById("centerPlayBtn")
            if centerBtn then centerBtn:SetVisible(true) end
        end,

        onEnded = function(self)
            print("[VideoExample] Ended")
            UpdatePlayPauseButton(false)
            local centerBtn = self:FindById("centerPlayBtn")
            if centerBtn then centerBtn:SetVisible(true) end
        end,

        onTimeUpdate = function(self, currentTime, duration)
            -- Update time label
            if timeLabel then
                timeLabel:SetText(FormatTime(currentTime) .. " / " .. FormatTime(duration))
            end
            -- Update progress slider (without triggering Seek)
            if progressSlider and duration > 0 then
                local newValue = currentTime / duration * 100
                if math.abs((progressSlider.props.value or 0) - newValue) > 1 then
                    isUpdatingSlider = true  -- Set flag to prevent Seek
                    progressSlider:SetValue(newValue)
                    isUpdatingSlider = false
                end
            end
        end,

        -- ============================================
        -- UI Overlays on top of video (for testing)
        -- ============================================

        -- Top bar overlay (title + info)
        UI.Panel {
            id = "topOverlay",
            position = "absolute",
            top = 0,
            left = 0,
            right = 0,
            height = 50,
            backgroundColor = {0, 0, 0, 150},
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingLeft = 16,
            paddingRight = 16,

            UI.Label {
                text = "Big Buck Bunny",
                fontSize = 18,
                fontColor = {255, 255, 255, 255},
            },

            UI.Row {
                gap = 12,
                alignItems = "center",

                UI.Label {
                    text = "HD",
                    fontSize = 12,
                    fontColor = {255, 255, 255, 200},
                    backgroundColor = {255, 100, 100, 200},
                    paddingLeft = 6,
                    paddingRight = 6,
                    paddingTop = 2,
                    paddingBottom = 2,
                    borderRadius = 4,
                },

                UI.Label {
                    text = "LIVE",
                    fontSize = 12,
                    fontColor = {255, 255, 255, 200},
                    backgroundColor = {200, 50, 50, 200},
                    paddingLeft = 6,
                    paddingRight = 6,
                    paddingTop = 2,
                    paddingBottom = 2,
                    borderRadius = 4,
                },
            },
        },

        -- Center play button (big circular button)
        UI.Panel {
            id = "centerPlayBtn",
            position = "absolute",
            top = "50%",
            left = "50%",
            width = 80,
            height = 80,
            marginTop = -40,
            marginLeft = -40,
            backgroundColor = {255, 255, 255, 180},
            borderRadius = 40,
            justifyContent = "center",
            alignItems = "center",

            onClick = function(self)
                TogglePlayPause()
            end,

            -- Play triangle icon (using a label with unicode)
            UI.Label {
                text = "\226\150\182",  -- UTF-8 for ▶
                fontSize = 36,
                fontColor = {0, 0, 0, 220},
                marginLeft = 6,  -- Offset to center the triangle visually
            },
        },

        -- Bottom left corner info
        UI.Panel {
            position = "absolute",
            bottom = 10,
            left = 10,
            backgroundColor = {0, 0, 0, 150},
            borderRadius = 6,
            padding = 8,
            flexDirection = "column",
            gap = 4,

            UI.Label {
                text = "Resolution: 1280x720",
                fontSize = 12,
                fontColor = {200, 200, 200, 255},
            },

            UI.Label {
                text = "Format: MP4/H.264",
                fontSize = 12,
                fontColor = {200, 200, 200, 255},
            },
        },

        -- Bottom right corner watermark
        UI.Panel {
            position = "absolute",
            bottom = 10,
            right = 10,
            backgroundColor = {0, 0, 0, 100},
            borderRadius = 4,
            paddingLeft = 8,
            paddingRight = 8,
            paddingTop = 4,
            paddingBottom = 4,

            UI.Label {
                text = "UrhoX Video",
                fontSize = 14,
                fontColor = {255, 255, 255, 180},
            },
        },
    }

    -- Create root with video player and controls
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = {20, 20, 20, 255},
        flexDirection = "column",

        -- Video player area
        videoPlayer or UI.Panel {
            flex = 1,
            backgroundColor = {0, 0, 0, 255},
            justifyContent = "center",
            alignItems = "center",

            UI.Label {
                text = "Video not supported\n(WASM only)",
                fontSize = 24,
                fontColor = {128, 128, 128, 255},
                textAlign = "center",
            },
        },

        -- Controls panel
        UI.Panel {
            id = "controls",
            width = "100%",
            height = 100,
            backgroundColor = {40, 40, 40, 255},
            flexDirection = "column",
            padding = 12,
            gap = 10,

            -- Progress bar row
            UI.Row {
                alignItems = "center",
                gap = 10,
                height = 30,

                UI.Label {
                    id = "timeLabel",
                    text = "00:00 / 00:00",
                    fontSize = 14,
                    fontColor = {200, 200, 200, 255},
                    width = 110,
                },

                UI.Slider {
                    id = "progressSlider",
                    flex = 1,
                    height = 24,
                    min = 0,
                    max = 100,
                    value = 0,
                    onChange = function(self, value)
                        -- Skip Seek if this is a programmatic update from onTimeUpdate
                        if isUpdatingSlider then return end
                        if videoPlayer then
                            local duration = videoPlayer:GetDuration()
                            if duration > 0 then
                                videoPlayer:Seek(value / 100 * duration)
                            end
                        end
                    end,
                },
            },

            -- Button row
            UI.Row {
                justifyContent = "center",
                alignItems = "center",
                gap = 16,
                flex = 1,

                UI.Button {
                    id = "playPauseBtn",
                    text = "Play",
                    variant = "primary",
                    width = 100,
                    onClick = function(self)
                        TogglePlayPause()
                    end,
                },

                UI.Button {
                    text = "Stop",
                    variant = "secondary",
                    width = 80,
                    onClick = function(self)
                        if videoPlayer then
                            videoPlayer:Stop()
                            UpdatePlayPauseButton(false)
                        end
                    end,
                },

                UI.Label {
                    text = "Vol:",
                    fontSize = 14,
                    fontColor = {200, 200, 200, 255},
                },

                UI.Slider {
                    id = "volumeSlider",
                    width = 80,
                    height = 24,
                    min = 0,
                    max = 100,
                    value = 100,
                    onChange = function(self, value)
                        if videoPlayer then
                            videoPlayer:SetVolume(value / 100)
                        end
                    end,
                },
            },
        },
    }

    -- Store references
    playPauseBtn = root:FindById("playPauseBtn")
    timeLabel = root:FindById("timeLabel")
    progressSlider = root:FindById("progressSlider")

    UI.SetRoot(root)
end

function TogglePlayPause()
    if not videoPlayer then return end

    if videoPlayer:IsPlaying() then
        videoPlayer:Pause()
    else
        videoPlayer:Play()
    end
end

function UpdatePlayPauseButton(isPlaying)
    if playPauseBtn then
        playPauseBtn:SetText(isPlaying and "Pause" or "Play")
    end
end

function FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

function Stop()
    UI.Shutdown()
end
