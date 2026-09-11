local Widget = require("urhox-libs/UI/Core/Widget")
local UI = require("urhox-libs/UI/Core/UI")

local Spine = Widget:Extend("Spine")

function Spine:Init(props)
    props = props or {}
    props.loop = props.loop ~= false
    props.speed = props.speed or 1.0
    props.defaultMix = props.defaultMix or 0.1
    props.objectFit = props.objectFit or "contain"

    self.spineInstance_ = nil

    Widget.Init(self, props)

    if props.src then
        self:LoadSpine(props.src)
    end
end

function Spine:LoadSpine(path)
    self:UnloadSpine()

    local nvg = UI.GetNVGContext()
    if not nvg then return false end

    self.spineInstance_ = nvgSpineCreate(nvg)
    if not self.spineInstance_ then return false end

    if not self.spineInstance_:Load(path) then
        self:UnloadSpine()
        return false
    end

    if self.props.pma ~= nil then
        self.spineInstance_:SetPremultipliedAlpha(self.props.pma)
    end
    self.spineInstance_:SetDefaultMix(self.props.defaultMix)
    self.spineInstance_:SetSpeed(self.props.speed)

    if self.props.skin then self.spineInstance_:SetSkin(self.props.skin) end

    if self.props.animation then
        self:SetAnimation(self.props.animation, self.props.loop)
    end

    return true
end

function Spine:UnloadSpine()
    if self.spineInstance_ then
        self.spineInstance_:Unload()
        self.spineInstance_ = nil
    end
end

function Spine:Destroy()
    self:UnloadSpine()
    Widget.Destroy(self)
end

function Spine:Update(dt)
    if self.spineInstance_ and self.spineInstance_:IsLoaded() then
        self.spineInstance_:Update(dt)
    end
end

function Spine:Render(nvg)
    self:RenderFullBackground(nvg)

    if not self.spineInstance_ or not self.spineInstance_:IsLoaded() then
        return
    end

    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end

    local dataW = self.spineInstance_:GetDataWidth()
    local dataH = self.spineInstance_:GetDataHeight()
    local dataX = self.spineInstance_:GetDataX()
    local dataY = self.spineInstance_:GetDataY()

    local flipX = self.props.flipX and true or false
    local flipY = true  -- Spine Y-up → screen Y-down

    if dataW > 0 and dataH > 0 then
        local scaleX = l.w / dataW
        local scaleY = l.h / dataH
        local fit = self.props.objectFit

        if fit == "fill" then
            -- non-uniform, keep separate scaleX/scaleY
        elseif fit == "cover" then
            local scale = math.max(scaleX, scaleY)
            scaleX = scale
            scaleY = scale
        else -- "contain"
            local scale = math.min(scaleX, scaleY)
            scaleX = scale
            scaleY = scale
        end

        -- Spine skeleton root position = where bone (0,0) maps to in screen space
        -- SCE reference: skeleton.setScaleY(-scaleY) for Y flip,
        -- then position accounts for data bounds offset
        local sx = scaleX * (flipX and -1 or 1)
        local sy = scaleY * (flipY and -1 or 1)
        self.spineInstance_:SetScale(sx, sy)

        -- Center the rendered skeleton within the widget
        local drawW = dataW * scaleX
        local drawH = dataH * scaleY
        local cx = l.x + (l.w - drawW) * 0.5
        local cy = l.y + (l.h - drawH) * 0.5

        -- Skeleton position: offset from widget corner to skeleton origin
        local x = cx + (flipX and (dataW + dataX) or (-dataX)) * scaleX
        local y = cy + (flipY and (dataH + dataY) or (-dataY)) * scaleY
        self.spineInstance_:SetPosition(x, y)
    else
        self.spineInstance_:SetPosition(l.x + l.w * 0.5, l.y + l.h * 0.5)
    end

    nvgSpineRender(nvg, self.spineInstance_)
end

--- Set the current animation on a track, replacing any queued animations.
---@overload fun(self: Spine, name: string, loop?: boolean): Spine
---@overload fun(self: Spine, trackIndex: number, name: string, loop?: boolean): Spine
---@param trackOrName number|string Track index (0-based) or animation name
---@param nameOrLoop string|boolean Animation name (if track given) or loop flag
---@param loopOrNil boolean|nil Loop flag (if track given)
---@return Spine self
function Spine:SetAnimation(trackOrName, nameOrLoop, loopOrNil)
    local track, name, loop
    if type(trackOrName) == "number" then
        track = trackOrName
        name = nameOrLoop
        loop = loopOrNil ~= false
    else
        track = 0
        name = trackOrName
        loop = nameOrLoop ~= false
    end
    if self.spineInstance_ and self.spineInstance_:IsLoaded() then
        self.spineInstance_:SetAnimation(track, name, loop)
    end
    return self
