-- ============================================================================
-- Shop Module - Client-side IAP API
-- ============================================================================
--
-- Drives the client side of the IAP create-order flow:
--   client Shop.purchase(productId, cb)
--      -> ShopCreateOrder remote event (server)
--         -> server queries maker_iap_shop.json + NodeServer
--            -> ShopCreateOrderResult remote event (client)
--               -> sdk:Pay() 自动拉起支付弹窗
--               -> cb({ ok=true }) 或 cb({ ok=false, error, message })
--
-- sdk:Pay 由 Shop.purchase 内部自动调用，游戏侧无需手动调用。
-- 发货由服务端 Shop.onDeliver 异步处理，客户端通过 Shop.onDelivered 接收通知（待实现）。
--
-- Usage:
--   local Shop = require("urhox-libs/Shop")
--
--   Shop.purchase("gem_pack_60", function(result)
--       if not result.ok then
--           -- 建单失败（平台不支持、网络错误等）
--           print("purchase failed:", result.error, result.message)
--       end
--       -- result.ok == true 表示支付弹窗已拉起，发货由服务端异步完成
--   end)
--
-- miniappId (TapTap mini-game offerId) is read automatically from the client
-- startup arg `miniapp_id` (via GetAppArgv) and forwarded to the server in
-- ShopCreateOrder.
--
--   local products = Shop.getProducts()
--   -- [{sku_id, name, price(元), delivery=[{key,amount}]}]，nil 表示 IAP 未开通
--
-- ============================================================================

-- 服务端不加载此模块：Shop 全局对象由 C++ SetupLuaShopGlobals 注册，
-- 客户端模块在服务端无意义且会使用客户端专属 API。
if network and network.serverRunning then
    return {}
end

local Shop = {}

local DEFAULT_TIMEOUT_SEC = 30
local SHOP_PATH     = "maker_iap_shop.json"
local DELIVERY_PATH = "maker_iap_delivery.json"
local MINIAPP_ID_KEY = "miniapp_id"
local EMBED_KEY = "embed"

-- ============================================================================
-- Module state
-- ============================================================================

local initialized_ = false
local eventNode_ = nil          -- standalone Node for independent event subscription
local eventSO_ = nil            -- ScriptObject on eventNode_
local pending_ = {}             -- requestId -> { cb, deadline }
local deliveredHandlers_ = {}   -- list of user-registered ShopDelivered handlers
local seq_ = 0
local productsCache_ = nil      -- cached normalized product list (from shop + delivery)
local productsLoadFailed_ = false
local miniappIdCache_ = nil     -- cached -miniapp_id startup arg ("" if missing)
local purchaseSupportedCache_ = nil  -- cached platform+embed check result

-- ============================================================================
-- Helpers
-- ============================================================================

local function nextRequestId()
    seq_ = seq_ + 1
    return string.format("c_%d_%d", math.floor(time.elapsedTime * 1000), seq_)
end

local function getMiniappId()
    if miniappIdCache_ ~= nil then return miniappIdCache_ end
    if type(GetAppArgv) == "function" then
        miniappIdCache_ = GetAppArgv(MINIAPP_ID_KEY) or ""
    else
        miniappIdCache_ = ""
    end
    return miniappIdCache_
end

-- IAP 仅在安卓/iOS 内嵌模式（-embed 启动参数）下支持
local function isPurchaseSupported()
    if purchaseSupportedCache_ ~= nil then return purchaseSupportedCache_ end
    local platform = type(GetPlatform) == "function" and GetPlatform() or ""
    local isNativeMobile = (platform == "Android" or platform == "iOS")
    local hasEmbed = HasAppArg and HasAppArg(EMBED_KEY) or false
    purchaseSupportedCache_ = isNativeMobile and hasEmbed
    if not purchaseSupportedCache_ then
        print(string.format("[Shop] IAP not supported: platform=%q embed=%s", platform, tostring(hasEmbed)))
    end
    return purchaseSupportedCache_
end

local function failPending(requestId, err, msg)
    local entry = pending_[requestId]
    if not entry then return end
    pending_[requestId] = nil
    if entry.cb then
        local ok, e = pcall(entry.cb, {
            ok = false,
            error = err,
            message = msg,
        })
        if not ok then
            print("[Shop] purchase callback error: " .. tostring(e))
        end
    end
end

local function failAll(err, msg)
    local ids = {}
    for id, _ in pairs(pending_) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do failPending(id, err, msg) end
end

-- ============================================================================
-- Remote event handlers
-- ============================================================================

