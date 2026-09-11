-- 弹射4096：装扮、成就、每日任务、每日挑战数据层。
-- 规则与微信版 metaGame.js 对齐；平台差异仅限本地/云存储适配。

local MetaGame = {}
MetaGame.__index = MetaGame

local VERSION = 1
local DAILY_CHEST_REWARD = 16
local DAILY_CHALLENGE_TARGET = 4000
local DAILY_CHALLENGE_REWARD = 24
local DAILY_FREEZE_LAUNCHES = 5

local ACHIEVEMENTS = {
    { id = "merge_1", name = "初次合成", description = "完成 1 次方块合成", metric = "totalMerges", target = 1, reward = 5 },
    { id = "merge_25", name = "渐入佳境", description = "累计完成 25 次合成", metric = "totalMerges", target = 25, reward = 12 },
    { id = "merge_100", name = "合成达人", description = "累计完成 100 次合成", metric = "totalMerges", target = 100, reward = 30 },
    { id = "combo_5", name = "连击起步", description = "达成 5 Combo", metric = "highestCombo", target = 5, reward = 10 },
    { id = "combo_15", name = "连击高手", description = "达成 15 Combo", metric = "highestCombo", target = 15, reward = 28 },
    { id = "value_128", name = "突破三位数", description = "合成 128 方块", metric = "highestValue", target = 128, reward = 15 },
    { id = "value_1024", name = "千分高手", description = "合成 1024 方块", metric = "highestValue", target = 1024, reward = 40 },
    { id = "runs_10", name = "坚持不懈", description = "完成 10 局游戏", metric = "completedRuns", target = 10, reward = 25 },
    { id = "rescue_5", name = "化险为夷", description = "累计解除 5 次红线危险", metric = "totalDangerRescues", target = 5, reward = 20 },
    { id = "ice_3", name = "破冰专家", description = "完成 3 次每日挑战", metric = "dailyChallengesCompleted", target = 3, reward = 30 },
}

local COSMETICS = {
    { id = "trail_default", kind = "trail", name = "原色轨迹", price = 0, rarity = "基础", effect = "classic" },
    { id = "trail_star", kind = "trail", name = "金星拖尾", price = 60, rarity = "稀有", effect = "starfall", color = {255, 203, 36, 255} },
    { id = "trail_mint", kind = "trail", name = "星环航迹", price = 0, level = 5, rarity = "稀有", effect = "aurora", color = {0, 214, 160, 255} },
    { id = "trail_sunset", kind = "trail", name = "流星矩阵", price = 100, rarity = "史诗", effect = "comet", color = {255, 139, 74, 255} },
    { id = "trail_music", kind = "trail", name = "音符律动", price = 240, rarity = "传说", effect = "music", color = {167, 123, 255, 255} },
    { id = "merge_default", kind = "merge", name = "原色合成", price = 0, rarity = "基础", effect = "classic" },
    { id = "merge_gold", kind = "merge", name = "星芒冲击", price = 0, level = 10, rarity = "稀有", effect = "crown", color = {255, 203, 36, 255} },
    { id = "merge_mint", kind = "merge", name = "双环冲击", price = 160, rarity = "史诗", effect = "aurora", color = {0, 224, 164, 255} },
    { id = "merge_prism", kind = "merge", name = "棱镜爆裂", price = 280, rarity = "传说", effect = "prism", color = {167, 123, 255, 255} },
    { id = "merge_explosion", kind = "merge", name = "核爆现场", price = 240, rarity = "传说", effect = "explosion", color = {255, 138, 32, 255} },
    { id = "fireworks_default", kind = "fireworks", name = "派对彩带", price = 0, rarity = "基础", effect = "classic" },
    { id = "fireworks_gold", kind = "fireworks", name = "冠军星爆", price = 0, level = 15, rarity = "史诗", effect = "starburst", color = {255, 203, 36, 255} },
    { id = "fireworks_neon", kind = "fireworks", name = "星爆瀑布", price = 240, rarity = "传说", effect = "starfall", color = {167, 123, 255, 255} },
    { id = "block_default", kind = "block", name = "经典方块", price = 0, rarity = "基础", effect = "classic" },
    { id = "block_candy", kind = "block", name = "流光渐变", price = 0, level = 20, rarity = "传说", effect = "gradient", palette = {{255,111,174,255},{255,209,102,255},{88,214,185,255},{89,167,255,255},{167,123,255,255}} },
    { id = "block_midnight", kind = "block", name = "莫兰迪方块", price = 0, level = 30, rarity = "传说", effect = "morandi", palette = {{183,166,160,255},{197,184,143,255},{143,169,163,255},{145,160,181,255},{173,154,175,255},{182,154,145,255}} },
    { id = "block_royal", kind = "block", name = "多巴胺方块", price = 360, rarity = "传说", effect = "dopamine", palette = {{255,61,127,255},{255,212,0,255},{0,216,149,255},{30,139,255,255},{155,81,255,255},{255,107,0,255}} },
    { id = "theme_retro", kind = "theme", name = "复古乐园", price = 0, rarity = "基础", effect = "retro" },
    { id = "theme_mint", kind = "theme", name = "薄荷派对", price = 0, level = 25, rarity = "史诗", effect = "mint" },
    { id = "theme_tomato", kind = "theme", name = "番茄庆典", price = 420, rarity = "传说", effect = "tomato" },
}

