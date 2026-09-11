-- ====================================================================
-- urhox-libs/Profiler/ProfilerUI.lua
-- 性能分析器可视化面板 - 基于 urhox-libs/UI
--
-- 功能:
--   - 实时性能统计 (FPS, 帧时间, 内存)
--   - 帧时间直方图
--   - 热点函数列表
--   - 完整报告显示 (可展开)
--   - 重置/导出按钮
--
-- 使用方法:
--   local ProfilerUI = require("urhox-libs/Profiler/ProfilerUI")
--   local ui = ProfilerUI:new()
--   uiManager:addWidget(ui:build())
--
--   -- 在 Update 中调用
--   ui:update()
--
--   -- 切换显示
--   ui:toggle()
--
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local Profiler = require("urhox-libs/Profiler/Profiler")

---@class ProfilerUI
local ProfilerUI = {}
ProfilerUI.__index = ProfilerUI

-- UI 配置
local CONFIG = {
    width = 380,
    maxHotspots = 10,
    maxHistogramBars = 9,
    maxReportLines = 50,  -- 报告最大行数
    barHeight = 14,
    updateInterval = 0.5,  -- 0.5秒更新一次
    colors = {
        background = {15, 15, 25, 240},
        headerBg = {30, 30, 50, 255},
        sectionBg = {25, 25, 40, 255},
        text = {220, 220, 230, 255},
        textDim = {140, 140, 160, 255},
        accent = {100, 180, 255, 255},
        success = {80, 200, 120, 255},
        warning = {255, 180, 80, 255},
        danger = {255, 100, 100, 255},
        buttonBg = {50, 50, 70, 255},
        buttonHover = {70, 70, 100, 255},
        reportBg = {20, 20, 35, 255},
    },
}

---创建 ProfilerUI 实例
---@return ProfilerUI
function ProfilerUI:new()
    local self = setmetatable({}, ProfilerUI)
    self.root = nil
    self.visible = false
    self.lastUpdate = 0
    self.labels = {}
    self.showReport = false  -- 是否显示完整报告
    return self
end

---创建报告行
---@param index number 行索引
---@return Widget
function ProfilerUI:createReportLine(index)
    return UI.Label {
        id = "report_line_" .. index,
        text = "",
        fontSize = 8,
        fontColor = CONFIG.colors.text,
        width = "100%",
        height = 12,
        visible = false,
    }
end

---创建热点行
---@param index number 行索引
---@return Widget
function ProfilerUI:createHotspotRow(index)
    return UI.Row {
        id = "hotspot_row_" .. index,
        height = 16,
        alignItems = "center",
        gap = 6,
        visible = false,
        
        -- 热度指示器
        UI.Label {
            id = "hotspot_heat_" .. index,
            text = "-",
            fontSize = 9,
            fontColor = CONFIG.colors.success,
            width = 14,
            textAlign = "center",
        },
        
        -- 名称
        UI.Label {
            id = "hotspot_name_" .. index,
            text = "",
            fontSize = 9,
            fontColor = CONFIG.colors.text,
            width = 140,
            textAlign = "left",
        },
        
        -- 时间
        UI.Label {
            id = "hotspot_time_" .. index,
            text = "",
            fontSize = 9,
            fontColor = CONFIG.colors.accent,
            width = 70,
            textAlign = "right",
        },
        
        -- 调用次数
        UI.Label {
            id = "hotspot_calls_" .. index,
            text = "",
            fontSize = 9,
            fontColor = CONFIG.colors.textDim,
            width = 60,
            textAlign = "right",
        },
        
        -- 平均时间
        UI.Label {
            id = "hotspot_avg_" .. index,
            text = "",
            fontSize = 9,
            fontColor = CONFIG.colors.textDim,
            width = 55,
            textAlign = "right",
        },
    }
end