local function onShopCreateOrderResult(self, eventType, eventData)
    local requestId = eventData["RequestId"]:GetString()
    local entry = pending_[requestId]
    if not entry then
        -- Late or duplicate result; ignore.
        return
    end
    pending_[requestId] = nil

    local ok = eventData["Ok"]:GetBool()
    local result
    if ok then
        result = {
            ok = true,
            orderId   = eventData["OrderId"]:GetString(),
            signData  = eventData["SignData"]:GetString(),
            paySig    = eventData["PaySig"]:GetString(),
            signature = eventData["Signature"]:GetString(),
        }
    else
        result = {
            ok = false,
            error   = eventData["Error"]:GetString(),
            message = eventData["Message"]:GetString(),
        }
    end

    if entry.cb then
        local cbOk, e = pcall(entry.cb, result)
        if not cbOk then
            print("[Shop] purchase callback error: " .. tostring(e))
        end
    end
end

local function onShopDelivered(self, eventType, eventData)
    local payload = {
        orderId   = eventData["OrderId"]:GetString(),
        productId = eventData["ProductId"]:GetString(),
    }
    for _, h in ipairs(deliveredHandlers_) do
        local ok, e = pcall(h, payload)
        if not ok then
            print("[Shop] onDelivered handler error: " .. tostring(e))
        end
    end
end

local function onServerDisconnected()
    failAll("network_error", "disconnected from server")
end

