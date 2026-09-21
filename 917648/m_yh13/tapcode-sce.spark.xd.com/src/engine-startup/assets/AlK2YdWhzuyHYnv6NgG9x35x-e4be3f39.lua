--- engine-startup/main.lua — UrhoX Bootstrap startup configuration
--- Runs in an independent Lua VM (LuaEnvironment::Startup)
--- Fixed C++ steps (before this script):
---   LoadVersionStep, LoadProjectManifestStep,
---   LoadSourceManifestsStep(engine-startup), InitializeResourceRouterStep


local function ConfigureServer(pipeline)
    -- Server: download resources, no UI.
    -- Do not add CleanupStep: versions share update/<game>/assets/ and
    -- one process would delete another version's hashed lua.
    pipeline:AddStep(LoadSourceManifestsStep:new())
    pipeline:AddStep(DownloadInitialPackageStep:new())
    pipeline:AddStep(LoadPreloadResourcesStep:new())
end

-- Forward declarations (implementations below ConfigureClient)
local resolveI18nLanguage
local PreloadI18nStep

local function ConfigureClient(pipeline)
    local ctx = pipeline:GetPipelineContext()
    local isWeb = GetPlatform() == "Web"
    local isReview = HasAppArg and HasAppArg("review")

    -- Set user pref path early so LoadJSONFile auto-selection can read user_lang
    if GetProjectRoot and localization.SetUserPrefPath then
        local projectRoot = GetProjectRoot()
        if projectRoot ~= "" then
            localization:SetUserPrefPath(projectRoot .. "savedata/")
        end
    end

    -- Reload localization: C++ BootstrapManager loaded from bundled resources (stale copy),
    -- now ResourceRouter is configured — release cached JSONFile so GetResource re-routes
    -- to the manifest version, then reset localization and reload.
    cache:ReleaseResource("JSONFile", "Strings/Bootstrap.json", true)
    localization:Reset()
    localization:LoadJSONFile("Strings/Bootstrap.json")

    -- WASM: first load uses web page loading (project-index.js), skip NanoVG UI.
    -- On restart (e.g. language switch), web page loading won't re-appear,
    -- so fall back to NanoVG loading UI.
    local isFirstBoot = not GetGlobalVar("_startup_has_booted"):GetBool()
    SetGlobalVar("_startup_has_booted", Variant(true))
    local LoadingUI

    -- -review 模式：隐藏 C++ LoadingUI 让登录按钮可见，点击后立即执行 LoginStep
    if isReview and not ctx.skipLogin then
        local StartupUI
        ctx:HideNativeLoadingUI()
        pipeline:AddLuaStep({
            name = "ShowLoginPage",
            weight = 0.01,
            onExecute = function(step)
                StartupUI = require("engine-startup.startup_ui")
                StartupUI.ShowLoginPage(function()
                    step:Complete(true)
                end)
            end,
        })
        pipeline:AddStep(LoginStep:new())
        -- 手机端（iOS/Android）由 TapTap SDK 内置实名认证，PC 才需要单独走
        if not isWeb and GetPlatform() ~= "iOS" and GetPlatform() ~= "Android" then
            pipeline:AddLuaStep({
                name = "AntiAddictCheck",
                weight = 0.01,
                onExecute = function(step)
                    local AntiAddict = require("engine-startup.anti_addict")
                    AntiAddict.RunCheckFlow(StartupUI, GetUserId and GetUserId() or 0,
                        function() step:Complete(true) end,
                        function() if engine then engine:Exit() end end)
                end,
            })
        end
        -- 登录完成并处理 review 弹窗后销毁 startup_ui，初始化 LoadingUI
        pipeline:AddLuaStep({
            name = "InitLoadingUI",
            weight = 0.01,
            onExecute = function(step)
                if StartupUI then
                    StartupUI.Destroy()
                    StartupUI = nil
                end
                if not isWeb or not isFirstBoot then
                    LoadingUI = require("engine-startup.loading_ui")
                    LoadingUI.Init(ctx)
                end
                step:Complete(true)
            end,
        })
    else
        if not isWeb or not isFirstBoot then
            LoadingUI = require("engine-startup.loading_ui")
            LoadingUI.Init(ctx)
        end
    end

    pipeline:AddStep(UpdateProjectInfoStep:new())
    pipeline:AddStep(LoadSourceManifestsStep:new())
    -- 旧二进制没有该 Step；engine-startup 资源必须继续兼容它们。
    if ClearShaderCacheStep ~= nil then
        pipeline:AddStep(ClearShaderCacheStep:new())
    end

    -- i18n: resolve language, set variant tag, prefetch translation file.
    -- Runs right after LoadSourceManifestsStep so i18n.json is registered in the manifest;
    -- runs before DownloadInitialPackageStep / LoadPreloadResourcesStep so SetVariantTag
    -- influences which locale-specific assets get pre-downloaded.
    pipeline:AddLuaStep(PreloadI18nStep())

    if not isWeb or (fileSystem.HasPersistentFS and fileSystem:HasPersistentFS()) then
        pipeline:AddStep(DownloadInitialPackageStep:new())
    end
    pipeline:AddStep(LoadPreloadResourcesStep:new())
    pipeline:AddStep(CleanupStep:new())
    pipeline:AddStep(RecordProjectSizeStep:new())
    -- CDN 脚本可能先于二进制更新，旧二进制没有该 Step 时直接跳过。
    if CleanupOtherProjectsStep and CleanupOtherProjectsStep.new then
        pipeline:AddStep(CleanupOtherProjectsStep:new())
    end

    local earlyLogin = ctx.HasVar and ctx:HasVar("earlyLogin")

    if ctx:HasDirectConnect() then
        pipeline:AddStep(DirectConnectStep:new())
    elseif not ctx.skipLogin and not earlyLogin and not isReview then
        -- 默认 entrance 配置（域名映射 / wss / 443）由 C++ LoginStep 处理。
        -- 线上紧急修复时取消下方注释并改写规则即可，CDN 热更生效，无需重编客户端：
        -- pipeline:AddLuaStep({
        --     name = "RenameEntranceIP",
        --     weight = 0.01,
        --     onExecute = function(step)
        --         ctx.entranceIP = "your-entrance.example.com"
        --         ctx.entrancePort = 443
        --         ctx.entranceProtocol = "wss"
        --         step:Complete(true)
        --     end,
        -- })
        pipeline:AddStep(LoginStep:new())
    end

    pipeline:AddStep(ReadyStep:new())

    -- DEBUG: test blockingRetry dialog (step:Complete(false) triggers ConfirmRetry)
    -- pipeline:AddLuaStep({
    --     name = "DebugFailStep",
    --     weight = 1.0,
    --     blockingRetry = true,
    --     onExecute = function(step)
    --         step:Complete(false, "Simulated failure for testing retry dialog")
    --     end,
    -- })

    -- Fade out loading UI as final step.
    -- LoadingUI 可能为 nil（Web 首次启动、或 review 模式静默登录跳过了登录页）；
    -- 因此不在配置阶段判断，而是在 onExecute 里判断，避免漏加步骤。
    pipeline:AddLuaStep({
        name = "FadeOutLoading",
        weight = 0.01,
        onExecute = function(step)
            if LoadingUI then
                LoadingUI.FadeOut(function()
                    step:Complete(true)
                    LoadingUI.Destroy()
                end)
            else
                step:Complete(true)
            end
        end,
    })