local DEFAULT_EQUIPPED = {
    trail = "trail_default", merge = "merge_default", fireworks = "fireworks_default",
    block = "block_default", theme = "theme_retro",
}
local JOURNEY_UNLOCKS = { [5]="trail_mint", [10]="merge_gold", [15]="fireworks_gold", [20]="block_candy", [25]="theme_mint", [30]="block_midnight" }

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function Int(v, fallback) return math.floor(tonumber(v) or fallback or 0) end
local function Copy(source)
    local out = {}
    for k, v in pairs(source or {}) do out[k] = v end
    return out
end
local function Contains(list, value)
    for _, item in ipairs(list or {}) do if item == value then return true end end
    return false
end
local function FindById(list, id)
    for _, item in ipairs(list) do if item.id == id then return item end end
    return nil
end
local function DateKey(now)
    return os.date("%Y-%m-%d", now or os.time())
end
local function HashText(text)
    local hash = 5381
    for i = 1, #text do hash = (hash * 33 + string.byte(text, i)) % 2147483647 end
    return hash
end
local function JourneyLevel(score)
    local level = 1
    while level < 30 and score >= 250 * level * (level + 1) / 2 do level = level + 1 end
    return level
end

local function BuildDailyMissions(key, highestValue)
    local difficulty = highestValue < 128 and {merge=32, combo=3}
        or (highestValue < 512 and {merge=128, combo=5} or {merge=256, combo=10})
    local pool = {
        { id="merge", type="merge_at_least", value=difficulty.merge, target=1, reward=11, label="合成 1 个至少 "..difficulty.merge.." 的方块" },
        { id="combo", type="combo", target=difficulty.combo, reward=10, label="达到 "..difficulty.combo.." Combo" },
        { id="score", type="score_today", target=highestValue < 128 and 1000 or 3000, reward=11, label="今日累计获得积分" },
        { id="runs", type="play_runs", target=2, reward=11, label="完成 2 局游戏" },
        { id="rescue", type="danger_rescue", target=2, reward=12, label="解除 2 次红线危险" },
        { id="chain", type="chain_merge", target=2, reward=13, label="完成 2 次连锁合成" },
    }
    table.sort(pool, function(a,b) return HashText(key..a.id) < HashText(key..b.id) end)
    local result = {
        -- TapTap Maker 当前未提供分享回调，微信版“分享 1 次”在此适配为完成 1 局。
        { id=key.."_play", type="play_runs", target=1, reward=8, label="完成 1 局游戏", progress=0, completed=false, claimed=false },
        { id=key.."_video", type="watch_video", target=3, reward=15, label="完整观看 3 次视频", progress=0, completed=false, claimed=false },
    }
    for i = 1, 3 do
        local mission = Copy(pool[i]); mission.id = key.."_"..mission.id
        mission.progress, mission.completed, mission.claimed = 0, false, false
        result[#result+1] = mission
    end
    return result
end

local function DefaultData(now)
    local key = DateKey(now)
    return {
        version=VERSION, revision=0, stars=0, lifetimeScore=0, journeyLevel=1,
        highestValue=2, highestCombo=0, completedRuns=0,
        stats={totalLaunches=0,totalMerges=0,totalDangerRescues=0,dailyChallengesCompleted=0},
        achievementClaims={}, unlockedCosmetics={"trail_default","merge_default","fireworks_default","block_default","theme_retro"},
        equipped=Copy(DEFAULT_EQUIPPED),
        daily={key=key,missions=BuildDailyMissions(key,2),chestClaimed=false,firstRunClaimed=false,
            normalBestScore=0,challenge={launchProgress=0,pendingFreezes=0,freezesTriggered=0,thaws=0,bestScore=0,completed=false,rewardClaimed=false}},
        activeRun=nil,
    }
end

local function Normalize(raw, now)
    local data = type(raw)=="table" and raw or DefaultData(now)
    data.version, data.revision = VERSION, math.max(0, Int(data.revision,0))
    data.stars, data.lifetimeScore = math.max(0,Int(data.stars,0)), math.max(0,Int(data.lifetimeScore,0))
    data.highestValue, data.highestCombo = math.max(2,Int(data.highestValue,2)), math.max(0,Int(data.highestCombo,0))
    data.completedRuns = math.max(0,Int(data.completedRuns,0)); data.journeyLevel = JourneyLevel(data.lifetimeScore)
    data.stats = type(data.stats)=="table" and data.stats or {}
    for _, key in ipairs({"totalLaunches","totalMerges","totalDangerRescues","dailyChallengesCompleted"}) do data.stats[key]=math.max(0,Int(data.stats[key],0)) end
    data.achievementClaims = type(data.achievementClaims)=="table" and data.achievementClaims or {}
    data.unlockedCosmetics = type(data.unlockedCosmetics)=="table" and data.unlockedCosmetics or {}
    for _, id in pairs(DEFAULT_EQUIPPED) do if not Contains(data.unlockedCosmetics,id) then data.unlockedCosmetics[#data.unlockedCosmetics+1]=id end end
    data.equipped = type(data.equipped)=="table" and data.equipped or Copy(DEFAULT_EQUIPPED)
    for kind,id in pairs(DEFAULT_EQUIPPED) do if not Contains(data.unlockedCosmetics,data.equipped[kind]) then data.equipped[kind]=id end end
    for level,id in pairs(JOURNEY_UNLOCKS) do if data.journeyLevel>=level and not Contains(data.unlockedCosmetics,id) then data.unlockedCosmetics[#data.unlockedCosmetics+1]=id end end
    local key=DateKey(now)
    if type(data.daily)~="table" or data.daily.key~=key then
        data.daily=DefaultData(now).daily
    else
        data.daily.missions=type(data.daily.missions)=="table" and data.daily.missions or BuildDailyMissions(key,data.highestValue)
        data.daily.challenge=type(data.daily.challenge)=="table" and data.daily.challenge or DefaultData(now).daily.challenge
    end
    return data
end

function MetaGame.new(raw, now)
    return setmetatable({data=Normalize(raw,now)}, MetaGame)
end
function MetaGame:Touch() self.data.revision=self.data.revision+1; if self.onChanged then self.onChanged(self.data) end end
function MetaGame:EnsureDaily(now)
    local key=DateKey(now)
    if self.data.daily.key==key then return false end
    self.data.daily=DefaultData(now).daily; self.data.daily.missions=BuildDailyMissions(key,self.data.highestValue); self:Touch(); return true
end
function MetaGame:BeginRun(id, now)
    self:EnsureDaily(now); self.data.activeRun={id=id or ("run_"..os.time()),score=0,maxValue=2,maxCombo=0,launchCount=0,currentLaunchId=0,chainCounts={}}; self:Touch()
end
function MetaGame:RecordLaunch(value, now)
    if not self.data.activeRun then self:BeginRun(nil,now) end
    local run=self.data.activeRun; run.launchCount=run.launchCount+1; run.currentLaunchId=run.currentLaunchId+1; run.chainCounts[run.currentLaunchId]=0
    run.maxValue=math.max(run.maxValue,value); self.data.stats.totalLaunches=self.data.stats.totalLaunches+1; self:Touch()
end
function MetaGame:ApplyMissionEvent(kind, value, now)
    self:EnsureDaily(now); local changed=false
    for _,m in ipairs(self.data.daily.missions) do
        if not m.completed and m.type==kind then
            if kind=="merge_at_least" then if value>=m.value then m.progress=m.progress+1 end
            elseif kind=="combo" then m.progress=math.max(m.progress,value)
            else m.progress=m.progress+math.max(1,Int(value,1)) end
            m.progress=math.min(m.target,m.progress); m.completed=m.progress>=m.target; changed=true
        end
    end
    if changed then self:Touch() end
end
function MetaGame:RecordMerge(value, combo, now)
    if not self.data.activeRun then self:BeginRun(nil,now) end
    local run=self.data.activeRun; run.score=run.score+value; run.maxValue=math.max(run.maxValue,value); run.maxCombo=math.max(run.maxCombo,combo)
    self.data.highestValue=math.max(self.data.highestValue,value); self.data.highestCombo=math.max(self.data.highestCombo,combo); self.data.stats.totalMerges=self.data.stats.totalMerges+1
    self:ApplyMissionEvent("merge_at_least",value,now); self:ApplyMissionEvent("combo",combo,now); self:ApplyMissionEvent("score_today",value,now)
    local id=run.currentLaunchId
    if id>0 then run.chainCounts[id]=(run.chainCounts[id] or 0)+1; if run.chainCounts[id]==2 then self:ApplyMissionEvent("chain_merge",1,now) end end
    self:Touch()
end
function MetaGame:RecordDangerRescue(now) self.data.stats.totalDangerRescues=self.data.stats.totalDangerRescues+1; self:ApplyMissionEvent("danger_rescue",1,now); self:Touch() end
function MetaGame:FinishRun(score,maxValue,maxCombo,now)
    local run=self.data.activeRun or {id="run_"..os.time()}; local oldLevel=self.data.journeyLevel
    self.data.lifetimeScore=self.data.lifetimeScore+math.max(0,Int(score,0)); self.data.completedRuns=self.data.completedRuns+1
    self.data.highestValue=math.max(self.data.highestValue,Int(maxValue,2)); self.data.highestCombo=math.max(self.data.highestCombo,Int(maxCombo,0)); self.data.journeyLevel=JourneyLevel(self.data.lifetimeScore)
    local reward=math.min(40,math.floor(score/150)+math.min(10,math.floor(maxCombo/5)*2)+(self.data.daily.firstRunClaimed and 0 or 3))
    self.data.daily.firstRunClaimed=true; self.data.stars=self.data.stars+reward
    for level=oldLevel+1,self.data.journeyLevel do local id=JOURNEY_UNLOCKS[level]; if id and not Contains(self.data.unlockedCosmetics,id) then self.data.unlockedCosmetics[#self.data.unlockedCosmetics+1]=id end end
    self.data.activeRun=nil; self:ApplyMissionEvent("play_runs",1,now); self:Touch(); return reward
end
function MetaGame:Achievements()
    local out={}
    for _,a in ipairs(ACHIEVEMENTS) do local e=Copy(a); local p=(a.metric=="highestCombo" and self.data.highestCombo) or (a.metric=="highestValue" and self.data.highestValue) or (a.metric=="completedRuns" and self.data.completedRuns) or self.data.stats[a.metric] or 0; e.progress=math.min(a.target,p); e.completed=p>=a.target; e.claimed=self.data.achievementClaims[a.id]==true; out[#out+1]=e end
    return out
end
function MetaGame:ClaimAchievement(id)
    local item=FindById(self:Achievements(),id); if not item or not item.completed or item.claimed then return false end
    self.data.achievementClaims[id]=true; self.data.stars=self.data.stars+item.reward; self:Touch(); return true
end
function MetaGame:ClaimMission(id)
    local m=FindById(self.data.daily.missions,id); if not m or not m.completed or m.claimed then return false end
    m.claimed=true; self.data.stars=self.data.stars+m.reward
    if not self.data.daily.chestClaimed then local all=true; for _,x in ipairs(self.data.daily.missions) do if not x.claimed then all=false end end; if all then self.data.daily.chestClaimed=true; self.data.stars=self.data.stars+DAILY_CHEST_REWARD end end
    self:Touch(); return true
end
function MetaGame:Cosmetics(kind)
    local out={}; for _,item in ipairs(COSMETICS) do if not kind or item.kind==kind then local e=Copy(item); e.unlocked=Contains(self.data.unlockedCosmetics,item.id); e.equipped=self.data.equipped[item.kind]==item.id; out[#out+1]=e end end; return out
end
function MetaGame:PurchaseOrEquip(id)
    local item=FindById(COSMETICS,id); if not item then return false,"missing" end
    if not Contains(self.data.unlockedCosmetics,id) then
        if item.level and self.data.journeyLevel<item.level then return false,"level" end
        if self.data.stars<item.price then return false,"stars" end
        self.data.stars=self.data.stars-item.price; self.data.unlockedCosmetics[#self.data.unlockedCosmetics+1]=id
    end
    self.data.equipped[item.kind]=id; self:Touch(); return true
end
function MetaGame:Equipped(kind) return FindById(COSMETICS,self.data.equipped[kind]) or FindById(COSMETICS,DEFAULT_EQUIPPED[kind]) end
function MetaGame:RecordChallengeLaunch(now)
    self:EnsureDaily(now); local c=self.data.daily.challenge; c.launchProgress=(c.launchProgress or 0)+1; local freeze=false
    if c.launchProgress>=DAILY_FREEZE_LAUNCHES then c.launchProgress=0; c.pendingFreezes=math.min(3,(c.pendingFreezes or 0)+1); freeze=true end
    self:Touch(); return freeze,c.launchProgress
end
function MetaGame:ClaimChallengeFreeze() local c=self.data.daily.challenge; if (c.pendingFreezes or 0)<=0 then return false end; c.pendingFreezes=c.pendingFreezes-1; c.freezesTriggered=(c.freezesTriggered or 0)+1; self:Touch(); return true end
function MetaGame:RecordChallengeThaw() local c=self.data.daily.challenge; c.thaws=(c.thaws or 0)+1; self:Touch() end
function MetaGame:RecordChallengeScore(score)
    local c=self.data.daily.challenge; c.bestScore=math.max(c.bestScore or 0,score); local reward=0
    if c.bestScore>=DAILY_CHALLENGE_TARGET and not c.rewardClaimed then c.completed=true;c.rewardClaimed=true;reward=DAILY_CHALLENGE_REWARD;self.data.stars=self.data.stars+reward;self.data.stats.dailyChallengesCompleted=self.data.stats.dailyChallengesCompleted+1 end
    self:Touch(); return reward
end
function MetaGame:ResetChallengeAttempt() local c=self.data.daily.challenge;c.launchProgress=0;c.pendingFreezes=0;self:Touch() end
function MetaGame:Export() return self.data end
function MetaGame.MergeRemote(localData,remoteData)
    if type(remoteData)~="table" then return localData end
    if Int(remoteData.revision,0)>Int(localData and localData.revision,0) then return remoteData end
    return localData
end

MetaGame.CONFIG={version=VERSION,dailyChestReward=DAILY_CHEST_REWARD,dailyChallengeTarget=DAILY_CHALLENGE_TARGET,dailyChallengeReward=DAILY_CHALLENGE_REWARD,dailyFreezeLaunches=DAILY_FREEZE_LAUNCHES,achievements=ACHIEVEMENTS,cosmetics=COSMETICS,kinds={"trail","merge","fireworks","block","theme"}}
return MetaGame
