-- ====================================================================
-- urhox-libs/Profiler/Profiler.lua
-- 通用性能分析器 - 函数级别时间追踪、帧时间统计、内存监控
-- 
-- 无外部依赖，可用于任何 Lua 项目
-- ====================================================================
--
-- 使用方法:
--   local Profiler = require("urhox-libs/Profiler/Profiler")
--
--   -- 初始化
--   Profiler:init()
--
--   -- 方式 1: 手动 begin/end (推荐用于大块代码)
--   Profiler:beginScope("WorldGen")
--   -- ... 代码 ...
--   Profiler:endScope("WorldGen")
--
--   -- 方式 2: 自动闭包 (推荐用于短代码块)
--   Profiler:measure("ChunkBuild", function()
--       -- ... 代码 ...
--   end)
--
--   -- 记录帧时间 (在 Update 中调用)
--   Profiler:recordFrame(timeStep)
--
--   -- 显示报告
--   Profiler:printReport()
--
-- ====================================================================

---@class ProfilerScope
---@field name string
---@field totalTime number 总耗时(秒)
---@field callCount number 调用次数
---@field minTime number 最短耗时
---@field maxTime number 最长耗时
---@field startTime number 当前作用域开始时间
---@field depth number 嵌套深度

---@class Profiler
local Profiler = {
    -- 是否启用
    enabled = true,
    
    -- 作用域数据: [name] = ProfilerScope
    scopes = {},
    
    -- 调用栈 (用于嵌套追踪)
    callStack = {},
    
    -- 帧时间数据
    frameTimes = {},
    maxFrameSamples = 600,  -- 10秒 @ 60fps
    frameIndex = 0,
    
    -- 内存追踪
    memorySnapshots = {},
    maxMemorySamples = 120,  -- 2秒间隔，记录120个 = 4分钟
    lastMemoryTime = 0,
    memoryInterval = 2.0,  -- 2秒采样一次
    
    -- GC 追踪
    gcBefore = 0,
    gcScopes = {},  -- [name] = { allocations = KB }
    
    -- 时间记录起点
    sessionStart = 0,
    
    -- UI 相关
    showUI = false,
    lastReportTime = 0,
    reportInterval = 5.0,
    autoReport = false,
}
Profiler.__index = Profiler

-- 高精度时间
local clock = os.clock

-- ====================================================================
-- 初始化
-- ====================================================================

---初始化分析器
function Profiler:init()
    self.sessionStart = clock()
    self.scopes = {}
    self.callStack = {}
    self.frameTimes = {}
    self.frameIndex = 0
    self.memorySnapshots = {}
    self.lastMemoryTime = 0
    self.gcScopes = {}
    print("[Profiler] Initialized")
end

---重置所有数据
function Profiler:reset()
    self.scopes = {}
    self.callStack = {}
    self.frameTimes = {}
    self.frameIndex = 0
    self.memorySnapshots = {}
    self.gcScopes = {}
    self.sessionStart = clock()
    print("[Profiler] Data reset")
end

---设置启用状态
---@param enabled boolean
function Profiler:setEnabled(enabled)
    self.enabled = enabled
    print("[Profiler] " .. (enabled and "Enabled" or "Disabled"))
end

-- ====================================================================
-- 作用域追踪
-- ====================================================================

---开始追踪一个作用域
---@param name string 作用域名称
function Profiler:beginScope(name)
    if not self.enabled then return end
    
    local now = clock()
    
    -- 创建或获取作用域
    local scope = self.scopes[name]
    if not scope then
        scope = {
            name = name,
            totalTime = 0,
            callCount = 0,
            minTime = math.huge,
            maxTime = 0,
            startTime = 0,
            depth = 0,
        }
        self.scopes[name] = scope
    end
    
    -- 记录开始时间和深度
    scope.startTime = now
    scope.depth = #self.callStack
    
    -- 压入调用栈
    table.insert(self.callStack, name)
    
    -- GC 追踪
    if not self.gcScopes[name] then
        self.gcScopes[name] = { allocations = 0, samples = 0 }
    end
    self.gcBefore = collectgarbage("count")
end

