-- ====================================================================
-- 战棋游戏 - 怪物入侵（单角色版）
-- ====================================================================
-- 入口文件：组装各模块，加载资源，注册事件
-- ====================================================================

require "LuaScripts/Utilities/Sample"

local GS = require("GameState")
local Combat = require("Combat")
local Renderer = require("Renderer")
local Input = require("Input")
local ImageManager = require("ImageManager")
local BoardOverlay = require("BoardOverlay")
local RainEffect = require("RainEffect")
local WindEffect = require("WindEffect")
local ScorchEffect = require("ScorchEffect")
local EventManager = require("Event.EventManager")
require("Event.Event_Awakening")  -- 注册苏醒事件
require("Event.Event_DifenRevenge")  -- 注册迪芬复仇事件
local OnlineMonitor = require("OnlineMonitor")
local SignInSystem = require("SignInSystem")
local SessionLock = require("SessionLock")
local BanManager = require("BanManager")

-- ====================================================================
-- NanoVG 上下文 & 场景
-- ====================================================================
local vg = nil
---@type Scene|nil
local scene_ = nil

-- ====================================================================
-- Start
-- ====================================================================
function Start()
    SampleStart()

    vg = nvgCreate(1)
    if not vg then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    local fontNormal = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontNormal == -1 then
        print("ERROR: Failed to load font")
        return
    end

    -- ================================================================
    -- ImageManager 统一加载所有图片资源
    -- ================================================================
    ImageManager.init(vg)

    -- UI 类图片（背景、头像、图标等）
    ImageManager.loadBatch("ui", {
        {"bgImage",       "image/bg_grass.png"},
        {"playerAvatar",  "image/player_avatar.png"},
        {"classAvatarTraveler", "image/player_hooded.png"},
        {"classAvatarMage",     "image/class_mage.png"},
        {"classAvatarHunter",   "image/class_hunter.png"},
        {"classAvatarPriest",   "image/class_priest.png"},
        {"classAvatarWarrior",  "image/class_warrior.png"},
        {"classAvatarAssassin", "image/class_assassin.png"},
        {"swordImage",    "image/sword_icon.png"},
        {"bowImage",      "image/bow_floating.png"},
        {"daggerImage",   "image/dagger_iron.png"},
        {"maceImage",     "image/mace_weapon.png"},
        {"staffImage",    "image/staff_weapon.png"},
        {"arrowImage",    "image/arrow.png"},
        {"slimeImage",    "image/slime_icon.png"},
        {"tombstoneImage","image/tombstone.png"},
        {"characterIcon", "image/character_icon.png"},
        {"backpackIcon",  "image/backpack_icon.png"},
        {"mapIcon",       "image/map_icon.png"},
        {"skillIcon",     "image/skill_icon.png"},
        {"bookIcon",      "image/book_icon.png"},
        {"charPanelBg",   "image/char_panel_bg.png"},
        {"parchmentBg",   "image/parchment_bg.png"},
        {"worldMapImg",   "image/world_map.png"},
        {"townClearwater","image/town_clearwater.png"},
        {"townClearwaterDusk","image/town_clearwater_dusk.png"},
        {"townClearwaterDawn","image/town_clearwater_dawn.png"},
        {"townClearwaterNight","image/town_clearwater_night.png"},
        {"blacksmithInterior","image/bg_blacksmith.png"},
        {"potionShopInterior","image/bg_potion_shop.png"},
        {"potionShopInterior2","image/potion_shop_bg2.png"},
        {"jewelryShopInterior","image/bg_jewelry_shop.png"},
        {"armorShopInterior","image/bg_armor_shop.png"},
        {"tavernInterior","image/bg_tavern.png"},
        {"bulletinBoardInterior","image/bulletin_board_interior.png"},
        {"guildInterior","image/guild_interior.png"},
        {"guildMasterOfficeInterior","image/bg_guild_master_office.png"},
        {"adMachineInterior","image/bg_ad_machine.png"},
        {"forestElfScene","image/forest_elf_scene.png"},
        {"npcForestElf","image/npc_forest_elf.png"},
        {"npcForestElfVisit","image/npc_forest_elf_visit.png"},
        {"npcGuildMaster","image/npc_guild_master.png"},
        {"npcGuildReceptionist","image/npc_guild_receptionist.png"},
        {"npcPotionShopOwner","image/npc_potion_shop_owner.png"},
        {"npcJewelryShopOwner","image/npc_jewelry_shop_owner.png"},
        {"npcTavernKeeper","image/npc_tavern_keeper.png"},
        {"npcTavernDancer","image/npc_tavern_dancer.png"},

        {"charAvatarImg", "image/char_avatar.png"},
        {"moneyBagImg",   "image/money_bag.png"},
        {"lockClosed",    "image/lock_closed.png"},
        {"lockOpen",      "image/lock_open.png"},
        {"mapTowerBg",    "image/cg_infinite_tower.png"},
        {"mapAbyssBg",    "image/bg_abyss.png"},
        {"mapSlimeRevengeBg", "image/monster_slime_king.png"},
        {"mapDihataRevengeBg", "image/goblin_hero_dihata.png"},
    })

    -- 稀有度图片
    ImageManager.loadBatch("rarity", {
        {"common",   "image/rarity_common.png"},
        {"uncommon", "image/rarity_uncommon.png"},
        {"rare",     "image/rarity_rare.png"},
    })

    -- 技能图标
    ImageManager.loadBatch("skill", {
        {"strike",       "image/skill_strike.png"},
        {"dual_wield",   "image/skill_dual_wield.png"},
        {"counter",      "image/skill_counter.png"},
        {"whirlwind",    "image/skill_whirlwind.png"},
        {"hp_up",        "image/skill_hp_up.png"},
        {"mighty",       "image/skill_mighty.png"},
        {"shield_master","image/skill_shield_master.png"},
        {"crit_rate",    "image/skill_crit_rate.png"},
        {"crit_dmg",     "image/skill_crit_dmg.png"},
        {"w_blood_drink","image/skill_blood_drink.png"},
        {"sword_prof",   "image/skill_sword_prof.png"},
        {"sword_master", "image/skill_sword_master.png"},
        {"mst_counter",  "image/skill_mst_counter.png"},
        {"mst_whirl",    "image/skill_mst_whirl.png"},
        {"deriv_storm",  "image/skill_deriv_storm.png"},
        {"shield_bash",  "image/skill_shield_bash.png"},
        {"charge",       "image/skill_charge.png"},
        {"w_hp_up",      "image/skill_hp_up.png"},
        {"charge_roar",  "image/skill_charge_roar.png"},
        {"shield_prof",  "image/skill_shield_prof.png"},
        {"cleave",       "image/skill_cleave.png"},
        {"pwr_stk",      "image/skill_pwr_stk.png"},
        {"mst_stk",      "image/skill_mst_stk.png"},
        {"sup_stk",      "image/skill_sup_stk.png"},
        -- 猎人技能（暂用强击图标）
        {"h_power_shot",   "image/skill_power_shot.png"},
        {"h_hit_up",       "image/skill_hit_up.png"},
        {"h_enh_shot",     "image/skill_enh_shot.png"},
        {"h_hound",        "image/skill_hound.png"},
        {"h_scatter",      "image/skill_scatter.png"},
        {"h_distraction",  "image/skill_distraction.png"},
        {"h_shoot_prof",   "image/skill_shoot_prof.png"},
        {"h_patk_up",      "image/skill_mighty.png"},
        {"h_beast_prof",   "image/skill_beast_prof.png"},
        {"h_hp_regen",     "image/skill_quick_adj.png"},
        {"h_mark_target",  "image/skill_mark_target.png"},
        {"h_stun_shot",    "image/skill_stun_shot.png"},
        {"h_bond_link",    "image/skill_bond_link.png"},
        {"h_aim",          "image/skill_aim.png"},
        {"h_pcrit_up",     "image/skill_crit_rate.png"},
        {"h_full_draw",    "image/skill_full_draw.png"},
        {"h_beast_master", "image/skill_beast_master.png"},
        {"h_chase_arrow",  "image/skill_chase_arrow.png"},
        {"h_shoot_master", "image/skill_shoot_master.png"},
        {"h_snipe",        "image/skill_snipe.png"},
        {"h_wild",         "image/skill_wild.png"},
        {"h_shuttle",      "image/skill_shuttle.png"},
        {"h_pcrit_dmg",    "image/skill_crit_dmg.png"},
        -- 刺客技能（暂用强击图标）
        {"a_weapon_throw", "image/skill_weapon_throw.png"},
        {"a_moon_shadow",  "image/skill_moon_shadow.png"},
        {"a_enh_throw",    "image/skill_enh_throw.png"},
        {"a_double_strike","image/skill_double_strike.png"},
        {"a_dodge_up",     "image/skill_dodge_up.png"},
        {"a_dagger_prof",  "image/skill_dagger_prof.png"},
        {"a_poison_throw", "image/skill_poison_throw.png"},
        {"a_dual_prof",    "image/skill_dual_prof.png"},
        {"a_stealth",      "image/skill_stealth.png"},
        {"a_sand_throw",   "image/skill_sand_throw.png"},
        {"a_spare_weapon", "image/skill_spare_weapon.png"},
        {"a_aspd_up",      "image/skill_aspd_up.png"},
        {"a_flash_assault","image/skill_flash_assault.png"},
        {"a_assassinate",  "image/skill_assassinate.png"},
        {"a_armor_break",  "image/skill_armor_break.png"},
        {"a_dual_master",  "image/skill_dual_master.png"},
        {"a_deflect",      "image/skill_deflect.png"},
        {"a_dagger_master","image/skill_dagger_master.png"},
        {"a_notice",       "image/skill_notice.png"},
        {"a_storm_rain",   "image/skill_storm_rain.png"},
        {"a_phantom",      "image/skill_phantom.png"},
        {"a_full_moon",    "image/skill_full_moon.png"},
        {"a_pcrit_dmg",    "image/skill_crit_dmg.png"},
        -- 法师技能（暂用强击图标）
        {"m_spark",        "image/skill_spark.png"},
        {"m_ice_spike",    "image/skill_ice_spike.png"},
        {"m_lightning",    "image/skill_lightning.png"},
        {"m_mp_up",        "image/skill_mp_up.png"},
        {"m_fire_shield",  "image/skill_fire_shield.png"},
        {"m_ice_ring",     "image/skill_ice_ring.png"},
        {"m_chain_light",  "image/skill_chain_light.png"},
        {"m_magic_shield", "image/skill_magic_shield.png"},
        {"m_fire_prof",    "image/skill_fire_prof.png"},
        {"m_ice_prof",     "image/skill_ice_prof.png"},
        {"m_elec_prof",    "image/skill_elec_prof.png"},
        {"m_mp_regen",     "image/skill_matk_up.png"},
        {"m_fireball",     "image/skill_fireball.png"},
        {"m_ice_wall",     "image/skill_ice_wall.png"},
        {"m_thunder",      "image/skill_thunder.png"},
        {"m_blink",        "image/skill_blink.png"},
        {"m_fire_master",  "image/skill_fire_master.png"},
        {"m_ice_master",   "image/skill_ice_master.png"},
        {"m_elec_master",  "image/skill_elec_master.png"},
        {"m_cast_spd",     "image/skill_cast_spd.png"},
        {"m_meteor",       "image/skill_meteor.png"},
        {"m_blizzard",     "image/skill_blizzard.png"},
        {"m_thunder_cloud","image/skill_thunder_cloud.png"},
        {"m_matk_up",      "image/skill_mana_efficient.png"},
        -- 牧师技能（暂用强击图标）
        {"p_baptism",      "image/skill_baptism.png"},
        {"p_prayer",       "image/skill_prayer.png"},
        {"p_radiance",     "image/skill_radiance.png"},
        {"p_bless",        "image/skill_bless.png"},
        {"p_hp_regen",     "image/skill_quick_adj.png"},
        {"p_holy_spring",  "image/skill_holy_spring.png"},
        {"p_restore",      "image/skill_restore.png"},
        {"p_mace_prof",    "image/skill_mace_prof.png"},
        {"p_shield_prof",  "image/skill_shield_prof.png"},
        {"p_piety",        "image/skill_piety.png"},
        {"p_holy_purity",  "image/skill_holy_purity.png"},
        {"p_patk_up",      "image/skill_mighty.png"},
        {"p_dmg_reduce",   "image/skill_dmg_reduce.png"},
        {"p_conquer_bless","image/skill_conquer_bless.png"},
        {"p_hp_up",        "image/skill_hp_up.png"},
        {"p_mace_master",  "image/skill_mace_master.png"},
        {"p_shield_master","image/skill_shield_master.png"},
        {"p_shelter_bless","image/skill_shelter_bless.png"},
        {"p_holy_heal",    "image/skill_holy_heal.png"},
        {"p_exorcism",     "image/skill_exorcism.png"},
        {"p_divine_grace", "image/skill_divine_grace.png"},
        {"p_miracle_bless","image/skill_miracle_bless.png"},
        {"p_holy_tree",    "image/skill_holy_tree.png"},
    })

    -- 生活技能图标
    for _, lsDef in ipairs(GS.LIFE_SKILL_DEFS) do
        local handle = ImageManager.load("lifeskill", lsDef.id, lsDef.iconPath)
        GS.lifeSkillImages[lsDef.id] = handle
    end

    -- 物品图片（从 itemTemplates 数据库加载）
    ImageManager.loadFromDB("item", GS.itemTemplates, "icon")
    -- 同步到 GS.itemImages 供现有代码使用
    GS.itemImages = ImageManager.getCategory("item")

    -- 怪物图片：按需加载（首次渲染时通过 ImageManager.lazyGet 加载）

    ImageManager.printStats()

    -- ================================================================
    -- 注入 NanoVG 资源到 Renderer（兼容现有代码）
    -- ================================================================
    Renderer.vg = vg
    Renderer.fontNormal = fontNormal
    Renderer.bgImage = ImageManager.get("ui", "bgImage")
    Renderer.playerAvatar = ImageManager.get("ui", "playerAvatar")
    Renderer.classAvatars = {
        mage     = ImageManager.get("ui", "classAvatarMage"),
        hunter   = ImageManager.get("ui", "classAvatarHunter"),
        priest   = ImageManager.get("ui", "classAvatarPriest"),
        warrior  = ImageManager.get("ui", "classAvatarWarrior"),
        assassin = ImageManager.get("ui", "classAvatarAssassin"),
        traveler = ImageManager.get("ui", "classAvatarTraveler"),
    }
    Renderer.swordImage = ImageManager.get("ui", "swordImage")
    Renderer.bowImage = ImageManager.get("ui", "bowImage")
    Renderer.daggerImage = ImageManager.get("ui", "daggerImage")
    Renderer.maceImage = ImageManager.get("ui", "maceImage")
    Renderer.staffImage = ImageManager.get("ui", "staffImage")
    Renderer.arrowImage = ImageManager.get("ui", "arrowImage")
    Renderer.slimeImage = ImageManager.get("ui", "slimeImage")
    -- monsterImages 不再预加载，Renderer 通过 ImageManager.lazyGet 按需加载
    Renderer.tombstoneImage = ImageManager.get("ui", "tombstoneImage")
    Renderer.characterIcon = ImageManager.get("ui", "characterIcon")
    Renderer.backpackIcon = ImageManager.get("ui", "backpackIcon")
    Renderer.mapIcon = ImageManager.get("ui", "mapIcon")
    Renderer.skillIcon = ImageManager.get("ui", "skillIcon")
    Renderer.bookIcon = ImageManager.get("ui", "bookIcon")
    Renderer.charPanelBg = ImageManager.get("ui", "charPanelBg")
    Renderer.parchmentBg = ImageManager.get("ui", "parchmentBg")
    Renderer.worldMapImg = ImageManager.get("ui", "worldMapImg")
    Renderer.mapTowerBg = ImageManager.get("ui", "mapTowerBg")
    Renderer.mapAbyssBg = ImageManager.get("ui", "mapAbyssBg")
    Renderer.mapSlimeRevengeBg = ImageManager.get("ui", "mapSlimeRevengeBg")
    Renderer.mapDihataRevengeBg = ImageManager.get("ui", "mapDihataRevengeBg")
    Renderer.npcForestElfImg = ImageManager.get("ui", "npcForestElf")
    Renderer.npcForestElfVisitImg = ImageManager.get("ui", "npcForestElfVisit")
    -- 伴侣头像映射（家中显示用）
    Renderer.partnerPortraits = {
        guild_master = ImageManager.get("ui", "npcGuildMaster"),
        guild_receptionist = ImageManager.get("ui", "npcGuildReceptionist"),
        potion_shop_owner = ImageManager.get("ui", "npcPotionShopOwner"),
        jewelry_shop_owner = ImageManager.get("ui", "npcJewelryShopOwner"),
        tavern_keeper = ImageManager.get("ui", "npcTavernKeeper"),
        tavern_dancer = ImageManager.get("ui", "npcTavernDancer"),
        forest_elf = ImageManager.get("ui", "npcForestElf"),
    }
    -- 注册棋盘覆盖层图片
    BoardOverlay.registerBatch("town", {
        clearwater = ImageManager.get("ui", "townClearwater"),
        clearwater_dusk = ImageManager.get("ui", "townClearwaterDusk"),
        clearwater_dawn = ImageManager.get("ui", "townClearwaterDawn"),
        clearwater_night = ImageManager.get("ui", "townClearwaterNight"),
    })
    BoardOverlay.registerBatch("building", {
        blacksmith = ImageManager.get("ui", "blacksmithInterior"),
        potion_shop = ImageManager.get("ui", "potionShopInterior"),
        potion_shop_2 = ImageManager.get("ui", "potionShopInterior2"),
        jewelry_shop = ImageManager.get("ui", "jewelryShopInterior"),
        armor_shop = ImageManager.get("ui", "armorShopInterior"),
        tavern = ImageManager.get("ui", "tavernInterior"),
        bulletin_board = ImageManager.get("ui", "bulletinBoardInterior"),
        guild = ImageManager.get("ui", "guildInterior"),
        guild_master_office = ImageManager.get("ui", "guildMasterOfficeInterior"),
        guild_ad_machine = ImageManager.get("ui", "adMachineInterior"),
        forest_elf = ImageManager.get("ui", "forestElfScene"),
    })

    Renderer.charAvatarImg = ImageManager.get("ui", "charAvatarImg")
    Renderer.moneyBagImg = ImageManager.get("ui", "moneyBagImg")
    Renderer.lockClosedImg = ImageManager.get("ui", "lockClosed")
    Renderer.lockOpenImg = ImageManager.get("ui", "lockOpen")
    Renderer.skillImages = ImageManager.getCategory("skill")
    Renderer.rarityImages = ImageManager.getCategory("rarity")

    -- 创建最小场景（用于音频播放）
    scene_ = Scene()

    -- 加载并播放背景音乐
    -- BGM 系统：预加载所有背景音乐
    bgmTracks = {}
    -- default 使用主题曲（慈爱平原等未指定区域的兜底BGM）
    local defaultBgm = cache:GetResource("Sound", "audio/主题曲.ogg")
    if defaultBgm then defaultBgm.looped = true; bgmTracks["default"] = defaultBgm end
    local manorBgm = cache:GetResource("Sound", "audio/巴洛庄园圆舞曲.ogg")
    if manorBgm then manorBgm.looped = true; bgmTracks["manor"] = manorBgm end
    local townBgm = cache:GetResource("Sound", "audio/清水镇.ogg")
    if townBgm then townBgm.looped = true; bgmTracks["town"] = townBgm end
    local forestBgm = cache:GetResource("Sound", "audio/垂雾森林.ogg")
    if forestBgm then forestBgm.looped = true; bgmTracks["forest"] = forestBgm end
    local seaBgm = cache:GetResource("Sound", "audio/灰海.ogg")
    if seaBgm then seaBgm.looped = true; bgmTracks["sea"] = seaBgm end
    local mountainBgm = cache:GetResource("Sound", "audio/灰山.ogg")
    if mountainBgm then mountainBgm.looped = true; bgmTracks["mountain"] = mountainBgm end
    local fortBgm = cache:GetResource("Sound", "audio/升月堡.ogg")
    if fortBgm then fortBgm.looped = true; bgmTracks["fort"] = fortBgm end
    local menuBgm = cache:GetResource("Sound", "audio/主题曲.ogg")
    if menuBgm then menuBgm.looped = true; bgmTracks["menu"] = menuBgm end
    local undeadBgm = cache:GetResource("Sound", "audio/亡灵之曲.ogg")
    if undeadBgm then undeadBgm.looped = true; bgmTracks["undead"] = undeadBgm end

    local bgmNode = scene_:CreateChild("BGM")
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = SOUND_MUSIC
    bgmSource.gain = 0.4 * GS.masterVolume
    currentBgmKey = ""  -- 空值，让 Update 第一帧自动选择正确BGM

    -- 加载音效并注入到 Combat
    local sfxAttack = cache:GetResource("Sound", "audio/sfx/attack_normal.ogg")
    if sfxAttack then
        print("Attack sound loaded")
    else
        print("WARNING: Failed to load attack sound")
    end

    local sfxSlimeHit = cache:GetResource("Sound", "audio/sfx/slime_hit.ogg")

    local sfxMaceHit = cache:GetResource("Sound", "audio/sfx/mace_hit.ogg")
    if sfxMaceHit then
        print("Mace hit sound loaded")
    else
        print("WARNING: Failed to load mace hit sound")
    end

    local sfxTaunt = cache:GetResource("Sound", "audio/sfx/sfx_taunt.ogg")
    local sfxWhirlwind = cache:GetResource("Sound", "audio/sfx/whirlwind_slash.ogg")
    local sfxShieldBlock = cache:GetResource("Sound", "audio/sfx/shield_block.ogg")

    Combat.sfxAttack = sfxAttack
    Combat.sfxSlimeHit = sfxSlimeHit
    Combat.sfxMaceHit = sfxMaceHit
    Combat.sfxTaunt = sfxTaunt
    Combat.sfxWhirlwind = sfxWhirlwind
    Combat.sfxShieldBlock = sfxShieldBlock
    Combat.scene_ = scene_

    SampleInitMouseMode(MM_FREE)

    -- 注册事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("TextInput", "HandleTextInput")
    SubscribeToEvent("TextEditing", "HandleTextEditing")

    -- 从后台恢复焦点时立刻触发 SessionLock 即时检查
    -- 防止 Device B 后台放置期间 Device A 产生了新 sessionId，
    -- Device B 恢复后在心跳窗口期（最长5秒）内误触发云存档
    SubscribeToEvent("InputFocus", function(_, eventData)
        local hasFocus = eventData["Focus"]:GetBool()
        if hasFocus then
            SessionLock.checkOnResume()
        end
    end)

    -- 启动时从云端读取音量设置 & 预加载云存档
    GS.loadVolumeFromCloud()
    GS.loadAnimationToggleFromCloud()
    GS.loadDisplayTogglesFromCloud()
    -- 启动时先按默认值（竖屏）锁定方向，避免解锁所有方向导致 Android 横向旋转闪烁
    -- 异步读取云端偏好后会自动切换到用户保存的方向
    GS.applyScreenOrientation()
    GS.loadOrientationFromCloud()
    GS.preloadCloudSave()
    GS.loadAdFreeFromCloud()

    -- 初始化天气效果
    RainEffect.init(vg)
    WindEffect.init(vg)
    ScorchEffect.init(vg)

    -- 多端会话锁：写入本机 session ID 到云端
    SessionLock.init()

    -- 实时封禁系统初始化
    BanManager.init()

    print("=== 战棋游戏 - 怪物入侵 ===")