local function sweepTimeouts()
    local now = time.elapsedTime
    local expired = {}
    for id, entry in pairs(pending_) do
        if entry.deadline and now >= entry.deadline then
            expired[#expired + 1] = id
        end
    end
    for _, id in ipairs(expired) do
        failPending(id, "timeout", "create order timeout")
    end
end

-- ============================================================================
-- Lazy init: register remote events + subscribe (once)
-- ============================================================================

local function ensureInit()
    if initialized_ then return end
    if not network then
        print("[Shop] network subsystem not available")
        return
    end

    network:RegisterRemoteEvent("ShopCreateOrder")
    network:RegisterRemoteEvent("ShopCreateOrderResult")
    network:RegisterRemoteEvent("ShopDelivered")

    -- Use a standalone Node + LuaScriptObject for our own subscriptions so we
    -- never overwrite the game's global "Update" / event handlers.
    eventNode_ = Node()
    eventSO_ = eventNode_:CreateScriptObject("LuaScriptObject")
    eventSO_:SubscribeToEvent("ShopCreateOrderResult", onShopCreateOrderResult)
    eventSO_:SubscribeToEvent("ShopDelivered", onShopDelivered)
    eventSO_:SubscribeToEvent("ServerDisconnected", onServerDisconnected)
    eventSO_:SubscribeToEvent("Update", function(self, eventType, eventData)
        if next(pending_) ~= nil then
            sweepTimeouts()
        end
    end)

    initialized_ = true
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Internal: create an order via NodeServer and return raw sign data to callback.
--- The callback receives { ok=true, orderId, signData, paySig, signature }
--- or { ok=false, error, message }.
---@param productId string
---@param callback function(result table)
---@return string|nil requestId
local function createOrder(productId, callback)
    ensureInit()

    local miniappId = getMiniappId()
    if miniappId == "" then
        callback({ ok = false, error = "bad_request",
                   message = "missing -miniapp_id startup argument" })
        return nil
    end

    local connection = network and network:GetServerConnection() or nil
    if not connection then
        callback({ ok = false, error = "network_error", message = "not connected to server" })
        return nil
    end

    local requestId = nextRequestId()

    pending_[requestId] = {
        cb = callback,
        deadline = time.elapsedTime + DEFAULT_TIMEOUT_SEC,
    }

    -- platform：仅 android/ios 内嵌场景有效，其他平台不传（服务端用于建单区分渠道）
    local platform = ""
    if type(GetPlatform) == "function" then
        local p = GetPlatform()
        if p == "Android" or p == "iOS" then
            platform = p:lower()  -- "android" / "ios"
        end
    end

    local vm = VariantMap()
    vm["RequestId"] = Variant(requestId)
    vm["ProductId"] = Variant(productId)
    vm["MiniappId"] = Variant(miniappId)
    if platform ~= "" then
        vm["Platform"] = Variant(platform)
    end
    connection:SendRemoteEvent("ShopCreateOrder", true, vm)

    return requestId
end

--- Initiate a purchase: create an order and immediately launch the platform
--- payment dialog. The callback (optional) fires once the dialog has been
--- triggered — not when payment completes (delivery is handled server-side).
---
---   { ok=true }                     -- dialog launched successfully
---   { ok=false, error, message }    -- order creation failed
---
--- Common error codes: platform_not_supported, bad_request, unknown_product,
--- shop_not_configured, internal_error, network_error, timeout.
---@param productId string Product id matching one entry in maker_iap_shop.json
---@param callback function|nil  function(result table)
function Shop.purchase(productId, callback)
    if type(productId) ~= "string" or productId == "" then
        error("Shop.purchase: productId must be a non-empty string", 2)
    end

    if not isPurchaseSupported() then
        if callback then
            local ok, e = pcall(callback, {
                ok = false,
                error = "platform_not_supported",
                message = _tr("t_1DUhjSl6b1D43Agaj5"),
            })
            if not ok then print("[Shop] purchase callback error: " .. tostring(e)) end
        end
        return
    end

    createOrder(productId, function(result)
        if result.ok then
            if sdk and sdk.Pay then
                sdk:Pay(result.signData, result.paySig, result.signature)
            else
                if callback then
                    local ok, e = pcall(callback, { ok = false, error = "platform_not_supported",
                                                    message = "sdk:Pay not available on this platform" })
                    if not ok then print("[Shop] purchase callback error: " .. tostring(e)) end
                end
                return
            end
            if callback then
                local ok, e = pcall(callback, { ok = true })
                if not ok then print("[Shop] purchase callback error: " .. tostring(e)) end
            end
        else
            if callback then
                local ok, e = pcall(callback, result)
                if not ok then print("[Shop] purchase callback error: " .. tostring(e)) end
            end
        end
    end)
end

--- Register a handler for server-pushed delivery notifications.
--- Multiple handlers may be registered; each receives { orderId, productId }.
--- Note: server-side push of ShopDelivered is a follow-up; until then this
--- registers the handler and remains dormant.
---@param handler function(payload table)
function Shop.onDelivered(handler)
    if type(handler) ~= "function" then
        error("Shop.onDelivered: handler must be a function", 2)
    end
    ensureInit()
    deliveredHandlers_[#deliveredHandlers_ + 1] = handler
end

--- 读取文件并 JSON 解析，返回 table 或 nil
local function readJsonFile(filePath)
    local c = GetCache and GetCache() or cache
    if not c then return nil end
    if not c:Exists(filePath) then return nil end
    local file = c:GetFile(filePath)
    if not file then return nil end
    local lines = {}
    while not file:IsEof() do
        lines[#lines + 1] = file:ReadLine()
    end
    local ok, decoded = pcall(cjson.decode, table.concat(lines, "\n"))
    if not ok or type(decoded) ~= "table" then
        print("[Shop] failed to parse " .. filePath .. ": " .. tostring(decoded))
        return nil
    end
    return decoded
end

--- 返回商品列表（cached）。每项格式：
---   { sku_id, name, price（元）, delivery（[{key,amount}]） }
--- 返回 nil 表示配置文件不存在（IAP 未开通）。
---@return table|nil
function Shop.getProducts()
    if productsCache_ ~= nil then return productsCache_ end
    if productsLoadFailed_ then return nil end

    local shopData = readJsonFile(SHOP_PATH)
    if not shopData then
        productsLoadFailed_ = true
        return nil
    end

    -- delivery map: merchant_sku_id -> [{key, amount}]，文件缺失时用空表
    local deliveryData = readJsonFile(DELIVERY_PATH)
    local deliveryMap = (deliveryData and deliveryData.delivery) or {}

    local result = {}
    local platformStr = type(GetPlatform) == "function" and GetPlatform() or ""
    local platformId = ({ Android = 1, iOS = 2 })[platformStr] or 3  -- 1=Android 2=iOS 3=PC

    local products = shopData.products or {}
    for _, product in ipairs(products) do
        local title = product.title or ""
        for _, sku in ipairs(product.sku_list or {}) do
            -- 过滤未上架（published=false）、已删除（deleted=true）的 SKU，
            -- 以及商品整体已下架（status=2 强制下架 / status=3 主动下架）的情况
            if not sku.published or sku.deleted or product.status == 2 or product.status == 3 then goto continue end
            -- 过滤不支持当前平台的 SKU（platform 字段缺失时视为全平台支持；Web 环境仅展示，不过滤）
            if type(sku.platform) == "table" and platformStr ~= "Web" then
                local supported = false
                for _, pid in ipairs(sku.platform) do if pid == platformId then supported = true; break end end
                if not supported then goto continue end
            end

            local skuCode = sku.merchant_sku_id or ""
            -- 价格：price.price 单位是元（DC 接口直接返回元，无需换算）
            local priceYuan = 0
            if sku.price and sku.price.price then
                priceYuan = tonumber(sku.price.price)
            end
            result[#result + 1] = {
                sku_id   = skuCode,
                name     = title,
                price    = priceYuan,
                delivery = deliveryMap[skuCode] or {},
            }
            ::continue::
        end
    end

    productsCache_ = result
    return productsCache_
end


return Shop