---结束追踪一个作用域
---@param name string 作用域名称
---@return number elapsed 耗时(毫秒)
function Profiler:endScope(name)
    if not self.enabled then return 0 end
    
    local now = clock()
    local scope = self.scopes[name]
    
    if not scope or scope.startTime == 0 then
        print("[Profiler] Warning: endScope called without matching beginScope for: " .. name)
        return 0
    end
    
    -- 计算耗时
    local elapsed = now - scope.startTime
    
    -- 更新统计
    scope.totalTime = scope.totalTime + elapsed
    scope.callCount = scope.callCount + 1
    scope.minTime = math.min(scope.minTime, elapsed)
    scope.maxTime = math.max(scope.maxTime, elapsed)
    scope.startTime = 0  -- 重置
    
    -- 弹出调用栈
    if #self.callStack > 0 and self.callStack[#self.callStack] == name then
        table.remove(self.callStack)
    end
    
    -- GC 追踪
    local gcAfter = collectgarbage("count")
    local gcAlloc = gcAfter - self.gcBefore
    if gcAlloc > 0 then
        local gcScope = self.gcScopes[name]
        gcScope.allocations = gcScope.allocations + gcAlloc
        gcScope.samples = gcScope.samples + 1
    end
    
    return elapsed * 1000  -- 返回毫秒
end

---使用闭包测量代码块
---@param name string 作用域名称
---@param fn function 要测量的函数
---@return any 函数返回值
function Profiler:measure(name, fn)
    if not self.enabled then
        return fn()
    end
    
    self:beginScope(name)
    local result = fn()
    self:endScope(name)
    return result
end

-- ====================================================================
-- 帧时间追踪
-- ====================================================================

---记录帧时间
---@param deltaTime number 帧时间(秒)
function Profiler:recordFrame(deltaTime)
    if not self.enabled then return end
    
    self.frameIndex = self.frameIndex + 1
    local idx = ((self.frameIndex - 1) % self.maxFrameSamples) + 1
    self.frameTimes[idx] = deltaTime
    
    -- 定期内存快照
    local now = clock()
    if now - self.lastMemoryTime >= self.memoryInterval then
        self:recordMemory()
        self.lastMemoryTime = now
    end
    
    -- 自动报告
    if self.autoReport and now - self.lastReportTime >= self.reportInterval then
        self:printReport()
        self.lastReportTime = now
    end
end

