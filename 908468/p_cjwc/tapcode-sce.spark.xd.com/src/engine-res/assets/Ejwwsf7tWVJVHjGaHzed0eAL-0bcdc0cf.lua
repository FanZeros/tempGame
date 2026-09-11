-- Effects.lua
-- 粒子特效和音效辅助函数
-- 来源：从 Sample2D.lua 提取并改进

---@class Effects
local Effects = {}

-- 内部定时器管理
---@type {node: Node, delay: number, elapsed: number}[]
local activeTimers = {}

---内部函数：处理节点延迟删除
---@private
function Effects_HandleRemoveTimer(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()

    -- 遍历所有活动的定时器
    for i = #activeTimers, 1, -1 do
        local timer = activeTimers[i]
        if timer.node and timer.node:GetID() ~= 0 then
            timer.elapsed = timer.elapsed + timeStep

            if timer.elapsed >= timer.delay then
                -- 时间到,删除节点
                timer.node:Remove()
                table.remove(activeTimers, i)
            end
        else
            -- 节点已被删除,清理定时器
            table.remove(activeTimers, i)
        end
    end

    -- 如果没有活动定时器了,取消订阅
    if #activeTimers == 0 then
        UnsubscribeFromEvent("SceneUpdate")
    end
end

---延迟删除节点
---@param node Node 要删除的节点
---@param delay number 延迟时间(秒)
function Effects.RemoveNodeAfter(node, delay)
    if not node or delay <= 0 then
        return
    end

    -- 添加到定时器列表
    table.insert(activeTimers, {
        node = node,
        delay = delay,
        elapsed = 0
    })

    -- 确保订阅了更新事件
    if #activeTimers == 1 then
        SubscribeToEvent("SceneUpdate", "Effects_HandleRemoveTimer")
    end
end

---在节点上创建粒子特效
---@param scene Scene 场景对象
---@param parentNode Node 父节点
---@param effectPath string 粒子特效文件路径（.pex）
---@param options? {scale?: number, offset?: Vector2, duration?: number} 可选配置
---@return Node|nil 粒子节点
function Effects.SpawnParticle(scene, parentNode, effectPath, options)
    options = options or {}

    if not scene then
        log:Write(LOG_ERROR, "Effects.SpawnParticle: Invalid scene")
        return nil
    end

    if not parentNode then
        log:Write(LOG_ERROR, "Effects.SpawnParticle: Invalid parent node")
        return nil
    end

    -- 创建粒子节点
    local particleNode = parentNode:CreateChild("ParticleEmitter")

    -- 设置缩放（避免受父节点缩放影响）
    local scale = options.scale or 0.5
    if parentNode.scale.x ~= 0 then
        particleNode:SetScale(scale / parentNode.scale.x)
    else
        log:Write(LOG_WARNING, "Effects.SpawnParticle: Parent node scale.x is 0, using default scale")
        particleNode:SetScale(scale)
    end

    -- 设置位置偏移
    if options.offset then
        particleNode.position2D = options.offset
    end

    -- 创建粒子发射器组件
    local particleEmitter = particleNode:CreateComponent("ParticleEmitter2D")

    -- 加载粒子特效
    local effect = cache:GetResource("ParticleEffect2D", effectPath)
    if effect then
        particleEmitter.effect = effect
    else
        log:Write(LOG_WARNING, "Effects.SpawnParticle: Cannot load effect: " .. effectPath)
    end

    -- 自动删除（如果指定了duration）
    if options.duration and options.duration > 0 then
        Effects.RemoveNodeAfter(particleNode, options.duration)
    end

    return particleNode
end

---播放音效（非循环）
---@param scene Scene 场景对象
---@param soundPath string 音效文件路径
---@param options? {gain?: number, frequency?: number, position?: Vector3, autoRemove?: boolean} 可选配置
---@return {node: Node, source: SoundSource, Stop: fun(), FadeOut: fun(duration?: number)}|nil 音效句柄
function Effects.PlaySound(scene, soundPath, options)
    options = options or {}

    if not scene then
        log:Write(LOG_ERROR, "Effects.PlaySound: Invalid scene")
        return nil
    end

    -- 创建音效节点
    local soundNode = scene:CreateChild("Sound")

    -- 设置位置（3D 音效）
    if options.position then
        soundNode.position = options.position
    end

    -- 创建音源组件
    local source = soundNode:CreateComponent("SoundSource")

    -- 加载音效
    local sound = cache:GetResource("Sound", soundPath)
    if not sound then
        log:Write(LOG_WARNING, "Effects.PlaySound: Cannot load sound: " .. soundPath)
        soundNode:Remove()
        return nil
    end

    -- 设置音量和频率
    if options.gain then
        source.gain = options.gain
    end
    if options.frequency then
        source.frequency = options.frequency
    end

    -- 播放音效
    source:Play(sound)

    -- 自动删除（默认在音效播放完后删除）
    local autoRemove = options.autoRemove
    if autoRemove == nil then
        autoRemove = true  -- 默认自动删除
    end

    if autoRemove and sound.length > 0 then
        Effects.RemoveNodeAfter(soundNode, sound.length + 0.1)
    end

    -- 返回统一的句柄
    local handle = {
        node = soundNode,
        source = source
    }

    -- 提供便捷方法
    function handle:Stop()
        if self.source then
            self.source:Stop()
        end
        if self.node then
            self.node:Remove()
        end
    end

    function handle:FadeOut(duration)
        Effects.FadeOutSound(self, duration, true)
    end

    return handle
end

---播放循环音效（背景音乐等）
---@param scene Scene 场景对象
---@param soundPath string 音效文件路径
---@param options? {gain?: number, frequency?: number, position?: Vector3, soundType?: number} 可选配置
---@return {node: Node, source: SoundSource, Stop: fun(), FadeIn: fun(duration?: number, targetGain?: number), FadeOut: fun(duration?: number, removeAfter?: boolean)}|nil 音效句柄
function Effects.PlaySoundLooped(scene, soundPath, options)
    options = options or {}

    if not scene then
        log:Write(LOG_ERROR, "Effects.PlaySoundLooped: Invalid scene")
        return nil
    end

    -- 创建音效节点
    local soundNode = scene:CreateChild("LoopedSound")

    -- 设置位置（3D 音效）
    if options.position then
        soundNode.position = options.position
    end

    -- 创建音源组件
    local source = soundNode:CreateComponent("SoundSource")
    source.soundType = options.soundType or SOUND_EFFECT

    -- 加载音效
    local sound = cache:GetResource("Sound", soundPath)
    if not sound then
        log:Write(LOG_WARNING, "Effects.PlaySoundLooped: Cannot load sound: " .. soundPath)
        soundNode:Remove()
        return nil
    end

    -- 设置循环
    sound.looped = true

    -- 设置音量和频率
    if options.gain then
        source.gain = options.gain
    end
    if options.frequency then
        source.frequency = options.frequency
    end

    -- 播放音效
    source:Play(sound)

    -- 返回统一的句柄
    local handle = {
        node = soundNode,
        source = source
    }

    -- 提供便捷方法
    function handle:Stop()
        if self.source then
            self.source:Stop()
        end
        if self.node then
            self.node:Remove()
        end
    end

    function handle:FadeIn(duration, targetGain)
        Effects.FadeInSound(self, duration, targetGain)
    end

    function handle:FadeOut(duration, removeAfter)
        Effects.FadeOutSound(self, duration, removeAfter)
    end

    return handle
end

---停止音效（兼容旧API）
---@param soundHandle table 音效句柄
---@deprecated 请使用 soundHandle:Stop() 代替
function Effects.StopSound(soundHandle)
    if soundHandle and soundHandle.Stop then
        soundHandle:Stop()
    end
end

---淡入音效
---@param soundHandle table 音效句柄
---@param duration number 淡入时间（秒）
---@param targetGain number 目标音量
function Effects.FadeInSound(soundHandle, duration, targetGain)
    if not soundHandle or not soundHandle.source then
        log:Write(LOG_WARNING, "Effects.FadeInSound: Invalid sound handle")
        return
    end

    targetGain = targetGain or 1.0
    duration = duration or 1.0

    -- 从 0 开始
    soundHandle.source.gain = 0

    -- 创建音量动画
    local animation = ValueAnimation:new()
    animation:SetKeyFrame(0, Variant(0.0))
    animation:SetKeyFrame(duration, Variant(targetGain))

    soundHandle.source:SetAttributeAnimation("Gain", animation, WM_ONCE, 1.0)
end

---淡出音效
---@param soundHandle table 音效句柄
---@param duration number 淡出时间（秒）
---@param removeAfter boolean 淡出后是否移除
function Effects.FadeOutSound(soundHandle, duration, removeAfter)
    if not soundHandle or not soundHandle.source then
        log:Write(LOG_WARNING, "Effects.FadeOutSound: Invalid sound handle")
        return
    end

    duration = duration or 1.0
    local currentGain = soundHandle.source.gain

    -- 创建音量动画
    local animation = ValueAnimation:new()
    animation:SetKeyFrame(0, Variant(currentGain))
    animation:SetKeyFrame(duration, Variant(0.0))

    soundHandle.source:SetAttributeAnimation("Gain", animation, WM_ONCE, 1.0)

    -- 淡出后自动移除
    if removeAfter then
        Effects.RemoveNodeAfter(soundHandle.node, duration + 0.1)
    end
end

---创建屏幕震动效果
---@param cameraNode Node 相机节点
---@param intensity number 震动强度
---@param duration number 持续时间
---@return table 震动控制器 { Update() }
function Effects.CreateScreenShake(cameraNode, intensity, duration)
    if not cameraNode then
        log:Write(LOG_ERROR, "Effects.CreateScreenShake: Invalid camera node")
        return nil
    end

    duration = duration or 0.5
    if duration <= 0 then
        log:Write(LOG_WARNING, "Effects.CreateScreenShake: Invalid duration (" .. duration .. "), using default 0.5")
        duration = 0.5
    end

    local shake = {
        cameraNode = cameraNode,
        originalPosition = Vector3(cameraNode.position),
        intensity = intensity or 0.1,
        duration = duration,
        elapsed = 0,
        active = true
    }

    function shake:Update(timeStep)
        if not self.active then
            return false
        end

        self.elapsed = self.elapsed + timeStep

        if self.elapsed >= self.duration then
            -- 恢复原始位置
            self.cameraNode.position = self.originalPosition
            self.active = false
            return false
        end

        -- 计算衰减
        local progress = self.elapsed / self.duration
        local currentIntensity = self.intensity * (1 - progress)

        -- 随机偏移
        local offsetX = (Random() - 0.5) * 2 * currentIntensity
        local offsetY = (Random() - 0.5) * 2 * currentIntensity

        self.cameraNode.position = self.originalPosition + Vector3(offsetX, offsetY, 0)

        return true
    end

    return shake
end

return Effects