end

-- ============================================================
-- i18n config + language resolution
-- KEEP IN SYNC with urhox-libs/Engine/i18n.lua — 直接复制粘贴同步
-- ============================================================

local NONE = {}
local i18nConfig_ = nil

-- UUID 来自 engine-res-project 的 .meta 文件，重新生成 meta 后需同步更新
local ENGINE_I18N_CONFIG_UUID = "Q4M3GntfTmiNZCdTeiz5Kg"  -- .project/i18n.json.meta
local ENGINE_I18N_LANG_URIS = {
    zh_CN = "uuid://-73mcwx1QB6NyLrwJxv8Kg",  -- i18n/zh_CN.json.meta
    en    = "uuid://u05oYbz5RtecsyHB9-bmKQ",   -- i18n/en.json.meta
}
local URHOX_LIBS_I18N_PREFIX = "urhox-libs/i18n/"

local function engineLangUri(lang)
    return ENGINE_I18N_LANG_URIS[lang]
end

local function urhoxLibsLangUri(lang)
    local uri = URHOX_LIBS_I18N_PREFIX .. lang .. ".json"
    if cache.GetResUuid then
        local uuid = cache:GetResUuid(uri)
        if uuid and uuid ~= "" then return uri end
    end
    return cache:Exists(uri) and uri or nil
