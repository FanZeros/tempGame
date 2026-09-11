-- ============================================================================
-- SpriteAnimator — Frame animation playback controller
-- ============================================================================
--
-- Manages animation playback timing, frame advancement, and state transitions.
-- Pure logic layer with no rendering or texture concerns; driven by Sprite widget.
--
-- Features:
--   • Per-frame independent duration (not uniform fps, precise to ms per frame)
--   • Playback direction: forward / reverse / pingpong
--   • Repeat count control (0 = infinite loop, N = play N times)
--   • Animation queue (Chain): auto-play next when current completes
--   • GotoAndPlay / GotoAndStop for precise frame jumping
--   • onComplete / onLoop / onFrameChange callbacks
--
-- Industry reference:
--   • PixiJS AnimatedSprite — animationSpeed + per-frame time model
--   • Phaser AnimationState — chain/repeat/yoyo(pingpong)/timeScale control
-- ============================================================================

-- ============================================================================
-- Types
-- ============================================================================

---@class SpritePlayOptions
---@field loop? boolean Whether to loop (nil = use animation definition). Overrides repeatCount when set explicitly.
---@field speed? number Playback speed multiplier (default: keep current). Negative = reverse playback.
---@field direction? "forward"|"reverse"|"pingpong" Direction override
---@field repeatCount? number Repeat count (0=infinite, overrides animation def). Only used when loop is nil.
---@field restart? boolean Force restart even if same animation is playing (default: false)
---@field onComplete? fun(animName: string) Called when non-looping animation ends
---@field onLoop? fun(count: number) Called on each loop iteration
---@field onFrameChange? fun(frame: number, localFrame: number) Called on frame change

---@class SpriteChainEntry
---@field name string Animation name
---@field opts? SpritePlayOptions Play options

-- ============================================================================
-- SpriteAnimator Class
-- ============================================================================

---@class SpriteAnimator
---@field private status_ "stopped"|"playing"|"paused"
---@field private animName_ string
---@field private frameIndices_ number[] Ordered absolute frame indices of the current animation (1-based into sheet)
---@field private direction_ "forward"|"reverse"|"pingpong"
---@field private currentFrame_ number Current frame (absolute index in sheet, 1-based)
---@field private localFrame_ number Current frame (relative index in animation, 0-based)
---@field private elapsed_ number Time accumulated in current frame (ms)
---@field private speed_ number Playback speed multiplier
---@field private loop_ boolean
---@field private repeatCount_ number
---@field private repeatsDone_ number
---@field private pingpongForward_ boolean Current travel direction in pingpong mode
---@field private frameCount_ number Total frames in current animation
---@field private frameDurations_ table<number, number> localFrame -> duration(ms)
---@field private onComplete_ fun(animName: string)|nil
---@field private onLoop_ fun(count: number)|nil
---@field private onFrameChange_ fun(frame: number, localFrame: number)|nil
---@field private queue_ SpriteChainEntry[]
---@field private chainResolver_ fun(name: string, opts: SpritePlayOptions|nil)|nil
---@field private reverseTime_ boolean Transient: true while consuming negative-speed (reverse) time this frame
local SpriteAnimator = {}
SpriteAnimator.__index = SpriteAnimator

--- Create a new animator instance.
---@return SpriteAnimator
function SpriteAnimator.New()
    local self = setmetatable({}, SpriteAnimator)
    self.status_ = "stopped"
    self.animName_ = ""
    self.frameIndices_ = {}
    self.direction_ = "forward"
    self.currentFrame_ = 1
    self.localFrame_ = 0
    self.elapsed_ = 0
    self.speed_ = 1.0
    self.loop_ = true
    self.repeatCount_ = 0
    self.repeatsDone_ = 0
    self.pingpongForward_ = true
    self.frameCount_ = 0
    self.frameDurations_ = {}
    self.onComplete_ = nil
    self.onLoop_ = nil
    self.onFrameChange_ = nil
    self.queue_ = {}
    self.chainResolver_ = nil
    self.reverseTime_ = false
    return self
end

-- ============================================================================
-- Playback Control
-- ============================================================================

