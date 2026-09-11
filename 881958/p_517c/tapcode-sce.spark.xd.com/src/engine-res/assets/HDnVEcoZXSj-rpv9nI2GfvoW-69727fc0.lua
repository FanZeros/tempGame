-- LuaScripts/Utilities/Previews/UIGuard.lua
-- UI-related compatibility layer and guards

if not NVG_ALIGN_CENTER_VISUAL then
    NVG_ALIGN_CENTER_VISUAL = NVG_ALIGN_CENTER
end

-- Safe area insets (added in newer versions)
if not GetSafeAreaInsets then
    -- Return zero Rect (no safe area) for old binaries
    GetSafeAreaInsets = function(calcScale)
        return Rect(0, 0, 0, 0)
    end
end

-- YGUndefined constant (NaN, for unconstrained dimensions in YGNodeCalculateLayout)
if not YGGetUndefined then
    YGGetUndefined = function() return 0.0 / 0.0 end  -- NaN fallback for old binaries
end
YGUndefined = YGGetUndefined()

-- Yoga config functions (added in newer versions)
if not YGConfigGetDefault then
    YGConfigGetDefault = function() return nil end
end
if not YGConfigSetPointScaleFactor then
    YGConfigSetPointScaleFactor = function(config, scale) end
    print("[UI] Warning: YGConfigSetPointScaleFactor not available, using legacy screen pixel layout")
end

-- Yoga flexBasis extended functions (added in newer versions)
if not YGNodeStyleSetFlexBasisMaxContent then
    YGNodeStyleSetFlexBasisMaxContent = function(node) end
end
if not YGNodeStyleSetFlexBasisFitContent then
    YGNodeStyleSetFlexBasisFitContent = function(node) end
end
if not YGNodeStyleSetFlexBasisStretch then
    YGNodeStyleSetFlexBasisStretch = function(node) end
end

-- Yoga min/max width/height extended functions (added in newer versions)
if not YGNodeStyleSetMinWidthMaxContent then
    YGNodeStyleSetMinWidthMaxContent = function(node) end
end
if not YGNodeStyleSetMinWidthFitContent then
    YGNodeStyleSetMinWidthFitContent = function(node) end
end
if not YGNodeStyleSetMinWidthStretch then
    YGNodeStyleSetMinWidthStretch = function(node) end
end
if not YGNodeStyleSetMinHeightMaxContent then
    YGNodeStyleSetMinHeightMaxContent = function(node) end
end
if not YGNodeStyleSetMinHeightFitContent then
    YGNodeStyleSetMinHeightFitContent = function(node) end
end
if not YGNodeStyleSetMinHeightStretch then
    YGNodeStyleSetMinHeightStretch = function(node) end
end
if not YGNodeStyleSetMaxWidthMaxContent then
    YGNodeStyleSetMaxWidthMaxContent = function(node) end
end
if not YGNodeStyleSetMaxWidthFitContent then
    YGNodeStyleSetMaxWidthFitContent = function(node) end
end
if not YGNodeStyleSetMaxWidthStretch then
    YGNodeStyleSetMaxWidthStretch = function(node) end
end
if not YGNodeStyleSetMaxHeightMaxContent then
    YGNodeStyleSetMaxHeightMaxContent = function(node) end
end
if not YGNodeStyleSetMaxHeightFitContent then
    YGNodeStyleSetMaxHeightFitContent = function(node) end
end
if not YGNodeStyleSetMaxHeightStretch then
    YGNodeStyleSetMaxHeightStretch = function(node) end
end

