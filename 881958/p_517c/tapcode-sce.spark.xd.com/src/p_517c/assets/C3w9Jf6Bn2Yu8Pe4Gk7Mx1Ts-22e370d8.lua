-- 弹射4096成长系统 NanoVG 界面。按系统逻辑分辨率绘制与命中。

local MetaUI = {}
MetaUI.__index = MetaUI

local C = {
    ink={35,42,43,255}, cream={255,247,218,255}, blood={185,58,50,255},
    mint={71,194,159,255}, mustard={242,190,67,255}, teal={49,126,125,255},
    lavender={167,123,255,255}, gray={112,116,112,255}, ice={126,220,255,255},
}
local TAB_NAMES = {wardrobe="装扮",achievements="成就",missions="每日任务",challenge="每日挑战"}
local TAB_ORDER = {"wardrobe","achievements","missions","challenge"}
local KIND_NAMES = {trail="轨迹",merge="合成",fireworks="连击",block="方块",theme="主题"}

local function Color(c,a) return nvgRGBA(c[1],c[2],c[3],a or c[4] or 255) end
local function Inside(x,y,r) return r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h end
local function RoundRect(vg,x,y,w,h,r,color,alpha,stroke)
    nvgBeginPath(vg); nvgRoundedRect(vg,x,y,w,h,r); nvgFillColor(vg,Color(color,alpha)); nvgFill(vg)
    if stroke then nvgStrokeColor(vg,Color(stroke));nvgStrokeWidth(vg,2);nvgStroke(vg) end
end
local function Text(vg,selectBody,x,y,text,size,color,align)
    selectBody();nvgFontSize(vg,size);nvgTextAlign(vg,align or (NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE));nvgFillColor(vg,Color(color));nvgText(vg,x,y,tostring(text),nil)
end
local function ShortProgress(progress,target) return tostring(math.min(progress or 0,target or 1)).."/"..tostring(target or 1) end

function MetaUI.new()
    return setmetatable({
        open = false,
        tab = "wardrobe",
        kind = "trail",
        page = 1,
        buttons = {},
        toast = nil,
        toastAge = 0,
        hintAge = 7.5,
        entryButton = nil,
        growthButton = nil,
        challengeButton = nil,
    }, MetaUI)
end
function MetaUI:SetToast(text) self.toast = text; self.toastAge = 2.4 end
function MetaUI:Update(dt)
    if self.toastAge > 0 then
        self.toastAge = math.max(0, self.toastAge - dt)
        if self.toastAge == 0 then self.toast = nil end
    end
    if self.hintAge and self.hintAge > 0 then
        self.hintAge = math.max(0, self.hintAge - dt)
    end
end
function MetaUI:IsOpen() return self.open end
function MetaUI:Close() self.open = false; self.buttons = {} end
function MetaUI:Open(tab)
    self.open = true
    if tab then self.tab = tab end
    self.hintAge = 0
end

