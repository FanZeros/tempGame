-- ====================================================================
-- Renderer_Utils.lua — Renderer 子模块共享的工具函数与常量
-- ====================================================================

local GS = require("GameState")

local Utils = {}

-- 方向偏移常量
Utils.OFFSETS_4 = {{-1,0},{1,0},{0,-1},{0,1}}
Utils.OFFSETS_8 = {{-1,0},{1,0},{0,-1},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}

--- 安全的进度比率计算（防止除零）
---@param timer number 当前计时
---@param duration number 总时长
---@param default? number 当 duration<=0 时的默认值，默认 1.0
---@return number 0~1 之间的进度值
function Utils.safeProgress(timer, duration, default)
    if not duration or duration <= 0 then return default or 1.0 end
    return math.min(1.0, timer / duration)
end

---@param vg any NanoVG context
---@param x number 文字 x
---@param y number 文字 y
---@param text string 文字内容
---@param r number 正文红 0-255
---@param g number 正文绿 0-255
---@param b number 正文蓝 0-255
---@param a number 正文透明度 0-255
---@param outlineA? number 未使用（保留参数兼容性）
function Utils.drawTextOutlined(vg, x, y, text, r, g, b, a, outlineA)
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgText(vg, x, y, text, nil)
end

--- 检测鼠标是否悬停在矩形区域上
---@param x number 区域左上角 x
---@param y number 区域左上角 y
---@param w number 区域宽度
---@param h number 区域高度
---@return boolean
function Utils.isHovered(x, y, w, h)
    local mx, my = GS.hoverX, GS.hoverY
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

--- 在按钮上绘制半透明白色高亮叠层（hover 时调用）
---@param vg any NanoVG context
---@param x number 按钮 x
---@param y number 按钮 y
---@param w number 按钮宽度
---@param h number 按钮高度
---@param r number 圆角半径
---@param alpha? number 高亮透明度（默认 40）
function Utils.drawHoverHighlight(vg, x, y, w, h, r, alpha)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r or 3)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha or 40))
    nvgFill(vg)
end

--- 千分位格式化数字（如 1234567 → "1,234,567"）
---@param n number
---@return string
function Utils.fmtNum(n)
    local s = tostring(math.floor(n))
    local len = #s
    if len <= 3 then return s end
    local parts = {}
    local r = len % 3
    if r > 0 then parts[#parts + 1] = s:sub(1, r) end
    for i = r + 1, len, 3 do
        parts[#parts + 1] = s:sub(i, i + 2)
    end
    return table.concat(parts, ",")
end

return Utils