end

--- Queue an animation to play after the current one finishes.
---@overload fun(self: Spine, name: string, loop?: boolean, delay?: number): Spine
---@overload fun(self: Spine, trackIndex: number, name: string, loop?: boolean, delay?: number): Spine
---@param trackOrName number|string Track index (0-based) or animation name
---@param nameOrLoop string|boolean Animation name (if track given) or loop flag
---@param loopOrDelay boolean|number Loop flag (if track given) or delay in seconds
---@param delayOrNil number|nil Delay in seconds (if track given)
---@return Spine self
function Spine:AddAnimation(trackOrName, nameOrLoop, loopOrDelay, delayOrNil)
    local track, name, loop, delay
    if type(trackOrName) == "number" then
        track = trackOrName
        name = nameOrLoop
        loop = loopOrDelay ~= false
        delay = delayOrNil or 0
    else
        track = 0
        name = trackOrName
        loop = nameOrLoop ~= false
        delay = loopOrDelay or 0
    end
    if self.spineInstance_ and self.spineInstance_:IsLoaded() then
        self.spineInstance_:AddAnimation(track, name, loop, delay)
    end
    return self
end

function Spine:ClearTrack(trackIndex)
    if self.spineInstance_ then self.spineInstance_:ClearTrack(trackIndex) end
    return self
end

function Spine:ClearTracks()
    if self.spineInstance_ then self.spineInstance_:ClearTracks() end
    return self
end

function Spine:Stop()
    return self:ClearTracks()
end

function Spine:SetSkin(name)
    self.props.skin = name
    if self.spineInstance_ then self.spineInstance_:SetSkin(name or "") end
    return self
end

function Spine:SetSpeed(speed)
    self.props.speed = speed
    if self.spineInstance_ then self.spineInstance_:SetSpeed(speed) end
    return self
end

function Spine:SetSrc(src)
    if src ~= self.props.src then
        self.props.src = src
        self:LoadSpine(src)
    end
    return self
end

function Spine:SetAttachment(slotName, attachmentName)
    if self.spineInstance_ then self.spineInstance_:SetAttachment(slotName, attachmentName) end
    return self
end

function Spine:SetMix(fromAnim, toAnim, duration)
    if self.spineInstance_ then self.spineInstance_:SetMix(fromAnim, toAnim, duration) end
    return self
end

function Spine:SetEmptyAnimation(trackIndex, mixDuration)
    if self.spineInstance_ then self.spineInstance_:SetEmptyAnimation(trackIndex, mixDuration or 0) end
    return self
end

function Spine:AddEmptyAnimation(trackIndex, mixDuration, delay)
    if self.spineInstance_ then self.spineInstance_:AddEmptyAnimation(trackIndex, mixDuration or 0, delay or 0) end
    return self
end

function Spine:SetToSetupPose()
    if self.spineInstance_ then self.spineInstance_:SetToSetupPose() end
    return self
end

function Spine:SetBonesToSetupPose()
    if self.spineInstance_ then self.spineInstance_:SetBonesToSetupPose() end
    return self
end

function Spine:SetSlotsToSetupPose()
    if self.spineInstance_ then self.spineInstance_:SetSlotsToSetupPose() end
    return self
end

function Spine:SetTimeScale(timeScale)
    if self.spineInstance_ then self.spineInstance_:SetTimeScale(timeScale) end
    return self
end

function Spine:GetTimeScale()
    if self.spineInstance_ then return self.spineInstance_:GetTimeScale() end
    return 1.0
end

function Spine:SetColor(r, g, b, a)
    if self.spineInstance_ then self.spineInstance_:SetColor(r, g, b, a ~= nil and a or 1) end
    return self
end

function Spine:GetColor()
    if self.spineInstance_ then return self.spineInstance_:GetColor() end
    return 1, 1, 1, 1
end

function Spine:SetTrackAlpha(trackIndex, alpha)
    if self.spineInstance_ then self.spineInstance_:SetTrackAlpha(trackIndex, alpha) end
    return self
end

function Spine:GetTrackAlpha(trackIndex)
    if self.spineInstance_ then return self.spineInstance_:GetTrackAlpha(trackIndex or 0) end
    return 1.0
end

function Spine:GetAnimationNames()
    if self.spineInstance_ then return self.spineInstance_:GetAnimationNames() end
    return {}
end

function Spine:GetSkinNames()
    if self.spineInstance_ then return self.spineInstance_:GetSkinNames() end
    return {}
end

function Spine:GetBoneNames()
    if self.spineInstance_ then return self.spineInstance_:GetBoneNames() end
    return {}
end

function Spine:GetSlotNames()
    if self.spineInstance_ then return self.spineInstance_:GetSlotNames() end
    return {}
end

