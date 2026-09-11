-- i18n - Internationalization runtime support
--
-- Provides global _tr() function for translated string lookup with
-- automatic rendering hook injection. All text that reaches the screen
-- passes through _tr(), which translates hash keys (t_xxx) to localized text.
--
-- Build tool injects _tr() calls in Lua source:
--   _tr("t_1710742800_x3f2")              -- simple lookup
--   _tr("t_1710742801_a8d1", count, name) -- with {0}{1} placeholders
--
-- JSON/XML values are replaced with hash keys directly (t_xxx).
-- Rendering hooks (nvgText, Text3D:SetText) call _tr() transparently,
-- so hash keys from data files are translated at display time.
--
-- Config file: i18n.json (render-blocking, minimal subset of build config)
--   { "source_lang": "zh_CN", "target_langs": ["en", "ja"] }
--
-- Translation files: i18n/{lang}.json (not render-blocking, loaded on demand)
--
-- Language preference: {project_root}/user_lang (plain text, via C++ Localization)
--
-- Language resolution:
--   actualLang cache > user_lang file > -lang > server intl game VM en > system language > source_lang

local i18n = {}

-- Translation table: hash_key -> translated text
local translations_ = {}

-- Source-language table for fit width ratios (separate from active translations_).
local sourceTranslations_ = {}

-- Dedup input for SetLanguage (prevents redundant reload)
local requestLang_ = nil

-- Resolved language currently in effect
local actualLang_ = nil

-- translated value -> provenance. Static entries have no lastAccessFrame.
-- scaleCache is the quantized width ratio only; min font floor is applied per draw.
local translatedTextProvenanceCache_ = {}
local dynamicTranslatedTextProvenanceCount_ = 0
local nextDynamicTranslationProvenanceSweepFrame_ = 0
local DYNAMIC_TRANSLATION_PROVENANCE_MAX_ENTRIES = 2048
local DYNAMIC_TRANSLATION_PROVENANCE_TTL_FRAMES = 600
local DYNAMIC_TRANSLATION_PROVENANCE_SWEEP_INTERVAL = 120

