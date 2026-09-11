-- ============================================================================
-- UrhoX Video Library
-- WASM Video Playback Support
-- ============================================================================
--
-- Provides video playback functionality for WASM platform.
-- Uses HTML5 video element for decoding and WebGL for rendering.
--
-- Requirements:
--   - WASM platform only (__EMSCRIPTEN__)
--   - video_bridge.js must be loaded in the HTML page
--
-- Usage (2D UI):
--   local Video = require("urhox-libs/Video")
--   local player = Video.VideoPlayer {
--       src = "path/to/video.mp4",
--       width = "100%",
--       height = 400,
--       autoPlay = true,
--   }
--
-- Usage (3D World - IMAX Screen):
--   local Video = require("urhox-libs/Video")
--   local screen = Video.VideoScreen3D.Create(scene, {
--       videoUrl = "path/to/video.mp4",
--       videoWidth = 1280,
--       videoHeight = 720,
--       autoPlay = true,
--   })
--   -- Must call every frame:
--   screen:Update()
--
-- ============================================================================

local Video = {}

-- Check if we're on WASM platform
Video.isSupported = (function()
    -- Check if VideoPlayer class exists (only available on WASM)
    return VideoPlayer ~= nil
end)()

if Video.isSupported then
    -- Load VideoPlayer widget (2D UI)
    Video.VideoPlayer = require("urhox-libs/Video/VideoPlayer")

    -- Load VideoScreen3D (3D World)
    Video.VideoScreen3D = require("urhox-libs/Video/VideoScreen3D")
else
    -- Provide stubs that log warnings
    Video.VideoPlayer = function(props)
        print("[Video] Warning: VideoPlayer is only supported on WASM platform")
        return nil
    end

    Video.VideoScreen3D = {
        Create = function(scene, config)
            print("[Video] Warning: VideoScreen3D is only supported on WASM platform")
            return nil
        end
    }
end

return Video
