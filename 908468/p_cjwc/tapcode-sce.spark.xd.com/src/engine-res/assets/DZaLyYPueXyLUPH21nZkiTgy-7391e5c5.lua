-- ============================================================================
-- Sprite — Spritesheet frame animation / static display UI widget
-- ============================================================================
--
-- An AnimatedSprite widget (named "Sprite" for AI-friendly brevity) that can
-- also display a single static frame from an atlas — like PixiJS Sprite with
-- a Texture from a Spritesheet.
--
-- Architecture (aligned with PixiJS):
--   SpriteSheet = UI-agnostic atlas DATA (parse JSON, frame/animation lookup, page
--                 image paths) — shared core in urhox-libs/Sprite/, reusable by 3D
--   Sprite      = this 2D UI widget — resolves page paths to nvgImage handles (via
--                 ImageCache) and renders one frame / animates through frames
--
-- Frame keys are the "texture references" (PixiJS-style); there is no intermediate
-- Texture class — the sheet yields a page image path and this widget resolves/draws it.
--
-- Usage patterns:
--
--   -- Pattern 1 (preferred): One atlas whose `animations` array defines its clips —
--   -- every entry auto-registers as a named animation; with no defaultAnimation the
--   -- FIRST animation in the array plays (the conventional default). Industry-standard
--   -- layout (PixiJS sheet.animations / Godot SpriteFrames / Spine skeleton).
--   local hero = UI.Sprite({ src = "sprites/hero/sprite.json" })          -- plays first animation
--   local hero2 = UI.Sprite({ src = "sprites/hero/sprite.json", defaultAnimation = "walk" })
--
--   -- Pattern 2: Static frame (like PixiJS new Sprite(sheet.textures['key']))
--   local pose = UI.Sprite({ src = "sprites/hero/sprite.json", frame = "idle_0001" })
--
--   -- Pattern 3: Animations split across SEPARATE files (e.g. sprite-gen's
--   -- one-file-per-animation output, kept apart for per-anim sizing / DWP). Use
--   -- the declarative `animations` map — one block, no AddAnimation()+Play() loop.
--   local hero3 = UI.Sprite({
--       animations = {                                          -- name → path map
--           idle = "sprites/hero/idle/spritesheet.json",
--           jump = "sprites/hero/jump/spritesheet.json",
--       },
--       defaultAnimation = "idle",     -- recommended here: a map has no inherent order
--   })
--   -- (animations also accepts an array: { {name="idle", src="..."}, ... })
--
--   -- Pattern 4: Imperative, for animations added/swapped dynamically at runtime
--   local hero4 = UI.Sprite({ width = 156, height = 256 })
--   hero4:AddAnimation("idle", "sprites/hero/idle/spritesheet.json")
--   hero4:Play("idle")
--
-- Industry reference:
--   * PixiJS: Spritesheet → Texture (frame ref) → Sprite / AnimatedSprite
--   * Phaser: TextureManager → AnimationState (multi-animation, chain, direction)
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local UI = require("urhox-libs/UI/Core/UI")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")
-- UI-agnostic sprite core (shared with future 3D sprites); this widget is the 2D
-- consumer that resolves the atlas page paths to nvgImage handles via ImageCache.
local SpriteSheet = require("urhox-libs/Sprite/SpriteSheet")
local SpriteAnimator = require("urhox-libs/Sprite/SpriteAnimator")

-- ============================================================================
-- objectPosition parsing (CSS object-position subset)
-- ============================================================================

local OBJPOS_X = { left = 0, center = 0.5, right = 1 }
local OBJPOS_Y = { top = 0, center = 0.5, bottom = 1 }

-- Shared read-only fallback pivot (do NOT mutate the returned table).
local DEFAULT_PIVOT = { x = 0.5, y = 0.5 }

-- ============================================================================
-- objectFit validation (runtime layer; EmmyLua union literal is the static layer)
-- ============================================================================

local VALID_FIT = { contain = true, cover = true, fill = true, none = true }
local FIT_LIST = "contain/cover/fill/none"

--- Coerce an objectFit value to a valid one, warning on a typo'd/unknown value.
-- Pairs with the @field's union-literal type: the editor LSP flags bad values
-- statically, and this catches whatever slips through at runtime instead of
-- silently rendering blank.
---@param fit any
---@return "contain"|"cover"|"fill"|"none"
local function normalizeFit(fit)
    if fit == nil then return "contain" end
    if VALID_FIT[fit] then return fit end
    if log then
        log:Write(LOG_WARNING, "[Sprite] objectFit '" .. tostring(fit)
            .. "' is invalid, falling back to 'contain' (valid: " .. FIT_LIST .. ")")
    end
    return "contain"
end