end

local function translationUris(lang)
    local uris = {}
    local engineUri = engineLangUri(lang)
    if engineUri then uris[#uris + 1] = engineUri end
    local urhoxLibsUri = urhoxLibsLangUri(lang)
    if urhoxLibsUri then uris[#uris + 1] = urhoxLibsUri end
    uris[#uris + 1] = "i18n/" .. lang .. ".json"
    return uris
end

local function loadConfig()
    if i18nConfig_ ~= nil then
        return i18nConfig_ ~= NONE and i18nConfig_ or nil
    end
    if not cache:Exists("i18n.json") then
        i18nConfig_ = NONE
        return nil
    end
    local file = cache:GetFile("i18n.json")
    if not file then
        i18nConfig_ = NONE
        return nil
    end
    local content = file:ReadString()
    file:Close()
    if not content or content == "" then
        i18nConfig_ = NONE
        return nil
    end
    local ok, data = pcall(cjson.decode, content)
    if not ok or not data then
        i18nConfig_ = NONE
        return nil
    end

    -- engine-res 增加了多语言能力，非多语言项目会 fallback 到引擎的 i18n.json，
    -- 通过 GetResUuid 与引擎已知 UUID 比较来检测，fallback 时 support_langs 限制为 source_lang。
    if cache.GetResUuid then
        local uuid = cache:GetResUuid("i18n.json")
        log:Write(LOG_INFO, "[i18n] loadConfig: uuid='" .. tostring(uuid) .. "' engine='" .. ENGINE_I18N_CONFIG_UUID .. "' match=" .. tostring(uuid == ENGINE_I18N_CONFIG_UUID))
        if uuid == ENGINE_I18N_CONFIG_UUID and data.source_lang then
            data.support_langs = { data.source_lang }
            data.support_langs_str = data.source_lang
            log:Write(LOG_INFO, "[i18n] loadConfig: engine fallback, support_langs='" .. data.support_langs_str .. "'")
        end
    end

    if not data.support_langs then
        local langs = {}
        if data.source_lang and data.source_lang ~= "" then
            langs[#langs + 1] = data.source_lang
        end
        if data.target_langs then
            for _, lang in ipairs(data.target_langs) do
                langs[#langs + 1] = lang
            end
        end
        data.support_langs = langs
        data.support_langs_str = #langs > 0 and table.concat(langs, ",") or ""
    end

    i18nConfig_ = data
    return i18nConfig_
end

--- Resolve language: user pref > -lang > system > source_lang.
resolveI18nLanguage = function()
    local cfg = loadConfig()
    if not cfg then return nil, nil end
    local supportLangs = cfg.support_langs_str

    if localization.ReadUserPrefLanguage then
        local pref = localization:ReadUserPrefLanguage()
        if pref and pref ~= "" then
            local matched = pref
            if supportLangs ~= "" and localization.MatchLanguage then
                matched = localization:MatchLanguage(pref, supportLangs)
            end
            if matched and matched ~= "" then
                return matched, cfg
            end
        end
    end

    local argLang = GetAppArgv and GetAppArgv("lang") or ""
    if argLang ~= "" then
        local matched = argLang
        if supportLangs ~= "" and localization.MatchLanguage then
            matched = localization:MatchLanguage(argLang, supportLangs)
        end
        if matched and matched ~= "" then
            log:Write(LOG_INFO, "[i18n] -lang='" .. argLang .. "' matched='" .. matched .. "'")
            return matched, cfg
        end
        log:Write(LOG_WARNING, "[i18n] -lang='" .. argLang .. "' not in support_langs='" .. supportLangs .. "', falling through")
    end

    local sysLang = localization.GetSystemLanguage and localization:GetSystemLanguage() or ""
    if sysLang ~= "" then
        local matched = sysLang
        if supportLangs ~= "" and localization.MatchLanguage then
            matched = localization:MatchLanguage(sysLang, supportLangs)
        end
        if matched and matched ~= "" then
            return matched, cfg
        end
    end

    if cfg.source_lang and cfg.source_lang ~= "" then
        return cfg.source_lang, cfg
    end

    return nil, cfg
end

-- ============================================================
-- END SYNC BLOCK
-- ============================================================

--- Pipeline step: resolve language, set variant tag, prefetch engine + urhox-libs + project translation files.
--- @return table LuaStep
PreloadI18nStep = function()
    return {
        name = "PreloadI18nStep",
        weight = 0.2,
        blockingRetry = true,
        onExecute = function(step)
            if not cache.GetResUuid or cache:GetResUuid("i18n.json") == "" then
                log:Write(LOG_INFO, "[i18n] PreloadI18nStep: i18n.json not in manifest, skip")
                step:Complete(true)
                return
            end

            local dm = GetDownloadManager and GetDownloadManager()
            if not dm then
                log:Write(LOG_WARNING, "[i18n] PreloadI18nStep: DownloadManager unavailable, skip")
                step:Complete(true)
                return
            end

            dm:DownloadResource("i18n.json", function(task)
                if not task or not task:IsSuccess() then
                    step:Complete(false, "Failed to download translation files")
                    return
                end

                local lang, cfg = resolveI18nLanguage()
                log:Write(LOG_INFO, "[i18n] PreloadI18nStep: resolved='" .. tostring(lang) .. "'")
                if not lang or lang == "" then
                    step:Complete(true)
                    return
                end

                -- Set variant tag (skip when lang == source_lang — source uses default assets)
                if cache.SetVariantTag then
                    local variantLang = lang
                    if cfg and lang == cfg.source_lang then
                        variantLang = ""
                    end
                    if variantLang ~= "" then
                        cache:SetVariantTag(2000, variantLang)
                        log:Write(LOG_INFO, "[i18n] PreloadI18nStep: SetVariantTag='" .. variantLang .. "'")
                    end
                end

                -- Preload target-language tables and, when a translated target
                -- language is active, the source-language tables required by
                -- naked NanoVG text fit.
                -- They form one required batch: any failed resource fails the
                -- preload step.
                local uris = translationUris(lang)

                local sourceLang = cfg and cfg.source_lang or nil
                if sourceLang and sourceLang ~= ""
                    and sourceLang ~= lang then
                    for _, uri in ipairs(translationUris(sourceLang)) do
                        uris[#uris + 1] = uri
                    end
                end

                dm:DownloadResources(uris, function(success)
                    if success then
                        step:Complete(true)
                    else
                        step:Complete(false, "Failed to download translation files")
                    end
                end)
            end)
        end,
    }
end

function OnPipelineConfigure(pipeline)
    if IsServerMode() then
        ConfigureServer(pipeline)
    else
        ConfigureClient(pipeline)
    end
end
