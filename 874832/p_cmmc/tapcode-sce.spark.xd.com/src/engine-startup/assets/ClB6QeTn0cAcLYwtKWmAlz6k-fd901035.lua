--- engine-startup/anti_addict.lua
--- 防沉迷与实名认证逻辑（参考老项目 anti/anti_addict.lua）
--- 在 engine-startup Lua VM 中运行，依赖 http (HttpManager) / cjson 全局
--- 隐私：实名生日只在调用栈/闭包内流转，本模块不缓存到内存、不落盘。
local M = {}

------------ 常量 ------------

-- 2026年全部休息日（周五/周六/周日 + 法定节假日延长日，已扣除补班日）
-- 由脚本生成，覆盖164天；2027年起由下方通用周末规则兜底
local HOLIDAYS = {
    -- 2026-01（元旦 Jan 1-3）
    "2026-01-01","2026-01-02","2026-01-03","2026-01-09","2026-01-10","2026-01-11",
    "2026-01-16","2026-01-17","2026-01-18","2026-01-23","2026-01-24","2026-01-25",
    "2026-01-30","2026-01-31",
    -- 2026-02（春节 Feb 17-23，补班日 Feb 14/28 已排除）
    "2026-02-01","2026-02-06","2026-02-07","2026-02-08","2026-02-13","2026-02-15",
    "2026-02-17","2026-02-18","2026-02-19","2026-02-20","2026-02-21","2026-02-22",
    "2026-02-23","2026-02-27",
    -- 2026-03
    "2026-03-01","2026-03-06","2026-03-07","2026-03-08","2026-03-13","2026-03-14",
    "2026-03-15","2026-03-20","2026-03-21","2026-03-22","2026-03-27","2026-03-28",
    "2026-03-29",
    -- 2026-04（清明 Apr 4-6）
    "2026-04-03","2026-04-04","2026-04-05","2026-04-06","2026-04-10","2026-04-11",
    "2026-04-12","2026-04-17","2026-04-18","2026-04-19","2026-04-24","2026-04-25",
    "2026-04-26",
    -- 2026-05（劳动节 May 1-5，补班日 May 9 已排除）
    "2026-05-01","2026-05-02","2026-05-03","2026-05-04","2026-05-05","2026-05-08",
    "2026-05-10","2026-05-15","2026-05-16","2026-05-17","2026-05-22","2026-05-23",
    "2026-05-24","2026-05-29","2026-05-30","2026-05-31",
    -- 2026-06（端午 Jun 19-22）
    "2026-06-05","2026-06-06","2026-06-07","2026-06-12","2026-06-13","2026-06-14",
    "2026-06-19","2026-06-20","2026-06-21","2026-06-22","2026-06-26","2026-06-27",
    "2026-06-28",
    -- 2026-07
    "2026-07-03","2026-07-04","2026-07-05","2026-07-10","2026-07-11","2026-07-12",
    "2026-07-17","2026-07-18","2026-07-19","2026-07-24","2026-07-25","2026-07-26",
    "2026-07-31",
    -- 2026-08
    "2026-08-01","2026-08-02","2026-08-07","2026-08-08","2026-08-09","2026-08-14",
    "2026-08-15","2026-08-16","2026-08-21","2026-08-22","2026-08-23","2026-08-28",
    "2026-08-29","2026-08-30",
    -- 2026-09（中秋 Sep 25-27，补班日 Sep 20 已排除）
    "2026-09-04","2026-09-05","2026-09-06","2026-09-11","2026-09-12","2026-09-13",
    "2026-09-18","2026-09-19","2026-09-25","2026-09-26","2026-09-27",
    -- 2026-10（国庆 Oct 1-8，补班日 Oct 10 已排除）
    "2026-10-01","2026-10-02","2026-10-03","2026-10-04","2026-10-05","2026-10-06",
    "2026-10-07","2026-10-08","2026-10-09","2026-10-11","2026-10-16","2026-10-17",
    "2026-10-18","2026-10-23","2026-10-24","2026-10-25","2026-10-30","2026-10-31",
    -- 2026-11
    "2026-11-01","2026-11-06","2026-11-07","2026-11-08","2026-11-13","2026-11-14",
    "2026-11-15","2026-11-20","2026-11-21","2026-11-22","2026-11-27","2026-11-28",
    "2026-11-29",
    -- 2026-12
    "2026-12-04","2026-12-05","2026-12-06","2026-12-11","2026-12-12","2026-12-13",
    "2026-12-18","2026-12-19","2026-12-20","2026-12-25","2026-12-26","2026-12-27",
}