-- Equal partition of (0,1]: scale_i = (STEPS-i)/STEPS, midpoint-rounded.
local NVG_TEXT_FIT_STEPS = 8
-- Min floor is the dpr-normalized font size in the author's coordinate space:
--   cssFs = nvgFontSize * (beginFrameRatio / systemDpr)
-- Mode B (default): BeginFrame(log, log, dpr) → cssFs = F
-- Mode C: BeginFrame(phys, phys, 1) → cssFs = F / systemDpr
-- Author transforms (nvgScale design scale / shrink animations) are intent and
-- hit source and translated text alike — the floor deliberately ignores them.
-- It only bounds i18n's own width-ratio shrink relative to the source text.
local NVG_TEXT_MIN_FONT_SIZE = 7          -- dpr-normalized relative floor (capped at 1)
local NVG_TEXT_MIN_SOURCE_CHARACTERS = 4
-- No-provenance fallback: long strings use lerp(avgAppliedScale, 1, t).
-- Length gate is raw string length (#s) — coarse filter only, not glyph count.
local NVG_TEXT_UNKNOWN_PROVENANCE_MIN_LEN = 10
local NVG_TEXT_UNKNOWN_PROVENANCE_DEFAULT_SCALE = 0.8
local NVG_TEXT_UNKNOWN_PROVENANCE_LERP_TO_ONE = 0.25
local nvgTextFitEnabled_ = false
local appliedFitScaleSum_ = 0
local appliedFitScaleCount_ = 0
-- translationKey -> true once that key has contributed to the unknown-fallback
-- average. Dynamic provenance TTL may drop and recreate metadata for the same
-- formatted result; without this gate the same template would be counted again.
local recordedFitScaleKeys_ = {}

local function selectNvgTextFitScale(requiredScale)
    local steps = NVG_TEXT_FIT_STEPS
    if type(requiredScale) ~= "number" then
        return 1
    end
    if requiredScale >= 1 then
        return 1
    end
    -- scales: 1, (n-1)/n, ..., 1/n
    for i = 0, steps - 2 do
        local largerScale = (steps - i) / steps
        local smallerScale = (steps - i - 1) / steps
        if requiredScale >= (largerScale + smallerScale) * 0.5 then
            return largerScale
        end
    end
    return 1 / steps
end

local function recordAppliedFitScale(scale, translationKey)
    if type(scale) ~= "number" or scale >= 1 or scale <= 0 then
        return
    end
    -- One sample per translation key (template ratio), not per cache-miss /
    -- dynamic-string instance. Prevents TTL recreate from re-weighting avg.
    if type(translationKey) == "string" and translationKey ~= "" then
        if recordedFitScaleKeys_[translationKey] then
            return
        end
        recordedFitScaleKeys_[translationKey] = true
    end
    appliedFitScaleSum_ = appliedFitScaleSum_ + scale
    appliedFitScaleCount_ = appliedFitScaleCount_ + 1
end

local function unknownProvenanceFitScale()
    local averageScale = appliedFitScaleCount_ > 0
        and (appliedFitScaleSum_ / appliedFitScaleCount_)
        or NVG_TEXT_UNKNOWN_PROVENANCE_DEFAULT_SCALE
    local t = NVG_TEXT_UNKNOWN_PROVENANCE_LERP_TO_ONE
    return averageScale * (1 - t) + 1.0 * t
end

-- Snapshot Time: games may overwrite global `time`.
local engineTime_ = time

local function getCurrentFrameNumber()
    return engineTime_ and engineTime_.frameNumber or 0
end

local function clearTranslationFitCaches()
    translatedTextProvenanceCache_ = {}
    dynamicTranslatedTextProvenanceCount_ = 0
    nextDynamicTranslationProvenanceSweepFrame_ = 0
    appliedFitScaleSum_ = 0
    appliedFitScaleCount_ = 0
    recordedFitScaleKeys_ = {}
end

local function hasSourceTranslationPair()
    for translationKey in pairs(sourceTranslations_) do
        if translations_[translationKey] ~= nil then
            return true
        end
    end
    return false
end

local function sweepDynamicTranslatedTextProvenance(frameNumber, force)
    if not force and frameNumber < nextDynamicTranslationProvenanceSweepFrame_ then
        return
    end

    if frameNumber > 0 then
        local oldestActiveFrame = frameNumber - DYNAMIC_TRANSLATION_PROVENANCE_TTL_FRAMES
        for translatedText, metadata in pairs(translatedTextProvenanceCache_) do
            if metadata.lastAccessFrame
                and metadata.lastAccessFrame < oldestActiveFrame
            then
                translatedTextProvenanceCache_[translatedText] = nil
                dynamicTranslatedTextProvenanceCount_
                    = dynamicTranslatedTextProvenanceCount_ - 1
            end
        end
    end

    nextDynamicTranslationProvenanceSweepFrame_
        = frameNumber + DYNAMIC_TRANSLATION_PROVENANCE_SWEEP_INTERVAL
end

local function canRecordTranslatedTextProvenance(translatedText, translationKey)
    -- Always record real _tr results (Label/source lookup needs this even if
    -- nvg text fit is off).
    if type(translatedText) ~= "string"
        or translatedText == ""
        or type(translationKey) ~= "string"
        or translationKey == ""
    then
        return false
    end
    return true
end

local function recordStaticTranslatedTextProvenance(translatedText, translationKey)
    if not canRecordTranslatedTextProvenance(translatedText, translationKey) then
        return nil
    end

    local metadata = translatedTextProvenanceCache_[translatedText]
    if metadata then
        if metadata.lastAccessFrame then
            dynamicTranslatedTextProvenanceCount_
                = dynamicTranslatedTextProvenanceCount_ - 1
            metadata.lastAccessFrame = nil
        end
        if metadata.translationKey ~= translationKey then
            metadata.scaleCache = nil
        end
        metadata.translationKey = translationKey
        return metadata
    end

    metadata = {
        translationKey = translationKey,
    }
    translatedTextProvenanceCache_[translatedText] = metadata
    return metadata
end

local function recordDynamicTranslatedTextProvenance(translatedText, translationKey)
    if not canRecordTranslatedTextProvenance(translatedText, translationKey) then
        return nil
    end

    local frameNumber = getCurrentFrameNumber()
    sweepDynamicTranslatedTextProvenance(frameNumber, false)

    local metadata = translatedTextProvenanceCache_[translatedText]
    if metadata then
        -- A stable translation is authoritative and must never be replaced by
        -- a coincidentally equal dynamic result.
        if not metadata.lastAccessFrame then return metadata end
        if metadata.translationKey ~= translationKey then
            metadata.scaleCache = nil
        end
        metadata.translationKey = translationKey
        metadata.lastAccessFrame = frameNumber
        return metadata
    end

    if dynamicTranslatedTextProvenanceCount_
        >= DYNAMIC_TRANSLATION_PROVENANCE_MAX_ENTRIES
    then
        sweepDynamicTranslatedTextProvenance(frameNumber, true)
        if dynamicTranslatedTextProvenanceCount_
            >= DYNAMIC_TRANSLATION_PROVENANCE_MAX_ENTRIES
        then
            return nil
        end
    end

    metadata = {
        translationKey = translationKey,
        lastAccessFrame = frameNumber,
    }
    translatedTextProvenanceCache_[translatedText] = metadata
    dynamicTranslatedTextProvenanceCount_
        = dynamicTranslatedTextProvenanceCount_ + 1
    return metadata
end

local function findTranslatedTextProvenance(translatedText)
    local metadata = translatedTextProvenanceCache_[translatedText]
    if metadata and metadata.lastAccessFrame then
        metadata.lastAccessFrame = getCurrentFrameNumber()
    end
    return metadata
end

-- ============================================================
-- Core: _tr()
-- ============================================================

local function format_placeholders(text, ...)
    local args = {...}
    if #args == 0 then
        return text
    end
    return (text:gsub("{(%d+)}", function(idx)
        local arg = args[tonumber(idx) + 1]
        return arg ~= nil and tostring(arg) or ""
    end))
end

local function translateOnly(key, ...)
    if key == nil then return "", nil end
    local translatedTemplate = translations_[key]
    if translatedTemplate == nil then
        if select('#', ...) > 0 then
            return format_placeholders(key, ...), nil
        end
        return key, nil
    end
    if select('#', ...) > 0 then
        return format_placeholders(translatedTemplate, ...), key
    end
    return translatedTemplate, key
end

local function resolveTranslatedTextProvenance(text)
    local translatedText, translationKey = translateOnly(text)
    local metadata
    if translationKey then
        metadata = recordStaticTranslatedTextProvenance(
            translatedText, translationKey)
    else
        metadata = findTranslatedTextProvenance(translatedText)
    end
    return translatedText, metadata
end

--- Global translation function.
-- @param key string Hash key (e.g. "t_VEeXsa8AyD") or plain text
-- @param ... any Format arguments for {0}, {1}, ... placeholders
-- @return string Translated and formatted text
local function _tr_impl(key, ...)
    local translatedText, translationKey = translateOnly(key, ...)
    if translationKey then
        if select('#', ...) == 0 then
            recordStaticTranslatedTextProvenance(translatedText, translationKey)
        else
            recordDynamicTranslatedTextProvenance(translatedText, translationKey)
        end
    end
    return translatedText
end

-- Default: passthrough, switched to _tr_impl when i18nConfig_ exists
function _tr(key) return key or "" end

--- Passthrough — marks text as "do not translate".
-- Also serves as safety net: if i18n is disabled after a build that
-- injected _raw() calls, the function still exists.
-- @param text string
-- @return string
function _raw(text)
    return text
end

-- ============================================================
-- Rendering hooks
-- ============================================================

local originalNvgText_ = nil
local originalNvgTextBox_ = nil
local originalNvgTextBounds_ = nil
local originalNvgTextBoxBounds_ = nil
local originalNvgFontSize_ = nil
local getCurrentNvgFontSize_ = nil
local hooksInstalled_ = false
local nvgTextFitHooksInstalled_ = false

local nvgTextStateByContext_ = setmetatable({}, { __mode = "k" })
local lastNvgTextContext_ = nil
local lastNvgTextState_ = nil
-- Per-context unitsToCss (= beginFrameRatio / systemDpr), computed once per
-- nvgBeginFrame so the per-draw floor check is a single weak-table read.
local unitsToCssByContext_ = setmetatable({}, { __mode = "k" })

local NANO_VG_MAX_STATE_DEPTH = 32

local function isPositiveFiniteNumber(value)
    return type(value) == "number"
        and value > 0
        and value == value
        and math.abs(value) ~= math.huge
end

-- Per-frame precompute (called from the BeginFrame wrapper): both factors of
-- unitsToCss are frame constants, so the per-draw path never touches Graphics.
-- The quotient check covers the desktop dpr_ = width/logicWidth path, which
-- has no zero guard in C++ (Android/OHOS fall back to 1.0 engine-side).
local function rememberBeginFrameRatio(ctx, devicePxRatio)
    if isPositiveFiniteNumber(devicePxRatio) then
        local unitsToCss = devicePxRatio / graphics:GetDPR()
        if isPositiveFiniteNumber(unitsToCss) then
            unitsToCssByContext_[ctx] = unitsToCss
        end
    end
end

-- User-space font size → dpr-normalized size (inverse of nvg-resolution-mode).
-- unitsToCss = beginFrameRatio / systemDpr, precomputed per BeginFrame.
-- Author transforms (nvgCurrentTransform) are intentionally excluded: they
-- apply to source and translated text alike, so the floor works in the
-- author's coordinate space and never fights shrink animations or
-- design-resolution scaling. Never-seen ctx (hooks installed after the first
-- BeginFrame) falls back to 1 — same as assuming mode B.
local function getUnitsToCssLogical(ctx)
    return unitsToCssByContext_[ctx] or 1
end

local function createNvgTextState()
    return {
        fontSize = 16,
        nativeStateDepth = 1,
        savedStateCount = 0,
        savedFontSizes = {},
    }
end

local function getNvgTextState(ctx)
    if ctx == lastNvgTextContext_ then
        return lastNvgTextState_
    end
    local state = nvgTextStateByContext_[ctx]
    if not state then
        state = createNvgTextState()
        nvgTextStateByContext_[ctx] = state
    end
    lastNvgTextContext_ = ctx
    lastNvgTextState_ = state
    return state
end

local function invalidateNvgTranslationFitScales()
    for _, metadata in pairs(translatedTextProvenanceCache_) do
        metadata.scaleCache = nil
    end
    -- Font/metric changes make prior width ratios stale; drop the unknown-
    -- provenance average so it is resampled under the new metrics.
    appliedFitScaleSum_ = 0
    appliedFitScaleCount_ = 0
    recordedFitScaleKeys_ = {}
end

local function setTrackedFontSize(ctx, fontSize)
    local state = getNvgTextState(ctx)
    state.fontSize = fontSize
end

local function pushTrackedNvgTextState(ctx)
    local state = getNvgTextState(ctx)
    if state.nativeStateDepth >= NANO_VG_MAX_STATE_DEPTH then return end

    local index = state.savedStateCount + 1
    state.savedStateCount = index
    state.nativeStateDepth = state.nativeStateDepth + 1
    state.savedFontSizes[index] = state.fontSize
end

local function popTrackedNvgTextState(ctx)
    local state = getNvgTextState(ctx)
    if state.nativeStateDepth <= 1 or state.savedStateCount <= 0 then return end

    local index = state.savedStateCount
    state.fontSize = state.savedFontSizes[index]
    state.savedStateCount = index - 1
    state.nativeStateDepth = state.nativeStateDepth - 1
end

local function resetTrackedNvgTextState(ctx)
    local state = getNvgTextState(ctx)
    state.fontSize = 16
end

local function beginTrackedNvgTextFrame(ctx)
    local state = getNvgTextState(ctx)
    state.fontSize = 16
    state.nativeStateDepth = 1
    state.savedStateCount = 0
end

-- Min floor is the dpr-normalized font size (inverse of nvg-resolution-mode):
--   cssFs = fontSize * (beginFrameRatio / systemDpr)
--   floorScale = min(1, MIN / cssFs); final = max(widthScale, floorScale)
-- RELATIVE bound, capped at 1: the floor is a brake on i18n's own width-ratio
-- shrink, never an enlarger. Author sizes are both the ceiling and the
-- baseline — an author size already at/below MIN yields floorScale = 1,
-- which also suppresses the width-ratio shrink entirely (keep author size).
-- Author transforms (nvgScale design upscaling, shrink animations) are
-- deliberately excluded: they scale source and translated text equally and
-- stay author-owned; with the cap at 1 this exclusion is safe — the floor
-- can never push a size beyond what the author wrote.
-- Width-ratio scale is cached on metadata; floor is applied per draw because
-- the same translation can be drawn at different fontSize / BeginFrame ratio.
-- Fast path: scale >= 1 never needs the floor (it could only lower it).
local function applyNvgTextMinFontSize(ctx, scale, fontSize)
    if type(scale) ~= "number" or scale <= 0 then return scale end
    if scale >= 1 then
        return scale
    end
    if type(fontSize) ~= "number" or fontSize <= 0 then return scale end

    local floorCss = NVG_TEXT_MIN_FONT_SIZE
    if type(floorCss) ~= "number" or floorCss <= 0 then
        return scale
    end

    local cssFs = fontSize * getUnitsToCssLogical(ctx)
    if not isPositiveFiniteNumber(cssFs) then
        return scale
    end

    local floorScale = math.min(1, floorCss / cssFs)
    return math.max(scale, floorScale)
end

local function getTranslationFitScale(ctx, metadata)
    -- Single-line source/target width ratio; short sources use 4-char baseline.
    -- Cached on metadata.scaleCache (width ratio only — not CSS floor).
    -- Source/target both come from translation-key tables (t_xxx → text).
    -- No plain-text-key fallback: packages and server must ship real keys +
    -- source-language runtime table for width ratios.
    local cachedScale = metadata.scaleCache
    if cachedScale ~= nil then return cachedScale end

    local translationKey = metadata.translationKey
    local sourceTemplate = translationKey and sourceTranslations_[translationKey] or nil
    local targetTemplate = translationKey and translations_[translationKey] or nil
    local scale = 1
    if type(sourceTemplate) == "string"
        and type(targetTemplate) == "string"
        and not sourceTemplate:find("[\r\n]")
        and not targetTemplate:find("[\r\n]")
    then
        local sourceWidth = originalNvgTextBounds_(ctx, 0, 0, sourceTemplate)
        local targetWidth = originalNvgTextBounds_(ctx, 0, 0, targetTemplate)
        local sourceCharacterCount = utf8.len(sourceTemplate)
        if sourceCharacterCount and sourceCharacterCount > 0
            and sourceCharacterCount < NVG_TEXT_MIN_SOURCE_CHARACTERS
        then
            sourceWidth = sourceWidth / sourceCharacterCount
                * NVG_TEXT_MIN_SOURCE_CHARACTERS
        end
        if sourceWidth > 0 and targetWidth > sourceWidth then
            scale = selectNvgTextFitScale(sourceWidth / targetWidth)
        end
    end

    metadata.scaleCache = scale
    if scale < 1 then
        recordAppliedFitScale(scale, translationKey)
    end
    return scale
end

local function resolveNvgTextFitScale(
        ctx, metadata, fontSize, translatedText)
    local widthScale = 1
    if metadata then
        widthScale = getTranslationFitScale(ctx, metadata)
    elseif type(translatedText) == "string"
        -- Coarse length gate only; # is enough (no utf8.len).
        and #translatedText > NVG_TEXT_UNKNOWN_PROVENANCE_MIN_LEN
    then
        -- Unknown-provenance uses running avg of applied width scales
        -- (not cached per string).
        widthScale = unknownProvenanceFitScale()
    end
    -- Relative floor (capped at 1): brakes the shrink, never enlarges.
    return applyNvgTextMinFontSize(ctx, widthScale, fontSize)
end

local function drawTranslatedNvgText(
        ctx, x, y, translatedText, textEnd, metadata, additionalI18nFit)
    if not additionalI18nFit or not nvgTextFitEnabled_
        or textEnd ~= nil
    then
        return originalNvgText_(ctx, x, y, translatedText, textEnd)
    end

    local fontSize = getCurrentNvgFontSize_(ctx)
    local scale = resolveNvgTextFitScale(
        ctx, metadata, fontSize, translatedText)
    if scale >= 1 then
        return originalNvgText_(ctx, x, y, translatedText, textEnd)
    end

    originalNvgFontSize_(ctx, fontSize * scale)
    local advance = originalNvgText_(ctx, x, y, translatedText, textEnd)
    originalNvgFontSize_(ctx, fontSize)
    return advance
end

local function drawTranslatedNvgTextBox(
        ctx, x, y, breakRowWidth, translatedText, textEnd, metadata,
        additionalI18nFit)
    if not additionalI18nFit or not nvgTextFitEnabled_
        or textEnd ~= nil
    then
        return originalNvgTextBox_(
            ctx, x, y, breakRowWidth, translatedText, textEnd)
    end

    local fontSize = getCurrentNvgFontSize_(ctx)
    local scale = resolveNvgTextFitScale(
        ctx, metadata, fontSize, translatedText)
    if scale >= 1 then
        return originalNvgTextBox_(
            ctx, x, y, breakRowWidth, translatedText, textEnd)
    end

    originalNvgFontSize_(ctx, fontSize * scale)
    local result = originalNvgTextBox_(
        ctx, x, y, breakRowWidth, translatedText, textEnd)
    originalNvgFontSize_(ctx, fontSize)
    return result
end

local function measureTranslatedNvgTextBounds(
        ctx, x, y, translatedText, metadata, endOrBounds, bounds,
        additionalI18nFit)
    local hasTextEnd = endOrBounds ~= nil and type(endOrBounds) ~= "table"
    if not additionalI18nFit or not nvgTextFitEnabled_
        or hasTextEnd
    then
        return originalNvgTextBounds_(
            ctx, x, y, translatedText, endOrBounds, bounds)
    end

    local fontSize = getCurrentNvgFontSize_(ctx)
    local scale = resolveNvgTextFitScale(
        ctx, metadata, fontSize, translatedText)
    if scale >= 1 then
        return originalNvgTextBounds_(
            ctx, x, y, translatedText, endOrBounds, bounds)
    end

    originalNvgFontSize_(ctx, fontSize * scale)
    local advance, bounds = originalNvgTextBounds_(
        ctx, x, y, translatedText, endOrBounds, bounds)
    originalNvgFontSize_(ctx, fontSize)
    return advance, bounds
end

local function measureTranslatedNvgTextBoxBounds(
        ctx, x, y, breakRowWidth, translatedText, metadata,
        endOrBounds, bounds, additionalI18nFit)
    local hasTextEnd = endOrBounds ~= nil and type(endOrBounds) ~= "table"
    if not additionalI18nFit or not nvgTextFitEnabled_
        or hasTextEnd
    then
        return originalNvgTextBoxBounds_(
            ctx, x, y, breakRowWidth, translatedText, endOrBounds, bounds)
    end

    local fontSize = getCurrentNvgFontSize_(ctx)
    local scale = resolveNvgTextFitScale(
        ctx, metadata, fontSize, translatedText)
    if scale >= 1 then
        return originalNvgTextBoxBounds_(
            ctx, x, y, breakRowWidth, translatedText, endOrBounds, bounds)
    end

    originalNvgFontSize_(ctx, fontSize * scale)
    local measuredBounds = originalNvgTextBoxBounds_(
        ctx, x, y, breakRowWidth, translatedText, endOrBounds, bounds)
    originalNvgFontSize_(ctx, fontSize)
    return measuredBounds
end

-- Remember BeginFrame devicePxRatio so CSS-logical min can invert
-- mode A/B/C (beginRatio / systemDpr). Must arity-passthrough: tolua defaults
-- the 4th arg to 1.0 only when it is omitted from the stack — forwarding an
-- explicit nil becomes 0.0 and blows up tessTol/fringeWidth.
local function installBeginFrameRatioTracking()
    local _orig_nvgBeginFrame = nvgBeginFrame
    nvgBeginFrame = function(ctx, ...)
        -- select(3, ...) is devicePxRatio in (windowWidth, windowHeight, ratio, ...)
        local ratio = (select(3, ...))
        -- Omitted 4th arg → tolua applies its documented 1.0 default; record 1
        -- rather than keeping a stale ratio / falling back to systemDpr.
        if ratio == nil and select("#", ...) == 2 then
            ratio = 1
        end
        rememberBeginFrameRatio(ctx, ratio)
        return _orig_nvgBeginFrame(ctx, ...)
    end
end

local function installLegacyNvgFontSizeTracking()
    -- SHORT-TERM COMPATIBILITY: old runtimes do not expose nvgGetFontSize().
    -- Mirror the native font-size state so Lua-only hot updates still work.
    -- Remove this branch after all supported runtimes provide the getter.
    -- BeginFrame is already wrapped for ratio tracking; chain font-size reset.
    local _ratioAwareBeginFrame = nvgBeginFrame
    local _orig_nvgSave = nvgSave
    local _orig_nvgRestore = nvgRestore
    local _orig_nvgReset = nvgReset

    nvgFontSize = function(ctx, fontSize)
        local result = originalNvgFontSize_(ctx, fontSize)
        setTrackedFontSize(ctx, fontSize)
        return result
    end
    nvgBeginFrame = function(ctx, ...)
        local result = _ratioAwareBeginFrame(ctx, ...)
        beginTrackedNvgTextFrame(ctx)
        return result
    end
    nvgSave = function(ctx)
        local result = _orig_nvgSave(ctx)
        pushTrackedNvgTextState(ctx)
        return result
    end
    nvgRestore = function(ctx)
        local result = _orig_nvgRestore(ctx)
        popTrackedNvgTextState(ctx)
        return result
    end
    nvgReset = function(ctx)
        local result = _orig_nvgReset(ctx)
        resetTrackedNvgTextState(ctx)
        return result
    end

    getCurrentNvgFontSize_ = function(ctx)
        return getNvgTextState(ctx).fontSize
    end

    local _orig_nvgDelete = nvgDelete
    if _orig_nvgDelete then
        nvgDelete = function(ctx)
            local result = _orig_nvgDelete(ctx)
            nvgTextStateByContext_[ctx] = nil
            unitsToCssByContext_[ctx] = nil
            if lastNvgTextContext_ == ctx then
                lastNvgTextContext_ = nil
                lastNvgTextState_ = nil
            end
            return result
        end
    end
end

local function installNvgTextFitHooks()
    if nvgTextFitHooksInstalled_ or not nvgTextFitEnabled_ then
        return
    end
    nvgTextFitHooksInstalled_ = true
    originalNvgFontSize_ = nvgFontSize

    -- Always track BeginFrame ratio for CSS-logical min inverse.
    installBeginFrameRatioTracking()

    if type(nvgGetFontSize) == "function" then
        getCurrentNvgFontSize_ = nvgGetFontSize
        local _orig_nvgDelete = nvgDelete
        if _orig_nvgDelete then
            nvgDelete = function(ctx)
                local result = _orig_nvgDelete(ctx)
                unitsToCssByContext_[ctx] = nil
                return result
            end
        end
    else
        installLegacyNvgFontSizeTracking()
    end

    -- Font changes can invalidate width ratios in scaleCache.
    local metricInvalidators = {
        "nvgCreateFont", "nvgDeleteFont",
        "nvgAddFallbackFont", "nvgAddFallbackFontId",
        "nvgForceAutoHint", "nvgFontSizeMethod",
    }
    for _, functionName in ipairs(metricInvalidators) do
        local originalFunction = _G[functionName]
        if originalFunction then
            _G[functionName] = function(ctx, ...)
                local results = table.pack(originalFunction(ctx, ...))
                invalidateNvgTranslationFitScales()
                return table.unpack(results, 1, results.n)
            end
        end
    end
end

local function installHooks()
    if hooksInstalled_ then
        installNvgTextFitHooks()
        return
    end
    hooksInstalled_ = true
    _tr = _tr_impl

    originalNvgText_ = nvgText
    if originalNvgText_ then
        nvgText = function(ctx, x, y, text, e, additionalI18nFit)
            if additionalI18nFit == nil then
                additionalI18nFit = true
            end
            local translatedText, provenance
            if additionalI18nFit then
                translatedText, provenance
                    = resolveTranslatedTextProvenance(text)
            else
                translatedText = translateOnly(text)
            end
            return drawTranslatedNvgText(
                ctx, x, y, translatedText, e, provenance,
                additionalI18nFit)
        end
    end

    originalNvgTextBox_ = nvgTextBox
    if originalNvgTextBox_ then
        nvgTextBox = function(
                ctx, x, y, breakRowWidth, text, e,
                additionalI18nFit)
            if additionalI18nFit == nil then
                additionalI18nFit = true
            end
            local translatedText, provenance
            if additionalI18nFit then
                translatedText, provenance
                    = resolveTranslatedTextProvenance(text)
            else
                translatedText = translateOnly(text)
            end
            return drawTranslatedNvgTextBox(
                ctx, x, y, breakRowWidth, translatedText, e, provenance,
                additionalI18nFit)
        end
    end

    originalNvgTextBounds_ = nvgTextBounds
    if originalNvgTextBounds_ then
        nvgTextBounds = function(
                ctx, x, y, text, endOrBounds, bounds,
                additionalI18nFit)
            if additionalI18nFit == nil then
                additionalI18nFit = true
            end
            local translatedText, provenance
            if additionalI18nFit then
                translatedText, provenance
                    = resolveTranslatedTextProvenance(text)
            else
                translatedText = translateOnly(text)
            end
            return measureTranslatedNvgTextBounds(
                ctx, x, y, translatedText, provenance, endOrBounds, bounds,
                additionalI18nFit)
        end
    end

    originalNvgTextBoxBounds_ = nvgTextBoxBounds
    if originalNvgTextBoxBounds_ then
        nvgTextBoxBounds = function(
                ctx, x, y, breakRowWidth, text, endOrBounds, bounds,
                additionalI18nFit)
            if additionalI18nFit == nil then
                additionalI18nFit = true
            end
            local translatedText, provenance
            if additionalI18nFit then
                translatedText, provenance
                    = resolveTranslatedTextProvenance(text)
            else
                translatedText = translateOnly(text)
            end
            return measureTranslatedNvgTextBoxBounds(
                ctx, x, y, breakRowWidth, translatedText, provenance,
                endOrBounds, bounds, additionalI18nFit)
        end
    end

    local _orig_string_format = string.format
    if _orig_string_format then
        string.format = function(fmt, ...)
            local translatedFormat, translationKey = translateOnly(fmt)
            if not translationKey then
                local provenance = findTranslatedTextProvenance(translatedFormat)
                translationKey = provenance and provenance.translationKey or nil
            end
            local formattedText = _orig_string_format(translatedFormat, ...)
            if translationKey then
                recordDynamicTranslatedTextProvenance(formattedText, translationKey)
            end
            return formattedText
        end
    end

    installNvgTextFitHooks()

    if Text3D then
        -- Hook method call: text3d:SetText("t_xxx")
        local _orig_SetText = Text3D.SetText
        Text3D.SetText = function(self, text)
            return _orig_SetText(self, (translateOnly(text)))
        end

        -- Hook property assignment: text3d.text = "t_xxx"
        -- tolua stores property setters in .set table
        local setTable = Text3D[".set"]
        if setTable and setTable.text then
            local _orig_set_text = setTable.text
            setTable.text = function(self, value)
                return _orig_set_text(self, (translateOnly(value)))
            end
        end
    end
end

--- Inject in-memory translation entries for tests and controlled fixtures.
-- This does not refresh existing UI widget measurement caches and is not a
-- live language-switching API; production language changes still restart the
-- project. sourceText is optional, and validation is atomic: malformed input
-- returns an error without applying any entries.
---@param entries table<string, {sourceText: string|nil, translatedText: string}>
---@return boolean success
---@return string|nil errorMessage
function i18n.AddTranslationEntries(entries)
    if type(entries) ~= "table" then
        return false, "entries must be a table"
    end

    local hasEntry = false
    for translationKey, entry in pairs(entries) do
        hasEntry = true
        if type(translationKey) ~= "string" or translationKey == "" then
            return false, "translation keys must be non-empty strings"
        end
        if type(entry) ~= "table" then
            return false, "entry '" .. translationKey .. "' must be a table"
        end
        if type(entry.translatedText) ~= "string" then
            return false,
                "entry '" .. translationKey .. "'.translatedText must be a string"
        end
        if entry.sourceText ~= nil and type(entry.sourceText) ~= "string" then
            return false,
                "entry '" .. translationKey .. "'.sourceText must be a string or nil"
        end
    end
    if not hasEntry then
        return false, "entries must not be empty"
    end

    for translationKey, entry in pairs(entries) do
        translations_[translationKey] = entry.translatedText
        if entry.sourceText ~= nil then
            sourceTranslations_[translationKey] = entry.sourceText
        end
    end

    clearTranslationFitCaches()
    nvgTextFitEnabled_ = nvgTextFitEnabled_
        or hasSourceTranslationPair()
    installHooks()
    return true
end

-- ============================================================
-- i18n config + language resolution
-- Keep the shared config and base resolution logic in sync with
-- engine-startup/main.lua. The server game-VM override below is runtime-only.
-- ============================================================

local NONE = {}
local i18nConfig_ = nil

-- UUID 来自 engine-res-project 的 .meta 文件，重新生成 meta 后需同步更新
local ENGINE_I18N_CONFIG_UUID = "Q4M3GntfTmiNZCdTeiz5Kg"  -- .project/i18n.json.meta
local ENGINE_I18N_LANG_URIS = {
    zh_CN = "uuid://-73mcwx1QB6NyLrwJxv8Kg",  -- i18n/zh_CN.json.meta
    en    = "uuid://u05oYbz5RtecsyHB9-bmKQ",   -- i18n/en.json.meta
}
local URHOX_LIBS_I18N_PREFIX = "urhox-libs/i18n/"

local function engineLangUri(lang)
    return ENGINE_I18N_LANG_URIS[lang]
end

local function urhoxLibsLangUri(lang)
    local uri = URHOX_LIBS_I18N_PREFIX .. lang .. ".json"
    if cache.GetResUuid then
        local uuid = cache:GetResUuid(uri)
        if uuid and uuid ~= "" then return uri end
    end
    return cache:Exists(uri) and uri or nil
end

local function translationUris(lang)
    local uris = {}
    local engineUri = engineLangUri(lang)
    if engineUri then uris[#uris + 1] = engineUri end
    local urhoxLibsUri = urhoxLibsLangUri(lang)
    if urhoxLibsUri then uris[#uris + 1] = urhoxLibsUri end
    uris[#uris + 1] = "i18n/" .. lang .. ".json"
    return uris
end

local function loadConfig()
    if i18nConfig_ ~= nil then
        return i18nConfig_ ~= NONE and i18nConfig_ or nil
    end
    if not cache:Exists("i18n.json") then
        log:Write(LOG_INFO, "[i18n] loadConfig: i18n.json not found, i18n disabled")
        i18nConfig_ = NONE
        return nil
    end
    local file = cache:GetFile("i18n.json")
    if not file then
        i18nConfig_ = NONE
        return nil
    end
    local content = file:ReadString()
    file:Close()
    if not content or content == "" then
        i18nConfig_ = NONE
        return nil
    end
    local ok, data = pcall(cjson.decode, content)
    if not ok or not data then
        i18nConfig_ = NONE
        return nil
    end

    -- engine-res 增加了多语言能力，非多语言项目会 fallback 到引擎的 i18n.json，
    -- 通过 GetResUuid 与引擎已知 UUID 比较来检测，fallback 时 support_langs 限制为 source_lang。
    if cache.GetResUuid then
        local uuid = cache:GetResUuid("i18n.json")
        log:Write(LOG_INFO, "[i18n] loadConfig: uuid='" .. tostring(uuid) .. "' engine='" .. ENGINE_I18N_CONFIG_UUID .. "' match=" .. tostring(uuid == ENGINE_I18N_CONFIG_UUID))
        if uuid == ENGINE_I18N_CONFIG_UUID and data.source_lang then
            data.support_langs = { data.source_lang }
            data.support_langs_str = data.source_lang
            log:Write(LOG_INFO, "[i18n] loadConfig: engine fallback, support_langs='" .. data.support_langs_str .. "'")
        end
    end

    if not data.support_langs then
        local langs = {}
        if data.source_lang and data.source_lang ~= "" then
            langs[#langs + 1] = data.source_lang
        end
        if data.target_langs then
            for _, lang in ipairs(data.target_langs) do
                langs[#langs + 1] = lang
            end
        end
        data.support_langs = langs
        data.support_langs_str = #langs > 0 and table.concat(langs, ",") or ""
    end

    i18nConfig_ = data
    return i18nConfig_
end

local function getServerGameDefaultLanguage(cfg)
    if type(GetLuaEnvironment) ~= "function" then return nil end

    local ok, luaEnvironment = pcall(GetLuaEnvironment)
    if not ok or luaEnvironment ~= 0 then return nil end -- LuaEnvironment::Runtime

    if type(IsServerMode) ~= "function" or not IsServerMode() then
        return nil
    end

    -- New binaries expose the selected project revision directly. Treat a
    -- successful API call as authoritative; old binaries use the UUID heuristic.
    if type(GetProjectRevision) == "function" then
        local ok, revision = pcall(GetProjectRevision)
        if ok then
            if revision == "intl" then
                for _, lang in ipairs(cfg.support_langs or {}) do
                    if lang == "en" then return lang end
                end
            end
            return nil
        end
        log:Write(LOG_WARNING, "[i18n] GetProjectRevision failed; using legacy config detection")
    end

    -- Engine-res also provides i18n.json. Only a project-owned config may
    -- change the server default language.
    if not cache.GetResUuid then return nil end
    local configUuid = cache:GetResUuid("i18n.json")
    if not configUuid or configUuid == "" or configUuid == ENGINE_I18N_CONFIG_UUID then
        return nil
    end

    for _, lang in ipairs(cfg.support_langs or {}) do
        if lang == "en" then return lang end
    end
    return nil
end

--- Resolve language: user pref > -lang > server game VM en > system > source_lang.
local function resolveI18nLanguage()
    local cfg = loadConfig()
    if not cfg then return nil, nil end
    local supportLangs = cfg.support_langs_str

    if localization.ReadUserPrefLanguage then
        local pref = localization:ReadUserPrefLanguage()
        if pref and pref ~= "" then
            local matched = pref
            if supportLangs ~= "" and localization.MatchLanguage then
                matched = localization:MatchLanguage(pref, supportLangs)
            end
            if matched and matched ~= "" then
                return matched, cfg
            end
        end
    end

    local argLang = GetAppArgv and GetAppArgv("lang") or ""
    if argLang ~= "" then
        local matched = argLang
        if supportLangs ~= "" and localization.MatchLanguage then
            matched = localization:MatchLanguage(argLang, supportLangs)
        end
        if matched and matched ~= "" then
            log:Write(LOG_INFO, "[i18n] -lang='" .. argLang .. "' matched='" .. matched .. "'")
            return matched, cfg
        end
        log:Write(LOG_WARNING, "[i18n] -lang='" .. argLang .. "' not in support_langs='" .. supportLangs .. "', falling through")
    end

    local serverDefaultLang = getServerGameDefaultLanguage(cfg)
    if serverDefaultLang then
        log:Write(LOG_INFO, "[i18n] server game VM: defaulting to '" .. serverDefaultLang .. "'")
        return serverDefaultLang, cfg
    end

    local sysLang = localization.GetSystemLanguage and localization:GetSystemLanguage() or ""
    if sysLang ~= "" then
        local matched = sysLang
        if supportLangs ~= "" and localization.MatchLanguage then
            matched = localization:MatchLanguage(sysLang, supportLangs)
        end
        if matched and matched ~= "" then
            return matched, cfg
        end
    end

    if cfg.source_lang and cfg.source_lang ~= "" then
        return cfg.source_lang, cfg
    end

    return nil, cfg
end

-- ============================================================
-- END SYNC BLOCK
-- ============================================================

-- ============================================================
-- Built-in confirm dialog (independent NVG render target)
-- Mirrors engine-startup/loading_ui.lua dialog style.
-- No dependency on urhox-libs/UI — works in any project.
-- Uses ScriptObject + self:SubscribeToEvent for local events.
-- ============================================================

-- Layout constants (logical pixels, same as loading_ui)
local DLG_TITLE_SIZE   = 18
local DLG_MSG_SIZE     = 14
local DLG_BTN_SIZE     = 15
local DLG_WIDTH        = 400
local DLG_RADIUS       = 16
local DLG_BTN_RADIUS   = 10
local DLG_BTN_H        = 44
local DLG_BTN_GAP      = 12
local DLG_FADE_DUR     = 0.25
local DLG_PC_REF       = 720

-- Singleton dialog instance (lazy-created)
local dlgInstance = nil

---@class i18n_DialogReceiver : LuaScriptObject
i18n_DialogReceiver = ScriptObject()

function i18n_DialogReceiver:Start()
    -- NVG resources
    self.vg = nvgCreate(1)
    if not self.vg then
        log:Write(LOG_WARNING, "[i18n] Failed to create dialog NVG context")
        return
    end
    nvgSetRenderOrder(self.vg, 999998)  -- render on top

    self.font = nvgCreateFont(self.vg, "sans", "Fonts/MiSans-Regular.ttf")
    if self.font < 0 then
        self.font = nvgCreateFont(self.vg, "sans", "Fonts/Anonymous Pro.ttf")
    end

    -- State
    self.visible = false
    self.opacity = 0.0
    self.fading = false
    self.fadeIn = false
    self.fadeProg = 0.0
    self.title = ""
    self.message = ""
    self.confirmText = "OK"
    self.cancelText = ""
    self.callback = nil
    self.confirmRect = { x = 0, y = 0, w = 0, h = 0 }
    self.cancelRect  = { x = 0, y = 0, w = 0, h = 0 }
    self.pressConfirm = false
    self.pressCancel = false
    self.logW = 0
    self.logH = 0
    self.dpr = 1.0

    self:RecalcLayout()

    -- Subscribe events via self (local, auto-cleanup)
    self:SubscribeToEvent(self.vg, "NanoVGRender", function(_, et, ed) self:HandleRender() end)
    self:SubscribeToEvent("Update", function(_, et, ed) self:HandleUpdate(ed["TimeStep"]:GetFloat()) end)
    self:SubscribeToEvent("MouseButtonDown", function(_, et, ed) self:HandleMouseDown(et, ed) end)
    self:SubscribeToEvent("MouseButtonUp", function(_, et, ed) self:HandleMouseUp(et, ed) end)
    self:SubscribeToEvent("TouchEnd", function(_, et, ed) self:HandleTouchEnd(et, ed) end)
end

function i18n_DialogReceiver:RecalcLayout()
    local rawDpr = graphics:GetDPR()
    local shortSide = math.min(graphics:GetWidth(), graphics:GetHeight()) / rawDpr
    local densityFactor = math.max(0.625, math.min(math.sqrt(shortSide / DLG_PC_REF), 1.0))
    self.dpr = rawDpr * densityFactor
    self.logW = graphics:GetWidth() / self.dpr
    self.logH = graphics:GetHeight() / self.dpr
end

function i18n_DialogReceiver:PointInRect(px, py, r)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function i18n_DialogReceiver:Dismiss(confirmed)
    if not self.visible then return end
    self.fading = true
    self.fadeIn = false
    self.fadeProg = 0
    if self.callback then
        local cb = self.callback
        self.callback = nil
        cb(confirmed)
    end
end

function i18n_DialogReceiver:HandleUpdate(dt)
    if not self.fading then return end
    self.fadeProg = self.fadeProg + dt / DLG_FADE_DUR
    if self.fadeProg >= 1.0 then
        self.fadeProg = 1.0
        self.fading = false
        self.opacity = self.fadeIn and 1.0 or 0.0
        if not self.fadeIn then
            self.visible = false
        end
    else
        self.opacity = self.fadeIn and self.fadeProg or (1.0 - self.fadeProg)
    end
end

function i18n_DialogReceiver:HandleRender()
    if not self.vg or self.opacity <= 0 then return end

    self:RecalcLayout()
    local vg = self.vg
    local da = self.opacity
    local logW, logH = self.logW, self.logH
    local padX, padTop, padBot = 28, 32, 24

    nvgBeginFrame(vg, logW, logH, self.dpr)

    -- Overlay
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(153 * da)))
    nvgFill(vg)

    -- Dialog dimensions
    local dw = math.min(DLG_WIDTH, logW * 0.85)
    local titleH = DLG_TITLE_SIZE + 4
    local msgH = DLG_MSG_SIZE * 2.5
    local contentH = padTop + titleH + 16 + msgH + 24 + DLG_BTN_H + padBot
    local dx = (logW - dw) / 2
    local dy = (logH - contentH) / 2

    -- Card shadow + background + border
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx - 2, dy - 2, dw + 4, contentH + 4, DLG_RADIUS + 1)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(80 * da)))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx, dy, dw, contentH, DLG_RADIUS)
    nvgFillColor(vg, nvgRGBA(30, 30, 45, math.floor(242 * da)))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx, dy, dw, contentH, DLG_RADIUS)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(20 * da)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local curY = dy + padTop

    -- Title
    if self.font >= 0 and self.title ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DLG_TITLE_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(242 * da)))
        nvgText(vg, logW / 2, curY, self.title, nil)
        curY = curY + titleH + 16
    end

    -- Message
    if self.font >= 0 and self.message ~= "" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, DLG_MSG_SIZE)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(153 * da)))
        nvgTextBox(vg, dx + padX, curY, dw - padX * 2, self.message, nil)
        curY = curY + msgH + 24
    end

    -- Buttons
    local hasCancelBtn = self.cancelText ~= ""
    local btnAreaX = dx + padX
    local btnAreaW = dw - padX * 2

    if hasCancelBtn then
        local btnW = (btnAreaW - DLG_BTN_GAP) / 2

        -- Cancel button
        self.cancelRect = { x = btnAreaX, y = curY, w = btnW, h = DLG_BTN_H }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, self.cancelRect.x, self.cancelRect.y, self.cancelRect.w, self.cancelRect.h, DLG_BTN_RADIUS)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor((self.pressCancel and 30 or 20) * da)))
        nvgFill(vg)
        if self.font >= 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, DLG_BTN_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(178 * da)))
            nvgText(vg, self.cancelRect.x + self.cancelRect.w / 2, self.cancelRect.y + self.cancelRect.h / 2, self.cancelText, nil)
        end

        -- Confirm button
        local cA = self.pressConfirm and 217 or 255
        self.confirmRect = { x = btnAreaX + btnW + DLG_BTN_GAP, y = curY, w = btnW, h = DLG_BTN_H }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, self.confirmRect.x, self.confirmRect.y, self.confirmRect.w, self.confirmRect.h, DLG_BTN_RADIUS)
        local grad = nvgLinearGradient(vg,
            self.confirmRect.x, self.confirmRect.y,
            self.confirmRect.x + self.confirmRect.w, self.confirmRect.y + self.confirmRect.h,
            nvgRGBA(91, 106, 240, math.floor(cA * da)),
            nvgRGBA(124, 91, 240, math.floor(cA * da)))
        nvgFillPaint(vg, grad)
        nvgFill(vg)
        if self.font >= 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, DLG_BTN_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * da)))
            nvgText(vg, self.confirmRect.x + self.confirmRect.w / 2, self.confirmRect.y + self.confirmRect.h / 2, self.confirmText, nil)
        end
    else
        -- Single confirm button (full width)
        local cA = self.pressConfirm and 217 or 255
        self.confirmRect = { x = btnAreaX, y = curY, w = btnAreaW, h = DLG_BTN_H }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, self.confirmRect.x, self.confirmRect.y, self.confirmRect.w, self.confirmRect.h, DLG_BTN_RADIUS)
        local grad = nvgLinearGradient(vg,
            self.confirmRect.x, self.confirmRect.y,
            self.confirmRect.x + self.confirmRect.w, self.confirmRect.y + self.confirmRect.h,
            nvgRGBA(91, 106, 240, math.floor(cA * da)),
            nvgRGBA(124, 91, 240, math.floor(cA * da)))
        nvgFillPaint(vg, grad)
        nvgFill(vg)
        if self.font >= 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, DLG_BTN_SIZE)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * da)))
            nvgText(vg, self.confirmRect.x + self.confirmRect.w / 2, self.confirmRect.y + self.confirmRect.h / 2, self.confirmText, nil)
        end
        self.cancelRect = { x = 0, y = 0, w = 0, h = 0 }
    end

    nvgEndFrame(vg)