--- Resolve one token to a normalized axis value (keyword, "N%", or bare number).
---@param tok string
---@param axisMap table<string, number>
---@return number|nil
local function axisToken(tok, axisMap)
    local kw = axisMap[tok]
    if kw then return kw end
    local pct = tok:match("^([%d%.]+)%%$")
    if pct then return tonumber(pct) / 100 end
    local num = tonumber(tok)
    if num then return num end  -- assume already normalized [0,1]
    return nil
end

--- Parse an objectPosition value into normalized x, y (CSS object-position).
-- Accepts a table ({x=,y=} or {x, y}, normalized) or a string ("center",
-- "bottom", "top left", "50% 100%", ...). Returns nil on unrecognized input.
---@param v table|string|nil
---@return number|nil x
---@return number|nil y
local function resolveObjectPosition(v)
    if type(v) == "table" then
        local x = v.x or v[1]
        local y = v.y or v[2]
        if type(x) == "number" and type(y) == "number" then return x, y end
        return nil
    end
    if type(v) ~= "string" then return nil end

    local toks = {}
    for t in v:gmatch("%S+") do toks[#toks + 1] = t:lower() end

    if #toks == 1 then
        local t = toks[1]
        if t == "center" then return 0.5, 0.5 end
        if OBJPOS_X[t] and t ~= "center" then return OBJPOS_X[t], 0.5 end
        if OBJPOS_Y[t] and t ~= "center" then return 0.5, OBJPOS_Y[t] end
        local n = axisToken(t, {})
        if n then return n, 0.5 end
        return nil
    elseif #toks >= 2 then
        -- Keyword pair in any order (e.g. "top left" == "left top")
        local x, y
        for i = 1, 2 do
            local t = toks[i]
            if t == "left" or t == "right" then x = OBJPOS_X[t]
            elseif t == "top" or t == "bottom" then y = OBJPOS_Y[t] end
        end
        if x and y then return x, y end
        -- Positional fallback: first = x-axis, second = y-axis
        local xv = axisToken(toks[1], OBJPOS_X)
        local yv = axisToken(toks[2], OBJPOS_Y)
        if xv and yv then return xv, yv end
    end
    return nil
end

-- ============================================================================
-- Types
-- ============================================================================

---@class SpriteProps : WidgetProps
---@field sheet? SpriteSheet|string A ready SpriteSheet (or path); takes priority over src. Mutually exclusive with src (if both given, src is ignored)
---@field src? string Single-atlas JSON path (auto-loads via cached SpriteSheet.Load). All animations in its `animations` array register as named animations — preferred layout
---@field animations? table<string, string|SpriteSheet>|{name: string, src: string|SpriteSheet}[] Only needed when animations live in SEPARATE files: a name→path/sheet map, or an array of {name, src}. Registered via AddAnimation, ALWAYS merged on top of sheet/src
---@field defaultAnimation? string Which registered animation to auto-play on mount (paired with autoPlay). If omitted, the first registered animation plays
---@field frame? string Frame key for static display (e.g. "idle_0001"); calls GotoAndStop internally
---@field loop? boolean Override loop for the played animation. Unset (nil) = respect each animation's own data `repeat` (idle loops, jump plays once, ...). true = force loop, false = force play-once
---@field speed? number Playback speed multiplier (default: 1.0)
---@field autoPlay? boolean Auto-play on load (default: true; ignored when frame is set)
---@field objectFit? "contain"|"cover"|"fill"|"none" Display fitting mode (default: "contain")
---@field objectPosition? table|string In-box content alignment (CSS object-position). Default: center. Independent of pivot
---@field applyPivotInAbsolute? boolean When position is "absolute": register the pivot point at left/top (per-frame synced translate) AND set transformOrigin to "top-left" so rotate/scale pivot around the foot. Default: false. No effect in flow
---@field flipX? boolean Horizontal flip
---@field flipY? boolean Vertical flip
---@field onComplete? fun(animName: string) Called when non-looping animation ends
---@field onLoop? fun(count: number) Called on each loop iteration
---@field onFrameChange? fun(frame: number, localFrame: number) Called on frame change
---@field onPlay? fun(name: string, prevName: string|nil) Called right after Play starts an animation — fired once the new animation's size/pivot/box are already updated, so GetCurrentAnimation/GetSourceSize/GetPivot/box read the NEW values (use it to re-layout on switch). name = animation now playing, prevName = previous (nil on first play). Fires on switch/restart, not on an ignored same-animation replay

-- ============================================================================
-- Sprite Widget Class
-- ============================================================================

---@class Sprite : Widget
---@field private sheets_ table<string, SpriteSheet> Animation name → sheet mapping (references only; never owned)
---@field private animator_ SpriteAnimator
---@field private currentSheet_ SpriteSheet|nil
---@field private staticFrame_ number|nil Absolute frame index for static display
local Sprite = Widget:Extend("Sprite")

-- Exposed for unit testing the CSS object-position parser (pure function).
Sprite._parseObjectPosition = resolveObjectPosition

function Sprite:Init(props)
    props = props or {}
    -- NOTE: props.loop is intentionally NOT defaulted. Each animation's loop count
    -- lives in its data (animations[].repeat: -1/0 = infinite, N = N times). loop is
    -- an OPTIONAL override of the played animation — nil (unset) → respect the data.
    props.speed = props.speed or 1.0
    props.autoPlay = props.autoPlay ~= false
    props.objectFit = normalizeFit(props.objectFit)

    -- Whether the user pinned an explicit box size. With neither dimension given, the
    -- Sprite reports its intrinsic sourceSize to Yoga (like a CSS <img>) so it auto-sizes.
    self.userSetWidth_ = props.width ~= nil
    self.userSetHeight_ = props.height ~= nil
    self.userSetAspectRatio_ = props.aspectRatio ~= nil
    -- Last intrinsic size/aspect pushed to Yoga; change-detected so only a real
    -- sourceSize change (bbox-per-anim switch) re-dirties layout.
    self.intrinsicW_, self.intrinsicH_, self.intrinsicAR_ = nil, nil, nil

    -- Optional runtime pivot override (SetCustomPivot); takes priority in GetPivot.
    self.customPivot_ = nil
    -- True while applyPivotInAbsolute owns translateX/Y + transformOrigin;
    -- prevTransformOrigin_ holds the author's value to restore on disengage.
    self.pivotTranslateApplied_ = false
    self.prevTransformOrigin_ = nil

    -- Sprite-level "animation started" callback, fired by Play on every switch/restart
    -- (unlike the per-Play animator callbacks onComplete/onLoop/onFrameChange).
    self.onPlay_ = props.onPlay

    self.sheets_ = {}
    -- Registration order of animation names (deterministic "first animation",
    -- unlike pairs() over the sheets_ map). Appended on register, pruned on remove.
    self.animOrder_ = {}
    self.animator_ = SpriteAnimator.New()
    self.currentSheet_ = nil
    self.staticFrame_ = nil
    self.destroyed_ = false
    self.cachedFrameIdx_ = nil  -- Render-side cache key (see Render)

    self.animator_:SetChainResolver(function(name, opts)
        self:Play(name, opts)
    end)

    Widget.Init(self, props)

    -- Sheets are owned by the global SpriteSheet cache; a Sprite only references
    -- them. Both props.sheet (a ready instance) and props.src (a path) are just
    -- registered, never destroyed by this widget.
    if props.sheet then
        self:UseSheet_(props.sheet)
    elseif props.src then
        local sheet = SpriteSheet.Load(props.src)
        if sheet then
            self:UseSheet_(sheet)
        end
    end

    -- Declarative multi-animation: a name→path/sheet map (recommended) or an
    -- array of {name, src} entries. Lets the whole sprite be authored in one block
    -- instead of an imperative AddAnimation()+Play() loop.
    if type(props.animations) == "table" then
        self:RegisterAnimations_(props.animations)
    end

    -- Resolve initial display mode
    if self.currentSheet_ then
        if props.frame then
            self:GotoAndStop(props.frame)
        elseif props.autoPlay then
            local anim = props.defaultAnimation or self:FirstAnimationName_()
            if anim then
                self:Play(anim, {
                    loop = props.loop,
                    speed = props.speed,
                    onComplete = props.onComplete,
                    onLoop = props.onLoop,
                    onFrameChange = props.onFrameChange,
                })
            end
        end
    end
end

---@private
--- Map an animation name to a sheet, tracking first-seen order so that the
--- implicit "first animation" is deterministic (a plain pairs() over sheets_ is
--- not). Re-registering an existing name updates the sheet but keeps its order.
---@param name string
---@param sheet SpriteSheet
function Sprite:RegisterAnimName_(name, sheet)
    if self.sheets_[name] == nil then
        self.animOrder_[#self.animOrder_ + 1] = name
    end
    self.sheets_[name] = sheet
end

---@private
--- Register every animation of a sheet, preserving the sheet's `animations` array
--- declaration order so the implicit "first animation" is the first declared one
--- (the conventional default), not an alphabetical or hash-order pick.
---@param sheet SpriteSheet
function Sprite:RegisterSheetAnims_(sheet)
    for _, name in ipairs(sheet:GetAnimationNames()) do
        self:RegisterAnimName_(name, sheet)
    end
end

---@private
--- Register all animations from a sheet into the internal lookup table.
--- Accepts a ready SpriteSheet instance or a path string (loaded via the cache),
--- mirroring AddAnimation — passing a path to `sheet` is a common mix-up with `src`
--- and should degrade gracefully rather than hard-crash.
---@param sheet SpriteSheet|string
function Sprite:UseSheet_(sheet)
    if type(sheet) == "string" then
        sheet = SpriteSheet.Load(sheet)
    end
    if type(sheet) ~= "table" or type(sheet.GetAnimationNames) ~= "function" then
        if log then
            log:Write(LOG_WARNING, "[Sprite] UseSheet_ ignored invalid sheet (expected SpriteSheet or path)")
        end
        return
    end
    self:RegisterSheetAnims_(sheet)
    if not self.currentSheet_ then
        self.currentSheet_ = sheet
    end
    self:ApplyIntrinsicSize_()
end

---@private
--- Register a declarative `animations` spec (map name→path/sheet, or an array of
--- {name, src}). Map keys are sorted so registration order is deterministic.
---@param spec table
function Sprite:RegisterAnimations_(spec)
    if #spec > 0 then
        -- Array form: { {name=, src=}, ... } — order as authored.
        for _, item in ipairs(spec) do
            if type(item) == "table" and item.name then
                self:AddAnimation(item.name, item.src or item.sheet)
            elseif log then
                log:Write(LOG_WARNING, "[Sprite] animations[] entry missing {name, src}")
            end
        end
    else
        -- Map form: { name = path/sheet, ... } — sort keys for determinism.
        local names = {}
        for name in pairs(spec) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            self:AddAnimation(name, spec[name])
        end
    end
end

---@private
---@return string|nil
function Sprite:FirstAnimationName_()
    return self.animOrder_[1]
end

---@private
--- Report the current animation's intrinsic sourceSize to Yoga when the user did not
--- pin a box, like a CSS <img> auto-sizing to its natural dimensions (the engine has
--- no Yoga measure-func, so the size is pushed). Re-applied on animation switch:
---   * neither width nor height set → push both = sourceSize (box = intrinsic)
---   * exactly one set             → derive the other via aspectRatio (keep ratio)
---   * both set                    → leave the user's box untouched
--- For bbox-per-anim atlases the unpinned box tracks the playing animation, so render
--- scale stays consistent and, in absolute layout, the pivot keeps the foot anchored.
--- Change-detected: an unchanged sourceSize (canvas mode / same-anim replay) is a no-op.
function Sprite:ApplyIntrinsicSize_()
    if not self.currentSheet_ then return end
    local src = self:GetSourceSize()  -- current animation/frame's sourceSize
    if not src or not src.w or src.w <= 0 or src.h <= 0 then return end

    if not self.userSetWidth_ and not self.userSetHeight_ then
        if self.intrinsicW_ ~= src.w or self.intrinsicH_ ~= src.h then
            self:SetWidth(src.w)
            self:SetHeight(src.h)
            self.intrinsicW_, self.intrinsicH_ = src.w, src.h
        end
    elseif not self.userSetAspectRatio_ and self.userSetWidth_ ~= self.userSetHeight_ then
        -- Only one dimension pinned: let Yoga derive the other from the source
        -- aspect ratio (width / height), exactly like <img> with width:auto.
        local ar = src.w / src.h
        if self.intrinsicAR_ ~= ar then
            YGNodeStyleSetAspectRatio(self.node, ar)
            self.intrinsicAR_ = ar
            Widget._notifyLayoutDirty()
        end
    end
end

---@private
--- When `applyPivotInAbsolute` is on AND position is "absolute": each frame translate
--- the box so the pivot point registers at the absolute left/top (recomputed from the
--- current rendered rect — objectFit/objectPosition/size). Also takes over
--- transformOrigin = "top-left" so rotate/scale pivot around that same foot point; the
--- author's prior transformOrigin is restored on disengage. No-op in flow layout.
function Sprite:SyncPivotTranslate_()
    -- Disengaged (off / not absolute): release the translate + transformOrigin we owned.
    if not self.props.applyPivotInAbsolute or self.props.position ~= "absolute" then
        if self.pivotTranslateApplied_ then
            self.props.translateX = nil
            self.props.translateY = nil
            self.props.transformOrigin = self.prevTransformOrigin_
            self.prevTransformOrigin_ = nil
            self.pivotTranslateApplied_ = false
        end
        return
    end
    -- Engaged but not ready yet (no sheet/layout/frame): leave last value untouched.
    if not self.currentSheet_ then return end
    local l = self:GetAbsoluteLayout()
    if not l or l.w <= 0 or l.h <= 0 then return end
    local fd = self.currentSheet_:GetFrame(self:GetCurrentFrame())
    if not fd then return end

    local src = fd.sourceSize
    if not src or src.w <= 0 or src.h <= 0 then return end  -- guard div-by-zero
    local sx, sy = l.w / src.w, l.h / src.h
    local fit = self.props.objectFit
    if fit == "contain" then local s = math.min(sx, sy); sx, sy = s, s
    elseif fit == "cover" then local s = math.max(sx, sy); sx, sy = s, s
    elseif fit == "none" then sx, sy = 1, 1 end
    local drawW, drawH = src.w * sx, src.h * sy

    local opx, opy = self:ResolveObjectPos_()
    local piv = self:GetPivot()
    -- On engage (once): take over transformOrigin = "top-left" (the translate below
    -- parks the foot there); save the author's value for disengage.
    if not self.pivotTranslateApplied_ then
        self.prevTransformOrigin_ = self.props.transformOrigin
        self.props.transformOrigin = "top-left"
    end
    -- translate the box so the content's pivot point lands at the box origin (left/top)
    self.props.translateX = -((l.w - drawW) * opx + piv.x * drawW)
    self.props.translateY = -((l.h - drawH) * opy + piv.y * drawH)
    self.pivotTranslateApplied_ = true
end

---@private
--- Resolve objectPosition → normalized (px, py), default center. Memoized by the
--- raw prop value (objectPosition rarely changes) to avoid per-frame string parsing
--- in Render and SyncPivotTranslate_.
---@return number px
---@return number py
function Sprite:ResolveObjectPos_()
    local op = self.props.objectPosition
    if op == nil then return 0.5, 0.5 end
    if op ~= self.opRaw_ then
        self.opRaw_ = op
        local rx, ry = resolveObjectPosition(op)
        self.opX_, self.opY_ = rx or 0.5, ry or 0.5
    end
    return self.opX_, self.opY_
end

-- ============================================================================
-- Data Loading
-- ============================================================================

--- Register an animation atlas.
-- Accepts either a JSON path (loaded through the global SpriteSheet cache) or an
-- already-loaded SpriteSheet instance. With `name` nil, every animation in the
-- atlas's `animations` array is registered; if `name` is given, it is the single
-- lookup key. The Sprite only references the cached sheet — it never frees it
-- (use SpriteSheet.Release / ClearCache for that).
---@param name string|nil Animation name (nil = register all of the sheet's animations)
---@param source string|SpriteSheet Atlas JSON path, or a ready SpriteSheet instance
---@return Sprite self
function Sprite:AddAnimation(name, source)
    local sheet
    if type(source) == "string" then
        sheet = SpriteSheet.Load(source)
        if not sheet then
            if log then
                log:Write(LOG_WARNING, "[Sprite] Failed to load: " .. tostring(source))
            end
            return self
        end
    else
        sheet = source  -- already a SpriteSheet instance
    end

    if name then
        self:RegisterAnimName_(name, sheet)
    else
        self:RegisterSheetAnims_(sheet)
    end

    if not self.currentSheet_ then
        self.currentSheet_ = sheet
    end

    self:ApplyIntrinsicSize_()

    return self
end

--- Remove a registered animation.
---@param name string
---@return Sprite self
function Sprite:RemoveAnimation(name)
    -- Only drops the name → sheet mapping. The sheet itself stays in the global
    -- cache (it may be shared by other Sprites); unload it via SpriteSheet.Release.
    if self.sheets_[name] ~= nil then
        self.sheets_[name] = nil
        for i, n in ipairs(self.animOrder_) do
            if n == name then
                table.remove(self.animOrder_, i)
                break
            end
        end
    end
    return self
end

-- ============================================================================
-- Playback Control
-- ============================================================================

--- Play the specified animation (immediately switches, interrupts current).
-- If the same animation is already playing, does nothing (ignoreIfPlaying).
-- Pass opts.restart = true to force restart from frame 0.
---@param name string Animation name
---@param opts SpritePlayOptions|nil Play options
---@return Sprite self
function Sprite:Play(name, opts)
    if self.destroyed_ then return self end
    local sheet = self.sheets_[name]
    if not sheet then
        if log then
            local avail = table.concat(self:GetAnimationNames(), ", ")
            log:Write(LOG_WARNING, "[Sprite] animation '" .. tostring(name)
                .. "' not registered (available: " .. (avail ~= "" and avail or "<none>") .. ")")
        end
        return self
    end

    opts = opts or {}

    -- ignoreIfPlaying: skip if same animation is already active (industry standard)
    if not opts.restart and self.animator_:IsPlaying()
        and self.animator_:GetAnimationName() == name and self.currentSheet_ == sheet then
        return self
    end

    self.currentSheet_ = sheet
    self.staticFrame_ = nil
    -- Exact match first, fallback to sheet's first animation (handles name alias case).
    local animName = name
    if not sheet:GetAnimation(name) then
        animName = sheet:GetFirstAnimationName()
        -- Log the fallback so a typo'd name doesn't silently play the wrong clip.
        if log then
            log:Write(LOG_WARNING, "[Sprite] '" .. tostring(name)
                .. "' has no matching animation in its sheet; falling back to '"
                .. tostring(animName) .. "'")
        end
    end
    if animName then
        -- Previous animation (for onPlay), captured before the animator switches.
        local prevName = self.animator_:GetAnimationName()
        self.animator_:Play(sheet, animName, opts)
        -- Track the new animation's intrinsic size (bbox-per-anim box follows the
        -- current animation; no-op for canvas mode / same size).
        self:ApplyIntrinsicSize_()
        -- Fire onPlay AFTER the size/pivot update so the callback reads the new
        -- animation's state (GetSourceSize / GetPivot / box); pcall-guarded like the
        -- animator callbacks.
        if self.onPlay_ then
            pcall(self.onPlay_, animName, (prevName ~= "" and prevName) or nil)
        end
    end
    return self
end

--- Stop playback and clear the queue.
---@return Sprite self
function Sprite:Stop()
    self.animator_:Stop()
    return self
end

--- Pause playback.
---@return Sprite self
function Sprite:Pause()
    self.animator_:Pause()
    return self
end

--- Resume playback.
---@return Sprite self
function Sprite:Resume()
    self.animator_:Resume()
    return self
end

--- Set playback speed multiplier.
---@param speed number 1.0 = normal, 2.0 = double speed
---@return Sprite self
function Sprite:SetSpeed(speed)
    self.props.speed = speed
    self.animator_:SetSpeed(speed)
    return self
end

--- Display a single static frame by its atlas key (e.g. "idle_0001"), stopping
--- any animation. Searches the current sheet first, then other registered sheets
--- (switching currentSheet_ on a cross-sheet hit). The key is an ABSOLUTE frame
--- reference, independent of any animation.
---@param key string Frame key from the atlas
---@return Sprite self
function Sprite:GotoFrameKey(key)
    if self.destroyed_ then return self end
    -- Search current sheet first for deterministic behavior
    if self.currentSheet_ then
        local idx = self.currentSheet_:GetFrameIndex(key)
        if idx then
            self.staticFrame_ = idx
            self.animator_:Stop()
            return self
        end
    end
    for _, sheet in pairs(self.sheets_) do
        if sheet ~= self.currentSheet_ then
            local idx = sheet:GetFrameIndex(key)
            if idx then
                self.currentSheet_ = sheet
                self.staticFrame_ = idx
                self.animator_:Stop()
                return self
            end
        end
    end
    if log then
        log:Write(LOG_WARNING, "[Sprite] Frame key not found: " .. tostring(key))
    end
    return self
end

--- Jump to a 0-based LOCAL frame index within the current animation and pause.
--- Requires an animation context (call Play first); the index is relative to the
--- current animation's frame range, not an absolute atlas index.
---@param localFrame number 0-based local frame index within current animation
---@return Sprite self
function Sprite:GotoLocalFrame(localFrame)
    if self.destroyed_ then return self end
    self.staticFrame_ = nil
    self.animator_:GotoAndStop(localFrame)
    return self
end

--- Jump to a frame and stop. Compatibility dispatcher:
---   string → GotoFrameKey (absolute atlas key, may switch sheet)
---   number → GotoLocalFrame (0-based index within current animation)
--- Note the two forms use DIFFERENT coordinate systems; prefer the explicit
--- GotoFrameKey / GotoLocalFrame methods in new code.
---@param frame number|string Frame key, or 0-based local frame index
---@return Sprite self
---@overload fun(self: Sprite, frameKey: string): Sprite
---@overload fun(self: Sprite, localFrame: number): Sprite
function Sprite:GotoAndStop(frame)
    if type(frame) == "string" then
        return self:GotoFrameKey(frame)
    end
    return self:GotoLocalFrame(frame)
end

--- Jump to a 0-based LOCAL frame index within the current animation and play.
-- Requires an active animation context (call Play first) — without one the
-- animator has no frame range and Update will not advance. Use GotoFrameKey for
-- string-key static display; use Play to switch animations.
---@param localFrame number 0-based local frame index within current animation
---@return Sprite self
function Sprite:GotoAndPlay(localFrame)
    if self.destroyed_ then return self end
    self.staticFrame_ = nil
    self.animator_:GotoAndPlay(localFrame)
    return self
end

--- Enqueue an animation to play after the current one completes.
---@param name string
---@param opts SpritePlayOptions|nil
---@return Sprite self
function Sprite:Chain(name, opts)
    self.animator_:Chain(name, opts)
    return self
end

--- Clear the animation queue.
---@return Sprite self
function Sprite:ClearChain()
    self.animator_:ClearChain()
    return self
end

-- ============================================================================
-- Getters
-- ============================================================================

--- Get the current frame's absolute index in the sheet (1-based).
---@return number
function Sprite:GetCurrentFrame()
    if self.staticFrame_ then return self.staticFrame_ end
    return self.animator_:GetCurrentFrame()
end

--- Get the current frame's local index within the animation (0-based).
---@return number
function Sprite:GetLocalFrame()
    return self.animator_:GetLocalFrame()
end

--- Get the current frame's atlas key (string), or nil if none.
---@return string|nil
function Sprite:GetCurrentFrameKey()
    if not self.currentSheet_ then return nil end
    local f = self.currentSheet_:GetFrame(self:GetCurrentFrame())
    return f and f.name or nil
end

--- Get the total frame count of the current animation.
---@return number
function Sprite:GetFrameCount()
    return self.animator_:GetFrameCount()
end

--- Get playback progress (0~1).
---@return number
function Sprite:GetProgress()
    return self.animator_:GetProgress()
end

--- Get the name of the currently playing animation.
---@return string
function Sprite:GetCurrentAnimation()
    return self.animator_:GetAnimationName()
end

---@return boolean
function Sprite:IsPlaying()
    return self.animator_:IsPlaying()
end

---@return boolean
function Sprite:IsPaused()
    return self.animator_:IsPaused()
end

--- Whether playback has stopped (e.g. a non-looping animation finished).
---@return boolean
function Sprite:IsStopped()
    return self.animator_:IsStopped()
end

--- Get all registered animation names.
---@return string[]
function Sprite:GetAnimationNames()
    -- Return in registration order (animOrder_ is the source of truth); copy so
    -- callers can't mutate internal state.
    local names = {}
    for i, name in ipairs(self.animOrder_) do
        names[i] = name
    end
    return names
end

--- Get the total duration of a registered animation in seconds.
---@param name string Animation name
---@return number
function Sprite:GetDuration(name)
    local sheet = self.sheets_[name]
    if not sheet then return 0 end
    local animName = sheet:GetAnimation(name) and name or sheet:GetFirstAnimationName()
    if not animName then return 0 end
    return sheet:GetAnimationDuration(animName) / 1000
end

--- Get the current SpriteSheet (atlas) in use.
---@return SpriteSheet|nil
function Sprite:GetSheet()
    return self.currentSheet_
end

--- Get the current sheet's source (canvas) size, or nil if no sheet.
---@return {w: number, h: number}|nil
function Sprite:GetSourceSize()
    if not self.currentSheet_ then return nil end
    local f = self.currentSheet_:GetFrame(self:GetCurrentFrame())
    if f and f.sourceSize then return f.sourceSize end
    return self.currentSheet_:GetSourceSize()
end

--- Get the effective pivot for the current frame (normalized, sourceSize space,
--- top-left origin). Precedence: custom (SetCustomPivot) → frame.pivot → animation
--- pivot → sheet meta.pivot → (0.5,0.5). Always returns a table (never nil).
--- READ-ONLY — may be a shared internal table; use SetCustomPivot to change it.
---@return {x: number, y: number}
function Sprite:GetPivot()
    if self.customPivot_ then return self.customPivot_ end
    if not self.currentSheet_ then return DEFAULT_PIVOT end
    local f = self.currentSheet_:GetFrame(self:GetCurrentFrame())
    if f and f.pivot then return f.pivot end
    local anim = self.currentSheet_:GetAnimation(self.animator_:GetAnimationName())
    if anim and anim.pivot then return anim.pivot end
    return self.currentSheet_:GetPivot() or DEFAULT_PIVOT
end

--- Override the pivot at runtime (highest priority in GetPivot). Pass numbers,
--- a table ({x,y} or {x=,y=}), or nil to clear and fall back to atlas pivot.
---@param x number|table|nil Normalized x ([0,1]), or a {x,y} table, or nil to clear
---@param y number|nil Normalized y ([0,1]) when x is a number
---@return Sprite self
function Sprite:SetCustomPivot(x, y)
    if x == nil then
        self.customPivot_ = nil
    elseif type(x) == "table" then
        self.customPivot_ = { x = x.x or x[1] or 0.5, y = x.y or x[2] or 0.5 }
    else
        self.customPivot_ = { x = x, y = y or 0.5 }  -- omitted y defaults to 0.5
    end
    return self
end

-- ============================================================================
-- Display
-- ============================================================================

--- Set horizontal flip.
---@param flip boolean
---@return Sprite self
function Sprite:SetFlipX(flip)
    self.props.flipX = flip
    return self
end

--- Set vertical flip.
---@param flip boolean
---@return Sprite self
function Sprite:SetFlipY(flip)
    self.props.flipY = flip
    return self
end

--- Set display fitting mode.
---@param fit "contain"|"cover"|"fill"|"none"
---@return Sprite self
function Sprite:SetObjectFit(fit)
    self.props.objectFit = normalizeFit(fit)
    return self
end

--- Set in-box content alignment (CSS object-position), independent of the pivot.
--- Accepts {x, y} normalized ([0,1], top-left origin) or a keyword string
--- ("center", "bottom", "top left", "50% 100%", ...); nil → center.
--- Only has effect when objectFit leaves slack (contain/none with box ≠ content);
--- with "fill" the content fills the box, so this is a no-op.
---@param pos table|string|nil
---@return Sprite self
function Sprite:SetObjectPosition(pos)
    self.props.objectPosition = pos
    return self
end

-- ============================================================================
-- Widget Lifecycle
-- ============================================================================

--- Per-frame update. Called automatically by the UI framework's widget tree
--- walk — do NOT subscribe to the engine "Update" event for this; the framework
--- drives it. (Game-level logic that is not a widget still needs its own
--- SubscribeToEvent("Update", ...).)
---@param dt number Frame delta time in seconds
function Sprite:Update(dt)
    if self.destroyed_ then return end
    if not self.staticFrame_ and self.currentSheet_ then
        self.animator_:Update(dt, self.currentSheet_)
    end

    -- Keep the absolute pivot-registration translate in sync (no-op unless
    -- applyPivotInAbsolute && position:absolute). Runs for static frames too.
    self:SyncPivotTranslate_()
end

--- Render the current frame (called automatically by UI framework).
---@param nvg userdata NanoVG context
function Sprite:Render(nvg)
    if self.destroyed_ then return end
    self:RenderFullBackground(nvg)

    if not self.currentSheet_ then return end

    local frameIdx = self.staticFrame_ or self.animator_:GetCurrentFrame()

    -- Cache the frame data lookup: it only changes when the frame index or the
    -- active sheet changes. Static frames and held animation frames re-render
    -- without re-indexing frames_ every frame.
    if frameIdx ~= self.cachedFrameIdx_ or self.currentSheet_ ~= self.cachedSheet_ then
        self.cachedFrameIdx_ = frameIdx
        self.cachedSheet_ = self.currentSheet_
        self.cachedFrameData_ = self.currentSheet_:GetFrame(frameIdx)
    end
    local frameData = self.cachedFrameData_
    if not frameData then return end

    -- Resolve the current frame's page path to an nvgImage handle via ImageCache
    -- (per-page lazy: unrendered pages never fetched; handle 0 = still downloading/DWP).
    local imagePath, atlasW, atlasH = self.currentSheet_:GetPageForFrame(frameIdx)
    if not imagePath or atlasW == 0 or atlasH == 0 then return end
    local handle = ImageCache.Get(imagePath)
    if handle == 0 then return end

    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end

    local fr = frameData.frame
    local offset = frameData.offset
    local srcSize = frameData.sourceSize
    if not srcSize or srcSize.w <= 0 or srcSize.h <= 0 then return end  -- guard div-by-zero

    local scaleX, scaleY = l.w / srcSize.w, l.h / srcSize.h
    local fit = self.props.objectFit

    if fit == "contain" then
        local s = math.min(scaleX, scaleY)
        scaleX, scaleY = s, s
    elseif fit == "cover" then
        local s = math.max(scaleX, scaleY)
        scaleX, scaleY = s, s
    elseif fit == "none" then
        scaleX, scaleY = 1, 1
    end

    local drawW = srcSize.w * scaleX
    local drawH = srcSize.h * scaleY

    -- In-box content alignment (CSS object-position), default center — independent of
    -- the atlas pivot (which is pure data; see GetPivot / applyPivotInAbsolute).
    local px, py = self:ResolveObjectPos_()

    local baseX = l.x + (l.w - drawW) * px
    local baseY = l.y + (l.h - drawH) * py

    local flipX = self.props.flipX and true or false
    local flipY = self.props.flipY and true or false

    local frameX, frameY
    if flipX then
        frameX = baseX + (srcSize.w - offset.x - fr.w) * scaleX
    else
        frameX = baseX + offset.x * scaleX
    end
    if flipY then
        frameY = baseY + (srcSize.h - offset.y - fr.h) * scaleY
    else
        frameY = baseY + offset.y * scaleY
    end
    local frameW = fr.w * scaleX
    local frameH = fr.h * scaleY

    local patW = atlasW * scaleX
    local patH = atlasH * scaleY

    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    if flipX or flipY then
        local tx = flipX and (frameX + frameW) or frameX
        local ty = flipY and (frameY + frameH) or frameY
        nvgTranslate(nvg, tx, ty)
        nvgScale(nvg, flipX and -1 or 1, flipY and -1 or 1)

        local localPatX = -(fr.x * scaleX)
        local localPatY = -(fr.y * scaleY)
        local imgPaint = nvgImagePattern(nvg, localPatX, localPatY, patW, patH, 0, handle, 1)

        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, frameW, frameH)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    else
        local patX = frameX - fr.x * scaleX
        local patY = frameY - fr.y * scaleY
        local imgPaint = nvgImagePattern(nvg, patX, patY, patW, patH, 0, handle, 1)

        nvgBeginPath(nvg)
        nvgRect(nvg, frameX, frameY, frameW, frameH)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    end

    nvgRestore(nvg)
end

--- Destroy the widget. Sheets are owned by the global SpriteSheet cache, so this
--- only drops references — it never frees atlas data (use SpriteSheet.Release /
--- ClearCache for that). Multiple Sprites may share the same cached sheet.
function Sprite:Destroy()
    if self.destroyed_ then return end
    self.destroyed_ = true
    self.animator_:Stop()
    self.animator_:SetChainResolver(nil)

    self.sheets_ = {}
    self.animOrder_ = {}
    self.currentSheet_ = nil
    self.cachedSheet_ = nil
    self.cachedFrameData_ = nil
    self.cachedFrameIdx_ = nil

    Widget.Destroy(self)
end

return Sprite
