--[[
LobbyProto.lua - Lobby 协议解析模块

负责加载 protobuf 描述文件并解析 Lobby 协议消息。
]]

local M = {}

local pbReady = false
local messageHandlers = {}

-- 协议 ID 到消息类型的映射
local MESSAGE_TYPES = {
    [0x3011] = "CEProto.TSLobbyServer.NotifyTeamCurrentStatus",
    [0x3040] = "CEProto.TSLobbyServer.ResponseUserCurrentStatus",
}

-- 从 VectorBuffer 读取二进制数据
local function ReadBinaryFromBuffer(buffer)
    if not buffer then return nil end
    local size = buffer:GetSize()
    if size == 0 then return nil end

    buffer:Seek(0)
    local bytes = {}
    for i = 1, size do
        bytes[i] = string.char(buffer:ReadUByte())
    end
    return table.concat(bytes)
end

-- 加载 .pb 文件
local function LoadProtoFile()
    if not pb then
        print("[LobbyProto] pb module not available")
        return false
    end

    local cache = GetCache()
    if not cache then
        print("[LobbyProto] Cache not available")
        return false
    end

    local file = cache:GetFile("urhox-libs/Lobby/proto/TSLobbyServer.pb")
    if not file then
        print("[LobbyProto] TSLobbyServer.pb not found")
        return false
    end

    local buffer = file:Read(file:GetSize())
    file:Close()

    local content = ReadBinaryFromBuffer(buffer)
    if not content then
        print("[LobbyProto] Failed to read TSLobbyServer.pb")
        return false
    end

    local ok, err = pb.load(content)
    if not ok then
        print("[LobbyProto] Failed to parse TSLobbyServer.pb: " .. tostring(err))
        return false
    end

    print("[LobbyProto] Loaded TSLobbyServer.pb")
    return true
end

-- 处理协议消息
local function OnProtocolRaw(eventType, eventData)
    local messageId = eventData["MessageId"]:GetInt()
    local buffer = eventData["MessageBody"]:GetBuffer()
    local bodyLen = buffer and buffer:GetSize() or 0

    print(string.format("[LobbyProto] Protocol received: id=0x%04X, body_len=%d", messageId, bodyLen))

    if not pbReady or not buffer or bodyLen == 0 then
        return
    end

    local messageBody = ReadBinaryFromBuffer(buffer)
    if not messageBody then
        return
    end

    -- 先查处理器，没有 handler 就不需要解码
    local handler = messageHandlers[messageId]
    if not handler then
        return
    end

    local msgType = MESSAGE_TYPES[messageId]
    if not msgType then
        return
    end

    local msg, err = pb.decode(msgType, messageBody)
    if msg then
        print(string.format("[LobbyProto] Decoded %s: %s", msgType, cjson.encode(msg)))
        handler(messageId, msg)
    else
        print(string.format("[LobbyProto] Failed to decode: %s", tostring(err)))
    end
end

-- 初始化
function M.Init()
    pbReady = LoadProtoFile()

    if pbReady then
        SubscribeToEvent("LobbyProtocolRaw", OnProtocolRaw)
    end

    return pbReady
end

-- 注册消息处理器
function M.RegisterHandler(messageId, handler)
    messageHandlers[messageId] = handler
end

-- 取消注册消息处理器
function M.UnregisterHandler(messageId)
    messageHandlers[messageId] = nil
end

-- 添加消息类型映射
function M.AddMessageType(messageId, msgType)
    MESSAGE_TYPES[messageId] = msgType
end

-- 是否已初始化
function M.IsReady()
    return pbReady
end

-- 发送编码后的协议到服务器
-- @param messageId 协议 ID
-- @param messageBody 编码后的二进制数据（Lua string）
-- @return requestId 请求 ID（用于匹配响应），失败返回 -1
function M.SendProtocol(messageId, messageBody)
    if not messageBody then
        print(string.format("[LobbyProto] SendProtocol: nil body for messageId=0x%04X", messageId))
        return -1
    end

    -- 创建 VectorBuffer 并写入二进制数据
    local buffer = VectorBuffer()
    for i = 1, #messageBody do
        buffer:WriteUByte(messageBody:byte(i))
    end

    -- 创建事件数据
    local eventData = VariantMap()
    eventData["MessageId"] = messageId
    eventData["MessageBody"] = buffer

    -- 发送事件（C++ 会填充 RequestId）
    SendEvent("LobbySendProtocol", eventData)

    -- 读取 C++ 返回的 requestId
    local requestId = eventData["RequestId"]:GetInt()

    print(string.format("[LobbyProto] SendProtocol: messageId=0x%04X, bodySize=%d, requestId=%d", messageId, #messageBody, requestId))
    return requestId
end

-- 编码并发送协议（便捷方法）
-- @param messageId 协议 ID
-- @param msgType 消息类型名（如 "CEProto.TSLobbyServer.RequestXxx"）
-- @param msgData 消息数据（Lua table）
-- @return requestId 请求 ID（用于匹配响应），失败返回 -1
function M.EncodeAndSend(messageId, msgType, msgData)
    if not pbReady then
        print("[LobbyProto] EncodeAndSend: pb not ready")
        return -1
    end

    local encoded, err = pb.encode(msgType, msgData)
    if not encoded then
        print(string.format("[LobbyProto] EncodeAndSend: failed to encode %s: %s", msgType, tostring(err)))
        return -1
    end

    return M.SendProtocol(messageId, encoded)
end

return M