---记录内存快照
function Profiler:recordMemory()
    collectgarbage("collect")
    local memKB = collectgarbage("count")
    
    local idx = (#self.memorySnapshots % self.maxMemorySamples) + 1
    self.memorySnapshots[idx] = {
        time = clock() - self.sessionStart,
        memory = memKB
    }
end

-- ====================================================================
-- 统计计算
-- ====================================================================

---获取帧时间统计
---@return table stats { avg, min, max, p50, p95, p99, fps }
function Profiler:getFrameStats()
    local count = math.min(self.frameIndex, self.maxFrameSamples)
    if count == 0 then
        return { avg = 0, min = 0, max = 0, p50 = 0, p95 = 0, p99 = 0, fps = 0, count = 0 }
    end
    
    -- 收集有效样本
    local samples = {}
    for i = 1, count do
        table.insert(samples, self.frameTimes[i])
    end
    table.sort(samples)
    
    -- 计算统计
    local sum = 0
    local minTime = math.huge
    local maxTime = 0
    for _, t in ipairs(samples) do
        sum = sum + t
        minTime = math.min(minTime, t)
        maxTime = math.max(maxTime, t)
    end
    
    local avg = sum / count
    local p50 = samples[math.ceil(count * 0.50)] or 0
    local p95 = samples[math.ceil(count * 0.95)] or 0
    local p99 = samples[math.ceil(count * 0.99)] or 0
    
    return {
        avg = avg,
        min = minTime,
        max = maxTime,
        p50 = p50,
        p95 = p95,
        p99 = p99,
        fps = avg > 0 and (1 / avg) or 0,
        count = count
    }
end

---获取热点函数列表（按总耗时排序）
---@param limit number|nil 限制数量
---@return table 热点列表
function Profiler:getHotspots(limit)
    limit = limit or 20
    
    local list = {}
    for name, scope in pairs(self.scopes) do
        if scope.callCount > 0 then
            table.insert(list, {
                name = name,
                totalTime = scope.totalTime,
                callCount = scope.callCount,
                avgTime = scope.totalTime / scope.callCount,
                minTime = scope.minTime,
                maxTime = scope.maxTime,
                percentOfSession = 0,
            })
        end
    end
    
    -- 按总耗时排序
    table.sort(list, function(a, b)
        return a.totalTime > b.totalTime
    end)
    
    -- 计算会话占比
    local sessionTime = clock() - self.sessionStart
    for _, item in ipairs(list) do
        item.percentOfSession = sessionTime > 0 and ((item.totalTime / sessionTime) * 100) or 0
    end
    
    -- 截取前 N 个
    local result = {}
    for i = 1, math.min(limit, #list) do
        result[i] = list[i]
    end
    
    return result
end

---获取 GC 分配热点
---@param limit number|nil 限制数量
---@return table GC热点列表
function Profiler:getGCHotspots(limit)
    limit = limit or 10
    
    local list = {}
    for name, data in pairs(self.gcScopes) do
        if data.allocations > 0 then
            table.insert(list, {
                name = name,
                totalAlloc = data.allocations,
                samples = data.samples,
                avgAlloc = data.samples > 0 and (data.allocations / data.samples) or 0
            })
        end
    end
    
    -- 按总分配排序
    table.sort(list, function(a, b)
        return a.totalAlloc > b.totalAlloc
    end)
    
    -- 截取前 N 个
    local result = {}
    for i = 1, math.min(limit, #list) do
        result[i] = list[i]
    end
    
    return result
end

---获取内存趋势
---@return table { current, peak, trend }
function Profiler:getMemoryStats()
    collectgarbage("collect")
    local current = collectgarbage("count")
    
    local peak = current
    local firstSample = current
    for _, snapshot in ipairs(self.memorySnapshots) do
        peak = math.max(peak, snapshot.memory)
        if firstSample == current then
            firstSample = snapshot.memory
        end
    end
    
    local trend = current - firstSample  -- 正数 = 增长
    
    return {
        current = current,
        peak = peak,
        trend = trend,
        samples = #self.memorySnapshots
    }
end

-- ====================================================================
-- 帧时间直方图
-- ====================================================================

---获取帧时间直方图数据
---@return table { bins, maxCount, distribution }
function Profiler:getFrameHistogram()
    local count = math.min(self.frameIndex, self.maxFrameSamples)
    if count == 0 then
        return { bins = {}, maxCount = 0, distribution = {} }
    end
    
    -- 定义区间 (毫秒)
    local binEdges = { 0, 8, 16, 24, 33, 50, 66, 100, 200, math.huge }
    local binLabels = { "<8", "8-16", "16-24", "24-33", "33-50", "50-66", "66-100", "100-200", ">200" }
    local bins = {}
    for i = 1, #binLabels do
        bins[i] = { label = binLabels[i], count = 0 }
    end
    
    -- 统计
    for i = 1, count do
        local ms = self.frameTimes[i] * 1000
        for j = 1, #binEdges - 1 do
            if ms >= binEdges[j] and ms < binEdges[j + 1] then
                bins[j].count = bins[j].count + 1
                break
            end
        end
    end
    
    -- 计算最大计数（用于归一化）
    local maxCount = 0
    for _, bin in ipairs(bins) do
        maxCount = math.max(maxCount, bin.count)
    end
    
    -- 计算分布百分比
    local distribution = {}
    for i, bin in ipairs(bins) do
        distribution[i] = {
            label = bin.label,
            count = bin.count,
            percent = (bin.count / count) * 100
        }
    end
    
    return {
        bins = bins,
        maxCount = maxCount,
        distribution = distribution,
        totalFrames = count
    }
end

-- ====================================================================
-- 报告生成
-- ====================================================================

---生成文本报告
---@return string 报告文本
function Profiler:generateReport()
    local lines = {}
    
    table.insert(lines, string.rep("=", 60))
    table.insert(lines, "         PERFORMANCE PROFILER REPORT")
    table.insert(lines, string.rep("=", 60))
    table.insert(lines, string.format("Session Time: %.1f seconds", clock() - self.sessionStart))
    table.insert(lines, "")
    
    -- 帧时间统计
    local frameStats = self:getFrameStats()
    table.insert(lines, "📊 FRAME TIME STATISTICS")
    table.insert(lines, string.rep("-", 45))
    table.insert(lines, string.format("  Samples:  %d frames", frameStats.count))
    table.insert(lines, string.format("  Average:  %.2f ms (%.1f FPS)", frameStats.avg * 1000, frameStats.fps))
    table.insert(lines, string.format("  Min:      %.2f ms", frameStats.min * 1000))
    table.insert(lines, string.format("  Max:      %.2f ms", frameStats.max * 1000))
    table.insert(lines, string.format("  P50:      %.2f ms", frameStats.p50 * 1000))
    table.insert(lines, string.format("  P95:      %.2f ms", frameStats.p95 * 1000))
    table.insert(lines, string.format("  P99:      %.2f ms", frameStats.p99 * 1000))
    table.insert(lines, "")
    
    -- 内存统计
    local memStats = self:getMemoryStats()
    table.insert(lines, "💾 MEMORY USAGE")
    table.insert(lines, string.rep("-", 45))
    table.insert(lines, string.format("  Current:  %.2f MB", memStats.current / 1024))
    table.insert(lines, string.format("  Peak:     %.2f MB", memStats.peak / 1024))
    local trendStr = memStats.trend >= 0 and "+" or ""
    table.insert(lines, string.format("  Trend:    %s%.2f KB", trendStr, memStats.trend))
    table.insert(lines, "")
    
    -- 热点函数
    local hotspots = self:getHotspots(15)
    if #hotspots > 0 then
        table.insert(lines, "🔥 TOP HOTSPOTS (by total time)")
        table.insert(lines, string.rep("-", 45))
        table.insert(lines, string.format("  %-20s %8s %6s %8s", "Scope", "Total", "Calls", "Avg"))
        table.insert(lines, string.rep("-", 45))
        for _, h in ipairs(hotspots) do
            local percent = h.percentOfSession
            local heat = ""
            if percent > 10 then heat = "!!"
            elseif percent > 5 then heat = "! "
            elseif percent > 1 then heat = "* "
            else heat = "- " end
            
            table.insert(lines, string.format("%s%-18s %7.0fms %6d %7.2fms", 
                heat, 
                string.sub(h.name, 1, 18), 
                h.totalTime * 1000, 
                h.callCount, 
                h.avgTime * 1000))
        end
        table.insert(lines, "")
    end
    
    -- GC 分配热点
    local gcHotspots = self:getGCHotspots(10)
    if #gcHotspots > 0 then
        table.insert(lines, "🗑️ GC ALLOCATION HOTSPOTS")
        table.insert(lines, string.rep("-", 45))
        table.insert(lines, string.format("  %-20s %10s %6s", "Scope", "Total(KB)", "Avg"))
        table.insert(lines, string.rep("-", 45))
        for _, g in ipairs(gcHotspots) do
            table.insert(lines, string.format("  %-20s %10.1f %6.1f", 
                string.sub(g.name, 1, 20), 
                g.totalAlloc, 
                g.avgAlloc))
        end
        table.insert(lines, "")
    end
    
    table.insert(lines, string.rep("=", 60))
    
    return table.concat(lines, "\n")
end

---打印性能报告到控制台
function Profiler:printReport()
    print("\n" .. self:generateReport())
end

---获取简短摘要
---@return string 简短报告
function Profiler:getSummary()
    local frameStats = self:getFrameStats()
    local memStats = self:getMemoryStats()
    local hotspots = self:getHotspots(3)
    
    local lines = {}
    table.insert(lines, string.format("FPS: %.0f | P95: %.1fms | Mem: %.1fMB", 
        frameStats.fps, frameStats.p95 * 1000, memStats.current / 1024))
    
    if #hotspots > 0 then
        local top = hotspots[1]
        table.insert(lines, string.format("Top: %s (%.0fms)", top.name, top.totalTime * 1000))
    end
    
    return table.concat(lines, " | ")
end

-- ====================================================================
-- UI 相关
-- ====================================================================

---切换 UI 显示
function Profiler:toggleUI()
    self.showUI = not self.showUI
end

---是否显示 UI
---@return boolean
function Profiler:isUIVisible()
    return self.showUI
end

-- ====================================================================
-- 便捷装饰器
-- ====================================================================

---创建一个带追踪的函数包装器
---@param name string 作用域名称
---@param fn function 原函数
---@return function 包装后的函数
function Profiler:wrap(name, fn)
    local self_ = self
    return function(...)
        self_:beginScope(name)
        local results = {fn(...)}
        self_:endScope(name)
        return table.unpack(results)
    end
end

---获取会话时间
---@return number 秒
function Profiler:getSessionTime()
    return clock() - self.sessionStart
end

-- ====================================================================
-- 单例初始化
-- ====================================================================

Profiler:init()

return Profiler