--- Start playing the specified animation.
---@param sheet SpriteSheet Data source
---@param name string Animation name
---@param opts SpritePlayOptions|nil Play options
---@return boolean # Whether playback started successfully
function SpriteAnimator:Play(sheet, name, opts)
    local anim = sheet:GetAnimation(name)
    if not anim or not anim.frameIndices or #anim.frameIndices == 0 then return false end

    opts = opts or {}

    -- Switching animation clears pending chain (industry standard)
    self.queue_ = {}

    self.animName_ = name
    self.frameIndices_ = anim.frameIndices  -- ordered absolute indices; localFrame_ indexes this
    self.direction_ = opts.direction or anim.direction or "forward"
    self.frameCount_ = #anim.frameIndices
    self.speed_ = opts.speed or self.speed_
    self.elapsed_ = 0
    self.repeatsDone_ = 0
    self.pingpongForward_ = true

    if opts.loop ~= nil then
        self.loop_ = opts.loop
        self.repeatCount_ = opts.loop and 0 or 1
    else
        self.repeatCount_ = opts.repeatCount or anim.repeatCount or 0
        self.loop_ = (self.repeatCount_ == 0)
    end

    self.onComplete_ = opts.onComplete or nil
    self.onLoop_ = opts.onLoop or nil
    self.onFrameChange_ = opts.onFrameChange or nil

    -- Build per-frame duration table (localFrame → ms)
    self.frameDurations_ = {}
    for i = 0, self.frameCount_ - 1 do
        local f = sheet:GetFrame(self.frameIndices_[i + 1])
        self.frameDurations_[i] = f and f.duration or 42
    end

    -- Initial frame based on direction
    if self.direction_ == "reverse" then
        self.localFrame_ = self.frameCount_ - 1
    else
        self.localFrame_ = 0
    end
    self.currentFrame_ = self.frameIndices_[self.localFrame_ + 1]
    self.status_ = "playing"

    return true
end

--- Stop playback immediately and clear the queue.
function SpriteAnimator:Stop()
    if self.status_ == "stopped" then return end
    self.status_ = "stopped"
    self.queue_ = {}
end

--- Pause playback (retains current frame position).
function SpriteAnimator:Pause()
    if self.status_ == "playing" then
        self.status_ = "paused"
    end
end

--- Resume paused playback.
function SpriteAnimator:Resume()
    if self.status_ == "paused" then
        self.status_ = "playing"
    end
end

--- Set playback speed multiplier (1.0 = normal, 2.0 = double speed).
---@param speed number
function SpriteAnimator:SetSpeed(speed)
    self.speed_ = speed
end

---@return number
function SpriteAnimator:GetSpeed()
    return self.speed_
end

--- Jump to a specific frame (0-based local index within current animation).
---@param localFrame number
function SpriteAnimator:SetFrame(localFrame)
    if localFrame < 0 then localFrame = 0 end
    if localFrame >= self.frameCount_ then localFrame = self.frameCount_ - 1 end
    local oldFrame = self.currentFrame_
    self.localFrame_ = localFrame
    self.currentFrame_ = self.frameIndices_[localFrame + 1]
    self.elapsed_ = 0
    if self.currentFrame_ ~= oldFrame and self.onFrameChange_ then
        pcall(self.onFrameChange_, self.currentFrame_, self.localFrame_)
    end
end

--- Jump to a specific frame and pause.
---@param localFrame number 0-based
function SpriteAnimator:GotoAndStop(localFrame)
    self:SetFrame(localFrame)
    self.status_ = "paused"
end

--- Jump to a specific frame and start playing.
---@param localFrame number 0-based
function SpriteAnimator:GotoAndPlay(localFrame)
    self:SetFrame(localFrame)
    self.status_ = "playing"
end

-- ============================================================================
-- Queue (Chain)
-- ============================================================================

