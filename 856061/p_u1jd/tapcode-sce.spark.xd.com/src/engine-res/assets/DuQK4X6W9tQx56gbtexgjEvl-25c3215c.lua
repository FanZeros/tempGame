--[[
Example_Proto.lua - LobbyProto 使用示例

本文件展示如何使用 LobbyProto 模块在 Lua 中收发 protobuf 协议。

依赖:
- lua-protobuf (pb 模块)
- LobbyProto.lua
- TSLobbyServer.pb (编译后的 protobuf 描述文件)
]]

local LobbyProto = require("urhox-libs.Lobby.LobbyProto")

--------------------------------------------------------------------------------
-- 1. 初始化
--------------------------------------------------------------------------------

-- 初始化 LobbyProto 模块（加载 .pb 文件并订阅 LobbyProtocolRaw 事件）
local function InitProto()
    local success = LobbyProto.Init()
    if success then
        print("[Example] LobbyProto initialized successfully")
    else
        print("[Example] LobbyProto initialization failed")
    end
    return success
end

--------------------------------------------------------------------------------
-- 2. 注册消息类型映射
--------------------------------------------------------------------------------

-- 添加协议 ID 到消息类型的映射
-- 这样 LobbyProto 收到协议后才知道用哪个类型来解码
local function RegisterMessageTypes()
    -- 格式: LobbyProto.AddMessageType(协议ID, 消息类型全名)
    LobbyProto.AddMessageType(0x3011, "CEProto.TSLobbyServer.NotifyTeamCurrentStatus")
    LobbyProto.AddMessageType(0x3040, "CEProto.TSLobbyServer.ResponseUserCurrentStatus")
    LobbyProto.AddMessageType(0x3001, "CEProto.TSLobbyServer.ResponseTeamCreate")
    -- ... 添加更多映射
end

--------------------------------------------------------------------------------
-- 3. 注册消息处理器（接收协议）
--------------------------------------------------------------------------------

-- 注册特定协议的处理函数
-- 当收到对应协议时，LobbyProto 会自动解码并调用处理函数
local function RegisterHandlers()
    -- 处理队伍状态通知
    LobbyProto.RegisterHandler(0x3011, function(messageId, msg)
        print("[Example] Received NotifyTeamCurrentStatus:")
        print("  team_id: " .. tostring(msg.team_id))
        print("  member_count: " .. tostring(msg.member_count))
        -- 处理业务逻辑...
    end)

    -- 处理用户状态响应
    LobbyProto.RegisterHandler(0x3040, function(messageId, msg)
        print("[Example] Received ResponseUserCurrentStatus:")
        print("  user_id: " .. tostring(msg.user_id))
        print("  status: " .. tostring(msg.status))
        -- 处理业务逻辑...
    end)
end

-- 取消注册处理器
local function UnregisterHandlers()
    LobbyProto.UnregisterHandler(0x3011)
    LobbyProto.UnregisterHandler(0x3040)
end

--------------------------------------------------------------------------------
-- 4. 发送协议
--------------------------------------------------------------------------------

-- 方式一：手动编码后发送
local function SendProtocolManual()
    if not pb then
        print("[Example] pb module not available")
        return -1
    end

    -- 构造消息数据
    local requestData = {
        map_name = "test_map",
        max_count = 4,
        is_private = false,
    }

    -- 手动编码
    local encoded, err = pb.encode("CEProto.TSLobbyServer.RequestTeamCreate", requestData)
    if not encoded then
        print("[Example] Encode failed: " .. tostring(err))
        return -1
    end

    -- 发送编码后的数据，返回 requestId
    local requestId = LobbyProto.SendProtocol(0x3000, encoded)
    if requestId > 0 then
        print("[Example] Protocol sent successfully (manual), requestId=" .. requestId)
    end
    return requestId
end

-- 方式二：使用便捷方法自动编码并发送
local function SendProtocolAuto()
    -- 构造消息数据
    local requestData = {
        map_name = "test_map",
        max_count = 4,
        is_private = false,
    }

    -- 自动编码并发送，返回 requestId
    local requestId = LobbyProto.EncodeAndSend(
        0x3000,  -- 协议 ID
        "CEProto.TSLobbyServer.RequestTeamCreate",  -- 消息类型
        requestData  -- 消息数据
    )

    if requestId > 0 then
        print("[Example] Protocol sent successfully (auto), requestId=" .. requestId)
    end
    return requestId
end

--------------------------------------------------------------------------------
-- 5. 直接使用 pb 模块（不通过 LobbyProto）
--------------------------------------------------------------------------------

-- 如果需要更底层的控制，可以直接使用 pb 模块
local function DirectPbUsage()
    if not pb then
        print("[Example] pb module not available")
        return
    end

    -- 检查消息类型是否存在
    local msgType = "CEProto.TSLobbyServer.RequestTeamCreate"
    if not pb.type(msgType) then
        print("[Example] Message type not found: " .. msgType)
        return
    end

    -- 编码
    local data = { map_name = "test", max_count = 2 }
    local encoded = pb.encode(msgType, data)
    print("[Example] Encoded size: " .. #encoded)

    -- 解码
    local decoded = pb.decode(msgType, encoded)
    print("[Example] Decoded map_name: " .. tostring(decoded.map_name))

    -- 遍历消息字段定义
    print("[Example] Fields of " .. msgType .. ":")
    for name, number, type in pb.fields(msgType) do
        print(string.format("  %s (#%d) : %s", name, number, type))
    end
end

--------------------------------------------------------------------------------
-- 6. 完整使用流程示例
--------------------------------------------------------------------------------

local function FullExample()
    print("==================== LobbyProto Example ====================")

    -- Step 1: 初始化
    if not InitProto() then
        print("[Example] Init failed, abort")
        return
    end

    -- Step 2: 注册消息类型
    RegisterMessageTypes()

    -- Step 3: 注册处理器
    RegisterHandlers()

    -- Step 4: 发送协议
    -- SendProtocolManual()
    -- 或
    -- SendProtocolAuto()

    print("[Example] Setup complete. Ready to send/receive protocols.")
    print("============================================================")
end

--------------------------------------------------------------------------------
-- 导出
--------------------------------------------------------------------------------

return {
    -- 初始化相关
    InitProto = InitProto,
    RegisterMessageTypes = RegisterMessageTypes,
    RegisterHandlers = RegisterHandlers,
    UnregisterHandlers = UnregisterHandlers,

    -- 发送相关
    SendProtocolManual = SendProtocolManual,
    SendProtocolAuto = SendProtocolAuto,

    -- 其他
    DirectPbUsage = DirectPbUsage,
    FullExample = FullExample,
}
