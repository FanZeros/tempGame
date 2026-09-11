-- LuaScripts/Utilities/Previews/UrlWhitelist.lua
-- URL whitelist loader for preview-mode HTTP isolation.
--
-- Two matching modes are supported, in order of priority:
--   1. exact   - full URL after normalization (config field "urls")
--   2. domain  - host-only after normalization (config field "domains");
--                applied as a fallback when the exact lookup misses
--
-- Normalization is intentionally narrow:
--   - scheme is lowercased
--   - host is lowercased
--   - root path is normalized to "/"
--   - non-root paths strip trailing slashes
-- Query/fragment remain exact-match to preserve whitelist precision.
--
-- Domain mode is deliberately strict: a request URL must be http/https,
-- carry no userinfo, and use the default port (80/443). Anything else falls
-- through to deny. Use an exact entry if a non-default port or scheme is
-- genuinely required.

local M = {}

M.DEFAULT_RESOURCE = "LuaScripts/Utilities/Previews/ServiceUrlWhitelist.json"

local function Warn(msg)
    if log then
        log:Write(LOG_WARNING, msg)
    end
end

local function NormalizeAuthority(authority)
    local userinfo = ""
    local hostPort = authority

    local userinfoPrefix, rest = authority:match("^(.*@)(.+)$")
    if userinfoPrefix then
        userinfo = userinfoPrefix
        hostPort = rest
    end

    if hostPort:sub(1, 1) == "[" then
        local ipv6Host, port = hostPort:match("^(%b[])(:.*)$")
        if not ipv6Host then
            ipv6Host = hostPort:match("^(%b[])$")
        end
        if ipv6Host then
            return userinfo .. string.lower(ipv6Host) .. (port or "")
        end
    end

    local host, port = hostPort:match("^(.-)(:%d+)$")
    if not host then
        host = hostPort
        port = ""
    end

    return userinfo .. string.lower(host) .. port
end

local function NormalizePath(path)
    if not path or path == "" or path == "/" then
        return "/"
    end

    local trimmed = path:gsub("/+$", "")
    if trimmed == "" then
        return "/"
    end

    return trimmed
end

local function NormalizeUrl(url)
    if url == nil then
        return nil
    end
    url = tostring(url)
    if url == "" then
        return nil
    end

    -- The scheme/authority pattern below is duplicated in
    -- ExtractHostForDomainMatch (deliberately, to keep the security-critical
    -- domain path independent). See the SECURITY INVARIANT note there before
    -- touching this regex.
    local scheme, authority, suffix = url:match("^([%a][%w+.-]*)://([^/?#]*)(.*)$")
    if scheme then
        local path, rest = suffix:match("^([^?#]*)(.*)$")
        return string.lower(scheme) .. "://" .. NormalizeAuthority(authority) .. NormalizePath(path) .. rest
    end

    local otherScheme, remainder = url:match("^([%a][%w+.-]*):(.*)$")
    if otherScheme then
        return string.lower(otherScheme) .. ":" .. remainder
    end

    return url
end

