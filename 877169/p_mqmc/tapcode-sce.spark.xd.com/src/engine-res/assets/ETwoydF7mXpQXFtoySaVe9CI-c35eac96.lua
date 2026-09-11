require("InputExtensions")
require("ResourceCacheExtensions")

do
    local ok, err = pcall(function() require("i18n") end)
    if not ok then
        log:Write(LOG_ERROR, "[i18n] require('i18n') FAILED: " .. tostring(err))
    end
end
