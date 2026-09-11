-- Video Player with NanoVG
-- A minimal example showing video playback using VideoPlayer + NanoVG
-- Video playback only works on WASM platform
--
-- Controls:
--   Space: Play/Pause
--   R: Restart
--   Left/Right: Seek -5s/+5s

require "LuaScripts/Utilities/Sample"

local nvgContext = nil
local fontId = -1
local videoPlayer = nil
local nvgImageHandle = nil

-- Video source supports: virtual path ("videos/intro.mp4"), uuid ("uuid://xxx"), or https URL
local VIDEO_URL = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

function Start()
    SampleStart()

    -- Create NanoVG context
    nvgContext = nvgCreate(1)
    if nvgContext == nil then
        print("[VideoNanoVG] ERROR: Failed to create NanoVG context")
        return
    end

    -- Create font
    fontId = nvgCreateFont(nvgContext, "sans", "Fonts/MiSans-Regular.ttf")

    -- Create VideoPlayer
    videoPlayer = VideoPlayer:new()
    if videoPlayer then
        local success = videoPlayer:Load(VIDEO_URL, 1280, 720)
        if success then
            print("[VideoNanoVG] Video loading: " .. VIDEO_URL)
            videoPlayer:SetVolume(1.0)
            videoPlayer:SetLoop(false)
        else
            print("[VideoNanoVG] Failed to load video (expected on non-WASM)")
        end
    else
        print("[VideoNanoVG] VideoPlayer not available (WASM only)")
    end

    -- Set mouse mode
    SampleInitMouseMode(MM_FREE)

    -- Subscribe to events
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvgContext, "NanoVGRender", "HandleRender")

    print("==========================================")
    print("  Video Player + NanoVG Example")
    print("  Space: Play/Pause | R: Restart")
    print("  Left/Right: Seek -5s/+5s")
    print("  (Video only works on WASM)")
    print("==========================================")
end

function Stop()
    if videoPlayer then
        videoPlayer:Stop()
        videoPlayer = nil
    end
    nvgImageHandle = nil

    if nvgContext then
        nvgDelete(nvgContext)
        nvgContext = nil
    end
end

function HandleUpdate(eventType, eventData)
    -- Update video texture
    if videoPlayer then
        videoPlayer:Update()
    end

    -- Handle input
    if input:GetKeyPress(KEY_SPACE) then
        TogglePlayPause()
    elseif input:GetKeyPress(KEY_R) then
        Restart()
    elseif input:GetKeyPress(KEY_LEFT) then
        Seek(-5)
    elseif input:GetKeyPress(KEY_RIGHT) then
        Seek(5)
    end
end

function TogglePlayPause()
    if not videoPlayer then return end
    if videoPlayer:IsPlaying() then
        videoPlayer:Pause()
        print("[VideoNanoVG] Paused")
    else
        videoPlayer:Play()
        print("[VideoNanoVG] Playing")
    end
end

function Restart()
    if not videoPlayer then return end
    videoPlayer:Seek(0)
    videoPlayer:Play()
    print("[VideoNanoVG] Restarted")
end

function Seek(delta)
    if not videoPlayer then return end
    local newTime = math.max(0, videoPlayer:GetCurrentTime() + delta)
    videoPlayer:Seek(newTime)
end

