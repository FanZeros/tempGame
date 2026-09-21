-- ============================================================================
-- VideoPlayer Widget
-- UrhoX Video Library - WASM Video Playback
-- ============================================================================
--
-- A widget for playing videos in WASM builds.
-- Uses HTML5 video element for decoding and WebGL texture for rendering.
--
-- Usage:
--   local Video = require("urhox-libs/Video")
--   local player = Video.VideoPlayer {
--       src = "https://example.com/video.mp4",
--       width = "100%",
--       height = 400,
--       autoPlay = false,
--       loop = false,
--       muted = false,
--       volume = 1.0,
--       onPlay = function(self) print("Playing") end,
--       onPause = function(self) print("Paused") end,
--       onEnded = function(self) print("Ended") end,
--       onTimeUpdate = function(self, time, duration) end,
--   }
--
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local UI = require("urhox-libs/UI/Core/UI")
local Theme = require("urhox-libs/UI/Core/Theme")

-- ============================================================================
-- Orphan detection: tracks all VideoPlayer instances via weak references.
-- Warns when a VideoPlayer is detached from the UI tree without Destroy().
-- ============================================================================

local ORPHAN_WARN_SECONDS = 5

-- Weak-key table: { [widget] = state }
-- state: false = in tree, number = seconds orphaned, true = already warned
local tracked_ = setmetatable({}, { __mode = "k" })

--- Check if a widget is attached to the UI root
local function isInUITree(widget)
    local w = widget
    while w.parent do
        w = w.parent
    end
    return w == UI.GetRoot()
end

-- Global component registered once; Update is called every frame by UI system.
local orphanWatcher_ = {}

function orphanWatcher_:Update(dt)
    local root = UI.GetRoot()
    if not root then return end

    -- Modify existing keys only — safe during pairs()
    for widget, state in pairs(tracked_) do
        if state == true then
            -- Already warned; check if re-inserted into tree
            if isInUITree(widget) then
                tracked_[widget] = false
            end
        elseif isInUITree(widget) then
            -- In tree — reset timer
            if state ~= false then
                tracked_[widget] = false
            end
        else
            -- Orphaned — accumulate timer
            local timer = (state == false) and 0 or (state + dt)
            if timer >= ORPHAN_WARN_SECONDS then
                local id = (widget.props and widget.props.id) or "?"
                log:Write(LOG_ERROR, "[VideoPlayer] VideoPlayer (id=\"" .. id .. "\") has been "
                    .. "detached from the UI tree for " .. ORPHAN_WARN_SECONDS .. "s "
                    .. "without Destroy() being called. The widget will eventually be "
                    .. "cleaned up by GC, but GC timing is unpredictable and may cause "
                    .. "temporary GPU memory buildup (video textures are large). "
                    .. "Best practice: call widget:Destroy() before or after removing "
                    .. "video widgets from the tree, e.g. videoPlayer:Destroy() before "
                    .. "parent:ClearChildren(), or on the removed subtree afterwards.")
                tracked_[widget] = true  -- stop repeated warnings
            else
                tracked_[widget] = timer
            end
        end
    end
end

---@class VideoPlayerProps : WidgetProps
---@field src? string Video source URL (alias: source)
---@field source? string Alias for src
---@field autoPlay? boolean Auto play on load (default: false)
---@field loop? boolean Loop playback (default: false)
---@field muted? boolean Muted state (default: false)
---@field volume? number Volume 0-1 (default: 1.0)
---@field textureWidth? number Initial texture width (default: 1920)
---@field textureHeight? number Initial texture height (default: 1080)
---@field objectFit? string "contain", "cover", or "fill" (default: "contain")
---@field backgroundColor? table Background color {r, g, b, a}
---@field onPlay? fun(self: VideoPlayerWidget) Callback when play starts
---@field onPause? fun(self: VideoPlayerWidget) Callback when paused
---@field onEnded? fun(self: VideoPlayerWidget) Callback when video ends
---@field onTimeUpdate? fun(self: VideoPlayerWidget, time: number, duration: number) Time update callback
---@field onReady? fun(self: VideoPlayerWidget) Callback when video is ready
---@field playbackRate? number Playback rate 0.25-4.0 (default: 1.0). Audio pitch changes with rate.
---@field onLoadError? fun(self: VideoPlayerWidget, errorCode: number, errorName: string) Callback when async load fails