---创建直方图条
---@param index number 条索引
---@return Widget
function ProfilerUI:createHistogramBar(index)
    return UI.Row {
        id = "histogram_row_" .. index,
        height = CONFIG.barHeight,
        alignItems = "center",
        gap = 4,
        
        -- 标签
        UI.Label {
            id = "histogram_label_" .. index,
            text = "",
            fontSize = 8,
            fontColor = CONFIG.colors.textDim,
            width = 45,
            textAlign = "right",
        },
        
        -- 进度条背景
        UI.Panel {
            id = "histogram_bar_bg_" .. index,
            width = 180,
            height = 10,
            backgroundColor = {40, 40, 60, 255},
            borderRadius = 2,
            
            -- 进度条填充
            UI.Panel {
                id = "histogram_bar_fill_" .. index,
                width = 0,
                height = "100%",
                backgroundColor = CONFIG.colors.accent,
                borderRadius = 2,
            },
        },
        
        -- 百分比
        UI.Label {
            id = "histogram_percent_" .. index,
            text = "0%",
            fontSize = 8,
            fontColor = CONFIG.colors.text,
            width = 40,
            textAlign = "left",
        },
    }
end

---构建 UI
---@return Widget 根 Widget
function ProfilerUI:build()
    -- 创建热点行
    local hotspotRows = {}
    for i = 1, CONFIG.maxHotspots do
        table.insert(hotspotRows, self:createHotspotRow(i))
    end
    
    -- 创建直方图条
    local histogramBars = {}
    for i = 1, CONFIG.maxHistogramBars do
        table.insert(histogramBars, self:createHistogramBar(i))
    end
    
    -- 创建报告行
    local reportLines = {}
    for i = 1, CONFIG.maxReportLines do
        table.insert(reportLines, self:createReportLine(i))
    end
    
    self.root = UI.Panel {
        id = "profiler_ui",
        position = "absolute",
        top = 10,
        right = 10,
        width = CONFIG.width,
        backgroundColor = CONFIG.colors.background,
        borderRadius = 8,
        flexDirection = "column",
        visible = false,
        
        -- 标题栏
        UI.Panel {
            id = "profiler_header",
            width = "100%",
            height = 36,
            backgroundColor = CONFIG.colors.headerBg,
            borderTopLeftRadius = 8,
            borderTopRightRadius = 8,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 12,
            paddingRight = 8,
            
            UI.Label {
                text = "⚡ Performance Profiler",
                fontSize = 12,
                fontWeight = "bold",
                fontColor = CONFIG.colors.accent,
                flex = 1,
            },
            
            -- FPS 显示
            UI.Label {
                id = "profiler_fps",
                text = "-- FPS",
                fontSize = 11,
                fontColor = CONFIG.colors.success,
                marginRight = 8,
            },
            
            -- 关闭按钮
            UI.Panel {
                id = "btn_close",
                width = 24,
                height = 24,
                backgroundColor = {80, 80, 100, 255},
                borderRadius = 4,
                alignItems = "center",
                justifyContent = "center",
                cursor = "pointer",
                
                UI.Label {
                    text = "×",
                    fontSize = 14,
                    fontColor = CONFIG.colors.text,
                },
            },
        },
        
        -- 内容区域
        UI.Panel {
            id = "profiler_content",
            width = "100%",
            flexDirection = "column",
            padding = 10,
            gap = 10,
            
            -- 帧时间统计
            UI.Panel {
                width = "100%",
                backgroundColor = CONFIG.colors.sectionBg,
                borderRadius = 6,
                padding = 10,
                flexDirection = "column",
                gap = 6,
                
                UI.Label {
                    text = "📊 Frame Time",
                    fontSize = 10,
                    fontWeight = "bold",
                    fontColor = CONFIG.colors.text,
                },
                
                UI.Row {
                    gap = 20,
                    
                    UI.Column {
                        gap = 2,
                        UI.Label { text = "Avg", fontSize = 8, fontColor = CONFIG.colors.textDim },
                        UI.Label { id = "frame_avg", text = "--", fontSize = 11, fontColor = CONFIG.colors.text },
                    },
                    
                    UI.Column {
                        gap = 2,
                        UI.Label { text = "P95", fontSize = 8, fontColor = CONFIG.colors.textDim },
                        UI.Label { id = "frame_p95", text = "--", fontSize = 11, fontColor = CONFIG.colors.warning },
                    },
                    
                    UI.Column {
                        gap = 2,
                        UI.Label { text = "P99", fontSize = 8, fontColor = CONFIG.colors.textDim },
                        UI.Label { id = "frame_p99", text = "--", fontSize = 11, fontColor = CONFIG.colors.danger },
                    },
                    
                    UI.Column {
                        gap = 2,
                        UI.Label { text = "Max", fontSize = 8, fontColor = CONFIG.colors.textDim },
                        UI.Label { id = "frame_max", text = "--", fontSize = 11, fontColor = CONFIG.colors.danger },
                    },
                },
            },
            
            -- 内存统计
            UI.Panel {
                width = "100%",
                backgroundColor = CONFIG.colors.sectionBg,
                borderRadius = 6,
                padding = 10,
                flexDirection = "column",
                gap = 6,
                
                UI.Label {
                    text = "💾 Memory",
                    fontSize = 10,
                    fontWeight = "bold",
                    fontColor = CONFIG.colors.text,
                },
                
                UI.Row {
                    gap = 20,
                    
                    UI.Column {
                        gap = 2,
                        UI.Label { text = "Current", fontSize = 8, fontColor = CONFIG.colors.textDim },
                        UI.Label { id = "mem_current", text = "--", fontSize = 11, fontColor = CONFIG.colors.text },
                    },
                    
                    UI.Column {
                        gap = 2,
                        UI.Label { text = "Peak", fontSize = 8, fontColor = CONFIG.colors.textDim },
                        UI.Label { id = "mem_peak", text = "--", fontSize = 11, fontColor = CONFIG.colors.warning },
                    },
                    
                    UI.Column {
                        gap = 2,
                        UI.Label { text = "Trend", fontSize = 8, fontColor = CONFIG.colors.textDim },
                        UI.Label { id = "mem_trend", text = "--", fontSize = 11, fontColor = CONFIG.colors.text },
                    },
                },
            },
            
            -- 帧时间直方图
            UI.Panel {
                width = "100%",
                backgroundColor = CONFIG.colors.sectionBg,
                borderRadius = 6,
                padding = 10,
                flexDirection = "column",
                gap = 4,
                
                UI.Label {
                    text = "📈 Frame Distribution",
                    fontSize = 10,
                    fontWeight = "bold",
                    fontColor = CONFIG.colors.text,
                    marginBottom = 4,
                },
                
                table.unpack(histogramBars),
            },
            
            -- 热点函数
            UI.Panel {
                width = "100%",
                backgroundColor = CONFIG.colors.sectionBg,
                borderRadius = 6,
                padding = 10,
                flexDirection = "column",
                gap = 3,
                
                -- 标题行
                UI.Row {
                    marginBottom = 4,
                    
                    UI.Label {
                        text = "🔥 Hotspots",
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = CONFIG.colors.text,
                        flex = 1,
                    },
                    
                    UI.Label {
                        text = "Total",
                        fontSize = 8,
                        fontColor = CONFIG.colors.textDim,
                        width = 70,
                        textAlign = "right",
                    },
                    
                    UI.Label {
                        text = "Calls",
                        fontSize = 8,
                        fontColor = CONFIG.colors.textDim,
                        width = 60,
                        textAlign = "right",
                    },
                    
                    UI.Label {
                        text = "Avg",
                        fontSize = 8,
                        fontColor = CONFIG.colors.textDim,
                        width = 55,
                        textAlign = "right",
                    },
                },
                
                table.unpack(hotspotRows),
                
                UI.Label {
                    id = "hotspot_empty",
                    text = "(No profiling data yet)",
                    fontSize = 9,
                    fontColor = CONFIG.colors.textDim,
                    textAlign = "center",
                    width = "100%",
                },
            },
            
            -- 完整报告区域 (可折叠)
            UI.Panel {
                id = "report_section",
                width = "100%",
                backgroundColor = CONFIG.colors.sectionBg,
                borderRadius = 6,
                padding = 10,
                flexDirection = "column",
                gap = 4,
                visible = false,
                
                UI.Label {
                    text = "📋 Full Report",
                    fontSize = 10,
                    fontWeight = "bold",
                    fontColor = CONFIG.colors.text,
                    marginBottom = 4,
                },
                
                UI.Panel {
                    id = "report_container",
                    width = "100%",
                    maxHeight = 350,
                    backgroundColor = CONFIG.colors.reportBg,
                    borderRadius = 4,
                    padding = 6,
                    flexDirection = "column",
                    gap = 0,
                    
                    table.unpack(reportLines),
                },
            },
            
            -- 按钮区域
            UI.Row {
                width = "100%",
                gap = 8,
                justifyContent = "center",
                marginTop = 4,
                
                -- 重置按钮
                UI.Panel {
                    id = "btn_reset",
                    width = 100,
                    height = 28,
                    backgroundColor = CONFIG.colors.buttonBg,
                    borderRadius = 4,
                    alignItems = "center",
                    justifyContent = "center",
                    cursor = "pointer",
                    
                    UI.Label {
                        text = "🔄 Reset",
                        fontSize = 10,
                        fontColor = CONFIG.colors.text,
                    },
                },
                
                -- 报告按钮
                UI.Panel {
                    id = "btn_report",
                    width = 100,
                    height = 28,
                    backgroundColor = CONFIG.colors.buttonBg,
                    borderRadius = 4,
                    alignItems = "center",
                    justifyContent = "center",
                    cursor = "pointer",
                    
                    UI.Label {
                        id = "btn_report_text",
                        text = "📋 Report",
                        fontSize = 10,
                        fontColor = CONFIG.colors.text,
                    },
                },
                
                -- 打印到控制台按钮
                UI.Panel {
                    id = "btn_print",
                    width = 100,
                    height = 28,
                    backgroundColor = CONFIG.colors.buttonBg,
                    borderRadius = 4,
                    alignItems = "center",
                    justifyContent = "center",
                    cursor = "pointer",
                    
                    UI.Label {
                        text = "🖨️ Print",
                        fontSize = 10,
                        fontColor = CONFIG.colors.text,
                    },
                },
            },
            
            -- 提示
            UI.Label {
                id = "profiler_hint",
                text = "` toggle | Ctrl+` report | Alt+` reset",
                fontSize = 8,
                fontColor = CONFIG.colors.textDim,
                textAlign = "center",
                width = "100%",
                marginTop = 4,
            },
        },
    }
    
    -- 缓存引用并绑定事件
    self:cacheReferences()
    self:bindEvents()
    
    return self.root
