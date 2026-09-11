-- Shim: allow require("cjson") to work.
-- cjson is an engine built-in global, not a Lua module file.
-- AI agents trained on standard Lua idioms write require("cjson"),
-- this file makes that pattern work transparently.
---@diagnostic disable-next-line: undefined-global
return cjson
