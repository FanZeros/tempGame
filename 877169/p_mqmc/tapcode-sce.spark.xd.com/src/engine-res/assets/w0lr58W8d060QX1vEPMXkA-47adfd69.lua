---屏幕取色工具（静态调用，无状态）。
---@class ScreenColorPicker
local ScreenColorPicker = {}

local function ClampInt(value, minValue, maxValue)
    value = math.floor(value or 0)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

---读取屏幕像素坐标处 backbuffer 的颜色。
---注意：TakeScreenShot 会抓取整屏来读取单个像素，开销大——只用于点击/低频取色，
---切勿每帧调用。
---@param x number 屏幕像素 X
---@param y number 屏幕像素 Y
---@param options table|nil { flipY = boolean }
---@return Color|nil
function ScreenColorPicker.Pick(x, y, options)
    if not graphics then
        return nil
    end

    local image = Image()
    if not graphics:TakeScreenShot(image) then
        return nil
    end

    local width = image.width
    local height = image.height
    if width <= 0 or height <= 0 then
        return nil
    end

    local px = ClampInt(x, 0, width - 1)
    local py = ClampInt(y, 0, height - 1)
    if options and options.flipY then
        py = height - 1 - py
    end

    return image:GetPixel(px, py)
end

return ScreenColorPicker