function HandleRender(eventType, eventData)
    if nvgContext == nil then return end

    local graphics = GetGraphics()
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()

    nvgBeginFrame(nvgContext, screenW, screenH, 1.0)

    -- Draw background
    nvgBeginPath(nvgContext)
    nvgRect(nvgContext, 0, 0, screenW, screenH)
    nvgFillColor(nvgContext, nvgRGBA(20, 20, 30, 255))
    nvgFill(nvgContext)

    -- Draw video
    if videoPlayer and videoPlayer:IsReady() then
        local texture = videoPlayer:GetTexture()
        if texture then
            -- Create NanoVG image handle (once)
            if not nvgImageHandle and nvgCreateVideo then
                nvgImageHandle = nvgCreateVideo(nvgContext, texture)
            end

            if nvgImageHandle and nvgImageHandle > 0 then
                local videoW = videoPlayer:GetVideoWidth()
                local videoH = videoPlayer:GetVideoHeight()

                -- Calculate aspect-fit rectangle
                local drawX, drawY, drawW, drawH = CalculateAspectFit(
                    0, 60, screenW, screenH - 120,
                    videoW, videoH
                )

                -- Draw video frame
                local imgPaint = nvgImagePattern(nvgContext, drawX, drawY, drawW, drawH, 0, nvgImageHandle, 1)
                nvgBeginPath(nvgContext)
                nvgRect(nvgContext, drawX, drawY, drawW, drawH)
                nvgFillPaint(nvgContext, imgPaint)
                nvgFill(nvgContext)
            end
        end
    else
        -- Show "Loading..." or "Not supported" message
        nvgFontFace(nvgContext, "sans")
        nvgFontSize(nvgContext, 24)
        nvgFillColor(nvgContext, nvgRGBA(150, 150, 150, 255))
        nvgTextAlign(nvgContext, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        local msg = videoPlayer and "Loading video..." or "Video not supported (WASM only)"
        nvgText(nvgContext, screenW / 2, screenH / 2, msg, nil)
    end

    -- Draw top bar
    DrawTopBar(nvgContext, screenW)

    -- Draw bottom controls
    DrawBottomBar(nvgContext, screenW, screenH)

    nvgEndFrame(nvgContext)
end

function DrawTopBar(ctx, screenW)
    -- Background
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, screenW, 50)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
    nvgFill(ctx)

    -- Title
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 20)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(ctx, 16, 25, "Big Buck Bunny - NanoVG Video Player", nil)
end

function DrawBottomBar(ctx, screenW, screenH)
    local barY = screenH - 60
    local barH = 60

    -- Background
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, barY, screenW, barH)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
    nvgFill(ctx)

    if not videoPlayer then return end

    local currentTime = videoPlayer:GetCurrentTime()
    local duration = videoPlayer:GetDuration()
    local isPlaying = videoPlayer:IsPlaying()

    -- Progress bar background
    local progressX = 120
    local progressW = screenW - 240
    local progressY = barY + 20
    local progressH = 8

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, progressX, progressY, progressW, progressH, 4)
    nvgFillColor(ctx, nvgRGBA(60, 60, 60, 255))
    nvgFill(ctx)

    -- Progress bar fill
    if duration > 0 then
        local progress = currentTime / duration
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, progressX, progressY, progressW * progress, progressH, 4)
        nvgFillColor(ctx, nvgRGBA(100, 150, 255, 255))
        nvgFill(ctx)
    end

    -- Play/Pause indicator
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 16)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local stateText = isPlaying and "[Playing]" or "[Paused]"
    nvgText(ctx, 16, barY + 30, stateText, nil)

    -- Time display
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local timeText = FormatTime(currentTime) .. " / " .. FormatTime(duration)
    nvgText(ctx, screenW / 2, barY + 45, timeText, nil)

    -- Controls hint
    nvgFontSize(ctx, 12)
    nvgFillColor(ctx, nvgRGBA(180, 180, 180, 255))
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(ctx, screenW - 16, barY + 45, "Space: Play/Pause | R: Restart | Left/Right: Seek", nil)
end

function CalculateAspectFit(containerX, containerY, containerW, containerH, videoW, videoH)
    if videoW <= 0 or videoH <= 0 then
        return containerX, containerY, containerW, containerH
    end

    local containerRatio = containerW / containerH
    local videoRatio = videoW / videoH

    local drawW, drawH
    if videoRatio > containerRatio then
        drawW = containerW
        drawH = containerW / videoRatio
    else
        drawH = containerH
        drawW = containerH * videoRatio
    end

    local drawX = containerX + (containerW - drawW) / 2
    local drawY = containerY + (containerH - drawH) / 2

    return drawX, drawY, drawW, drawH
end

function FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end
