-- 旧版大厅总开关（Lua 热更）。返回值选择大厅实现，只认布尔：
--   return false  -- 新版自定义大厅（默认）
--   return true   -- 旧版固定大厅（Legacy/ 目录整套，跑在 Host 侧）
-- 开关在大厅 state 创建时读取一次；改后需重进大厅或重启生效，不支持局内实时切换。
-- Host（HostSandbox/main.lua）与 Runtime（LobbyBootstrap.lua）经 LegacyGate 统一读取，语义一致。
return false
