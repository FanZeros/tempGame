-- Shim: allow require("cmsgpack") to work.
-- cmsgpack is an engine built-in global, not a Lua module file.
---@diagnostic disable-next-line: undefined-global
return cmsgpack