function Spine:IsLoaded()
    return self.spineInstance_ and self.spineInstance_:IsLoaded() or false
end

function Spine:IsAnimationComplete(trackIndex)
    if self.spineInstance_ then return self.spineInstance_:IsAnimationComplete(trackIndex or 0) end
    return true
end

function Spine:GetTrackTime(trackIndex)
    if self.spineInstance_ then return self.spineInstance_:GetTrackTime(trackIndex or 0) end
    return 0
end

function Spine:GetAnimationDuration(trackIndex)
    if self.spineInstance_ then return self.spineInstance_:GetAnimationDuration(trackIndex or 0) end
    return 0
end

function Spine:SetCompleteListener(fn)
    if self.spineInstance_ then self.spineInstance_:SetCompleteListener(fn) end
    return self
end

function Spine:SetStartListener(fn)
    if self.spineInstance_ then self.spineInstance_:SetStartListener(fn) end
    return self
end

function Spine:SetEndListener(fn)
    if self.spineInstance_ then self.spineInstance_:SetEndListener(fn) end
    return self
end

function Spine:SetEventListener(fn)
    if self.spineInstance_ then self.spineInstance_:SetEventListener(fn) end
    return self
end

function Spine:SetDisposeListener(fn)
    if self.spineInstance_ then self.spineInstance_:SetDisposeListener(fn) end
    return self
end

function Spine:SetPremultipliedAlpha(pma)
    self.props.pma = pma
    if self.spineInstance_ then self.spineInstance_:SetPremultipliedAlpha(pma) end
    return self
end

function Spine:UpdateWorldTransform()
    if self.spineInstance_ then self.spineInstance_:UpdateWorldTransform() end
    return self
end

function Spine:FindBone(name)
    if self.spineInstance_ then
        return self.spineInstance_:FindBone(name)
    end
    return nil
end

function Spine:FindSlot(name)
    if self.spineInstance_ then
        return self.spineInstance_:FindSlot(name)
    end
    return nil
end

function Spine:LocalToSkeleton(localX, localY)
    if not self.spineInstance_ or not self.spineInstance_:IsLoaded() then
        return 0, 0
    end

    local l = self:GetAbsoluteLayout()
    local dataW = self.spineInstance_:GetDataWidth()
    local dataH = self.spineInstance_:GetDataHeight()
    local dataX = self.spineInstance_:GetDataX()
    local dataY = self.spineInstance_:GetDataY()

    if dataW <= 0 or dataH <= 0 then return 0, 0 end

    local scaleX = l.w / dataW
    local scaleY = l.h / dataH
    local fit = self.props.objectFit
    if fit == "cover" then
        local s = math.max(scaleX, scaleY); scaleX = s; scaleY = s
    elseif fit ~= "fill" then
        local s = math.min(scaleX, scaleY); scaleX = s; scaleY = s
    end

    local flipX = self.props.flipX and true or false
    local drawW = dataW * scaleX
    local drawH = dataH * scaleY
    local offsetX = (l.w - drawW) * 0.5
    local offsetY = (l.h - drawH) * 0.5

    local originX = offsetX + (flipX and (dataW + dataX) or (-dataX)) * scaleX
    local originY = offsetY + (dataH + dataY) * scaleY

    local sx = flipX and -1 or 1
    local sy = -1
    return (localX - originX) / (scaleX * sx), (localY - originY) / (scaleY * sy)
end

function Spine:ScreenToSkeleton(screenX, screenY)
    if not self.spineInstance_ or not self.spineInstance_:IsLoaded() then
        return 0, 0
    end

    local l = self:GetAbsoluteLayoutForHitTest()
    local dataW = self.spineInstance_:GetDataWidth()
    local dataH = self.spineInstance_:GetDataHeight()
    local dataX = self.spineInstance_:GetDataX()
    local dataY = self.spineInstance_:GetDataY()

    if dataW <= 0 or dataH <= 0 then return 0, 0 end

    local scaleX = l.w / dataW
    local scaleY = l.h / dataH
    local fit = self.props.objectFit
    if fit == "cover" then
        local s = math.max(scaleX, scaleY); scaleX = s; scaleY = s
    elseif fit ~= "fill" then
        local s = math.min(scaleX, scaleY); scaleX = s; scaleY = s
    end

    local drawW = dataW * scaleX
    local drawH = dataH * scaleY
    local cx = l.x + (l.w - drawW) * 0.5
    local cy = l.y + (l.h - drawH) * 0.5

    local flipX = self.props.flipX and true or false

    local originX = cx + (flipX and (dataW + dataX) or (-dataX)) * scaleX
    local originY = cy + (dataH + dataY) * scaleY

    local sxSign = flipX and -1 or 1
    return (screenX - originX) / (scaleX * sxSign), (screenY - originY) / (-scaleY)
end

return Spine
