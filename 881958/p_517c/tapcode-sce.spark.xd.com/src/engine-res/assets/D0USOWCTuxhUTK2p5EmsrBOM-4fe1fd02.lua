-- ============================================================================
-- SpriteSheet — parsed sprite atlas: frames, animations, pivots, page paths
-- ============================================================================
--
-- The atlas abstraction layer: parses Aseprite / TexturePacker JSON Hash format and
-- holds the atlas DATA — frame crop/trim/sourceSize, named animations, pivots, and
-- each texture page's image PATH — with key-based frame lookup.
--
-- Lives in urhox-libs/Sprite/ (not UI/) so any sprite consumer can share it. It does
-- NOT resolve GPU textures: GetPageForFrame returns a page's image path + atlas dims,
-- and the CONSUMER loads it (the 2D UI Sprite via ImageCache→nvgImage; a future 3D
-- sprite via the engine texture loader). Per-page lazy loading therefore lives on the
-- consumer side — it only resolves the page of the frame currently shown.
--
-- Equivalent to PixiJS Spritesheet — a loaded atlas that produces named frame
-- references (by string key). Multiple sprites can share one cached instance.
--
-- Usage:
--   -- Shared atlas (cached; multiple sprites reference it)
--   local atlas = UI.SpriteSheet("sprites/hero/sprite.json")
--   local s1 = UI.Sprite({ sheet = atlas, frame = "idle_0001" })       -- static frame by key
--   local s2 = UI.Sprite({ sheet = atlas, defaultAnimation = "idle" }) -- animated
--
-- Features (sprite-gen format):
--   * frames: key→data map (Hash) or array; key ({anim}_{num}) is globally unique
--   * animations: top-level ordered array [{name, frames:[keys], repeat, fps, pivot}];
--     each animation references its frames BY KEY (order/membership explicit), so a
--     merged multi-animation sheet, a per-animation file, or a virtual sprite.json
--     entry all resolve identically — first animation is the default
--   * relatedMultiPacks: recursively loaded & merged (pages of one anim, sibling
--     animation sheets, or a virtual entry's children — all unified by key)
--   * transparent-pixel trim offset restoration
--   * module-level cache: same path returns same instance (SpriteSheet.Load)
--
-- Industry reference: PixiJS Spritesheet + Phaser TextureManager.
-- ============================================================================

--- Parse a pivot value into a normalized {x, y} table, or nil.
-- Contract (TexturePacker-aligned): pivot is normalized [0,1] relative to sourceSize
-- with a top-left origin. Accepts either a bare {x, y} or the self-describing
-- meta block { space, unit, origin, x, y } — only x/y are read; the descriptor
-- fields are treated as the fixed format contract.
---@param p table|nil
---@return {x: number, y: number}|nil
local function parsePivot(p)
    if type(p) ~= "table" then return nil end
    local x, y = p.x, p.y
    if type(x) == "number" and type(y) == "number" then
        return { x = x, y = y }
    end
    return nil
end

--- Normalize an animation repeat count: <=0 → 0 (infinite loop), N>=1 → play N times.
-- Accepts a number (sprite-gen) or string ("" = infinite, "3" = 3x; legacy Aseprite).
---@param rep any
---@return number
local function normalizeRepeat(rep)
    if type(rep) == "number" then return rep <= 0 and 0 or rep end
    if type(rep) == "string" then return (rep == "") and 0 or (tonumber(rep) or 0) end
    return 0
end

-- ============================================================================
-- Types
-- ============================================================================

---@class SpriteFrameData
---@field name string Frame name / key (e.g. "attack_0001")
---@field page number Texture page index (0-based)
---@field frame {x: number, y: number, w: number, h: number} Crop rect in atlas
---@field offset {x: number, y: number} Trim offset (restores original canvas position)
---@field sourceSize {w: number, h: number} Original frame size (before trim)
---@field duration number Frame duration in milliseconds
---@field rotated boolean Whether packed rotated (not currently handled)
---@field pivot {x: number, y: number}|nil Per-frame pivot override (normalized, sourceSize space)

---@class SpriteAnimationDef
---@field name string Animation name
---@field frameIndices number[] Ordered 1-based indices into frames_ (resolved from the animation's frame-key list; may be non-contiguous)
---@field direction "forward"|"reverse"|"pingpong" Playback direction
---@field repeatCount number Repeat count (0 = infinite loop)
---@field fps number|nil Optional uniform fps hint (per-frame duration is the source of truth)
---@field pivot {x: number, y: number}|nil Per-animation pivot (falls back to its sheet's meta.pivot at parse)

---@class SpritePageInfo
---@field imagePath string Page image path; the consumer resolves it to a texture (its own cache key)
---@field width number Atlas width from meta.size (authoritative; placeholder texture size is ignored)
---@field height number Atlas height from meta.size

-- ============================================================================
-- SpriteSheet Class
-- ============================================================================

---@class SpriteSheet
---@field private jsonPath_ string
---@field private basePath_ string
---@field private pages_ SpritePageInfo[]
---@field private frames_ SpriteFrameData[]
---@field private frameMap_ table<string, number> Frame key → 1-based index
---@field private animations_ table<string, SpriteAnimationDef> name → resolved def
---@field private animOrder_ string[] Animation names in declaration order (first = default)
---@field private sourceSize_ {w: number, h: number}|nil
---@field private pivot_ {x: number, y: number}|nil Entry sheet's meta.pivot (sheet-wide fallback)
local SpriteSheet = {}
SpriteSheet.__index = SpriteSheet

--- Module-level atlas cache: path → SpriteSheet instance.
---@type table<string, SpriteSheet>
local sheetCache_ = {}

-- ============================================================================
-- Constructors
-- ============================================================================

--- Load a SpriteSheet from the global cache (recommended).
-- Same path always returns the same instance — parsed once, shared by every
-- Sprite that references it (like ImageCache for textures or PixiJS Assets).
-- The cache OWNS the instance; sheets stay resident until SpriteSheet.Release(path)
-- or SpriteSheet.ClearCache(). Sprites only reference sheets, never free them.
---@param jsonPath string Spritesheet JSON path (relative to ResourceCache)
---@return SpriteSheet|nil # Cached instance on success, nil on failure
function SpriteSheet.Load(jsonPath)
    local cached = sheetCache_[jsonPath]
    if cached then
        return cached
    end

    local sheet = SpriteSheet.New(jsonPath)
    if not sheet then return nil end

    sheetCache_[jsonPath] = sheet
    return sheet
end

--- Create a new (uncached) SpriteSheet instance.
-- Use SpriteSheet.Load() for shared atlases; use New() only when you need a
-- private instance that won't be shared or cached.
---@param jsonPath string Spritesheet JSON path (relative to ResourceCache)
---@return SpriteSheet|nil # Instance on success, nil on failure
function SpriteSheet.New(jsonPath)
    local self = setmetatable({}, SpriteSheet)
    self.jsonPath_ = jsonPath
    self.basePath_ = jsonPath:match("^(.*/)") or ""
    self.pages_ = {}
    self.frames_ = {}
    self.frameMap_ = {}
    self.animations_ = {}
    self.animOrder_ = {}
    self.sourceSize_ = nil
    self.pivot_ = nil          -- entry sheet's meta.pivot (sheet-wide fallback)
    self.pendingAnims_ = {}    -- raw anim defs (key lists), resolved to indices after load

    -- Recursively load the entry file + everything its relatedMultiPacks reference.
    -- frames merge into one global key→data map (keys are globally unique); animations
    -- merge by name. Load order only affects positional frame indices, never animation
    -- membership — animations reference frames by KEY and are resolved after every
    -- file is loaded, so a merged sheet / virtual sprite.json / multipage atlas all
    -- collapse into one consistent model.
    if not self:LoadRecursive_(jsonPath, {}) then
        return nil
    end

    -- Nothing usable loaded (empty/malformed sheet, or a virtual entry whose
    -- referenced packs all failed) → fail soft as nil, like a parse error.
    if #self.frames_ == 0 then
        return nil
    end

    self:ResolveAnimations_()

    -- No animations declared but frames exist → synthesize a "default" spanning
    -- every frame in load order (untagged / static atlas).
    if #self.animOrder_ == 0 and #self.frames_ > 0 then
        local idx = {}
        for i = 1, #self.frames_ do idx[i] = i end
        self.animations_["default"] = {
            name = "default", frameIndices = idx,
            direction = "forward", repeatCount = 0, fps = nil, pivot = self.pivot_,
        }
        self.animOrder_[1] = "default"
    end

    self.pendingAnims_ = nil
    return self
end

---@private
--- Load a file and (depth-first) everything in its relatedMultiPacks. Visited-set
--- guards against cycles / diamond re-loads. Only the ENTRY file's parse failure
--- aborts construction; a missing/bad related pack just warns.
---@param jsonPath string
---@param visited table<string, boolean>
---@return boolean # entry parse ok
function SpriteSheet:LoadRecursive_(jsonPath, visited)
    if visited[jsonPath] then return true end
    visited[jsonPath] = true

    local ok, rmp, fileBase = self:Parse_(jsonPath)
    if not ok then return false end

    for _, packName in ipairs(rmp) do
        local packPath = fileBase .. packName
        -- Probe with Exists first so a missing declared pack doesn't make
        -- cache:GetFile log a spurious "Could not find resource" error.
        if cache:Exists(packPath) then
            self:LoadRecursive_(packPath, visited)
        elseif log then
            log:Write(LOG_WARNING, "[SpriteSheet] related pack missing: " .. tostring(packPath))
        end
    end
    return true
end

---@private
--- Parse one JSON file: append its frames (as a new texture page) and collect its
--- animations (resolved later). Returns (ok, relatedMultiPacks, fileBaseDir).
---@param jsonPath string
---@return boolean ok
---@return string[] relatedMultiPacks
---@return string fileBaseDir
function SpriteSheet:Parse_(jsonPath)
    local file = cache:GetFile(jsonPath)
    if not file then return false, {}, "" end
    local content = file:ReadString()
    file:Close()
    if not content or content == "" then return false, {}, "" end

    local ok, data = pcall(cjson.decode, content)
    if not ok or not data then return false, {}, "" end

    local meta = data.meta or {}
    local fileBase = jsonPath:match("^(.*/)") or ""

    -- This file's pivot is the fallback for ITS OWN animations; the first file's
    -- meta.pivot also becomes the sheet-wide last-resort pivot.
    local fileMetaPivot = parsePivot(meta.pivot)
    if self.pivot_ == nil then self.pivot_ = fileMetaPivot end

    -- frames may be a hash {key:{...}}, an array [{filename,...}], or empty/absent
    -- for a virtual entry (sprite.json) that only aggregates via relatedMultiPacks.
    local frames = data.frames
    local hasFrames = type(frames) == "table" and next(frames) ~= nil

    -- A texture page exists only for files that carry frames; the virtual entry has none.
    local pageIndex = nil
    if hasFrames then
        self.pages_[#self.pages_ + 1] = {
            imagePath = fileBase .. (meta.image or "spritesheet.png"),
            width = meta.size and meta.size.w or 0,
            height = meta.size and meta.size.h or 0,
        }
        pageIndex = #self.pages_ - 1  -- 0-based

        local ordered = {}
        if #frames > 0 then
            for _, entry in ipairs(frames) do
                ordered[#ordered + 1] = { name = entry.filename or entry.name or ("frame_" .. #ordered), data = entry }
            end
        else
            -- Hash form: order is irrelevant (animations reference frames by key),
            -- but sort for a stable frames_ layout / deterministic "default".
            local names = {}
            for name in pairs(frames) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do ordered[#ordered + 1] = { name = name, data = frames[name] } end
        end

        for _, e in ipairs(ordered) do
            local f = e.data
            local fr = f.frame
            local sss = f.spriteSourceSize or { x = 0, y = 0, w = fr.w, h = fr.h }
            local ss = f.sourceSize or { w = fr.w, h = fr.h }
            self.frames_[#self.frames_ + 1] = {
                name = e.name,
                page = pageIndex,
                frame = { x = fr.x, y = fr.y, w = fr.w, h = fr.h },
                offset = { x = sss.x, y = sss.y },
                sourceSize = { w = ss.w, h = ss.h },
                duration = f.duration or 42,
                rotated = f.rotated or false,
                pivot = parsePivot(f.pivot),
            }
            self.frameMap_[e.name] = #self.frames_
            if not self.sourceSize_ then self.sourceSize_ = { w = ss.w, h = ss.h } end
        end
    end

    -- Collect animations (frame KEYS now; resolved to indices once all frames loaded).
    if type(data.animations) == "table" then
        for _, a in ipairs(data.animations) do
            if type(a) == "table" and a.name and type(a.frames) == "table" then
                self.pendingAnims_[#self.pendingAnims_ + 1] = {
                    name = a.name,
                    frames = a.frames,
                    direction = a.direction or "forward",
                    repeatCount = normalizeRepeat(a["repeat"]),
                    fps = a.fps,
                    pivot = parsePivot(a.pivot) or fileMetaPivot,
                }
            elseif log then
                log:Write(LOG_WARNING, "[SpriteSheet] animation entry missing name/frames in " .. tostring(jsonPath))
            end
        end
    end

    -- Accept camelCase (sprite-gen) and snake_case (TexturePacker).
    local rmp = meta.relatedMultiPacks or meta.related_multi_packs or {}
    return true, rmp, fileBase
end

---@private
--- Resolve collected animations' frame KEY lists into 1-based frames_ indices,
--- in declaration order. First definition of a name wins; duplicates/unknown keys warn.
function SpriteSheet:ResolveAnimations_()
    for _, a in ipairs(self.pendingAnims_) do
        if self.animations_[a.name] ~= nil then
            if log then
                log:Write(LOG_WARNING, "[SpriteSheet] duplicate animation name ignored: " .. tostring(a.name))
            end
        else
            local idx = {}
            for _, key in ipairs(a.frames) do
                local fi = self.frameMap_[key]
                if fi then
                    idx[#idx + 1] = fi
                elseif log then
                    log:Write(LOG_WARNING, "[SpriteSheet] animation '" .. tostring(a.name)
                        .. "' references unknown frame key: " .. tostring(key))
                end
            end
            if #idx > 0 then
                self.animations_[a.name] = {
                    name = a.name,
                    frameIndices = idx,
                    direction = a.direction,
                    repeatCount = a.repeatCount,
                    fps = a.fps,
                    pivot = a.pivot,
                }
                self.animOrder_[#self.animOrder_ + 1] = a.name
            end
        end
    end
end

-- ============================================================================
-- Public API — Frame Access (equivalent to PixiJS sheet.textures['key'])
-- ============================================================================

--- Get total frame count (across all pages).
---@return number
function SpriteSheet:GetFrameCount()
    if not self.frames_ then return 0 end
    return #self.frames_
end

--- Get frame data at the given index.
---@param index number 1-based frame index
---@return SpriteFrameData|nil
function SpriteSheet:GetFrame(index)
    if not self.frames_ then return nil end
    return self.frames_[index]
end

--- Get frame data by key name (equivalent to PixiJS sheet.textures['frameName']).
---@param key string Frame key from the JSON frames hash (e.g. "attack_0001")
---@return SpriteFrameData|nil
function SpriteSheet:GetFrameByKey(key)
    if not self.frameMap_ then return nil end
    local idx = self.frameMap_[key]
    if idx then return self.frames_[idx] end
    return nil
end

--- Get frame index by key name.
---@param key string Frame key name
---@return number|nil # 1-based index, nil if not found
function SpriteSheet:GetFrameIndex(key)
    if not self.frameMap_ then return nil end
    return self.frameMap_[key]
end

--- Get all frame keys (equivalent to Object.keys(sheet.textures) in PixiJS).
---@return string[]
function SpriteSheet:GetFrameKeys()
    local keys = {}
    if not self.frames_ then return keys end
    for i, f in ipairs(self.frames_) do
        keys[i] = f.name
    end
    return keys
end

--- Get the uniform source size (from the first frame's sourceSize).
---@return {w: number, h: number}|nil
function SpriteSheet:GetSourceSize()
    return self.sourceSize_
end

--- Get the atlas-level default pivot (meta.pivot), normalized in sourceSize space
--- with a top-left origin. Per-frame pivots (SpriteFrameData.pivot) take priority.
---@return {x: number, y: number}|nil
function SpriteSheet:GetPivot()
    return self.pivot_
end

-- ============================================================================
-- Public API — Animation Definitions
-- ============================================================================

--- Get animation definition by name.
---@param name string Animation name (from the `animations` array, or "default")
---@return SpriteAnimationDef|nil
function SpriteSheet:GetAnimation(name)
    if not self.animations_ then return nil end
    return self.animations_[name]
end

--- Get the first available animation name. Returns the first entry of the
--- `animations` array in declaration order (the conventional default), or
--- "default" for a sheet with no animations declared.
---@return string|nil
function SpriteSheet:GetFirstAnimationName()
    if not self.animOrder_ then return nil end
    return self.animOrder_[1]
end

--- Get all available animation names, in `animations` declaration order.
---@return string[]
function SpriteSheet:GetAnimationNames()
    local names = {}
    if not self.animOrder_ then return names end
    for i, name in ipairs(self.animOrder_) do
        names[i] = name
    end
    return names
end

--- Total duration (ms) of a named animation = sum of its frames' durations.
---@param name string
---@return number
function SpriteSheet:GetAnimationDuration(name)
    local anim = self.animations_ and self.animations_[name]
    if not anim then return 0 end
    local total = 0
    for _, fi in ipairs(anim.frameIndices) do
        local f = self.frames_[fi]
        if f then total = total + f.duration end
    end
    return total
end

-- ============================================================================
-- Public API — Page Lookup
-- ============================================================================

--- Get the image PATH + atlas dimensions of the page a given frame lives on. Pure
--- data — the consumer resolves the texture (the UI Sprite via ImageCache, a 3D
--- sprite via the engine texture loader). Returns only the current frame's page, so
--- the consumer fetches just that one (per-page lazy).
--- Atlas dims are meta.size (authoritative, known at parse — not the live texture size).
---@param index number 1-based frame index
---@return string|nil imagePath Page image path (nil = invalid frame / no page)
---@return number atlasW Atlas width (meta.size; 0 when invalid)
---@return number atlasH Atlas height (0 when invalid)
function SpriteSheet:GetPageForFrame(index)
    if not self.frames_ then return nil, 0, 0 end
    local f = self.frames_[index]
    if not f then return nil, 0, 0 end
    local page = self.pages_[f.page + 1]
    if not page then return nil, 0, 0 end
    return page.imagePath, page.width, page.height
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

--- Free this sheet's data and drop it from the cache. Idempotent.
-- Sprites do NOT call this — they only reference sheets. Use it (or the
-- path-based Release / ClearCache) for explicit unloading. Any Sprite still
-- referencing a destroyed sheet renders blank (all accessors are nil-guarded).
function SpriteSheet:Destroy()
    if not self.frames_ then return end  -- already destroyed
    if self.jsonPath_ and sheetCache_[self.jsonPath_] == self then
        sheetCache_[self.jsonPath_] = nil
    end
    self.pages_ = nil
    self.frames_ = nil
    self.frameMap_ = nil
    self.animations_ = nil
    self.animOrder_ = nil
    -- Also clear sheet-level fallbacks so a Sprite still holding this destroyed sheet
    -- doesn't read stale size/pivot via GetSourceSize/GetPivot (which would let
    -- ApplyIntrinsicSize_ push an outdated box to Yoga).
    self.sourceSize_ = nil
    self.pivot_ = nil
end

--- Unload a cached sheet by path (PixiJS Assets.unload style). No-op if absent.
---@param jsonPath string
function SpriteSheet.Release(jsonPath)
    local sheet = sheetCache_[jsonPath]
    if sheet then sheet:Destroy() end
end

--- Clear ALL cached SpriteSheet instances. Call on scene teardown.
-- Frees only the lightweight frame metadata; the actual PNG texture memory lives
-- in ImageCache and is released separately (ImageCache.Clear / Release).
function SpriteSheet.ClearCache()
    for _, sheet in pairs(sheetCache_) do
        sheet.pages_ = nil
        sheet.frames_ = nil
        sheet.frameMap_ = nil
        sheet.animations_ = nil
        sheet.animOrder_ = nil
        sheet.sourceSize_ = nil
        sheet.pivot_ = nil
    end
    sheetCache_ = {}
end

-- Make SpriteSheet callable: SpriteSheet("path") = SpriteSheet.Load("path")
setmetatable(SpriteSheet, {
    __call = function(_, jsonPath)
        return SpriteSheet.Load(jsonPath)
    end,
})

return SpriteSheet