local HOLIDAY_SET = {}
for _, d in ipairs(HOLIDAYS) do HOLIDAY_SET[d] = true end

-- 2026 补班日（已从 HOLIDAYS 中排除，此表仅供 IsHoliday 二次校验）
local ADJUSTED_WORKDAYS = {
    "2026-01-04",
    "2026-02-14","2026-02-28",
    "2026-05-09",
    "2026-09-20",
    "2026-10-10",
}

local ADJUSTED_WORKDAY_SET = {}
for _, d in ipairs(ADJUSTED_WORKDAYS) do ADJUSTED_WORKDAY_SET[d] = true end

-- 身份证校验通过 app-box-server 代理，APPCODE 保留在服务端，客户端不再持有
local VERIFY_ID_CARD_PATH = "/api/v1/verify_id_card"

local function ResolveIpEnv()
    -- -review 模式固定走 master 环境
    if HasAppArg and HasAppArg("review") then
        return "master"
    end
    local fn = _G and _G.GetIpEnv
    if type(fn) == "function" then
        return fn() or "test"
    end
    return "test"
end

------------ JSON ------------

local function DecodeJson(content)
    if not content or content == "" then return nil end
    local codec = cjson or json
    if not codec or not codec.decode then return nil end
    local ok, data = pcall(codec.decode, content)
    return ok and data or nil
end

local function EncodeJson(data)
    local codec = cjson or json
    if not codec or not codec.encode then return "" end
    local ok, content = pcall(codec.encode, data)
    return ok and content or ""
end

------------ HTTP 工具 ------------

local activeRequests = {}

local function LogWarning(message)
    if log and log.Write then
        log:Write(LOG_WARNING, message)
    else
        print(message)
    end
end

local function LogInfo(message)
    if log and log.Write then
        log:Write(LOG_INFO, message)
    else
        print(message)
    end
end