end

---缓存 UI 组件引用
function ProfilerUI:cacheReferences()
    if not self.root then return end
    
    self.labels.fps = self.root:FindById("profiler_fps")
    self.labels.frameAvg = self.root:FindById("frame_avg")
    self.labels.frameP95 = self.root:FindById("frame_p95")
    self.labels.frameP99 = self.root:FindById("frame_p99")
    self.labels.frameMax = self.root:FindById("frame_max")
    self.labels.memCurrent = self.root:FindById("mem_current")
    self.labels.memPeak = self.root:FindById("mem_peak")
    self.labels.memTrend = self.root:FindById("mem_trend")
    self.labels.hotspotEmpty = self.root:FindById("hotspot_empty")
    self.labels.reportSection = self.root:FindById("report_section")
    self.labels.btnReportText = self.root:FindById("btn_report_text")
    
    -- 报告行
    self.labels.reportLines = {}
    for i = 1, CONFIG.maxReportLines do
        self.labels.reportLines[i] = self.root:FindById("report_line_" .. i)
    end
    
    -- 按钮
    self.buttons = {
        close = self.root:FindById("btn_close"),
        reset = self.root:FindById("btn_reset"),
        report = self.root:FindById("btn_report"),
        print = self.root:FindById("btn_print"),
    }
    
    -- 热点行
    self.labels.hotspotRows = {}
    for i = 1, CONFIG.maxHotspots do
        self.labels.hotspotRows[i] = {
            row = self.root:FindById("hotspot_row_" .. i),
            heat = self.root:FindById("hotspot_heat_" .. i),
            name = self.root:FindById("hotspot_name_" .. i),
            time = self.root:FindById("hotspot_time_" .. i),
            calls = self.root:FindById("hotspot_calls_" .. i),
            avg = self.root:FindById("hotspot_avg_" .. i),
        }
    end
    
    -- 直方图
    self.labels.histogramBars = {}
    for i = 1, CONFIG.maxHistogramBars do
        self.labels.histogramBars[i] = {
            label = self.root:FindById("histogram_label_" .. i),
            fill = self.root:FindById("histogram_bar_fill_" .. i),
            percent = self.root:FindById("histogram_percent_" .. i),
        }
    end