end

function i18n_DialogReceiver:HandleMouseDown(eventType, eventData)
    if not self.visible or self.opacity <= 0 then return end
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt() / self.dpr
    local my = eventData["Y"]:GetInt() / self.dpr
    self.pressConfirm = self:PointInRect(mx, my, self.confirmRect)
    self.pressCancel  = self:PointInRect(mx, my, self.cancelRect)
end

function i18n_DialogReceiver:HandleMouseUp(eventType, eventData)
    if not self.visible or self.opacity <= 0 then return end
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local mx = eventData["X"]:GetInt() / self.dpr
    local my = eventData["Y"]:GetInt() / self.dpr
    self.pressConfirm = false
    self.pressCancel = false
    if self:PointInRect(mx, my, self.confirmRect) then
        self:Dismiss(true)
    elseif self:PointInRect(mx, my, self.cancelRect) then
        self:Dismiss(false)
    end
end

function i18n_DialogReceiver:HandleTouchEnd(eventType, eventData)
    if not self.visible or self.opacity <= 0 then return end
    local tx = eventData["X"]:GetInt() / self.dpr
    local ty = eventData["Y"]:GetInt() / self.dpr
    if self:PointInRect(tx, ty, self.confirmRect) then
        self:Dismiss(true)
    elseif self:PointInRect(tx, ty, self.cancelRect) then
        self:Dismiss(false)
    end
