-- Shim: allow require("bit") to work.
-- bit is an engine built-in global, not a Lua module file.
---@diagnostic disable-next-line: undefined-global
return bit
