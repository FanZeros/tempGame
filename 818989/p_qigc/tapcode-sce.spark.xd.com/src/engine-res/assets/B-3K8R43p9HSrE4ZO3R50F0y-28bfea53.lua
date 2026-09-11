-- PlatformUtils.lua
-- 平台检测和通用工具
-- 来源：从 Sample.lua 提取

---@class PlatformUtils
local PlatformUtils = {}

-- 缓存平台字符串（避免重复调用）
---@type string|nil
local cachedPlatform = nil

---获取当前平台名称
---@return string 平台名称："Windows", "Linux", "Mac", "Android", "iOS", "HarmonyOS", "Web"
function PlatformUtils.GetPlatform()
    if cachedPlatform == nil then
        cachedPlatform = GetPlatform()
    end
    return cachedPlatform
end

---判断是否为移动平台
---@return boolean 是否为 Android / iOS / HarmonyOS
function PlatformUtils.IsMobilePlatform()
    local platform = PlatformUtils.GetPlatform()
    return platform == "Android" or platform == "iOS" or platform == "HarmonyOS"
end

---判断是否为桌面平台
---@return boolean 是否为 Windows, Linux 或 Mac
function PlatformUtils.IsDesktopPlatform()
    local platform = PlatformUtils.GetPlatform()
    return platform == "Windows" or platform == "Linux" or platform == "Mac"
end

---判断是否为 Web 平台
---@return boolean 是否为 Web (WebAssembly)
function PlatformUtils.IsWebPlatform()
    return PlatformUtils.GetPlatform() == "Web"
end

---判断是否为 Android 平台
---@return boolean
function PlatformUtils.IsAndroid()
    return PlatformUtils.GetPlatform() == "Android"
end

---判断是否为 iOS 平台
---@return boolean
function PlatformUtils.IsIOS()
    return PlatformUtils.GetPlatform() == "iOS"
end

---判断是否为 HarmonyOS / OpenHarmony 平台
---@return boolean
function PlatformUtils.IsHarmonyOS()
    return PlatformUtils.GetPlatform() == "HarmonyOS"
end

---判断是否为 Windows 平台
---@return boolean
function PlatformUtils.IsWindows()
    return PlatformUtils.GetPlatform() == "Windows"
end

---判断是否为 Linux 平台
---@return boolean
function PlatformUtils.IsLinux()
    return PlatformUtils.GetPlatform() == "Linux"
end

---判断是否为 Mac 平台
---@return boolean
function PlatformUtils.IsMac()
    return PlatformUtils.GetPlatform() == "Mac"
end

---判断是否支持触摸输入
---@return boolean 移动平台或启用了触摸模拟
function PlatformUtils.IsTouchSupported()
    return PlatformUtils.IsMobilePlatform() or input.touchEmulation
end

---判断是否需要虚拟摇杆
---@return boolean 移动平台或启用了触摸模拟
function PlatformUtils.NeedsVirtualJoystick()
    return PlatformUtils.IsTouchSupported()
end

---获取平台友好名称
---@return string 适合显示的平台名称
function PlatformUtils.GetPlatformDisplayName()
    local platform = PlatformUtils.GetPlatform()
    local displayNames = {
        Windows = "Windows",
        Linux = "Linux",
        Mac = "macOS",
        Android = "Android",
        iOS = "iOS",
        HarmonyOS = "HarmonyOS",
        Web = "Web (Browser)"
    }
    return displayNames[platform] or platform
end

return PlatformUtils