---@class VideoPlayerWidget : Widget
---@overload fun(props?: VideoPlayerProps): VideoPlayerWidget
---@field props VideoPlayerProps
---@field new fun(self, props?: VideoPlayerProps): VideoPlayerWidget
local VideoPlayerWidget = Widget:Extend("VideoPlayer")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props VideoPlayerProps?
function VideoPlayerWidget:Init(props)
    props = props or {}

    -- Alias: source → src
    if props.source and not props.src then
        props.src = props.source
    end

    -- Default properties
    props.textureWidth = props.textureWidth or 1920
    props.textureHeight = props.textureHeight or 1080
    props.autoPlay = props.autoPlay or false
    props.loop = props.loop or false
    props.muted = props.muted or false
    props.volume = props.volume or 1.0
    props.playbackRate = props.playbackRate or 1.0
    props.objectFit = props.objectFit or "contain"
    props.backgroundColor = props.backgroundColor or {0, 0, 0, 255}

    -- Default size: if no explicit height/flex/aspectRatio, use 16:9 aspect ratio
    -- so the widget adapts to parent width instead of a fixed 400px height.
    -- This avoids conflicts with absolute positioning + inset constraints.
    if not props.height and not props.flex and not props.aspectRatio then
        props.aspectRatio = 16 / 9
        if not props.width then
            props.width = "100%"
        end
    end

    -- Initialize state
    self.state = {
        ready = false,
        playing = false,
        currentTime = 0,
        duration = 0,
        wasPlaying = false,
    }

    -- C++ VideoPlayer instance (lazily created in LoadVideo)
    self.player_ = nil
    self.nvgImageHandle_ = nil
    self.lastTimeUpdate_ = 0

    -- Load video if src is provided
    if props.src then
        self:LoadVideo(props.src)
    end

    -- Register for orphan detection (weak ref, won't prevent GC)
    tracked_[self] = false
    -- Ensure watcher is registered (idempotent)
    UI.RegisterGlobalComponent("VideoPlayerOrphanWatcher", orphanWatcher_)

    Widget.Init(self, props)
end

---Set video source property (triggers LoadVideo)
---@param src string Video source URL
function VideoPlayerWidget:SetSrc(src)
    self.props.src = src
    self:LoadVideo(src)
end

---Alias: widget.source = "url" also works
VideoPlayerWidget.SetSource = VideoPlayerWidget.SetSrc

---Override SetStyle to detect src changes (SetStyle bypasses setters)
---@param style table
function VideoPlayerWidget:SetStyle(style)
    local newSrc = style.src or style.source
    Widget.SetStyle(self, style)
    if newSrc and newSrc ~= "" then
        self:LoadVideo(newSrc)
    end
end

--- Release video-specific resources (NanoVG handle + C++ player).
--- Called from both Destroy() and __gc. Safe to call multiple times.
function VideoPlayerWidget:ReleaseVideoResources()
    -- Delete NanoVG video image BEFORE destroying the video player,
    -- so NanoVG releases its reference to the texture first.
    if self.nvgImageHandle_ then
        local nvg = UI.GetNVGContext and UI.GetNVGContext()
        if nvg and nvgDeleteVideo then
            nvgDeleteVideo(nvg, self.nvgImageHandle_)
        end
        self.nvgImageHandle_ = nil
    end

    -- Dispose C++ player immediately — calls destructor and clears the
    -- userdata so GC won't double-free. Frees video texture + decoder at once.
    if self.player_ then
        if self.player_.Dispose then
            self.player_:Dispose()
        end
        self.player_ = nil
    end
end

--- GC safety net: ensure resources are released if Destroy was never called.
function VideoPlayerWidget:__gc()
    self:ReleaseVideoResources()
end

--- Destroy widget and release resources
function VideoPlayerWidget:Destroy()
    -- Guard against double-destroy (explicit Destroy + __gc)
    if self.destroyed_ then return end
    self.destroyed_ = true

    -- Unregister from orphan detection
    tracked_[self] = nil

    self:ReleaseVideoResources()

    Widget.Destroy(self)
end

-- ============================================================================
-- Video Control Methods
-- ============================================================================

--- VideoLoadResult error code to name mapping.
local VIDEO_LOAD_RESULT_NAMES = {
    [0] = "SUCCESS",
    [1] = "ERROR_NO_DECODER",
    [2] = "ERROR_SOURCE_NOT_FOUND",
    [3] = "ERROR_OPEN_FAILED",
    [4] = "ERROR_TEXTURE_FAILED",
    [5] = "ERROR_CANCELLED",
}

---Load video from URL (async with completion callback)
---@param src string Video source URL
---@return boolean success Whether async load was started
function VideoPlayerWidget:LoadVideo(src)
    -- Lazily recreate C++ player if it was destroyed (e.g. orphan cleanup)
    if not self.player_ and VideoPlayer then
        self.player_ = VideoPlayer:new()
    end
    if not self.player_ then
        print("[VideoPlayer] Player not initialized")
        return false
    end

    local width = self.props.textureWidth
    local height = self.props.textureHeight

    -- Apply settings before async load (values are stored in member variables,
    -- FinalizeLoad will use them when creating audio source)
    self.player_:SetVolume(self.props.volume)
    self.player_:SetMuted(self.props.muted)
    self.player_:SetLoop(self.props.loop)
    self.player_:SetPlaybackRate(self.props.playbackRate)

    -- Release old NanoVG image handle if we recreated the player (new texture pointer).
    -- For same player, nvgCreateVideo is idempotent (same texture key), but after
    -- lazy recreation the old handle references a destroyed texture.
    if self.nvgImageHandle_ then
        local nvg = UI.GetNVGContext and UI.GetNVGContext()
        if nvg and nvgDeleteVideo then
            nvgDeleteVideo(nvg, self.nvgImageHandle_)
        end
        self.nvgImageHandle_ = nil
    end

    -- Async load video with callback (non-blocking)
    local success = self.player_:AsyncLoad(src, width, height, function(resultCode)
        local resultName = VIDEO_LOAD_RESULT_NAMES[resultCode] or ("UNKNOWN_" .. resultCode)

        if resultCode == 0 then
            print("[VideoPlayer] Async load succeeded: " .. src)
        else
            print("[VideoPlayer] Async load failed: " .. src
                .. " (error " .. resultCode .. ": " .. resultName .. ")")

            -- Decoder unavailable is a platform limitation, show fallback UI
            if resultCode == 1 then  -- ERROR_NO_DECODER
                self:SetState({ decoderUnavailable = true })
            end

            if self.props.onLoadError then
                self.props.onLoadError(self, resultCode, resultName)
            end
        end
    end)

    if success then
        self:SetState({ ready = false })

        -- Auto play if requested (pendingPlay_ will defer until load completes)
        if self.props.autoPlay then
            self.player_:Play()
        end
    end

    return success
end

---Play video
function VideoPlayerWidget:Play()
    if self.player_ then
        self.player_:Play()
        self:SetState({ playing = true })

        if self.props.onPlay then
            self.props.onPlay(self)
        end
    end
end

---Pause video
function VideoPlayerWidget:Pause()
    if self.player_ then
        self.player_:Pause()
        self:SetState({ playing = false })

        if self.props.onPause then
            self.props.onPause(self)
        end
    end
end

---Stop video
function VideoPlayerWidget:Stop()
    if self.player_ then
        self.player_:Stop()
        self:SetState({ playing = false, currentTime = 0 })
    end
end

---Seek to time
---@param time number Time in seconds
function VideoPlayerWidget:Seek(time)
    if self.player_ then
        self.player_:Seek(time)
        -- 强制下次 Update 触发 onTimeUpdate：seek 后若新旧时间差 < 0.1s 的节流阈值，
        -- onTimeUpdate 不会触发，导致 seekFadeInTarget 检查不执行、loading 永不解除。
        self.lastTimeUpdate_ = -1
    end
end

---Set volume
---@param volume number Volume 0-1
function VideoPlayerWidget:SetVolume(volume)
    self.props.volume = volume
    if self.player_ then
        self.player_:SetVolume(volume)
    end
end

---Set muted state
---@param muted boolean
function VideoPlayerWidget:SetMuted(muted)
    self.props.muted = muted
    if self.player_ then
        self.player_:SetMuted(muted)
    end
end

---Check if muted
---@return boolean
function VideoPlayerWidget:IsMuted()
    if self.player_ then
        return self.player_:IsMuted()
    end
    return self.props.muted or false
end

---Set playback rate (0.25 to 4.0, default 1.0). Audio pitch changes with rate.
---@param rate number
function VideoPlayerWidget:SetPlaybackRate(rate)
    self.props.playbackRate = rate
    if self.player_ then
        self.player_:SetPlaybackRate(rate)
    end
end

---Get current playback rate
---@return number rate
function VideoPlayerWidget:GetPlaybackRate()
    if self.player_ then
        return self.player_:GetPlaybackRate()
    end
    return self.props.playbackRate or 1.0
end

---Get current playback time
---@return number time Time in seconds
function VideoPlayerWidget:GetCurrentTime()
    if self.player_ then
        return self.player_:GetCurrentTime()
    end
    return 0
end

---Get video duration
---@return number duration Duration in seconds
function VideoPlayerWidget:GetDuration()
    if self.player_ then
        return self.player_:GetDuration()
    end
    return 0
end

---Check if video is playing
---@return boolean
function VideoPlayerWidget:IsPlaying()
    if self.player_ then
        return self.player_:IsPlaying()
    end
    return false
end

---Check if video is ready
---@return boolean
function VideoPlayerWidget:IsReady()
    if self.player_ then
        return self.player_:IsReady()
    end
    return false
end

-- ============================================================================
-- Update
-- ============================================================================

function VideoPlayerWidget:Update(dt)
    if not self.player_ then return end

    -- Always call Update for async load state and WebGL texture setup,
    -- but C++ side skips texSubImage2D when video is not playing (see VideoPlayer.cpp).
    -- The <video> element continues preloading (network buffering) regardless.
    self.player_:Update()

    -- Sync ready state with C++ player (handles both load-ready and source-released)
    local isReady = self.player_:IsReady()
    if isReady ~= self.state.ready then
        self:SetState({ ready = isReady })
        if isReady and self.props.onReady then
            self.props.onReady(self)
        end
    end

    -- Check playback state
    local nowPlaying = self.player_ and self.player_:IsPlaying() or false
    if nowPlaying ~= self.state.playing then
        self:SetState({ playing = nowPlaying })
    end

    -- Check for ended state (onEnded callback may destroy player_)
    if self.player_ then
        local state = self.player_:GetState()
        if state == VIDEO_ENDED and self.state.wasPlaying then
            self:SetState({ wasPlaying = false })
            if self.props.onEnded then
                self.props.onEnded(self)
            end
        end
    end

    if nowPlaying then
        self.state.wasPlaying = true
    end

    -- Time update callback (throttled to ~10 updates per second)
    if self.player_ and self.props.onTimeUpdate then
        local currentTime = self.player_:GetCurrentTime()
        if math.abs(currentTime - self.lastTimeUpdate_) > 0.1 then
            self.lastTimeUpdate_ = currentTime
            local duration = self.player_:GetDuration()
            self:SetState({ currentTime = currentTime, duration = duration })
            self.props.onTimeUpdate(self, currentTime, duration)
        end
    end
end

-- ============================================================================
-- Rendering
-- ============================================================================

function VideoPlayerWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props

    -- Draw background
    if props.backgroundColor then
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, l.h)
        nvgFillColor(nvg, nvgRGBA(
            props.backgroundColor[1],
            props.backgroundColor[2],
            props.backgroundColor[3],
            props.backgroundColor[4] or 255
        ))
        nvgFill(nvg)
    end

    -- Draw video texture
    if self.player_ and self.state.ready then
        local texture = self.player_:GetTexture()
        if texture then
            -- Get or create NanoVG image handle
            local imgHandle = self:GetOrCreateNvgImage(nvg, texture)
            if imgHandle and imgHandle > 0 then
                -- Get video dimensions
                local videoW = self.player_:GetVideoWidth()
                local videoH = self.player_:GetVideoHeight()

                if videoW > 0 and videoH > 0 then
                    -- Calculate draw rectangle based on objectFit
                    local drawX, drawY, drawW, drawH = self:CalculateDrawRect(
                        l.x, l.y, l.w, l.h,
                        videoW, videoH,
                        props.objectFit
                    )

                    -- Draw video frame
                    local imgPaint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, imgHandle, 1)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, drawX, drawY, drawW, drawH)
                    nvgFillPaint(nvg, imgPaint)
                    nvgFill(nvg)
                end
            end
        end
    end

    -- Draw status indicator if not ready
    if self.player_ and not self.state.ready then
        if self.state.decoderUnavailable then
            -- Decoder not available on this platform — show subtle placeholder
            nvgFontSize(nvg, 14)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 120))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(nvg, l.x + l.w / 2, l.y + l.h / 2, "Video not available", nil)
        else
            -- Still loading
            nvgFontSize(nvg, 16)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 180))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(nvg, l.x + l.w / 2, l.y + l.h / 2, "Loading...", nil)
        end
    end

    -- Note: Children (overlays, controls, etc.) are rendered automatically
    -- by the UI framework's renderWidgetTree() after this Render() call