end

function Stop()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

-- ====================================================================
-- 事件委托：输入
-- ====================================================================
function HandleMouseDown(eventType, eventData)
    Input.handleMouseDown(eventType, eventData)
end

function HandleMouseUp(eventType, eventData)
    Input.handleMouseUp(eventType, eventData)
end

function HandleKeyDown(eventType, eventData)
    -- GM 封禁面板按键处理
    if BanManager.isInputActive() then
        local key = eventData["Key"]:GetInt()
        if key == KEY_BACKSPACE then
            BanManager.backspaceInput()
            return
        elseif key == KEY_ESCAPE then
            BanManager.deactivateInput()
            return
        elseif key == KEY_RETURN or key == KEY_RETURN2 then
            local text = BanManager.getGMInputText()
            if #text > 0 then
                BanManager.gmBanUserByInput(text)
            end
            return
        end
    end
    -- GM 存档修复 Tab 按键处理
    if BanManager.restoreIsUserIdActive() then
        local key = eventData["Key"]:GetInt()
        if key == KEY_BACKSPACE then
            BanManager.restoreBackspace()
            return
        elseif key == KEY_ESCAPE then
            BanManager.restoreDeactivate()
            return
        elseif key == KEY_RETURN or key == KEY_RETURN2 then
            BanManager.sendRestoreCmd()
            return
        end
    end
    -- GM 封禁面板打开时 ESC 关闭
    if BanManager.isGMPanelOpen() then
        local key = eventData["Key"]:GetInt()
        if key == KEY_ESCAPE then
            BanManager.closeGMPanel()
            return
        end
    end
    Input.handleKeyDown(eventType, eventData)
end

function HandleTextInput(eventType, eventData)
    local _dbgCh = eventData["Text"]:GetString()
    local _dbgRci = GS.redeemCodeInput and GS.redeemCodeInput.active
    local _dbgPni = GS.petNameInput and GS.petNameInput.active
    local _dbgNi  = GS.eventNameInput and GS.eventNameInput.active
    print("[TextInput] ch='" .. tostring(_dbgCh) .. "' rci=" .. tostring(_dbgRci) .. " pni=" .. tostring(_dbgPni) .. " ni=" .. tostring(_dbgNi) .. (_dbgNi and (" imeC=" .. tostring(GS.eventNameInput.imeComposing)) or ""))

    -- GM 封禁面板输入模式：ID模式接受数字，昵称模式接受任意字符
    if BanManager.isInputActive() then
        local ch = eventData["Text"]:GetString()
        if ch and #ch > 0 then
            BanManager.appendInputChar(ch)
        end
        return
    end
    -- GM 存档修复 Tab 用户ID输入
    if BanManager.restoreIsUserIdActive() then
        local ch = eventData["Text"]:GetString()
        if ch and #ch > 0 then
            BanManager.restoreAppendChar(ch)
        end
        return
    end

    -- 改名输入模式：接收 SDL 文本输入（UTF-8 字符）
    local ri = GS.renameInput
    if ri and ri.active then
        local ch = eventData["Text"]:GetString()
        if ch and #ch > 0 then
            local isMultiByte = #ch > 1
            if not ri.imeComposing or isMultiByte then
                if isMultiByte then
                    ri.imeComposing = false
                end
                local current = ri.text or ""
                local currentLen = utf8.len(current) or 0
                local chLen = utf8.len(ch) or 0
                if currentLen + chLen <= 12 then
                    ri.text = current .. ch
                end
            end
        end
        return
    end

    -- 兑换码输入模式：接收 SDL 文本输入
    local rci = GS.redeemCodeInput
    if rci and rci.active then
        if rci.imeComposing then return end
        local ch = eventData["Text"]:GetString()
        if ch and #ch > 0 then
            local current = rci.text or ""
            -- 限制最大 30 个字符
            local currentLen = utf8.len(current) or 0
            local chLen = utf8.len(ch) or 0
            if currentLen + chLen <= 30 then
                rci.text = current .. ch
            end
        end
        return
    end

    -- 爱称输入模式：接收 SDL 文本输入（UTF-8 字符）
    -- 加权长度：中文字符占2，英文/数字占1，上限12
    local pni = GS.petNameInput
    if pni and pni.active then
        -- IME 组合期间：抑制单个拼音字母的 TextInput 事件
        if pni.imeComposing then
            return
        end
        local ch = eventData["Text"]:GetString()
        if ch and #ch > 0 then
            local current = pni.text or ""
            local wLen = GS._petNameWeightedLen(current .. ch)
            if wLen <= 12 then
                pni.text = current .. ch
            end
        end
        return
    end

    -- 名字输入模式：接收 SDL 文本输入（UTF-8 字符）
    local ni = GS.eventNameInput
    if ni and ni.active then
        local ch = eventData["Text"]:GetString()
        if ch and #ch > 0 then
            local isMultiByte = #ch > 1  -- 中文/日文等多字节字符
            -- iOS 上 TextInput 可能在 TextEditing("") 之前触发，导致 imeComposing 误判
            -- 多字节字符（中文等）：强制接受，清除 IME 状态
            -- 单字节 ASCII：仅在非组合状态时接受（避免桌面端拼音字母插入）
            if not ni.imeComposing or isMultiByte then
                if isMultiByte then
                    ni.imeComposing = false  -- 字符已提交，清除组合状态
                end
                local current = ni.text or ""
                local currentLen = utf8.len(current) or 0
                local chLen = utf8.len(ch) or 0
                if currentLen + chLen <= 12 then
                    ni.text = current .. ch
                    print("[TextInput] name+='" .. ch .. "' now='" .. ni.text .. "'")
                end
            else
                print("[TextInput] name skip imeComposing, ch='" .. ch .. "'")
            end
        end
    end
end

--- IME 组合事件：跟踪中文输入法的拼音组合状态
function HandleTextEditing(eventType, eventData)
    local composition = eventData["Composition"]:GetString()
    local composing = composition and #composition > 0

    local ri = GS.renameInput
    if ri and ri.active then
        ri.imeComposing = composing
        ri.imeComposition = composing and composition or nil
        return
    end

    local rci = GS.redeemCodeInput
    if rci and rci.active then
        rci.imeComposing = composing
        rci.imeComposition = composing and composition or nil
        return
    end

    local pni = GS.petNameInput
    if pni and pni.active then
        pni.imeComposing = composing
        pni.imeComposition = composing and composition or nil
        return
    end

    local ni = GS.eventNameInput
    if ni and ni.active then
        ni.imeComposing = composing
        ni.imeComposition = composing and composition or nil
        return
    end