-- Extract a bare host from a request URL for domain-set lookup. Returns the
-- lowercased host string on success, or nil if the URL is ineligible for
-- domain matching for any of these reasons:
--   - unparseable / no "<scheme>://<authority>" form
--   - scheme is not http or https
--   - authority carries userinfo (rejects phishing-style URLs like
--     https://evil.com@trusted.com/)
--   - authority carries an explicit :port (domain entries are restricted to
--     default ports; use an exact URL entry for non-default ports)
--
-- SECURITY INVARIANT — parser-differential prevention:
-- The "^([%a][%w+.-]*)://([^/?#]*)" regex below MUST stay byte-for-byte
-- identical to the one in NormalizeUrl above. The two functions are the
-- two halves of the whitelist parser (exact-URL path vs. domain path);
-- any divergence in how they parse scheme/authority creates a classic
-- parser-differential SSRF — one half allows a request the other half
-- thinks targets a different host. If you change one, you MUST change the
-- other and re-run test_url_whitelist (subdomain / userinfo / :port /
-- non-http(s) cases all need to remain denied).
local function ExtractHostForDomainMatch(url)
    if url == nil then
        return nil
    end
    url = tostring(url)
    if url == "" then
        return nil
    end

    local scheme, authority = url:match("^([%a][%w+.-]*)://([^/?#]*)")
    if not scheme then
        return nil
    end
    scheme = string.lower(scheme)
    if scheme ~= "http" and scheme ~= "https" then
        return nil
    end

    if authority == "" or authority:find("@", 1, true) then
        return nil
    end

    if authority:sub(1, 1) == "[" then
        -- IPv6 literal: brackets must wrap the entire authority. Anything after
        -- the closing bracket would be ":port" (or junk) and is not allowed.
        local ipv6Host = authority:match("^(%b[])$")
        if not ipv6Host then
            return nil
        end
        return string.lower(ipv6Host)
    end

    if authority:find(":", 1, true) then
        return nil
    end

    return string.lower(authority)
end

-- Validate a host string written in the "domains" config field. Returns the
-- canonical (lowercased) host on success, or nil + reason on rejection.
-- The config value is required to be a bare host: no scheme, no path, no
-- port, no userinfo. This catches the common mistake of pasting a full URL.
local function NormalizeConfigDomain(domain)
    if type(domain) ~= "string" or domain == "" then
        return nil, "must be a non-empty string"
    end

    if domain:find("://", 1, true) then
        return nil, "must not contain a scheme"
    end
    if domain:find("/", 1, true) then
        return nil, "must not contain a path"
    end
    if domain:find("?", 1, true) or domain:find("#", 1, true) then
        return nil, "must not contain query or fragment"
    end
    if domain:find("@", 1, true) then
        return nil, "must not contain userinfo"
    end

    if domain:sub(1, 1) == "[" then
        if not domain:match("^%b[]$") then
            return nil, "malformed IPv6 literal"
        end
        return string.lower(domain)
    end

    if domain:find(":", 1, true) then
        return nil, "must not contain a port (default ports only)"
    end

    return string.lower(domain)
end

local function BuildPolicy(urls, domains)
    local policy = {
        urls = {},
        urlCount = 0,
        domains = {},
        domainCount = 0,
    }

    if type(urls) == "table" then
        for _, url in ipairs(urls) do
            url = NormalizeUrl(url)
            if url and not policy.urls[url] then
                policy.urls[url] = true
                policy.urlCount = policy.urlCount + 1
            end
        end
    end

    if type(domains) == "table" then
        for _, domain in ipairs(domains) do
            local host, reason = NormalizeConfigDomain(domain)
            if host then
                if not policy.domains[host] then
                    policy.domains[host] = true
                    policy.domainCount = policy.domainCount + 1
                end
            else
                Warn(string.format(
                    "[Preview/UrlWhitelist] Ignoring invalid domain entry %q: %s",
                    tostring(domain),
                    reason
                ))
            end
        end
    end

    return policy
end

local function ReadStringArray(root, key)
    local value = root:Get(key)
    if not value or value:IsNull() then
        return {}
    end

    if value:IsString() then
        return { value:GetString() }
    end

    if not value:IsArray() then
        return {}
    end

    local items = {}
    for index = 0, value:Size() - 1 do
        local item = value[index]
        if item and item:IsString() then
            items[#items + 1] = item:GetString()
        end
    end
    return items
end

local function LoadPolicyFromString(jsonString)
    local jsonFile = JSONFile:new()
    if not jsonFile:FromString(jsonString) then
        Warn("[Preview/UrlWhitelist] Failed to parse whitelist JSON, defaulting to deny-all")
        return BuildPolicy(nil, nil)
    end

    local root = jsonFile:GetRoot()
    if not root or not root:IsObject() then
        Warn("[Preview/UrlWhitelist] Whitelist root must be an object, defaulting to deny-all")
        return BuildPolicy(nil, nil)
    end

    return BuildPolicy(ReadStringArray(root, "urls"), ReadStringArray(root, "domains"))
end

function M.LoadPolicyFromResource(resourceName)
    resourceName = resourceName or M.DEFAULT_RESOURCE

    if not cache or not cache.GetFile then
        Warn("[Preview/UrlWhitelist] Resource cache is unavailable, defaulting to deny-all")
        return BuildPolicy(nil, nil)
    end

    local file = cache:GetFile(resourceName)
    if not file then
        Warn("[Preview/UrlWhitelist] Whitelist resource not found: " .. resourceName)
        return BuildPolicy(nil, nil)
    end

    local content = file:ReadString()
    file:Close()

    local policy = LoadPolicyFromString(content)
    policy.resourceName = resourceName
    return policy
end

local function IsRequestAllowed(policy, url, label)
    policy = policy or BuildPolicy(nil, nil)

    local normalizedUrl = NormalizeUrl(url)
    if not normalizedUrl then
        return false, "empty URL"
    end

    if policy.urls[normalizedUrl] then
        return true, normalizedUrl
    end

    if policy.domainCount > 0 then
        -- Pass the original url, not the normalized form, so the strict
        -- checks (no userinfo, no explicit port) see what the caller
        -- actually requested.
        local host = ExtractHostForDomainMatch(url)
        if host and policy.domains[host] then
            return true, host
        end
    end

    return false, "URL is not in the " .. (label or "service") .. " whitelist"
end
M.IsRequestAllowed = IsRequestAllowed

-- Install whitelist enforcement on every HTTP API reachable from game Lua:
-- Network:MakeHttpRequest and HttpClient:SetUrl/Send. Each outbound URL is
-- checked against `policy` before the request leaves the sandbox; `label`
-- ("client"/"service") only phrases the deny message.
--
-- Call during isolation init, before user scripts run: the wrapper closures
-- capture the original C functions and `policy`, so later tampering with
-- package.loaded or the globals cannot reach the unwrapped originals.
--
-- AddQuery is reduced to a warning no-op: its C++ accumulation semantics
-- (duplicate keys, ordering, URL-encoding) cannot be mirrored in Lua, so a
-- tracked URL would diverge from the bytes actually sent. Callers must put the
-- full query string into SetUrl.
--
-- A whitelist denial on HttpClient:Send invokes the client's OnError callback
-- (statusCode 0) so callers see an explicit failure rather than a silent no-op.
-- Network:MakeHttpRequest has no callback channel, so it still just returns nil.
function M.InstallHttpHooks(policy, label)
    local function CheckAllowed(url, apiName)
        local allowed, reason = IsRequestAllowed(policy, url, label)
        if not allowed then
            Warn(string.format("%s blocked: %s (%s)", apiName, reason, tostring(url)))
            return false
        end
        return true
    end

    if Network and Network.MakeHttpRequest then
        local origMakeHttpRequest = Network.MakeHttpRequest
        rawset(Network, "MakeHttpRequest", function(self, url, verb, headers, postData)
            if not CheckAllowed(url, "Network:MakeHttpRequest") then
                return nil
            end
            return origMakeHttpRequest(self, url, verb, headers, postData)
        end)
    end

    if not (HttpClient and HttpClient.SetUrl and HttpClient.Send) then
        Warn("[Preview/UrlWhitelist] HttpClient API unavailable; skipping HttpClient URL whitelist hooks")
        return
    end

    -- Defense in depth: if a future binding exposes `client.url = ...`, disable
    -- the property setter so SetUrl stays the only way to set the URL.
    local setters = rawget(HttpClient, ".set")
    if setters and setters.url then
        setters.url = nil
    end

    -- Track the URL from SetUrl for the Send-time check. Weak keys let finished
    -- clients be collected.
    local clientUrls = setmetatable({}, { __mode = "k" })

    -- Mirror the OnError callback into Lua so a whitelist denial can signal the
    -- caller instead of silently no-op-ing. The C++ side still holds its own copy
    -- (for real network errors); this copy only drives the synthetic block error.
    local clientErrorCbs = setmetatable({}, { __mode = "k" })

    local origSetUrl = HttpClient.SetUrl
    rawset(HttpClient, "SetUrl", function(self, url)
        clientUrls[self] = tostring(url or "")
        return origSetUrl(self, url)
    end)

    if HttpClient.OnError then
        local origOnError = HttpClient.OnError
        rawset(HttpClient, "OnError", function(self, callback)
            if type(callback) == "function" then
                clientErrorCbs[self] = callback
            end
            return origOnError(self, callback)
        end)
    end

    if HttpClient.AddQuery then
        rawset(HttpClient, "AddQuery", function(self)
            Warn("HttpClient:AddQuery is ignored in URL whitelist mode; include the full query string in SetUrl")
            return self
        end)
    end

    -- Fire the caller's OnError for a blocked request. Signature mirrors the C++
    -- error callback: (client, statusCode, error). statusCode is 0 because no
    -- request ever reached the network. Fired synchronously inside Send (the real
    -- network-error path is async); wrapped in pcall so a throwing callback cannot
    -- break the hook.
    local function FireBlockedError(self, message)
        local cb = clientErrorCbs[self]
        if not cb then
            return
        end
        local ok, err = pcall(cb, self, 0, message)
        if not ok then
            Warn("HttpClient OnError callback raised while handling a blocked request: " .. tostring(err))
        end
    end

    local origSend = HttpClient.Send
    rawset(HttpClient, "Send", function(self)
        local url = clientUrls[self]
        if not url or url == "" then
            Warn("HttpClient:Send blocked: URL was not configured")
            FireBlockedError(self, "HttpClient:Send blocked: URL was not configured")
            return nil
        end
        if not CheckAllowed(url, "HttpClient:Send") then
            FireBlockedError(self, "HttpClient:Send blocked: URL is not in the whitelist")
            return nil
        end
        return origSend(self)
    end)
end

return M