end

function i18n_DialogReceiver:ShowConfirm(title, message, confirmText, cancelText, callback)
    self.title = title or ""
    self.message = message or ""
    self.confirmText = confirmText or "OK"
    self.cancelText = cancelText or ""
    self.callback = callback
    self.visible = true
    self.fading = true
    self.fadeIn = true
    self.fadeProg = 0
    self.pressConfirm = false
    self.pressCancel = false
end

function i18n_DialogReceiver:ShowAlert(title, message, buttonText, callback)
    self:ShowConfirm(title, message, buttonText, nil, function()
        if callback then callback() end
    end)
end

--- Get or create the singleton dialog instance
local function getDialog()
    if dlgInstance and dlgInstance.vg then return dlgInstance end
    local node = Node()
    dlgInstance = node:CreateScriptObject("i18n_DialogReceiver")
    if not dlgInstance or not dlgInstance.vg then
        log:Write(LOG_WARNING, "[i18n] Failed to create dialog ScriptObject")
        dlgInstance = nil
        return nil
    end
    return dlgInstance
end

-- ============================================================
-- Public API
-- ============================================================

local function loadTranslationsInto(uri, destination)
    -- Target lang file may be absent pre-restart on language switch; relies on
    -- post-restart PreloadI18nStep to fetch. Skip silently to avoid ERROR noise.
    if not cache:Exists(uri) then
        log:Write(LOG_INFO, "[i18n] AddTranslations: '" .. uri .. "' not loaded yet, will take effect after restart")
        return false
    end

    local file = cache:GetFile(uri)
    if not file then
        log:Write(LOG_WARNING, "[i18n] AddTranslations: '" .. uri .. "' not found")
        return false
    end

    local content = file:ReadString()
    file:Close()

    if not content or content == "" then
        log:Write(LOG_WARNING, "[i18n] AddTranslations: '" .. uri .. "' is empty")
        return false
    end

    local ok, data = pcall(cjson.decode, content)
    if not ok or not data then
        log:Write(LOG_WARNING, "[i18n] AddTranslations: '" .. uri .. "' parse failed")
        return false
    end

    for key, text in pairs(data) do
        destination[key] = text
    end
    return true