end

-- ====================================================================
-- 更新逻辑
-- ====================================================================
local _bulletinDayCheckTimer = 0

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    GS.dt = dt

    -- 在线跨天检测：每30秒检查一次，日期变化时立刻刷新每日委托
    if GS.gameState == GS.STATE_PLAYER or GS.gameState == GS.STATE_SELECT
       or GS.gameState == GS.STATE_ENEMY or GS.gameState == GS.STATE_COMPANION then
        _bulletinDayCheckTimer = _bulletinDayCheckTimer + dt
        if _bulletinDayCheckTimer >= 30 then
            _bulletinDayCheckTimer = 0
            local BulletinBoard = require("BulletinBoard")
            if BulletinBoard.needsRefresh() then
                BulletinBoard.refresh()
                print("[布告栏] 检测到跨天，已自动刷新每日委托")
            end
        end
    end

    -- 更新在线监测（心跳 + 在线时长上报）
    OnlineMonitor.update(dt)

    -- 实时封禁系统轮询
    BanManager.update(dt)
    SignInSystem.update(dt)
    SignInSystem.updateAdminTime(dt)
    -- 多端会话锁心跳检测
    SessionLock.update(dt)

    -- 更新天气效果（各效果内部已自动判断室内跳过）
    RainEffect.update(dt)
    WindEffect.update(dt)
    ScorchEffect.update(dt)

    -- 更新印章盖章动画
    BoardOverlay.updateStampAnim(dt)

    -- 更新视频播放器 & 过渡动画
    BoardOverlay.updateVideo(dt)

    -- 封禁提示弹窗倒计时
    if GS.charSelectBanMsg then
        GS.charSelectBanMsg.timer = GS.charSelectBanMsg.timer - dt
        if GS.charSelectBanMsg.timer <= 0 then
            GS.charSelectBanMsg = nil
        end
    end

    -- 虚拟广告倒计时（兑换码 shenyuanjiaguang）
    if GS.abyssFakeAdTimer then
        GS.abyssFakeAdTimer = GS.abyssFakeAdTimer - dt
        if GS.abyssFakeAdTimer <= 0 then
            GS.abyssFakeAdTimer = nil
            local cb = GS.abyssFakeAdCallback
            GS.abyssFakeAdCallback = nil
            if cb then cb() end
        end
    end

    -- 更新鼠标悬停位置（设计坐标）
    local mp = input.mousePosition
    GS.hoverX = mp.x / GS.dpr / GS.S
    GS.hoverY = mp.y / GS.dpr / GS.S
    GS.leftClickThisFrame = input:GetMouseButtonPress(MOUSEB_LEFT)

    -- 息屏挂机：持续跟踪滑动位置
    if GS.screenOffMode and GS._screenOffSwipeStartY then
        GS._screenOffSwipeCurrentY = mp.y / GS.dpr / GS.S
    end

    -- 每帧清除技能文本防重复标记
    Combat._lastSkillTextId = nil

    -- Tab 切换滑动动画计时器
    if GS.tabAnimTimer > 0 then
        GS.tabAnimTimer = GS.tabAnimTimer - dt
        if GS.tabAnimTimer <= 0 then
            GS.tabAnimTimer = 0
            GS.tabAnimFrom = 0
        end
    end

    -- 音量滑块拖拽
    Input.updateSliderDrag()

    -- 同步背景音乐音量 & 关卡BGM切换
    if bgmSource then
        bgmSource.gain = 0.4 * GS.masterVolume
        -- 根据当前关卡/区域决定BGM
        local stage = GS.currentStage
        local area = GS.currentAreaName
        local wantKey = "default"
        -- 主界面/角色选择/创建角色：播放主题曲
        if GS.gameState == GS.STATE_MENU
            or GS.gameState == GS.STATE_CHAR_SELECT
            or GS.gameState == GS.STATE_CHAR_CREATE then
            wantKey = "menu"
        -- 事件期间BGM静音（苏醒事件到达公会前）
        elseif GS.bgmMuted then
            wantKey = "silent"
        -- 艾莉雅子场景：使用垂雾森林BGM
        elseif BoardOverlay.subScene and BoardOverlay.subScene.id == "forest_elf" then
            wantKey = "forest"
        -- 区域名优先（清水镇/家 不受 currentStage 残留值影响）
        elseif area == "清水镇" or area == "家" or area == "酒馆"
            or stage == GS.STAGE_TRAINING then
            wantKey = "town"
        elseif stage == GS.STAGE_SKELETON
            or stage == GS.STAGE_MUMMY then
            wantKey = "undead"
        elseif area == "慈爱平原" then
            wantKey = "menu"
        elseif area == "垂雾森林" then
            wantKey = "forest"
        elseif area == "灰海" then
            wantKey = "sea"
        elseif area == "灰山" then
            wantKey = "mountain"
        elseif area == "升月堡" then
            wantKey = "fort"
        elseif area == "巴洛庄园"
            or stage == GS.STAGE_VAMPIRE_YOUTH
            or stage == GS.STAGE_GHOST
            or stage == GS.STAGE_FURNITURE
            or stage == GS.STAGE_DOLLS
            or stage == GS.STAGE_VAMPIRES
            or stage == GS.STAGE_GATHER_MANOR_LV1
            or stage == GS.STAGE_GATHER_MANOR_LV2
            or stage == GS.STAGE_GATHER_MANOR_LV3
            or stage == GS.STAGE_GATHER_MANOR_LV4 then
            wantKey = "manor"
        end
        if wantKey ~= currentBgmKey then
            if wantKey == "silent" then
                currentBgmKey = "silent"
                bgmSource:Stop()
            elseif bgmTracks[wantKey] then
                currentBgmKey = wantKey
                bgmSource:Play(bgmTracks[wantKey])
            end
        end
    end

    -- 经验条动画
    if GS.player and GS.player.exp ~= nil then
        local targetExp = GS.player.exp
        local targetLevel = GS.player.level or 1
        if GS.displayExpLevel ~= targetLevel then
            GS.displayExpLevel = targetLevel
            GS.displayExp = 0
        end
        if math.abs(GS.displayExp - targetExp) > 0.5 then
            local speed = math.max(15, math.abs(targetExp - GS.displayExp) * 3)
            if GS.displayExp < targetExp then
                GS.displayExp = math.min(targetExp, GS.displayExp + speed * dt)
            else
                GS.displayExp = math.max(targetExp, GS.displayExp - speed * dt)
            end
        else
            GS.displayExp = targetExp
        end
    end

    -- HP/MP 条动画
    if GS.player and GS.player.hp then
        local targetHp = GS.player.hp
        if math.abs(GS.displayHp - targetHp) > 0.5 then
            local speed = math.max(20, math.abs(targetHp - GS.displayHp) * 4)
            if GS.displayHp < targetHp then
                GS.displayHp = math.min(targetHp, GS.displayHp + speed * dt)
            else
                GS.displayHp = math.max(targetHp, GS.displayHp - speed * dt)
            end
        else
            GS.displayHp = targetHp
        end

        local targetMp = GS.player.mp or 0
        if math.abs(GS.displayMp - targetMp) > 0.5 then
            local speed = math.max(15, math.abs(targetMp - GS.displayMp) * 3)
            if GS.displayMp < targetMp then
                GS.displayMp = math.min(targetMp, GS.displayMp + speed * dt)
            else
                GS.displayMp = math.max(targetMp, GS.displayMp - speed * dt)
            end
        else
            GS.displayMp = targetMp
        end
    end

    -- 云存档状态提示倒计时
    if GS.cloudSaveTimer > 0 then
        GS.cloudSaveTimer = GS.cloudSaveTimer - dt
        if GS.cloudSaveTimer <= 0 then
            GS.cloudSaveTimer = 0
            GS.cloudSaveStatus = ""
        end
    end

    -- 角色删除冷却倒计时
    if GS.charDeleteStep == 2 and GS.charDeleteTimer > 0 then
        GS.charDeleteTimer = GS.charDeleteTimer - dt
        if GS.charDeleteTimer < 0 then GS.charDeleteTimer = 0 end
    end

    -- 强化结果消息倒计时（pending 状态不递减，等回调覆盖）
    if GS.enhanceResult and GS.enhanceResult.timer and not GS.enhanceResult.pending then
        GS.enhanceResult.timer = GS.enhanceResult.timer - dt
        if GS.enhanceResult.timer <= 0 then
            GS.enhanceResult = nil
        end
    end

    -- 精炼结果消息倒计时（pending 状态不递减）
    if GS.refineResult and GS.refineResult.timer and not GS.refineResult.pending then
        GS.refineResult.timer = GS.refineResult.timer - dt
        if GS.refineResult.timer <= 0 then
            GS.refineResult = nil
        end
    end

    -- 修复结果消息倒计时
    if GS.repairResult and GS.repairResult.timer then
        GS.repairResult.timer = GS.repairResult.timer - dt
        if GS.repairResult.timer <= 0 then
            GS.repairResult = nil
        end
    end

    -- 锻造结果消息倒计时
    if GS.forgeResult and GS.forgeResult.timer then
        GS.forgeResult.timer = GS.forgeResult.timer - dt
        if GS.forgeResult.timer <= 0 then
            GS.forgeResult = nil
        end
    end

    -- 炼金结果消息倒计时
    if GS.alchemyResult and GS.alchemyResult.timer then
        GS.alchemyResult.timer = GS.alchemyResult.timer - dt
        if GS.alchemyResult.timer <= 0 then
            GS.alchemyResult = nil
        end
    end

    -- 烹饪结果消息倒计时
    if GS.cookingResult and GS.cookingResult.timer then
        GS.cookingResult.timer = GS.cookingResult.timer - dt
        if GS.cookingResult.timer <= 0 then
            GS.cookingResult = nil
        end
    end

    -- 镶嵌结果消息倒计时
    if GS.socketResult and GS.socketResult.timer then
        GS.socketResult.timer = GS.socketResult.timer - dt
        if GS.socketResult.timer <= 0 then
            GS.socketResult = nil
        end
    end

    -- 委托加工-强化结果消息倒计时（pending 状态不递减）
    if GS.craftEnhanceResult and GS.craftEnhanceResult.timer and not GS.craftEnhanceResult.pending then
        GS.craftEnhanceResult.timer = GS.craftEnhanceResult.timer - dt
        if GS.craftEnhanceResult.timer <= 0 then
            GS.craftEnhanceResult = nil
        end
    end

    -- 委托加工-精炼结果消息倒计时（pending 状态不递减）
    if GS.craftRefineResult and GS.craftRefineResult.timer and not GS.craftRefineResult.pending then
        GS.craftRefineResult.timer = GS.craftRefineResult.timer - dt
        if GS.craftRefineResult.timer <= 0 then
            GS.craftRefineResult = nil
        end
    end

    -- 委托加工-修复结果消息倒计时
    if GS.craftRepairResult and GS.craftRepairResult.timer then
        GS.craftRepairResult.timer = GS.craftRepairResult.timer - dt
        if GS.craftRepairResult.timer <= 0 then
            GS.craftRepairResult = nil
        end
    end

    -- 附魔结果消息倒计时（pending 状态不递减）
    if GS.enchantResult and GS.enchantResult.timer and not GS.enchantResult.pending then
        GS.enchantResult.timer = GS.enchantResult.timer - dt
        if GS.enchantResult.timer <= 0 then
            GS.enchantResult = nil
        end
    end

    -- 天气/时间变更计时
    -- 剧情事件/场景切换期间：冻结时间
    -- 战斗中（野外）：由回合推进，重置实时计时器
    -- 城镇/建筑内/家/野外探索：每5秒+1分钟实时流逝
    -- 菜单/选角/游戏结束：冻结时间
    if not EventManager.isActive() and not GS.sceneTransition then
        local inCombatState = (GS.gameState == GS.STATE_PLAYER or GS.gameState == GS.STATE_SELECT
            or GS.gameState == GS.STATE_ENEMY)
        local inSafeZone = BoardOverlay.isActive() or GS.homeMode
        -- 采集区/深渊区副本无怪物时不算战斗状态，改走实时时间流逝
        if inCombatState then
            local curStageTime = GS.STAGE_DEFS[GS.currentStage]
            local isNoRespawnStage = curStageTime and curStageTime.noRespawn
            local isDungeonWaiting = GS.isDungeon and GS.arenaWaitForExit
            if isNoRespawnStage or isDungeonWaiting then
                local hasEnemyTime = false
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 then hasEnemyTime = true; break end
                end
                if not hasEnemyTime then inCombatState = false end
            end
        end
        if inCombatState and not inSafeZone then
            -- 战斗中：由 Combat.startPlayerTurn 按回合推进，重置实时计时器
            GS.weatherRealTimer = 0
        elseif GS.gameState ~= GS.STATE_GAMEOVER
           and GS.gameState ~= GS.STATE_CHAR_SELECT
           and GS.gameState ~= GS.STATE_CHAR_CREATE
           and GS.gameState ~= GS.STATE_MENU then
            -- 床上加速时间流逝：前3秒+1/秒，3~9秒+10/秒，9秒后+30/秒
            local onBed = GS.isPlayerOnBed()
            if GS.streetSleepActive then
                -- 街头睡觉：每秒推进1小时，到早上7点自动停止
                GS.streetSleepTimer = GS.streetSleepTimer + dt
                while GS.streetSleepTimer >= 1.0 do
                    GS.streetSleepTimer = GS.streetSleepTimer - 1.0
                    GS.tickWeatherTime(60)
                end
                -- 检查是否已到达早上7点（7:00~7:29视为到达）
                local curHour = math.floor(((GS.weatherTime - 1) % 1440) / 60)
                if curHour >= 7 and curHour < 18 then
                    GS.streetSleepActive = false
                    GS.streetSleepTimer = 0
                    print("=== 清晨到了，从街头醒来 ===")
                end
            elseif onBed and not GS.homePartnerTalkActive and not GS.giftMode then
                GS.bedTimeAccum = (GS.bedTimeAccum or 0) + dt
                GS.weatherRealTimer = GS.weatherRealTimer + dt
                local t = GS.bedTimeAccum
                local tickAmount = (t <= 3.0) and 1 or (t <= 9.0) and 10 or 30
                while GS.weatherRealTimer >= 1.0 do
                    GS.weatherRealTimer = GS.weatherRealTimer - 1.0
                    GS.tickWeatherTime(tickAmount)
                end
            else
                GS.bedTimeAccum = 0
                -- 城镇/建筑/家/野外探索：实时计时（每5秒+1分钟）
                GS.weatherRealTimer = GS.weatherRealTimer + dt
                while GS.weatherRealTimer >= 5.0 do
                    GS.weatherRealTimer = GS.weatherRealTimer - 5.0
                    GS.tickWeatherTime(1)
                end
            end
        end
    end

    -- [修复] 处理因角色切换保存未完成而延迟的槽位加载
    GS.tickPendingLoadSlot(dt)

    -- 自动存档检测
    GS.tickAutoSave(dt)

    -- 定时特效统一倒计时
    local function tickTimedEffects(array)
        for i = #array, 1, -1 do
            local e = array[i]
            if not e.pendingHit then
                e.timer = e.timer + dt
            end
            if e.timer >= e.duration then
                table.remove(array, i)
            end
        end
    end

    -- 弹道命中检测：攻击特效到达 hitRatio 时解锁对应 projectileId 的伤害文字
    for _, e in ipairs(GS.attackEffects) do
        if e.hitRatio and not e.hitFired then
            local t = e.timer / e.duration
            if t >= e.hitRatio then
                e.hitFired = true
                local pid = e.projectileId
                for _, d in ipairs(GS.damageTexts) do
                    if d.pendingHit and d.projectileId == pid then
                        d.pendingHit = false
                        d.timer = 0  -- 从命中瞬间开始计时
                    end
                end
                -- 解锁对应弹道ID的延迟回蓝
                for _, mr in ipairs(GS.pendingMpRestores) do
                    if mr.pendingHit and mr.projectileId == pid then
                        mr.pendingHit = false
                    end
                end
                -- 解锁对应弹道ID的死亡特效
                for _, de in ipairs(GS.deathEffects) do
                    if de.pendingHit and de.projectileId == pid then de.pendingHit = false end
                end
                -- 解锁对应弹道ID的爆炸特效（爆炸信）
                for _, re in ipairs(GS.rangedExplosionEffects) do
                    if re.pendingHit and re.projectileId == pid then
                        re.pendingHit = false
                        re.timer = 0
                    end
                end
                -- 弹道命中时触发暴击震动
                if GS._pendingCritShake then
                    GS._pendingCritShake = nil
                    GS.setScreenShake(0.15, 2, 0)
                end
            end
        end
    end

    -- 落雷术命中检测：雷电劈到地面（t >= 0.28）时解锁对应弹道ID的伤害文字
    for _, e in ipairs(GS.thunderStrikeEffects) do
        if not e.hitFired then
            local t = e.timer / e.duration
            if t >= 0.28 then
                e.hitFired = true
                local pid = e.projectileId
                for _, d in ipairs(GS.damageTexts) do
                    if d.pendingHit and d.projectileId == pid then
                        d.pendingHit = false
                        d.timer = 0
                    end
                end
                -- 解锁对应弹道ID的延迟回蓝
                for _, mr in ipairs(GS.pendingMpRestores) do
                    if mr.pendingHit and mr.projectileId == pid then
                        mr.pendingHit = false
                    end
                end
                -- 解锁对应弹道ID的死亡特效
                for _, de in ipairs(GS.deathEffects) do
                    if de.pendingHit and de.projectileId == pid then de.pendingHit = false end
                end
                -- 解锁对应弹道ID的爆炸特效（爆炸信）
                for _, re in ipairs(GS.rangedExplosionEffects) do
                    if re.pendingHit and re.projectileId == pid then
                        re.pendingHit = false
                        re.timer = 0
                    end
                end
                -- 弹道命中时触发暴击震动
                if GS._pendingCritShake then
                    GS._pendingCritShake = nil
                    GS.setScreenShake(0.15, 2, 0)
                end
            end
        end
    end

    -- 剑气弹道命中检测：delay 耗尽后 timer 推进，到达 hitRatio 时解锁伤害
    for _, e in ipairs(GS.swordQiEffects) do
        if e.hitRatio and not e.hitFired and (not e.delay or e.delay <= 0) then
            local t = e.timer / e.duration
            if t >= e.hitRatio then
                e.hitFired = true
                local pid = e.projectileId
                for _, d in ipairs(GS.damageTexts) do
                    if d.pendingHit and d.projectileId == pid then
                        d.pendingHit = false
                        d.timer = 0
                    end
                end
                for _, de in ipairs(GS.deathEffects) do
                    if de.pendingHit and de.projectileId == pid then de.pendingHit = false end
                end
                if GS._pendingCritShake then
                    GS._pendingCritShake = nil
                    GS.setScreenShake(0.15, 2, 0)
                end
            end
        end
    end

    -- 安全网：如果有 pendingHit 的伤害文字但已经没有任何未触发的弹道特效，强制解锁全部
    local hasUntriggeredProjectile = false
    for _, e in ipairs(GS.attackEffects) do
        if e.hitRatio and not e.hitFired then
            hasUntriggeredProjectile = true
            break
        end
    end
    if not hasUntriggeredProjectile then
        -- 也检查是否有未触发的雷击特效
        for _, e in ipairs(GS.thunderStrikeEffects) do
            if not e.hitFired then
                hasUntriggeredProjectile = true
                break
            end
        end
    end
    if not hasUntriggeredProjectile then
        -- 也检查是否有未触发的剑气特效
        for _, e in ipairs(GS.swordQiEffects) do
            if not e.hitFired then
                hasUntriggeredProjectile = true
                break
            end
        end
    end
    if not hasUntriggeredProjectile then
        for _, d in ipairs(GS.damageTexts) do
            if d.pendingHit then
                d.pendingHit = false
                d.timer = 0
            end
        end
        -- 安全网：解锁延迟回蓝
        for _, mr in ipairs(GS.pendingMpRestores) do
            if mr.pendingHit then mr.pendingHit = false end
        end
        -- 安全网：解锁死亡特效
        for _, de in ipairs(GS.deathEffects) do
            if de.pendingHit then de.pendingHit = false end
        end
        -- 安全网：解锁爆炸特效（爆炸信）
        for _, re in ipairs(GS.rangedExplosionEffects) do
            if re.pendingHit then
                re.pendingHit = false
                re.timer = 0
            end
        end
        -- 安全网：同步清理暴击震动
        if GS._pendingCritShake then
            GS._pendingCritShake = nil
            GS.setScreenShake(0.15, 2, 0)
        end
    end

    -- 场景切换过渡中：立即清空所有伤害数字和延迟回蓝，避免残留
    if GS.sceneTransition and #GS.damageTexts > 0 then
        GS.flushPendingMpRestores()
        GS.damageTexts = {}
    end

    -- damageTexts 单独处理：delay 期间冻结 timer，delay 结束后才开始计时
    for i = #GS.damageTexts, 1, -1 do
        local d = GS.damageTexts[i]
        if d.pendingHit then
            -- 弹道未命中：timer 不动
        elseif d.delay and d.delay > 0 then
            -- delay 倒计时期间：只递减 delay，不递增 timer
            d.delay = d.delay - dt
            if d.delay < 0 then d.delay = 0 end
        else
            -- delay 结束/无 delay：正常计时
            d.timer = d.timer + dt
        end
        if d.timer >= d.duration then
            table.remove(GS.damageTexts, i)
        end
    end
    -- 延迟回蓝队列：与伤害数字同步，delay 结束且非 pendingHit 时立即生效并移除
    for i = #GS.pendingMpRestores, 1, -1 do
        local mr = GS.pendingMpRestores[i]
        if mr.pendingHit then
            -- 弹道未命中：等待
        elseif mr.delay and mr.delay > 0 then
            mr.delay = mr.delay - dt
            if mr.delay < 0 then mr.delay = 0 end
        else
            -- 生效：回复 MP
            local t = mr.target
            if t and t.mp and t.maxMp then
                t.mp = math.min(t.mp + mr.amount, t.maxMp)
            end
            table.remove(GS.pendingMpRestores, i)
        end
    end
    -- 剑气特效：支持 delay 倒计时后再推进 timer
    for i = #GS.swordQiEffects, 1, -1 do
        local e = GS.swordQiEffects[i]
        if e.delay and e.delay > 0 then
            e.delay = e.delay - dt
            if e.delay < 0 then e.delay = 0 end
        else
            e.timer = e.timer + dt
            if e.timer >= e.duration then
                table.remove(GS.swordQiEffects, i)
            end
        end
    end
    tickTimedEffects(GS.attackEffects)
    tickTimedEffects(GS.strikeEffects)
    tickTimedEffects(GS.whirlwindEffects)
    tickTimedEffects(GS.iceRingEffects)
    tickTimedEffects(GS.fireballEffects)
    tickTimedEffects(GS.meteorEffects)
    tickTimedEffects(GS.lightningChainEffects)
    tickTimedEffects(GS.thunderStrikeEffects)
    tickTimedEffects(GS.blizzardIceEffects)
    tickTimedEffects(GS.burnEffects)
    tickTimedEffects(GS.thunderCloudStrikeEffects)
    tickTimedEffects(GS.healEffects)
    tickTimedEffects(GS.divineGraceEffects)
    tickTimedEffects(GS.holyTreeWaveEffects)
    tickTimedEffects(GS.blessEffects)
    tickTimedEffects(GS.sandBlindEffects)
    tickTimedEffects(GS.tauntEffects)
    tickTimedEffects(GS.cleaveEffects)
    tickTimedEffects(GS.meleeSplashEffects)
    tickTimedEffects(GS.holyAoeEffects)
    tickTimedEffects(GS.strikeAoeEffects)
    -- rangedExplosionEffects 单独处理：pendingHit 期间冻结 timer
    for i = #GS.rangedExplosionEffects, 1, -1 do
        local re = GS.rangedExplosionEffects[i]
        if not re.pendingHit then
            re.timer = re.timer + dt
            if re.timer >= re.duration then
                table.remove(GS.rangedExplosionEffects, i)
            end
        end
    end
    tickTimedEffects(GS.magicShieldEffects)
    tickTimedEffects(GS.iceWallCreateEffects)
    tickTimedEffects(GS.blinkEffects)
    tickTimedEffects(GS.radianceWaveEffects)
    tickTimedEffects(GS.apocalypseAoeEffects)
    -- 延迟燃烧地面：弹道命中后才出现
    for i = #GS.pendingBurningGrounds, 1, -1 do
        local p = GS.pendingBurningGrounds[i]
        p.delay = p.delay - dt
        if p.delay <= 0 then
            for _, item in ipairs(p.items) do
                local found = false
                for _, bg in ipairs(GS.burningGrounds) do
                    if bg.x == item.x and bg.y == item.y then
                        bg.turnsLeft = item.turnsLeft
                        bg.burnPct = item.burnPct
                        bg.casterMAtk = item.casterMAtk
                        found = true
                        break
                    end
                end
                if not found then
                    GS.burningGrounds[#GS.burningGrounds + 1] = item
                end
            end
            table.remove(GS.pendingBurningGrounds, i)
        end
    end
    -- 深渊弹射分帧处理（每帧执行一跳）
    Combat.processPendingBounces()
    -- deathEffects 单独处理：pendingHit/delay 期间冻结 timer，等伤害文字显示后再播放死亡动画
    for i = #GS.deathEffects, 1, -1 do
        local e = GS.deathEffects[i]
        if e.pendingHit then
            -- 弹道未命中：timer 不动
        elseif e.delay and e.delay > 0 then
            e.delay = e.delay - dt
            if e.delay < 0 then e.delay = 0 end
        else
            e.timer = e.timer + dt
        end
        if e.timer >= e.duration then
            table.remove(GS.deathEffects, i)
        end
    end
    tickTimedEffects(GS.phantomDissolveEffects)
    tickTimedEffects(GS.phantomAttackEffects)

    -- 闪烁延迟移动：等特效飞到终点后再更新角色位置
    if GS.pendingBlinkMove then
        local pb = GS.pendingBlinkMove
        pb.timer = pb.timer + dt
        if pb.timer >= pb.delay then
            GS.updateFacing(pb.unit, pb.unit.x, pb.unit.y, pb.tx, pb.ty)
            pb.unit.x = pb.tx
            pb.unit.y = pb.ty
            pb.unit.blinkHidden = nil
            GS.pendingBlinkMove = nil
        end
    end

    -- 隐匿烟雾特效计时
    if GS.stealthSmokeEffect then
        GS.stealthSmokeEffect.timer = GS.stealthSmokeEffect.timer + dt
        if GS.stealthSmokeEffect.timer >= GS.stealthSmokeEffect.duration then
            GS.stealthSmokeEffect = nil
        end
    end

    -- 延迟结束玩家回合：等攻击特效播完+伤害数字显示后再真正执行
    if GS.pendingEndPlayerTurn then
        GS._pendingEndTurnTimer = (GS._pendingEndTurnTimer or 0) + dt
        Combat.endPlayerTurn()  -- 内部会再次检查，条件满足才真正执行
    end

    -- 爱称输入确认/取消处理
    do
        local pni = GS.petNameInput
        if pni and pni.confirmed then
            local txt = pni.text or ""
            if #txt > 0 and pni.npcKey then
                GS.customPetNames[pni.npcKey] = txt
            end
            GS.petNameInput = nil
            -- 停用文本输入（桌面端关闭 IME，移动端收起软键盘）
            input:SetScreenKeyboardVisible(false)
            -- 关闭伴侣对话状态
            GS.homePartnerTalkActive = false
            GS.eventInputLocked = false
            local DialogueManager = require("DialogueManager")
            DialogueManager.finish()
            GS.saveToCloud()
        elseif pni and pni.cancelled then
            -- 取消：不保存，关闭输入框和对话
            GS.petNameInput = nil
            -- 停用文本输入（桌面端关闭 IME，移动端收起软键盘）
            input:SetScreenKeyboardVisible(false)
            GS.homePartnerTalkActive = false
            GS.eventInputLocked = false
            local DialogueManager = require("DialogueManager")
            DialogueManager.finish()
        end
    end

    -- 屏幕震动计时
    if GS.screenShake then
        local s = GS.screenShake
        s.timer = s.timer + dt
        if s.timer >= s.duration + (s.delay or 0) then
            GS.screenShake = nil
        end
    end

    -- 卓越装备橙光闪烁计时
    if GS.superiorDropFlash then
        GS.superiorDropFlash.timer = GS.superiorDropFlash.timer + dt
        if GS.superiorDropFlash.timer >= GS.superiorDropFlash.duration then
            GS.superiorDropFlash = nil
        end
    end

    -- 受伤闪红计时
    if GS.player and GS.player.hurtTimer then
        GS.player.hurtTimer = GS.player.hurtTimer + dt
        if GS.player.hurtTimer >= GS.player.hurtDuration then
            GS.player.hurtTimer = nil
        end
    end
    -- 玩家浮动文本计时器（冲锋怒吼等）
    if GS.player and GS.player.floatingText then
        GS.player.floatingText.timer = GS.player.floatingText.timer + dt
        if GS.player.floatingText.timer >= GS.player.floatingText.duration then
            GS.player.floatingText = nil
        end
    end
    for _, m in ipairs(GS.monsters) do
        if m.hurtTimer then
            m.hurtTimer = m.hurtTimer + dt
            if m.hurtTimer >= m.hurtDuration then
                m.hurtTimer = nil
            end
        end
        -- 浮动文本计时器（BOSS头顶台词等）
        if m.floatingText then
            m.floatingText.timer = m.floatingText.timer + dt
            if m.floatingText.timer >= m.floatingText.duration then
                m.floatingText = nil
            end
        end
    end
    for _, c in ipairs(GS.companions) do
        if c.hurtTimer then
            c.hurtTimer = c.hurtTimer + dt
            if c.hurtTimer >= c.hurtDuration then
                c.hurtTimer = nil
            end
        end
    end

    -- 反击/复仇发光计时
    if GS.player and GS.player.counterGlow then
        local cg = GS.player.counterGlow
        cg.timer = cg.timer + dt
        if cg.timer >= cg.duration then
            GS.player.counterGlow = nil
        end
    end

    -- 怪物撞击动画
    for _, m in ipairs(GS.monsters) do
        if m.slamAnim then
            local prev = m.slamAnim.timer
            m.slamAnim.timer = m.slamAnim.timer + dt
            local half = m.slamAnim.duration * 0.5
            if prev < half and m.slamAnim.timer >= half then
                Combat.playSlimeHitSound()
            end
            if m.slamAnim.timer >= m.slamAnim.duration then
                m.slamAnim = nil
            end
        end
    end
    -- 友军撞击动画
    for _, c in ipairs(GS.companions) do
        if c.slamAnim then
            c.slamAnim.timer = c.slamAnim.timer + dt
            if c.slamAnim.timer >= c.slamAnim.duration then
                c.slamAnim = nil
            end
        end
    end

    -- 跳跃动画（事件中哥布林受惊跳跃）
    for _, m in ipairs(GS.monsters) do
        if m.jumpAnim then
            m.jumpAnim.timer = m.jumpAnim.timer + dt
            if m.jumpAnim.timer >= m.jumpAnim.duration then
                m.jumpAnim = nil
            end
        end
    end

    -- 移动动画
    if GS.player and GS.player.moveAnim then
        GS.player.moveAnim.timer = GS.player.moveAnim.timer + dt
        if GS.player.moveAnim.timer >= GS.player.moveAnim.duration then
            GS.player.moveAnim = nil
            if GS.homeMode then
                -- 家模式：走到门格子 → 切换到清水镇
                if GS.homeDoorPending then
                    GS.homeDoorPending = false
                    GS.homePendingTarget = nil
                    GS.homeChestPending = false
                    GS.startSceneTransition(function()
                        if GS.warehouseMode then GS.exitWarehouseMode() end
                        if GS.lostItemsMode then GS.exitLostItemsMode() end
                        GS.homeMode = false
                        GS.trainingMode = false
                        GS.gameState = GS.STATE_PLAYER
                        GS.turnPhase = GS.PHASE_MOVE
                        GS.currentBattleBg = "image/bg_grass.png"
                        GS.currentAreaName = "清水镇"
                        GS.currentStageName = "清水镇"
                        BoardOverlay.show("town", "clearwater", "清水镇")
                        print("=== 从家出门 → 清水镇 ===")
                    end)
                elseif GS.homePendingTarget then
                    -- 有待定目标 → 继续移动
                    local tx, ty = GS.homePendingTarget[1], GS.homePendingTarget[2]
                    GS.homePendingTarget = nil
                    local ox, oy = GS.player.x, GS.player.y
                    local startedMove = false
                    if tx ~= ox or ty ~= oy then
                        local path = GS.homePathFind(ox, oy, tx, ty)
                        if path and #path >= 2 then
                            GS.player.x = tx
                            GS.player.y = ty
                            Combat.startMoveAnim(GS.player, ox, oy, path)
                            startedMove = true
                            local doorP = GS.getHomeRoomParams(GS.homeType)
                            if ty == doorP.doorY and (tx == doorP.doorX1 or tx == doorP.doorX2) then
                                GS.homeDoorPending = true
                            end
                        end
                    end
                    -- 没有启动新移动（已在目标或无路径）→ 检查待交互家具
                    if not startedMove and GS.homeChestPending and GS.homePendingFurniture then
                        GS.homeChestPending = false
                        local furn = GS.homePendingFurniture
                        GS.homePendingFurniture = nil
                        -- 共享仓库未解锁时拦截
                        if furn.interact == "shared_storage" and not GS.sharedStorageUnlocked then
                            -- 未解锁，静默忽略
                        else
                            local fcx = furn.x + (furn.w - 1) * 0.5
                            local fcy = furn.y + (furn.h - 1) * 0.5
                            GS.updateFacing(GS.player, GS.player.x, GS.player.y, fcx, fcy)
                            GS.startFurnitureInteract(fcx, fcy, furn.name, function()
                                if furn.interact == "warehouse" then
                                    GS.enterWarehouseMode(furn.warehouseId)
                                elseif furn.interact == "alchemy" then
                                    GS.homeAlchemyMode = true
                                    GS.alchemyMode = true
                                    GS.alchemyResult = nil
                                    GS.alchemyScrollY = 0
                                    GS.alchemyBtnRects = {}
                                elseif furn.interact == "cooking" then
                                    GS.homeCookingMode = true
                                    GS.cookingMode = true
                                    GS.cookingResult = nil
                                    GS.cookingScrollY = 0
                                    GS.cookingBtnRects = {}
                                elseif furn.interact == "smithy" then
                                    GS.homeSmithySelectMode = true
                                    GS.homeSmithySelectRects = nil
                                elseif furn.interact == "socket" then
                                    GS.homeSocketMode = true
                                    GS.socketMode = true
                                    GS.socketResult = nil
                                    GS.socketScrollY = 0
                                elseif furn.interact == "shared_storage" then
                                    GS.enterSharedStorageMode()
                                end
                            end, nil, furn.w, furn.h)
                        end
                    end
                elseif GS.homeChestPending and GS.homePendingFurniture then
                    -- 到达家具旁 → 面向家具后启动交互进度条
                    GS.homeChestPending = false
                    local furn = GS.homePendingFurniture
                    GS.homePendingFurniture = nil
                    if furn.interact == "shared_storage" and not GS.sharedStorageUnlocked then
                        -- 未解锁，静默忽略
                    else
                        local fcx = furn.x + (furn.w - 1) * 0.5
                        local fcy = furn.y + (furn.h - 1) * 0.5
                        GS.updateFacing(GS.player, GS.player.x, GS.player.y, fcx, fcy)
                        GS.startFurnitureInteract(fcx, fcy, furn.name, function()
                            if furn.interact == "warehouse" then
                                GS.enterWarehouseMode(furn.warehouseId)
                            elseif furn.interact == "alchemy" then
                                GS.homeAlchemyMode = true
                                GS.alchemyMode = true
                                GS.alchemyResult = nil
                                GS.alchemyScrollY = 0
                                GS.alchemyBtnRects = {}
                            elseif furn.interact == "cooking" then
                                GS.homeCookingMode = true
                                GS.cookingMode = true
                                GS.cookingResult = nil
                                GS.cookingScrollY = 0
                                GS.cookingBtnRects = {}
                            elseif furn.interact == "smithy" then
                                GS.homeSmithySelectMode = true
                                GS.homeSmithySelectRects = nil
                            elseif furn.interact == "socket" then
                                GS.homeSocketMode = true
                                GS.socketMode = true
                                GS.socketResult = nil
                                GS.socketScrollY = 0
                            elseif furn.interact == "shared_storage" then
                                GS.enterSharedStorageMode()
                            end
                        end, nil, furn.w, furn.h)
                    end
                elseif GS._homePartnerTalkPending and GS.homeNpc then
                    -- 到达伴侣旁 → 面向伴侣后发起交谈
                    GS._homePartnerTalkPending = false
                    GS.updateFacing(GS.player, GS.player.x, GS.player.y, GS.homeNpc.x, GS.homeNpc.y)
                    Input._startHomePartnerTalk(GS.homeNpc.npcKey)
                end
            elseif GS.arenaWaitForExit then
                -- 竞技场自由移动完成处理
                GS.player.acted = false
                if GS.arenaPendingTarget then
                    -- 有待定目标 → 继续移动
                    local tx, ty = GS.arenaPendingTarget[1], GS.arenaPendingTarget[2]
                    GS.arenaPendingTarget = nil
                    local ox, oy = GS.player.x, GS.player.y
                    local startedMove = false
                    if tx ~= ox or ty ~= oy then
                        local path = GS.arenaPathFind(ox, oy, tx, ty)
                        if path and #path >= 2 then
                            GS.player.x = tx
                            GS.player.y = ty
                            Combat.startMoveAnim(GS.player, ox, oy, path)
                            startedMove = true
                        end
                    end
                    -- 没有启动新移动（已在目标或无路径）→ 立即处理宝箱/出口
                    if not startedMove then
                        if GS.arenaChestPending and GS.arenaChests then
                            local chestIdx = GS.arenaChestPending
                            GS.arenaChestPending = nil
                            local chest = GS.arenaChests[chestIdx]
                            if chest and not chest.opened then
                                GS.updateFacing(GS.player, ox, oy, chest.x, chest.y)
                                GS.arenaChestInteract = {
                                    chestIdx = chestIdx,
                                    progress = 0, duration = 1.5, _displayProgress = 0,
                                }
                                print("[竞技场] 到达宝箱旁，开始读条开启 #" .. chestIdx)
                            end
                        elseif GS.arenaExitPending then
                            GS.arenaExitPending = false
                            local DungeonManager = require("Dungeon.DungeonManager")
                            DungeonManager.triggerArenaExit()
                            print("[竞技场] 到达出口格子，触发进入下一关")
                        end
                    end
                elseif GS.arenaChestPending and GS.arenaChests then
                    -- 到达宝箱旁 → 面向宝箱并开始读条
                    local chestIdx = GS.arenaChestPending
                    GS.arenaChestPending = nil
                    local chest = GS.arenaChests[chestIdx]
                    if chest and not chest.opened then
                        GS.updateFacing(GS.player, GS.player.x, GS.player.y, chest.x, chest.y)
                        GS.arenaChestInteract = {
                            chestIdx = chestIdx,
                            progress = 0, duration = 1.5, _displayProgress = 0,
                        }
                        print("[竞技场] 到达宝箱旁，开始读条开启 #" .. chestIdx)
                    end
                elseif GS.arenaExitPending then
                    -- 到达出口格子 → 触发进入下一关
                    GS.arenaExitPending = false
                    local DungeonManager = require("Dungeon.DungeonManager")
                    DungeonManager.triggerArenaExit()
                    print("[竞技场] 到达出口格子，触发进入下一关")
                end
            end
        end
    end

    for _, m in ipairs(GS.monsters) do
        if m.moveAnim then
            m.moveAnim.timer = m.moveAnim.timer + dt
            if m.moveAnim.timer >= m.moveAnim.duration then
                m.moveAnim = nil
            end
        end
    end
    -- 友军移动动画
    for _, c in ipairs(GS.companions) do
        if c.moveAnim then
            c.moveAnim.timer = c.moveAnim.timer + dt
            if c.moveAnim.timer >= c.moveAnim.duration then
                c.moveAnim = nil
            end
        end
    end

    -- ======== 家中伴侣位置备选点 ========
    local HOME_FALLBACKS = {
        ["10_4"] = {9, 4},   -- 晚间站位备选
        ["10_3"] = {9, 3},   -- 睡觉位置备选
        ["3_3"]  = {4, 3},   -- 清晨站位备选
        ["3_5"]  = {3, 6},   -- 晚间随机点备选
        ["9_5"]  = {10, 5},  -- 晚间随机点备选
    }
    local function homePosFallback(px, py, tx, ty)
        if px == tx and py == ty then
            local key = tx .. "_" .. ty
            local fb = HOME_FALLBACKS[key]
            if fb then return fb[1], fb[2] end
        end
        return tx, ty
    end
    -- 晚间 idle 位置等权随机（4个候选点），每次调用随机一个
    local EVENING_IDLE_SPOTS = {
        {10, 4}, {3, 3}, {3, 5}, {9, 5},
    }
    local function pickEveningIdlePos(px, py)
        local idx = math.random(1, #EVENING_IDLE_SPOTS)
        local spot = EVENING_IDLE_SPOTS[idx]
        return homePosFallback(px, py, spot[1], spot[2])
    end

    -- ======== 家中伴侣NPC更新 ========
    if GS.homeMode and GS.homeNpc then
        local hn = GS.homeNpc
        -- moveAnim 计时
        if hn.moveAnim then
            hn.moveAnim.timer = hn.moveAnim.timer + dt
            if hn.moveAnim.timer >= hn.moveAnim.duration then
                hn.moveAnim = nil
                if hn.state == "arriving" then
                    -- 到达后根据当前阶段决定状态
                    local phase = GS.getPartnerHomePhase(hn.npcKey)
                    if phase == "sleeping" then
                        hn.state = "sleeping"
                    else
                        hn.state = "idle"
                    end
                elseif hn.state == "leaving" then
                    hn.state = "fading_out"
                    hn.fadeTimer = 0
                elseif hn.state == "going_to_sleep" then
                    hn.state = "sleeping"
                elseif hn.state == "waking_up" then
                    hn.state = "idle"
                end
            end
        end
        -- 淡入动画
        if hn.state == "fading_in" then
            hn.fadeTimer = (hn.fadeTimer or 0) + dt
            hn.drawAlpha = math.min(1, hn.fadeTimer / 0.5)
            if hn.drawAlpha >= 1 then
                hn.drawAlpha = 1
                -- 淡入完成，根据阶段寻路到目标位置（检查占位）
                local phase = GS.getPartnerHomePhase(hn.npcKey)
                local targetX, targetY
                if phase == "sleeping" then
                    targetX, targetY = homePosFallback(GS.player.x, GS.player.y, 10, 3)
                elseif phase == "awake_morning" then
                    targetX, targetY = homePosFallback(GS.player.x, GS.player.y, 3, 3)
                else
                    targetX, targetY = pickEveningIdlePos(GS.player.x, GS.player.y)
                end
                local path = GS.homePathFind(hn.x, hn.y, targetX, targetY)
                if path and #path >= 2 then
                    local ox, oy = hn.x, hn.y
                    hn.x = targetX
                    hn.y = targetY
                    hn.state = "arriving"
                    Combat.startMoveAnim(hn, ox, oy, path)
                else
                    hn.x = targetX
                    hn.y = targetY
                    if phase == "sleeping" then
                        hn.state = "sleeping"
                    else
                        hn.state = "idle"
                    end
                end
            end
        -- 淡出动画
        elseif hn.state == "fading_out" then
            hn.fadeTimer = (hn.fadeTimer or 0) + dt
            hn.drawAlpha = math.max(0, 1 - hn.fadeTimer / 0.5)
            if hn.drawAlpha <= 0 then
                GS.homeNpc = nil
            end
        end

        -- 睡眠/苏醒阶段切换检测（仅在 idle 或 sleeping 且无移动动画时）
        -- 交谈期间跳过，避免把暂时设为 idle 的伴侣重新移去睡觉
        if GS.homeNpc and not GS.homeNpc.moveAnim and not GS.homePartnerTalkActive and not GS.giftMode then
            local hn2 = GS.homeNpc
            if hn2.state == "idle" or hn2.state == "sleeping" then
                local phase = GS.getPartnerHomePhase(hn2.npcKey)
                if phase == "sleeping" and hn2.state == "idle" then
                    -- 该睡觉了 → 移动到 (10,3)，检查占位
                    local sx, sy = homePosFallback(GS.player.x, GS.player.y, 10, 3)
                    local path = GS.homePathFind(hn2.x, hn2.y, sx, sy)
                    if path and #path >= 2 then
                        local ox, oy = hn2.x, hn2.y
                        hn2.x = sx
                        hn2.y = sy
                        hn2.state = "going_to_sleep"
                        Combat.startMoveAnim(hn2, ox, oy, path)
                    else
                        hn2.x = sx
                        hn2.y = sy
                        hn2.state = "sleeping"
                    end
                elseif phase ~= "sleeping" and hn2.state == "sleeping" then
                    -- 睡醒了 → 移动到 (3,3)，检查占位
                    local wx, wy = homePosFallback(GS.player.x, GS.player.y, 3, 3)
                    local path = GS.homePathFind(hn2.x, hn2.y, wx, wy)
                    if path and #path >= 2 then
                        local ox, oy = hn2.x, hn2.y
                        hn2.x = wx
                        hn2.y = wy
                        hn2.state = "waking_up"
                        Combat.startMoveAnim(hn2, ox, oy, path)
                    else
                        hn2.x = wx
                        hn2.y = wy
                        hn2.state = "idle"
                    end
                end
            end
        end
    end
    -- 伴侣NPC出现/离开时间检测
    if GS.homeMode and GS.partnerLivingTogether and GS.partnerNpcKey then
        local shouldBeHome = GS.shouldPartnerBeHome(GS.partnerNpcKey)
        if shouldBeHome and not GS.homeNpc then
            local p = GS.getHomeRoomParams(GS.homeType)
            if GS.homeNpcLastShouldState == nil then
                -- 刚进入家，伴侣已在家 → 根据阶段决定初始位置（检查占位）
                local phase = GS.getPartnerHomePhase(GS.partnerNpcKey)
                local initX, initY, initState
                if phase == "sleeping" then
                    initX, initY = homePosFallback(GS.player.x, GS.player.y, 10, 3)
                    initState = "sleeping"
                elseif phase == "awake_morning" then
                    initX, initY = homePosFallback(GS.player.x, GS.player.y, 3, 3)
                    initState = "idle"
                else
                    initX, initY = pickEveningIdlePos(GS.player.x, GS.player.y)
                    initState = "idle"
                end
                GS.homeNpc = {
                    npcKey = GS.partnerNpcKey,
                    x = initX, y = initY,
                    drawAlpha = 1,
                    state = initState,
                    facing = "down",
                }
            else
                -- 时间变化，伴侣从外面回来 → 门口淡入+走过去
                GS.homeNpc = {
                    npcKey = GS.partnerNpcKey,
                    x = p.doorX1, y = p.doorY,
                    drawAlpha = 0,
                    state = "fading_in",
                    fadeTimer = 0,
                    facing = "up",
                }
            end
        elseif not shouldBeHome and GS.homeNpc and not GS.homePartnerTalkActive and not GS.giftMode then
            local hn = GS.homeNpc
            if hn.state == "idle" or hn.state == "sleeping" then
                -- 该去上班了 → 从当前位置寻路到 (3,3) 再到门口
                -- 如果正在睡觉先去(3,3)，如果已在(3,3)直接去门口
                local p = GS.getHomeRoomParams(GS.homeType)
                local path = GS.homePathFind(hn.x, hn.y, p.doorX1, p.doorY)
                if path and #path >= 2 then
                    local ox, oy = hn.x, hn.y
                    hn.x = p.doorX1
                    hn.y = p.doorY
                    hn.state = "leaving"
                    Combat.startMoveAnim(hn, ox, oy, path)
                else
                    hn.state = "fading_out"
                    hn.fadeTimer = 0
                end
            end
        end
        GS.homeNpcLastShouldState = shouldBeHome
    elseif not GS.homeMode then
        -- 离开家模式 → 清理状态
        if GS.homeNpc then GS.homeNpc = nil end
        GS.homeNpcLastShouldState = nil
        if GS.homeHound then GS.homeHound = nil end
    end

    -- 家中猎犬显示（学习了猎犬技能时）
    if GS.homeMode and not GS.homeHound then
        if (GS.skillLevels["h_hound"] or 0) >= 1 then
            local pos = GS.HOME_HOUND_POS[GS.homeType]
            if pos then
                GS.homeHound = { x = pos.x, y = pos.y }
            end
        end
    end
    -- 家中猎犬：浮动文本计时 + 点击冷却倒计时
    if GS.homeHound then
        local hh = GS.homeHound
        if hh.floatingText then
            local ft = hh.floatingText
            ft.timer = ft.timer + dt
            if ft.timer >= ft.duration then
                hh.floatingText = nil
            end
        end
        if (hh._barkCooldown or 0) > 0 then
            hh._barkCooldown = hh._barkCooldown - dt
        end
    end

    -- 家具交互进度条更新
    if GS.furnitureInteract then
        local fi = GS.furnitureInteract
        fi.progress = fi.progress + dt / fi.duration
        if fi.progress >= 1.0 then
            fi.progress = 1.0
            local action = fi.action
            GS.furnitureInteract = nil
            if action then action() end
        end
    end

    -- 竞技场宝箱交互进度条更新
    if GS.arenaChestInteract then
        local ci = GS.arenaChestInteract
        ci.progress = ci.progress + dt / ci.duration
        if ci.progress >= 1.0 then
            ci.progress = 1.0
            local chestIdx = ci.chestIdx
            local chest = GS.arenaChests[chestIdx]
            GS.arenaChestInteract = nil
            if chest and not chest.opened then
                chest.opened = true
                local goldReward = chest.gold or 500
                GS.gold = GS.gold + goldReward
                Combat.addDamageText(chest.x, chest.y, "+" .. goldReward .. "G", {255, 215, 0})
                print("[竞技场] 宝箱 #" .. chestIdx .. " 开启，获得 " .. goldReward .. "G")
                -- 宝箱装备掉落（视同怪物掉落：附魔/精炼/宝石槽随机判定）
                if chest.drops then
                    for _, drop in ipairs(chest.drops) do
                        local ok, msg, addedItem = GS.addToInventory(drop.id, 1)
                        if ok then
                            if addedItem and drop.enchantTier ~= nil then
                                addedItem.tier = drop.enchantTier
                                if math.random() < GS.ENCHANT_CHANCE then
                                    GS.rollEnchantment(addedItem, drop.enchantTier)
                                end
                                GS.rollRefineSlots(addedItem, drop.enchantTier)
                                GS.rollGemSlots(addedItem)

                            end
                            local tpl = GS.itemTemplates[drop.id]
                            local dropName = tpl and tpl.name or drop.id
                            if addedItem and addedItem.abyssAffix then
                                dropName = dropName .. " [词缀:" .. addedItem.abyssAffix.name .. "]"
                            end
                            Combat.addDamageText(chest.x, chest.y - 0.5, "+" .. dropName, {180, 220, 255})
                            print("[竞技场] 宝箱掉落: " .. dropName)
                        else
                            local tpl = GS.itemTemplates[drop.id]
                            Combat.addDamageText(chest.x, chest.y - 0.5,
                                "背包已满! " .. (tpl and tpl.name or drop.id) .. " 丢失", {255, 80, 80})
                        end
                    end
                end
            end
            -- 读条完成：自由移动模式下不消耗回合，让玩家继续操作
            if GS.player then
                GS.player.acted = false
            end
        end
    end

    -- 火精锐史莱姆尸体：实时倒计时爆炸（自由移动模式下回合不推进，改用实时5秒计时）
    if #GS.fireCorpses > 0 and GS.arenaWaitForExit then
        for i = #GS.fireCorpses, 1, -1 do
            local corpse = GS.fireCorpses[i]
            corpse.realTimer = (corpse.realTimer or 0) + dt
            if corpse.realTimer >= 5.0 then
                -- 爆炸伤害：暴怒火史莱姆 = 等级×15，普通精锐 = 800
                local expDmg = 800
                if corpse.defId == "fire_slime_enraged" and corpse.level then
                    expDmg = corpse.level * 15
                end
                -- 5秒到达，触发爆炸
                Combat.addDamageText(corpse.x, corpse.y, "爆炸!", {255, 120, 40})
                GS.setScreenShake(0.5, 5, 0)
                -- 对周围8格+自身格造成真实伤害（伤害玩家）
                if GS.player and GS.player.hp > 0 then
                    local px, py = GS.player.x, GS.player.y
                    for dy = -1, 1 do
                        for dx = -1, 1 do
                            local tx, ty = corpse.x + dx, corpse.y + dy
                            if tx == px and ty == py then
                                GS.player.hp = GS.player.hp - expDmg
                                Combat.addDamageText(px, py, "" .. expDmg, {255, 120, 40})
                                Combat.addHurtFlash(GS.player)
                                if GS.player.hp <= 0 then GS.player.hp = 0 end
                            end
                        end
                    end
                end
                table.remove(GS.fireCorpses, i)
            end
        end
        -- 爆炸后检查玩家是否死亡
        if GS.player and GS.player.hp <= 0 then
            Combat.checkPlayerDeath()
        end
    end

    -- 副本棋盘滚动动画
    if GS.dungeonScrollAnim then
        GS.dungeonScrollAnim.timer = GS.dungeonScrollAnim.timer + dt
        if GS.dungeonScrollAnim.timer >= GS.dungeonScrollAnim.duration then
            -- 动画结束：将玩家移到目标位置
            local isScrollTransition = GS.dungeonScrollAnim.scrollModeTransition
            local scrollAnnounce = GS.dungeonScrollAnim.announce
            if GS.player then
                GS.player.x = GS.dungeonScrollAnim.targetX
                GS.player.y = GS.dungeonScrollAnim.targetY
            end
            GS.dungeonScrollAnim = nil
            -- 滚动模式过场：滚动结束后刷怪、生成猎犬，走统一 arenaTransition 对话流程
            if isScrollTransition then
                local DM = require("Dungeon.DungeonManager")
                GS.spawnHound()
                if DM.isActive() then
                    DM.spawnForPhase()
                end
                -- 创建 arenaTransition 从 dialogue 步骤开始
                local phase = DM.getPhase()
                GS.arenaTransition = {
                    step = "dialogue",
                    timer = 0,
                    isScrollTransition = true,
                    announce = scrollAnnounce,
                }
                -- 如果没有对话也没有播报，直接进入 done
                if not (phase and phase.phaseDialogue and #phase.phaseDialogue > 0)
                   and not GS.arenaTransition.announce then
                    GS.arenaTransition.step = "done"
                end
                print("=== 棋盘滚动过场结束，进入 arenaTransition 对话流程 ===")
            end
        end
    end

    -- 竞技场过场动画
    if GS.arenaTransition then
        local DungeonManager = require("Dungeon.DungeonManager")
        DungeonManager.updateArenaTransition(dt)
    end

    -- 墓碑动画
    if GS.tombstoneDropAnim then
        GS.tombstoneDropAnim.timer = GS.tombstoneDropAnim.timer + dt
        if GS.tombstoneDropAnim.timer >= GS.tombstoneDropAnim.duration then
            GS.tombstoneDropAnim = nil
        end
    end
    if GS.tombstoneAnim then
        GS.tombstoneAnim.timer = GS.tombstoneAnim.timer + dt
        if GS.tombstoneAnim.timer >= GS.tombstoneAnim.duration then
            GS.tombstoneAnim = nil
        end
    end
    if GS.reviveEffect then
        GS.reviveEffect.timer = GS.reviveEffect.timer + dt
        if GS.reviveEffect.timer >= GS.reviveEffect.duration then
            GS.reviveEffect = nil
        end
    end

    -- 采集进度（回合制，由 endPlayerTurn / processAutoCombat 推进）
    -- 不再使用实时计时器

    -- 采集结果动画计时器
    if GS.gatherResultAnim then
        GS.gatherResultAnim.timer = GS.gatherResultAnim.timer + dt
        if GS.gatherResultAnim.timer >= GS.gatherResultAnim.duration then
            GS.gatherResultAnim = nil
        end
    end

    -- 地图提示文本计时
    if GS.mapTipTimer > 0 then
        GS.mapTipTimer = GS.mapTipTimer - dt
        if GS.mapTipTimer <= 0 then
            GS.mapTipText = nil
        end
    end

    -- 场景切换过渡计时器
    local tr = GS.sceneTransition
    if tr then
        tr.timer = tr.timer + dt
        if tr.phase == "in" and tr.timer >= tr.FADE_IN then
            -- 淡入结束 → 全黑保持，执行回调
            tr.phase = "hold"
            tr.timer = 0
            if tr.callback then
                tr.callback()
                tr.callback = nil
            end
        elseif tr.phase == "hold" and tr.timer >= tr.HOLD then
            -- 保持结束 → 开始淡出
            tr.phase = "out"
            tr.timer = 0
        elseif tr.phase == "out" and tr.timer >= tr.FADE_OUT then
            -- 淡出结束 → 过渡完成
            local onComplete = tr.onComplete
            GS.sceneTransition = nil
            if onComplete then onComplete() end
        end
    end

    -- 酒馆肉搏黑屏过渡计时器（brawlCinematic）
    local bc = GS.brawlCinematic
    if bc then
        bc.timer = bc.timer + dt
        if bc.phase == "fade_in" then
            bc.alpha = math.min(255, math.floor(255 * (bc.timer / bc.FADE_IN)))
            if bc.timer >= bc.FADE_IN then
                bc.alpha = 255
                bc.phase = "dialogue"
                bc.timer = 0
                if bc.onFadeInDone then
                    bc.onFadeInDone()
                    bc.onFadeInDone = nil
                end
            end
        elseif bc.phase == "dialogue" then
            bc.alpha = 255  -- 保持全黑，等待对话结束（对话结束后由回调切到 fade_out）
        elseif bc.phase == "fade_out" then
            bc.alpha = math.max(0, math.floor(255 * (1 - bc.timer / bc.FADE_OUT)))
            if bc.timer >= bc.FADE_OUT then
                GS.brawlCinematic = nil
            end
        end
    end

    -- 非战斗实时回复：每5秒按玩家 hpRegen/mpRegen 属性回复一次
    -- 触发条件：家模式、BoardOverlay激活、采集区无怪物（与自动战斗无关）
    -- 床效果：站在床上时回复间隔缩短为1秒
    do
        local isNonCombat = false
        if BoardOverlay.isActive() then
            isNonCombat = true
        elseif GS.homeMode then
            isNonCombat = true
        else
            local curStage = GS.STAGE_DEFS[GS.currentStage]
            if curStage and curStage.noRespawn then
                local hasEnemy = false
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 then hasEnemy = true; break end
                end
                if not hasEnemy then isNonCombat = true end
            end
        end
        if isNonCombat then
            -- 判断是否在床上，在床上时回复间隔1秒，否则5秒
            local onBed = GS.isPlayerOnBed()
            local regenInterval = onBed and 1 or 5
            GS.regenTimer = (GS.regenTimer or 0) + dt
            if GS.regenTimer >= regenInterval then
                GS.regenTimer = GS.regenTimer - regenInterval
                local p = GS.player
                if p and p.hp > 0 then
                    local hpGain = math.floor(p.hpRegen or 0)
                    local mpGain = math.floor(p.mpRegen or 0)
                    if hpGain > 0 and p.hp < p.maxHp then
                        p.hp = math.min(p.maxHp, p.hp + hpGain)
                    end
                    if mpGain > 0 and (p.mp or 0) < p.maxMp then
                        p.mp = math.min(p.maxMp, (p.mp or 0) + mpGain)
                    end
                end
            end
        else
            GS.regenTimer = 0
        end
    end

    -- 事件关卡更新（优先于普通战斗逻辑）
    if EventManager.isActive() then
        EventManager.update(dt)
    end

    -- 覆盖层激活或场景切换过渡中时跳过所有战斗逻辑
    -- eventAllowNormalTurns 的事件关卡需要正常执行战斗逻辑（友军/敌人回合等）
    local eventBlocking = EventManager.isActive() and not GS.eventAllowNormalTurns
    if not BoardOverlay.isActive() and not GS.sceneTransition and not eventBlocking then
        -- 连击队列处理（优先级最高，处理期间阻塞其他战斗逻辑）
        if Combat.isChaining() then
            Combat.updateChainAttacks(dt)
        elseif Combat.pendingAutoAction or Combat.pendingManualAction or Combat.pendingAutoGather then
            -- 等待移动动画完成后执行待定动作
            Combat.processPendingActions(dt)
        else
            -- 采集回合推进（回合制，无论手动/自动均自动推进）
            Combat.processGatheringTurn(dt)

            -- 吟唱消耗动画（每0.7秒填充1段，阻塞自动战斗和玩家操作）
            Combat.processChantConsumeAnim(dt)

            -- 自动战斗
            Combat.processAutoCombat(dt)

            -- 友军（猎犬）回合
            Combat.processCompanionTurn(dt)

            -- 敌人回合
            Combat.processEnemyTurn(dt)

            -- 复活逻辑
            Combat.processRespawn(dt)
        end

        -- 酒馆肉搏：每帧兜底检查全部混混是否已击晕（brawlCinematic/sceneTransition 过渡中跳过）
        if GS.tavernBrawlState and not GS.tavernBrawlState.done and not GS.brawlCinematic and not GS.sceneTransition then
            local standing, totalThugs = 0, 0
            for _, m in ipairs(GS.monsters) do
                if m.isBrawlThug then
                    totalThugs = totalThugs + 1
                    if not m.brawlStunned then standing = standing + 1 end
                end
            end
            if totalThugs > 0 and standing == 0 then
                Combat.removeDeadMonsters()  -- 内部会触发胜利对话
            elseif totalThugs == 0 then
                -- 混混全被清空（切换关卡/地图），中断肉搏任务
                print("[酒馆肉搏] 混混不存在，任务中断")
                GS.tavernBrawlState = nil
                GS.brawlCinematic = nil
            end
        end
    end
end

-- ====================================================================
-- NanoVG 渲染
-- ====================================================================
function HandleNanoVGRender(eventType, eventData)
    if not vg then return end

    local logicalW, logicalH = Renderer.updateLayout()

    nvgBeginFrame(vg, logicalW, logicalH, GS.dpr)

    nvgScale(vg, GS.S, GS.S)

    if GS.gameState == GS.STATE_MENU then
        Renderer.drawMenu()
    elseif GS.gameState == GS.STATE_CHAR_SELECT then
        Renderer.drawCharSelect()
    elseif GS.gameState == GS.STATE_CHAR_CREATE then
        Renderer.drawCharCreate()
    elseif GS.gameState == GS.STATE_GAMEOVER then
        Renderer.drawGameOver()
    else
        -- 离开菜单/角色选择界面时销毁视频播放器
        Renderer.destroyMenuVideo()
        -- ★ 棋盘+特效+天气整体包裹在 pcall 中，
        -- 任何渲染错误都不会阻止后续 UI 面板的绘制
        local boardOk, boardErr = pcall(function()
        -- 屏幕震动偏移（仅影响战斗区域，UI面板不抖）
        nvgSave(vg)
        if GS.screenShake then
            local s = GS.screenShake
            local elapsed = s.timer - (s.delay or 0)
            if elapsed > 0 and elapsed < s.duration then
                local progress = elapsed / s.duration
                local decay = 1.0 - progress
                local shakeX = s.intensity * decay * math.sin(progress * math.pi * 8)
                local shakeY = s.intensity * decay * math.cos(progress * math.pi * 6)
                nvgTranslate(vg, shakeX, shakeY)
            end
        end
        Renderer.drawBackground()

        if not GS.eventSceneBg then
        -- 副本棋盘滚动：边框固定，内容在裁剪区内滑动
        local scrollOffset = 0
        if GS.dungeonScrollAnim then
            local a = GS.dungeonScrollAnim
            local t = math.min(1.0, a.timer / a.duration)
            local ease = t * t * (3 - 2 * t) -- smoothstep
            scrollOffset = a.totalOffset * ease -- 从0增长到totalOffset
        end
        local origBoardY = GS.BOARD_Y
        local boardPixel = GS.CELL * GS.BOARD_SIZE

        -- 1) 画棋盘边框（始终在原位）
        Renderer.drawBoardFrame()

        -- 2) 如果有滚动偏移，设置裁剪区域并偏移内容
        if scrollOffset ~= 0 then
            nvgSave(vg)
            nvgScissor(vg, GS.BOARD_X, origBoardY, boardPixel, boardPixel)
            GS.BOARD_Y = origBoardY + scrollOffset
        end

        -- 3) 画格子和所有棋盘内容（滚动时向上延伸额外行填充空白）
        local extraRows = 0
        if scrollOffset > 0 and GS.CELL > 0 then
            extraRows = math.ceil(scrollOffset / GS.CELL) + 1
        end
        Renderer.drawBoardCells(extraRows)
        Renderer.drawArenaExitTiles()

        Renderer.drawHomeRoom()
        if BoardOverlay.isActive() then
            BoardOverlay.draw(Renderer.vg)
        else
            if GS.gameState ~= GS.STATE_RESPAWN then
                Renderer.drawHighlights()
            end
            Renderer.drawChantingCircle()
            Renderer.drawUnits()
            Renderer.drawArenaChests()
            Renderer.drawArenaChestInteractBar()
            -- 所有技能特效绘制包裹在 pcall + nvgSave/nvgRestore 中，
            -- 即使特效渲染出错也不影响后续 UI 面板绘制
            nvgSave(vg)
            local fxOk, fxErr = pcall(function()
            Renderer.drawAttackEffects()
            Renderer.drawStrikeEffects()
            Renderer.drawBlessEffects()
            Renderer.drawWhirlwindEffects()
            Renderer.drawIceRingEffects()
            Renderer.drawFireballEffects()
            Renderer.drawMeteorEffects()
            Renderer.drawLightningChainEffects()
            Renderer.drawThunderStrikeEffects()
            Renderer.drawBlizzardIceEffects()
            Renderer.drawBurnEffects()
            Renderer.drawThunderCloudStrikeEffects()
            Renderer.drawSandBlindEffects()
            Renderer.drawTauntEffects()
            Renderer.drawCleaveEffects()
            Renderer.drawMeleeSplashEffects()
            Renderer.drawHolyAoeEffects()
            Renderer.drawStrikeAoeEffects()
            Renderer.drawRangedExplosionEffects()
            Renderer.drawPhantomAttackEffects()
            Renderer.drawSwordQiEffects()
            Renderer.drawMagicShieldEffects()
            Renderer.drawIceWallCreateEffects()
            Renderer.drawBlinkEffects()
            Renderer.drawStealthSmokeEffect()
            Renderer.drawHealEffects()
            Renderer.drawDivineGraceEffects()
            Renderer.drawHolyTreeWaveEffects()
            Renderer.drawRadianceWaveEffects()
            Renderer.drawApocalypseAoeEffects()
            Renderer.drawFocusBuffEffect()
            Renderer.drawStormBuffEffect()
            Renderer.drawPrayerBuffEffect()
            Renderer.drawChantingEffect()
            Renderer.drawHolySpringBuffEffect()
            Renderer.drawConquerBuffEffect()
            Renderer.drawShelterBuffEffect()
            Renderer.drawMiracleBuffEffect()
            end) -- pcall end for effects
            if not fxOk then
                print("[FX RENDER ERROR] " .. tostring(fxErr))
            end
            nvgRestore(vg)

            if GS.gameState == GS.STATE_RESPAWN or GS.tombstoneAnim then
                Renderer.drawTombstone()
            end

            if GS.gameState == GS.STATE_RESPAWN then
                Renderer.drawRespawnOverlay()
            end

        end
        -- 家模式下仓库面板（覆盖在单位之上）
        if GS.homeMode and GS.warehouseMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawWarehousePanel(Renderer.vg, bx, by, boardSize)
        end
        -- 家模式下共享仓库面板
        if GS.homeMode and GS.sharedStorageMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawSharedStoragePanel(Renderer.vg, bx, by, boardSize)
            -- 日志记录面板（叠加在共享仓库面板之上）
            if GS.sharedStorageLogOpen then
                BoardOverlay.drawSharedStorageLogPanel(Renderer.vg, bx, by, boardSize)
            end
        end
        -- 家模式下炼金面板（覆盖在单位之上）
        if GS.homeMode and GS.alchemyMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawAlchemyPanel(Renderer.vg, bx, by, boardSize)
        end

        if GS.homeMode and GS.cookingMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawCookingPanel(Renderer.vg, bx, by, boardSize)
        end

        if GS.homeMode and GS.forgeMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawForgePanel(Renderer.vg, bx, by, boardSize)
        end

        if GS.homeMode and GS.craftMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawCraftPanel(Renderer.vg, bx, by, boardSize)
        end

        if GS.homeMode and GS.enchantMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawEnchantPanel(Renderer.vg, bx, by, boardSize)
        end

        if GS.homeMode and GS.socketMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawSocketPanel(Renderer.vg, bx, by, boardSize)
        end

        if GS.homeMode and GS.homeSmithySelectMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawSmithySelectPopup(Renderer.vg, bx, by, boardSize)
        end

        if GS.homeMode and GS.giftMode then
            local bx, by = GS.BOARD_X, GS.BOARD_Y
            local boardSize = GS.BOARD_SIZE * GS.CELL
            BoardOverlay.drawGiftPanel(Renderer.vg, bx, by, boardSize)
        end

        -- 家场景伴侣互动黑屏遮罩（BoardOverlay 未激活时手动处理）
        -- 注意：当 BoardOverlay 已激活（子场景内）时，黑屏和对话框由 BoardOverlay.draw() 统一处理，
        -- 此处不能再画第二层黑屏，否则会覆盖对话框（且 fade 会被双重更新）。
        if GS.homeMode and BoardOverlay._kissSceneActive and not BoardOverlay.isActive() then
            -- 更新淡入淡出 alpha
            local fadeDt = math.min(GS.dt or 0.016, 0.05)
            if BoardOverlay._fadeAlpha and BoardOverlay._fadeTarget ~= nil then
                local speed = BoardOverlay._fadeSpeed or 800
                if BoardOverlay._fadeAlpha < BoardOverlay._fadeTarget then
                    BoardOverlay._fadeAlpha = math.min(BoardOverlay._fadeAlpha + speed * fadeDt, BoardOverlay._fadeTarget)
                elseif BoardOverlay._fadeAlpha > BoardOverlay._fadeTarget then
                    BoardOverlay._fadeAlpha = math.max(BoardOverlay._fadeAlpha - speed * fadeDt, BoardOverlay._fadeTarget)
                end
                if BoardOverlay._fadeAlpha == BoardOverlay._fadeTarget and BoardOverlay._fadeDoneCallback then
                    local cb = BoardOverlay._fadeDoneCallback
                    BoardOverlay._fadeDoneCallback = nil
                    cb()
                end
            end
            -- 渲染黑屏遮罩
            if BoardOverlay._fadeAlpha and BoardOverlay._fadeAlpha > 0 then
                local boardSize = GS.CELL * GS.BOARD_SIZE
                local bx, by = GS.BOARD_X, GS.BOARD_Y
                nvgBeginPath(vg)
                nvgRect(vg, bx, by, boardSize, boardSize)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(BoardOverlay._fadeAlpha)))
                nvgFill(vg)
            end
        end

        -- 事件对话框（不依赖 BoardOverlay，在棋盘上层绘制）
        Renderer.drawEventDialogue()

        -- 名字输入覆盖层（事件期间的交互面板）
        Renderer.drawNameInput()

        -- 4) 恢复
        if scrollOffset ~= 0 then
            nvgRestore(vg)
        end
        GS.BOARD_Y = origBoardY

        else -- eventSceneBg: 在棋盘区域绘制事件场景背景图（与建筑物场景相同方式）
            local sceneBgHandle = ImageManager.lazyGet("eventSceneBg", GS.eventSceneBg)
            if sceneBgHandle and sceneBgHandle ~= -1 then
                local bx, by = GS.BOARD_X, GS.BOARD_Y
                local boardSize = GS.CELL * GS.BOARD_SIZE
                local border = 4
                local cr = 6

                -- 黑色圆角边框（与 BoardOverlay.draw 一致）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx - border, by - border,
                    boardSize + border * 2, boardSize + border * 2, cr)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
                nvgFill(vg)

                -- 图片铺满（圆角裁剪）
                local innerR = math.max(0, cr - border)
                local pat = nvgImagePattern(vg, bx, by, boardSize, boardSize, 0, sceneBgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, by, boardSize, boardSize, innerR)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
            end

            -- 事件对话框（CG场景上层）
            Renderer.drawEventDialogue()
        end -- eventSceneBg

        -- 场景切换黑屏遮罩（在棋盘之上、UI之下）
        local tr = GS.sceneTransition
        if tr then
            local alpha = 0
            if tr.phase == "in" then
                alpha = math.floor(255 * math.min(1, tr.timer / tr.FADE_IN))
            elseif tr.phase == "hold" then
                alpha = 255
            elseif tr.phase == "out" then
                alpha = math.floor(255 * (1 - math.min(1, tr.timer / tr.FADE_OUT)))
            end
            if alpha > 0 then
                nvgBeginPath(vg)
                nvgRect(vg, -50, -50, GS.SCREEN_W + 100, GS.SCREEN_H + 100)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
                nvgFill(vg)
            end
        end

        -- 恢复震动偏移，以下UI面板不受屏幕抖动影响
        nvgRestore(vg)

        -- 卓越装备掉落橙光闪烁（覆盖整个非UI区域，不受屏幕震动影响）
        Renderer.drawSuperiorDropFlash()

        -- 天气效果（在UI面板下方绘制，各效果内部已自动判断室内跳过）
        RainEffect.draw(vg, GS.SCREEN_W, GS.SCREEN_H)
        WindEffect.draw(vg, GS.SCREEN_W, GS.SCREEN_H)
        ScorchEffect.draw(vg, GS.SCREEN_W, GS.SCREEN_H)

        end) -- pcall end: 棋盘 + 特效 + 天气
        if not boardOk then
            print("[BOARD RENDER ERROR] " .. tostring(boardErr))
        end
        -- ★ 强制恢复 NanoVG 状态到根状态，确保 UI 面板不受任何渲染异常影响
        -- NanoVG 源码中 nstates<=1 时 nvgRestore 安全返回，可多次调用
        for i = 1, 50 do
            nvgRestore(vg)
        end
        -- ★ 防御性重置：即使根状态的 transform/scissor/alpha 被 pcall 内部的渲染意外修改，
        -- 也能保证 UI 面板使用干净正确的绘制状态
        nvgResetTransform(vg)
        nvgResetScissor(vg)
        nvgGlobalAlpha(vg, 1.0)
        nvgScale(vg, GS.S, GS.S)

        Renderer.drawTopBar()
        SignInSystem.drawButton(vg)
        Renderer.drawFloatingTexts()
        if GS.trainingMode then
            Renderer.drawTrainingStats()
            Renderer.drawTrainingLevelPanel()
        end
        if GS.showGMPanel then
            Renderer.drawGMPanel()
        end
        Renderer.drawInfoBar()
        Renderer.drawInventoryBar()
        if GS.showSettings then
            Renderer.drawSettingsPanel()
        end
        -- 怪物增益&减益面板绘制在底部面板之上，避免被遮挡
        if GS.showMonsterBuffSummary and GS._monsterBuffTarget then
            Renderer.drawMonsterBuffPanel(vg)
        end
        -- 测试面板绘制在背包之上，避免被遮挡
        if GS.showGMPanel then
            if GS.showTestStagePanel then
                Renderer.drawTestStagePanel()
            end
            if GS.showTestItemPanel then
                Renderer.drawTestItemPanel()
            end
        end
        -- 监测面板（覆盖层，在测试面板之上）
        local MonitorPanel = require("MonitorPanel")
        MonitorPanel.drawPanel(vg)
        -- GM 封禁面板（覆盖层）
        if BanManager.isGMPanelOpen() then
            Renderer.drawGMBanPanel()
        end
        -- 在线监测面板（兼容从GM面板直接打开的情况）
        if not MonitorPanel.showPanel then
            OnlineMonitor.drawPanel(vg)
        end

        Renderer.drawDragFloatingItem()
        Renderer.drawReadingPopup()
        Renderer.drawElfvahLearnedPopup()
        Renderer.drawElfNotFoundPopup()
        Renderer.drawDestroyConfirmDialog()
        Renderer.drawRespecPopupDialog()
        Renderer.drawSplitPopupDialog()
        Renderer.drawBuyConfirmDialog()
        Renderer.drawAbyssConfirmDialog()
        Renderer.drawAbyssWorldConfirmDialog()
        Renderer.drawSlimeRevengeConfirmDialog()
        Renderer.drawDihataRevengeConfirmDialog()
        Renderer.drawAbyssFakeAdOverlay()
        SignInSystem.drawPanel(vg)
        Renderer.drawSlimeRevengeRewardPanel()
        Renderer.drawSlimeRevengeRankPanel()
        Renderer.drawDihataRevengeRewardPanel()
        Renderer.drawDihataRevengeRankPanel()
        Renderer.drawItemTooltip()
        Renderer.drawProposalSuccessPopup()
        Renderer.drawPetNameInput()
        Renderer.drawRenameInput()
        Renderer.drawRedeemCodeDialog()
        if GS._unstuckConfirmVisible then
            Renderer.drawUnstuckConfirm()
        end
        Renderer.drawHouseBuyDialog()
        Renderer.drawHouseBuySuccessDialog()
        Renderer.drawHomeUpgradeDialog()
        Renderer.drawStreetSleepOverlay()
        Renderer.drawScreenOffOverlay()
        Renderer.drawShopBuyMsg(GS.dt or 0.016)
        Renderer.drawActionMenu()
        Renderer.drawSkillTooltip()
        if GS.showAutoBattleSettings then
            Renderer.drawAutoBattleSettingsPanel()
        end
        Renderer.drawSkillEquipPopup()
    end

    Renderer.drawDebuffTooltip()

    -- 浮动文本在所有UI面板之上绘制，避免被背包等面板遮挡
    Renderer.drawDamageTexts()

    -- 事件场景图片覆盖层（覆盖棋盘区域，与建筑物内景一致）
    if GS.eventSceneImage then
        local si = GS.eventSceneImage
        local imgHandle = ImageManager.lazyGet("bg", si.imagePath)
        local boardSize = GS.CELL * GS.BOARD_SIZE
        local bx = GS.BOARD_X
        local by = GS.BOARD_Y
        local border = 4
        local cr = 6
        local innerR = math.max(0, cr - border)
        local alpha = math.floor((si.alpha or 1.0) * 255)

        -- 黑色圆角边框（与 BoardOverlay 一致）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx - border, by - border,
            boardSize + border * 2, boardSize + border * 2, cr)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)

        -- 图片铺满棋盘区域（圆角裁剪）
        if imgHandle and imgHandle ~= -1 and alpha > 0 then
            local pat = nvgImagePattern(vg, bx, by, boardSize, boardSize, 0, imgHandle, alpha / 255.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, boardSize, boardSize, innerR)
            nvgFillPaint(vg, pat)
            nvgFill(vg)
        end
        -- 事件场景图片之上再绘制对话框，避免被背景图遮挡
        Renderer.drawEventDialogue()
    end

    -- 酒馆肉搏黑屏过渡覆盖层（棋盘区域黑色遮罩 + 对话框）
    local bc = GS.brawlCinematic
    if bc and bc.alpha > 0 then
        local boardSize = GS.CELL * GS.BOARD_SIZE
        local bx, by = GS.BOARD_X, GS.BOARD_Y
        local border = 4
        local cr = 6
        -- 1) 黑色圆角边框（与 BoardOverlay / eventSceneBg 一致）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx - border, by - border,
            boardSize + border * 2, boardSize + border * 2, cr)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, bc.alpha))
        nvgFill(vg)
        -- 2) 对话阶段：在黑屏之上绘制对话框
        if bc.phase == "dialogue" then
            Renderer.drawEventDialogue()
        end
    end

    -- 事件黑屏覆盖层（全屏背景 + 逐字打出文本）
    if GS.eventBlackScreen then
        local bs = GS.eventBlackScreen
        -- 背景色：免责声明段 = 黑色，正文段 = 米白色，过渡期插值
        local blend = bs.bgBlend or (bs.isDisclaimer and 0 or 1)
        local bgR = math.floor(245 * blend)
        local bgG = math.floor(240 * blend)
        local bgB = math.floor(230 * blend)
        nvgBeginPath(vg)
        nvgRect(vg, -50, -50, GS.SCREEN_W + 100, GS.SCREEN_H + 100)
        nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 255))
        nvgFill(vg)
        -- 逐字打出文字 + 末尾方块光标
        if bs.fullText and bs.alpha > 0 then
            local textAlpha = math.floor(bs.alpha * 255)
            local fontSize = math.max(20, GS.SCREEN_W * 0.045)
            -- 文字颜色：免责声明段 = 白色，"第三意志" = 红色，其余正文 = 黑灰色
            local tr, tg, tb = 60, 60, 60
            if bs.isDisclaimer then tr, tg, tb = 255, 255, 255 end
            if bs.isLast then tr, tg, tb = 230, 50, 50 end

            -- 截取已显示的字符（按 UTF-8 字符数）
            local displayText = ""
            if bs.visibleChars > 0 then
                local bytePos = utf8.offset(bs.fullText, bs.visibleChars + 1)
                if bytePos then
                    displayText = string.sub(bs.fullText, 1, bytePos - 1)
                else
                    displayText = bs.fullText
                end
            end

            nvgFontFace(vg, "sans")
            nvgFillColor(vg, nvgRGBA(tr, tg, tb, textAlpha))

            if bs.isDisclaimer then
                -- 免责声明段：较小字号，手动按字符换行，黑底白字
                local disclaimerFontSize = math.max(14, GS.SCREEN_W * 0.028)
                nvgFontSize(vg, disclaimerFontSize)
                local boxW = GS.SCREEN_W * 0.7
                local boxX = GS.SCREEN_W * 0.15

                -- 用完整文本预计算行数，避免打字过程中行位置跳动
                local function wrapTextToLines(text)
                    local lines = {}
                    local cur = ""
                    for _, c in utf8.codes(text) do
                        local ch = utf8.char(c)
                        local test = cur .. ch
                        local tw = nvgTextBounds(vg, 0, 0, test, nil)
                        if tw > boxW and cur ~= "" then
                            lines[#lines + 1] = cur
                            cur = ch
                        else
                            cur = test
                        end
                    end
                    if cur ~= "" then lines[#lines + 1] = cur end
                    return lines
                end

                local fullLines = wrapTextToLines(bs.fullText)
                local isSingleLine = (#fullLines <= 1)

                -- 垂直居中：始终基于完整文本的行数
                local lineH = disclaimerFontSize * 1.4
                local totalH = #fullLines * lineH
                local baseY = GS.SCREEN_H / 2 - totalH / 2 + lineH / 2

                -- 对已显示的部分文本做换行，用于实际绘制
                local dispLines = wrapTextToLines(displayText)

                if isSingleLine then
                    -- 单行文本（如"觉浅湖工作室"）：水平居中
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    for i, line in ipairs(dispLines) do
                        nvgText(vg, GS.SCREEN_W / 2, baseY + (i - 1) * lineH, line, nil)
                    end
                else
                    -- 多行文本：左对齐
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    for i, line in ipairs(dispLines) do
                        nvgText(vg, boxX, baseY + (i - 1) * lineH, line, nil)
                    end
                end

                -- 方块光标（跟在最后一行末尾）
                if bs.visibleChars > 0 then
                    local lastLine = dispLines[#dispLines] or ""
                    local lastLineW = nvgTextBounds(vg, 0, 0, lastLine, nil)
                    local cursorSize = disclaimerFontSize * 0.5
                    local cursorAlpha = textAlpha
                    if bs.visibleChars >= bs.charCount then
                        local blink = math.sin(os.clock() * 5) > 0
                        cursorAlpha = blink and textAlpha or 0
                    end
                    if cursorAlpha > 0 then
                        local cursorX, cursorY
                        if isSingleLine then
                            cursorX = GS.SCREEN_W / 2 + lastLineW / 2 + disclaimerFontSize * 0.3
                        else
                            cursorX = boxX + lastLineW + disclaimerFontSize * 0.3
                        end
                        cursorY = baseY + (#dispLines - 1) * lineH
                        nvgBeginPath(vg)
                        nvgRect(vg, cursorX - cursorSize * 0.5, cursorY - cursorSize * 0.5, cursorSize, cursorSize)
                        nvgFillColor(vg, nvgRGBA(tr, tg, tb, cursorAlpha))
                        nvgFill(vg)
                    end
                end
            else
                -- 正文段：单行居中，米白底黑灰字（第三意志红色）
                nvgFontSize(vg, fontSize)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2, displayText, nil)

                -- 末尾方块光标（闪烁效果）
                if bs.visibleChars > 0 then
                    local textW = nvgTextBounds(vg, 0, 0, displayText, nil)
                    local cursorX = GS.SCREEN_W / 2 + textW / 2 + fontSize * 0.3
                    local cursorSize = fontSize * 0.55
                    local cursorAlpha = textAlpha
                    if bs.visibleChars >= bs.charCount then
                        local blink = math.sin(os.clock() * 5) > 0
                        cursorAlpha = blink and textAlpha or 0
                    end
                    if cursorAlpha > 0 then
                        nvgBeginPath(vg)
                        nvgRect(vg, cursorX - cursorSize * 0.5, GS.SCREEN_H / 2 - cursorSize * 0.5, cursorSize, cursorSize)
                        nvgFillColor(vg, nvgRGBA(tr, tg, tb, cursorAlpha))
                        nvgFill(vg)
                    end
                end
            end
        end
    end

    -- 米白色背景阶段：在覆盖层上方再画一层雨效（正常游戏时雨在底层绘制）
    if GS.eventBlackScreen and (GS.eventBlackScreen.bgBlend or 0) >= 1 then
        RainEffect.draw(vg, GS.SCREEN_W, GS.SCREEN_H)
    end

    -- 事件过渡层（米白色闪光：米白 → 纯白 → 渐隐）
    if GS.eventWhiteFlash then
        local wf = GS.eventWhiteFlash
        local progress = wf.timer / wf.duration
        if progress > 1 then progress = 1 end
        local r, g, b, alpha
        if progress < 0.3 then
            -- 前30%：从米白色闪到纯白
            local t = progress / 0.3
            r = math.floor(245 + 10 * t)
            g = math.floor(240 + 15 * t)
            b = math.floor(230 + 25 * t)
            alpha = 255
        else
            -- 后70%：纯白渐隐
            r, g, b = 255, 255, 255
            alpha = math.floor(255 * (1 - (progress - 0.3) / 0.7))
        end
        if alpha > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, -50, -50, GS.SCREEN_W + 100, GS.SCREEN_H + 100)
            nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
            nvgFill(vg)
        end
    end

    -- 全屏黑屏淡入淡出（角色选择→进入游戏等场景切换）
    if GS.screenFade then
        local sf = GS.screenFade
        local fadeDt = math.min(GS.dt or 0.016, 0.05)
        local speed = sf.speed or 400
        if sf.alpha < sf.target then
            sf.alpha = math.min(sf.alpha + speed * fadeDt, sf.target)
        elseif sf.alpha > sf.target then
            sf.alpha = math.max(sf.alpha - speed * fadeDt, sf.target)
        end
        if sf.alpha == sf.target and sf.callback then
            local cb = sf.callback
            sf.callback = nil
            cb()
        end
        if sf.alpha > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, -50, -50, GS.SCREEN_W + 100, GS.SCREEN_H + 100)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(sf.alpha)))
            nvgFill(vg)
        end
        -- 淡出完毕后清理
        if sf.alpha == 0 and sf.target == 0 and not sf.callback then
            GS.screenFade = nil
        end
    end

    nvgEndFrame(vg)
end