local function Truncate(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    return s:sub(1, n) .. "...(" .. tostring(#s) .. " bytes)"
end

local function UrlEncode(s)
    s = tostring(s or "")
    s = string.gsub(s, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

local function FormEncode(fields)
    local parts = {}
    for k, v in pairs(fields or {}) do
        parts[#parts + 1] = UrlEncode(k) .. "=" .. UrlEncode(v)
    end
    return table.concat(parts, "&")
end

local function GetHttpManager()
    if GetHttp then return GetHttp() end
    return http
end

--- 发起 POST 请求，回调 onComplete(success, body)
local function HttpPost(url, body, contentType, headers, onComplete)
    local manager = GetHttpManager()
    if not manager then
        LogWarning("[anti_addict] HttpManager unavailable")
        if onComplete then onComplete(false, nil) end
        return
    end

    LogInfo(string.format("[anti_addict] POST %s ct=%s body=%s",
        url, tostring(contentType or ""), Truncate(body, 512)))

    local request = manager:Create()
    activeRequests[request] = true
    request:SetUrl(url):SetMethod(HTTP_POST):SetTimeout(15000)
    if body and body ~= "" then
        request:SetBody(body)
        if contentType and contentType ~= "" then
            request:SetContentType(contentType)
        end
    end
    if headers then
        for k, v in pairs(headers) do
            request:AddHeader(k, v)
        end
    end
    request:OnSuccess(function(client, response)
        activeRequests[client] = nil
        local respBody = response:GetDataAsString()
        local statusCode = response:GetStatusCode()
        if response:IsSuccess() then
            LogInfo(string.format("[anti_addict] <- %d body=%s",
                statusCode, Truncate(respBody, 512)))
            if onComplete then onComplete(true, respBody, statusCode) end
        else
            LogWarning(string.format("[anti_addict] <- %d %s body=%s",
                statusCode, tostring(response:GetStatusText()), Truncate(respBody, 512)))
            if onComplete then onComplete(false, respBody, statusCode) end
        end
    end)
    request:OnError(function(client, statusCode, error)
        activeRequests[client] = nil
        local logFn = (statusCode == 400) and LogInfo or LogWarning
        logFn(string.format("[anti_addict] <- ERR %d: %s", statusCode or 0, tostring(error)))
        if onComplete then onComplete(false, nil, statusCode) end
    end)
    request:Send()
end

--- POST form 请求（application/x-www-form-urlencoded）
local function HttpPostForm(url, fields, headers, onComplete)
    HttpPost(url, FormEncode(fields), "application/x-www-form-urlencoded", headers, onComplete)
end

--- POST JSON 请求
local function HttpPostJson(url, data, headers, onComplete)
    HttpPost(url, EncodeJson(data or {}), "application/json", headers, onComplete)
end

local function NormalizeIdCard(idcard)
    idcard = tostring(idcard or "")
    idcard = string.gsub(idcard, "%s+", "")
    return string.upper(idcard)
end

local function NormalizeName(name)
    name = tostring(name or "")
    return string.gsub(name, "%s+", "")
end

local function IsValidIdCardShape(idcard)
    if #idcard ~= 18 then return false end
    return string.match(idcard, "^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d[%dX]$") ~= nil
end

local function ExtractBirthdayFromIdCard(idcard)
    if not IsValidIdCardShape(idcard) then return nil end
    local y = idcard:sub(7, 10)
    local m = idcard:sub(11, 12)
    local d = idcard:sub(13, 14)
    local birthday = string.format("%s-%s-%s", y, m, d)
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    if not t then return nil end
    if os.date("%Y-%m-%d", t) ~= birthday then return nil end
    return birthday
end


------------ 核心逻辑 ------------
--- 实名生日（"YYYY-MM-DD"）只在调用栈中流转，本模块不缓存、不落盘——属于隐私数据。

local function NormalizeUserId(user_id)
    if type(user_id) ~= "string" then user_id = tostring(user_id) end
    return user_id
end

--- 拉取实名信息，回调 onResult(birthday | nil)。无缓存：每次都向服务器查询。
--- 服务端对"无记录"返回 400（不是错误），birthday=nil 表示用户未实名。
function M.FetchAuthInfo(user_id, onResult)
    user_id = NormalizeUserId(user_id)
    LogInfo(string.format("[anti_addict] FetchAuthInfo user_id=%s", user_id))
    local url = string.format("https://app-box-server-%s.spark.xd.com/api/v1/get_auth_info", ResolveIpEnv())
    HttpPostJson(url, { user_id = user_id }, nil, function(success, content, statusCode)
        local birthday = nil
        if success and content then
            local data = DecodeJson(content)
            if data and data.result == 0 and type(data.data) == "string" and data.data ~= "" then
                birthday = data.data
            end
        elseif statusCode == 400 then
            -- 400 = 数据库无记录（未实名），属于正常情况
            LogInfo("[anti_addict] FetchAuthInfo: user not registered (400)")
        end
        LogInfo(string.format("[anti_addict] FetchAuthInfo result: birthday=%s", tostring(birthday)))
        if onResult then onResult(birthday) end
    end)
end

local function CalculateAge(birthday)
    if not birthday or #birthday ~= 10 then return nil end
    local year = tonumber(birthday:sub(1, 4))
    local month = tonumber(birthday:sub(6, 7))
    local day = tonumber(birthday:sub(9, 10))
    if not (year and month and day) then return nil end

    local cy = tonumber(os.date("%Y"))
    local cm = tonumber(os.date("%m"))
    local cd = tonumber(os.date("%d"))
    local age = cy - year
    if (cm < month) or (cm == month and cd < day) then
        age = age - 1
    end
    return age
end

function M.IsUnderage(birthday)
    if not birthday then return false end
    local age = CalculateAge(birthday)
    return age ~= nil and age < 18
end

--- 上报实名信息到服务器，回调 onDone()。本地不存。
function M.UploadAuthInfo(user_id, birthday, onDone)
    user_id = NormalizeUserId(user_id)
    LogInfo(string.format("[anti_addict] UploadAuthInfo user_id=%s birthday=%s", user_id, tostring(birthday)))
    local url = string.format("https://app-box-server-%s.spark.xd.com/api/v1/save_auth_info", ResolveIpEnv())
    HttpPostJson(url, { user_id = user_id, info = birthday }, nil, function(success, content)
        local ok = false
        if success and content then
            local data = DecodeJson(content)
            if data and data.result == 0 then
                ok = true
            end
        end
        if ok then
            LogInfo("[anti_addict] UploadAuthInfo result: ok")
        else
            -- 上传失败不阻断流程（服务端临时不可用），但下次启动会再次要求实名认证
            LogWarning("[anti_addict] UploadAuthInfo failed: server not reachable, user will need to re-verify next session")
        end
        if onDone then onDone() end
    end)
end

-- 注意：os.date 取设备本地时间，玩家可改系统时钟绕过。本函数仅作客户端
-- 提示性检查（决定要不要弹"游戏中"窗口）；合规硬拦截由服务端在登录/心跳里
-- 校验后端时间完成，不依赖此处的判断。
function M.IsTimeBetween20_21()
    return tonumber(os.date("%H")) == 20
end

function M.AllowGameMin()
    local cur = tonumber(os.date("%M"))
    return 60 - cur
end

function M.IsHoliday()
    local today = os.date("%Y-%m-%d")
    if ADJUSTED_WORKDAY_SET[today] then
        return false
    end
    if HOLIDAY_SET[today] then
        return true
    end

    -- 2027 起用通用规则兜底（2026已有完整枚举），调休工作日由上面的表排除。
    -- 注意：国家防沉迷规定允许未成年人在「周五、周六、周日和法定节假日」20-21 时游玩，
    -- 此处返回 true 表示「该日期允许游玩」而非「法定休息日」。
    local year = tonumber(os.date("%Y"))
    if year and year >= 2027 then
        local weekday = tonumber(os.date("%w")) -- 0=Sunday, 5=Friday, 6=Saturday
        return weekday == 0 or weekday == 5 or weekday == 6
    end

    return false
end

--- 是否允许开始游戏（基于已知 birthday；nil 表示未实名）
--- @return boolean canPlay 是否可玩
--- @return string|nil reason 不可玩原因 ("not_authed"|"out_of_window"|nil)
function M.CanStartGame(birthday)
    if not birthday then
        return false, "not_authed"
    end
    if M.IsUnderage(birthday) then
        if M.IsTimeBetween20_21() and M.IsHoliday() then
            return true, nil
        end
        return false, "out_of_window"
    end
    return true, nil
end

--- 通过阿里云校验身份证 + 姓名，回调 onResult(success, birthday "YYYY-MM-DD" | err)
function M.VerifyIdCard(name, idcard, onResult)
    name = NormalizeName(name)
    idcard = NormalizeIdCard(idcard)
    -- 日志：name 长度，idcard 仅前6后4（脱敏）
    local idMasked = (#idcard >= 10) and (idcard:sub(1,6) .. "********" .. idcard:sub(-4)) or idcard
    LogInfo(string.format("[anti_addict] VerifyIdCard name_len=%d idcard=%s", #name, idMasked))
    if not name or name == "" or not idcard or idcard == "" then
        LogWarning("[anti_addict] VerifyIdCard: input_empty")
        onResult(false, "input_empty")
        return
    end

    -- 通过 app-box-server 代理校验，APPCODE 在服务端持有
    local url = string.format("https://app-box-server-%s.spark.xd.com%s", ResolveIpEnv(), VERIFY_ID_CARD_PATH)
    HttpPostJson(url, { name = name, cardNo = idcard }, nil, function(success, content)
        if not success or not content then
            LogWarning("[anti_addict] VerifyIdCard: network_error")
            onResult(false, "network_error")
            return
        end
        local data = DecodeJson(content)
        if type(data) ~= "table" then
            LogWarning("[anti_addict] VerifyIdCard: parse_error")
            onResult(false, "parse_error")
            return
        end
        -- 服务端响应：result==0 表示匹配，birthday 已由服务端补零为 YYYY-MM-DD
        if data.result == 0 then
            local birthday = type(data.birthday) == "string" and data.birthday ~= "" and data.birthday
                             or ExtractBirthdayFromIdCard(idcard)
            if not birthday then
                LogWarning("[anti_addict] VerifyIdCard: bad_birthday")
                onResult(false, "bad_birthday")
                return
            end
            LogInfo(string.format("[anti_addict] VerifyIdCard: ok birthday=%s", birthday))
            onResult(true, birthday)
        else
            LogWarning(string.format("[anti_addict] VerifyIdCard: verify_failed msg=%s",
                tostring(data.msg)))
            onResult(false, "verify_failed")
        end
    end)
end

------------ 时间监听 ------------

local rejectTimer = nil
local rejectCallback = nil
local rejectUpdateHandler = nil

--- 启动时间监听：超过 21 点强制退出
function M.WaitRejectTime(onReject)
    M.StopRejectTimer()
    rejectCallback = onReject

    local accumulated = 0
    rejectTimer = true
    rejectUpdateHandler = function(eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()
        accumulated = accumulated + dt
        if accumulated < 1.0 then return end
        accumulated = 0

        if not M.IsTimeBetween20_21() then
            M.StopRejectTimer()
            if rejectCallback then
                local cb = rejectCallback
                rejectCallback = nil
                cb()
            end
        end
    end
    SubscribeToEvent("Update", rejectUpdateHandler)
end

function M.StopRejectTimer()
    if rejectUpdateHandler then
        UnsubscribeFromEvent("Update", rejectUpdateHandler)
        rejectUpdateHandler = nil
    end
    rejectTimer = nil
    rejectCallback = nil
end

--- 取消所有 pending 请求，在过渡到下一阶段前调用。
--- 注意：不停止 RejectTimer——未成年用户的 21:00 踢出定时器需要在整个会话内存活，
--- 直到 Lua VM 销毁时自动清理。
function M.Destroy()
    for request in pairs(activeRequests) do
        if request.Cancel then request:Cancel() end
    end
    activeRequests = {}
end

------------ 启动流程编排 ------------

--- 实名与防沉迷流程：登录后调用，根据用户状态弹窗，完成后调用 onComplete()。
--- 退出场景（未实名关闭、未成年时段限制）由 onExit() 处理。
--- 实名生日仅在闭包内流转，本模块不缓存、不落盘。
--- @param StartupUI table 已显示的 startup_ui 模块（dialog 渲染依赖）
--- @param userId number|string 当前登录用户 ID
--- @param onComplete fun() 流程完成（已实名 + 可游玩）
--- @param onExit fun() 用户拒绝实名 / 未成年时段不可玩
function M.RunCheckFlow(StartupUI, userId, onComplete, onExit)
    if not StartupUI or not userId or userId == 0 then
        if onComplete then onComplete() end
        return
    end

    local function ProceedAfterAuthed(birthday)
        if not M.CanStartGame(birthday) then
            StartupUI.ShowAntiAddictTips({ mode = "exit", onExit = onExit })
            return
        end
        if M.IsUnderage(birthday) then
            StartupUI.ShowAntiAddictTips({
                mode = "enter",
                remainMin = M.AllowGameMin(),
                onEnter = function()
                    M.WaitRejectTime(onExit)
                    onComplete()
                end,
            })
        else
            onComplete()
        end
    end

    local function ShowAuthDialog()
        StartupUI.ShowRealNameDialog(function(name, idcard)
            if not name or name == "" or not idcard or idcard == "" then
                StartupUI.SetRealNameError("请输入真实姓名和身份证号")
                return
            end
            StartupUI.SetRealNameSubmitting(true)
            StartupUI.SetRealNameError("")
            M.VerifyIdCard(name, idcard, function(ok, birthdayOrErr)
                if ok then
                    local birthday = birthdayOrErr
                    M.UploadAuthInfo(userId, birthday, function()
                        StartupUI.CloseRealNameDialog()
                        ProceedAfterAuthed(birthday)
                    end)
                else
                    -- 显式重置 submitting，不依赖 SetRealNameError 非空时的副作用，
                    -- 避免未来调用方传空错误消息时把表单卡死
                    StartupUI.SetRealNameSubmitting(false)
                    StartupUI.SetRealNameError("认证未通过，请提交真实信息")
                end
            end)
        end, onExit)
    end

    M.FetchAuthInfo(userId, function(birthday)
        if birthday then
            ProceedAfterAuthed(birthday)
        else
            ShowAuthDialog()
        end
    end)
end

return M