function MetaUI:DrawEntry(ctx, meta, challengeActive)
    local vg, w = ctx.vg, ctx.w
    local stars = (meta and meta.data and meta.data.stars) or 0
    local bw, bh, gap = 100, 36, 8
    local x = w - 12 - bw
    local growthY = 73
    local challengeY = growthY + bh + gap

    RoundRect(vg, x + 2, growthY + 3, bw, bh, 18, C.blood)
    RoundRect(vg, x, growthY, bw, bh, 18, C.mustard, 255, C.ink)
    Text(vg, ctx.selectBody, x + bw / 2, growthY + bh / 2 + 1,
        "成长 " .. stars, 13, C.ink, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    RoundRect(vg, x + 2, challengeY + 3, bw, bh, 18, C.blood)
    RoundRect(vg, x, challengeY, bw, bh, 18, challengeActive and C.ice or C.lavender, 255, C.ink)
    Text(vg, ctx.selectBody, x + bw / 2, challengeY + bh / 2 + 1,
        challengeActive and "挑战中" or "每日挑战", 13, C.ink, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    self.growthButton = { x = x, y = growthY, w = bw, h = bh }
    self.challengeButton = { x = x, y = challengeY, w = bw, h = bh }
    self.entryButton = self.growthButton

    if not self.open and self.hintAge and self.hintAge > 0 then
        local hintW, hintH = 176, 28
        local hintX = w - 12 - hintW
        local hintY = challengeY + bh + 8
        local pulse = 0.72 + 0.28 * math.abs(math.sin((self.hintAge or 0) * 3.2))
        RoundRect(vg, hintX, hintY, hintW, hintH, 14, C.ink, math.floor(230 * pulse))
        Text(vg, ctx.selectBody, hintX + hintW / 2, hintY + hintH / 2,
            "点这里看装扮和每日挑战", 11, C.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
end

local function Header(self,ctx,meta)
    local vg,w=ctx.vg,ctx.w
    RoundRect(vg,0,0,w,74,0,C.blood)
    Text(vg,ctx.selectBody,18,22,"成长中心",24,C.cream,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    Text(vg,ctx.selectBody,18,50,"★ "..meta.data.stars.."   旅程 Lv."..meta.data.journeyLevel,13,C.cream,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    RoundRect(vg,w-48,14,34,34,17,C.mustard,255,C.ink);Text(vg,ctx.selectBody,w-31,31,"×",23,C.ink,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    self.buttons[#self.buttons+1]={x=w-48,y=14,w=34,h=34,action="close"}
    local gap=5; local tabW=(w-20-gap*3)/4
    for i,id in ipairs(TAB_ORDER) do local x=10+(i-1)*(tabW+gap);local active=self.tab==id
        RoundRect(vg,x,80,tabW,35,10,active and C.mustard or C.cream,255,C.ink)
        Text(vg,ctx.selectBody,x+tabW/2,97,TAB_NAMES[id],11,active and C.ink or C.gray,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        self.buttons[#self.buttons+1]={x=x,y=80,w=tabW,h=35,action="tab",id=id}
    end
end

local function ActionButton(self,ctx,x,y,w,h,label,enabled,action,id)
    RoundRect(ctx.vg,x+2,y+3,w,h,12,C.blood,enabled and 255 or 80)
    RoundRect(ctx.vg,x,y,w,h,12,enabled and C.mustard or C.gray,255,C.ink)
    Text(ctx.vg,ctx.selectBody,x+w/2,y+h/2,label,11,enabled and C.ink or C.cream,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    if enabled then self.buttons[#self.buttons+1]={x=x,y=y,w=w,h=h,action=action,id=id} end
end

local function DrawWardrobe(self,ctx,meta)
    local vg,w=ctx.vg,ctx.w; local kinds=meta.CONFIG.kinds; local gap=4; local kw=(w-20-gap*4)/5
    for i,kind in ipairs(kinds) do local x=10+(i-1)*(kw+gap);local active=self.kind==kind
        RoundRect(vg,x,124,kw,30,9,active and C.teal or C.cream,255,C.ink)
        Text(vg,ctx.selectBody,x+kw/2,139,KIND_NAMES[kind],11,active and C.cream or C.ink,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
        self.buttons[#self.buttons+1]={x=x,y=124,w=kw,h=30,action="kind",id=kind}
    end
    local list=meta:Cosmetics(self.kind); local y=164
    for _,item in ipairs(list) do
        local h=60;RoundRect(vg,12,y,w-24,h,13,item.equipped and C.mint or C.cream,255,C.ink)
        Text(vg,ctx.selectBody,25,y+17,item.name,15,C.ink)
        local status=item.equipped and "使用中" or (item.unlocked and "已拥有" or (item.level and ("Lv."..item.level.."解锁") or ("★ "..item.price)))
        Text(vg,ctx.selectBody,25,y+41,item.rarity.." · "..status,10,C.gray)
        if not item.equipped then ActionButton(self,ctx,w-92,y+13,66,34,item.unlocked and "装备" or "获取",(not item.level or meta.data.journeyLevel>=item.level),"cosmetic",item.id) end
        y=y+h+7
    end
end

local function DrawAchievements(self,ctx,meta)
    local list=meta:Achievements();local w=ctx.w;local y=126
    for _,item in ipairs(list) do
        local h=48;RoundRect(ctx.vg,12,y,w-24,h,11,item.claimed and C.gray or (item.completed and C.mint or C.cream),item.claimed and 120 or 255,C.ink)
        Text(ctx.vg,ctx.selectBody,23,y+15,item.name.."  ★"..item.reward,13,C.ink)
        Text(ctx.vg,ctx.selectBody,23,y+35,item.description.."  "..ShortProgress(item.progress,item.target),10,C.gray)
        if item.completed and not item.claimed then ActionButton(self,ctx,w-78,y+9,54,30,"领取",true,"achievement",item.id) end
        y=y+h+5
    end
end

local function DrawMissions(self,ctx,meta)
    local daily=meta.data.daily;local w=ctx.w;local y=126
    Text(ctx.vg,ctx.selectBody,16,y,"今日任务 · 全部领取再得 ★"..meta.CONFIG.dailyChestReward,13,C.ink);y=y+25
    for _,m in ipairs(daily.missions) do
        local h=62;RoundRect(ctx.vg,12,y,w-24,h,12,m.claimed and C.gray or (m.completed and C.mint or C.cream),m.claimed and 120 or 255,C.ink)
        Text(ctx.vg,ctx.selectBody,23,y+18,m.label,13,C.ink)
        Text(ctx.vg,ctx.selectBody,23,y+43,ShortProgress(m.progress,m.target).."   奖励 ★"..m.reward,11,C.gray)
        if m.completed and not m.claimed then ActionButton(self,ctx,w-78,y+14,54,32,"领取",true,"mission",m.id) end
        y=y+h+7
    end
    local chest=daily.chestClaimed and "今日宝箱已领取" or "完成并领取全部任务可开宝箱"
    Text(ctx.vg,ctx.selectBody,w/2,y+14,chest,12,daily.chestClaimed and C.mint or C.gray,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
end

local function DrawChallenge(self,ctx,meta,challengeActive)
    local vg,w=ctx.vg,ctx.w;local c=meta.data.daily.challenge
    RoundRect(vg,15,130,w-30,188,18,C.ice,255,C.ink)
    Text(vg,ctx.selectBody,w/2,160,"❄ 寒冰连发",28,C.ink,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    Text(vg,ctx.selectBody,w/2,198,"每发射 5 次，冻结 1 个安全区方块",13,C.ink,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    Text(vg,ctx.selectBody,w/2,224,"同值合成可破冰 · 达到 4000 分通关",13,C.ink,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    Text(vg,ctx.selectBody,w/2,257,"今日最佳 "..(c.bestScore or 0).." / "..meta.CONFIG.dailyChallengeTarget,16,C.blood,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    Text(vg,ctx.selectBody,w/2,284,(c.completed and "今日已完成" or ("奖励 ★"..meta.CONFIG.dailyChallengeReward)),14,c.completed and C.teal or C.ink,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    ActionButton(self,ctx,(w-190)/2,338,190,46,challengeActive and "返回普通模式" or "开始今日挑战",true,challengeActive and "normal_mode" or "start_challenge")
    RoundRect(vg,28,410,w-56,116,14,C.cream,255,C.ink)
    Text(vg,ctx.selectBody,43,433,"本日挑战统计",16,C.ink)
    Text(vg,ctx.selectBody,43,461,"五连进度  "..(c.launchProgress or 0).." / 5",13,C.gray)
    Text(vg,ctx.selectBody,43,487,"累计冻结  "..(c.freezesTriggered or 0).."    破冰  "..(c.thaws or 0),13,C.gray)
end

function MetaUI:Draw(ctx,meta,challengeActive)
    self.buttons={};self:DrawEntry(ctx,meta,challengeActive);if not self.open then return end
    nvgBeginPath(ctx.vg);nvgRect(ctx.vg,0,0,ctx.w,ctx.h);nvgFillColor(ctx.vg,Color(C.ink,225));nvgFill(ctx.vg)
    RoundRect(ctx.vg,5,5,ctx.w-10,ctx.h-10,20,C.cream,255,C.ink);Header(self,ctx,meta)
    if self.tab=="wardrobe" then DrawWardrobe(self,ctx,meta)
    elseif self.tab=="achievements" then DrawAchievements(self,ctx,meta)
    elseif self.tab=="missions" then DrawMissions(self,ctx,meta)
    else DrawChallenge(self,ctx,meta,challengeActive) end
    if self.toast then RoundRect(ctx.vg,30,ctx.h-58,ctx.w-60,38,19,C.ink,235);Text(ctx.vg,ctx.selectBody,ctx.w/2,ctx.h-39,self.toast,12,C.cream,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE) end
end

function MetaUI:HandleTap(x,y,meta,callbacks)
    if not self.open then
        if Inside(x, y, self.challengeButton) then
            self:Open("challenge")
            return true
        end
        if Inside(x, y, self.growthButton) or Inside(x, y, self.entryButton) then
            self:Open("wardrobe")
            return true
        end
        return false
    end
    for i=#self.buttons,1,-1 do local b=self.buttons[i];if Inside(x,y,b) then
        if b.action=="close" then self:Close()
        elseif b.action=="tab" then self.tab=b.id
        elseif b.action=="kind" then self.kind=b.id
        elseif b.action=="achievement" then self:SetToast(meta:ClaimAchievement(b.id) and "成就奖励已领取" or "暂不可领取")
        elseif b.action=="mission" then self:SetToast(meta:ClaimMission(b.id) and "任务奖励已领取" or "暂不可领取")
        elseif b.action=="cosmetic" then local ok,reason=meta:PurchaseOrEquip(b.id);self:SetToast(ok and "装扮已启用" or (reason=="stars" and "星星不足" or "旅程等级不足"))
        elseif b.action=="start_challenge" and callbacks.startChallenge then self:Close();callbacks.startChallenge()
        elseif b.action=="normal_mode" and callbacks.normalMode then self:Close();callbacks.normalMode() end
        return true
    end end
    return true
end

return MetaUI