end

---Get or create NanoVG image from texture
---@param nvg userdata NanoVG context
---@param texture VideoTexture
---@return number|nil imageHandle
function VideoPlayerWidget:GetOrCreateNvgImage(nvg, texture)
    if not self.nvgImageHandle_ then
        if nvgCreateVideo then
            self.nvgImageHandle_ = nvgCreateVideo(nvg, texture)
            if not self.nvgImageHandle_ or self.nvgImageHandle_ <= 0 then
                self.nvgImageHandle_ = nil
            end
        end
    end
    return self.nvgImageHandle_
end

---Calculate draw rectangle based on objectFit mode
---@param containerX number
---@param containerY number
---@param containerW number
---@param containerH number
---@param videoW number
---@param videoH number
---@param objectFit string "contain", "cover", or "fill"
---@return number, number, number, number drawX, drawY, drawW, drawH
function VideoPlayerWidget:CalculateDrawRect(containerX, containerY, containerW, containerH, videoW, videoH, objectFit)
    if videoW <= 0 or videoH <= 0 then
        return containerX, containerY, containerW, containerH
    end

    if objectFit == "fill" then
        -- Stretch to fill container
        return containerX, containerY, containerW, containerH
    end

    local containerRatio = containerW / containerH
    local videoRatio = videoW / videoH

    local drawW, drawH

    if objectFit == "cover" then
        -- Scale to cover (may crop)
        if videoRatio > containerRatio then
            drawH = containerH
            drawW = containerH * videoRatio
        else
            drawW = containerW
            drawH = containerW / videoRatio
        end
    else
        -- "contain" - Scale to fit (letterbox/pillarbox)
        if videoRatio > containerRatio then
            drawW = containerW
            drawH = containerW / videoRatio
        else
            drawH = containerH
            drawW = containerH * videoRatio
        end
    end

    local drawX = containerX + (containerW - drawW) / 2
    local drawY = containerY + (containerH - drawH) / 2

    return drawX, drawY, drawW, drawH
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function VideoPlayerWidget:OnPointerUp(event)
    Widget.OnPointerUp(self, event)

    -- Toggle play/pause on click
    if self.player_ then
        if self.player_:IsPlaying() then
            self:Pause()
        else
            self:Play()
        end
    end
end

return VideoPlayerWidget