end

function i18n.AddTranslations(uri)
    local loaded = loadTranslationsInto(uri, translations_)
    if loaded then
        clearTranslationFitCaches()
    end
    return loaded
end

--- Get current language.
-- Resolution: actualLang cache > user_lang file > -lang > server game VM en
-- > system language > source_lang
-- @return string
function i18n.GetLanguage()
    if actualLang_ then return actualLang_ end

    local lang = resolveI18nLanguage()

    if lang then
        log:Write(LOG_INFO, "[i18n] GetLanguage: resolved='" .. lang .. "'")
        actualLang_ = lang
        return lang
    end

    log:Write(LOG_INFO, "[i18n] GetLanguage: no language resolved")
    return ""
end

--- Check whether a translated target language is active.
---@return boolean
function i18n.IsActive()
    local cfg = loadConfig()
    return cfg ~= nil
        and type(cfg.source_lang) == "string"
        and cfg.source_lang ~= ""
        and type(actualLang_) == "string"
        and actualLang_ ~= ""
        and actualLang_ ~= cfg.source_lang
end

--- Switch language. If lang is nil/empty, resolves via GetLanguage().
-- Falls back to source_lang if lang is not supported.
-- @param lang string|nil Language code (nil = auto-resolve, won't persist to user_lang)
function i18n.SetLanguage(lang)
    -- Track whether caller explicitly picked a language. Auto-resolve (nil/empty input)
    -- happens at module load and shouldn't persist -lang/system pick to user pref —
    -- otherwise -lang=xx becomes sticky across boots and stale pref overrides future -lang.
    local explicit = lang and lang ~= ""

    -- Resolve language if not provided
    if not explicit then
        lang = i18n.GetLanguage()
    end

    local cfg = loadConfig()
    if cfg and lang and lang ~= "" then
        local supportLangs = cfg.support_langs_str
        if supportLangs and supportLangs ~= "" and localization.MatchLanguage then
            local matched = localization:MatchLanguage(lang, supportLangs)
            if matched and matched ~= "" then
                if matched ~= lang then
                    log:Write(LOG_INFO, "[i18n] SetLanguage: '" .. lang .. "' matched to '" .. matched .. "'")
                end
                lang = matched
            else
                -- C++ MatchLanguage step 5 already returns "en" when supported; reaching here
                -- means even en is unavailable → use source_lang as last resort.
                log:Write(LOG_WARNING, "[i18n] Language '" .. lang .. "' not supported, fallback to source_lang='" .. (cfg.source_lang or "") .. "'")
                lang = cfg.source_lang
            end
        end
    end

    -- Final fallback to source_lang
    if (not lang or lang == "") and cfg then
        lang = cfg.source_lang
    end

    if not lang or lang == "" then
        return
    end

    -- Persist user pref BEFORE dedup: if explicit caller re-picks the same lang as a
    -- prior auto-resolve (which didn't persist), dedup would otherwise drop the write.
    if explicit and localization.SaveUserPrefLanguage then
        localization:SaveUserPrefLanguage(lang)
    end

    -- Skip translation table reload if already on this language
    if lang == requestLang_ then
        log:Write(LOG_INFO, "[i18n] SetLanguage: lang='" .. lang .. "' explicit=" .. tostring(explicit) .. " (dedup, reload skipped)")
        return
    end
    requestLang_ = lang

    actualLang_ = lang
    log:Write(LOG_INFO, "[i18n] SetLanguage: actualLang='" .. lang .. "' explicit=" .. tostring(explicit))

    -- Set resource variant tag for locale-specific assets (@en, @ja, etc.)
    if cache.SetVariantTag then
        local variantLang = lang
        -- Source language uses default resources (no variant tag)
        if cfg and lang == cfg.source_lang then
            variantLang = ""
        end
        log:Write(LOG_INFO, "[i18n] SetVariantTag: priority=2000, tag='" .. variantLang .. "'")
        cache:SetVariantTag(2000, variantLang)
    else
        log:Write(LOG_WARNING, "[i18n] cache.SetVariantTag not available")
    end

    clearTranslationFitCaches()
    translations_ = {}
    sourceTranslations_ = {}
    for _, uri in ipairs(translationUris(lang)) do
        i18n.AddTranslations(uri)
    end

    -- Nvg text fitting is enabled only when a translated target language
    -- is active and the source-language runtime table pairs with it
    -- (translation keys on both sides). No plain-text-key fallback.
    nvgTextFitEnabled_ = false
    local sourceLang = cfg and cfg.source_lang or nil
    if i18n.IsActive() and sourceLang and sourceLang ~= "" and lang ~= sourceLang then
        for _, uri in ipairs(translationUris(sourceLang)) do
            loadTranslationsInto(uri, sourceTranslations_)
        end
        nvgTextFitEnabled_ = hasSourceTranslationPair()
        if not nvgTextFitEnabled_ then
            log:Write(LOG_WARNING,
                "[i18n] Source-language table unavailable; nvg text fit disabled")
        end
    end

    if hooksInstalled_ then
        installNvgTextFitHooks()
    end
end

--- Get supported language list (array of language codes).
-- @return table Array of language codes, e.g. {"zh_CN", "en", "ja"}
function i18n.GetSupportLanguages()
    local cfg = loadConfig()
    if cfg and cfg.support_langs then
        return cfg.support_langs
    end
    return {}
end

--- Request language change with confirm dialog.
-- On confirm: applies SetLanguage and restarts (new engine) or prompts manual restart (old engine).
-- SetLanguage is only called after user confirms.
-- @param lang string Target language code
function i18n.RequestChangeLanguage(lang)
    if not lang or lang == "" then return end
    if lang == actualLang_ then return end

    -- Feature detection: SetVariantTag exists = new binary with safe restart
    local canAutoRestart = (cache.SetVariantTag and true) or false

    local l10n = localization
    local function Tr(key) return l10n and l10n:Get(key) or key end

    local dlg = getDialog()
    if not dlg then
        -- Fallback: apply directly (best effort)
        log:Write(LOG_WARNING, "[i18n] RequestChangeLanguage: dialog unavailable, applying directly")
        i18n.SetLanguage(lang)
        return
    end

    local message = canAutoRestart
        and Tr("Switching language requires restarting. Continue?")
        or  Tr("Current engine version does not support language switching.")

    dlg:ShowConfirm(
        Tr("Switch Language"),
        message,
        Tr("OK"),
        Tr("Cancel"),
        function(confirmed)
            if not confirmed then return end
            i18n.SetLanguage(lang)
            if canAutoRestart then
                SendEvent("RequestRestartGame", VariantMap())
            end
        end
    )
end

--- Get display name for a language code.
-- Uses lang_to_display mapping from i18n.json if available,
-- otherwise falls back to built-in defaults.
-- @param lang string|nil Language code (nil = current language)
-- @return string Display name (e.g. "简体中文", "English")
function i18n.GetLanguageDisplay(lang)
    lang = lang or actualLang_ or ""
    if lang == "" then return "" end
    local cfg = loadConfig()
    if cfg and cfg.lang_to_display and cfg.lang_to_display[lang] then
        return cfg.lang_to_display[lang]
    end
    return lang
end

--- Get config table (for debugging).
function i18n.GetConfig()
    return i18nConfig_
end

--- Get raw translations_ table (for debugging).
function i18n.GetTranslations()
    return translations_
end

--- Resolve source-language text for a display string produced by _tr().
-- Used by Label auto-wrap: measure whether the source would overflow the same
-- box, matching nvg text fit's translationKey → sourceTranslations_ lookup.
-- @param displayText string Final display text (formatted translation)
-- @return string|nil Source template/text, or nil when unknown
function i18n.GetSourceTextForDisplay(displayText)
    if type(displayText) ~= "string" or displayText == "" then
        return nil
    end

    local metadata = findTranslatedTextProvenance(displayText)
    local translationKey = metadata and metadata.translationKey or nil
    if type(translationKey) ~= "string" or translationKey == "" then
        -- Display text may still be a bare translation key.
        if type(sourceTranslations_[displayText]) == "string"
            and sourceTranslations_[displayText] ~= ""
        then
            return sourceTranslations_[displayText]
        end
        return nil
    end

    local sourceText = sourceTranslations_[translationKey]
    if type(sourceText) == "string" and sourceText ~= "" then
        return sourceText
    end
    return nil
end


-- ============================================================
-- Auto-initialize on require
-- ============================================================

i18n.SetLanguage()
if i18nConfig_ and i18nConfig_ ~= NONE then
    installHooks()
    log:Write(LOG_INFO, "[i18n] init: lang='" .. tostring(actualLang_) .. "' translations=" .. tostring(next(translations_) ~= nil) .. " hooks=true")
else
    log:Write(LOG_INFO, "[i18n] init: no config found, hooks NOT installed")
end

-- Register as global
_G.i18n = i18n

return i18n