-- Yoga style getter functions returning YGValue table (added in newer versions)
if not YGNodeStyleGetFlexBasis then
    YGNodeStyleGetFlexBasis = function(node) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetWidth then
    YGNodeStyleGetWidth = function(node) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetHeight then
    YGNodeStyleGetHeight = function(node) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetMinWidth then
    YGNodeStyleGetMinWidth = function(node) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetMinHeight then
    YGNodeStyleGetMinHeight = function(node) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetMaxWidth then
    YGNodeStyleGetMaxWidth = function(node) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetMaxHeight then
    YGNodeStyleGetMaxHeight = function(node) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetPosition then
    YGNodeStyleGetPosition = function(node, edge) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetMargin then
    YGNodeStyleGetMargin = function(node, edge) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetPadding then
    YGNodeStyleGetPadding = function(node, edge) return {value = 0, unit = 0} end
end
if not YGNodeStyleGetGap then
    YGNodeStyleGetGap = function(node, gutter) return {value = 0, unit = 0} end
end

-- Yoga baseline alignment functions (added in newer versions)
if not YGNodeSetBaselineValue then
    YGNodeSetBaselineValue = function(node, baseline) end
end
if not YGNodeClearBaselineValue then
    YGNodeClearBaselineValue = function(node) end
end

-- NanoVG image pattern with tint color (added in newer versions)
-- Fallback: ignore tint, use alpha from color.a only
if not nvgImagePatternTinted then
    nvgImagePatternTinted = function(ctx, ox, oy, ex, ey, angle, image, color)
        local alpha = color and color.a or 1.0
        return nvgImagePattern(ctx, ox, oy, ex, ey, angle, image, alpha)
    end
end

-- NanoVG render order function (added in newer versions)
if not nvgSetRenderOrder then
    nvgSetRenderOrder = function(ctx, renderOrder) end
end

-- NanoVG text scale mode (added in newer versions)
-- Fallback: no-op, old binaries always use full scale
if not nvgTextScaleMode then
    nvgTextScaleMode = function(ctx, mode) end
end
if not NVG_TEXT_SCALE_FULL then
    NVG_TEXT_SCALE_FULL = 0
end
if not NVG_TEXT_SCALE_DPR_ONLY then
    NVG_TEXT_SCALE_DPR_ONLY = 1
end

-- VideoLoadResult error code constants (added in newer versions)
if not VIDEO_LOAD_SUCCESS then
    VIDEO_LOAD_SUCCESS = 0
    VIDEO_LOAD_ERROR_NO_DECODER = 1
    VIDEO_LOAD_ERROR_SOURCE_NOT_FOUND = 2
    VIDEO_LOAD_ERROR_OPEN_FAILED = 3
    VIDEO_LOAD_ERROR_TEXTURE_FAILED = 4
    VIDEO_LOAD_ERROR_CANCELLED = 5
end

-- VideoPlayer:SetPlaybackRate/GetPlaybackRate fallback (added in newer versions)
-- Old binaries don't have playback rate control; no-op gracefully
if VideoPlayer and not VideoPlayer.SetPlaybackRate then
    rawset(VideoPlayer, 'SetPlaybackRate', function(self, rate) end)
    rawset(VideoPlayer, 'GetPlaybackRate', function(self) return 1.0 end)
end

-- VideoPlayer:AsyncLoad fallback (added in newer versions)
-- Old binaries only have Load(); wrap it as AsyncLoad() with sync behavior
if VideoPlayer and not VideoPlayer.AsyncLoad then
    rawset(VideoPlayer, 'AsyncLoad', function(self, source, width, height, callback)
        local success = self:Load(source, width or 1920, height or 1080)
        if callback then
            callback(success and VIDEO_LOAD_SUCCESS or VIDEO_LOAD_ERROR_OPEN_FAILED)
        end
        return success
    end)
end

-- ============================================================================
-- AI hallucination aliases
-- ============================================================================

-- GetNanoVGContext() → lazy-init singleton
-- AI hallucinates a C++-style getter; UrhoX uses nvgCreate() factory function.
local _nvgContext = nil
function GetNanoVGContext()
    if not _nvgContext then
        _nvgContext = nvgCreate(1)
    end
    return _nvgContext
end
