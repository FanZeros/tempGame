-- ====================================================================
-- urhox-libs/Profiler/init.lua
-- 性能分析器入口
-- ====================================================================
--
-- 使用方法:
--   local Profiler = require("urhox-libs/Profiler/init")
--   
--   -- 初始化 UI (可选)
--   local ui = Profiler.UI:new()
--   uiManager:addWidget(ui:build())
--
--   -- 在 Update 中
--   Profiler.Core:recordFrame(timeStep)
--   ui:update()
--
--   -- 添加追踪
--   Profiler.Core:beginScope("MyFunction")
--   -- ...
--   Profiler.Core:endScope("MyFunction")
--
-- ====================================================================

local Profiler = {
    -- 核心分析器 (无外部依赖)
    Core = require("urhox-libs/Profiler/Profiler"),
    
    -- UI 面板 (依赖 urhox-libs/UI)
    UI = require("urhox-libs/Profiler/ProfilerUI"),
    
    -- 版本
    VERSION = "1.0.0",
}

-- 便捷方法：直接代理到 Core
setmetatable(Profiler, {
    __index = function(t, k)
        return t.Core[k]
    end
})

return Profiler