--- Enqueue an animation to play after the current one completes.
---@param name string Animation name
---@param opts SpritePlayOptions|nil
function SpriteAnimator:Chain(name, opts)
    self.queue_[#self.queue_ + 1] = { name = name, opts = opts }
end

--- Clear the animation queue.
function SpriteAnimator:ClearChain()
    self.queue_ = {}
end

--- Set a chain resolver function (called instead of direct Play on queue advance).
-- Used by Sprite widget to resolve animations across different sheets.
---@param resolver fun(name: string, opts: SpritePlayOptions|nil)|nil
function SpriteAnimator:SetChainResolver(resolver)
    self.chainResolver_ = resolver
end

-- ============================================================================
-- Getters
-- ============================================================================

--- Get the current frame's absolute index in the sheet (1-based).
---@return number
function SpriteAnimator:GetCurrentFrame()
    return self.currentFrame_
end

--- Get the current frame's local index within the animation (0-based).
---@return number
function SpriteAnimator:GetLocalFrame()
    return self.localFrame_
end

--- Get the total frame count of the current animation.
---@return number
function SpriteAnimator:GetFrameCount()
    return self.frameCount_
end

--- Get the current animation name.
---@return string
function SpriteAnimator:GetAnimationName()
    return self.animName_
end

---@return boolean
function SpriteAnimator:IsPlaying()
    return self.status_ == "playing"
end

---@return boolean
function SpriteAnimator:IsPaused()
    return self.status_ == "paused"
end

---@return boolean
function SpriteAnimator:IsStopped()
    return self.status_ == "stopped"
end

--- Get playback progress (0~1).
---@return number
function SpriteAnimator:GetProgress()
    if self.frameCount_ <= 1 then return 1 end
    return self.localFrame_ / (self.frameCount_ - 1)
end

-- ============================================================================
-- Update (called every frame)
-- ============================================================================

--- Advance animation time. Called by Sprite widget's Update(dt) each frame.
---@param dt number Frame delta time in seconds
---@param sheet SpriteSheet Data source (used for chain playback lookups)
---@return boolean # Whether a frame change occurred
function SpriteAnimator:Update(dt, sheet)
    if self.status_ ~= "playing" then return false end
    if self.frameCount_ <= 0 then return false end

    local dtMs = dt * 1000 * self.speed_
    if dtMs == 0 then return false end

    -- Negative speed → reverse time direction (industry standard behavior)
    local reverseTime = dtMs < 0
    if reverseTime then dtMs = -dtMs end

    self.elapsed_ = self.elapsed_ + dtMs

    local frameDur = self.frameDurations_[self.localFrame_] or 42
    if frameDur <= 0 then frameDur = 1 end
    if self.elapsed_ < frameDur then
        return false
    end

    -- Consume accumulated time, advance frames (handles frame skipping)
    self.reverseTime_ = reverseTime
    local changed = false
    local maxSkips = self.frameCount_ * 2
    while self.elapsed_ >= frameDur and self.status_ == "playing" and maxSkips > 0 do
        maxSkips = maxSkips - 1
        self.elapsed_ = self.elapsed_ - frameDur
        changed = true

        local nextLocal = self:NextLocalFrame_()
        if nextLocal < 0 then
            self:OnAnimationEnd_(sheet)
            return changed
        end

        self.localFrame_ = nextLocal
        self.currentFrame_ = self.frameIndices_[self.localFrame_ + 1]
        frameDur = self.frameDurations_[self.localFrame_] or 42
        if frameDur <= 0 then frameDur = 1 end
    end
    self.reverseTime_ = false

    if changed and self.onFrameChange_ then
        pcall(self.onFrameChange_, self.currentFrame_, self.localFrame_)
    end

    return changed
end

-- ============================================================================
-- Private
-- ============================================================================

---@private
---@return number # Next local frame, or -1 if animation should end
function SpriteAnimator:NextLocalFrame_()
    -- Negative speed flips forward/reverse (pingpong reverses travel direction)
    local dir = self.direction_
    if self.reverseTime_ then
        if dir == "forward" then dir = "reverse"
        elseif dir == "reverse" then dir = "forward"
        end
    end

    if dir == "forward" then
        local next = self.localFrame_ + 1
        if next >= self.frameCount_ then
            return self:HandleBoundary_()
        end
        return next

    elseif dir == "reverse" then
        local next = self.localFrame_ - 1
        if next < 0 then
            return self:HandleBoundary_()
        end
        return next

    else -- pingpong
        if self.frameCount_ <= 1 then
            return self:HandleBoundary_()
        end
        local fwd = self.pingpongForward_
        if self.reverseTime_ then fwd = not fwd end
        if fwd then
            local next = self.localFrame_ + 1
            if next >= self.frameCount_ then
                self.pingpongForward_ = not self.pingpongForward_
                return self.localFrame_ - 1
            end
            return next
        else
            local next = self.localFrame_ - 1
            if next < 0 then
                self.pingpongForward_ = not self.pingpongForward_
                -- Count the cycle (HandleBoundary_ honors repeatCount; <0 = end), then
                -- step up to localFrame_+1 — symmetric with the top boundary above.
                if self:HandleBoundary_() < 0 then return -1 end
                return self.localFrame_ + 1
            end
            return next
        end
    end
end

---@private
---@return number # -1 to end, or reset frame index for loop
function SpriteAnimator:HandleBoundary_()
    self.repeatsDone_ = self.repeatsDone_ + 1

    if not self.loop_ and self.repeatCount_ > 0 and self.repeatsDone_ >= self.repeatCount_ then
        return -1
    end

    if self.onLoop_ then
        pcall(self.onLoop_, self.repeatsDone_)
    end

    local dir = self.direction_
    if self.reverseTime_ then
        if dir == "forward" then dir = "reverse"
        elseif dir == "reverse" then dir = "forward"
        end
    end

    if dir == "forward" then
        return 0
    elseif dir == "reverse" then
        return self.frameCount_ - 1
    else -- pingpong
        -- Phase resets relative to travel direction: forward at normal speed, from the
        -- far end under reverse (negative-speed) time.
        self.pingpongForward_ = not self.reverseTime_
        return 0
    end
end

---@private
function SpriteAnimator:OnAnimationEnd_(sheet)
    self.status_ = "stopped"

    if self.onComplete_ then
        pcall(self.onComplete_, self.animName_)
    end

    -- Play next queued animation via resolver (reaches into Sprite:Play) if set, else
    -- direct; pcall-guards the resolver so a bad chain entry can't break playback.
    if #self.queue_ > 0 then
        local entry = table.remove(self.queue_, 1)
        if self.chainResolver_ then
            pcall(self.chainResolver_, entry.name, entry.opts)
        else
            self:Play(sheet, entry.name, entry.opts)
        end
    end
end

return SpriteAnimator