end

---绑定按钮事件
function ProfilerUI:bindEvents()
    if not self.buttons then return end
    
    -- 关闭按钮
    if self.buttons.close then
        self.buttons.close:OnClick(function()
            self:setVisible(false)
        end)
    end
    
    -- 重置按钮
    if self.buttons.reset then
        self.buttons.reset:OnClick(function()
            Profiler:reset()
            self:updateDisplay()
        end)
    end
    
    -- 报告按钮 (切换报告显示)
    if self.buttons.report then
        self.buttons.report:OnClick(function()
            self:toggleReport()
        end)
    end
    
    -- 打印按钮
    if self.buttons.print then
        self.buttons.print:OnClick(function()
            Profiler:printReport()
        end)
    end
end

---切换报告显示
function ProfilerUI:toggleReport()
    self.showReport = not self.showReport
    
    if self.labels.reportSection then
        self.labels.reportSection:SetVisible(self.showReport)
    end
    
    if self.labels.btnReportText then
        self.labels.btnReportText:SetText(self.showReport and "📋 Hide" or "📋 Report")
    end
    
    if self.showReport then
        self:updateReportText()
    end
end

---更新报告文本
function ProfilerUI:updateReportText()
    if not self.labels.reportLines then return end
    
    local report = Profiler:generateReport()
    
    -- 分行
    local lines = {}
    for line in string.gmatch(report .. "\n", "([^\n]*)\n") do
        table.insert(lines, line)
    end
    
    -- 更新每行
    for i, labelWidget in ipairs(self.labels.reportLines) do
        if labelWidget then
            local lineText = lines[i] or ""
            if lineText ~= "" then
                labelWidget:SetText(lineText)
                labelWidget:SetVisible(true)
            else
                labelWidget:SetVisible(i <= #lines)  -- 空行也显示（保持间距）
                labelWidget:SetText("")
            end
        end
    end
end

---切换可见性
function ProfilerUI:toggle()
    self:setVisible(not self.visible)
end

---设置可见性
---@param visible boolean
function ProfilerUI:setVisible(visible)
    self.visible = visible
    if self.root then
        self.root:SetVisible(visible)
    end
end

---获取可见性
---@return boolean
function ProfilerUI:isVisible()
    return self.visible
end

---更新显示
function ProfilerUI:updateDisplay()
    if not self.visible or not self.root then return end
    
    -- 帧时间统计
    local frameStats = Profiler:getFrameStats()
    
    if self.labels.fps then
        local fps = frameStats.fps
        local fpsColor = fps >= 55 and CONFIG.colors.success 
            or (fps >= 30 and CONFIG.colors.warning or CONFIG.colors.danger)
        self.labels.fps:SetText(string.format("%.0f FPS", fps))
        self.labels.fps:SetFontColor(fpsColor)
    end
    
    if self.labels.frameAvg then
        self.labels.frameAvg:SetText(string.format("%.1fms", frameStats.avg * 1000))
    end
    if self.labels.frameP95 then
        self.labels.frameP95:SetText(string.format("%.1fms", frameStats.p95 * 1000))
    end
    if self.labels.frameP99 then
        self.labels.frameP99:SetText(string.format("%.1fms", frameStats.p99 * 1000))
    end
    if self.labels.frameMax then
        self.labels.frameMax:SetText(string.format("%.1fms", frameStats.max * 1000))
    end
    
    -- 内存统计
    local memStats = Profiler:getMemoryStats()
    
    if self.labels.memCurrent then
        self.labels.memCurrent:SetText(string.format("%.1fMB", memStats.current / 1024))
    end
    if self.labels.memPeak then
        self.labels.memPeak:SetText(string.format("%.1fMB", memStats.peak / 1024))
    end
    if self.labels.memTrend then
        local trend = memStats.trend
        local trendStr = trend >= 0 and string.format("+%.1fKB", trend) or string.format("%.1fKB", trend)
        local trendColor = trend > 100 and CONFIG.colors.danger 
            or (trend > 0 and CONFIG.colors.warning or CONFIG.colors.success)
        self.labels.memTrend:SetText(trendStr)
        self.labels.memTrend:SetFontColor(trendColor)
    end
    
    -- 直方图
    local histogram = Profiler:getFrameHistogram()
    if histogram.distribution then
        for i, bar in ipairs(self.labels.histogramBars) do
            local data = histogram.distribution[i]
            if data and bar.label then
                bar.label:SetText(data.label)
                local fillWidth = math.floor((data.count / math.max(histogram.maxCount, 1)) * 180)
                bar.fill:SetWidth(fillWidth)
                bar.percent:SetText(string.format("%.1f%%", data.percent))
            end
        end
    end
    
    -- 热点函数
    local hotspots = Profiler:getHotspots(CONFIG.maxHotspots)
    local hasHotspots = #hotspots > 0
    
    if self.labels.hotspotEmpty then
        self.labels.hotspotEmpty:SetVisible(not hasHotspots)
    end
    
    for i, row in ipairs(self.labels.hotspotRows) do
        local h = hotspots[i]
        if h and row.row then
            row.row:SetVisible(true)
            row.name:SetText(string.sub(h.name, 1, 20))
            row.time:SetText(string.format("%.0fms", h.totalTime * 1000))
            row.calls:SetText(tostring(h.callCount))
            row.avg:SetText(string.format("%.2fms", h.avgTime * 1000))
            
            -- 热度指示
            local percent = h.percentOfSession
            local heatSymbol, heatColor
            if percent > 10 then
                heatSymbol = "!!"
                heatColor = CONFIG.colors.danger
            elseif percent > 5 then
                heatSymbol = "!"
                heatColor = CONFIG.colors.warning
            elseif percent > 1 then
                heatSymbol = "*"
                heatColor = {255, 255, 100, 255}
            else
                heatSymbol = "-"
                heatColor = CONFIG.colors.success
            end
            row.heat:SetText(heatSymbol)
            row.heat:SetFontColor(heatColor)
        elseif row.row then
            row.row:SetVisible(false)
        end
    end
    
    -- 更新报告（如果展开）
    if self.showReport then
        self:updateReportText()
    end
end

---每帧更新
function ProfilerUI:update()
    if not self.visible then return end
    
    local now = os.clock()
    if now - self.lastUpdate >= CONFIG.updateInterval then
        self:updateDisplay()
        self.lastUpdate = now
    end
end

---设置快捷键提示文本
---@param keyName string 快捷键名称
function ProfilerUI:setHotkeyHint(keyName)
    local hint = self.root and self.root:FindById("profiler_hint")
    if hint then
        hint:SetText("Press " .. keyName .. " to toggle")
    end
end

return ProfilerUI

