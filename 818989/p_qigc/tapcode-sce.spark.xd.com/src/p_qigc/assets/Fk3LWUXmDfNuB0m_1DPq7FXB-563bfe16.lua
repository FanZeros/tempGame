-- ============================================================
-- Renderer_Panels.lua  —— UI 面板（角色 / 属性汇总 / 背包 / 技能 / 日志 / 地图）
-- 由 Renderer.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================
local GS = require("GameState")
local Utils = require("Renderer_Utils")
local drawTextOutlined = Utils.drawTextOutlined
local isHovered        = Utils.isHovered
local drawHoverHighlight = Utils.drawHoverHighlight
local fmtNum           = Utils.fmtNum


local sub = {}

function sub.init(M)


-- ====================================================================
-- 面板内容：角色信息（Tab 1）—— 装备槽 + 属性汇总按钮
-- ====================================================================
function M.drawCharacterPanel(cx, cy, cw, ch)
    local vg = M.vg
    local p = GS.player
    if not p then return end

    nvgFontFace(vg, "sans")

    -- 布局参数
    local pad = 6
    local btnH = 0               -- 不再有底部按钮
    local avatarSize = 0         -- 角色头像尺寸（如有图标）
    local topInfoH = 0           -- 顶部信息区高度
    local mx, my = GS.hoverX or 0, GS.hoverY or 0

    -- 顶部：名称 + 等级
    local infoY = cy + pad
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local lvText = (p.name or "战士") .. "  Lv." .. (p.level or 1)
    drawTextOutlined(vg, cx + pad, infoY + 8, lvText, 55, 30, 10, 255)

    -- 测量等级文字宽度
    nvgFontSize(vg, 12)
    local lvTextW = nvgTextBounds(vg, 0, 0, lvText, nil, nil)

    -- "增益&减益状态效果" 按钮（紧跟等级文字后）
    do
        local btnLabel = "增益&减益状态效果"
        local btnFs = 9
        nvgFontSize(vg, btnFs)
        local btnTw = nvgTextBounds(vg, 0, 0, btnLabel, nil, nil)
        local btnPadX = 4
        local btnW = btnTw + btnPadX * 2
        local btnH2 = 14
        local btnX = cx + pad + lvTextW + 6
        local btnY = infoY + 8 - btnH2 / 2
        local btnHovered = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH2, 3)
        if GS.showBuffSummary then
            nvgFillColor(vg, nvgRGBA(80, 160, 60, 200))
        elseif btnHovered then
            nvgFillColor(vg, nvgRGBA(100, 80, 50, 200))
        else
            nvgFillColor(vg, nvgRGBA(70, 55, 35, 180))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(140, 120, 80, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, btnFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(230, 210, 170, 255))
        nvgText(vg, btnX + btnW / 2, btnY + btnH2 / 2, btnLabel, nil)

        GS.buffSummaryBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH2 }
        -- 调整 debuff 方块起始位置（在按钮之后）
        lvTextW = lvTextW + btnW + 10
    end

    -- 经验信息（右对齐）
    local curExp = math.floor(p.exp or 0)
    local needExp = GS.expToNextLevel(p.level or 1)
    local expText = "EXP " .. fmtNum(curExp) .. "/" .. fmtNum(needExp)
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    drawTextOutlined(vg, cx + cw - pad, infoY + 8, expText, 40, 25, 10, 200)
    topInfoH = 20

    -- 玩家 debuff 方块（等级文字后、经验值前，同一行）
    GS.debuffTooltip = nil
    local anyDebuffIconHovered = false
    local dbClicked = GS.leftClickThisFrame
    local debuffList = {}
    -- 收集 playerDebuffs 列表中的 debuff（麻痹/冻僵等）
    if #GS.playerDebuffs > 0 then
        local debuffSummary = {}
        for _, db in ipairs(GS.playerDebuffs) do
            local key = db.source or db.type
            if not debuffSummary[key] then
                debuffSummary[key] = { type = db.type, source = db.source or db.type, totalVal = 0, maxTurns = 0, stacks = 0 }
            end
            local s = debuffSummary[key]
            s.totalVal = s.totalVal + db.val
            s.maxTurns = math.max(s.maxTurns, db.turns)
            s.stacks = s.stacks + 1
        end
        for _, s in pairs(debuffSummary) do debuffList[#debuffList + 1] = s end
    end
    -- 收集凝视 debuff（存储在 player._unknownGaze）
    if p and (p._unknownGaze or 0) > 0 then
        debuffList[#debuffList + 1] = {
            type = "gaze", source = "gaze",
            totalVal = p._unknownGaze, maxTurns = 0, stacks = p._unknownGaze,
        }
    end
    if #debuffList > 0 then
        local iconSz = 14
        local gap = 3
        local rowMidY = infoY + 8
        local startX = cx + pad + lvTextW + 6  -- 紧跟等级文字

        for i, s in ipairs(debuffList) do
            local ix = startX + (i - 1) * (iconSz + gap)
            local iy = rowMidY - iconSz / 2
            local isElec = s.source == "elec"
            local isIce  = s.source == "ice"
            local isGaze = s.source == "gaze"
            local r, g, b = 200, 200, 200
            local label, name, desc = "?", "未知", ""
            if isElec then
                r, g, b = 240, 220, 60
                label = "麻"
                name = "麻痹"
                desc = "闪避-" .. s.totalVal .. " (" .. s.stacks .. "层)"
            elseif isIce then
                r, g, b = 100, 180, 240
                label = "僵"
                name = "冻僵"
                desc = "移速-" .. s.totalVal .. " (" .. s.stacks .. "层)"
            elseif isGaze then
                r, g, b = 180, 120, 255
                label = "凝"
                name = "不可知物的凝视"
                desc = "感知+" .. (p._gazePer or 0) .. " 专注+" .. (p._gazeFoc or 0) .. " (" .. s.stacks .. "层)"
            end

            nvgBeginPath(vg)
            nvgRect(vg, ix, iy, iconSz, iconSz)
            nvgFillColor(vg, nvgRGBA(r, g, b, 50))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(r, g, b, 180))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, iconSz * 0.65)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(r, g, b, 240))
            nvgText(vg, ix + iconSz / 2, iy + iconSz / 2, label, nil)

            if s.stacks > 1 then
                nvgFontSize(vg, iconSz * 0.4)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
                nvgText(vg, ix + iconSz - 1, iy + iconSz - 1, tostring(s.stacks), nil)
            end

            local isOver = mx >= ix and mx <= ix + iconSz and my >= iy and my <= iy + iconSz
            if isOver then
                anyDebuffIconHovered = true
                local tipData = { x = ix + iconSz / 2, y = iy, name = name, desc = desc, r = r, g = g, b = b }
                GS.debuffTooltip = tipData
                -- 点击/触摸：锁定 tooltip
                if dbClicked then
                    GS.lockedDebuffTooltip = tipData
                end
            end
        end
    end

    -- 点击/触摸锁定 tooltip 逻辑
    if GS.lockedDebuffTooltip then
        if dbClicked and not anyDebuffIconHovered then
            -- 点击了 debuff 图标以外的区域 → 解锁
            GS.lockedDebuffTooltip = nil
        else
            -- 锁定状态下优先显示锁定的 tooltip
            GS.debuffTooltip = GS.lockedDebuffTooltip
        end
    end
    -- debuff 全部消失时清除锁定
    if #debuffList == 0 then
        GS.lockedDebuffTooltip = nil
    end

    -- 分隔线
    local sepY = infoY + topInfoH + 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + 5, sepY)
    nvgLineTo(vg, cx + cw - 5, sepY)
    nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 内容区域
    local contentTop = sepY + 4
    local contentBottom = cy + ch - btnH - pad - 4
    local contentH = contentBottom - contentTop
    local dividerX = cx + math.floor(cw * 0.48) -- 左右分区线

    -- 共享的行高和标题区高度（左右两侧对齐）
    local statCount = #GS.STAT_DEFS
    local rowH = math.min(28, math.floor(contentH / (statCount + 2)))
    local headerH = rowH

    -- ========== 左侧：加点系统 ==========
    do
        local lx = cx + pad
        local lw = dividerX - lx - 4
        local statStartY = contentTop + headerH + 4

        -- 标题 "属性加点"
        nvgFontSize(vg, math.max(9, rowH * 0.45))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        drawTextOutlined(vg, lx, contentTop + headerH / 2, "属性加点", 60, 35, 10, 255)

        -- 可用点数
        local pts = (p.statPoints or 0)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if pts > 0 then
            drawTextOutlined(vg, lx + lw, contentTop + headerH / 2, "可用: " .. pts, 20, 120, 20, 255)
        else
            drawTextOutlined(vg, lx + lw, contentTop + headerH / 2, "可用: " .. pts, 120, 100, 75, 180)
        end

        -- 分隔细线
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx, contentTop + headerH + 1)
        nvgLineTo(vg, lx + lw, contentTop + headerH + 1)
        nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 90))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        GS.statAddBtnRects = {}
        local btnSize = math.max(12, rowH - 6)
        local eb = GS.getEquipBonus()
        local rankBonus = GS.getAdventurerRankBonus()

        -- 收集勿忘我/食物/药水对基础属性的额外加成
        local buffBonus = { str = 0, agi = 0, con = 0, wis = 0, foc = 0, per = 0, wil = 0, luk = 0, cha = 0 }
        -- 勿忘我: 力量+(1+lv), 专注+(1+lv), 智慧+(1+lv) — 永久效果或临时buff
        local fmnActive = GS.forgetMeNotPermanent
            or (GS.forgetMeNotBuff and GS.forgetMeNotBuff.active
                and (not GS.forgetMeNotBuff.expireTime or GS.weatherTime < GS.forgetMeNotBuff.expireTime))
        if fmnActive then
            local fmnVal = 1 + (GS.forgetMeNotLevel or 0)
            buffBonus.str = buffBonus.str + fmnVal
            buffBonus.foc = buffBonus.foc + fmnVal
            buffBonus.wis = buffBonus.wis + fmnVal
        end
        -- 精神抖擞: 全属性+1
        if GS.hugBuff and GS.hugBuff.active
           and (not GS.hugBuff.expireTime or GS.weatherTime < GS.hugBuff.expireTime) then
            buffBonus.str = buffBonus.str + 1
            buffBonus.agi = buffBonus.agi + 1
            buffBonus.con = buffBonus.con + 1
            buffBonus.wis = buffBonus.wis + 1
            buffBonus.foc = buffBonus.foc + 1
            buffBonus.per = buffBonus.per + 1
            buffBonus.wil = buffBonus.wil + 1
            buffBonus.luk = buffBonus.luk + 1
            buffBonus.cha = buffBonus.cha + 1
        end
        -- 食物buff
        if GS.foodBuff and (not GS.foodBuff.expireTime or GS.weatherTime < GS.foodBuff.expireTime) then
            local fb = GS.foodBuff
            buffBonus.str = buffBonus.str + (fb.str or 0)
            buffBonus.foc = buffBonus.foc + (fb.foc or 0)
            buffBonus.wis = buffBonus.wis + (fb.wis or 0)
            buffBonus.con = buffBonus.con + (fb.con or 0)
            buffBonus.agi = buffBonus.agi + (fb.agi or 0)
            buffBonus.per = buffBonus.per + (fb.per or 0)
            buffBonus.wil = buffBonus.wil + (fb.wil or 0)
            buffBonus.luk = buffBonus.luk + (fb.luk or 0)
        end
        -- 药水buff（仅影响基础属性的部分）
        if GS.potionBuffs then
            for stat, buff in pairs(GS.potionBuffs) do
                if buff.expireTime and GS.weatherTime <= buff.expireTime then
                    local key = stat:sub(6)  -- "buff_str" -> "str"
                    if buffBonus[key] ~= nil and not buff.isPercent then
                        buffBonus[key] = buffBonus[key] + (buff.amount or 0)
                    end
                end
            end
        end

        -- 六维属性对应的装备加成键
        local statBonusKeys = { str = "str", agi = "agi", con = "con", wis = "wis", foc = "foc", per = "per", wil = "wil", luk = "luk", cha = "cha" }

        GS.statInfoBtnRects = {}
        -- 悬停检测（非锁定时，每帧更新）
        if not GS.statInfoLocked then
            GS.statInfoHover = nil
        end

        for i, def in ipairs(GS.STAT_DEFS) do
            local ry = statStartY + (i - 1) * rowH
            local val = p.stats[def.key] or 0
            local equipBonus = (eb[statBonusKeys[def.key]] or 0) + rankBonus + (buffBonus[def.key] or 0)
            -- 凝视加成（不可知物）
            if def.key == "per" then equipBonus = equipBonus + (p._gazePer or 0) end
            if def.key == "foc" then equipBonus = equipBonus + (p._gazeFoc or 0) end
            local atCap = (val >= 100)

            -- 属性名
            local fSize = math.max(8, rowH * 0.42)
            nvgFontSize(vg, fSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            drawTextOutlined(vg, lx + 2, ry + rowH / 2, def.name, 50, 30, 10, 255)

            -- 感叹号信息图标
            local nameW = nvgTextBounds(vg, 0, 0, def.name, nil)
            local infoR = math.max(5, rowH * 0.18)
            local infoCx = lx + 2 + nameW + infoR + 3
            local infoCy = ry + rowH / 2
            local infoActive = (GS.statInfoLocked == def.key) or (GS.statInfoHover == def.key)
            -- 圆形背景
            nvgBeginPath(vg)
            nvgCircle(vg, infoCx, infoCy, infoR)
            if infoActive then
                nvgFillColor(vg, nvgRGBA(220, 180, 60, 240))
            else
                nvgFillColor(vg, nvgRGBA(140, 120, 80, 160))
            end
            nvgFill(vg)
            -- "!" 文字
            nvgFontSize(vg, infoR * 1.6)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if infoActive then
                nvgFillColor(vg, nvgRGBA(40, 20, 0, 255))
            else
                nvgFillColor(vg, nvgRGBA(220, 200, 160, 220))
            end
            nvgText(vg, infoCx, infoCy, "!")
            -- 记录点击区域
            GS.statInfoBtnRects[def.key] = { x = infoCx - infoR - 2, y = infoCy - infoR - 2, w = (infoR + 2) * 2, h = (infoR + 2) * 2 }
            -- 悬停检测
            if not GS.statInfoLocked and isHovered(infoCx - infoR, infoCy - infoR, infoR * 2, infoR * 2) then
                GS.statInfoHover = def.key
            end

            -- 属性值 + 装备加值（绿色）
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            local valX = lx + lw - btnSize - 6
            if equipBonus > 0 then
                local bonusFmt = (equipBonus == math.floor(equipBonus)) and "+%d" or "+%.1f"
                local bonusStr = string.format(bonusFmt, equipBonus)
                local bfSize = math.max(7, rowH * 0.36)
                nvgFontSize(vg, bfSize)
                local bw = nvgTextBounds(vg, 0, 0, bonusStr, nil)
                -- 底值
                nvgFontSize(vg, fSize)
                drawTextOutlined(vg, valX - bw - 2, ry + rowH / 2, tostring(val), 30, 25, 15, 255)
                -- 装备加值（正绿负红）
                nvgFontSize(vg, bfSize)
                if equipBonus > 0 then
                    drawTextOutlined(vg, valX, ry + rowH / 2, bonusStr, 20, 120, 20, 255)
                else
                    drawTextOutlined(vg, valX, ry + rowH / 2, bonusStr, 180, 40, 30, 255)
                end
            else
                nvgFontSize(vg, fSize)
                drawTextOutlined(vg, valX, ry + rowH / 2, tostring(val), 30, 25, 15, 255)
            end

            -- "+" 按钮（有点数且未到上限99时显示）
            if pts > 0 and not atCap then
                local bx = lx + lw - btnSize
                local by = ry + (rowH - btnSize) / 2
                -- 按钮背景
                local btnGrad = nvgLinearGradient(vg, bx, by, bx, by + btnSize,
                    nvgRGBA(80, 140, 60, 220), nvgRGBA(50, 100, 35, 220))
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, by, btnSize, btnSize, 3)
                nvgFillPaint(vg, btnGrad)
                nvgFill(vg)
                -- 按钮边框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, by, btnSize, btnSize, 3)
                nvgStrokeColor(vg, nvgRGBA(120, 200, 80, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                -- hover 高亮
                if isHovered(bx, by, btnSize, btnSize) then
                    drawHoverHighlight(vg, bx, by, btnSize, btnSize, 3)
                end
                -- "+"
                nvgFontSize(vg, math.max(10, btnSize * 0.7))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                drawTextOutlined(vg, bx + btnSize / 2, by + btnSize / 2, "+", 255, 255, 255, 255)

                GS.statAddBtnRects[def.key] = { x = bx, y = by, w = btnSize, h = btnSize }
            elseif atCap then
                -- 已满99：显示 "MAX" 标记
                nvgFontSize(vg, math.max(7, rowH * 0.32))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local bx = lx + lw - btnSize
                drawTextOutlined(vg, bx + btnSize / 2, ry + rowH / 2, "MAX", 0, 0, 0, 200)
            end

            -- 底部细线
            if i < statCount then
                nvgBeginPath(vg)
                nvgMoveTo(vg, lx + 2, ry + rowH - 0.5)
                nvgLineTo(vg, lx + lw - 2, ry + rowH - 0.5)
                nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 60))
                nvgStrokeWidth(vg, 0.5)
                nvgStroke(vg)
            end
        end

        -- ====== 属性信息悬停提示框 ======
        local showInfoKey = GS.statInfoLocked or GS.statInfoHover
        if showInfoKey then
            local infoDef = nil
            for _, d in ipairs(GS.STAT_DEFS) do
                if d.key == showInfoKey then infoDef = d; break end
            end
            if infoDef then
                local tipFSize = math.max(9, rowH * 0.46)
                nvgFontSize(vg, tipFSize)
                -- 根据职业选择描述（猎人力量/专注加成不同）
                local isHunter = (GS.currentClass == "hunter")
                local descText = (isHunter and infoDef.descHunter) or infoDef.desc
                -- 分割 desc 为多行（按逗号分割）
                local lines = {}
                lines[#lines + 1] = "【" .. infoDef.name .. "】每点提供:"
                for part in descText:gmatch("[^,]+") do
                    lines[#lines + 1] = "  " .. part:match("^%s*(.-)%s*$")
                end
                -- 计算提示框尺寸
                local tipLineH = tipFSize + 6
                local tipH = #lines * tipLineH + 10
                local tipW = 0
                for _, ln in ipairs(lines) do
                    local tw = nvgTextBounds(vg, 0, 0, ln, nil)
                    if tw > tipW then tipW = tw end
                end
                tipW = tipW + 18
                -- 定位：感叹号图标右侧弹出
                local btnR = GS.statInfoBtnRects[showInfoKey]
                local tipX = btnR and (btnR.x + btnR.w + 4) or lx
                local tipY = btnR and (btnR.y + btnR.h / 2 - tipH / 2) or (statStartY + #GS.STAT_DEFS * rowH + 4)
                -- 右侧超出面板时改为左对齐
                if tipX + tipW > lx + lw then
                    tipX = lx
                end
                -- 确保不超出面板上下边界
                if tipY < contentTop then tipY = contentTop + 2 end
                if tipY + tipH > contentBottom then tipY = contentBottom - tipH - 2 end
                -- 背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, tipX, tipY, tipW, tipH, 4)
                nvgFillColor(vg, nvgRGBA(30, 25, 18, 235))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, tipX, tipY, tipW, tipH, 4)
                nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                -- 文本
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                for li, ln in ipairs(lines) do
                    local ly = tipY + 5 + (li - 1) * tipLineH + tipLineH / 2
                    if li == 1 then
                        nvgFillColor(vg, nvgRGBA(220, 190, 80, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(200, 200, 180, 230))
                    end
                    nvgFontSize(vg, tipFSize)
                    nvgText(vg, tipX + 9, ly, ln)
                end
            end
        end

    end

    -- 左右分隔竖线
    nvgBeginPath(vg)
    nvgMoveTo(vg, dividerX, contentTop + 2)
    nvgLineTo(vg, dividerX, contentBottom - 2)
    nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 90))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- ========== 右侧：属性汇总（内嵌，支持滚动） ==========
    do
        local rx = dividerX + 4
        local rw = cx + cw - pad - rx
        local lineH = rowH  -- 与左侧属性加点行高一致

        local col1X = rx + 4
        local valRX = rx + rw - 4

        -- 计算内容总高度（先虚拟布局）
        local totalContentH = 0

        -- 标题 + 分隔线（与左侧 headerH 对齐）
        totalContentH = totalContentH + headerH + 4

        -- HP/MP + 分页按钮 + 战斗属性
        local bs = p.baseStats or {}
        local eb = GS.getEquipBonus()
        -- 进攻属性三组
        local physAtkGroup = {
            { name = "物理攻击力", val = bs.atk or 0,     bonus = (p.atk or 0) - (bs.atk or 0) },
            { name = "物理暴击值", val = bs.critVal or 0,  bonus = (p.critVal or 0) - (bs.critVal or 0) },
            { name = "物理暴击伤害", val = string.format("%d%%", math.floor(100 + (bs.critDmg or 25))), bonus = math.floor((p.critDmg or 25) - (bs.critDmg or 25)), bfmt = "%+d%%" },
            { name = "攻击速度", val = string.format("%.1f", bs.atkSpeed or 0), bonus = (p.atkSpeed or 0) - (bs.atkSpeed or 0), bfmt = "%+.1f" },
        }
        local magAtkGroup = {
            { name = "魔法攻击力", val = bs.mAtk or 0,     bonus = (p.mAtk or 0) - (bs.mAtk or 0) },
            { name = "魔法暴击值", val = bs.mCritRate or 0, bonus = (p.mCritRate or 0) - (bs.mCritRate or 0) },
            { name = "魔法暴击伤害", val = string.format("%d%%", math.floor(100 + (bs.mCritDmg or 25))), bonus = math.floor((p.mCritDmg or 25) - (bs.mCritDmg or 25)), bfmt = "%+d%%" },
            { name = "吟唱速度", val = string.format("%.1f", bs.castSpeed or 0), bonus = (p.castSpeed or 0) - (bs.castSpeed or 0), bfmt = "%+.1f" },
        }
        local otherAtkGroup = {
            { name = "命中值", val = bs.hit or 0,      bonus = (p.hit or 0) - (bs.hit or 0) },
            { name = "移动距离", val = bs.moveRange or 0, bonus = (p.moveRange or 0) - (bs.moveRange or 0) + GS.getPlayerDebuffTotal("move") },
        }
        -- 按职业排序：战士/猎人/刺客=物理-其他-魔法，法师=魔法-其他-物理，牧师=物理-魔法-其他
        local attackStats = {}
        local cls = GS.currentClass or "warrior"
        local groupOrder
        if cls == "mage" then
            groupOrder = { magAtkGroup, otherAtkGroup, physAtkGroup }
        elseif cls == "priest" then
            groupOrder = { physAtkGroup, magAtkGroup, otherAtkGroup }
        else -- warrior, hunter, assassin
            groupOrder = { physAtkGroup, otherAtkGroup, magAtkGroup }
        end
        for _, grp in ipairs(groupOrder) do
            for _, row in ipairs(grp) do
                attackStats[#attackStats + 1] = row
            end
        end
        local defenseStats = {
            { name = "物理防御力", val = bs.def or 0,       bonus = (p.def or 0) - (bs.def or 0) },
            { name = "魔法防御力", val = bs.mDef or 0,      bonus = (p.mDef or 0) - (bs.mDef or 0) },
            { name = "闪避值", val = bs.dodge or 0,     bonus = (p.dodge or 0) - (bs.dodge or 0) + GS.getPlayerDebuffTotal("dodge") },
            { name = "避开要害", val = bs.avoidCrit or 0, bonus = (p.avoidCrit or 0) - (bs.avoidCrit or 0) },
            { name = "物理吸血", val = string.format("%.1f%%", (eb.lifesteal or 0) + (eb.physLifesteal or 0)), bonus = 0 },
            { name = "法术吸血", val = string.format("%.1f%%", (eb.lifesteal or 0) + (eb.magLifesteal or 0)), bonus = 0 },
            { name = "魔力回收", val = string.format("%.2f%%", p.manaLeech or 0), bonus = 0 },
            { name = "HP自然回复", val = string.format("%.1f", bs.hpRegen or 0),  bonus = (p.hpRegen or 0) - (bs.hpRegen or 0), bfmt = "%+.1f" },
            { name = "MP自然回复", val = string.format("%.1f", bs.mpRegen or 0),  bonus = (p.mpRegen or 0) - (bs.mpRegen or 0), bfmt = "%+.1f" },
            { name = "火焰抗性", val = string.format("%.1f%%", math.min(p.resFire or 0, 30)),    bonus = 0 },
            { name = "冰冻抗性", val = string.format("%.1f%%", math.min(p.resIce or 0, 30)),     bonus = 0 },
            { name = "雷电抗性", val = string.format("%.1f%%", math.min(p.resElec or 0, 30)),    bonus = 0 },
            { name = "神圣抗性", val = string.format("%.1f%%", math.min(p.resLight or 0, 30)),   bonus = 0 },
            { name = "暗影抗性", val = string.format("%.1f%%", math.min(p.resDark or 0, 30)),    bonus = 0 },
            { name = "自然抗性", val = string.format("%.1f%%", math.min(p.resNature or 0, 30)), bonus = 0 },
        }
        local tabBtnH = lineH  -- 分页按钮行高
        local tabMode = GS.statsTabMode or "attack"
        local combatStats = (tabMode == "attack") and attackStats or defenseStats

        -- ====== 固定区域（不滚动）：标题 + HP/MP + 分页按钮 ======
        local fontSize = math.max(8, rowH * 0.42)
        local bonusFontSize = math.max(7, rowH * 0.36)

        local fixedY = contentTop

        -- 标题（与左侧 headerH 对齐）
        nvgSave(vg)
        nvgIntersectScissor(vg, rx, contentTop, rw, contentH)
        nvgFontSize(vg, math.max(9, rowH * 0.45))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        drawTextOutlined(vg, rx + rw / 2, fixedY + headerH / 2, "属 性 汇 总", 60, 35, 10, 255)
        fixedY = fixedY + headerH

        -- 分隔线（标题下方）
        nvgBeginPath(vg)
        nvgMoveTo(vg, rx + 2, fixedY + 1)
        nvgLineTo(vg, rx + rw - 2, fixedY + 1)
        nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 90))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)
        fixedY = fixedY + 4

        -- HP / MP 行
        local hpBonus = (p.maxHp or 0) - (bs.maxHp or 0)
        local mpBonus = (p.maxMp or 0) - (bs.maxMp or 0)
        local hpMpRows = {
            { name = "MaxHP", val = bs.maxHp or 0, bonus = hpBonus },
            { name = "MaxMP", val = bs.maxMp or 0, bonus = mpBonus },
        }
        for idx, row in ipairs(hpMpRows) do
            local ry = fixedY + (idx - 1) * lineH
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            drawTextOutlined(vg, col1X, ry + lineH / 2, row.name, 50, 30, 10, 255)
            local valStr = tostring(row.val)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if row.bonus and row.bonus ~= 0 then
                local _bfmt = (row.bonus == math.floor(row.bonus)) and "%+d" or "%+.1f"
                local bonusStr = string.format(_bfmt, row.bonus)
                nvgFontSize(vg, bonusFontSize)
                local bw = nvgTextBounds(vg, 0, 0, bonusStr, nil)
                nvgFontSize(vg, fontSize)
                drawTextOutlined(vg, valRX - bw - 2, ry + lineH / 2, valStr, 30, 25, 15, 255)
                nvgFontSize(vg, bonusFontSize)
                if row.bonus > 0 then
                    drawTextOutlined(vg, valRX, ry + lineH / 2, bonusStr, 20, 120, 20, 255)
                else
                    drawTextOutlined(vg, valRX, ry + lineH / 2, bonusStr, 180, 40, 30, 255)
                end
            else
                nvgFontSize(vg, fontSize)
                drawTextOutlined(vg, valRX, ry + lineH / 2, valStr, 30, 25, 15, 255)
            end
        end
        fixedY = fixedY + 2 * lineH

        -- 分隔线（MP 下方）
        nvgBeginPath(vg)
        nvgMoveTo(vg, rx + 2, fixedY)
        nvgLineTo(vg, rx + rw - 2, fixedY)
        nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 90))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)
        fixedY = fixedY + 3

        -- ========== 进攻/防守 分页按钮（固定） ==========
        local tabGap = 4
        local tabW = math.floor((rw - 8 - tabGap) / 2)
        local tabX1 = rx + 4
        local tabX2 = tabX1 + tabW + tabGap
        local tabY = fixedY
        local isAtk = (tabMode == "attack")
        local isDef = (tabMode == "defense")
        local tabFontSize = math.max(7, lineH * 0.45)

        -- 按钮1: 进攻属性（无底色下划线风格）
        local underlineH = math.max(1.5, tabBtnH * 0.08)
        nvgFontSize(vg, tabFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, isAtk and nvgRGBA(120, 70, 20, 255) or nvgRGBA(140, 120, 90, 160))
        nvgText(vg, tabX1 + tabW / 2, tabY + tabBtnH / 2, "进攻属性", nil)
        if isAtk then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tabX1 + tabW * 0.15, tabY + tabBtnH - underlineH - 1, tabW * 0.7, underlineH, underlineH / 2)
            nvgFillColor(vg, nvgRGBA(180, 100, 30, 230))
            nvgFill(vg)
        end

        -- 按钮2: 防守属性（无底色下划线风格）
        nvgFontSize(vg, tabFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, isDef and nvgRGBA(120, 70, 20, 255) or nvgRGBA(140, 120, 90, 160))
        nvgText(vg, tabX2 + tabW / 2, tabY + tabBtnH / 2, "防守属性", nil)
        if isDef then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tabX2 + tabW * 0.15, tabY + tabBtnH - underlineH - 1, tabW * 0.7, underlineH, underlineH / 2)
            nvgFillColor(vg, nvgRGBA(180, 100, 30, 230))
            nvgFill(vg)
        end

        -- 记录按钮区域用于点击检测
        GS._statsTabAtkRect = { x = tabX1, y = tabY, w = tabW, h = tabBtnH }
        GS._statsTabDefRect = { x = tabX2, y = tabY, w = tabW, h = tabBtnH }

        fixedY = fixedY + tabBtnH + 5
        nvgRestore(vg)

        -- ====== 滚动区域：仅战斗属性列表 ======
        local scrollTop = fixedY
        local scrollViewH = contentBottom - scrollTop
        local scrollContentH = #combatStats * lineH

        GS.charStatScrollY = GS.charStatScrollY or 0
        local maxScroll = math.max(0, scrollContentH - scrollViewH)
        if GS.charStatScrollY < 0 then GS.charStatScrollY = 0 end
        if GS.charStatScrollY > maxScroll then GS.charStatScrollY = maxScroll end
        local scrollOff = GS.charStatScrollY

        -- 滚动区域记录（供输入模块判断）
        GS.charStatScrollRect = { x = rx, y = scrollTop, w = rw, h = scrollViewH }
        GS.charStatContentH = scrollContentH
        GS.charStatVisibleH = scrollViewH

        -- 裁剪滚动区域
        nvgSave(vg)
        nvgIntersectScissor(vg, rx, scrollTop, rw, scrollViewH)

        local startY = scrollTop - scrollOff

        -- 重置右侧感叹号按钮区域
        GS.combatStatInfoBtnRects = {}
        if not GS.combatStatInfoLocked then
            GS.combatStatInfoHover = nil
        end

        for idx, row in ipairs(combatStats) do
            local ry = startY + (idx - 1) * lineH
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            drawTextOutlined(vg, col1X, ry + lineH / 2, row.name, 50, 30, 10, 255)

            -- 感叹号图标（仅对有 tip 的属性显示）
            if GS.COMBAT_STAT_TIPS[row.name] then
                local nameW = nvgTextBounds(vg, 0, 0, row.name, nil)
                local infoR = math.max(5, lineH * 0.18)
                local infoCx = col1X + nameW + infoR + 3
                local infoCy = ry + lineH / 2
                local infoActive = (GS.combatStatInfoLocked == row.name) or (GS.combatStatInfoHover == row.name)
                nvgBeginPath(vg)
                nvgCircle(vg, infoCx, infoCy, infoR)
                if infoActive then
                    nvgFillColor(vg, nvgRGBA(220, 180, 60, 240))
                else
                    nvgFillColor(vg, nvgRGBA(140, 120, 80, 160))
                end
                nvgFill(vg)
                nvgFontSize(vg, infoR * 1.6)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if infoActive then
                    nvgFillColor(vg, nvgRGBA(40, 20, 0, 255))
                else
                    nvgFillColor(vg, nvgRGBA(220, 200, 160, 220))
                end
                nvgText(vg, infoCx, infoCy, "!")
                GS.combatStatInfoBtnRects[row.name] = { x = infoCx - infoR - 2, y = infoCy - infoR - 2, w = (infoR + 2) * 2, h = (infoR + 2) * 2 }
                if not GS.combatStatInfoLocked and isHovered(infoCx - infoR, infoCy - infoR, infoR * 2, infoR * 2) then
                    GS.combatStatInfoHover = row.name
                end
            end

            local valStr = tostring(row.val)
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if row.bonus and row.bonus ~= 0 then
                local _bfmt2 = row.bfmt or ((row.bonus == math.floor(row.bonus)) and "%+d" or "%+.1f")
                local bonusStr = string.format(_bfmt2, row.bonus)
                nvgFontSize(vg, bonusFontSize)
                local bw = nvgTextBounds(vg, 0, 0, bonusStr, nil)
                nvgFontSize(vg, fontSize)
                drawTextOutlined(vg, valRX - bw - 2, ry + lineH / 2, valStr, 30, 25, 15, 255)
                nvgFontSize(vg, bonusFontSize)
                if row.bonus > 0 then
                    drawTextOutlined(vg, valRX, ry + lineH / 2, bonusStr, 20, 120, 20, 255)
                else
                    drawTextOutlined(vg, valRX, ry + lineH / 2, bonusStr, 180, 40, 30, 255)
                end
            else
                nvgFontSize(vg, fontSize)
                drawTextOutlined(vg, valRX, ry + lineH / 2, valStr, 30, 25, 15, 255)
            end
        end

        nvgRestore(vg)

        -- ====== 右侧属性感叹号 tooltip ======
        local csTipKey = GS.combatStatInfoLocked or GS.combatStatInfoHover
        if csTipKey and GS.COMBAT_STAT_TIPS[csTipKey] then
            local tipDef = GS.COMBAT_STAT_TIPS[csTipKey]
            local segments
            if type(tipDef) == "function" then
                segments = tipDef()
            elseif type(tipDef) == "string" and tipDef ~= "" then
                segments = { { text = tipDef } }
            end
            if segments then
                local tipFSize = math.max(9, lineH * 0.46)
                nvgFontSize(vg, tipFSize)
                local tipPadX = 10  -- 左右内边距
                local tipPadY = 6   -- 上下内边距
                local maxLineW = rw - tipPadX * 2 - 4  -- tooltip 内文本最大行宽

                -- 将所有 segments 展平为逐字符列表 {char, color}
                local allChars = {}
                -- 标题行
                local titleText = "【" .. csTipKey .. "】"
                local tpos = 1
                while tpos <= #titleText do
                    local tb = string.byte(titleText, tpos)
                    local tl = tb < 0x80 and 1 or (tb < 0xE0 and 2 or (tb < 0xF0 and 3 or 4))
                    local tc = titleText:sub(tpos, tpos + tl - 1)
                    allChars[#allChars + 1] = { ch = tc, color = {220, 190, 80, 255}, isTitle = true }
                    tpos = tpos + tl
                end
                -- 标题后强制换行
                allChars[#allChars + 1] = { ch = "\n" }
                -- 正文 segments 逐字符展开
                for _, seg in ipairs(segments) do
                    local segText = seg.text
                    local spos = 1
                    while spos <= #segText do
                        local sb = string.byte(segText, spos)
                        local sl = sb < 0x80 and 1 or (sb < 0xE0 and 2 or (sb < 0xF0 and 3 or 4))
                        local sc = segText:sub(spos, spos + sl - 1)
                        allChars[#allChars + 1] = { ch = sc, color = seg.color }
                        spos = spos + sl
                    end
                end

                -- 按 maxLineW 分行
                local tipLines = {}  -- 每行 = { {text, color}, ... }
                local curLine = {}
                local curLineW = 0
                local curSeg = { text = "", color = nil }

                local function flushSeg()
                    if curSeg.text ~= "" then
                        curLine[#curLine + 1] = { text = curSeg.text, color = curSeg.color }
                        curSeg = { text = "", color = nil }
                    end
                end
                local function flushLine()
                    flushSeg()
                    if #curLine > 0 then
                        tipLines[#tipLines + 1] = curLine
                    end
                    curLine = {}
                    curLineW = 0
                end

                for _, ci in ipairs(allChars) do
                    if ci.ch == "\n" then
                        flushLine()
                    else
                        local chW = nvgTextBounds(vg, 0, 0, ci.ch, nil)
                        -- 需要换行
                        if curLineW + chW > maxLineW and curLineW > 0 then
                            flushLine()
                        end
                        -- 颜色标记：用序列化后的字符串做比较，避免 table 引用不等
                        local cKey = ci.color and (ci.color[1] .. "," .. ci.color[2] .. "," .. ci.color[3]) or "nil"
                        local sKey = curSeg.color and (curSeg.color[1] .. "," .. curSeg.color[2] .. "," .. curSeg.color[3]) or "nil"
                        if cKey ~= sKey then
                            flushSeg()
                            curSeg.color = ci.color
                        end
                        curSeg.text = curSeg.text .. ci.ch
                        curLineW = curLineW + chW
                    end
                end
                flushLine()

                -- 标记标题行
                local titleLineCount = 1
                for i = 1, math.min(titleLineCount, #tipLines) do
                    tipLines[i].isTitle = true
                end

                -- 计算 tooltip 尺寸
                local tipLineH = tipFSize + 6
                local tipH = #tipLines * tipLineH + tipPadY * 2
                local tipW = 0
                for _, line in ipairs(tipLines) do
                    local lw2 = 0
                    for _, seg in ipairs(line) do
                        lw2 = lw2 + nvgTextBounds(vg, 0, 0, seg.text, nil)
                    end
                    if lw2 > tipW then tipW = lw2 end
                end
                tipW = tipW + tipPadX * 2
                -- 限制不超过面板宽度
                if tipW > rw then tipW = rw end

                -- 定位 tooltip
                local btnR = GS.combatStatInfoBtnRects[csTipKey]
                -- 优先在按钮右侧显示，放不下则左对齐到面板
                local tipX = btnR and (btnR.x + btnR.w + 4) or rx
                local tipY = btnR and (btnR.y - tipH / 2) or scrollTop
                -- 右边界：不超出面板
                if tipX + tipW > rx + rw then tipX = rx + rw - tipW end
                if tipX < rx then tipX = rx end
                -- 上下边界
                if tipY < contentTop then tipY = contentTop + 2 end
                if tipY + tipH > contentBottom then tipY = contentBottom - tipH - 2 end

                -- 重置所有裁剪区域，tooltip 不受外层 scissor 限制
                nvgSave(vg)
                nvgResetScissor(vg)

                -- 背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, tipX, tipY, tipW, tipH, 4)
                nvgFillColor(vg, nvgRGBA(30, 25, 18, 240))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, tipX, tipY, tipW, tipH, 4)
                nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 逐行逐段绘制文本
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                for li, line in ipairs(tipLines) do
                    local ly = tipY + tipPadY + (li - 1) * tipLineH + tipLineH / 2
                    local sx = tipX + tipPadX
                    nvgFontSize(vg, tipFSize)
                    local defaultColor = line.isTitle and {220, 190, 80, 255} or {200, 200, 180, 230}
                    for _, seg in ipairs(line) do
                        local c = seg.color or defaultColor
                        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], c[4] or 255))
                        nvgText(vg, sx, ly, seg.text)
                        sx = sx + nvgTextBounds(vg, 0, 0, seg.text, nil)
                    end
                end

                nvgRestore(vg)
            end
        end

        -- 滚动条
        if scrollContentH > scrollViewH then
            local barW = 3
            local barX2 = rx + rw - barW - 1
            local barH2 = math.max(16, scrollViewH * (scrollViewH / scrollContentH))
            local barY2 = scrollTop + (scrollViewH - barH2) * (scrollOff / maxScroll)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX2, barY2, barW, barH2, barW / 2)
            nvgFillColor(vg, nvgRGBA(60, 55, 50, 140))
            nvgFill(vg)
        end
    end

    -- BUFF/DEBUFF 总结覆盖层
    if GS.showBuffSummary then
        M.drawBuffSummaryOverlay(cx, cy, cw, ch)
    end
end

-- ====================================================================
-- BUFF/DEBUFF 总结面板（覆盖在角色面板上）
-- ====================================================================
function M.drawBuffSummaryOverlay(cx, cy, cw, ch)
    local vg = M.vg
    local p = GS.player
    if not p then return end

    -- 不透明遮罩
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx, cy + 20, cw, ch - 20, 4)
    nvgFillColor(vg, nvgRGBA(25, 18, 10, 250))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    local pad = 6
    local startY = cy + 24
    local lineH = 15
    local contentX = cx + pad
    local contentW = cw - pad * 2

    -- 标题
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 230, 170, 255))
    nvgText(vg, cx + cw / 2, startY + 6, "增 益 & 减 益 效 果 一 览", nil)
    startY = startY + 16

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + 5, startY)
    nvgLineTo(vg, cx + cw - 5, startY)
    nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    startY = startY + 4

    -- ========== 收集所有当前生效的 BUFF/DEBUFF ==========
    local entries = {}  -- { name, desc, color={r,g,b}, isBuff=true/false }

    -- 药水buff名称映射
    local potionNames = {
        buff_atk = "物攻", buff_matk = "魔攻", buff_def = "物防",
        buff_mdef = "魔防", buff_hit = "命中", buff_dodge = "闪避",
        buff_str = "力量", buff_agi = "敏捷", buff_con = "体质",
        buff_wis = "智慧", buff_foc = "专注", buff_per = "感知",
        buff_wil = "意念", buff_luk = "幸运", buff_cha = "魅力",
        buff_fire_res = "火焰抗性", buff_ice_res = "冰冻抗性",
        buff_thunder_res = "雷电抗性", buff_nature_res = "自然抗性",
        buff_dark_res = "暗影抗性", buff_holy_res = "神圣抗性",
        buff_fire_dmg = "火焰增幅", buff_ice_dmg = "冰冻增幅",
        buff_thunder_dmg = "雷电增幅", buff_holy_dmg = "神圣增幅",
    }

    -- 辅助：计算 weatherTime 剩余时间文本
    local function fmtRemain(expireTime)
        if not expireTime or expireTime <= 0 then return "" end
        local rem = math.max(0, expireTime - GS.weatherTime)
        local h = math.floor(rem / 60)
        local m = rem % 60
        if h > 0 then
            return string.format(" [%d时%d分]", h, m)
        else
            return string.format(" [%d分]", m)
        end
    end

    -- 1) 食物 BUFF
    if GS.foodBuff and (not GS.foodBuff.expireTime or GS.weatherTime < GS.foodBuff.expireTime) then
        local fb = GS.foodBuff
        local parts = {}
        if (fb.hpRegen or 0) > 0 then parts[#parts+1] = "HP回复+" .. fb.hpRegen end
        if (fb.mpRegen or 0) > 0 then parts[#parts+1] = "MP回复+" .. fb.mpRegen end
        if (fb.str or 0) > 0 then parts[#parts+1] = "力量+" .. fb.str end
        if (fb.agi or 0) > 0 then parts[#parts+1] = "敏捷+" .. fb.agi end
        if (fb.con or 0) > 0 then parts[#parts+1] = "体质+" .. fb.con end
        if (fb.foc or 0) > 0 then parts[#parts+1] = "专注+" .. fb.foc end
        if (fb.wis or 0) > 0 then parts[#parts+1] = "智慧+" .. fb.wis end
        if (fb.per or 0) > 0 then parts[#parts+1] = "感知+" .. fb.per end
        if (fb.wil or 0) > 0 then parts[#parts+1] = "意念+" .. fb.wil end
        if (fb.luk or 0) > 0 then parts[#parts+1] = "幸运+" .. fb.luk end
        if (fb.physCrit or 0) > 0 then parts[#parts+1] = "物理暴击+" .. fb.physCrit end
        if (fb.magicCrit or 0) > 0 then parts[#parts+1] = "魔法暴击+" .. fb.magicCrit end
        if (fb.fireDmgPct or 0) > 0 then parts[#parts+1] = "火焰伤害+" .. fb.fireDmgPct .. "%" end
        if (fb.iceDmgPct or 0) > 0 then parts[#parts+1] = "寒冰伤害+" .. fb.iceDmgPct .. "%" end
        if (fb.thunderDmgPct or 0) > 0 then parts[#parts+1] = "雷电伤害+" .. fb.thunderDmgPct .. "%" end
        if (fb.holyDmgPct or 0) > 0 then parts[#parts+1] = "神圣伤害+" .. fb.holyDmgPct .. "%" end
        local desc = table.concat(parts, " ")
        entries[#entries+1] = {
            name = "食物: " .. (fb.name or "未知"),
            desc = desc .. fmtRemain(fb.expireTime),
            color = {180, 220, 120}, isBuff = true,
        }
    end

    -- 2) 勿忘我 BUFF（永久效果或临时buff）
    local fmnShowBuff = GS.forgetMeNotPermanent
        or (GS.forgetMeNotBuff and GS.forgetMeNotBuff.active
            and (not GS.forgetMeNotBuff.expireTime or GS.weatherTime < GS.forgetMeNotBuff.expireTime))
    if fmnShowBuff then
        local fmnLv = GS.forgetMeNotLevel or 0
        local fmnVal = 1 + fmnLv
        local fmnDesc = "HP回复+" .. fmnVal .. " MP回复+" .. fmnVal
                      .. " 力量+" .. fmnVal .. " 专注+" .. fmnVal .. " 智慧+" .. fmnVal
        
        local fmnRemain = ""
        if GS.forgetMeNotPermanent then
            fmnRemain = " [永久]"
        elseif GS.forgetMeNotBuff then
            fmnRemain = fmtRemain(GS.forgetMeNotBuff.expireTime)
        end
        entries[#entries+1] = {
            name = "\"勿忘我\"",
            desc = fmnDesc .. fmnRemain,
            color = {220, 160, 255}, isBuff = true,
        }
    end

    -- 2.5) 精神抖擞 BUFF
    if GS.hugBuff and GS.hugBuff.active
       and (not GS.hugBuff.expireTime or GS.weatherTime < GS.hugBuff.expireTime) then
        entries[#entries+1] = {
            name = "精神抖擞",
            desc = "全属性+1" .. fmtRemain(GS.hugBuff.expireTime),
            color = {255, 200, 140}, isBuff = true,
        }
    end

    -- 3) 药水 BUFF
    if GS.potionBuffs then
        for stat, buff in pairs(GS.potionBuffs) do
            if buff.expireTime and GS.weatherTime <= buff.expireTime then
                local label = potionNames[stat] or stat
                local valStr = buff.isPercent and ("+" .. buff.amount .. "%") or ("+" .. buff.amount)
                entries[#entries+1] = {
                    name = "药水: " .. label,
                    desc = valStr .. fmtRemain(buff.expireTime),
                    color = {100, 200, 255}, isBuff = true,
                }
            end
        end
    end

    -- 4) 祝福 BUFF（玩家身上的）
    if p.prayerTurns and p.prayerTurns > 0 then
        entries[#entries+1] = {
            name = "祈祷",
            desc = "每回合回复" .. string.format("%.1f", p.prayerHealPct or 0) .. "%HP [" .. p.prayerTurns .. "回合]",
            color = {255, 220, 100}, isBuff = true,
        }
    end
    if p.holySpringTurns and p.holySpringTurns > 0 then
        entries[#entries+1] = {
            name = "圣泉祝福",
            desc = "HP/MP回复+" .. string.format("%.0f", p.holySpringRegenPct or 0) .. "% [" .. p.holySpringTurns .. "回合]",
            color = {255, 220, 100}, isBuff = true,
        }
    elseif (p.holySpringBlessing or 0) > 0 then
        local pct = p.holySpringBlessing * 5
        entries[#entries+1] = {
            name = "圣泉祝福",
            desc = "HP/MP回复+" .. pct .. "% [装备·永久]",
            color = {100, 200, 220}, isBuff = true,
        }
    end
    if p.conquerTurns and p.conquerTurns > 0 then
        entries[#entries+1] = {
            name = "征服祝福",
            desc = "物攻/魔攻+" .. string.format("%.0f", p.conquerAtkPct or 0) .. "% [" .. p.conquerTurns .. "回合]",
            color = {255, 220, 100}, isBuff = true,
        }
    end
    if (p.chargeRoarTurns or 0) > 0 then
        entries[#entries+1] = {
            name = "冲锋怒吼",
            desc = "伤害+" .. (p.chargeRoarDmgPct or 0) .. "% 减伤+" .. (p.chargeRoarReducePct or 0) .. "% [" .. p.chargeRoarTurns .. "回合]",
            color = {240, 160, 40}, isBuff = true,
        }
    end
    if p.shelterTurns and p.shelterTurns > 0 then
        entries[#entries+1] = {
            name = "庇护祝福",
            desc = "防御力+" .. string.format("%.0f", p.shelterDefPct or 0) .. "% [" .. p.shelterTurns .. "回合]",
            color = {255, 220, 100}, isBuff = true,
        }
    elseif (p.shelterBlessing or 0) > 0 then
        local pct = p.shelterBlessing * 1
        entries[#entries+1] = {
            name = "庇护祝福",
            desc = "物防/魔防+" .. pct .. "% [装备·永久]",
            color = {100, 200, 220}, isBuff = true,
        }
    end
    if p.miracleTurns and p.miracleTurns > 0 then
        local mv = p.miracleVal or 0
        entries[#entries+1] = {
            name = "奇迹祝福",
            desc = "暴击/闪避/命中+" .. mv .. "% 暴伤+" .. (mv*2) .. "% [" .. p.miracleTurns .. "回合]",
            color = {255, 220, 100}, isBuff = true,
        }
    end

    -- 5) 战斗 BUFF
    if GS.stormBuffTurns > 0 then
        entries[#entries+1] = {
            name = "风暴",
            desc = "回合开始/结束自动旋风斩 [" .. GS.stormBuffTurns .. "回合]",
            color = {180, 220, 255}, isBuff = true,
        }
    end
    if GS.focusBuffTurns > 0 then
        entries[#entries+1] = {
            name = "静神",
            desc = "弓伤害/攻速提升 [本回合]",
            color = {200, 180, 255}, isBuff = true,
        }
    end
    if GS.stealthActive and GS.stealthTurns > 0 then
        entries[#entries+1] = {
            name = "隐匿",
            desc = "敌人无法主动攻击 [" .. GS.stealthTurns .. "回合]",
            color = {160, 160, 200}, isBuff = true,
        }
    end
    if GS.fireShieldTurns > 0 then
        entries[#entries+1] = {
            name = "火焰护盾",
            desc = "减伤" .. math.floor(GS.fireShieldReducePct or 0) .. "% 反射" .. math.floor(GS.fireShieldReflectPct or 0) .. "%火伤 [" .. GS.fireShieldTurns .. "回合]",
            color = {255, 140, 60}, isBuff = true,
        }
    end
    if GS.magicShieldActive then
        entries[#entries+1] = {
            name = "魔法盾",
            desc = "伤害转为消耗MP [持续]",
            color = {100, 160, 255}, isBuff = true,
        }
    end
    if GS.player and (GS.player._spareWeaponCritTurns or 0) > 0 then
        entries[#entries+1] = {
            name = "备用武器",
            desc = "暴击伤害+" .. (GS.player._spareWeaponCritDmg or 0) .. "% [" .. GS.player._spareWeaponCritTurns .. "回合]",
            color = {160, 140, 120}, isBuff = true,
        }
    end

    -- 5.5) 元素流转 BUFF
    if GS._eleFlowLastElem and (GS._eleFlowTurns or 0) > 0 then
        local elemNames = { fire = "火", ice = "冰", thunder = "雷", light = "光", holy = "光" }
        local eName = elemNames[GS._eleFlowLastElem] or GS._eleFlowLastElem
        local bonus = (GS.player and GS.player.eleFlowBonus or 0)
        entries[#entries+1] = {
            name = "元素流转",
            desc = "上回合使用" .. eName .. "元素，其他元素魔伤+" .. bonus .. "% [" .. GS._eleFlowTurns .. "回合]",
            color = {120, 200, 255}, isBuff = true,
        }
    end

    -- 6) 玩家 DEBUFF
    if #GS.playerDebuffs > 0 then
        local debuffSummary = {}
        for _, db in ipairs(GS.playerDebuffs) do
            local key = db.source or db.type
            if not debuffSummary[key] then
                debuffSummary[key] = { type = db.type, source = db.source or db.type, totalVal = 0, maxTurns = 0, stacks = 0 }
            end
            local s = debuffSummary[key]
            s.totalVal = s.totalVal + db.val
            s.maxTurns = math.max(s.maxTurns, db.turns)
            s.stacks = s.stacks + 1
        end
        for _, s in pairs(debuffSummary) do
            local name, desc, r, g, b = "未知", "", 200, 200, 200
            if s.source == "elec" then
                name = "麻痹"
                desc = "闪避-" .. s.totalVal .. " (" .. s.stacks .. "层) [" .. s.maxTurns .. "回合]"
                r, g, b = 240, 220, 60
            elseif s.source == "ice" then
                name = "冻僵"
                desc = "移速-" .. s.totalVal .. " (" .. s.stacks .. "层) [" .. s.maxTurns .. "回合]"
                r, g, b = 100, 180, 240
            end
            entries[#entries+1] = {
                name = name, desc = desc,
                color = {r, g, b}, isBuff = false,
            }
        end
    end

    -- 7) 不可知物凝视 DEBUFF
    if (p._unknownGaze or 0) > 0 then
        entries[#entries+1] = {
            name = "不可知物的凝视",
            desc = "感知+" .. (p._gazePer or 0) .. " 专注+" .. (p._gazeFoc or 0) .. " (" .. p._unknownGaze .. "层) [战斗中]",
            color = {180, 120, 255}, isBuff = false,
        }
    end

    -- 7.5) 狂怒 BUFF（血屠装备）
    if (p._furyStacks or 0) > 0 then
        local stk = p._furyStacks
        entries[#entries+1] = {
            name = "狂怒",
            desc = "攻击力+" .. (stk * 3) .. " 暴击伤害+" .. stk .. "% (" .. stk .. "层)",
            color = {255, 80, 40}, isBuff = true,
        }
    end

    -- 7.6) 月影 BUFF（刺客被动技能）
    if (p._moonShadowStacks or 0) > 0 then
        local stk = p._moonShadowStacks
        local msLv = GS.skillLevels["a_moon_shadow"] or 1
        local perStack = 1.5 * msLv
        local totalDodge = stk * perStack
        entries[#entries+1] = {
            name = "月影",
            desc = "闪避率+" .. totalDodge .. "% (" .. stk .. "层×" .. perStack .. "%/层) [1回合]",
            color = {120, 160, 255}, isBuff = true,
        }
    end

    -- 7.7) 满月 BUFF（刺客被动技能）
    local fmLvBuf = GS.skillLevels["a_full_moon"] or 0
    local fmChargeNeed = (GS.SKILL_DEFS["a_full_moon"].fullMoonDodgePerCharge[fmLvBuf] or 20)
    if (p._fullMoonStacks or 0) > 0 and p._fullMoonStackList then
        local stk = p._fullMoonStacks
        local cnt = p._fullMoonDodgeCount or 0
        -- 构建每层剩余回合显示
        local turnParts = {}
        for si = 1, #p._fullMoonStackList do
            turnParts[#turnParts + 1] = p._fullMoonStackList[si] .. "回合"
        end
        local turnsStr = table.concat(turnParts, "/")
        entries[#entries+1] = {
            name = "满月",
            desc = stk .. "层（致死伤害时消耗1层，伤害-95%）[各层剩余:" .. turnsStr .. "] 下一层进度:" .. cnt .. "/" .. fmChargeNeed,
            color = {200, 210, 255}, isBuff = true,
        }
    elseif fmLvBuf >= 3 and (p._fullMoonDodgeCount or 0) > 0 then
        local cnt = p._fullMoonDodgeCount or 0
        entries[#entries+1] = {
            name = "满月(蓄力中)",
            desc = "闪避计数:" .. cnt .. "/" .. fmChargeNeed,
            color = {160, 170, 200}, isBuff = true,
        }
    end

    -- 7.8) 燃火 BUFF（火魔女腰带：回合开始时站在灼烧地面激活）
    if (p._ragingFireBonus or 0) > 0 then
        entries[#entries+1] = {
            name = "燃火",
            desc = "火焰伤害额外提高" .. string.format("%g%%", p._ragingFireBonus) .. " [本回合]",
            color = {255, 140, 40}, isBuff = true,
        }
    end

    -- 8) 其他战斗 DEBUFF（直接挂在 player 属性上的）
    if (p.stunned or 0) > 0 then
        entries[#entries+1] = {
            name = "晕眩",
            desc = "无法行动 [" .. p.stunned .. "回合]",
            color = {255, 220, 60}, isBuff = false,
        }
    end
    if p.poisoned and (p.poisonTurns or 0) > 0 then
        entries[#entries+1] = {
            name = "中毒",
            desc = "每回合受到最大HP" .. p.poisoned .. "%伤害 [" .. p.poisonTurns .. "回合]",
            color = {180, 80, 220}, isBuff = false,
        }
    end
    if p.armorBroken and (p.armorBrokenTurns or 0) > 0 then
        entries[#entries+1] = {
            name = "破甲",
            desc = "物理防御-" .. p.armorBroken .. "% [" .. p.armorBrokenTurns .. "回合]",
            color = {220, 100, 60}, isBuff = false,
        }
    end
    if (p.feared or 0) > 0 then
        entries[#entries+1] = {
            name = "恐惧",
            desc = "无法行动 [" .. p.feared .. "回合]",
            color = {200, 160, 80}, isBuff = false,
        }
    end
    if p.burned and p.burnStacks and #p.burnStacks > 0 then
        local maxTurns = 0
        for _, st in ipairs(p.burnStacks) do if st.turns > maxTurns then maxTurns = st.turns end end
        local sc = #p.burnStacks
        entries[#entries+1] = {
            name = "灼伤" .. (sc > 1 and (" x" .. sc) or ""),
            desc = "每回合受到火属性伤害 [最长" .. maxTurns .. "回合]" .. (sc > 1 and ("，共" .. sc .. "层") or ""),
            color = {255, 120, 40}, isBuff = false,
        }
    end
    if p.chilled and (p.chilledTurns or 0) > 0 then
        local csc = p.chillStacks or 1
        entries[#entries+1] = {
            name = "冻僵" .. (csc > 1 and (" x" .. csc) or ""),
            desc = "移动距离-1 [" .. p.chilledTurns .. "回合]" .. (csc > 1 and ("，共" .. csc .. "层") or ""),
            color = {100, 200, 255}, isBuff = false,
        }
    end
    if (p.frozen or 0) > 0 then
        entries[#entries+1] = {
            name = "冻结",
            desc = "无法移动 [" .. p.frozen .. "回合]",
            color = {80, 160, 240}, isBuff = false,
        }
    end
    if p.sandBlinded and (p.sandBlindedTurns or 0) > 0 then
        entries[#entries+1] = {
            name = "致盲",
            desc = "命中-" .. p.sandBlinded .. " [" .. p.sandBlindedTurns .. "回合]",
            color = {200, 180, 120}, isBuff = false,
        }
    end
    if (p.taunted or 0) > 0 then
        local parts = {}
        if (p.tauntAtkPct or 0) ~= 0 then parts[#parts+1] = "攻击" .. (p.tauntAtkPct > 0 and "+" or "") .. p.tauntAtkPct .. "%" end
        if (p.tauntDefPct or 0) ~= 0 then parts[#parts+1] = "防御" .. (p.tauntDefPct > 0 and "+" or "") .. p.tauntDefPct .. "%" end
        entries[#entries+1] = {
            name = "嘲讽",
            desc = (#parts > 0 and table.concat(parts, " ") or "被嘲讽") .. " [" .. p.taunted .. "回合]",
            color = {255, 180, 60}, isBuff = false,
        }
    end

    -- ========== 渲染列表 ==========
    local scrollArea = { x = cx, y = startY, w = cw, h = ch - (startY - cy) - 4 }
    GS.buffSummaryClipRect = scrollArea

    nvgSave(vg)
    nvgIntersectScissor(vg, scrollArea.x, scrollArea.y, scrollArea.w, scrollArea.h)

    local scrollOff = GS.buffSummaryScrollY or 0
    local drawY = startY - scrollOff

    if #entries == 0 then
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 130, 100, 180))
        nvgText(vg, cx + cw / 2, drawY + 20, "当前没有任何状态效果", nil)
        drawY = drawY + 40
    else
        -- 先渲染 buff，再渲染 debuff
        local buffEntries = {}
        local debuffEntries = {}
        for _, e in ipairs(entries) do
            if e.isBuff then buffEntries[#buffEntries+1] = e
            else debuffEntries[#debuffEntries+1] = e end
        end

        local function drawSection(title, titleColor, list)
            if #list == 0 then return end
            -- 小节标题
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(titleColor[1], titleColor[2], titleColor[3], 220))
            nvgText(vg, contentX, drawY + lineH / 2, "- " .. title, nil)
            drawY = drawY + lineH

            -- 分隔细线
            nvgBeginPath(vg)
            nvgMoveTo(vg, contentX, drawY)
            nvgLineTo(vg, contentX + contentW, drawY)
            nvgStrokeColor(vg, nvgRGBA(titleColor[1], titleColor[2], titleColor[3], 60))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
            drawY = drawY + 2

            for _, e in ipairs(list) do
                -- 名称+效果同一行：名称用增益绿/减益红，效果跟在后面偏灰
                local nameColor
                if e.isBuff then
                    nameColor = {80, 200, 80}   -- 增益绿色
                else
                    nameColor = {220, 70, 70}   -- 减益红色
                end

                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                local midY = drawY + lineH / 2

                -- 绘制名称（绿色/红色）
                nvgFillColor(vg, nvgRGBA(nameColor[1], nameColor[2], nameColor[3], 255))
                nvgText(vg, contentX + 4, midY, e.name, nil)

                -- 计算名称宽度，描述跟在后面
                if e.desc and e.desc ~= "" then
                    local nameW = nvgTextBounds(vg, 0, 0, e.name, nil)
                    nvgFontSize(vg, 8)
                    nvgFillColor(vg, nvgRGBA(200, 190, 170, 230))
                    nvgText(vg, contentX + 4 + nameW + 4, midY, e.desc, nil)
                end

                drawY = drawY + lineH
            end
        end

        drawSection("增益效果", {120, 220, 100}, buffEntries)
        if #debuffEntries > 0 then
            drawY = drawY + 4
            drawSection("减益效果", {240, 80, 80}, debuffEntries)
        end
    end

    nvgRestore(vg)

    -- 更新滚动范围
    local totalH = drawY + scrollOff - startY
    local maxScroll = math.max(0, totalH - scrollArea.h)
    GS.buffSummaryScrollY = math.max(0, math.min(GS.buffSummaryScrollY or 0, maxScroll))
    GS.buffSummaryMaxScroll = maxScroll

    -- 滚动条
    if maxScroll > 0 then
        local barW = 3
        local barX2 = cx + cw - barW - 2
        local barH2 = math.max(16, scrollArea.h * (scrollArea.h / totalH))
        local barY2 = scrollArea.y + (scrollArea.h - barH2) * (scrollOff / maxScroll)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX2, barY2, barW, barH2, barW / 2)
        nvgFillColor(vg, nvgRGBA(60, 55, 50, 140))
        nvgFill(vg)
    end
end

-- ====================================================================
-- 属性汇总子面板（覆盖在角色面板上）
-- ====================================================================
function M.drawStatsSummaryOverlay(cx, cy, cw, ch)
    local vg = M.vg
    local p = GS.player
    if not p then return end

    -- 不透明遮罩（完全遮盖底层内容）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 5, cy - 5, cw + 10, ch + 10, 6)
    nvgFillColor(vg, nvgRGBA(20, 15, 8, 255))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    local lineH = 16
    local col1X = cx + 8
    local colMid = cx + math.floor(cw / 2)  -- 左右列分界
    local col2X = colMid + 4
    local col1ValR = colMid - 4   -- 左列数值右对齐位置
    local col2ValR = cx + cw - 8  -- 右列数值右对齐位置
    local startY = cy + 8

    -- 标题
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 230, 170, 255))
    nvgText(vg, cx + cw / 2, startY + 6, "属 性 汇 总", nil)
    startY = startY + 18

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + 5, startY)
    nvgLineTo(vg, cx + cw - 5, startY)
    nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    startY = startY + 5

    -- HP / MP（含装备加成）
    local bs = p.baseStats or {}
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 10)
    local hpText = "MaxHP: " .. (bs.maxHp or 0)
    nvgFillColor(vg, nvgRGBA(120, 220, 120, 230))
    nvgText(vg, col1X, startY + lineH / 2, hpText, nil)
    local hpBonus = (p.maxHp or 0) - (bs.maxHp or 0)
    if hpBonus ~= 0 then
        local hpBw = nvgTextBounds(vg, 0, 0, hpText, nil)
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(80, 230, 80, 255))
        nvgText(vg, col1X + hpBw + 3, startY + lineH / 2, string.format("(%+d)", hpBonus), nil)
        nvgFontSize(vg, 10)
    end
    local mpText = "MaxMP: " .. (bs.maxMp or 0)
    nvgFillColor(vg, nvgRGBA(100, 160, 255, 230))
    nvgText(vg, col2X, startY + lineH / 2, mpText, nil)
    local mpBonus = (p.maxMp or 0) - (bs.maxMp or 0)
    if mpBonus ~= 0 then
        local mpBw = nvgTextBounds(vg, 0, 0, mpText, nil)
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(80, 230, 80, 255))
        nvgText(vg, col2X + mpBw + 3, startY + lineH / 2, string.format("(%+d)", mpBonus), nil)
        nvgFontSize(vg, 10)
    end
    startY = startY + lineH + 2

    -- 基础属性（六维）
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + 5, startY)
    nvgLineTo(vg, cx + cw - 5, startY)
    nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 90))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)
    startY = startY + 4

    local stats = p.stats or {}
    local statNames = {
        { key = "str", name = "力量", color = nvgRGBA(255, 100, 100, 255) },
        { key = "agi", name = "敏捷", color = nvgRGBA(100, 255, 100, 255) },
        { key = "con", name = "体质", color = nvgRGBA(255, 200, 80, 255) },
        { key = "wis", name = "智慧", color = nvgRGBA(100, 180, 255, 255) },
        { key = "foc", name = "专注", color = nvgRGBA(200, 130, 255, 255) },
        { key = "per", name = "感知", color = nvgRGBA(255, 180, 220, 255) },
        { key = "luk", name = "幸运", color = nvgRGBA(255, 215, 100, 255) },
    }
    local eb = GS.getEquipBonus()
    local rankBonus = GS.getAdventurerRankBonus()
    local statBonusKeys = { str = "str", agi = "agi", con = "con", wis = "wis", foc = "foc", per = "per", wil = "wil", luk = "luk", cha = "cha" }
    for idx, st in ipairs(statNames) do
        local row = math.ceil(idx / 2)
        local col = (idx - 1) % 2
        local sx = (col == 0) and col1X or col2X
        local valRX = (col == 0) and col1ValR or col2ValR
        local sy = startY + (row - 1) * lineH
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, st.color)
        nvgText(vg, sx, sy + lineH / 2, st.name, nil)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        local baseVal = stats[st.key] or 0
        local equipBonus = (eb[statBonusKeys[st.key]] or 0) + rankBonus
        -- 凝视加成（不可知物）
        if st.key == "per" then equipBonus = equipBonus + (p._gazePer or 0) end
        if st.key == "foc" then equipBonus = equipBonus + (p._gazeFoc or 0) end
        if equipBonus > 0 then
            local bonusFmt = (equipBonus == math.floor(equipBonus)) and "+%d" or "+%.1f"
            local bonusStr = string.format(bonusFmt, equipBonus)
            nvgFontSize(vg, 9)
            local bw = nvgTextBounds(vg, 0, 0, bonusStr, nil)
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(240, 230, 210, 255))
            nvgText(vg, valRX - bw - 2, sy + lineH / 2, tostring(baseVal), nil)
            nvgFontSize(vg, 9)
            nvgFillColor(vg, nvgRGBA(80, 230, 80, 255))
            nvgText(vg, valRX, sy + lineH / 2, bonusStr, nil)
        else
            nvgFillColor(vg, nvgRGBA(240, 230, 210, 255))
            nvgText(vg, valRX, sy + lineH / 2, tostring(baseVal), nil)
        end
    end
    startY = startY + math.ceil(#statNames / 2) * lineH + 4

    -- ========== 进攻/防守 分页按钮 ==========
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + 5, startY)
    nvgLineTo(vg, cx + cw - 5, startY)
    nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 90))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)
    startY = startY + 4

    local tabH = 18
    local tabGap = 6
    local tabW = math.floor((cw - 16 - tabGap) / 2)
    local tabX1 = cx + 8
    local tabX2 = tabX1 + tabW + tabGap
    local tabY = startY
    local tabMode = GS.statsTabMode or "attack"

    -- 按钮1: 进攻属性（无底色下划线风格）
    local isAtk = (tabMode == "attack")
    local isDef = (tabMode == "defense")
    local underlineH = math.max(1.5, tabH * 0.08)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isAtk and nvgRGBA(120, 70, 20, 255) or nvgRGBA(140, 120, 90, 160))
    nvgText(vg, tabX1 + tabW / 2, tabY + tabH / 2, "进攻属性", nil)
    if isAtk then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tabX1 + tabW * 0.15, tabY + tabH - underlineH - 1, tabW * 0.7, underlineH, underlineH / 2)
        nvgFillColor(vg, nvgRGBA(180, 100, 30, 230))
        nvgFill(vg)
    end

    -- 按钮2: 防守属性（无底色下划线风格）
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isDef and nvgRGBA(120, 70, 20, 255) or nvgRGBA(140, 120, 90, 160))
    nvgText(vg, tabX2 + tabW / 2, tabY + tabH / 2, "防守属性", nil)
    if isDef then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tabX2 + tabW * 0.15, tabY + tabH - underlineH - 1, tabW * 0.7, underlineH, underlineH / 2)
        nvgFillColor(vg, nvgRGBA(180, 100, 30, 230))
        nvgFill(vg)
    end

    -- 记录按钮区域用于点击检测
    GS._statsTabAtkRect = { x = tabX1, y = tabY, w = tabW, h = tabH }
    GS._statsTabDefRect = { x = tabX2, y = tabY, w = tabW, h = tabH }

    startY = startY + tabH + 4

    -- ========== 战斗属性（按分页过滤） ==========
    -- 使用 baseStats 分离基础值和装备加值
    local attackStats = {
        { name = "物攻", val = bs.atk or 0,     bonus = (p.atk or 0) - (bs.atk or 0) },
        { name = "魔攻", val = bs.mAtk or 0,     bonus = (p.mAtk or 0) - (bs.mAtk or 0) },
        { name = "物暴值", val = bs.critVal or 0, bonus = (p.critVal or 0) - (bs.critVal or 0) },
        { name = "法暴值", val = bs.mCritRate or 0, bonus = (p.mCritRate or 0) - (bs.mCritRate or 0) },
        { name = "物暴伤", val = string.format("%d%%", math.floor(100 + (bs.critDmg or 25))), bonus = math.floor((p.critDmg or 25) - (bs.critDmg or 25)), bfmt = "%+d%%" },
        { name = "法暴伤", val = string.format("%d%%", math.floor(100 + (bs.mCritDmg or 25))), bonus = math.floor((p.mCritDmg or 25) - (bs.mCritDmg or 25)), bfmt = "%+d%%" },
        { name = "命中", val = bs.hit or 0,      bonus = (p.hit or 0) - (bs.hit or 0) },
        { name = "攻速", val = string.format("%.1f", bs.atkSpeed or 0), bonus = (p.atkSpeed or 0) - (bs.atkSpeed or 0), bfmt = "%+.1f" },
        { name = "吟唱", val = string.format("%.1f", bs.castSpeed or 0), bonus = (p.castSpeed or 0) - (bs.castSpeed or 0), bfmt = "%+.1f" },
    }
    local defenseStats = {
        { name = "物理防御力", val = bs.def or 0,       bonus = (p.def or 0) - (bs.def or 0) },
        { name = "魔法防御力", val = bs.mDef or 0,      bonus = (p.mDef or 0) - (bs.mDef or 0) },
        { name = "闪避值", val = bs.dodge or 0,     bonus = (p.dodge or 0) - (bs.dodge or 0) + GS.getPlayerDebuffTotal("dodge") },
        { name = "避开要害", val = bs.avoidCrit or 0, bonus = (p.avoidCrit or 0) - (bs.avoidCrit or 0) },
        { name = "物理吸血", val = string.format("%.1f%%", (eb.lifesteal or 0) + (eb.physLifesteal or 0)), bonus = 0 },
        { name = "法术吸血", val = string.format("%.1f%%", (eb.lifesteal or 0) + (eb.magLifesteal or 0)), bonus = 0 },
        { name = "魔力回收", val = string.format("%.2f%%", p.manaLeech or 0), bonus = 0 },
        { name = "HP自然回复", val = string.format("%.1f", bs.hpRegen or 0),  bonus = (p.hpRegen or 0) - (bs.hpRegen or 0), bfmt = "%+.1f" },
        { name = "MP自然回复", val = string.format("%.1f", bs.mpRegen or 0),  bonus = (p.mpRegen or 0) - (bs.mpRegen or 0), bfmt = "%+.1f" },
        { name = "火焰抗性", val = string.format("%.1f%%", math.min(p.resFire or 0, 30)),    bonus = 0 },
        { name = "冰冻抗性", val = string.format("%.1f%%", math.min(p.resIce or 0, 30)),     bonus = 0 },
        { name = "雷电抗性", val = string.format("%.1f%%", math.min(p.resElec or 0, 30)),    bonus = 0 },
        { name = "神圣抗性", val = string.format("%.1f%%", math.min(p.resLight or 0, 30)),   bonus = 0 },
        { name = "暗影抗性", val = string.format("%.1f%%", math.min(p.resDark or 0, 30)),    bonus = 0 },
        { name = "自然抗性", val = string.format("%.1f%%", math.min(p.resNature or 0, 30)), bonus = 0 },
    }

    local combatStats = isAtk and attackStats or defenseStats
    for idx, cs in ipairs(combatStats) do
        local row = math.ceil(idx / 2)
        local col = (idx - 1) % 2
        local sx = (col == 0) and col1X or col2X
        local valRX = (col == 0) and col1ValR or col2ValR
        local sy = startY + (row - 1) * lineH
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        drawTextOutlined(vg, sx, sy + lineH / 2, cs.name, 50, 30, 10, 255)

        -- 基础数值
        local valStr = tostring(cs.val)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if cs.bonus and cs.bonus ~= 0 then
            -- 有装备加成：先画数值，再在右边追加绿色 +X
            local _bfmt3 = cs.bfmt or ((cs.bonus == math.floor(cs.bonus)) and "%+d" or "%+.1f")
            local bonusStr = string.format(_bfmt3, cs.bonus)
            -- 先测量加成文字宽度，数值右对齐到 valRX - 加成宽度 - 间距
            nvgFontSize(vg, 9)
            local bw = nvgTextBounds(vg, 0, 0, bonusStr, nil)
            local gap = 2
            -- 画基础数值
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(30, 25, 15, 255))
            nvgText(vg, valRX - bw - gap, sy + lineH / 2, valStr, nil)
            -- 画加成（正绿负红）
            nvgFontSize(vg, 9)
            if cs.bonus > 0 then
                nvgFillColor(vg, nvgRGBA(20, 120, 20, 255))
            else
                nvgFillColor(vg, nvgRGBA(180, 40, 30, 255))
            end
            nvgText(vg, valRX, sy + lineH / 2, bonusStr, nil)
        else
            nvgFillColor(vg, nvgRGBA(30, 25, 15, 255))
            nvgText(vg, valRX, sy + lineH / 2, valStr, nil)
        end
    end

    -- 底部关闭提示
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 80, 55, 150))
    nvgText(vg, cx + cw / 2, cy + ch - 6, "点击任意处关闭", nil)
end

-- ====================================================================
-- 面板内容：背包网格（Tab 2）
-- ====================================================================
function M.drawInventoryGrid(cx, cy, cw, ch)
    local vg = M.vg
    nvgFontFace(vg, "sans")

    -- ========== 等距布局规则 ==========
    -- 4个等宽边距 margin：
    --   金边→装备左列 = 装备右列→分隔线 = 分隔线→背包左列 = 背包右列→金边
    -- 装备两列间距 eGap = 2 × margin
    -- 所有格子统一大小，通过调整格子尺寸来满足等距约束
    --
    -- 水平：cw = 4*margin + 2*margin + 7*slotSize + (cols-1)*sGap
    --      = 6*margin + 7*slotSize + (cols-1)*sGap
    -- 垂直：ch >= eSlotRows*(slotSize+eLabelH) + (eSlotRows-1)*sGap

    local sGap = 3       -- 格子间距（水平/垂直通用）
    local eLabelH = 10   -- 装备标签高度
    local eSlotRows = 7
    local cols = GS.INV_SHOW_COLS  -- 5
    local scrollBarW = 6  -- 滚动条宽度

    -- 垂直方向最大格子尺寸
    local sMaxV = math.floor((ch - (eSlotRows - 1) * sGap) / eSlotRows - eLabelH)
    -- 水平方向最大格子尺寸（保证边距 >= 6）
    local minMargin = 6
    local sMaxH = math.floor((cw - (cols - 1) * sGap - 6 * minMargin) / 7)

    local slotSize = math.max(18, math.min(sMaxV, sMaxH))
    local eSlotSize = slotSize
    local slotGap = sGap

    -- 反推等宽边距，eGap = 2 * margin
    local margin = math.floor((cw - 7 * slotSize - (cols - 1) * sGap) / 6)
    local eGap = margin * 2

    -- 装备栏列 X 坐标
    local eCol1X = cx + margin
    local eCol2X = eCol1X + slotSize + eGap
    -- 分隔线 X（第2/3个margin之间）
    local divLineX = eCol2X + slotSize + margin
    -- 背包首列 X
    local bagGridX = divLineX + margin
    -- 背包区域（用于裁剪/滚动条）
    local totalGridW = cols * slotSize + (cols - 1) * sGap
    local bagX = bagGridX
    local bagW = totalGridW + scrollBarW + 4  -- 包含滚动条空间

    -- 垂直居中
    local eRowH = slotSize + eLabelH
    local totalSlotH = eSlotRows * eRowH + (eSlotRows - 1) * sGap
    local slotStartY = cy + math.floor((ch - totalSlotH) / 2)
    if slotStartY < cy then slotStartY = cy end

    -- ========== 左侧：装备栏 ==========
    do
        local col1X = eCol1X
        local col2X = eCol2X

        -- 拖拽装备时，计算哪些槽位可以接受该物品（用于绿色高亮）
        local dragHighlightSlots = {}
        if GS.itemDragActive and GS.dragSlotIdx then
            local dragItem = GS.inventory[GS.dragSlotIdx]
            if dragItem and dragItem.slot then
                local playerLv = (GS.player and GS.player.level) or 1
                local levelOk = not dragItem.level or playerLv >= dragItem.level
                if levelOk then
                    -- 戒指：ring1 类型物品可装入 ring1 或 ring2
                    if dragItem.slot == "ring1" then
                        dragHighlightSlots["ring1"] = true
                        dragHighlightSlots["ring2"] = true
                    else
                        dragHighlightSlots[dragItem.slot] = true
                    end
                    -- 匕首双持：刺客可将匕首拖到左手
                    if dragItem.weaponTag == "匕首" and dragItem.slot == "weapon_r" and GS.currentClass == "assassin" then
                        dragHighlightSlots["weapon_l"] = true
                    end
                    -- 右手武器职业限制检查
                    if dragItem.slot == "weapon_r" and dragItem.weaponTag then
                        local allowed = GS.CLASS_WEAPON_R and GS.CLASS_WEAPON_R[GS.currentClass]
                        if allowed and not allowed[dragItem.weaponTag] then
                            dragHighlightSlots["weapon_r"] = nil
                            dragHighlightSlots["weapon_l"] = nil
                        end
                    end
                    -- 副手职业限制检查
                    if dragItem.slot == "weapon_l" and dragItem.offhandTag then
                        if not GS.checkOffhand(dragItem.offhandTag) then
                            dragHighlightSlots["weapon_l"] = nil
                        end
                    end
                end
            end
        end

        GS.equipSlotAreas = {}
        local leftIdx, rightIdx = 0, 0
        for _, slot in ipairs(GS.equipSlotDefs) do
            local sx, sy
            if slot.col == "L" then
                leftIdx = leftIdx + 1
                sx = col1X
                sy = slotStartY + (leftIdx - 1) * (eRowH + sGap)
            else
                rightIdx = rightIdx + 1
                sx = col2X
                sy = slotStartY + (rightIdx - 1) * (eRowH + sGap)
            end

            GS.equipSlotAreas[slot.id] = { x = sx, y = sy, w = eSlotSize, h = eSlotSize }

            local equipped = GS.equipment[slot.id]
            local sr = math.max(2, math.floor(eSlotSize * 0.12))

            -- 外框描边（拖拽装备时匹配的槽位绿色高亮）
            local isHighlight = dragHighlightSlots[slot.id]
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx - 1, sy - 1, eSlotSize + 2, eSlotSize + 2, sr + 1)
            if isHighlight then
                nvgStrokeColor(vg, nvgRGBA(60, 220, 80, 255))
                nvgStrokeWidth(vg, 2.5)
            else
                nvgStrokeColor(vg, nvgRGBA(90, 65, 30, 220))
                nvgStrokeWidth(vg, 1.5)
            end
            nvgStroke(vg)

            -- 高亮时额外绘制内发光效果
            if isHighlight then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx, sy, eSlotSize, eSlotSize, sr)
                nvgStrokeColor(vg, nvgRGBA(60, 220, 80, 80))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            end

            -- 内凹底色（脆化装备变红）
            local slotGrad2
            if equipped and equipped.brittle then
                slotGrad2 = nvgLinearGradient(vg, sx, sy, sx, sy + eSlotSize,
                    nvgRGBA(200, 30, 30, 240), nvgRGBA(255, 50, 40, 240))
            else
                slotGrad2 = nvgLinearGradient(vg, sx, sy, sx, sy + eSlotSize,
                    nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, eSlotSize, eSlotSize, sr)
            nvgFillPaint(vg, slotGrad2)
            nvgFill(vg)

            -- 上边内阴影
            local shadowH = math.max(2, math.floor(eSlotSize * 0.2))
            local topShadow = nvgLinearGradient(vg, sx, sy, sx, sy + shadowH,
                nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, eSlotSize, shadowH, sr)
            nvgFillPaint(vg, topShadow)
            nvgFill(vg)

            -- 底部微光
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + sr, sy + eSlotSize - 1)
            nvgLineTo(vg, sx + eSlotSize - sr, sy + eSlotSize - 1)
            nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 装备图标
            if equipped then
                local eqImg = equipped.icon and GS.itemImages[equipped.icon]
                if eqImg then
                    local ep = 2
                    local eqPaint = nvgImagePattern(vg,
                        sx + ep, sy + ep,
                        eSlotSize - ep * 2, eSlotSize - ep * 2,
                        0, eqImg, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx + ep, sy + ep, eSlotSize - ep * 2, eSlotSize - ep * 2, sr)
                    nvgFillPaint(vg, eqPaint)
                    nvgFill(vg)
                end
            end

            -- 深渊词缀标识：深紫色垂直缎带（与附魔星水平居中，限定在图片区域内使黑色边框压住缎带）
            if equipped and equipped.abyssAffix then
                local sw = eSlotSize
                local ep = 2
                local rW = sw * 0.15
                nvgSave(vg)
                nvgIntersectScissor(vg, sx + ep, sy + ep, sw - ep * 2, sw - ep * 2)
                nvgBeginPath(vg)
                nvgRect(vg, sx + 5 - rW / 2, sy + ep, rW, sw - ep * 2)
                nvgFillColor(vg, nvgRGBA(90, 0, 155, 230))
                nvgFill(vg)
                nvgRestore(vg)
            end
            -- 精炼槽标识：十字飞镖形状，4个尖臂代表4个精炼槽（先画，衬于附魔星下方）
            if equipped and equipped.refineSlots and #equipped.refineSlots > 0 then
                local rfCx = sx + 5
                local rfCy = sy + 5
                local armD = 2.5   -- 臂尖沿对角线的分量
                local valD = 1.2   -- 凹谷到中心的距离
                -- 4个臂尖（对角线）：左上、右上、右下、左下
                local tips = {
                    { rfCx - armD, rfCy - armD }, { rfCx + armD, rfCy - armD },
                    { rfCx + armD, rfCy + armD }, { rfCx - armD, rfCy + armD },
                }
                -- 4个凹谷（十字方向）：左、上、右、下
                local vals = {
                    { rfCx - valD, rfCy }, { rfCx, rfCy - valD },
                    { rfCx + valD, rfCy }, { rfCx, rfCy + valD },
                }
                for ri, rslot in ipairs(equipped.refineSlots) do
                    if ri > 4 then break end
                    local vi1 = ri
                    local vi2 = (ri % 4) + 1
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, rfCx, rfCy)
                    nvgLineTo(vg, vals[vi1][1], vals[vi1][2])
                    nvgLineTo(vg, tips[ri][1], tips[ri][2])
                    nvgLineTo(vg, vals[vi2][1], vals[vi2][2])
                    nvgClosePath(vg)
                    if rslot.attr then
                        local rt = rslot.rolledTier or 0
                        local rr = (rt <= 1 and "common") or (rt <= 3 and "uncommon") or (rt <= 5 and "rare") or (rt <= 7 and "fine") or "superior"
                        local rc = GS.RARITY[rr] and GS.RARITY[rr].color or {200,200,200}
                        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
                        nvgFill(vg)
                        nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1]+50), math.min(255, rc[2]+50), math.min(255, rc[3]+50), 255))
                    else
                        nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 120))
                    end
                    nvgStrokeWidth(vg, 0.8)
                    nvgStroke(vg)
                end
            end

            -- 附魔标识：左上角四芒星，颜色按稀有度（后画，覆盖在精炼星上方）
            if equipped and equipped.enchantment then
                local ert = GS.getItemTier(equipped)
                local err = (ert <= 1 and "common") or (ert <= 3 and "uncommon") or (ert <= 5 and "rare") or (ert <= 7 and "fine") or "superior"
                local erc = GS.RARITY[err] and GS.RARITY[err].color or {80,160,255}
                local starCx = sx + 5
                local starCy = sy + 5
                local starR = 2.5
                nvgBeginPath(vg)
                nvgMoveTo(vg, starCx, starCy - starR)
                nvgLineTo(vg, starCx + starR * 0.3, starCy - starR * 0.3)
                nvgLineTo(vg, starCx + starR, starCy)
                nvgLineTo(vg, starCx + starR * 0.3, starCy + starR * 0.3)
                nvgLineTo(vg, starCx, starCy + starR)
                nvgLineTo(vg, starCx - starR * 0.3, starCy + starR * 0.3)
                nvgLineTo(vg, starCx - starR, starCy)
                nvgLineTo(vg, starCx - starR * 0.3, starCy - starR * 0.3)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(erc[1], erc[2], erc[3], 240))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(math.min(255, erc[1]+60), math.min(255, erc[2]+60), math.min(255, erc[3]+60), 255))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end

            -- 宝石插槽标识（圆形，叠于附魔标识上方，居中）
            if equipped and equipped.gemSlots and #equipped.gemSlots > 0 then
                local gemCx = sx + 5
                local gemCy = sy + 5
                local gemR = 1.0
                local rarityRank = { common=1, uncommon=2, rare=3, fine=4, superior=5, epic=6, legendary=7, divine=8 }
                local hasGem = false
                local bestRarity = nil
                for _, gs in ipairs(equipped.gemSlots) do
                    if gs.gemId then
                        hasGem = true
                        local gemTpl = GS.itemTemplates[gs.gemId]
                        if gemTpl then
                            local gr = gemTpl.rarity or "common"
                            if not bestRarity or (rarityRank[gr] or 0) > (rarityRank[bestRarity] or 0) then
                                bestRarity = gr
                            end
                        end
                    end
                end
                local gc
                if hasGem and bestRarity then
                    gc = GS.RARITY[bestRarity] and GS.RARITY[bestRarity].color or {80, 200, 255}
                else
                    gc = {160, 160, 160}
                end
                -- 深色底衬
                nvgBeginPath(vg)
                nvgCircle(vg, gemCx, gemCy, gemR + 0.5)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
                nvgFill(vg)
                -- 主体圆
                nvgBeginPath(vg)
                nvgCircle(vg, gemCx, gemCy, gemR)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], hasGem and 245 or 180))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(math.min(255, gc[1]+60), math.min(255, gc[2]+60), math.min(255, gc[3]+60), hasGem and 255 or 200))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            end

            -- 强化等级（右下角，半透明背景 + 稀有度颜色文字）
            if equipped and equipped.enhanceLevel and equipped.enhanceLevel > 0 then
                local enhText = "+" .. equipped.enhanceLevel
                local enhFs = math.max(7, math.floor(eSlotSize * 0.28))
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, enhFs)
                local etw = nvgTextBounds(vg, 0, 0, enhText, nil, nil)
                local ePad = 2
                local eBgW = etw + ePad * 2
                local eBgH = enhFs + 3
                local eBgX = sx + eSlotSize - eBgW
                local eBgY = sy + eSlotSize - eBgH
                nvgBeginPath(vg)
                nvgRoundedRect(vg, eBgX, eBgY, eBgW, eBgH, 3)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
                nvgFill(vg)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local _, enhC = GS.getEnhanceRarity(equipped.enhanceLevel)
                nvgFillColor(vg, nvgRGBA(enhC[1], enhC[2], enhC[3], 255))
                nvgText(vg, eBgX + eBgW * 0.5, eBgY + eBgH * 0.5, enhText, nil)
            end

            -- 锁定标识（右上角图片）
            if equipped and equipped.locked and M.lockClosedImg > 0 then
                local lockSz = math.max(10, eSlotSize * 0.32)
                local lx = sx + eSlotSize - lockSz - 1
                local ly = sy + 1
                local paint = nvgImagePattern(vg, lx, ly, lockSz, lockSz, 0, M.lockClosedImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, lx, ly, lockSz, lockSz)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end

            -- 收藏标识（左下角路径五角星，金属质感）
            if equipped and equipped.starred then
                local starR = math.max(4, eSlotSize * 0.15)
                local stcx = sx + 1 + starR
                local stcy = sy + eSlotSize - 1 - starR
                M.drawStarPath(vg, stcx, stcy, starR, "slot", true)
            end

            -- 槽位名称（显示在格子下方）
            local labelFs = math.max(7, math.min(eSlotSize * 0.30, 9))
            nvgFontSize(vg, labelFs)
            local label = equipped and ((equipped.name or slot.name):gsub(" %+%d+$", "")) or slot.name
            local labelAlpha = equipped and 220 or 200
            local lr, lg, lb = 55, 35, 15
            if equipped then
                local rd = GS.RARITY[equipped.rarity]
                if rd and rd.color then
                    lr, lg, lb = rd.color[1], rd.color[2], rd.color[3]
                end
            end
            -- 已装备时：绘制左右渐变淡出的灰色衬底（宽度跟随文字）
            if equipped then
                local labelY = sy + eSlotSize + 1
                local bgH = labelFs + 2
                local bgTopY = labelY
                local textW = nvgTextBounds(vg, 0, 0, label, nil)
                local fadeW = 6  -- 两侧渐变淡出区域
                local bgW = textW + fadeW * 2
                local bgX = sx + eSlotSize / 2 - bgW / 2
                local midX = bgX + fadeW
                local midW = textW
                -- 左侧渐变：透明→灰
                local gradL = nvgLinearGradient(vg, bgX, labelY, midX, labelY,
                    nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 90))
                nvgBeginPath(vg)
                nvgRect(vg, bgX, bgTopY, fadeW, bgH)
                nvgFillPaint(vg, gradL)
                nvgFill(vg)
                -- 中间实色
                nvgBeginPath(vg)
                nvgRect(vg, midX, bgTopY, midW, bgH)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 90))
                nvgFill(vg)
                -- 右侧渐变：灰→透明
                local gradR = nvgLinearGradient(vg, midX + midW, labelY, midX + midW + fadeW, labelY,
                    nvgRGBA(0, 0, 0, 90), nvgRGBA(0, 0, 0, 0))
                nvgBeginPath(vg)
                nvgRect(vg, midX + midW, bgTopY, fadeW, bgH)
                nvgFillPaint(vg, gradR)
                nvgFill(vg)
            end

            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            drawTextOutlined(vg, sx + eSlotSize / 2, sy + eSlotSize + 1, label, lr, lg, lb, labelAlpha)
        end
    end

    -- 左右分隔竖线
    nvgBeginPath(vg)
    nvgMoveTo(vg, divLineX, cy + 2)
    nvgLineTo(vg, divLineX, cy + ch - 2)
    nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 90))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- ========== 右侧：背包格子 ==========
    local bagSlots = GS.bagSlots
    local totalRows = math.ceil(bagSlots / cols)
    local step = slotSize + slotGap

    -- 内容总高度
    local contentH = totalRows * step - slotGap
    -- 可视区域：顶部与装备栏首行对齐
    local viewY = slotStartY
    local viewBottom = cy + ch
    local maxViewH = GS.INV_SHOW_ROWS * step - slotGap
    local viewH = math.min(viewBottom - viewY, maxViewH)
    GS.invContentH = contentH
    GS.invVisibleH = viewH
    GS.invClipRect = { x = bagX, y = viewY, w = bagW, h = viewH }

    -- 滚动范围限制
    local maxScroll = math.max(0, contentH - viewH)
    if GS.invScrollY < 0 then GS.invScrollY = 0 end
    if GS.invScrollY > maxScroll then GS.invScrollY = maxScroll end
    local scrollY = GS.invScrollY

    -- 格子起始 X（等距布局已精确计算）
    local gridOffX = bagGridX

    -- 背包容量显示（已用/上限）
    do
        local usedCount = 0
        for i = 1, bagSlots do
            if GS.inventory[i] then usedCount = usedCount + 1 end
        end
        local capText = usedCount .. "/" .. bagSlots
        local capFontSize = 10
        nvgFontSize(vg, capFontSize)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        local capX = gridOffX + (cols - 1) * step + slotSize
        local capY = viewY - 2
        nvgText(vg, capX, capY, capText, nil)
    end

    -- 裁剪区域
    nvgSave(vg)
    nvgIntersectScissor(vg, bagX, viewY, bagW, viewH)

    GS.inventorySlotAreas = {}

    for i = 1, bagSlots do
        local row = math.ceil(i / cols)
        local col = ((i - 1) % cols) + 1
        local sx = gridOffX + (col - 1) * step
        local sy = viewY + (row - 1) * step - scrollY

        -- 跳过完全不可见的行
        if sy + slotSize >= viewY and sy <= viewY + viewH then
            GS.inventorySlotAreas[i] = { x = sx, y = sy, w = slotSize, h = slotSize }

            local item = GS.inventory[i]
            local isDragSource = GS.itemDragActive and GS.dragSlotIdx == i

            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
            if isDragSource then
                nvgFillColor(vg, nvgRGBA(60, 45, 20, 180))
            elseif item and item.brittle then
                nvgFillColor(vg, nvgRGBA(220, 40, 40, 255))
            elseif item then
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            else
                nvgFillColor(vg, nvgRGBA(95, 62, 30, 180))
            end
            nvgFill(vg)

            -- 右下高光
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + slotSize, sy)
            nvgLineTo(vg, sx + slotSize, sy + slotSize)
            nvgLineTo(vg, sx, sy + slotSize)
            nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 120))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 左上阴影
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy + slotSize)
            nvgLineTo(vg, sx, sy)
            nvgLineTo(vg, sx + slotSize, sy)
            nvgStrokeColor(vg, nvgRGBA(40, 25, 10, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            if item then
                -- 绘制物品图片
                local imgHandle = item.icon and GS.itemImages[item.icon]
                local itemAlpha = isDragSource and 0.3 or 1.0
                if imgHandle then
                    local pad = 2
                    local imgPaint = nvgImagePattern(vg,
                        sx + pad, sy + pad,
                        slotSize - pad * 2, slotSize - pad * 2,
                        0, imgHandle, itemAlpha)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx + pad, sy + pad, slotSize - pad * 2, slotSize - pad * 2, 2)
                    nvgFillPaint(vg, imgPaint)
                    nvgFill(vg)
                else
                    -- 无图片时显示名称首字
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, math.max(12, slotSize * 0.45))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    local firstChar = item.name and string.sub(item.name, 1, 3) or "?"
                    drawTextOutlined(vg, sx + slotSize / 2, sy + slotSize / 2, firstChar, 50, 35, 15, 255)
                end
                -- 深渊词缀标识：深紫色垂直缎带（限定在图片区域内使黑色边框压住缎带，intersect保留面板裁剪区防溢出）
                if item.abyssAffix then
                    local sw = slotSize
                    local pad = 2
                    local rW = sw * 0.15
                    nvgSave(vg)
                    nvgIntersectScissor(vg, sx + pad, sy + pad, sw - pad * 2, sw - pad * 2)
                    nvgBeginPath(vg)
                    nvgRect(vg, sx + 5 - rW / 2, sy + pad, rW, sw - pad * 2)
                    nvgFillColor(vg, nvgRGBA(90, 0, 155, 230))
                    nvgFill(vg)
                    nvgRestore(vg)
                end
                -- 稀有度边框
                local rarityDef = GS.RARITY[item.rarity]
                if rarityDef then
                    local bc = rarityDef.border
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx + 0.5, sy + 0.5, slotSize - 1, slotSize - 1, 3)
                    nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 200))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end
                -- 精炼槽标识：十字飞镖形状，4个尖臂代表4个精炼槽（先画，衬于附魔星下方）
                if item.refineSlots and #item.refineSlots > 0 then
                    local rfCx = sx + 5
                    local rfCy = sy + 5
                    local armD = 2.5
                    local valD = 1.2
                    local tips = {
                        { rfCx - armD, rfCy - armD }, { rfCx + armD, rfCy - armD },
                        { rfCx + armD, rfCy + armD }, { rfCx - armD, rfCy + armD },
                    }
                    local vals = {
                        { rfCx - valD, rfCy }, { rfCx, rfCy - valD },
                        { rfCx + valD, rfCy }, { rfCx, rfCy + valD },
                    }
                    for ri, rslot in ipairs(item.refineSlots) do
                        if ri > 4 then break end
                        local vi1 = ri
                        local vi2 = (ri % 4) + 1
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, rfCx, rfCy)
                        nvgLineTo(vg, vals[vi1][1], vals[vi1][2])
                        nvgLineTo(vg, tips[ri][1], tips[ri][2])
                        nvgLineTo(vg, vals[vi2][1], vals[vi2][2])
                        nvgClosePath(vg)
                        if rslot.attr then
                            local rt = rslot.rolledTier or 0
                            local rr = (rt <= 1 and "common") or (rt <= 3 and "uncommon") or (rt <= 5 and "rare") or (rt <= 7 and "fine") or "superior"
                            local rc = GS.RARITY[rr] and GS.RARITY[rr].color or {200,200,200}
                            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
                            nvgFill(vg)
                            nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1]+50), math.min(255, rc[2]+50), math.min(255, rc[3]+50), 255))
                        else
                            nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 120))
                        end
                        nvgStrokeWidth(vg, 0.8)
                        nvgStroke(vg)
                    end
                end
                -- 附魔标识：左上角四芒星，颜色按稀有度（后画，覆盖在精炼星上方）
                if item.enchantment then
                    local ert = GS.getItemTier(item)
                    local err = (ert <= 1 and "common") or (ert <= 3 and "uncommon") or (ert <= 5 and "rare") or (ert <= 7 and "fine") or "superior"
                    local erc = GS.RARITY[err] and GS.RARITY[err].color or {80,160,255}
                    local starCx = sx + 5
                    local starCy = sy + 5
                    local starR = 2.5
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, starCx, starCy - starR)
                    nvgLineTo(vg, starCx + starR * 0.3, starCy - starR * 0.3)
                    nvgLineTo(vg, starCx + starR, starCy)
                    nvgLineTo(vg, starCx + starR * 0.3, starCy + starR * 0.3)
                    nvgLineTo(vg, starCx, starCy + starR)
                    nvgLineTo(vg, starCx - starR * 0.3, starCy + starR * 0.3)
                    nvgLineTo(vg, starCx - starR, starCy)
                    nvgLineTo(vg, starCx - starR * 0.3, starCy - starR * 0.3)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(erc[1], erc[2], erc[3], 240))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(math.min(255, erc[1]+60), math.min(255, erc[2]+60), math.min(255, erc[3]+60), 255))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                end
                -- 宝石插槽标识（圆形，叠于附魔标识上方，居中）
                if item.gemSlots and #item.gemSlots > 0 then
                    local gemCx = sx + 5
                    local gemCy = sy + 5
                    local gemR = 1.0
                    local rarityRank = { common=1, uncommon=2, rare=3, fine=4, superior=5, epic=6, legendary=7, divine=8 }
                    local hasGem = false
                    local bestRarity = nil
                    for _, gs in ipairs(item.gemSlots) do
                        if gs.gemId then
                            hasGem = true
                            local gemTpl = GS.itemTemplates[gs.gemId]
                            if gemTpl then
                                local gr = gemTpl.rarity or "common"
                                if not bestRarity or (rarityRank[gr] or 0) > (rarityRank[bestRarity] or 0) then
                                    bestRarity = gr
                                end
                            end
                        end
                    end
                    local gc
                    if hasGem and bestRarity then
                        gc = GS.RARITY[bestRarity] and GS.RARITY[bestRarity].color or {80, 200, 255}
                    else
                        gc = {160, 160, 160}
                    end
                    -- 深色底衬
                    nvgBeginPath(vg)
                    nvgCircle(vg, gemCx, gemCy, gemR + 0.5)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
                    nvgFill(vg)
                    -- 主体圆
                    nvgBeginPath(vg)
                    nvgCircle(vg, gemCx, gemCy, gemR)
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], hasGem and 245 or 180))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(math.min(255, gc[1]+60), math.min(255, gc[2]+60), math.min(255, gc[3]+60), hasGem and 255 or 200))
                    nvgStrokeWidth(vg, 0.8)
                    nvgStroke(vg)
                end
                -- 书籍已读标记（左上角绿色√，圆角矩形底板）
                if item.templateId and GS.elfvahBooksRead and GS.elfvahBooksRead[item.templateId] then
                    local checkSz = math.max(8, slotSize * 0.30)
                    local checkX = sx + 1
                    local checkY = sy + 1
                    local checkR = math.max(1.5, slotSize * 0.06)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, checkX, checkY, checkSz, checkSz, checkR)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
                    nvgFill(vg)
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, math.max(7, checkSz * 0.75))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(80, 220, 80, 255))
                    nvgText(vg, checkX + checkSz * 0.5, checkY + checkSz * 0.5, "✓", nil)
                end
                -- 强化等级（右下角，半透明背景 + 稀有度颜色文字）
                if item.enhanceLevel and item.enhanceLevel > 0 then
                    local enhText = "+" .. item.enhanceLevel
                    local enhFs = math.max(7, math.floor(slotSize * 0.28))
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, enhFs)
                    local etw = nvgTextBounds(vg, 0, 0, enhText, nil, nil)
                    local ePad = 2
                    local eBgW = etw + ePad * 2
                    local eBgH = enhFs + 3
                    local eBgX = sx + slotSize - eBgW
                    local eBgY = sy + slotSize - eBgH
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, eBgX, eBgY, eBgW, eBgH, 3)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
                    nvgFill(vg)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    local _, enhC = GS.getEnhanceRarity(item.enhanceLevel)
                    nvgFillColor(vg, nvgRGBA(enhC[1], enhC[2], enhC[3], 255))
                    nvgText(vg, eBgX + eBgW * 0.5, eBgY + eBgH * 0.5, enhText, nil)
                end
                -- 右下角标签：堆叠数量
                if item.stackable and item.quantity and item.quantity > 1 then
                    local qtyText = tostring(item.quantity)
                    local lvFs = math.max(7, math.floor(slotSize * 0.28))
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, lvFs)
                    local tw = nvgTextBounds(vg, 0, 0, qtyText, nil, nil)
                    local pad = 3
                    local bgW = tw + pad * 2
                    local bgH = lvFs + 4
                    local bgX = sx + slotSize - bgW
                    local bgY = sy + slotSize - bgH
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 3)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                    nvgFill(vg)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                    nvgText(vg, bgX + bgW * 0.5, bgY + bgH * 0.5, qtyText, nil)
                end
            end

            -- 消耗品冷却遮罩
            if item and item.consumable and GS.consumableCooldown > 0 then
                -- 半透明灰色遮罩
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
                nvgFill(vg)
                -- CD 数字
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(14, slotSize * 0.5))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
                nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, tostring(GS.consumableCooldown), nil)
            end

            -- 多选模式：选中标记
            if GS.invMultiSelect and item and GS.invSelected[i] then
                -- 半透明绿色覆盖
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
                nvgFillColor(vg, nvgRGBA(20, 160, 20, 60))
                nvgFill(vg)
                -- 绿色边框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + 0.5, sy + 0.5, slotSize - 1, slotSize - 1, 3)
                nvgStrokeColor(vg, nvgRGBA(20, 180, 20, 220))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
                -- 右上角勾选图标
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(10, slotSize * 0.35))
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                nvgText(vg, sx + slotSize - 1, sy + 1, "✓", nil)
            end
            -- 锁定标识（右上角图片）
            if item and item.locked and M.lockClosedImg > 0 then
                local lockSz = math.max(10, slotSize * 0.32)
                local lx = sx + slotSize - lockSz - 1
                local ly = sy + 1
                local paint = nvgImagePattern(vg, lx, ly, lockSz, lockSz, 0, M.lockClosedImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, lx, ly, lockSz, lockSz)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
            -- 收藏标识（左下角路径五角星，金属质感）
            if item and item.starred then
                local starR = math.max(4, slotSize * 0.15)
                local stcx = sx + 1 + starR
                local stcy = sy + slotSize - 1 - starR
                M.drawStarPath(vg, stcx, stcy, starR, "slot", true)
            end
        else
            GS.inventorySlotAreas[i] = nil
        end
    end

    nvgRestore(vg)

    -- 滚动条（仅当内容超出可视区域时）
    GS.invScrollBarRect = nil
    GS.invScrollBarTrack = nil
    if contentH > viewH then
        local barW = 10
        local hitW = 20  -- 点击热区比视觉更宽
        local barX2 = bagX + bagW - barW + 3
        local barAreaH = viewH
        local barH = math.max(20, barAreaH * (viewH / contentH))
        local scrollRatio = maxScroll > 0 and (scrollY / maxScroll) or 0
        local barY = viewY + (barAreaH - barH) * scrollRatio

        -- 存储几何信息供 Input 使用
        GS.invScrollBarRect = { x = barX2 - (hitW - barW) / 2, y = barY, w = hitW, h = barH }
        GS.invScrollBarTrack = { x = barX2, y = viewY, w = barW, h = barAreaH }

        -- 拖动时高亮
        local isDragging = GS.invScrollBarDragging
        local isHover = not isDragging and isHovered(barX2 - (hitW - barW) / 2, barY, hitW, barH)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX2, barY, barW, barH, barW / 2)
        if isDragging then
            nvgFillColor(vg, nvgRGBA(140, 120, 80, 200))
        elseif isHover then
            nvgFillColor(vg, nvgRGBA(100, 90, 65, 180))
        else
            nvgFillColor(vg, nvgRGBA(60, 55, 50, 140))
        end
        nvgFill(vg)
    end

    -- ========== 整理/多选 操作按钮 ==========
    do
        local btnH = slotSize
        local btnGap = sGap
        local btnY = viewY + viewH + sGap

        -- 清除旧的稀有度按钮 rect（非多选时不应保留）
        GS.invActionBtnRects.btnN = nil
        GS.invActionBtnRects.btnUC = nil
        GS.invActionBtnRects.btnR = nil
        GS.invActionBtnRects.btnF = nil
        -- 多选模式下清除拆分按钮区域和过滤按钮
        if GS.invMultiSelect then
            GS.splitBtnRect = nil
            GS.invActionBtnRects.btn3 = nil
            GS.lootFilterPanelRect = nil
            GS.lootFilterCheckRect = nil
            GS.lootFilterCheckRectRare = nil
            GS.lootFilterCheckRectFine = nil
        end

        if GS.invMultiSelect then
            -- 多选模式：第一行 N | UC | R | 精良 | 销毁，第二行 取消
            GS.invActionBtnRects.btnF = nil
            local btnCount = 5
            local btnW = math.floor((totalGridW - (btnCount - 1) * btnGap) / btnCount)
            local selCount = 0
            for _ in pairs(GS.invSelected) do selCount = selCount + 1 end

            local btnDefs = {
                { key = "btnN",  style = "rarity", rarity = "common" },
                { key = "btnUC", style = "rarity", rarity = "uncommon" },
                { key = "btnR",  style = "rarity", rarity = "rare" },
                { key = "btnF",  style = "rarity", rarity = "fine" },
                { key = "btn2", label = (GS.warehouseMode or GS.sharedStorageMode) and "存入" or (GS.shopMode and "出售" or "销毁"), style = (GS.warehouseMode or GS.sharedStorageMode) and "warehouse" or "destructive" },
            }

            for i, def in ipairs(btnDefs) do
                local bx = bagGridX + (i - 1) * (btnW + btnGap)
                GS.invActionBtnRects[def.key] = { x = bx, y = btnY, w = btnW, h = btnH }

                -- 按钮背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, btnY, btnW, btnH, 3)
                if def.style == "warehouse" then
                    if selCount > 0 then
                        local dGrad = nvgLinearGradient(vg, bx, btnY, bx, btnY + btnH,
                            nvgRGBA(35, 110, 170, 220), nvgRGBA(20, 80, 130, 220))
                        nvgFillPaint(vg, dGrad)
                    else
                        nvgFillColor(vg, nvgRGBA(60, 80, 100, 150))
                    end
                elseif def.style == "destructive" then
                    if selCount > 0 then
                        local dGrad = nvgLinearGradient(vg, bx, btnY, bx, btnY + btnH,
                            nvgRGBA(160, 40, 30, 220), nvgRGBA(120, 25, 15, 220))
                        nvgFillPaint(vg, dGrad)
                    else
                        nvgFillColor(vg, nvgRGBA(80, 60, 40, 150))
                    end
                elseif def.style == "rarity" then
                    local rImg = M.rarityImages and M.rarityImages[def.rarity]
                    if rImg and rImg ~= -1 then
                        local imgPat = nvgImagePattern(vg, bx, btnY, btnW, btnH, 0, rImg, 1.0)
                        nvgFillPaint(vg, imgPat)
                    else
                        local rc = GS.RARITY[def.rarity].color
                        local grad = nvgLinearGradient(vg, bx, btnY, bx, btnY + btnH,
                            nvgRGBA(rc[1], rc[2], rc[3], 220), nvgRGBA(math.floor(rc[1]*0.6), math.floor(rc[2]*0.6), math.floor(rc[3]*0.6), 220))
                        nvgFillPaint(vg, grad)
                    end
                else
                    local grad = nvgLinearGradient(vg, bx, btnY, bx, btnY + btnH,
                        nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
                    nvgFillPaint(vg, grad)
                end
                nvgFill(vg)

                -- 边框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 3)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)

                -- 文字（稀有度按钮不显示文字）
                if def.label then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, slotSize * 0.45)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    if def.style == "destructive" then
                        nvgFillColor(vg, nvgRGBA(255, 200, 180, 240))
                    elseif def.style == "warehouse" then
                        nvgFillColor(vg, nvgRGBA(200, 230, 255, 240))
                    else
                        nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))
                    end
                    nvgText(vg, bx + btnW / 2, btnY + btnH / 2, def.label, nil)
                end

                -- hover 高亮
                if isHovered(bx, btnY, btnW, btnH) then
                    drawHoverHighlight(vg, bx, btnY, btnW, btnH, 3)
                end
            end

            -- 第二行：取消按钮（与N按钮对齐）
            local cancelY = btnY + btnH + btnGap
            local cancelW = btnW
            local cancelX = bagGridX
            GS.invActionBtnRects.btn1 = { x = cancelX, y = cancelY, w = cancelW, h = btnH }

            nvgBeginPath(vg)
            nvgRoundedRect(vg, cancelX, cancelY, cancelW, btnH, 3)
            local cGrad = nvgLinearGradient(vg, cancelX, cancelY, cancelX, cancelY + btnH,
                nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
            nvgFillPaint(vg, cGrad)
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cancelX + 0.5, cancelY + 0.5, cancelW - 1, btnH - 1, 3)
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, slotSize * 0.45)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))
            nvgText(vg, cancelX + cancelW / 2, cancelY + btnH / 2, "取消", nil)
            if isHovered(cancelX, cancelY, cancelW, btnH) then
                drawHoverHighlight(vg, cancelX, cancelY, cancelW, btnH, 3)
            end

            -- （已选数量显示已移除，空间不足会被遮挡）
        else
            -- 非多选模式：拆分(col1) | 整理(col2) | 多选(col3)
            local btnW = slotSize
            local splitX = bagGridX
            local btn1X = splitX + btnW + btnGap
            local btn2X = btn1X + btnW + btnGap
            local btn3X = btn2X + btnW + btnGap

            GS.splitBtnRect = { x = splitX, y = btnY, w = btnW, h = btnH }
            GS.invActionBtnRects.btn1 = { x = btn1X, y = btnY, w = btnW, h = btnH }
            GS.invActionBtnRects.btn2 = { x = btn2X, y = btnY, w = btnW, h = btnH }
            GS.invActionBtnRects.btn3 = { x = btn3X, y = btnY, w = btnW, h = btnH }

            -- 拆分按钮 - 检测拖拽悬浮
            local dragOverSplit = false
            if GS.itemDragActive then
                local dmx = GS.dragOffsetX
                local dmy = GS.dragOffsetY
                if dmx >= splitX and dmx <= splitX + btnW
                    and dmy >= btnY and dmy <= btnY + btnH then
                    dragOverSplit = true
                end
            end

            -- 拆分按钮背景（橙色调）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, splitX, btnY, btnW, btnH, 3)
            if dragOverSplit then
                local sGrad2 = nvgLinearGradient(vg, splitX, btnY, splitX, btnY + btnH,
                    nvgRGBA(200, 140, 40, 240), nvgRGBA(160, 100, 20, 240))
                nvgFillPaint(vg, sGrad2)
            else
                local sGrad2 = nvgLinearGradient(vg, splitX, btnY, splitX, btnY + btnH,
                    nvgRGBA(150, 100, 30, 220), nvgRGBA(110, 70, 15, 220))
                nvgFillPaint(vg, sGrad2)
            end
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, splitX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 3)
            nvgStrokeColor(vg, dragOverSplit and nvgRGBA(255, 200, 80, 220) or nvgRGBA(0, 0, 0, 200))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            -- 拆分按钮文字（双行）
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 230, 180, 240))
            local splitFs = math.max(10, slotSize * 0.35)
            nvgFontSize(vg, splitFs)
            nvgText(vg, splitX + btnW / 2, btnY + btnH / 2 - splitFs * 0.55, "拖入", nil)
            nvgText(vg, splitX + btnW / 2, btnY + btnH / 2 + splitFs * 0.55, "拆分", nil)
            if not dragOverSplit and not GS.itemDragActive and isHovered(splitX, btnY, btnW, btnH) then
                drawHoverHighlight(vg, splitX, btnY, btnW, btnH, 3)
            end

            -- 整理 + 多选 + 拾取过滤按钮
            local btnDefs3 = {
                { label = "整理",   bx = btn1X, active = false },
                { label = "多选",   bx = btn2X, active = false },
                { label = "拾取\n过滤", bx = btn3X, active = GS.lootFilterNoFine or GS.lootFilterNoRare or GS.lootFilterNoFineGrade or GS.lootFilterVisible },
            }
            for _, def in ipairs(btnDefs3) do
                local bx = def.bx
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, btnY, btnW, btnH, 3)
                if def.active then
                    -- 激活状态：青绿色高亮
                    local grad = nvgLinearGradient(vg, bx, btnY, bx, btnY + btnH,
                        nvgRGBA(30, 140, 100, 230), nvgRGBA(15, 100, 70, 230))
                    nvgFillPaint(vg, grad)
                else
                    local grad = nvgLinearGradient(vg, bx, btnY, bx, btnY + btnH,
                        nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
                    nvgFillPaint(vg, grad)
                end
                nvgFill(vg)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 3)
                nvgStrokeColor(vg, def.active and nvgRGBA(80, 220, 160, 220) or nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))

                -- 支持双行文字（\n 分割）
                local nl = string.find(def.label, "\n")
                if nl then
                    local line1 = string.sub(def.label, 1, nl - 1)
                    local line2 = string.sub(def.label, nl + 1)
                    local fs = math.max(8, slotSize * 0.36)
                    nvgFontSize(vg, fs)
                    nvgText(vg, bx + btnW / 2, btnY + btnH / 2 - fs * 0.6, line1, nil)
                    nvgText(vg, bx + btnW / 2, btnY + btnH / 2 + fs * 0.6, line2, nil)
                else
                    nvgFontSize(vg, slotSize * 0.45)
                    nvgText(vg, bx + btnW / 2, btnY + btnH / 2, def.label, nil)
                end

                if isHovered(bx, btnY, btnW, btnH) then
                    drawHoverHighlight(vg, bx, btnY, btnW, btnH, 3)
                end
            end

            -- 拾取过滤面板（点击"拾取过滤"按钮后展开，多行复选框）
            if GS.lootFilterVisible then
                local filterRows = {
                    { label = "不拾取优秀装备", checked = GS.lootFilterNoFine, color = GS.RARITY.uncommon.color, rectKey = "lootFilterCheckRect" },
                    { label = "不拾取稀有装备", checked = GS.lootFilterNoRare, color = GS.RARITY.rare.color, rectKey = "lootFilterCheckRectRare" },
                    { label = "不拾取精良装备", checked = GS.lootFilterNoFineGrade, color = GS.RARITY.fine.color, rectKey = "lootFilterCheckRectFine" },
                }
                local rowCount = #filterRows
                local rowH   = math.max(28, btnH * 0.85)
                local fs2    = math.max(8, rowH * 0.42)
                local cbSize = math.max(12, rowH * 0.52)
                local padL   = rowH * 0.3
                local padR   = rowH * 0.3
                local padV   = rowH * 0.2
                local innerGap = rowH * 0.2
                local panH   = padV + rowCount * rowH + (rowCount - 1) * padV * 0.3 + padV

                -- 用字号估算最长行文字宽度（"不拾取优秀装备" = 7字）
                local maxCharCount = 7
                local textW  = maxCharCount * fs2 * 0.95
                local panW   = padL + cbSize + innerGap + textW + padR
                local panX   = btn3X + btnW - panW   -- 右对齐于按钮右边
                local panY   = btnY - panH - btnGap
                -- 防止超出左边界
                if panX < bagGridX then panX = bagGridX end

                GS.lootFilterPanelRect = { x = panX, y = panY, w = panW, h = panH }

                -- 面板背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, panX, panY, panW, panH, 5)
                nvgFillColor(vg, nvgRGBA(30, 25, 18, 235))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, panX + 0.5, panY + 0.5, panW - 1, panH - 1, 5)
                nvgStrokeColor(vg, nvgRGBA(200, 165, 60, 220))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)

                -- 逐行绘制复选框
                local rowGap = padV * 0.3
                for ri, row in ipairs(filterRows) do
                    local ry = panY + padV + (ri - 1) * (rowH + rowGap)
                    local cbX = panX + padL
                    local cbY = ry + rowH / 2 - cbSize / 2

                    -- 记录点击区域
                    GS[row.rectKey] = { x = cbX, y = cbY, w = cbSize, h = cbSize }

                    -- 勾选框背景
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, cbX, cbY, cbSize, cbSize, 2)
                    nvgFillColor(vg, row.checked and nvgRGBA(30, 160, 100, 240) or nvgRGBA(50, 40, 28, 220))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, cbX + 0.5, cbY + 0.5, cbSize - 1, cbSize - 1, 2)
                    nvgStrokeColor(vg, nvgRGBA(150, 130, 90, 200))
                    nvgStrokeWidth(vg, 0.8)
                    nvgStroke(vg)

                    -- 对勾
                    if row.checked then
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, cbX + cbSize * 0.18, cbY + cbSize * 0.52)
                        nvgLineTo(vg, cbX + cbSize * 0.42, cbY + cbSize * 0.76)
                        nvgLineTo(vg, cbX + cbSize * 0.82, cbY + cbSize * 0.24)
                        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 240))
                        nvgStrokeWidth(vg, 1.5)
                        nvgStroke(vg)
                    end

                    -- 选项文字（用稀有度颜色）
                    local textX = cbX + cbSize + innerGap
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, fs2)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    local rc = row.color
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
                    nvgText(vg, textX, ry + rowH / 2, row.label, nil)
                end
            else
                GS.lootFilterPanelRect = nil
                GS.lootFilterCheckRect = nil
                GS.lootFilterCheckRectRare = nil
                GS.lootFilterCheckRectFine = nil
            end
        end

        -- ========== 销毁按钮（右下角对齐） ==========
        local destroyBtnX = bagGridX + totalGridW - slotSize
        local destroyBtnY = btnY
        GS.destroyBtnRect = { x = destroyBtnX, y = destroyBtnY, w = slotSize, h = slotSize }

        -- 拖拽悬浮在销毁按钮上时高亮
        local dragOverDestroy = false
        if GS.itemDragActive then
            local dmx = GS.dragOffsetX
            local dmy = GS.dragOffsetY
            if dmx >= destroyBtnX and dmx <= destroyBtnX + slotSize
                and dmy >= destroyBtnY and dmy <= destroyBtnY + slotSize then
                dragOverDestroy = true
            end
        end

        -- 按钮背景 - 红色(销毁)/绿色(出售)/蓝色(存入)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, destroyBtnX, destroyBtnY, slotSize, slotSize, 3)
        if GS.warehouseMode or GS.sharedStorageMode then
            -- 仓库/共享仓库模式：蓝色/青色
            if dragOverDestroy then
                local dGrad = nvgLinearGradient(vg, destroyBtnX, destroyBtnY,
                    destroyBtnX, destroyBtnY + slotSize,
                    nvgRGBA(50, 140, 200, 240), nvgRGBA(30, 100, 160, 240))
                nvgFillPaint(vg, dGrad)
            else
                local dGrad = nvgLinearGradient(vg, destroyBtnX, destroyBtnY,
                    destroyBtnX, destroyBtnY + slotSize,
                    nvgRGBA(35, 110, 170, 220), nvgRGBA(20, 80, 130, 220))
                nvgFillPaint(vg, dGrad)
            end
        elseif GS.shopMode then
            if dragOverDestroy then
                local dGrad = nvgLinearGradient(vg, destroyBtnX, destroyBtnY,
                    destroyBtnX, destroyBtnY + slotSize,
                    nvgRGBA(60, 180, 60, 240), nvgRGBA(30, 140, 30, 240))
                nvgFillPaint(vg, dGrad)
            else
                local dGrad = nvgLinearGradient(vg, destroyBtnX, destroyBtnY,
                    destroyBtnX, destroyBtnY + slotSize,
                    nvgRGBA(40, 130, 40, 220), nvgRGBA(25, 95, 25, 220))
                nvgFillPaint(vg, dGrad)
            end
        else
            if dragOverDestroy then
                local dGrad = nvgLinearGradient(vg, destroyBtnX, destroyBtnY,
                    destroyBtnX, destroyBtnY + slotSize,
                    nvgRGBA(220, 60, 40, 240), nvgRGBA(180, 30, 15, 240))
                nvgFillPaint(vg, dGrad)
            else
                local dGrad = nvgLinearGradient(vg, destroyBtnX, destroyBtnY,
                    destroyBtnX, destroyBtnY + slotSize,
                    nvgRGBA(160, 40, 30, 220), nvgRGBA(120, 25, 15, 220))
                nvgFillPaint(vg, dGrad)
            end
        end
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, destroyBtnX + 0.5, destroyBtnY + 0.5, slotSize - 1, slotSize - 1, 3)
        if GS.warehouseMode or GS.sharedStorageMode then
            nvgStrokeColor(vg, dragOverDestroy and nvgRGBA(120, 200, 255, 220) or nvgRGBA(60, 150, 200, 150))
        elseif GS.shopMode then
            nvgStrokeColor(vg, dragOverDestroy and nvgRGBA(180, 255, 120, 220) or nvgRGBA(100, 200, 60, 150))
        else
            nvgStrokeColor(vg, dragOverDestroy and nvgRGBA(255, 180, 120, 220) or nvgRGBA(200, 100, 60, 150))
        end
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 按钮文字标签
        local destroyLabel = (GS.warehouseMode or GS.sharedStorageMode) and "存入" or (GS.shopMode and "出售" or "销毁")

        -- 文字
        nvgFontFace(vg, "sans")
        nvgFillColor(vg, nvgRGBA(255, 220, 200, 240))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if GS.invMultiSelect then
            nvgFontSize(vg, slotSize * 0.45)
            nvgText(vg, destroyBtnX + slotSize / 2, destroyBtnY + slotSize / 2, destroyLabel, nil)
        else
            local fontSize = slotSize * 0.35
            nvgFontSize(vg, fontSize)
            local dtx = destroyBtnX + slotSize / 2
            local dty = destroyBtnY + slotSize / 2
            nvgText(vg, dtx, dty - fontSize * 0.55, "拖入", nil)
            nvgText(vg, dtx, dty + fontSize * 0.55, destroyLabel, nil)
        end

        -- hover 高亮（非拖拽状态）
        if not dragOverDestroy and not GS.itemDragActive and isHovered(destroyBtnX, destroyBtnY, slotSize, slotSize) then
            drawHoverHighlight(vg, destroyBtnX, destroyBtnY, slotSize, slotSize, 3)
        end
    end

    -- 记录 slotSize 供拖拽渲染使用
    GS.invSlotSize = slotSize

end

-- ====================================================================
-- 面板内容：技能配置（Tab 3）
-- ====================================================================
function M.drawSkillPanel(cx, cy, cw, ch)
    local vg = M.vg
    local treeCols = 4
    local treeRows = 6
    local sGap = 3

    -- 格子大小：与装备栏一致（基于面板尺寸计算）
    local eLabelH = 10
    local eSlotRows = 7
    local sMaxV = math.floor((ch - (eSlotRows - 1) * sGap) / eSlotRows - eLabelH)
    local minMargin = 6
    local invCols = GS.INV_SHOW_COLS or 5
    local sMaxH = math.floor((cw - (invCols - 1) * sGap - 6 * minMargin) / 7)
    local slotSize = math.max(18, math.min(sMaxV, sMaxH))
    local labelH = 10  -- 图标下方文字高度
    local colGap = slotSize * 0.45  -- 列间距加大，防止文字重叠
    local stepX = slotSize + colGap
    local stepY = slotSize + labelH + sGap -- 行间距（垂直，含文字）

    -- === 布局：左侧生活技能栏 + 右侧技能树 ===
    local margin = 8
    local gridW = treeCols * slotSize + (treeCols - 1) * colGap
    local gridH = treeRows * (slotSize + labelH) + (treeRows - 1) * sGap
    local gridX = math.floor(cx + cw - gridW - 2 * colGap - slotSize)
    local divX = math.floor(gridX - colGap - slotSize / 2)
    local gridY = cy + math.floor((ch - gridH) / 2) + 8

    local layout = GS.SKILL_TREE_LAYOUT

    -- 计算已投入总点数（用于层级解锁判断和标题显示）
    local totalInvested = 0
    for _, lv in pairs(GS.skillLevels) do
        totalInvested = totalInvested + lv
    end

    -- ========== 左侧：生活技能栏 ==========
    local lifeSkillCount = #GS.LIFE_SKILL_DEFS
    local lifeStepY = slotSize + labelH + sGap
    local lifeTotalH = lifeSkillCount * (slotSize + labelH) + (lifeSkillCount - 1) * sGap
    local lifeX = cx + margin
    local lifeStartY = cy + math.floor((ch - lifeTotalH) / 2)

    -- 左侧标题
    local leftTitleX = (cx + divX) / 2
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
    nvgText(vg, leftTitleX, gridY - 4, "生活技能", nil)

    GS.lifeSkillSlotAreas = {}
    for i, lsDef in ipairs(GS.LIFE_SKILL_DEFS) do
        local ly = lifeStartY + (i - 1) * lifeStepY
        GS.lifeSkillSlotAreas[i] = { x = lifeX, y = ly, w = slotSize, h = slotSize }

        local lv = GS.lifeSkillLevels[lsDef.id] or 1
        local c = lsDef.col

        -- 格子背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, lifeX, ly, slotSize, slotSize, 3)
        nvgFillColor(vg, nvgRGBA(35, 30, 25, 160))
        nvgFill(vg)

        -- 图标（图片）
        local lsImg = GS.lifeSkillImages[lsDef.id]
        if lsImg and lsImg ~= -1 then
            local pad = 1
            local imgPat = nvgImagePattern(vg, lifeX + pad, ly + pad,
                slotSize - pad * 2, slotSize - pad * 2, 0, lsImg, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, lifeX + pad, ly + pad, slotSize - pad * 2, slotSize - pad * 2, 2)
            nvgFillPaint(vg, imgPat)
            nvgFill(vg)
        end

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, lifeX, ly, slotSize, slotSize, 3)
        nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 右侧：等级和段位信息（居中于图标右侧与分割线之间）
        local tier = GS.lifeSkillTiers[lsDef.id] or 1
        local tierDef = GS.LIFE_SKILL_TIERS[tier] or GS.LIFE_SKILL_TIERS[1]
        local tc = tierDef.col
        local infoCenterX = math.floor((lifeX + slotSize + divX) / 2)
        local infoFsName = math.max(9, math.floor(slotSize * 0.32))
        local infoFsLv = math.max(8, math.floor(slotSize * 0.28))
        local expBarH0 = math.max(8, math.floor(infoFsLv * 1.0))
        local totalTextH = infoFsName + infoFsLv + expBarH0 + 6
        local textStartY = ly + math.floor((slotSize - totalTextH) / 2)

        -- 技能名称
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(vg, infoFsName)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
        nvgText(vg, infoCenterX, textStartY, lsDef.name, nil)

        -- 段位名（带颜色）
        nvgFontSize(vg, infoFsLv)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 255))
        nvgText(vg, infoCenterX, textStartY + infoFsName + 2, tierDef.name, nil)

        -- 经验条 / 满级显示
        local exp = GS.lifeSkillExp[lsDef.id] or 0
        local maxExp = GS.LIFE_SKILL_MAX_LEVEL
        local isMaxLevel = tier >= GS.LIFE_SKILL_MAX_TIER and exp >= maxExp
        local expBarY = textStartY + infoFsName + infoFsLv + 5
        local expBarW = math.max(24, math.floor((divX - lifeX - slotSize - 8) * 0.85))
        local expBarH = math.max(8, math.floor(infoFsLv * 1.0))
        local expBarX = infoCenterX - math.floor(expBarW / 2)

        if isMaxLevel then
            -- 满级：显示 "MAX"
            local maxFs = math.max(9, math.floor(expBarH * 1.2))
            nvgFontSize(vg, maxFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 180, 0, 255))
            nvgText(vg, infoCenterX, expBarY, "MAX", nil)
        else
            local expPct = math.min(exp / math.max(1, maxExp), 1.0)

            -- 经验条背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, expBarX, expBarY, expBarW, expBarH, 2)
            nvgFillColor(vg, nvgRGBA(20, 18, 15, 160))
            nvgFill(vg)

            -- 经验条填充
            if expPct > 0 then
                local fillW = math.max(2, math.floor(expBarW * expPct))
                nvgBeginPath(vg)
                nvgRoundedRect(vg, expBarX, expBarY, fillW, expBarH, 2)
                nvgFillColor(vg, nvgRGBA(180, 140, 30, 230))
                nvgFill(vg)
            end

            -- 经验条边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, expBarX, expBarY, expBarW, expBarH, 2)
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)

            -- 经验值文本 "0/100"
            local expFontSize = math.max(7, math.floor(expBarH * 0.9))
            nvgFontSize(vg, expFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 215, 200, 220))
            nvgText(vg, infoCenterX, expBarY + math.floor(expBarH / 2), exp .. "/" .. maxExp, nil)
        end

        -- 悬停高亮
        if isHovered(lifeX, ly, slotSize, slotSize) then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, lifeX, ly, slotSize, slotSize, 3)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 30))
            nvgFill(vg)
        end
    end

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, divX, cy + 4)
    nvgLineTo(vg, divX, cy + ch - 4)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ========== 标题（居中于技能树区域） ==========
    local titleY = gridY - 4
    local rightTitleX = gridX + gridW / 2
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFontSize(vg, 10)
    local titleLeft = "已分配技能点数:" .. totalInvested .. " "
    local titleRight = "可用:" .. GS.skillPoints
    -- 用 nvgTextBounds 返回值获取宽度
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    local leftW = nvgTextBounds(vg, 0, 0, titleLeft, nil)
    local rightW = nvgTextBounds(vg, 0, 0, titleRight, nil)
    local totalW = leftW + rightW
    local startX = rightTitleX - totalW / 2
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
    nvgText(vg, startX, titleY, titleLeft, nil)
    if GS.skillPoints > 0 then
        nvgFillColor(vg, nvgRGBA(20, 120, 20, 255))
    else
        nvgFillColor(vg, nvgRGBA(120, 100, 75, 180))
    end
    nvgText(vg, startX + leftW, titleY, titleRight, nil)

    -- 各层解锁所需的总投入点数（第1层=0, 第2层=10, ...）
    local layerReq = { 0, 5, 15, 25, 35, 45 }

    -- 清空点击区域
    GS.skillSlotAreas = {}

    -- 绘制技能格子
    for row = 1, treeRows do
        for col = 1, treeCols do
            local skillId = layout[row] and layout[row][col]
            if skillId then
                local def = GS.SKILL_DEFS[skillId]
                if not def then goto continue end

                local sx = gridX + (col - 1) * stepX
                local sy = gridY + (row - 1) * stepY
                local lv = GS.skillLevels[skillId] or 0
                local maxLv = GS.SKILL_MAX_LEVEL
                local c = def.col
                local req = layerReq[row] or 0
                local locked = totalInvested < req
                -- 前置技能未满足也视为锁定
                local rawReqSkill = def.reqSkill or (def.mstCounter and "counter")
                if not locked and rawReqSkill then
                    local reqList = type(rawReqSkill) == "table" and rawReqSkill or { rawReqSkill }
                    local needLv = def.reqSkillLv or GS.SKILL_MAX_LEVEL
                    for _, reqId in ipairs(reqList) do
                        if (GS.skillLevels[reqId] or 0) < needLv then
                            locked = true
                            break
                        end
                    end
                end

                -- 记录点击区域
                GS.skillSlotAreas[skillId] = { x = sx, y = sy, w = slotSize, h = slotSize }

                -- 格子背景
                local sImg = M.skillImages and M.skillImages[skillId]
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
                if sImg and sImg ~= -1 then
                    local imgPat = nvgImagePattern(vg, sx, sy, slotSize, slotSize, 0, sImg, 1.0)
                    nvgFillPaint(vg, imgPat)
                elseif lv > 0 then
                    local alpha = 80 + math.floor(120 * lv / maxLv)
                    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
                else
                    nvgFillColor(vg, nvgRGBA(40, 35, 30, 180))
                end
                nvgFill(vg)

                -- 边框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 技能名称（垂直居中在上下两行格子之间）
                local name = def.name
                local fontSize = slotSize * 0.24
                nvgFontSize(vg, fontSize)
                nvgFontFace(vg, "sans")
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if locked then
                    nvgFillColor(vg, nvgRGBA(80, 75, 65, 140))
                else
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
                end
                nvgText(vg, sx + slotSize / 2, sy + slotSize + (labelH + sGap) / 2, name, nil)

                -- 等级显示（右下角，所有技能统一显示）
                local lvText = lv .. "/" .. maxLv
                local lvFontSize = slotSize * 0.22
                nvgFontSize(vg, lvFontSize)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local lvBgW = slotSize * 0.55
                local lvBgH = lvFontSize + 4
                local lvBgX = sx + slotSize - lvBgW - 1
                local lvBgY = sy + slotSize - lvBgH - 1
                nvgBeginPath(vg)
                nvgRoundedRect(vg, lvBgX, lvBgY, lvBgW, lvBgH, 2)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
                nvgFill(vg)
                local canLevelUp = not locked and GS.skillPoints > 0 and lv < maxLv
                if lv >= maxLv then
                    nvgFillColor(vg, nvgRGBA(255, 215, 0, 255))      -- 满级：金色
                elseif canLevelUp then
                    nvgFillColor(vg, nvgRGBA(80, 220, 80, 255))      -- 可加点：绿色
                elseif lv > 0 then
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))    -- 已学但不可加：白色
                else
                    nvgFillColor(vg, nvgRGBA(160, 155, 140, 180))    -- 未学：灰色
                end
                nvgText(vg, lvBgX + lvBgW / 2, lvBgY + lvBgH / 2, lvText, nil)

                -- 悬停高亮（非锁定）
                if not locked and isHovered(sx, sy, slotSize, slotSize) then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 30))
                    nvgFill(vg)
                end

                ::continue::
            end
        end
    end

    -- 每行右侧显示层级解锁需求（圆形背景，居中于虚拟第5列）
    local reqCenterX = gridX + gridW + colGap + slotSize / 2  -- 虚拟第5列中心
    for row = 1, treeRows do
        local req = layerReq[row] or 0
        if req > 0 then
            local locked = totalInvested < req
            local rowCenterY = gridY + (row - 1) * stepY + slotSize / 2
            local circR = slotSize * 0.38

            -- 圆形背景
            nvgBeginPath(vg)
            nvgCircle(vg, reqCenterX, rowCenterY, circR)
            if locked then
                nvgFillColor(vg, nvgRGBA(120, 40, 30, 140))
            else
                nvgFillColor(vg, nvgRGBA(40, 100, 40, 140))
            end
            nvgFill(vg)

            -- 圆形边框
            nvgBeginPath(vg)
            nvgCircle(vg, reqCenterX, rowCenterY, circR)
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 8)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if locked then
                nvgFillColor(vg, nvgRGBA(220, 120, 100, 255))
            else
                nvgFillColor(vg, nvgRGBA(140, 220, 120, 255))
            end
            nvgText(vg, reqCenterX, rowCenterY, req .. "点", nil)
        end
    end

    -- ========== 技能悬停检测（非锁定时跟随鼠标） ==========
    if not GS.skillTooltipPinned then
        local foundId, foundSrc, foundSlot = nil, nil, nil
        -- 检测技能树
        if GS.skillSlotAreas then
            for skillId, r in pairs(GS.skillSlotAreas) do
                if isHovered(r.x, r.y, r.w, r.h) then
                    foundId = skillId
                    foundSrc = "tree"
                    break
                end
            end
        end
        -- 检测装备槽
        if not foundId and GS.activeSkillSlotAreas then
            for i, r in pairs(GS.activeSkillSlotAreas) do
                if isHovered(r.x, r.y, r.w, r.h) and GS.activeSkills[i] then
                    foundId = GS.activeSkills[i]
                    foundSrc = "slot"
                    foundSlot = i
                    break
                end
            end
        end
        GS.skillTooltipId = foundId
        GS.skillTooltipSource = foundSrc
        GS.skillTooltipSlotIdx = foundSlot
    end
end

-- ====================================================================
-- 绘制：技能悬停提示面板
-- ====================================================================
function M.drawSkillTooltip()
    -- 非技能面板时清除悬停状态
    if GS.activeBottomTab ~= 3 and not GS.showAutoBattleSettings then
        if GS.skillTooltipId and not GS.skillTooltipPinned then
            GS.closeSkillTooltip()
        end
    end
    local skillId = GS.skillTooltipId
    if not skillId then
        GS.skillTooltipRect = nil
        return
    end

    local def = GS.SKILL_DEFS[skillId]
    if not def then
        GS.skillTooltipRect = nil
        return
    end

    -- 找到技能图标的屏幕位置
    local slotArea
    if GS.skillTooltipSource == "slot" and GS.skillTooltipSlotIdx then
        slotArea = GS.activeSkillSlotAreas and GS.activeSkillSlotAreas[GS.skillTooltipSlotIdx]
    else
        slotArea = GS.skillSlotAreas and GS.skillSlotAreas[skillId]
    end
    if not slotArea then
        GS.skillTooltipRect = nil
        return
    end

    local vg = M.vg
    local lv = GS.skillLevels[skillId] or 0

    -- ========== 构建显示行 ==========
    local lines = {}
    local lineColors = {}

    -- 第一行：名称 + 等级
    local title = def.name
    if lv > 0 then
        title = title .. " Lv." .. lv
    else
        title = title .. " (未学习)"
    end
    table.insert(lines, title)
    table.insert(lineColors, {255, 240, 200})

    -- 第二行：类型
    if def.type == "active" then
        local typeStr = "主动技能"
        local stages = def.castStages or 0
        if stages > 0 then
            local cnNum = {"一","二","三","四","五","六","七","八","九","十"}
            typeStr = typeStr .. " " .. (cnNum[stages] or tostring(stages)) .. "段咏唱法术"
        end
        table.insert(lines, typeStr)
        table.insert(lineColors, {255, 200, 80})
        -- 主动技能施展条件（装备要求）
        local activeCondTag = def.reqWeaponTag
        local activeLeftCat = def.reqLeftCategory
        if activeCondTag or activeLeftCat then
            local condName = activeCondTag or activeLeftCat
            -- 检测是否满足条件
            local weaponR = GS.equipment and GS.equipment["weapon_r"]
            local weaponL = GS.equipment and GS.equipment["weapon_l"]
            local met = false
            if activeCondTag then
                local curTag = weaponR and weaponR.weaponTag
                if not curTag and weaponL and weaponL.weaponTag then
                    curTag = weaponL.weaponTag
                end
                met = (curTag == activeCondTag)
                -- 弓需要箭袋
                if activeCondTag == "弓" and met then
                    if not weaponL or weaponL.category ~= "箭袋" then met = false end
                end
            elseif activeLeftCat then
                met = weaponL and weaponL.category == activeLeftCat
            end
            if activeCondTag == "弓" then
                -- 弓类技能：分两行显示弓和箭袋
                local curTag = weaponR and weaponR.weaponTag
                if not curTag and weaponL and weaponL.weaponTag then
                    curTag = weaponL.weaponTag
                end
                local metBow = (curTag == "弓")
                local metQuiver = weaponL and weaponL.category == "箭袋"
                if metBow then
                    table.insert(lines, "施展条件: 需装备弓 √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "施展条件: 需装备弓 ×")
                    table.insert(lineColors, {255, 100, 100})
                end
                if metQuiver then
                    table.insert(lines, "施展条件: 需装备箭袋 √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "施展条件: 需装备箭袋 ×")
                    table.insert(lineColors, {255, 100, 100})
                end
            else
                if met then
                    table.insert(lines, "施展条件: 需装备" .. condName .. " √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "施展条件: 需装备" .. condName .. " ×")
                    table.insert(lineColors, {255, 100, 100})
                end
            end
        end
    else
        table.insert(lines, "被动技能")
        table.insert(lineColors, {120, 200, 255})
        -- 被动技能生效条件
        local passiveCondTag = def.condTag
        if passiveCondTag then
            local condName = passiveCondTag
            if passiveCondTag == "盾" then condName = "盾牌" end
            -- 检测是否满足条件
            local weaponR = GS.equipment and GS.equipment["weapon_r"]
            local weaponL = GS.equipment and GS.equipment["weapon_l"]
            local curTag = weaponR and weaponR.weaponTag
            if not curTag and weaponL and weaponL.weaponTag then
                curTag = weaponL.weaponTag
            end
            local hasShield = weaponL and weaponL.category == "盾牌"
            local met = (curTag == passiveCondTag) or (passiveCondTag == "盾" and hasShield)
            if def.condRequireEmptyLeft then
                -- 双条件：分两行显示
                local metWeapon = (curTag == passiveCondTag)
                if metWeapon then
                    table.insert(lines, "生效条件: 需装备" .. condName .. " √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "生效条件: 需装备" .. condName .. " ×")
                    table.insert(lineColors, {255, 100, 100})
                end
                local metEmpty = (not weaponL)
                if metEmpty then
                    table.insert(lines, "生效条件: 左手武器栏为空 √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "生效条件: 左手武器栏为空 ×")
                    table.insert(lineColors, {255, 100, 100})
                end
            else
                if met then
                    table.insert(lines, "生效条件: 需装备" .. condName .. " √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "生效条件: 需装备" .. condName .. " ×")
                    table.insert(lineColors, {255, 100, 100})
                end
            end
        end
        -- 双持匕首生效条件
        if def.condDualDagger then
            local met = GS.isDualDagger()
            if met then
                table.insert(lines, "生效条件: 需双持匕首 √")
                table.insert(lineColors, {80, 255, 120})
            else
                table.insert(lines, "生效条件: 需双持匕首 ×")
                table.insert(lineColors, {255, 100, 100})
            end
        end
        -- 被动技能装备要求（reqWeaponTag，与 condTag 不同）
        local passiveReqWeapon = def.reqWeaponTag
        if passiveReqWeapon then
            local weaponR = GS.equipment and GS.equipment["weapon_r"]
            local weaponL = GS.equipment and GS.equipment["weapon_l"]
            if passiveReqWeapon == "弓" then
                local curTag = weaponR and weaponR.weaponTag
                if not curTag and weaponL and weaponL.weaponTag then
                    curTag = weaponL.weaponTag
                end
                local metBow = (curTag == "弓")
                local metQuiver = weaponL and weaponL.category == "箭袋"
                if metBow then
                    table.insert(lines, "生效条件: 需装备弓 √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "生效条件: 需装备弓 ×")
                    table.insert(lineColors, {255, 100, 100})
                end
                if metQuiver then
                    table.insert(lines, "生效条件: 需装备箭袋 √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "生效条件: 需装备箭袋 ×")
                    table.insert(lineColors, {255, 100, 100})
                end
            else
                local curTag = weaponR and weaponR.weaponTag
                if not curTag and weaponL and weaponL.weaponTag then
                    curTag = weaponL.weaponTag
                end
                local met = (curTag == passiveReqWeapon)
                if met then
                    table.insert(lines, "生效条件: 需装备" .. passiveReqWeapon .. " √")
                    table.insert(lineColors, {80, 255, 120})
                else
                    table.insert(lines, "生效条件: 需装备" .. passiveReqWeapon .. " ×")
                    table.insert(lineColors, {255, 100, 100})
                end
            end
        end
    end

    -- 前置条件显示（支持单个或多个）
    local rawReq = def.reqSkill or (def.mstCounter and "counter")
    if rawReq then
        local reqList = type(rawReq) == "table" and rawReq or { rawReq }
        local needLv = def.reqSkillLv or GS.SKILL_MAX_LEVEL
        for _, reqId in ipairs(reqList) do
            local reqDef = GS.SKILL_DEFS[reqId]
            local reqName = reqDef and reqDef.name or reqId
            local reqLv = GS.skillLevels[reqId] or 0
            if reqLv >= needLv then
                table.insert(lines, "前置: " .. reqName .. " Lv." .. needLv .. " [已满足]")
                table.insert(lineColors, {80, 255, 120})
            else
                table.insert(lines, "前置: " .. reqName .. " Lv." .. needLv .. " [当前Lv." .. reqLv .. "]")
                table.insert(lineColors, {255, 100, 100})
            end
        end
    end

    -- 技能详情
    if def.type == "active" and def.cd then
        -- 施展距离
        -- 不需要选择目标的技能(selfCast无needTarget，或aoe以自身为中心)显示"自身"
        local isSelfRange = def.aoe or (def.selfCast and not def.needTarget)
        if isSelfRange then
            table.insert(lines, "施展距离: 自身")
            table.insert(lineColors, {200, 200, 200})
        else
            local castRange = def.skillRange
            if castRange then
                -- 考虑 rangeBreaks 随等级增加范围
                if def.rangeBreaks and lv > 0 then
                    for _, brk in ipairs(def.rangeBreaks) do
                        if lv >= brk then castRange = castRange + 1 end
                    end
                end
                -- 元素熟练满级施展距离加成
                castRange = castRange + GS.getElementRangeBonus(skillId)
            else
                -- 无 skillRange 时，根据武器类型决定基础距离
                local isRangedSkill = (def.reqWeaponTag == "弓" or def.reqWeaponTag == "法杖" or def.useMagic)
                local baseRange = isRangedSkill and 3 or 1
                local playerRange = GS.player and GS.player.atkRange or baseRange
                castRange = math.max(playerRange, baseRange)
            end
            table.insert(lines, "施展距离: " .. castRange .. "格")
            table.insert(lineColors, {200, 200, 200})
        end

        -- 主动技能：冷却、MP消耗、伤害倍率
        local cdVal = def.cd or 0
        if def.cdBreaks and lv > 0 then
            for _, brk in ipairs(def.cdBreaks) do
                if lv >= brk then cdVal = cdVal - 1 end
            end
        end
        if cdVal > 0 then
            table.insert(lines, "冷却时间: " .. cdVal .. "回合")
        else
            table.insert(lines, "无冷却时间")
        end
        table.insert(lineColors, {200, 200, 200})

        if lv > 0 and def.mpCost then
            local curMp = GS.getSkillMpCost(skillId)
            table.insert(lines, "MP消耗: " .. curMp)
            table.insert(lineColors, {100, 160, 255})
        elseif def.mpCost then
            table.insert(lines, "MP消耗: " .. (def.mpCost or 0))
            table.insert(lineColors, {100, 160, 255})
        end









    end

    -- 描述
    if def.desc then
        local descText = def.desc
        if type(descText) == "function" then
            descText = descText(lv > 0 and lv or 1)
        end
        table.insert(lines, descText)
        table.insert(lineColors, {180, 180, 160})
    end

    -- ========== 判断是否显示加点按钮及其状态 ==========
    local showLevelUpBtn = false  -- 是否显示按钮
    local canLevelUp = false      -- 按钮是否可点击（绿色/灰色）
    local levelUpBlockReason = nil -- 不可点击原因
    if GS.skillTooltipSource == "tree" and lv < GS.SKILL_MAX_LEVEL then
        showLevelUpBtn = true
        -- 层级解锁检查
        local skillRow = 1
        for row = 1, #GS.SKILL_TREE_LAYOUT do
            local cols = GS.SKILL_TREE_LAYOUT[row]
            for c = 1, #cols do
                if cols[c] == skillId then skillRow = row end
            end
        end
        local layerReq = { 0, 5, 15, 25, 35, 45 }
        local req = layerReq[skillRow] or 0
        local totalInvested = 0
        for _, slv in pairs(GS.skillLevels) do
            totalInvested = totalInvested + slv
        end
        local locked = totalInvested < req
        -- 前置技能检查
        if not locked then
            local rawReq2 = def.reqSkill or (def.mstCounter and "counter")
            if rawReq2 then
                local reqList2 = type(rawReq2) == "table" and rawReq2 or { rawReq2 }
                local needLv2 = def.reqSkillLv or GS.SKILL_MAX_LEVEL
                for _, reqId2 in ipairs(reqList2) do
                    if (GS.skillLevels[reqId2] or 0) < needLv2 then
                        locked = true
                        break
                    end
                end
            end
        end
        if locked then
            canLevelUp = false
            levelUpBlockReason = "未解锁"
        elseif not GS.skillPoints or GS.skillPoints <= 0 then
            canLevelUp = false
            levelUpBlockReason = "无可用技能点"
        else
            canLevelUp = true
        end
    end

    -- ========== 计算面板尺寸 ==========
    local titleFontSize = 18
    local fontSize = 14
    local lineH = 22
    local padX = 12
    local padY = 10
    local btnH = showLevelUpBtn and 28 or 0
    local btnGap = showLevelUpBtn and 8 or 0
    local maxPanelW = math.floor(GS.SCREEN_W * 0.55)  -- 最大宽度限制
    local maxTextW = maxPanelW - padX * 2

    -- 对长行做自动换行，生成新的 lines/lineColors
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local wrappedLines = {}
    local wrappedColors = {}
    for idx, line in ipairs(lines) do
        local fs = idx == 1 and titleFontSize or fontSize
        nvgFontSize(vg, fs)
        local w = nvgTextBounds(vg, 0, 0, line or "", nil)
        if w > maxTextW then
            -- 按字符逐步拆行
            local chars = {}
            for _, c in utf8.codes(line) do
                table.insert(chars, utf8.char(c))
            end
            local cur = ""
            for _, ch in ipairs(chars) do
                local test = cur .. ch
                local tw = nvgTextBounds(vg, 0, 0, test, nil)
                if tw > maxTextW and #cur > 0 then
                    table.insert(wrappedLines, cur)
                    table.insert(wrappedColors, lineColors[idx])
                    cur = ch
                else
                    cur = test
                end
            end
            if #cur > 0 then
                table.insert(wrappedLines, cur)
                table.insert(wrappedColors, lineColors[idx])
            end
        else
            table.insert(wrappedLines, line)
            table.insert(wrappedColors, lineColors[idx])
        end
    end
    lines = wrappedLines
    lineColors = wrappedColors

    local panelH = padY * 2 + #lines * lineH + btnGap + btnH

    -- 测量最宽行
    local maxW = 0
    for idx, line in ipairs(lines) do
        nvgFontSize(vg, idx == 1 and titleFontSize or fontSize)
        local w = nvgTextBounds(vg, 0, 0, line or "", nil)
        if w > maxW then maxW = w end
    end
    local panelW = maxW + padX * 2

    -- ========== 定位面板（避免遮挡技能图标） ==========
    local px, py
    local gap = 4
    -- 辅助：判断矩形是否与技能图标重叠
    local function overlapsSlot(tx, ty, tw, th)
        return tx < slotArea.x + slotArea.w and tx + tw > slotArea.x
           and ty < slotArea.y + slotArea.h and ty + th > slotArea.y
    end

    if GS.skillTooltipSource == "slot" then
        -- 装备栏：图标左侧
        px = slotArea.x - panelW - gap
        py = slotArea.y + slotArea.h / 2 - panelH / 2
    else
        -- 技能树：优先右侧
        px = slotArea.x + slotArea.w + gap
        py = slotArea.y + slotArea.h / 2 - panelH / 2
    end
    -- 边界约束：放不下时翻转水平方向
    if px < 2 then px = slotArea.x + slotArea.w + gap end
    if px + panelW > GS.SCREEN_W - 2 then px = slotArea.x - panelW - gap end
    if px < 2 then px = 2 end
    if px + panelW > GS.SCREEN_W - 2 then px = GS.SCREEN_W - 2 - panelW end
    if py < GS.TOP_BAR_H + 2 then py = GS.TOP_BAR_H + 2 end
    if py + panelH > GS.SCREEN_H - 2 then py = GS.SCREEN_H - 2 - panelH end

    -- 如果水平定位后仍与图标重叠，改为垂直定位（上方或下方）
    if overlapsSlot(px, py, panelW, panelH) then
        -- 尝试放在图标下方
        local belowY = slotArea.y + slotArea.h + gap
        -- 尝试放在图标上方
        local aboveY = slotArea.y - panelH - gap
        -- 水平居中对齐图标
        local centerX = slotArea.x + slotArea.w / 2 - panelW / 2
        centerX = math.max(2, math.min(centerX, GS.SCREEN_W - 2 - panelW))

        if belowY + panelH <= GS.SCREEN_H - 2 then
            px, py = centerX, belowY
        elseif aboveY >= GS.TOP_BAR_H + 2 then
            px, py = centerX, aboveY
        else
            -- 最后兜底：放在图标下方并 clamp
            px = centerX
            py = math.max(GS.TOP_BAR_H + 2, math.min(belowY, GS.SCREEN_H - 2 - panelH))
        end
    end

    GS.skillTooltipRect = { x = px, y = py, w = panelW, h = panelH }

    -- ========== 绘制面板背景 ==========
    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + 2, py + 2, panelW, panelH, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgFill(vg)

    -- 羊皮纸底色
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 4)
    nvgFillColor(vg, nvgRGBA(45, 38, 30, 240))
    nvgFill(vg)

    -- 金色边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 4)
    nvgStrokeColor(vg, nvgRGBA(180, 150, 80, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- ========== 绘制文本行 ==========
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    for i, line in ipairs(lines) do
        local lc = lineColors[i]
        local ly = py + padY + (i - 1) * lineH
        nvgFontSize(vg, i == 1 and titleFontSize or fontSize)
        nvgFillColor(vg, nvgRGBA(lc[1], lc[2], lc[3], 255))
        nvgText(vg, px + padX, ly, line, nil)
    end

    -- ========== 绘制加点按钮 ==========
    GS.skillLevelUpBtnRect = nil
    if showLevelUpBtn then
        local btnW = panelW - padX * 2
        local btnX = px + padX
        local btnY = py + padY + #lines * lineH + btnGap
        local btnText
        if canLevelUp then
            btnText = lv == 0 and "学习技能" or ("升级 Lv." .. lv .. " → " .. (lv + 1))
        else
            btnText = levelUpBlockReason or "不可升级"
        end

        if canLevelUp then
            -- 可点击：绿色渐变
            local bgPaint = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
                nvgRGBA(50, 140, 50, 230), nvgRGBA(35, 100, 35, 230))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
            nvgFillPaint(vg, bgPaint)
            nvgFill(vg)
            -- 绿色边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
            nvgStrokeColor(vg, nvgRGBA(80, 200, 80, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 白色文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 240, 255))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, btnText, nil)
            -- 记录按钮区域供点击检测
            GS.skillLevelUpBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        else
            -- 禁用：灰色
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
            nvgFillColor(vg, nvgRGBA(80, 80, 80, 180))
            nvgFill(vg)
            -- 灰色边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
            nvgStrokeColor(vg, nvgRGBA(100, 100, 100, 150))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 暗淡文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, btnText, nil)
            -- 禁用状态不设置 btnRect，防止点击
        end
    end
end

-- ====================================================================
-- 面板内容：旅行日志（Tab 4）
-- 三大分区：主线任务、支线任务、委托任务 + 滚动条
-- ====================================================================
function M.drawJournalPanel(cx, cy, cw, ch)
    local vg = M.vg
    local BulletinBoard = require("BulletinBoard")
    local QuestManager = require("QuestManager")

    local pad = 6
    local lineH = 15
    local sectionGap = 8
    local headerFs = math.max(11, lineH * 0.85)
    local bodyFs = math.max(9, lineH * 0.72)
    local textX = cx + pad + 2
    local indent = headerFs  -- 缩进1个汉字宽度
    local indentX = textX + indent
    local scrollBarW = 5
    local btnSize = headerFs  -- +/- 按钮尺寸

    -- 展开/收起状态
    local expanded = GS.journalSectionExpanded or { true, true, true }
    local toggleRects = {}
    local submitRects = {}  -- 提交任务按钮点击区域

    local totalH = 0

    -- 分区标题颜色：1=主线(金), 2=支线(蓝), 3=委托(绿)
    local sectionColors = {
        { r = 230, g = 195, b = 60 },   -- 主线：亮金色
        { r = 50,  g = 100, b = 200 },  -- 支线：蓝色
        { r = 40,  g = 120, b = 50 },   -- 委托：深绿色
    }

    -- 条目间分隔线的额外间距（让分隔线居中于上下文本之间）
    local entrySepGap = 8

    -- 辅助：绘制向右渐变消失的底板
    local function drawGradientPlate(plateX, plateY, plateW, plateH, r, g, b, alpha)
        local grad = nvgLinearGradient(vg, plateX, plateY, plateX + plateW, plateY,
            nvgRGBA(r, g, b, alpha), nvgRGBA(r, g, b, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, plateX, plateY, plateW, plateH, 3)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    -- 辅助：绘制分区标题（彩色加粗 + 展开/收起按钮 + 渐变底板，返回消耗高度）
    local function drawSectionHeader(secIdx, label, drawY, draw)
        local h = headerFs + 8
        local isExpanded = expanded[secIdx]
        local sc = sectionColors[secIdx] or { r = 25, g = 18, b = 8 }
        if draw then
            -- +/- 按钮
            local btnX = textX
            local btnY = drawY + 4
            local btnR = 3

            -- 渐变底板（覆盖标题整行，统一深灰色）
            local plateX = btnX - 2
            local plateY = drawY + 1
            local plateW = (cx + cw - pad - scrollBarW) - plateX
            local plateH = h - 2
            drawGradientPlate(plateX, plateY, plateW, plateH, 30, 25, 20, 100)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnSize, btnSize, btnR)
            nvgFillColor(vg, nvgRGBA(60, 45, 25, 180))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 90, 50, 160))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 按钮符号
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, headerFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 200, 160, 240))
            local symbol = isExpanded and "-" or "+"
            nvgText(vg, btnX + btnSize / 2, btnY + btnSize / 2, symbol, nil)

            -- 标题文字（彩色加粗）
            local labelX = btnX + btnSize + 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, headerFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local midY = drawY + h / 2
            nvgFillColor(vg, nvgRGBA(sc.r, sc.g, sc.b, 245))
            nvgText(vg, labelX, midY, label, nil)
            nvgText(vg, labelX + 0.5, midY, label, nil)

            -- 记录按钮区域（btnY 已是绝对屏幕坐标）
            toggleRects[secIdx] = { x = btnX, y = btnY, w = btnSize + 4 + nvgTextBounds(vg, 0, 0, label, nil) + 4, h = btnSize }
        else
            -- 第一轮也要记录（占位）
            toggleRects[secIdx] = { x = 0, y = 0, w = 0, h = 0 }
        end
        return h
    end

    -- 辅助：绘制委托任务条目（缩进显示，返回消耗高度）
    local function drawQuestEntry(quest, questIdx, drawY, draw)
        local textLeftX = indentX + 4
        local maxTextW = (cx + cw - pad - scrollBarW - 4) - textLeftX
        if maxTextW < 20 then maxTextW = 20 end

        -- 准备文本
        local typeLabel = BulletinBoard.getQuestTypeLabel(quest)
        local desc = BulletinBoard.getQuestDesc(quest)
        local isQuestReady = (quest.ready and not quest.completed)
        local progressText
        if quest.rewarded then
            progressText = "已完成 - 已领取奖励"
        elseif quest.completed then
            progressText = "已完成 - 待领取奖励"
        elseif isQuestReady then
            progressText = "目标已达成 - 待提交"
        else
            local current = quest.progress
            if quest.type == BulletinBoard.QUEST_TYPES.DROP_SUBMIT
                or quest.type == BulletinBoard.QUEST_TYPES.PLANT_GATHER
                or quest.type == BulletinBoard.QUEST_TYPES.MINE_GATHER then
                local held = GS.countInventoryItem(quest.targetId)
                current = held
            end
            progressText = "进度: " .. current .. " / " .. quest.required
        end

        -- 计算换行后高度（nvgTextBoxBounds 对 CJK 换行文本可能返回偏小值，
        -- 用单行宽度估算行数作为兜底）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, bodyFs)
        local _, _, actualLineH = nvgTextMetrics(vg)
        if actualLineH <= 0 then actualLineH = bodyFs end

        local descBounds = {0, 0, 0, 0}
        nvgTextBoxBounds(vg, 0, 0, maxTextW, desc, nil, descBounds)
        local descH = math.max(bodyFs, (descBounds[4] or 0) - (descBounds[2] or 0))
        -- 兜底：用单行宽度估算最少行数
        local descFullW = nvgTextBounds(vg, 0, 0, desc, nil)
        local descMinLines = math.max(1, math.ceil(descFullW / maxTextW))
        local descMinH = descMinLines * actualLineH
        if descH < descMinH then descH = descMinH end

        local bounds = {0, 0, 0, 0}
        nvgTextBoxBounds(vg, 0, 0, maxTextW, progressText, nil, bounds)
        local progH = (bounds[4] or 0) - (bounds[2] or 0)
        if progH <= 0 then progH = bodyFs end
        -- 兜底
        local progFullW = nvgTextBounds(vg, 0, 0, progressText, nil)
        local progMinLines = math.max(1, math.ceil(progFullW / maxTextW))
        local progMinH = progMinLines * actualLineH
        if progH < progMinH then progH = progMinH end

        local submitBtnH = isQuestReady and (bodyFs + 8) or 0
        local entryH = (bodyFs + 4) + descH + 2 + progH + 4 + submitBtnH

        if draw then
            local ey = drawY

            -- 三角形标志（与分区 +/- 按钮对齐在 textX）
            local triS = bodyFs * 0.45
            local tcx = textX + btnSize / 2
            local tcy = ey + bodyFs * 0.72
            local function triPath(s)
                nvgBeginPath(vg)
                nvgMoveTo(vg, tcx, tcy - s * 1.0)
                nvgLineTo(vg, tcx + s * 0.87, tcy + s * 0.5)
                nvgLineTo(vg, tcx - s * 0.87, tcy + s * 0.5)
                nvgClosePath(vg)
            end
            -- 外发光
            triPath(triS * 1.3)
            nvgFillColor(vg, nvgRGBA(40, 160, 60, 35))
            nvgFill(vg)
            -- 深色描边底
            triPath(triS * 1.1)
            nvgFillColor(vg, nvgRGBA(15, 60, 20, 220))
            nvgFill(vg)
            -- 渐变主体
            triPath(triS)
            local triPaint = nvgLinearGradient(vg, tcx, tcy - triS, tcx, tcy + triS * 0.5,
                nvgRGBA(80, 200, 90, 255), nvgRGBA(30, 110, 40, 255))
            nvgFillPaint(vg, triPaint)
            nvgFill(vg)
            -- 中心高光
            local hlS = triS * 0.35
            nvgBeginPath(vg)
            nvgMoveTo(vg, tcx, tcy - hlS * 0.6)
            nvgLineTo(vg, tcx + hlS * 0.5, tcy + hlS * 0.3)
            nvgLineTo(vg, tcx - hlS * 0.5, tcy + hlS * 0.3)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(180, 255, 190, 120))
            nvgFill(vg)

            -- 第一行：任务名称（深绿色字体 + 渐变底板）+ 右侧奖励
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local nameTW = nvgTextBounds(vg, 0, 0, typeLabel, nil)
            local namePlateW = math.max(nameTW + 20, (cx + cw - pad - scrollBarW - indentX) * 0.7)
            local qPlateH = bodyFs + 2
            local qPlateY = ey + 1
            drawGradientPlate(indentX - 2, qPlateY, namePlateW, qPlateH, 40, 35, 30, 60)
            nvgFillColor(vg, nvgRGBA(40, 130, 50, 245))
            nvgText(vg, indentX, ey, typeLabel, nil)
            -- 奖励（任务名称同行靠右，黑色描边）
            do
                local parts = {}
                if quest.reward and quest.reward > 0 then parts[#parts + 1] = quest.reward .. "金币" end
                if quest.expReward and quest.expReward > 0 then parts[#parts + 1] = (quest.expReward) .. "经验值" end
                if #parts > 0 then
                    local rewardStr = "奖励：" .. table.concat(parts, "、")
                    local rwRightX = cx + cw - pad - scrollBarW - 4
                    nvgFontSize(vg, bodyFs)
                    -- 先画暗金色下划线（底层）
                    local rwTW = nvgTextBounds(vg, 0, 0, rewardStr, nil)
                    local ulY2 = ey + bodyFs + 1
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, rwRightX - rwTW, ulY2)
                    nvgLineTo(vg, rwRightX, ulY2)
                    nvgStrokeColor(vg, nvgRGBA(160, 120, 30, 180))
                    nvgStrokeWidth(vg, 2.0)
                    nvgStroke(vg)
                    -- 再画文字（上层）
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(50, 35, 15, 230))
                    nvgText(vg, rwRightX, ey, rewardStr, nil)
                end
            end
            ey = ey + bodyFs + 4

            -- 第二行：任务内容（自动换行，CJK避头尾）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(50, 35, 15, 230))
            nvgTextBox(vg, textLeftX, ey, maxTextW, desc, nil)
            ey = ey + descH + 2

            -- 第三行：进度（未完成=白色，已完成=绿色+√）
            local objDone = isQuestReady or quest.completed or quest.rewarded
            if objDone then
                nvgFillColor(vg, nvgRGBA(40, 180, 50, 240))
            else
                nvgFillColor(vg, nvgRGBA(240, 240, 240, 240))
            end
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local displayProgress = progressText
            if objDone then displayProgress = progressText .. " √" end
            nvgTextBox(vg, textLeftX, ey, maxTextW, displayProgress, nil)
            ey = ey + progH + 2

            -- 记录进度行底部 Y，用于提交按钮居中
            local progBottomY = ey

            -- 提交任务按钮（仅 ready 且未 completed 时显示，居中于进度行底部与分隔线之间）
            if isQuestReady then
                local submitLabel = "提交任务"
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, bodyFs)
                local stw = nvgTextBounds(vg, 0, 0, submitLabel, nil)
                local sbW = stw + 12
                local sbH = bodyFs + 4
                local sbX = textLeftX
                -- 居中于 progBottomY 和 (progBottomY + submitBtnH) 之间
                local sbY = progBottomY + (submitBtnH - sbH) / 2

                -- 按钮背景（绿色渐变，与委托任务主题匹配）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sbX, sbY, sbW, sbH, 3)
                local sbGrad = nvgLinearGradient(vg, sbX, sbY, sbX, sbY + sbH,
                    nvgRGBA(60, 160, 60, 220), nvgRGBA(30, 120, 30, 220))
                nvgFillPaint(vg, sbGrad)
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(20, 80, 20, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 按钮文字
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(240, 255, 240, 255))
                nvgText(vg, sbX + sbW / 2, sbY + sbH / 2, submitLabel, nil)

                -- 记录点击区域
                submitRects[#submitRects + 1] = {
                    x = sbX, y = sbY, w = sbW, h = sbH,
                    questType = "bulletin", questIdx = questIdx
                }
            end
        end
        return entryH
    end

    -- 辅助：绘制主线/支线任务条目（缩进显示，返回消耗高度）
    local function drawMainQuestEntry(questInfo, drawY, draw)
        local def = questInfo.def
        local state = questInfo.state
        local isReady = (state and state.status == QuestManager.STATUS_READY)
        local canSubmitHere = isReady and QuestManager.canJournalSubmit(def.id)
        local cur, req, progressLabel, objectives = def.progress(GS, state)
        local textLeftX = indentX + 4
        local maxTextW = (cx + cw - pad - scrollBarW - 4) - textLeftX
        if maxTextW < 20 then maxTextW = 20 end

        -- 计算换行后高度（nvgTextBoxBounds 对 CJK 换行文本可能返回偏小值，
        -- 用单行宽度估算行数作为兜底）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, bodyFs)
        local _, _, actualLineH = nvgTextMetrics(vg)
        if actualLineH <= 0 then actualLineH = bodyFs end

        local descBounds2 = {0, 0, 0, 0}
        nvgTextBoxBounds(vg, 0, 0, maxTextW, def.desc, nil, descBounds2)
        local descH = math.max(bodyFs, (descBounds2[4] or 0) - (descBounds2[2] or 0))
        -- 兜底：用单行宽度估算最少行数
        local descFullW = nvgTextBounds(vg, 0, 0, def.desc, nil)
        local descMinLines = math.max(1, math.ceil(descFullW / maxTextW))
        local descMinH = descMinLines * actualLineH
        if descH < descMinH then descH = descMinH end

        -- 计算进度区域高度（支持多目标）
        local progLines = {}
        local progH = 0
        if objectives and #objectives > 0 then
            for _, obj in ipairs(objectives) do
                local txt = obj[3] .. ": " .. obj[1] .. " / " .. obj[2]
                local b = {0, 0, 0, 0}
                nvgTextBoxBounds(vg, 0, 0, maxTextW, txt, nil, b)
                local h = (b[4] or 0) - (b[2] or 0)
                if h <= 0 then h = bodyFs end
                local fw = nvgTextBounds(vg, 0, 0, txt, nil)
                local ml = math.max(1, math.ceil(fw / maxTextW))
                local mh = ml * actualLineH
                if h < mh then h = mh end
                progLines[#progLines + 1] = { text = txt, h = h, done = (obj[1] >= obj[2]) }
                progH = progH + h + 2
            end
        else
            local progressText = progressLabel .. ": " .. cur .. " / " .. req
            local bounds = {0, 0, 0, 0}
            nvgTextBoxBounds(vg, 0, 0, maxTextW, progressText, nil, bounds)
            local h = (bounds[4] or 0) - (bounds[2] or 0)
            if h <= 0 then h = bodyFs end
            local progFullW = nvgTextBounds(vg, 0, 0, progressText, nil)
            local progMinLines = math.max(1, math.ceil(progFullW / maxTextW))
            local progMinH = progMinLines * actualLineH
            if h < progMinH then h = progMinH end
            progLines[#progLines + 1] = { text = progressText, h = h, done = (cur >= req) }
            progH = h
        end

        local submitBtnH = canSubmitHere and (bodyFs + 8) or 0
        local entryH = (bodyFs + 4) + descH + 2 + progH + 4 + submitBtnH

        if draw then
            local ey = drawY
            local isSide = (def.category == "side")

            local iconS = isSide and (bodyFs * 0.45) or (bodyFs * 0.65)
            local icx = textX + btnSize / 2
            local icy = ey + bodyFs * 0.66

            if isSide then
                -- 方块标志（支线任务）
                local function squarePath(s)
                    nvgBeginPath(vg)
                    nvgRect(vg, icx - s, icy - s, s * 2, s * 2)
                end
                -- 外发光
                squarePath(iconS * 1.3)
                nvgFillColor(vg, nvgRGBA(50, 120, 220, 35))
                nvgFill(vg)
                -- 深色描边底
                squarePath(iconS * 1.1)
                nvgFillColor(vg, nvgRGBA(15, 40, 100, 220))
                nvgFill(vg)
                -- 渐变主体
                squarePath(iconS)
                local sqPaint = nvgLinearGradient(vg, icx, icy - iconS, icx, icy + iconS,
                    nvgRGBA(80, 150, 240, 255), nvgRGBA(30, 80, 180, 255))
                nvgFillPaint(vg, sqPaint)
                nvgFill(vg)
                -- 中心高光
                squarePath(iconS * 0.4)
                nvgFillColor(vg, nvgRGBA(180, 210, 255, 130))
                nvgFill(vg)
            else
                -- 四芒星标志（主线任务）
                local function starPath(s)
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, icx, icy - s)
                    nvgQuadTo(vg, icx + s * 0.18, icy - s * 0.18, icx + s, icy)
                    nvgQuadTo(vg, icx + s * 0.18, icy + s * 0.18, icx, icy + s)
                    nvgQuadTo(vg, icx - s * 0.18, icy + s * 0.18, icx - s, icy)
                    nvgQuadTo(vg, icx - s * 0.18, icy - s * 0.18, icx, icy - s)
                    nvgClosePath(vg)
                end
                -- 外发光
                starPath(iconS * 1.25)
                nvgFillColor(vg, nvgRGBA(255, 210, 50, 40))
                nvgFill(vg)
                -- 深色描边底
                starPath(iconS * 1.05)
                nvgFillColor(vg, nvgRGBA(120, 80, 10, 220))
                nvgFill(vg)
                -- 渐变主体
                starPath(iconS)
                local starPaint = nvgLinearGradient(vg, icx, icy - iconS, icx, icy + iconS,
                    nvgRGBA(255, 225, 80, 255), nvgRGBA(190, 140, 20, 255))
                nvgFillPaint(vg, starPaint)
                nvgFill(vg)
                -- 中心高光
                starPath(iconS * 0.45)
                nvgFillColor(vg, nvgRGBA(255, 250, 200, 140))
                nvgFill(vg)
            end

            -- 第一行：任务名称（+ 渐变底板）+ 右侧奖励
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local mNameTW = nvgTextBounds(vg, 0, 0, def.name, nil)
            local mNamePlateW = math.max(mNameTW + 20, (cx + cw - pad - scrollBarW - indentX) * 0.7)
            local mPlateH = bodyFs + 2
            local mPlateY = ey + 1
            if isSide then
                drawGradientPlate(indentX - 2, mPlateY, mNamePlateW, mPlateH, 40, 35, 30, 60)
                nvgFillColor(vg, nvgRGBA(50, 100, 200, 245))
            else
                drawGradientPlate(indentX - 2, mPlateY, mNamePlateW, mPlateH, 40, 35, 30, 60)
                nvgFillColor(vg, nvgRGBA(230, 195, 60, 245))
            end
            nvgText(vg, indentX, ey, def.name, nil)
            -- 奖励（任务名称同行靠右，黑色描边）
            do
                local rewardStr
                if def.rewardLabel then
                    rewardStr = def.rewardLabel
                else
                    local parts = {}
                    local rItems, rGold = QuestManager.resolveRewards(def)
                    if rGold and rGold > 0 then parts[#parts + 1] = rGold .. "金币" end
                    if rItems then
                        for _, ri in ipairs(rItems) do
                            local tpl = GS.itemTemplates[ri.templateId]
                            local itemName = tpl and tpl.name or ri.templateId
                            parts[#parts + 1] = itemName .. "x" .. (ri.count or 1)
                        end
                    end
                    if #parts > 0 then
                        rewardStr = "奖励：" .. table.concat(parts, "、")
                    end
                end
                if rewardStr then
                    local rwRightX = cx + cw - pad - scrollBarW - 4
                    nvgFontSize(vg, bodyFs)
                    -- 先画暗金色下划线（底层）
                    local rwTW = nvgTextBounds(vg, 0, 0, rewardStr, nil)
                    local ulY2 = ey + bodyFs + 1
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, rwRightX - rwTW, ulY2)
                    nvgLineTo(vg, rwRightX, ulY2)
                    nvgStrokeColor(vg, nvgRGBA(160, 120, 30, 180))
                    nvgStrokeWidth(vg, 2.0)
                    nvgStroke(vg)
                    -- 再画文字（上层）
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(50, 35, 15, 230))
                    nvgText(vg, rwRightX, ey, rewardStr, nil)
                end
            end
            ey = ey + bodyFs + 4

            -- 第二行：任务描述（自动换行，CJK避头尾）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(50, 35, 15, 230))
            nvgTextBox(vg, textLeftX, ey, maxTextW, def.desc, nil)
            ey = ey + descH + 2

            -- 第三行：进度（支持多目标，未完成=白色，已完成=绿色+√）
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            for _, pl in ipairs(progLines) do
                if pl.done then
                    nvgFillColor(vg, nvgRGBA(40, 180, 50, 240))
                else
                    nvgFillColor(vg, nvgRGBA(240, 240, 240, 240))
                end
                local displayProgress = pl.done and (pl.text .. " √") or pl.text
                nvgTextBox(vg, textLeftX, ey, maxTextW, displayProgress, nil)
                ey = ey + pl.h + 2
            end

            -- 记录进度行底部 Y，用于提交按钮居中
            local progBottomY = ey

            -- 提交任务按钮（仅 journal 提交方式 + ready 状态显示）
            if canSubmitHere then
                local submitLabel = "提交任务"
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, bodyFs)
                local stw = nvgTextBounds(vg, 0, 0, submitLabel, nil)
                local sbW = stw + 12
                local sbH = bodyFs + 4
                local sbX = textLeftX
                -- 居中于 progBottomY 和 (progBottomY + submitBtnH) 之间
                local sbY = progBottomY + (submitBtnH - sbH) / 2

                -- 按钮背景（暖金色渐变）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sbX, sbY, sbW, sbH, 3)
                local sbGrad = nvgLinearGradient(vg, sbX, sbY, sbX, sbY + sbH,
                    nvgRGBA(200, 160, 40, 220), nvgRGBA(160, 120, 20, 220))
                nvgFillPaint(vg, sbGrad)
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(120, 90, 20, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 按钮文字
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 250, 230, 255))
                nvgText(vg, sbX + sbW / 2, sbY + sbH / 2, submitLabel, nil)

                -- 记录点击区域
                submitRects[#submitRects + 1] = {
                    x = sbX, y = sbY, w = sbW, h = sbH,
                    questType = "main", questId = def.id
                }
            end
        end
        return entryH
    end

    -- 辅助：绘制空提示文字（缩进）
    local function drawEmptyHint(hint, drawY, draw)
        local h = lineH + 2
        if draw then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(130, 110, 80, 150))
            nvgText(vg, indentX + 4, drawY + 2, hint, nil)
        end
        return h
    end

    -- ======== 收集数据 ========
    local acceptedQuests = BulletinBoard.getAcceptedQuests()
    QuestManager.update()  -- 刷新主线/支线任务状态
    local activeMainQuests = QuestManager.getActiveMainQuests()
    local activeSideQuests = QuestManager.getActiveSideQuests()

    -- ======== 固定日期时间（不随滚动） ========
    local dateBandH = 0
    if GS.awakeningCompleted then
        dateBandH = lineH + 2
        local MONTH_DAYS_J = {30,30,30,30,30,30,30,30,30,30,30,30}
        local totalMin = ((GS.weatherTime or 1) - 1)
        local dayOfYear = math.floor(totalMin / 1440)
        local minuteOfDay = totalMin % 1440
        local hour = math.floor(minuteOfDay / 60)
        local minute = minuteOfDay % 60
        local month, day = 1, dayOfYear + 1
        for m = 1, 12 do
            if day <= MONTH_DAYS_J[m] then month = m; break end
            day = day - MONTH_DAYS_J[m]
        end
        local dateStr = string.format("%d月%d日 %02d:%02d", month, day, hour, minute)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, bodyFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
        nvgText(vg, cx + cw / 2, cy + dateBandH / 2, dateStr, nil)
    end

    -- 滚动区域从日期下方开始
    local scrollCy = cy + dateBandH
    local scrollCh = ch - dateBandH
    GS.journalScrollRect = { x = cx, y = scrollCy, w = cw, h = scrollCh }
    GS.journalVisibleH = scrollCh

    -- ======== 两轮渲染 ========
    for pass = 1, 2 do
        local draw = (pass == 2)
        local curY

        if draw then
            nvgSave(vg)
            nvgIntersectScissor(vg, cx, scrollCy, cw, scrollCh)
            curY = scrollCy + pad - (GS.journalScrollY or 0)
        else
            curY = 0
        end

        -- ---- 1. 主线任务 ----
        curY = curY + drawSectionHeader(1, "主线任务", curY, draw)
        if expanded[1] then
            if #activeMainQuests == 0 then
                curY = curY + drawEmptyHint("暂无主线任务", curY, draw)
            else
                for i_, qi in ipairs(activeMainQuests) do
                    curY = curY + drawMainQuestEntry(qi, curY, draw)
                    if i_ < #activeMainQuests then
                        if draw then
                            local sepY = curY + entrySepGap / 2
                            nvgBeginPath(vg)
                            nvgMoveTo(vg, indentX, sepY)
                            nvgLineTo(vg, cx + cw - pad - scrollBarW, sepY)
                            nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 50))
                            nvgStrokeWidth(vg, 0.5)
                            nvgStroke(vg)
                        end
                        curY = curY + entrySepGap
                    end
                end
            end
        end
        -- 分隔线 1→2
        if draw then
            local lineY = curY + sectionGap / 2
            nvgBeginPath(vg)
            nvgMoveTo(vg, textX, lineY)
            nvgLineTo(vg, cx + cw - pad - scrollBarW, lineY)
            nvgStrokeColor(vg, nvgRGBA(80, 60, 30, 60))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
        end
        curY = curY + sectionGap

        -- ---- 2. 支线任务 ----
        curY = curY + drawSectionHeader(2, "支线任务", curY, draw)
        if expanded[2] then
            if #activeSideQuests == 0 then
                curY = curY + drawEmptyHint("暂无支线任务", curY, draw)
            else
                for i_, qi in ipairs(activeSideQuests) do
                    curY = curY + drawMainQuestEntry(qi, curY, draw)
                    if i_ < #activeSideQuests then
                        if draw then
                            local sepY = curY + entrySepGap / 2
                            nvgBeginPath(vg)
                            nvgMoveTo(vg, indentX, sepY)
                            nvgLineTo(vg, cx + cw - pad - scrollBarW, sepY)
                            nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 50))
                            nvgStrokeWidth(vg, 0.5)
                            nvgStroke(vg)
                        end
                        curY = curY + entrySepGap
                    end
                end
            end
        end
        -- 分隔线 2→3
        if draw then
            local lineY = curY + sectionGap / 2
            nvgBeginPath(vg)
            nvgMoveTo(vg, textX, lineY)
            nvgLineTo(vg, cx + cw - pad - scrollBarW, lineY)
            nvgStrokeColor(vg, nvgRGBA(80, 60, 30, 60))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
        end
        curY = curY + sectionGap

        -- ---- 3. 委托任务 ----
        curY = curY + drawSectionHeader(3, "委托任务", curY, draw)
        if expanded[3] then
            if #acceptedQuests == 0 then
                curY = curY + drawEmptyHint("暂无已接取的委托，前往布告栏接取", curY, draw)
            else
                for i_, aq in ipairs(acceptedQuests) do
                    curY = curY + drawQuestEntry(aq.quest, aq.idx, curY, draw)
                    if i_ < #acceptedQuests then
                        if draw then
                            local sepY = curY + entrySepGap / 2
                            nvgBeginPath(vg)
                            nvgMoveTo(vg, indentX, sepY)
                            nvgLineTo(vg, cx + cw - pad - scrollBarW, sepY)
                            nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 50))
                            nvgStrokeWidth(vg, 0.5)
                            nvgStroke(vg)
                        end
                        curY = curY + entrySepGap
                    end
                end
            end
        end
        curY = curY + pad

        if pass == 1 then
            totalH = curY
        else
            nvgRestore(vg)
        end
    end

    -- 更新按钮点击区域（第二轮已计算好绝对坐标）
    GS.journalToggleBtnRects = toggleRects
    GS.journalSubmitBtnRects = submitRects
    GS.journalContentH = totalH

    -- ======== 滚动条 ========
    if totalH > scrollCh then
        local maxScroll = totalH - scrollCh
        local scrollY = math.min(GS.journalScrollY or 0, maxScroll)
        GS.journalScrollY = scrollY

        local barTotalH = scrollCh - 4
        local thumbH = math.max(12, barTotalH * (scrollCh / totalH))
        local thumbY = scrollCy + 2 + (barTotalH - thumbH) * (scrollY / maxScroll)
        local barX = cx + cw - scrollBarW - 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, scrollCy + 2, scrollBarW, barTotalH, 2)
        nvgFillColor(vg, nvgRGBA(80, 60, 40, 40))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, scrollBarW, thumbH, 2)
        nvgFillColor(vg, nvgRGBA(140, 110, 70, 160))
        nvgFill(vg)
    else
        GS.journalScrollY = 0
    end
end

-- ====================================================================
-- 面板内容：地图（Tab 5）
-- ====================================================================
-- 世界地图地点定义（归一化坐标，基于2048x2048原图）
-- tx, ty = 原图上装饰文字的中心位置（用于高亮和点击区域）
-- tw, th = 文字区域的大致宽高（归一化）
M.MAP_LOCATIONS = {
    { id = "grey_sea",       name = "灰海",     tx = 0.40,  ty = 0.190, tw = 0.18, th = 0.07, color = {80, 160, 220},  desc = "寒冷的北方海域，常年浓雾笼罩", level = "Lv.54-85", bg = "image/bg_sea.png", requiredRank = 3, stages = {
        { name = "灰海海岸", type = "battle", stageIndex = GS.STAGE_ROCK_TURTLE, monsterInfo = "岩壳龟 Lv54" },
        { name = "灰海浅滩", type = "battle", stageIndex = GS.STAGE_TURTLE_SHARK, monsterInfo = "鱼人 Lv69", bg = "image/bg_beach.png" },
        { name = "灰海海边洞窟", type = "battle", stageIndex = GS.STAGE_SEA_DEMONS, monsterInfo = "双魔 Lv83", bg = "image/bg_sea_cave_grotto.png" },
        { name = "海边植物区入口", type = "battle", stageIndex = GS.STAGE_GATHER_GREY_SEA_LV1, monsterInfo = "Lv54", bg = "image/bg_gather_sea.png", zone = "gather", gatherType = "plant" },
        { name = "海边植物区中心", type = "battle", stageIndex = GS.STAGE_GATHER_GREY_SEA_LV2, monsterInfo = "Lv69", bg = "image/bg_gather_sea.png", zone = "gather", gatherType = "plant" },
        { name = "海边植物区深处", type = "battle", stageIndex = GS.STAGE_GATHER_GREY_SEA_LV3, monsterInfo = "Lv85", bg = "image/bg_gather_sea.png", zone = "gather", gatherType = "plant" },
        { name = "海边矿洞入口", type = "battle", stageIndex = GS.STAGE_GATHER_SEA_LV1, monsterInfo = "Lv150", bg = "image/bg_sea_cave.png", zone = "gather", gatherType = "mine" },
        { name = "海边矿洞前段", type = "battle", stageIndex = GS.STAGE_GATHER_SEA_LV2, monsterInfo = "Lv150", bg = "image/bg_sea_cave_deep.png", zone = "gather", gatherType = "mine" },
        { name = "海边矿洞中心", type = "battle", stageIndex = GS.STAGE_GATHER_SEA_LV3, monsterInfo = "Lv150", bg = "image/bg_sea_cave_deep.png", zone = "gather", gatherType = "mine" },
        { name = "海边矿洞深处", type = "battle", stageIndex = GS.STAGE_GATHER_SEA_LV4, monsterInfo = "Lv150", bg = "image/bg_sea_cave_deep.png", zone = "gather", gatherType = "mine" },
        -- 深渊区
        { name = "潮汐祭祀圣所", type = "battle", stageIndex = GS.STAGE_TIDAL_SANCTUARY, monsterInfo = "Lv85", bg = "image/bg_tidal_sanctuary.png", dungeon = true, dungeonId = "tidal_sanctuary", zone = "dungeon", unlockQuest = "main_freya_dungeon3", unlockRank = 5 },
    }},
    { id = "clearwater",     name = "清水镇",   tx = 0.514, ty = 0.321, tw = 0.15, th = 0.06, color = {90, 190, 130},  desc = "宁静的小镇，冒险者的起点",     level = "Lv.1-5",   stages = {
        { name = "清水镇",   type = "town", overlayId = "clearwater", bg = "image/bg_grass.png" },
        { name = "你的家",   type = "home", bg = "image/bg_home.png" },
        { name = "训练场",   type = "training", stageIndex = GS.STAGE_TRAINING, bg = "image/bg_training.png" },
    }},
    { id = "grey_mountain",  name = "灰山",     tx = 0.133, ty = 0.505, tw = 0.12, th = 0.07, color = {160, 150, 140}, desc = "巍峨的山脉，矿藏丰富",         level = "Lv.46-120",bg = "image/bg_grass.png", requiredRank = 4, stages = {
        -- 采集区（植物）
        { name = "植物繁茂区入口", type = "battle", stageIndex = GS.STAGE_GATHER_GREY_MT_LV1, monsterInfo = "Lv46",  bg = "image/bg_gather_forest.png", zone = "gather", gatherType = "plant" },
        { name = "植物繁茂区中心", type = "battle", stageIndex = GS.STAGE_GATHER_GREY_MT_LV2, monsterInfo = "Lv90",  bg = "image/bg_gather_forest.png", zone = "gather", gatherType = "plant" },
        { name = "植物繁茂区深处", type = "battle", stageIndex = GS.STAGE_GATHER_GREY_MT_LV3, monsterInfo = "Lv120", bg = "image/bg_gather_forest.png", zone = "gather", gatherType = "plant" },
        -- 采集区（矿洞）
        { name = "山崖矿洞入口", type = "battle", stageIndex = GS.STAGE_GATHER_MOUNT_LV1, monsterInfo = "Lv46", bg = "image/bg_mount_cave.png", zone = "gather", gatherType = "mine" },
        { name = "山崖矿洞前段", type = "battle", stageIndex = GS.STAGE_GATHER_MOUNT_LV2, monsterInfo = "Lv46", bg = "image/bg_mount_cave_deep.png", zone = "gather", gatherType = "mine" },
        { name = "山崖矿洞中心", type = "battle", stageIndex = GS.STAGE_GATHER_MOUNT_LV3, monsterInfo = "Lv120", bg = "image/bg_mount_cave_deep.png", zone = "gather", gatherType = "mine" },
        { name = "山崖矿洞深处", type = "battle", stageIndex = GS.STAGE_GATHER_MOUNT_LV4, monsterInfo = "Lv120", bg = "image/bg_mount_cave_deep.png", zone = "gather", gatherType = "mine" },
        -- 常规区
        { name = "灰山脚下森林入口", type = "battle", stageIndex = GS.STAGE_GREY_BEAR, monsterInfo = "灰熊 Lv46", bg = "image/bg_forest.png" },
        { name = "灰山脚下森林", type = "battle", stageIndex = GS.STAGE_CENTAURS, monsterInfo = "半人马 Lv74", bg = "image/bg_forest.png" },
    }},
    { id = "mist_forest",    name = "垂雾森林", tx = 0.838, ty = 0.383, tw = 0.24, th = 0.07, color = {70, 160, 90},   desc = "古老的密林，暗藏未知的危险",   level = "Lv.3-88",  bg = "image/bg_forest.png", stages = {
        -- 采集区（植物）
        { name = "植物繁茂区入口", type = "battle", stageIndex = GS.STAGE_GATHER_MIST_FOREST_LV1, monsterInfo = "Lv3",  bg = "image/bg_gather_forest.png", zone = "gather", gatherType = "plant" },
        { name = "植物繁茂区中心", type = "battle", stageIndex = GS.STAGE_GATHER_MIST_FOREST_LV2, monsterInfo = "Lv30", bg = "image/bg_gather_forest.png", zone = "gather", gatherType = "plant" },
        { name = "植物繁茂区深处", type = "battle", stageIndex = GS.STAGE_GATHER_MIST_FOREST_LV3, monsterInfo = "Lv60", bg = "image/bg_gather_forest.png", zone = "gather", gatherType = "plant" },
        -- 采集区（矿洞）
        { name = "森林矿洞入口",   type = "battle", stageIndex = GS.STAGE_GATHER_FOREST_LV1, monsterInfo = "Lv3",  bg = "image/bg_forest_cave.png", zone = "gather", gatherType = "mine" },
        { name = "森林矿洞开发区", type = "battle", stageIndex = GS.STAGE_GATHER_FOREST_LV2, monsterInfo = "Lv30", bg = "image/bg_forest_cave_mid.png", zone = "gather", gatherType = "mine" },
        { name = "森林矿洞中心",   type = "battle", stageIndex = GS.STAGE_GATHER_FOREST_LV3, monsterInfo = "Lv60", bg = "image/bg_forest_cave_deep.png", zone = "gather", gatherType = "mine" },
        { name = "森林矿洞深处",   type = "battle", stageIndex = GS.STAGE_GATHER_FOREST_LV4, monsterInfo = "Lv90", bg = "image/bg_forest_cave_deep.png", zone = "gather", gatherType = "mine" },
        -- 常规区（默认）
        { name = "森林入口",   type = "battle", stageIndex = GS.STAGE_BAT,            monsterInfo = "蝙蝠 Lv3" },
        { name = "森林外围一", type = "battle", stageIndex = GS.STAGE_WOLF,           monsterInfo = "野狼 Lv7" },
        { name = "森林外围二", type = "battle", stageIndex = GS.STAGE_BOAR,           monsterInfo = "野猪 Lv11" },
        { name = "森林中心一", type = "battle", stageIndex = GS.STAGE_FIERCE_WOLF,    monsterInfo = "凶狼 Lv20" },
        { name = "森林中心二", type = "battle", stageIndex = GS.STAGE_TREE_ROOT,      monsterInfo = "树根精 Lv29" },
        { name = "森林中心三", type = "battle", stageIndex = GS.STAGE_BEAR,           monsterInfo = "野熊 Lv43" },
        { name = "森林深处一", type = "battle", stageIndex = GS.STAGE_GIANT_TREE_ROOT, monsterInfo = "大型树根精 Lv66" },
        { name = "森林深处二", type = "battle", stageIndex = GS.STAGE_TREE_FAIRY,     monsterInfo = "树精女妖 Lv88", bg = "image/bg_forest_deep.png" },
        -- 深渊区（暂空）
    }},
    { id = "mercy_plain",    name = "慈爱平原", tx = 0.46,  ty = 0.522, tw = 0.20, th = 0.06, color = {200, 180, 80},  desc = "广袤的草原，商路的交汇之地",   level = "Lv.1-63",  bg = "image/bg_grass.png", stages = {
        -- 采集区（植物）
        { name = "植物茂盛区入口", type = "battle", stageIndex = GS.STAGE_GATHER_PLAIN_LV1,    monsterInfo = "Lv1", bg = "image/bg_gather_plain.png", zone = "gather", gatherType = "plant" },
        { name = "植物茂盛区中心", type = "battle", stageIndex = GS.STAGE_GATHER_PLAIN_LV2,    monsterInfo = "Lv30", bg = "image/bg_gather_plain.png", zone = "gather", gatherType = "plant" },
        { name = "植物茂盛区深处", type = "battle", stageIndex = GS.STAGE_GATHER_PLAIN_LV3,    monsterInfo = "Lv60", bg = "image/bg_gather_plain.png", zone = "gather", gatherType = "plant" },
        -- 采集区（矿洞）
        { name = "平原矿洞入口", type = "battle", stageIndex = GS.STAGE_GATHER_PLAIN_MINE_LV1, monsterInfo = "Lv1",  bg = "image/bg_mine_entrance.png", zone = "gather", gatherType = "mine" },
        { name = "平原矿洞开发区", type = "battle", stageIndex = GS.STAGE_GATHER_PLAIN_MINE_LV2, monsterInfo = "Lv30", bg = "image/bg_mine_dev.png", zone = "gather", gatherType = "mine" },
        -- 战斗区（默认）
        { name = "平原入口",       type = "battle", stageIndex = GS.STAGE_SLIME,         monsterInfo = "史莱姆 Lv1" },
        { name = "平原外围",       type = "battle", stageIndex = GS.STAGE_GOBLIN,        monsterInfo = "哥布林 Lv15" },
        { name = "平原中心",       type = "battle", stageIndex = GS.STAGE_GOBLIN_SWARM,        monsterInfo = "大群哥布林 Lv16" },
        { name = "平原深处",       type = "battle", stageIndex = GS.STAGE_DEMON_SLIME,   monsterInfo = "恶魔史莱姆 Lv33" },
        { name = "平原深处的墓地", type = "battle", stageIndex = GS.STAGE_SKELETON, monsterInfo = "骷髅兵 Lv37", bg = "image/bg_graveyard.png" },
        { name = "墓穴入口",         type = "battle", stageIndex = GS.STAGE_MUMMY,         monsterInfo = "木乃伊 Lv63", bg = "image/bg_crypt.png" },
        -- 副本区
        { name = "史莱姆王国",     type = "battle", stageIndex = GS.STAGE_SLIME_KINGDOM,       monsterInfo = "Lv45", bg = "image/bg_slime_kingdom.png", dungeon = true, dungeonId = "slime_kingdom", zone = "dungeon", unlockQuest = "main_freya_dungeon1", unlockRank = 3 },
        { name = "哥布林竞技场",   type = "battle", stageIndex = GS.STAGE_GOBLIN_ARENA,        monsterInfo = "Lv65", bg = "image/bg_goblin_arena.png", dungeon = true, dungeonId = "goblin_arena", zone = "dungeon", unlockQuest = "main_freya_dungeon2", unlockRank = 4 },
    }},
    { id = "barlow_manor",   name = "巴洛庄园", tx = 0.862, ty = 0.570, tw = 0.20, th = 0.06, color = {180, 120, 70},  desc = "神秘的贵族庄园，传闻闹鬼",     level = "Lv.24-91", bg = "image/bg_manor.png", requiredRank = 2, stages = {
        -- 采集区（植物）
        { name = "庄园种植区入口", type = "battle", stageIndex = GS.STAGE_GATHER_MANOR_LV1, monsterInfo = "Lv24", bg = "image/bg_gather_manor.png", zone = "gather", gatherType = "plant" },
        { name = "庄园种植区中心", type = "battle", stageIndex = GS.STAGE_GATHER_MANOR_LV2, monsterInfo = "Lv42", bg = "image/bg_gather_manor.png", zone = "gather", gatherType = "plant" },
        { name = "庄园种植区深处", type = "battle", stageIndex = GS.STAGE_GATHER_MANOR_LV3, monsterInfo = "Lv57", bg = "image/bg_gather_manor.png", zone = "gather", gatherType = "plant" },
        { name = "庄园隐秘花房",   type = "battle", stageIndex = GS.STAGE_GATHER_MANOR_LV4, monsterInfo = "Lv91", bg = "image/bg_gather_manor.png", zone = "gather", gatherType = "plant" },
        -- 常规区
        { name = "庄园入口", type = "battle", stageIndex = GS.STAGE_VAMPIRE_YOUTH,      monsterInfo = "吸血魔蝠 Lv25" },
        { name = "庄园一楼", type = "battle", stageIndex = GS.STAGE_GHOST,              monsterInfo = "幽灵 Lv42", bg = "image/bg_manor_staircase.png" },
        { name = "庄园二楼", type = "battle", stageIndex = GS.STAGE_FURNITURE,                 monsterInfo = "家具妖怪 Lv51", bg = "image/bg_manor_library.png" },
        { name = "庄园三楼", type = "battle", stageIndex = GS.STAGE_DOLLS,                     monsterInfo = "人偶 Lv57", bg = "image/bg_manor_interior.png" },
        { name = "庄园四楼", type = "battle", stageIndex = GS.STAGE_VAMPIRES,                   monsterInfo = "吸血鬼 Lv91", bg = "image/bg_manor_bedroom.png" },
    }},
    { id = "moonrise_fort",  name = "升月堡",   tx = 0.298, ty = 0.724, tw = 0.14, th = 0.06, color = {150, 110, 180}, desc = "废弃的要塞，曾是抵御黑暗的前线", level = "Lv.75-97", bg = "image/bg_forest.png", requiredRank = 5, stages = {
        -- 采集区（花园/植物）
        { name = "城下花园入口", type = "battle", stageIndex = GS.STAGE_GATHER_FORT_LV1, monsterInfo = "Lv75", bg = "image/bg_gather_fort.png", zone = "gather", gatherType = "plant" },
        { name = "城下花园中心", type = "battle", stageIndex = GS.STAGE_GATHER_FORT_LV2, monsterInfo = "Lv79", bg = "image/bg_gather_fort.png", zone = "gather", gatherType = "plant" },
        { name = "城下花园深处", type = "battle", stageIndex = GS.STAGE_GATHER_FORT_LV3, monsterInfo = "Lv97", bg = "image/bg_gather_fort.png", zone = "gather", gatherType = "plant" },
        -- 采集区（深窟/矿洞）
        { name = "城下深窟入口", type = "battle", stageIndex = GS.STAGE_GATHER_FORT_MINE_LV1, monsterInfo = "Lv79", bg = "image/bg_deep_cave_entrance.png", zone = "gather", gatherType = "mine" },
        { name = "城下深窟通道", type = "battle", stageIndex = GS.STAGE_GATHER_FORT_MINE_LV2, monsterInfo = "Lv79", bg = "image/bg_deep_cave_tunnel.png", zone = "gather", gatherType = "mine" },
        { name = "城下深窟通道后段", type = "battle", stageIndex = GS.STAGE_GATHER_FORT_MINE_LV2B, monsterInfo = "Lv97", bg = "image/bg_deep_cave_tunnel.png", zone = "gather", gatherType = "mine" },
        { name = "城下深窟开阔区", type = "battle", stageIndex = GS.STAGE_GATHER_FORT_MINE_LV3, monsterInfo = "Lv97", bg = "image/bg_deep_cave_open.png", zone = "gather", gatherType = "mine" },
        -- 常规区
        { name = "城下森林入口", type = "battle", stageIndex = GS.STAGE_STAR_DEMON_ROUND, monsterInfo = "圆滚滚星恶魔 Lv75" },
        { name = "城下森林外围", type = "battle", stageIndex = GS.STAGE_STAR_DEMON_FAT,  monsterInfo = "胖乎乎星恶魔 Lv79" },
        { name = "城下森林中心", type = "battle", stageIndex = GS.STAGE_COSMOS_DEMONS,         monsterInfo = "宇宙恶魔 Lv94" },
        { name = "城下森林深处", type = "battle", stageIndex = GS.STAGE_CHIMERA,          monsterInfo = "蛇尾狮 Lv97" },
        { name = "正门桥梁", type = "battle", stageIndex = GS.STAGE_FORT_BRIDGE, monsterInfo = "石像鬼 Lv110", bg = "image/bg_fort_bridge_day.png" },
        { name = "城堡前厅", type = "battle", stageIndex = GS.STAGE_CASTLE_HALL, monsterInfo = "城堡史莱姆 Lv115", comingSoon = true },
    }},
    -- 异世深渊（圆形按钮入口，完成弑杀红龙的魔女后解锁）
    { id = "abyss", name = "异世深渊", circleBtn = true,
      tx = 0.298, ty = 0.82,
      color = {120, 60, 180}, desc = "时空裂隙中的未知世界",
      level = "Lv.???", bg = "image/bg_abyss.png",
      unlockQuest = "side_lina_manor_6",
      stages = {
          { name = "深渊一层", type = "battle", stageIndex = GS.STAGE_ABYSS_1, monsterInfo = "Lv105 变体 (1-20级怪)", bg = "image/bg_abyss.png" },
          { name = "深渊二层", type = "battle", stageIndex = GS.STAGE_ABYSS_2, monsterInfo = "Lv110 变体 (1-40级怪)", bg = "image/bg_abyss.png" },
          { name = "深渊三层", type = "battle", stageIndex = GS.STAGE_ABYSS_3, monsterInfo = "Lv120 变体 (1-60级怪)", bg = "image/bg_abyss.png" },
          { name = "深渊四层", type = "battle", stageIndex = GS.STAGE_ABYSS_4, monsterInfo = "Lv130 变体 (1-80级怪)", bg = "image/bg_abyss.png" },
          { name = "深渊五层", type = "battle", stageIndex = GS.STAGE_ABYSS_5, monsterInfo = "Lv140 变体 (1-100级怪)", bg = "image/bg_abyss.png" },
      }},
    -- 史莱姆国王大反击（圆形按钮入口，慈爱平原上方）
    { id = "slime_king_revenge", name = "史莱姆国王大反击！", circleBtn = true,
      tx = 0.46, ty = 0.44,
      color = {255, 140, 30}, desc = "暴怒的史莱姆王卷土重来！",
      level = "Lv.45", bg = "image/bg_slime_kingdom.png",
      stages = {
          { name = "迎战！", type = "battle", stageIndex = GS.STAGE_SLIME_KING_REVENGE, monsterInfo = "暴怒史莱姆王 Lv45", bg = "image/bg_slime_kingdom.png" },
      }},
    -- 迪哈塔大反击（圆形按钮入口，慈爱平原右上方）
    { id = "dihata_revenge", name = "是迪哈塔不是迪卡塔！", circleBtn = true,
      tx = 0.58, ty = 0.38,
      color = {200, 140, 40}, desc = "哥布林英雄迪哈塔的挑战！",
      level = "Lv.65", bg = "image/bg_goblin_arena.png",
      stages = {
          { name = "迎战！", type = "battle", stageIndex = GS.STAGE_DIHATA_REVENGE, monsterInfo = "哥布林英雄迪哈塔 Lv65", bg = "image/bg_goblin_arena.png" },
      }},
    -- 无限塔（圆形按钮入口，完成灰界旅行六后解锁）
    { id = "tower", name = "无限塔", circleBtn = true,
      tx = 0.133, ty = 0.42,
      color = {60, 120, 200}, desc = "封印于灰山之巅的无尽试炼",
      level = "Lv.???", bg = "image/cg_infinite_tower.png",
      unlockQuest = "main_eliya_travel_6",
      stages = {
          { name = "第一层", type = "battle", stageIndex = GS.STAGE_TOWER_1, monsterInfo = "守门人 Lv110", bg = "image/cg_infinite_tower.png" },
      }},
}

-- 根据关卡怪物等级计算解锁所需击杀数
local function getStageRequiredKills(stg)
    local lvNum = tonumber(string.match(stg.monsterInfo or "", "Lv(%d+)"))
    if not lvNum then return 100 end
    if lvNum < 10 then return 30
    elseif lvNum < 20 then return 50
    else return 100 end
end

-- 判断 displayEntries 中第 k 个关卡是否锁定（第 1 个始终解锁）
local function isStageLocked(displayEntries, k)
    if k <= 1 then return false end
    local curStg = displayEntries[k].stg

    -- 副本区：需要接取对应灰界大扫除任务解锁（旧存档已通关的保持解锁，等级兜底）
    if curStg.zone == "dungeon" and curStg.unlockQuest then
        -- 旧存档兼容：已通关过该副本 → 直接解锁
        if curStg.dungeonId and GS.dungeonsCleared and GS.dungeonsCleared[curStg.dungeonId] then
            return false
        end
        -- 检查对应任务是否已接取（active/ready/completed 均视为已接取）
        local QM = require("QuestManager")
        local st = QM.questStates[curStg.unlockQuest]
        if st and (st.status == QM.STATUS_ACTIVE or st.status == QM.STATUS_READY or st.status == QM.STATUS_COMPLETED) then
            return false
        end
        -- 等级兜底：冒险者等级达标必然解锁
        if curStg.unlockRank and (GS.adventurerRank or 1) >= curStg.unlockRank then
            return false
        end
        return true  -- 未满足任何条件 → 锁定
    end

    -- 采集区：按同 gatherType 链独立解锁，条件为前一关清空一次
    if curStg.zone == "gather" and curStg.gatherType then
        local gt = curStg.gatherType
        for prev = k - 1, 1, -1 do
            local prevStg = displayEntries[prev].stg
            if prevStg.zone == "gather" and prevStg.gatherType == gt and prevStg.stageIndex then
                -- 前一关未清空过 → 当前关锁定
                if not GS.stageClearedOnce[prevStg.stageIndex] then return true end
                return false  -- 前一关已清空，当前关解锁
            end
        end
        return false  -- 同类型没有前置关卡，默认解锁（第一关）
    end

    -- 非采集区：原逻辑（击杀数解锁）
    for prev = k - 1, 1, -1 do
        local prevStg = displayEntries[prev].stg
        if prevStg.type == "battle" and prevStg.stageIndex then
            local required = getStageRequiredKills(prevStg)
            local kills = GS.stageKillCounts[prevStg.stageIndex] or 0
            if kills < required then return true end
            return false
        end
    end
    return false
end

-- 获取锁定关卡的进度信息（返回 kills, required 或 cleared, total）
local function getStageLockProgress(displayEntries, k)
    local curStg = displayEntries[k].stg

    -- 副本区：任务解锁，返回 0, 0 表示无进度（由渲染侧显示文字提示）
    if curStg.zone == "dungeon" and curStg.unlockQuest then
        return 0, 0
    end

    -- 采集区：返回前一关是否清空（0或1 / 1）
    if curStg.zone == "gather" and curStg.gatherType then
        local gt = curStg.gatherType
        for prev = k - 1, 1, -1 do
            local prevStg = displayEntries[prev].stg
            if prevStg.zone == "gather" and prevStg.gatherType == gt and prevStg.stageIndex then
                local cleared = GS.stageClearedOnce[prevStg.stageIndex] and 1 or 0
                return cleared, 1
            end
        end
        return 0, 1
    end

    -- 非采集区：原逻辑
    for prev = k - 1, 1, -1 do
        local prevStg = displayEntries[prev].stg
        if prevStg.type == "battle" and prevStg.stageIndex then
            local required = getStageRequiredKills(prevStg)
            local kills = math.min(GS.stageKillCounts[prevStg.stageIndex] or 0, required)
            return kills, required
        end
    end
    return 0, 100
end

function M.drawMapPanel(cx, cy, cw, ch, cr)
    local vg = M.vg
    cr = cr or 0

    GS.mapBtnRects = {}

    -- 计算地图图片绘制尺寸，判断是否需要滚动
    local mapImgScale = cw / 2048
    local mapDrawH = 2048 * mapImgScale  -- 地图图片按宽度铺满后的实际绘制高度
    local mapMaxScroll = math.max(0, mapDrawH - ch)
    GS.mapScrollY = math.max(0, math.min(mapMaxScroll, GS.mapScrollY or 0))
    GS.mapClipRect = { x = cx, y = cy, w = cw, h = ch, mapDrawH = mapDrawH }

    -- 使用地图自己的裁剪区域（与外层 scissor 取交集，防止动画滑出时超出面板）
    nvgSave(vg)
    nvgIntersectScissor(vg, cx, cy, cw, ch + 2)

    -- 四角圆角矩形路径
    local function mapRect()
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cy, cw, ch, cr)
    end

    -- 底色填充（与地图羊皮纸边缘融合）
    mapRect()
    nvgFillColor(vg, nvgRGBA(195, 175, 140, 255))
    nvgFill(vg)

    -- 绘制世界地图图片（宽度铺满，竖屏可滚动）
    local mapImg = M.worldMapImg
    local drawX, drawY, scale = cx, cy, 1
    if mapImg and mapImg ~= 0 and mapImg ~= -1 then
        local imgW, imgH = 2048, 2048
        scale = cw / imgW
        local drawW = imgW * scale
        local drawH = imgH * scale
        drawX = cx
        drawY = cy - GS.mapScrollY  -- 应用滚动偏移

        local pat = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, mapImg, 1.0)
        mapRect()
        nvgFillPaint(vg, pat)
        nvgFill(vg)
    end

    -- 绘制地点高亮（覆盖在原图装饰文字上）
    local RANK_LETTERS = { "F", "E", "D", "C", "B", "A", "S", "G" }
    local imgSize = 2048
    for i, loc in ipairs(M.MAP_LOCATIONS) do
        if loc.circleBtn then goto continue_map_loc end
        -- 文字区域的屏幕坐标
        local tcx = drawX + loc.tx * imgSize * scale
        local tcy = drawY + loc.ty * imgSize * scale
        local tw  = loc.tw * imgSize * scale
        local th  = loc.th * imgSize * scale
        local tx  = tcx - tw / 2
        local ty  = tcy - th / 2

        -- 跳过不在可见区域内的地点
        if tcy + th / 2 >= cy and tcy - th / 2 <= cy + ch then
            local r, g, b = loc.color[1], loc.color[2], loc.color[3]
            local isLocked = (GS.adventurerRank or 1) < (loc.requiredRank or 1)
            local isSelected = (not isLocked) and (GS.selectedMapLocation == loc.id)
            local pad = th * 0.3  -- 高亮区域比文字稍大一圈
            local glowR = math.max(4, th * 0.25)

            -- 渐变内容底板（四周渐变为透明，与地图融合）
            local bx = tx - pad * 1.5
            local by = ty - pad
            local bw = tw + pad * 3
            local bh = th + pad * 2
            local bgAlpha = isSelected and 180 or (isLocked and 50 or 100)
            local feather = math.max(bw, bh) * 0.4
            local bgPaint = nvgBoxGradient(vg, bx + feather * 0.3, by + feather * 0.3,
                bw - feather * 0.6, bh - feather * 0.6, bh * 0.2, feather,
                nvgRGBA(255, 255, 255, bgAlpha), nvgRGBA(255, 255, 255, 0))
            nvgBeginPath(vg)
            nvgRect(vg, bx - feather, by - feather, bw + feather * 2, bh + feather * 2)
            nvgFillPaint(vg, bgPaint)
            nvgFill(vg)
            -- 底部金色线条
            local lineY = ty + th + pad * 0.3
            nvgBeginPath(vg)
            nvgMoveTo(vg, tx, lineY)
            nvgLineTo(vg, tx + tw, lineY)
            if isLocked then
                nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 100))
            else
                nvgStrokeColor(vg, nvgRGBA(210, 180, 100, isSelected and 220 or 150))
            end
            nvgStrokeWidth(vg, isSelected and 2.5 or 1.5)
            nvgStroke(vg)

            if isLocked then
                -- 锁定地点：叠加暗色遮罩
                local darkPaint = nvgBoxGradient(vg, bx + feather * 0.3, by + feather * 0.3,
                    bw - feather * 0.6, bh - feather * 0.6, bh * 0.2, feather,
                    nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
                nvgBeginPath(vg)
                nvgRect(vg, bx - feather, by - feather, bw + feather * 2, bh + feather * 2)
                nvgFillPaint(vg, darkPaint)
                nvgFill(vg)
                -- 显示所需等级提示
                local reqLetter = RANK_LETTERS[loc.requiredRank] or "?"
                local lockText = "需要冒险者" .. reqLetter .. "级"
                nvgFontFace(vg, "sans")
                local lockFontSize = math.max(10, th * 0.45)
                nvgFontSize(vg, lockFontSize)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                -- 文字阴影
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
                nvgText(vg, tcx + 1, lineY + pad * 0.3 + 1, lockText, nil)
                -- 文字本体
                nvgFillColor(vg, nvgRGBA(200, 160, 80, 220))
                nvgText(vg, tcx, lineY + pad * 0.3, lockText, nil)
            elseif isSelected then
                -- 外层大范围柔光
                local glow1 = nvgBoxGradient(vg, bx - feather * 0.2, by - feather * 0.2,
                    bw + feather * 0.4, bh + feather * 0.4, bh * 0.3, feather * 1.5,
                    nvgRGBA(255, 255, 255, 25), nvgRGBA(255, 255, 255, 0))
                nvgBeginPath(vg)
                nvgRect(vg, bx - feather * 2, by - feather * 2, bw + feather * 4, bh + feather * 4)
                nvgFillPaint(vg, glow1)
                nvgFill(vg)
                -- 中层光晕
                local glow2 = nvgBoxGradient(vg, bx + feather * 0.2, by + feather * 0.2,
                    bw - feather * 0.4, bh - feather * 0.4, bh * 0.2, feather * 0.8,
                    nvgRGBA(255, 255, 255, 45), nvgRGBA(255, 255, 255, 0))
                nvgBeginPath(vg)
                nvgRect(vg, bx - feather, by - feather, bw + feather * 2, bh + feather * 2)
                nvgFillPaint(vg, glow2)
                nvgFill(vg)
                -- 内层亮芯
                local glow3 = nvgBoxGradient(vg, bx + feather * 0.4, by + feather * 0.4,
                    bw - feather * 0.8, bh - feather * 0.8, bh * 0.15, feather * 0.4,
                    nvgRGBA(255, 255, 255, 30), nvgRGBA(255, 255, 255, 0))
                nvgBeginPath(vg)
                nvgRect(vg, bx - feather, by - feather, bw + feather * 2, bh + feather * 2)
                nvgFillPaint(vg, glow3)
                nvgFill(vg)
            end

            -- 记录点击区域（锁定地点不可点击）
            if not isLocked then
                GS.mapBtnRects[#GS.mapBtnRects + 1] = {
                    x = tx - pad, y = ty - pad, w = tw + pad * 2, h = th + pad * 2,
                    locId = loc.id, locName = loc.name, locIndex = i,
                }
            end
        end
        ::continue_map_loc::
    end

    -- 精灵NPC按钮（交谈过后显示在垂雾森林上方）
    GS.mapElfBtnRect = nil
    if GS.elfvahElfTalked then
        local elfImg = M.npcForestElfVisitImg or M.npcForestElfImg
        if elfImg and elfImg ~= 0 and elfImg ~= -1 then
            -- 垂雾森林位置：tx=0.838, ty=0.383
            local elfBtnSize = 18
            local elfCx = drawX + 0.838 * imgSize * scale
            local elfCy = drawY + (0.383 - 0.07) * imgSize * scale - elfBtnSize * 0.5
            local elfX = elfCx - elfBtnSize / 2
            local elfY = elfCy - elfBtnSize / 2

            -- 跳过不在可见区域的按钮
            if elfY + elfBtnSize >= cy and elfY <= cy + ch then
                -- 外圈光晕
                local glowR = elfBtnSize * 0.7
                local glowPaint = nvgRadialGradient(vg,
                    elfCx, elfCy, elfBtnSize * 0.3, glowR,
                    nvgRGBA(100, 200, 120, 60), nvgRGBA(100, 200, 120, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, elfCx, elfCy, glowR)
                nvgFillPaint(vg, glowPaint)
                nvgFill(vg)

                -- 圆形边框
                nvgBeginPath(vg)
                nvgCircle(vg, elfCx, elfCy, elfBtnSize / 2 + 2)
                nvgStrokeColor(vg, nvgRGBA(180, 220, 160, 200))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)

                -- 圆形裁剪绘制头像
                nvgSave(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, elfCx, elfCy, elfBtnSize / 2)
                nvgFillColor(vg, nvgRGBA(30, 50, 30, 200))
                nvgFill(vg)
                local elfPat = nvgImagePattern(vg, elfX, elfY, elfBtnSize, elfBtnSize, 0, elfImg, 1.0)
                nvgBeginPath(vg)
                nvgCircle(vg, elfCx, elfCy, elfBtnSize / 2)
                nvgFillPaint(vg, elfPat)
                nvgFill(vg)
                nvgRestore(vg)

                -- 记录点击区域
                GS.mapElfBtnRect = {
                    x = elfX, y = elfY, w = elfBtnSize, h = elfBtnSize,
                }
            end
        end
    end

    -- ====== 异世深渊方形按钮（完成弑杀红龙的魔女后显示） ======
    GS.mapAbyssBtnRect = nil
    do
        local QM_abyss = require("QuestManager")
        local abyssQuestState = QM_abyss.questStates["side_lina_manor_6"]
        if GS.abyssUnlocked or (abyssQuestState and abyssQuestState.status == QM_abyss.STATUS_COMPLETED) then
            local absBtnSize = 22
            local absCx = drawX + 0.298 * imgSize * scale
            local absCy = drawY + 0.82 * imgSize * scale
            local absX = absCx - absBtnSize / 2
            local absY = absCy - absBtnSize / 2
            local absR = 3  -- 圆角半径

            if absY + absBtnSize >= cy and absY <= cy + ch then
                -- 外圈光晕（红色）
                local glowR = absBtnSize * 0.8
                local glowPaint = nvgRadialGradient(vg,
                    absCx, absCy, absBtnSize * 0.3, glowR,
                    nvgRGBA(200, 50, 50, 50), nvgRGBA(200, 50, 50, 0))
                nvgBeginPath(vg)
                nvgRect(vg, absCx - glowR, absCy - glowR, glowR * 2, glowR * 2)
                nvgFillPaint(vg, glowPaint)
                nvgFill(vg)

                -- 方形底色
                nvgBeginPath(vg)
                nvgRoundedRect(vg, absX, absY, absBtnSize, absBtnSize, absR)
                nvgFillColor(vg, nvgRGBA(30, 8, 8, 230))
                nvgFill(vg)

                -- 背景图
                local abyssImg = M.mapAbyssBg
                if abyssImg and abyssImg > 0 then
                    local ip = 1.5
                    local imgPaint = nvgImagePattern(vg,
                        absX + ip, absY + ip,
                        absBtnSize - ip * 2, absBtnSize - ip * 2,
                        0, abyssImg, 0.85)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, absX + ip, absY + ip, absBtnSize - ip * 2, absBtnSize - ip * 2, absR)
                    nvgFillPaint(vg, imgPaint)
                    nvgFill(vg)
                end

                -- 方形边框（红色描边）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, absX - 1, absY - 1, absBtnSize + 2, absBtnSize + 2, absR + 1)
                nvgStrokeColor(vg, nvgRGBA(220, 80, 80, 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 选中态高亮
                if GS.selectedMapLocation == "abyss" then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, absX - 3, absY - 3, absBtnSize + 6, absBtnSize + 6, absR + 2)
                    nvgStrokeColor(vg, nvgRGBA(255, 140, 140, 180))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end

                GS.mapAbyssBtnRect = {
                    x = absX, y = absY, w = absBtnSize, h = absBtnSize,
                }
            end
        end
    end

    -- ====== 无限塔方形按钮（完成灰界旅行六后显示） ======
    GS.mapTowerBtnRect = nil
    do
        local QM_tower = require("QuestManager")
        local towerQuestState = QM_tower.questStates["main_eliya_travel_6"]
        if GS.infiniteTowerUnlocked or (towerQuestState and towerQuestState.status == QM_tower.STATUS_COMPLETED) then
            local twrBtnSize = 22
            local twrCx = drawX + 0.133 * imgSize * scale
            local twrCy = drawY + 0.42 * imgSize * scale
            local twrX = twrCx - twrBtnSize / 2
            local twrY = twrCy - twrBtnSize / 2
            local twrR = 3  -- 圆角半径

            if twrY + twrBtnSize >= cy and twrY <= cy + ch then
                -- 外圈光晕（蓝色）
                local glowR = twrBtnSize * 0.8
                local glowPaint = nvgRadialGradient(vg,
                    twrCx, twrCy, twrBtnSize * 0.3, glowR,
                    nvgRGBA(50, 100, 220, 50), nvgRGBA(50, 100, 220, 0))
                nvgBeginPath(vg)
                nvgRect(vg, twrCx - glowR, twrCy - glowR, glowR * 2, glowR * 2)
                nvgFillPaint(vg, glowPaint)
                nvgFill(vg)

                -- 方形底色
                nvgBeginPath(vg)
                nvgRoundedRect(vg, twrX, twrY, twrBtnSize, twrBtnSize, twrR)
                nvgFillColor(vg, nvgRGBA(8, 15, 35, 230))
                nvgFill(vg)

                -- 背景图
                local towerImg = M.mapTowerBg
                if towerImg and towerImg > 0 then
                    local ip = 1.5
                    local imgPaint = nvgImagePattern(vg,
                        twrX + ip, twrY + ip,
                        twrBtnSize - ip * 2, twrBtnSize - ip * 2,
                        0, towerImg, 0.85)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, twrX + ip, twrY + ip, twrBtnSize - ip * 2, twrBtnSize - ip * 2, twrR)
                    nvgFillPaint(vg, imgPaint)
                    nvgFill(vg)
                end

                -- 方形边框（蓝色描边）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, twrX - 1, twrY - 1, twrBtnSize + 2, twrBtnSize + 2, twrR + 1)
                nvgStrokeColor(vg, nvgRGBA(80, 140, 240, 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 选中态高亮
                if GS.selectedMapLocation == "tower" then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, twrX - 3, twrY - 3, twrBtnSize + 6, twrBtnSize + 6, twrR + 2)
                    nvgStrokeColor(vg, nvgRGBA(140, 180, 255, 180))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end

                GS.mapTowerBtnRect = {
                    x = twrX, y = twrY, w = twrBtnSize, h = twrBtnSize,
                }
            end
        end
    end

    -- ====== 史莱姆国王大反击 + 迪哈塔大反击 方形按钮（并排居中） ======
    GS.mapSlimeRevengeBtnRect = nil
    GS.mapDihataRevengeBtnRect = nil
    do
        local showSlime  = (GS.adventurerRank or 1) >= 4  -- C级 = 4
        local showDihata = (GS.adventurerRank or 1) >= 5  -- B级 = 5

        if showSlime then
            local btnSize = 22
            local btnGapR = 6  -- 两按钮间距
            local btnR = 3
            -- 基准：慈爱平原中心 tx=0.46 上方
            local anchorCx = drawX + 0.46 * imgSize * scale
            local anchorCy = drawY + 0.44 * imgSize * scale

            -- 计算按钮数量和整体宽度，居中排列
            local btnCount = showDihata and 2 or 1
            local totalW = btnCount * btnSize + (btnCount - 1) * btnGapR
            local startX = anchorCx - totalW / 2

            -- 按钮定义列表：{ id, img, glowColor, borderColor, selectedBorderColor, bgTint }
            local btnDefs = {}
            btnDefs[#btnDefs + 1] = {
                id = "slime_king_revenge",
                img = M.mapSlimeRevengeBg,
                glowR = 255, glowG = 140, glowB = 30,
                borderR = 240, borderG = 100, borderB = 140,
                selBorderR = 240, selBorderG = 120, selBorderB = 160,
                bgR = 35, bgG = 20, bgB = 8,
            }
            if showDihata then
                btnDefs[#btnDefs + 1] = {
                    id = "dihata_revenge",
                    img = M.mapDihataRevengeBg,
                    glowR = 200, glowG = 140, glowB = 40,
                    borderR = 200, borderG = 140, borderB = 40,
                    selBorderR = 220, selBorderG = 160, selBorderB = 60,
                    bgR = 40, bgG = 28, bgB = 8,
                }
            end

            for idx, def in ipairs(btnDefs) do
                local bCx = startX + (idx - 1) * (btnSize + btnGapR) + btnSize / 2
                local bCy = anchorCy
                local bX = bCx - btnSize / 2
                local bY = bCy - btnSize / 2

                if bY + btnSize >= cy and bY <= cy + ch then
                    -- 外圈光晕
                    local glowRadius = btnSize * 0.8
                    local glowPaint = nvgRadialGradient(vg,
                        bCx, bCy, btnSize * 0.3, glowRadius,
                        nvgRGBA(def.glowR, def.glowG, def.glowB, 50),
                        nvgRGBA(def.glowR, def.glowG, def.glowB, 0))
                    nvgBeginPath(vg)
                    nvgRect(vg, bCx - glowRadius, bCy - glowRadius, glowRadius * 2, glowRadius * 2)
                    nvgFillPaint(vg, glowPaint)
                    nvgFill(vg)

                    -- 方形底色
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, bX, bY, btnSize, btnSize, btnR)
                    nvgFillColor(vg, nvgRGBA(def.bgR, def.bgG, def.bgB, 230))
                    nvgFill(vg)

                    -- 背景图（1.5倍放大居中）
                    local bImg = def.img
                    if bImg and bImg > 0 then
                        local ip = 1.5
                        local imgSc = 1.5
                        local imgW = btnSize * imgSc
                        local imgH = btnSize * imgSc
                        local imgPaint = nvgImagePattern(vg,
                            bCx - imgW / 2, bCy - imgH / 2,
                            imgW, imgH,
                            0, bImg, 0.90)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, bX + ip, bY + ip, btnSize - ip * 2, btnSize - ip * 2, btnR)
                        nvgFillPaint(vg, imgPaint)
                        nvgFill(vg)
                    end

                    -- 方形边框
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, bX - 1, bY - 1, btnSize + 2, btnSize + 2, btnR + 1)
                    nvgStrokeColor(vg, nvgRGBA(def.borderR, def.borderG, def.borderB, 220))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)

                    -- 选中态高亮
                    if GS.selectedMapLocation == def.id then
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, bX - 3, bY - 3, btnSize + 6, btnSize + 6, btnR + 2)
                        nvgStrokeColor(vg, nvgRGBA(def.selBorderR, def.selBorderG, def.selBorderB, 200))
                        nvgStrokeWidth(vg, 2)
                        nvgStroke(vg)
                    end

                    -- 记录点击区域
                    if def.id == "slime_king_revenge" then
                        GS.mapSlimeRevengeBtnRect = { x = bX, y = bY, w = btnSize, h = btnSize }
                    else
                        GS.mapDihataRevengeBtnRect = { x = bX, y = bY, w = btnSize, h = btnSize }
                    end
                end
            end
        end
    end

    -- ====== 旅行任务按钮（艾莉雅 + 安吉莉娅，地图区域名下方的五角星按钮） ======
    GS.mapQuestBtnRects = {}
    do
        local QM = require("QuestManager")
        local activeQuests = QM.getActiveEliyaTravelQuests()
        -- 合并安吉莉娅旅行任务
        local angelicaQuests = QM.getActiveAngelicaTravelQuests()
        for _, aq in ipairs(angelicaQuests) do
            activeQuests[#activeQuests + 1] = aq
        end
        -- 合并迪芬旅行任务
        local difenQuests = QM.getActiveDifenTravelQuests()
        for _, dq in ipairs(difenQuests) do
            activeQuests[#activeQuests + 1] = dq
        end

        -- 按地图区域分组，同一地点的任务排在一起
        local locGroups = {}  -- locId → { {q, loc}, ... }
        for _, q in ipairs(activeQuests) do
            for _, loc in ipairs(M.MAP_LOCATIONS) do
                if loc.id == q.areaId then
                    local isLocked = (GS.adventurerRank or 1) < (loc.requiredRank or 1)
                    if not isLocked then
                        if not locGroups[loc.id] then locGroups[loc.id] = {} end
                        locGroups[loc.id][#locGroups[loc.id] + 1] = { q = q, loc = loc }
                    end
                    break
                end
            end
        end

        local qBtnSize = 16
        local qBtnGap = 4  -- 同一地点多个按钮的间距

        for _, group in pairs(locGroups) do
            local loc = group[1].loc
            local tcx = drawX + loc.tx * imgSize * scale
            local tcy = drawY + loc.ty * imgSize * scale
            local th  = loc.th * imgSize * scale
            local pad2 = th * 0.3
            local lineY = tcy + th / 2 + pad2 * 0.3
            local qBtnY = lineY + 3

            -- 计算整组的总宽度，使其居中于 tcx
            local count = #group
            local totalW = count * qBtnSize + (count - 1) * qBtnGap
            local startX = tcx - totalW / 2

            for gi, entry in ipairs(group) do
                local q = entry.q
                local qBtnX = startX + (gi - 1) * (qBtnSize + qBtnGap)
                local qBtnCx = qBtnX + qBtnSize / 2
                local qBtnCy = qBtnY + qBtnSize / 2

                if qBtnY + qBtnSize >= cy and qBtnY <= cy + ch then
                    -- 外圈金色光晕
                    local glowR2 = qBtnSize * 0.8
                    local gPaint = nvgRadialGradient(vg,
                        qBtnCx, qBtnCy, qBtnSize * 0.3, glowR2,
                        nvgRGBA(230, 195, 60, 50), nvgRGBA(230, 195, 60, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, qBtnCx, qBtnCy, glowR2)
                    nvgFillPaint(vg, gPaint)
                    nvgFill(vg)

                    -- 方形背景（深色底板）
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, qBtnX, qBtnY, qBtnSize, qBtnSize, 3)
                    nvgFillColor(vg, nvgRGBA(40, 32, 15, 200))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(230, 195, 60, 180))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)

                    -- 五角星（主线金色）
                    local starR = qBtnSize * 0.33
                    local starInner = starR * 0.4
                    nvgBeginPath(vg)
                    for si = 0, 9 do
                        local angle = -math.pi / 2 + si * math.pi / 5
                        local r2 = (si % 2 == 0) and starR or starInner
                        local sx = qBtnCx + math.cos(angle) * r2
                        local sy = qBtnCy + math.sin(angle) * r2
                        if si == 0 then
                            nvgMoveTo(vg, sx, sy)
                        else
                            nvgLineTo(vg, sx, sy)
                        end
                    end
                    nvgClosePath(vg)
                    local starPaint = nvgLinearGradient(vg, qBtnCx, qBtnCy - starR, qBtnCx, qBtnCy + starR,
                        nvgRGBA(255, 225, 80, 255), nvgRGBA(190, 140, 20, 255))
                    nvgFillPaint(vg, starPaint)
                    nvgFill(vg)

                    -- 记录点击区域
                    GS.mapQuestBtnRects[#GS.mapQuestBtnRects + 1] = {
                        x = qBtnX - 4, y = qBtnY - 4,
                        w = qBtnSize + 8, h = qBtnSize + 8,
                        questId   = q.questId,
                        questName = q.questName,
                        areaId    = q.areaId,
                        areaName  = q.areaName,
                        dialogue  = q.dialogue,
                        locId     = loc.id,
                        locName   = loc.name,
                    }
                end
            end
        end
    end

    -- 关卡列表 + "前往"按钮（选中地点且有关卡时显示）
    GS.mapGoButtonRect = nil
    GS.mapCancelButtonRect = nil
    GS.mapStageBtnRects = {}
    local selectedLoc = nil
    local questStageOverride = nil  -- 任务关卡覆盖模式
    if GS.mapQuestStageMode then
        -- 艾莉雅旅行任务模式：构造虚拟 selectedLoc
        local qm = GS.mapQuestStageMode
        for _, loc in ipairs(M.MAP_LOCATIONS) do
            if loc.id == qm.locId then selectedLoc = loc break end
        end
        if selectedLoc then
            questStageOverride = {
                questId   = qm.questId,
                questName = qm.questName,
                areaName  = qm.areaName,
                dialogue  = qm.dialogue,
                locName   = qm.locName,
                locId     = qm.locId,
                bg        = selectedLoc.bg or "image/bg_grass.png",
            }
        end
    elseif GS.selectedMapLocation then
        for _, loc in ipairs(M.MAP_LOCATIONS) do
            if loc.id == GS.selectedMapLocation then selectedLoc = loc break end
        end
    end

    if questStageOverride or (selectedLoc and selectedLoc.stages and #selectedLoc.stages > 0) then
        local stages = questStageOverride and {} or selectedLoc.stages
        local panelPad = 10
        local panelMargin = 6
        local panelR = 6

        -- 面板占据地图右半部分，上下留对称边距，底部多留空间
        local panelW = cw * 0.5 - panelMargin
        local panelX = cx + cw - panelW - panelMargin
        local panelY = cy + panelMargin
        local bottomMargin = panelMargin + ch * 0.03
        local panelH = ch - panelMargin - bottomMargin

        -- ====== 分区分组计算 ======
        local zoneGroups = { gather = {}, battle = {}, dungeon = {} }
        for i, stg in ipairs(stages) do
            local z = stg.zone or "battle"
            zoneGroups[z][#zoneGroups[z] + 1] = { idx = i, stg = stg }
        end
        -- 计算有内容的分区数
        local nonEmptyZones = {}
        for _, zId in ipairs(GS.MAP_ZONE_ORDER) do
            if #zoneGroups[zId] > 0 then
                nonEmptyZones[#nonEmptyZones + 1] = zId
            end
        end
        local showZoneTabs = (#nonEmptyZones >= 2) and (selectedLoc.id ~= "clearwater")

        -- 任务关卡覆盖：跳过分区标签，只显示一个"任务关卡"
        if questStageOverride then
            showZoneTabs = false
        end

        -- 确保当前分区有效
        local activeZone = GS.mapStageZone or "battle"
        if not zoneGroups[activeZone] or #zoneGroups[activeZone] == 0 then
            activeZone = nonEmptyZones[1] or "battle"
            GS.mapStageZone = activeZone
        end

        -- 当前分区的过滤列表
        local displayEntries = showZoneTabs and zoneGroups[activeZone] or {}
        if not showZoneTabs then
            -- 不显示标签时使用全部 stages
            displayEntries = {}
            for i, stg in ipairs(stages) do
                displayEntries[#displayEntries + 1] = { idx = i, stg = stg }
            end
        end

        -- 过滤：只保留已解锁的关卡 + 第一个锁定的关卡（正在解锁中）
        -- 采集区按 gatherType 分别追踪首个锁定关
        do
            local filtered = {}
            local foundFirstLocked = false        -- 非采集区用
            local gatherFirstLocked = {}          -- 采集区按 gatherType 追踪
            for k, e in ipairs(displayEntries) do
                local locked = isStageLocked(displayEntries, k)
                if not locked then
                    filtered[#filtered + 1] = e
                else
                    -- 锁定的副本区直接隐藏，不显示
                    if e.stg.zone == "dungeon" and e.stg.unlockQuest then
                        -- skip
                    else
                        -- 锁定关卡：按类型判断是否为该类的首个锁定
                        local gt = e.stg.gatherType
                        if gt then
                            -- 采集区：每个 gatherType 各显示一个锁定关
                            if not gatherFirstLocked[gt] then
                                filtered[#filtered + 1] = e
                                gatherFirstLocked[gt] = true
                            end
                        else
                            -- 非采集区：只显示一个锁定关
                            if not foundFirstLocked then
                                filtered[#filtered + 1] = e
                                foundFirstLocked = true
                            end
                        end
                    end
                end
            end
            displayEntries = filtered
        end

        -- 未购买房屋时隐藏"你的家"
        if not GS.housePurchased then
            local filtered2 = {}
            for _, e in ipairs(displayEntries) do
                if e.stg.type ~= "home" then
                    filtered2[#filtered2 + 1] = e
                end
            end
            displayEntries = filtered2
        end

        -- 任务关卡覆盖：用一个虚拟"任务关卡"条目替换整个列表
        if questStageOverride then
            displayEntries = {
                { idx = 1, stg = {
                    name = questStageOverride.questName or questStageOverride.areaName,
                    type = "quest",
                    questId  = questStageOverride.questId,
                    dialogue = questStageOverride.dialogue,
                    locName  = questStageOverride.locName,
                    locId    = questStageOverride.locId,
                    bg       = questStageOverride.bg,
                } },
            }
            GS.selectedMapStage = 1
        end

        -- 默认选中第一个未锁定的关卡（在过滤列表中）
        if not GS.selectedMapStage then
            for k, e in ipairs(displayEntries) do
                if not isStageLocked(displayEntries, k) then
                    GS.selectedMapStage = e.idx
                    break
                end
            end
        else
            -- 验证当前选中是否在当前分区中且未锁定
            local found = false
            for k, e in ipairs(displayEntries) do
                if e.idx == GS.selectedMapStage then
                    if not isStageLocked(displayEntries, k) then
                        found = true
                    end
                    break
                end
            end
            if not found then
                GS.selectedMapStage = nil
                for k, e in ipairs(displayEntries) do
                    if not isStageLocked(displayEntries, k) then
                        GS.selectedMapStage = e.idx
                        break
                    end
                end
            end
        end

        -- 标题区
        local titleFontSize = math.max(13, panelH * 0.045)
        local titleH = titleFontSize * 2.0

        -- 底部按钮区
        local btnFontSize = math.max(13, panelH * 0.04)
        local btnH = math.max(30, panelH * 0.08)
        local btnGap = 8
        local isSlimeRevenge = (selectedLoc and selectedLoc.id == "slime_king_revenge")
        local isDihataRevenge = (selectedLoc and selectedLoc.id == "dihata_revenge")
        local hasExtraRow = isSlimeRevenge or isDihataRevenge
        local extraBtnRowGap = math.max(10, panelH * 0.025)  -- 两行按钮间自适应间距
        local extraBtnRowH = hasExtraRow and (btnH + extraBtnRowGap) or 0  -- 排名/奖励按钮额外行
        local btnAreaH = btnH + panelPad + extraBtnRowH  -- 底部按钮区总高

        -- 关卡列表区（填充剩余空间）
        local listTopY = panelY + panelPad + titleH + 6
        local listBotY = panelY + panelH - btnAreaH - 6
        local listX = panelX + panelPad
        local listW = panelW - panelPad * 2
        local listAvailH = listBotY - listTopY

        -- 固定条目高度（以7个关卡为基准，保持字体大小一致）
        local itemGap = 3
        local maxVisible = 7  -- 固定最多显示7个
        local maxItemH = math.max(28, panelH * 0.09)
        local itemH = math.min(maxItemH, (listAvailH - itemGap * math.max(0, maxVisible - 1)) / maxVisible)
        local fontSize = math.max(11, itemH * 0.42)

        -- 滚动：使用过滤后的数量
        local filteredCount = #displayEntries
        local needScroll = filteredCount > maxVisible
        local maxScroll = needScroll and (filteredCount - maxVisible) or 0
        local scrollOffset = 0
        if needScroll then
            GS.mapStageScrollOffset = math.max(0, math.min(GS.mapStageScrollOffset, maxScroll))
            scrollOffset = GS.mapStageScrollOffset
        else
            GS.mapStageScrollOffset = 0
        end
        -- 保存列表裁剪区域供输入模块使用
        GS.mapStageListClip = { x = listX, y = listTopY, w = listW, h = listAvailH }

        -- 衬底面板
        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
        nvgFillColor(vg, nvgRGBA(25, 22, 18, 210))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(180, 155, 100, 160))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 标题：地点名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, titleFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(230, 210, 160, 255))
        nvgText(vg, panelX + panelW / 2, panelY + panelPad + titleH / 2, selectedLoc.name, nil)

        -- 标题分隔线
        local sepY = panelY + panelPad + titleH
        nvgBeginPath(vg)
        nvgMoveTo(vg, panelX + panelPad, sepY)
        nvgLineTo(vg, panelX + panelW - panelPad, sepY)
        nvgStrokeColor(vg, nvgRGBA(150, 130, 80, 120))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        -- ====== 分区标签栏 ======
        GS.mapZoneTabRects = {}
        if showZoneTabs then
            local tabBarH = math.max(22, titleFontSize * 1.6)
            local tabY = sepY + 3
            local tabTotalW = listW
            local tabCount = #nonEmptyZones
            local tabW = tabTotalW / tabCount
            local tabFontSize = math.max(10, fontSize * 0.88)

            for ti, zId in ipairs(nonEmptyZones) do
                local zDef = nil
                for _, d in ipairs(GS.MAP_ZONE_DEFS) do
                    if d.id == zId then zDef = d; break end
                end
                if not zDef then goto continueTab end

                local tx = listX + (ti - 1) * tabW
                local isActive = (zId == activeZone)
                local zr, zg, zb = zDef.color[1], zDef.color[2], zDef.color[3]

                -- 标签背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, tx + 1, tabY, tabW - 2, tabBarH - 2, 3)
                if isActive then
                    nvgFillColor(vg, nvgRGBA(zr, zg, zb, 50))
                else
                    nvgFillColor(vg, nvgRGBA(40, 38, 30, 100))
                end
                nvgFill(vg)

                -- 激活指示线
                if isActive then
                    nvgBeginPath(vg)
                    local lineW = tabW * 0.5
                    nvgRect(vg, tx + (tabW - lineW) / 2, tabY + tabBarH - 4, lineW, 2)
                    nvgFillColor(vg, nvgRGBA(zr, zg, zb, 220))
                    nvgFill(vg)
                end

                -- 标签文字
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, tabFontSize)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, isActive
                    and nvgRGBA(zr, zg, zb, 255)
                    or nvgRGBA(160, 150, 130, 180))
                nvgText(vg, tx + tabW / 2, tabY + (tabBarH - 2) / 2, zDef.name, nil)

                -- 记录点击区域
                GS.mapZoneTabRects[#GS.mapZoneTabRects + 1] = {
                    x = tx, y = tabY, w = tabW, h = tabBarH, zoneId = zId,
                }

                ::continueTab::
            end

            -- 调整列表起始位置
            listTopY = listTopY + tabBarH + 2
            listAvailH = listBotY - listTopY
            -- 重算 itemH（可用空间变了）
            itemH = math.min(maxItemH, (listAvailH - itemGap * math.max(0, maxVisible - 1)) / maxVisible)
        end

        -- ====== 任务关卡覆盖：直接显示任务信息，跳过关卡按钮列表 ======
        if questStageOverride then
            local QM = require("QuestManager")
            local qDef = QM.getQuestDef(questStageOverride.questId)
            local questCategory = qDef and qDef.category or "main"
            local questTypeName = (questCategory == QM.CATEGORY_MAIN) and "主线任务" or "支线任务"
            local questTypeColor = (questCategory == QM.CATEGORY_MAIN)
                and nvgRGBA(230, 195, 60, 255)
                or  nvgRGBA(100, 200, 255, 255)
            local questName = questStageOverride.questName or (qDef and qDef.name or "未知任务")
            local questDesc = qDef and qDef.desc or ""

            -- 任务类型（第一行）
            local qtFontSize = math.max(12, panelH * 0.038)
            local qtY = listTopY + qtFontSize * 1.2
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, qtFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, questTypeColor)
            nvgText(vg, panelX + panelW / 2, qtY, questTypeName, nil)

            -- 任务名称（第二行）
            local qnFontSize = math.max(13, panelH * 0.045)
            local qnY = qtY + qtFontSize * 0.6 + qnFontSize * 0.8
            nvgFontSize(vg, qnFontSize)
            nvgFillColor(vg, nvgRGBA(240, 225, 190, 255))
            nvgText(vg, panelX + panelW / 2, qnY, questName, nil)

            -- 分隔线
            local qSepY = qnY + qnFontSize * 0.8
            nvgBeginPath(vg)
            nvgMoveTo(vg, panelX + panelPad + listW * 0.2, qSepY)
            nvgLineTo(vg, panelX + panelW - panelPad - listW * 0.2, qSepY)
            nvgStrokeColor(vg, nvgRGBA(150, 130, 80, 80))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)

            -- 任务描述（多行自动换行）
            local qdFontSize = math.max(11, panelH * 0.034)
            local qdTopY = qSepY + qdFontSize * 0.8
            local qdMaxW = listW - 16
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, qdFontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(190, 180, 160, 220))
            nvgTextBox(vg, listX + 8, qdTopY, qdMaxW, questDesc, nil)

        else -- 普通关卡列表

        -- 关卡列表（带裁剪和滚动）
        nvgSave(vg)
        nvgIntersectScissor(vg, listX, listTopY, listW, listAvailH)

        for vi_raw, entry in ipairs(displayEntries) do
            local i = entry.idx
            local stg = entry.stg
            local vi = vi_raw - scrollOffset  -- 相对可见区域的索引
            local iy = listTopY + (vi - 1) * (itemH + itemGap)

            -- 跳过不可见条目
            if iy + itemH < listTopY or iy > listBotY then
                goto continueStage
            end

            local locked = isStageLocked(displayEntries, vi_raw)
            local comingSoon = not locked and stg.comingSoon
            local isSel = (not locked and not comingSoon) and (GS.selectedMapStage == i)

            -- 条目背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, listX, iy, listW, itemH, 4)
            if locked then
                nvgFillColor(vg, nvgRGBA(30, 28, 25, 180))
            elseif isSel then
                nvgFillColor(vg, stg.dungeon and nvgRGBA(60, 30, 30, 220) or nvgRGBA(60, 55, 40, 220))
            else
                nvgFillColor(vg, nvgRGBA(40, 38, 30, 150))
            end
            nvgFill(vg)

            -- 边框
            if locked then
                nvgStrokeColor(vg, nvgRGBA(80, 75, 65, 120))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)
            elseif stg.dungeon then
                nvgStrokeColor(vg, nvgRGBA(220, 70, 60, isSel and 255 or 180))
                nvgStrokeWidth(vg, isSel and 2.0 or 1.5)
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, listX + 2, iy + 2, listW - 4, itemH - 4, 2.5)
                nvgStrokeColor(vg, nvgRGBA(255, 120, 100, isSel and 100 or 50))
                nvgStrokeWidth(vg, 0.6)
                nvgStroke(vg)
            elseif isSel then
                nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 200))
                nvgStrokeWidth(vg, 1.2)
                nvgStroke(vg)
            end

            -- 关卡名称（左侧）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            if locked then
                nvgFillColor(vg, nvgRGBA(100, 95, 85, 160))
            elseif stg.dungeon then
                nvgFillColor(vg, isSel and nvgRGBA(255, 140, 130, 255) or nvgRGBA(220, 110, 100, 220))
            else
                nvgFillColor(vg, isSel and nvgRGBA(255, 240, 210, 255) or nvgRGBA(200, 190, 170, 200))
            end
            nvgText(vg, listX + 8, iy + itemH / 2, stg.name, nil)

            -- 右侧信息
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, fontSize * 0.82)
            if locked then
                -- 锁定关卡：采集区显示"待深入"，副本区显示"需接取任务"，其他显示解锁百分比
                if stg.gatherType then
                    nvgFillColor(vg, nvgRGBA(180, 140, 60, 200))
                    nvgText(vg, listX + listW - 8, iy + itemH / 2, "待深入", nil)
                elseif stg.zone == "dungeon" and stg.unlockQuest then
                    nvgFillColor(vg, nvgRGBA(180, 140, 60, 200))
                    nvgText(vg, listX + listW - 8, iy + itemH / 2, "需接取任务", nil)
                else
                    local kills, required = getStageLockProgress(displayEntries, vi_raw)
                    local pct = math.floor(kills / required * 100)
                    nvgFillColor(vg, nvgRGBA(180, 140, 60, 200))
                    nvgText(vg, listX + listW - 8, iy + itemH / 2, pct .. "%", nil)
                end
            elseif comingSoon then
                nvgFillColor(vg, nvgRGBA(160, 140, 180, 200))
                nvgText(vg, listX + listW - 8, iy + itemH / 2, "未完待续", nil)
            elseif stg.zone == "gather" then
                -- 采集区：绿色显示等级（取该区域怪物池中最高等级怪物的等级）
                nvgFillColor(vg, nvgRGBA(80, 180, 80, 230))
                local gatherLv = "采集"
                local stageDef = GS.STAGE_DEFS[stg.stageIndex]
                if stageDef and stageDef.monsters then
                    local maxLv = 0
                    for _, m in ipairs(stageDef.monsters) do
                        if m.def and m.def.level and m.def.level > maxLv then
                            maxLv = m.def.level
                        end
                    end
                    if maxLv > 0 then gatherLv = "Lv" .. maxLv end
                end
                nvgText(vg, listX + listW - 8, iy + itemH / 2, gatherLv, nil)
            elseif stg.type == "battle" then
                local lvNum = tonumber(string.match(stg.monsterInfo or "", "Lv(%d+)")) or 0
                local playerLv = (GS.player and GS.player.level) or 1
                if playerLv < lvNum then
                    nvgFillColor(vg, nvgRGBA(220, 80, 60, 230))
                else
                    nvgFillColor(vg, nvgRGBA(80, 200, 80, 230))
                end
                nvgText(vg, listX + listW - 8, iy + itemH / 2, "Lv" .. lvNum, nil)
            elseif stg.type == "home" then
                nvgFillColor(vg, nvgRGBA(200, 170, 100, 220))
                nvgText(vg, listX + listW - 8, iy + itemH / 2, "家", nil)
            elseif stg.type == "quest" then
                nvgFillColor(vg, nvgRGBA(230, 195, 60, 230))
                nvgText(vg, listX + listW - 8, iy + itemH / 2, "主线", nil)
            elseif stg.type == "training" then
                nvgFillColor(vg, nvgRGBA(220, 160, 60, 220))
                nvgText(vg, listX + listW - 8, iy + itemH / 2, "训练", nil)
            else
                nvgFillColor(vg, nvgRGBA(170, 160, 140, 180))
                nvgText(vg, listX + listW - 8, iy + itemH / 2, "城镇", nil)
            end

            -- 记录点击区域（锁定/未完待续关卡不可点击）
            if not locked and not comingSoon then
                GS.mapStageBtnRects[#GS.mapStageBtnRects + 1] = {
                    x = listX, y = iy, w = listW, h = itemH, stageIdx = i,
                }
            end

            ::continueStage::
        end

        nvgRestore(vg)

        -- 滚动提示：底部/顶部渐变遮罩 + 箭头
        if needScroll then
            local fadeH = itemH * 0.7
            local arrowSize = math.max(6, fontSize * 0.35)
            -- 最后一个可见关卡的底边Y
            local lastItemBotY = listTopY + (maxVisible - 1) * (itemH + itemGap) + itemH

            -- 底部：还能向下滚动时显示
            if scrollOffset < maxScroll then
                -- 渐变遮罩（从透明到面板背景色）
                local botFadeY = lastItemBotY - fadeH
                local paint = nvgLinearGradient(vg, 0, botFadeY, 0, lastItemBotY,
                    nvgRGBA(25, 22, 18, 0), nvgRGBA(25, 22, 18, 220))
                nvgBeginPath(vg)
                nvgRect(vg, listX, botFadeY, listW, fadeH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
                -- 向下箭头 ▼（中心对齐最后一个关卡底边）
                local arrowCX = listX + listW / 2
                local arrowCY = lastItemBotY
                nvgBeginPath(vg)
                nvgMoveTo(vg, arrowCX - arrowSize, arrowCY - arrowSize * 0.5)
                nvgLineTo(vg, arrowCX + arrowSize, arrowCY - arrowSize * 0.5)
                nvgLineTo(vg, arrowCX, arrowCY + arrowSize * 0.5)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(220, 200, 150, 180))
                nvgFill(vg)
            end

            -- 顶部：已经向下滚动时显示
            if scrollOffset > 0 then
                local topFadeY = listTopY
                local paint = nvgLinearGradient(vg, 0, topFadeY + fadeH, 0, topFadeY,
                    nvgRGBA(25, 22, 18, 0), nvgRGBA(25, 22, 18, 220))
                nvgBeginPath(vg)
                nvgRect(vg, listX, topFadeY, listW, fadeH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
                -- 向上箭头 ▲（中心对齐第一个关卡上边）
                local arrowCX = listX + listW / 2
                local arrowCY = listTopY
                nvgBeginPath(vg)
                nvgMoveTo(vg, arrowCX - arrowSize, arrowCY + arrowSize * 0.5)
                nvgLineTo(vg, arrowCX + arrowSize, arrowCY + arrowSize * 0.5)
                nvgLineTo(vg, arrowCX, arrowCY - arrowSize * 0.5)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(220, 200, 150, 180))
                nvgFill(vg)
            end
        end

        -- 滚动条（右侧竖条）
        GS.mapStageScrollbarRect = nil
        GS.mapStageScrollMaxOffset = 0
        if needScroll then
            GS.mapStageScrollMaxOffset = maxScroll
            local sbW = 4       -- 滚动条宽度
            local sbMargin = 6  -- 列表右边外侧间距
            local sbX = listX + listW + sbMargin
            local sbTrackH = listAvailH

            -- 轨道背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sbX, listTopY, sbW, sbTrackH, 2)
            nvgFillColor(vg, nvgRGBA(80, 70, 55, 100))
            nvgFill(vg)

            -- 滑块
            local thumbRatio = maxVisible / filteredCount
            local thumbH = math.max(20, sbTrackH * thumbRatio)
            local scrollRange = sbTrackH - thumbH
            local thumbY = listTopY + (maxScroll > 0 and (scrollOffset / maxScroll * scrollRange) or 0)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, sbX, thumbY, sbW, thumbH, 2)
            if GS.mapStageScrollbarDragging then
                nvgFillColor(vg, nvgRGBA(230, 210, 140, 240))
            else
                nvgFillColor(vg, nvgRGBA(180, 160, 110, 200))
            end
            nvgFill(vg)

            -- 保存滚动条区域供输入使用（扩大触摸区域）
            local touchPad = 12
            GS.mapStageScrollbarRect = {
                x = sbX - touchPad, y = listTopY, w = sbW + touchPad * 2, h = sbTrackH,
                thumbH = thumbH, scrollRange = scrollRange,
            }
        end

        end -- if questStageOverride then ... else ... end

        -- ===== 史莱姆国王大反击：懒加载历史最高伤害 =====
        if isSlimeRevenge and not GS._slimeRevengeBestLoaded and not GS._slimeRevengeBestLoading then
            if clientCloud then
                GS._slimeRevengeBestLoading = true
                clientCloud:Get("slime_revenge_best", {
                    ok = function(values, iscores)
                        GS._slimeRevengeBestLoading = false
                        GS._slimeRevengeBestLoaded = true
                        local v = iscores and iscores.slime_revenge_best
                        if v and v > 0 then
                            GS.slimeRevengeBestDmg = v
                        end
                        print("[大反击] 历史最高伤害已加载: " .. tostring(v))
                    end,
                    error = function(code, reason)
                        GS._slimeRevengeBestLoading = false
                        GS._slimeRevengeBestLoaded = true  -- 失败也标记已加载，避免反复请求
                        print("[大反击] 加载最高伤害失败: " .. tostring(code) .. " " .. tostring(reason))
                    end,
                })
            else
                GS._slimeRevengeBestLoaded = true
            end
        end

        -- ===== 史莱姆国王大反击：剧情提示 + 历史最高伤害（列表空白区域） =====
        if isSlimeRevenge then
            -- 计算列表中第一个条目底部到列表底部之间的空白区域
            local firstItemBot = listTopY + itemH + itemGap
            local centerX = panelX + panelW / 2

            -- 红色剧情提示文本（迎战按钮下方）
            local hintFontSize = math.max(11, panelH * 0.028)
            local hintY = firstItemBot + hintFontSize * 1.2
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, hintFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 80, 60, 210))
            nvgText(vg, centerX, hintY, "上次的事它们好像很不服……", nil)

            -- 历史最高伤害（在提示文本下方居中）
            local hintBot = hintY + hintFontSize * 1.4
            local emptyMidY = (hintBot + listBotY) / 2  -- 剩余空白区域的垂直中心
            local labelFontSize = math.max(13, panelH * 0.035)
            local valueFontSize = math.max(15, panelH * 0.045)
            local lineGap = math.max(6, panelH * 0.012)

            -- 第一行：标签 "历史最高伤害"
            local line1Y = emptyMidY - lineGap / 2 - valueFontSize * 0.3
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, labelFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(220, 215, 210, 200))
            nvgText(vg, centerX, line1Y, "历史最高伤害", nil)

            -- 第二行：数值 / 状态
            local line2Y = emptyMidY + lineGap / 2 + labelFontSize * 0.3
            nvgFontSize(vg, valueFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            if GS._slimeRevengeBestLoading then
                nvgFillColor(vg, nvgRGBA(200, 195, 190, 160))
                nvgText(vg, centerX, line2Y, "加载中...", nil)
            else
                local best = math.max(GS.slimeRevengeBestDmg or 0, GS.slimeRevengeAccDmg or 0)
                if best > 0 then
                    -- 千分位格式化
                    local s = tostring(best)
                    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                    nvgText(vg, centerX, line2Y, formatted, nil)
                else
                    nvgFillColor(vg, nvgRGBA(200, 195, 190, 180))
                    nvgText(vg, centerX, line2Y, "暂无记录", nil)
                end
            end
        end

        -- ===== 迪哈塔大反击：懒加载历史最高伤害 =====
        if isDihataRevenge and not GS._dihataRevengeBestLoaded and not GS._dihataRevengeBestLoading then
            if clientCloud then
                GS._dihataRevengeBestLoading = true
                clientCloud:Get("dihata_revenge_best", {
                    ok = function(values, iscores)
                        GS._dihataRevengeBestLoading = false
                        GS._dihataRevengeBestLoaded = true
                        local v = iscores and iscores.dihata_revenge_best
                        if v and v > 0 then
                            GS.dihataRevengeBestDmg = v
                        end
                        print("[迪哈塔大反击] 历史最高伤害已加载: " .. tostring(v))
                    end,
                    error = function(code, reason)
                        GS._dihataRevengeBestLoading = false
                        GS._dihataRevengeBestLoaded = true
                        print("[迪哈塔大反击] 加载最高伤害失败: " .. tostring(code) .. " " .. tostring(reason))
                    end,
                })
            else
                GS._dihataRevengeBestLoaded = true
            end
        end

        -- ===== 迪哈塔大反击：剧情提示 + 历史最高伤害（列表空白区域） =====
        if isDihataRevenge then
            local firstItemBot = listTopY + itemH + itemGap
            local centerX = panelX + panelW / 2

            local hintFontSize = math.max(11, panelH * 0.028)
            local hintY = firstItemBot + hintFontSize * 1.2
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, hintFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 160, 40, 210))
            nvgText(vg, centerX, hintY, "迪卡塔的弟弟正在寻仇……", nil)

            local hintBot = hintY + hintFontSize * 1.4
            local emptyMidY = (hintBot + listBotY) / 2
            local labelFontSize = math.max(13, panelH * 0.035)
            local valueFontSize = math.max(15, panelH * 0.045)
            local lineGap = math.max(6, panelH * 0.012)

            local line1Y = emptyMidY - lineGap / 2 - valueFontSize * 0.3
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, labelFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(220, 215, 210, 200))
            nvgText(vg, centerX, line1Y, "历史最高伤害", nil)

            local line2Y = emptyMidY + lineGap / 2 + labelFontSize * 0.3
            nvgFontSize(vg, valueFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            if GS._dihataRevengeBestLoading then
                nvgFillColor(vg, nvgRGBA(200, 195, 190, 160))
                nvgText(vg, centerX, line2Y, "加载中...", nil)
            else
                local best = math.max(GS.dihataRevengeBestDmg or 0, GS.dihataRevengeAccDmg or 0)
                if best > 0 then
                    local s = tostring(best)
                    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                    nvgText(vg, centerX, line2Y, formatted, nil)
                else
                    nvgFillColor(vg, nvgRGBA(200, 195, 190, 180))
                    nvgText(vg, centerX, line2Y, "暂无记录", nil)
                end
            end
        end

        -- ===== 史莱姆国王大反击：排名/奖励按钮 =====
        local bottomExtraY = panelY + panelH - panelPad - btnH  -- 取消/前往按钮的Y（最底部）
        if isSlimeRevenge then
            -- 清除迪哈塔的按钮 rect（防止残留导致点击错乱）
            GS.mapDihataRevengeRankBtnRect = nil
            GS.mapDihataRevengeRewardBtnRect = nil
            -- 排名 + 奖励按钮（在取消/前往上方一行，间距自适应）
            local extraBtnY = bottomExtraY - extraBtnRowGap - btnH
            local extraHalfW = (listW - btnGap) / 2

            -- 排名按钮
            local rankX = listX
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rankX, extraBtnY, extraHalfW, btnH, 4)
            nvgFillColor(vg, nvgRGBA(50, 60, 80, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 140, 200, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, btnFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 200, 255, 255))
            nvgText(vg, rankX + extraHalfW / 2, extraBtnY + btnH / 2, "排名", nil)
            GS.mapSlimeRevengeRankBtnRect = {
                x = rankX, y = extraBtnY, w = extraHalfW, h = btnH,
            }

            -- 奖励按钮
            local rewardX = listX + extraHalfW + btnGap
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rewardX, extraBtnY, extraHalfW, btnH, 4)
            nvgFillColor(vg, nvgRGBA(70, 55, 30, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, btnFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
            nvgText(vg, rewardX + extraHalfW / 2, extraBtnY + btnH / 2, "奖励", nil)
            GS.mapSlimeRevengeRewardBtnRect = {
                x = rewardX, y = extraBtnY, w = extraHalfW, h = btnH,
            }
        elseif isDihataRevenge then
            -- 清除史莱姆的按钮 rect（防止残留导致点击错乱）
            GS.mapSlimeRevengeRankBtnRect = nil
            GS.mapSlimeRevengeRewardBtnRect = nil
            -- ===== 迪哈塔大反击：排名/奖励按钮 =====
            local extraBtnY = bottomExtraY - extraBtnRowGap - btnH
            local extraHalfW = (listW - btnGap) / 2

            -- 排名按钮
            local rankX = listX
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rankX, extraBtnY, extraHalfW, btnH, 4)
            nvgFillColor(vg, nvgRGBA(50, 60, 80, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 140, 200, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, btnFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 200, 255, 255))
            nvgText(vg, rankX + extraHalfW / 2, extraBtnY + btnH / 2, "排名", nil)
            GS.mapDihataRevengeRankBtnRect = {
                x = rankX, y = extraBtnY, w = extraHalfW, h = btnH,
            }

            -- 奖励按钮
            local rewardX = listX + extraHalfW + btnGap
            nvgBeginPath(vg)
            nvgRoundedRect(vg, rewardX, extraBtnY, extraHalfW, btnH, 4)
            nvgFillColor(vg, nvgRGBA(70, 55, 30, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, btnFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
            nvgText(vg, rewardX + extraHalfW / 2, extraBtnY + btnH / 2, "奖励", nil)
            GS.mapDihataRevengeRewardBtnRect = {
                x = rewardX, y = extraBtnY, w = extraHalfW, h = btnH,
            }
        else
            GS.mapSlimeRevengeRankBtnRect = nil
            GS.mapSlimeRevengeRewardBtnRect = nil
            GS.mapDihataRevengeRankBtnRect = nil
            GS.mapDihataRevengeRewardBtnRect = nil
        end

        -- 底部按钮区：取消 + 前往，并列
        local btnAreaY = bottomExtraY
        local halfBtnW = (listW - btnGap) / 2

        -- 取消按钮
        local cancelX = listX
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnAreaY, halfBtnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(60, 55, 50, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(150, 140, 120, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, btnFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 190, 170, 255))
        nvgText(vg, cancelX + halfBtnW / 2, btnAreaY + btnH / 2, "取消", nil)

        GS.mapCancelButtonRect = {
            x = cancelX, y = btnAreaY, w = halfBtnW, h = btnH,
        }

        -- 前往按钮（深渊区 / 异世深渊 特殊样式）
        local goX = listX + halfBtnW + btnGap
        local isDungeonZone = (activeZone == "dungeon")
        local isAbyssZone = (selectedLoc and selectedLoc.id == "abyss")
        local abyssRemain = isDungeonZone and GS.getAbyssChallengeRemain() or 0
        local abyssWorldRemain = isAbyssZone and GS.getAbyssWorldRemain() or 0

        nvgBeginPath(vg)
        nvgRoundedRect(vg, goX, btnAreaY, halfBtnW, btnH, 4)
        if isDungeonZone then
            nvgFillColor(vg, nvgRGBA(160, 40, 40, 220))
        elseif isAbyssZone then
            nvgFillColor(vg, nvgRGBA(160, 40, 40, 220))
        else
            nvgFillColor(vg, nvgRGBA(140, 110, 50, 200))
        end
        nvgFill(vg)
        if isDungeonZone then
            nvgStrokeColor(vg, nvgRGBA(220, 80, 70, 230))
        elseif isAbyssZone then
            nvgStrokeColor(vg, nvgRGBA(220, 80, 70, 230))
        else
            nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 220))
        end
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isDungeonZone then
            -- 第一行："开启"
            local line1Size = math.max(11, btnFontSize * 0.9)
            local line1Y = btnAreaY + btnH * 0.35
            nvgFontSize(vg, line1Size)
            nvgFillColor(vg, nvgRGBA(255, 230, 220, 255))
            nvgText(vg, goX + halfBtnW / 2, line1Y, "开启", nil)
            -- 第二行：三种状态
            local line2Size = math.max(9, btnFontSize * 0.65)
            local line2Y = btnAreaY + btnH * 0.7
            nvgFontSize(vg, line2Size)
            if abyssRemain > 0 then
                -- 状态1：有剩余次数 → "剩余：1次"（数字绿色）
                local prefix = "剩余："
                local numStr = tostring(abyssRemain) .. "次"
                local prefixW = nvgTextBounds(vg, 0, 0, prefix, nil)
                local numW = nvgTextBounds(vg, 0, 0, numStr, nil)
                local startX = goX + halfBtnW / 2 - (prefixW + numW) / 2
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 190, 180, 220))
                nvgText(vg, startX, line2Y, prefix, nil)
                nvgFillColor(vg, nvgRGBA(100, 230, 100, 255))
                nvgText(vg, startX + prefixW, line2Y, numStr, nil)
            elseif GS.hasDivineKey() then
                -- 状态2：无次数但有神之匙 → 绿色"使用神之匙"
                nvgFillColor(vg, nvgRGBA(100, 230, 100, 255))
                nvgText(vg, goX + halfBtnW / 2, line2Y, "使用神之匙", nil)
            else
                -- 状态3：无次数也无钥匙 → "剩余：0次"（灰白色）
                local prefix = "剩余："
                local numStr = "0次"
                local prefixW = nvgTextBounds(vg, 0, 0, prefix, nil)
                local numW = nvgTextBounds(vg, 0, 0, numStr, nil)
                local startX = goX + halfBtnW / 2 - (prefixW + numW) / 2
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 190, 180, 220))
                nvgText(vg, startX, line2Y, prefix, nil)
                nvgFillColor(vg, nvgRGBA(180, 170, 160, 200))
                nvgText(vg, startX + prefixW, line2Y, numStr, nil)
            end
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        elseif isAbyssZone then
            -- 异世深渊：紫色"开启"按钮 + 剩余次数/看广告
            local line1Size = math.max(11, btnFontSize * 0.9)
            local line1Y = btnAreaY + btnH * 0.35
            nvgFontSize(vg, line1Size)
            nvgFillColor(vg, nvgRGBA(255, 230, 220, 255))
            nvgText(vg, goX + halfBtnW / 2, line1Y, "开启", nil)
            -- 第二行：会话中 / 有剩余次数 / 看广告
            local line2Size = math.max(9, btnFontSize * 0.65)
            local line2Y = btnAreaY + btnH * 0.7
            nvgFontSize(vg, line2Size)
            if GS.abyssWorldActive then
                -- 会话进行中：显示剩余复活次数
                local livesLeft = GS.abyssWorldLives or 0
                nvgFillColor(vg, livesLeft > 0 and nvgRGBA(100, 230, 100, 255) or nvgRGBA(230, 80, 60, 255))
                nvgText(vg, goX + halfBtnW / 2, line2Y, "剩余" .. livesLeft .. "次复活", nil)
            elseif abyssWorldRemain > 0 then
                -- 有剩余免费次数
                local prefix = "剩余："
                local numStr = tostring(abyssWorldRemain) .. "次"
                local prefixW = nvgTextBounds(vg, 0, 0, prefix, nil)
                local numW = nvgTextBounds(vg, 0, 0, numStr, nil)
                local startX = goX + halfBtnW / 2 - (prefixW + numW) / 2
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 190, 180, 220))
                nvgText(vg, startX, line2Y, prefix, nil)
                nvgFillColor(vg, nvgRGBA(100, 230, 100, 255))
                nvgText(vg, startX + prefixW, line2Y, numStr, nil)
            else
                -- 无免费次数，需看广告
                nvgFillColor(vg, nvgRGBA(220, 180, 80, 255))
                nvgText(vg, goX + halfBtnW / 2, line2Y, "看广告开启", nil)
            end
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        else
            -- 史莱姆国王大反击关卡：显示"挑战" + 剩余次数
            if isSlimeRevenge then
                -- 史莱姆大反击：显示"挑战" + 剩余次数
                local line1Size = math.max(11, btnFontSize * 0.9)
                local line1Y = btnAreaY + btnH * 0.35
                nvgFontSize(vg, line1Size)
                nvgFillColor(vg, nvgRGBA(255, 245, 220, 255))
                nvgText(vg, goX + halfBtnW / 2, line1Y, "挑战", nil)
                local line2Size = math.max(9, btnFontSize * 0.65)
                local line2Y = btnAreaY + btnH * 0.7
                nvgFontSize(vg, line2Size)
                local slimeRemain = GS.getSlimeRevengeRemain()
                if slimeRemain > 0 then
                    local prefix = "剩余："
                    local numStr = tostring(slimeRemain) .. "次"
                    local prefixW = nvgTextBounds(vg, 0, 0, prefix, nil)
                    local numW = nvgTextBounds(vg, 0, 0, numStr, nil)
                    local startX = goX + halfBtnW / 2 - (prefixW + numW) / 2
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(200, 190, 180, 220))
                    nvgText(vg, startX, line2Y, prefix, nil)
                    nvgFillColor(vg, nvgRGBA(100, 230, 100, 255))
                    nvgText(vg, startX + prefixW, line2Y, numStr, nil)
                else
                    nvgFillColor(vg, nvgRGBA(220, 180, 80, 255))
                    nvgText(vg, goX + halfBtnW / 2, line2Y, "看广告挑战", nil)
                end
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            else
                nvgFontSize(vg, btnFontSize)
                nvgFillColor(vg, nvgRGBA(255, 245, 220, 255))
                nvgText(vg, goX + halfBtnW / 2, btnAreaY + btnH / 2, "前往", nil)
            end
        end

        local stg
        if questStageOverride then
            stg = displayEntries[1] and displayEntries[1].stg
        else
            stg = stages[GS.selectedMapStage] or stages[1]
        end
        -- bg 优先级：关卡单独 bg > 区域 bg > 默认
        local stageBg = stg and stg.bg or selectedLoc.bg or "image/bg_grass.png"
        GS.mapGoButtonRect = {
            x = goX, y = btnAreaY, w = halfBtnW, h = btnH,
            stage = stg, locName = selectedLoc.name, locId = selectedLoc.id,
            bg = stageBg,
        }
    end

    -- 临时提示文本（居中浮现）
    if GS.mapTipText and GS.mapTipTimer > 0 then
        local alpha = math.min(1, GS.mapTipTimer / 0.3) * 230
        local tipFontSize = math.max(13, ch * 0.035)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, tipFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 背景条
        local tipW = tipFontSize * #GS.mapTipText * 0.55 + 24
        local tipH = tipFontSize * 2
        local tipX = cx + (cw - tipW) / 2
        local tipY = cy + ch * 0.4
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tipX, tipY, tipW, tipH, tipH * 0.25)
        nvgFillColor(vg, nvgRGBA(20, 15, 10, math.floor(alpha * 0.85)))
        nvgFill(vg)

        nvgFillColor(vg, nvgRGBA(255, 220, 160, math.floor(alpha)))
        nvgText(vg, tipX + tipW / 2, tipY + tipH / 2, GS.mapTipText, nil)
    end

    -- 灰色边框
    mapRect()
    nvgStrokeColor(vg, nvgRGBA(80, 80, 80, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgRestore(vg)
end


-- ====================================================================
-- 史莱姆国王大反击：累计伤害奖励面板（覆盖层弹窗）
-- ====================================================================
function M.drawSlimeRevengeRewardPanel()
    if not GS.slimeRevengeRewardPanel then return end
    local vg = M.vg
    local ImageManager = require("ImageManager")

    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    local panelW = math.min(320, sw - 20)
    local panelH = math.min(440, sh - 40)
    local panelX = (sw - panelW) / 2
    local panelY = (sh - panelH) / 2
    local pad = 10
    local cornerR = 8

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(30, 25, 18, 250))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    local titleH = 36
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, "最高伤害奖励", nil)

    -- 关闭按钮（右上角 ×）
    local closeBtnSize = 28
    local closeX = panelX + panelW - closeBtnSize - 4
    local closeY = panelY + 4
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 160, 200))
    nvgText(vg, closeX + closeBtnSize / 2, closeY + closeBtnSize / 2, "×", nil)
    GS._slimeRewardCloseBtnRect = { x = closeX, y = closeY, w = closeBtnSize, h = closeBtnSize }

    -- 当前累计伤害 / 历史最高
    local infoY = panelY + titleH
    local infoH = 22
    local bestDmg = GS.slimeRevengeBestDmg or 0
    local curDmg = GS.slimeRevengeAccDmg or 0
    local displayDmg = math.max(bestDmg, curDmg)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 195, 185, 220))
    nvgText(vg, panelX + panelW / 2, infoY + infoH / 2, "历史最高伤害: " .. fmtNum(displayDmg), nil)

    -- 列表区域
    local listX = panelX + pad
    local listY = infoY + infoH + 4
    local listW = panelW - pad * 2
    local listH = panelH - titleH - infoH - 4 - pad

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, listX, listY, listW, listH)

    -- 行参数
    local rowH = 38
    local rowGap = 2
    local totalRows = #GS.SLIME_REVENGE_REWARDS
    local contentH = totalRows * (rowH + rowGap)
    local maxScroll = math.max(0, contentH - listH)
    GS.slimeRevengeRewardScroll = math.max(0, math.min(GS.slimeRevengeRewardScroll, maxScroll))
    local scroll = GS.slimeRevengeRewardScroll

    -- 懒加载云端已领取数据
    if not GS._slimeRevengeRewardLoaded and not GS._slimeRevengeRewardLoading then
        if clientCloud then
            GS._slimeRevengeRewardLoading = true
            clientCloud:Get("slime_rev_claimed", {
                ok = function(values)
                    GS._slimeRevengeRewardLoading = false
                    GS._slimeRevengeRewardLoaded = true
                    local str = values and values.slime_rev_claimed
                    if str and str ~= "" then
                        -- 解析已领取索引："1,3,5,10" → { [1]=true, [3]=true, ... }
                        GS.slimeRevengeRewardClaimed = {}
                        for idx in string.gmatch(str, "(%d+)") do
                            GS.slimeRevengeRewardClaimed[tonumber(idx)] = true
                        end
                    end
                    print("[大反击奖励] 已领取数据加载完成: " .. tostring(str))
                end,
                error = function(code, reason)
                    GS._slimeRevengeRewardLoading = false
                    GS._slimeRevengeRewardLoaded = false  -- 加载失败不标记为已加载，禁止领取
                    print("[大反击奖励] 加载失败: " .. tostring(code) .. " " .. tostring(reason))
                end,
            })
        else
            GS._slimeRevengeRewardLoaded = true
        end
    end

    -- 存储领取按钮区域和行点击区域
    GS._slimeRewardClaimRects = {}
    GS._slimeRewardRowRects = {}

    -- 图标尺寸
    local iconSize = math.max(16, math.floor(rowH * 0.7))
    local iconPad = 2  -- 图标内边距

    for i, entry in ipairs(GS.SLIME_REVENGE_REWARDS) do
        local ry = listY - scroll + (i - 1) * (rowH + rowGap)
        -- 可见性剪裁优化
        if ry + rowH > listY and ry < listY + listH then
            local claimed = GS.slimeRevengeRewardClaimed[i]
            local canClaim = GS._slimeRevengeRewardLoaded and displayDmg >= entry.dmg and not claimed

            -- 行背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, listX, ry, listW, rowH, 4)
            if claimed then
                nvgFillColor(vg, nvgRGBA(40, 40, 35, 180))
            elseif canClaim then
                nvgFillColor(vg, nvgRGBA(60, 55, 30, 220))
            else
                nvgFillColor(vg, nvgRGBA(45, 40, 30, 200))
            end
            nvgFill(vg)

            -- 可领取行：金色边框
            if canClaim then
                nvgStrokeColor(vg, nvgRGBA(220, 180, 60, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end

            -- 奖励物品信息
            local tpl = GS.itemTemplates and GS.itemTemplates[entry.itemId]
            local itemName = tpl and tpl.name or entry.itemId
            local qtyStr = entry.qty > 1 and ("×" .. entry.qty) or ""
            -- 稀有度颜色
            local rarity = tpl and tpl.rarity or "common"
            local rc, gc, bc = 220, 215, 205
            if rarity == "epic" then rc, gc, bc = 180, 130, 255
            elseif rarity == "superior" then rc, gc, bc = 255, 200, 60
            elseif rarity == "rare" then rc, gc, bc = 100, 180, 255
            end

            -- 物品图标（左侧垂直居中）
            local iconX = listX + 6
            local iconY = ry + math.floor((rowH - iconSize) / 2)
            local imgH = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
            if imgH and imgH ~= -1 then
                local ip = nvgImagePattern(vg, iconX + iconPad, iconY + iconPad,
                    iconSize - iconPad * 2, iconSize - iconPad * 2, 0, imgH,
                    claimed and 0.5 or 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX + iconPad, iconY + iconPad,
                    iconSize - iconPad * 2, iconSize - iconPad * 2, 2)
                nvgFillPaint(vg, ip)
                nvgFill(vg)
            end
            -- 黑色边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 220))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 稀有度边框
            if tpl then
                local rd = GS.RARITY and GS.RARITY[rarity]
                if rd and rd.border then
                    local rbc = rd.border
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, iconX + 1, iconY + 1, iconSize - 2, iconSize - 2, 2)
                    nvgStrokeColor(vg, nvgRGBA(rbc[1], rbc[2], rbc[3], claimed and 100 or 200))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                end
            end

            -- 文本区域（图标右侧）
            local textX = iconX + iconSize + 6

            -- 累计伤害阈值（上方）
            local dmgStr = fmtNum(entry.dmg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if displayDmg >= entry.dmg then
                nvgFillColor(vg, nvgRGBA(180, 220, 140, 255))
            else
                nvgFillColor(vg, nvgRGBA(160, 155, 145, 200))
            end
            nvgText(vg, textX, ry + 4, dmgStr, nil)

            -- 物品名称（下方）
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(rc, gc, bc, claimed and 120 or 255))
            nvgText(vg, textX, ry + rowH - 4, itemName .. qtyStr, nil)

            -- 存储图标点击区域（用于点击弹出tooltip）
            GS._slimeRewardRowRects[i] = { x = iconX, y = iconY, w = iconSize, h = iconSize, itemId = entry.itemId }

            -- 右侧按钮/状态
            local btnW2 = 48
            local btnH2 = 22
            local btnX2 = listX + listW - btnW2 - 6
            local btnY2 = ry + (rowH - btnH2) / 2

            if claimed then
                -- 已领取 - 绿色文本
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(60, 180, 80, 200))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "已领取", nil)
            elseif canClaim then
                -- 领取按钮 - 绿色背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 3)
                nvgFillColor(vg, nvgRGBA(50, 160, 60, 230))
                nvgFill(vg)
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 240, 255))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "领取", nil)
                GS._slimeRewardClaimRects[i] = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }
            else
                -- 未达成 - 红色文本
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 60, 50, 200))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "未达成", nil)
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条
    if contentH > listH then
        local sbW = 3
        local sbX = panelX + panelW - pad - sbW
        local sbTrackH = listH
        local thumbRatio = listH / contentH
        local thumbH = math.max(20, sbTrackH * thumbRatio)
        local thumbY = listY + (scroll / maxScroll) * (sbTrackH - thumbH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbX, thumbY, sbW, thumbH, 1.5)
        nvgFillColor(vg, nvgRGBA(200, 180, 140, 120))
        nvgFill(vg)
    end

    -- 存储面板区域和列表区域供输入使用
    GS._slimeRewardPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }
    GS._slimeRewardListRect = { x = listX, y = listY, w = listW, h = listH }
    GS._slimeRewardMaxScroll = maxScroll
end

-- ====================================================================
-- 史莱姆国王大反击：累计伤害排名面板
-- ====================================================================
function M.drawSlimeRevengeRankPanel()
    if not GS.slimeRevengeRankPanel then return end
    local vg = M.vg

    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    local panelW = math.min(340, sw - 16)
    local panelH = math.min(480, sh - 30)
    local panelX = (sw - panelW) / 2
    local panelY = (sh - panelH) / 2
    local pad = 10
    local cornerR = 8

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(30, 25, 18, 250))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    local titleH = 36
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, "累计伤害排名", nil)

    -- 关闭按钮（右上角 ×）
    local closeBtnSize = 28
    local closeX = panelX + panelW - closeBtnSize - 4
    local closeY = panelY + 4
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 160, 200))
    nvgText(vg, closeX + closeBtnSize / 2, closeY + closeBtnSize / 2, "×", nil)
    GS._slimeRankCloseBtnRect = { x = closeX, y = closeY, w = closeBtnSize, h = closeBtnSize }

    -- Tab 栏
    local tabY = panelY + titleH
    local tabH = 28
    local tabs = GS.SLIME_RANK_TABS
    local tabCount = #tabs
    local tabW = (panelW - pad * 2) / tabCount
    local currentTab = GS.slimeRevengeRankTab or 0

    GS._slimeRankTabRects = {}
    for i, tab in ipairs(tabs) do
        local tx = panelX + pad + (i - 1) * tabW
        local isActive = (currentTab == (i - 1))

        -- Tab 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx + 1, tabY + 1, tabW - 2, tabH - 2, 4)
        if isActive then
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 200))
        else
            nvgFillColor(vg, nvgRGBA(50, 45, 35, 200))
        end
        nvgFill(vg)

        -- Tab 文字
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(40, 30, 10, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 170, 140, 200))
        end
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, tab.label, nil)

        GS._slimeRankTabRects[i] = { x = tx, y = tabY, w = tabW, h = tabH }
    end

    -- 列表区域
    local listY = tabY + tabH + 6
    local listX = panelX + pad
    local listW = panelW - pad * 2
    local listH = panelH - (listY - panelY) - pad - 40  -- 底部留40给"我的排名"
    local itemH = 28
    local gap = 2

    -- 加载中 / 空数据 / 列表渲染
    if GS.slimeRevengeRankLoading then
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 140, 200))
        nvgText(vg, panelX + panelW / 2, listY + listH / 2, "加载中...", nil)
    elseif not GS.slimeRevengeRankData or not GS.slimeRevengeRankData.entries or #GS.slimeRevengeRankData.entries == 0 then
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 120, 180))
        nvgText(vg, panelX + panelW / 2, listY + listH / 2, "暂无排名数据", nil)
    else
        local entries = GS.slimeRevengeRankData.entries
        local contentH = #entries * (itemH + gap)
        local maxScroll = math.max(0, contentH - listH)
        local scroll = math.max(0, math.min(GS.slimeRevengeRankScroll or 0, maxScroll))
        GS.slimeRevengeRankScroll = scroll
        GS._slimeRankMaxScroll = maxScroll

        -- 裁剪区
        nvgSave(vg)
        nvgScissor(vg, listX, listY, listW, listH)

        local myUserId = clientCloud and clientCloud.userId or 0
        local startY = listY - scroll

        for i, entry in ipairs(entries) do
            local iy = startY + (i - 1) * (itemH + gap)

            -- 只绘制可见行
            if iy + itemH >= listY and iy <= listY + listH then
                local isMe = (entry.userId == myUserId)

                -- 行背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, listX, iy, listW, itemH, 4)
                if isMe then
                    nvgFillColor(vg, nvgRGBA(50, 70, 100, 180))
                elseif i % 2 == 0 then
                    nvgFillColor(vg, nvgRGBA(30, 35, 55, 150))
                else
                    nvgFillColor(vg, nvgRGBA(35, 40, 60, 150))
                end
                nvgFill(vg)

                if isMe then
                    nvgStrokeColor(vg, nvgRGBA(80, 140, 220, 150))
                    nvgStrokeWidth(vg, 0.8)
                    nvgStroke(vg)
                end

                local midY = iy + itemH / 2

                -- 排名序号（前三名金银铜色）
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if i <= 3 then
                    local rankColors = {
                        {255, 215, 0},
                        {192, 192, 192},
                        {205, 127, 50},
                    }
                    local rc = rankColors[i]
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
                else
                    nvgFillColor(vg, nvgRGBA(140, 150, 180, 200))
                end
                nvgText(vg, listX + 16, midY, "#" .. i, nil)

                -- 职业颜色圆点（总排行才显示）
                local nameStartX = listX + 32
                if currentTab == 0 and entry.className then
                    local cc = GS.CLASS_COLORS[entry.className] or {160, 160, 160}
                    nvgBeginPath(vg)
                    nvgCircle(vg, nameStartX + 4, midY, 3.5)
                    nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                    nvgFill(vg)
                    nameStartX = nameStartX + 12
                end

                -- 昵称
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                local nameColor = isMe and nvgRGBA(120, 180, 255, 255) or nvgRGBA(200, 210, 230, 230)
                nvgFillColor(vg, nameColor)
                local displayName = entry.nickname or ("ID:" .. tostring(entry.userId))
                if isMe then displayName = displayName .. " (我)" end
                -- 截断过长昵称
                local maxNameW = listW - (nameStartX - listX) - 70
                nvgText(vg, nameStartX, midY, displayName, nil)

                -- 累计伤害值
                nvgFontSize(vg, 10)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 180, 80, 220))
                local dmgText = tostring(entry.damage or 0)
                -- 格式化大数字
                if (entry.damage or 0) >= 100000000 then
                    dmgText = string.format("%.1f亿", (entry.damage or 0) / 100000000)
                elseif (entry.damage or 0) >= 10000 then
                    dmgText = string.format("%.1f万", (entry.damage or 0) / 10000)
                end
                nvgText(vg, listX + listW - 4, midY, dmgText, nil)
            end
        end

        nvgRestore(vg)

        -- 滚动条
        if contentH > listH then
            local sbW = 3
            local sbX = panelX + panelW - pad - sbW
            local sbTrackH = listH
            local thumbRatio = listH / contentH
            local thumbH = math.max(20, sbTrackH * thumbRatio)
            local thumbY = listY + (scroll / maxScroll) * (sbTrackH - thumbH)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sbX, thumbY, sbW, thumbH, 1.5)
            nvgFillColor(vg, nvgRGBA(200, 180, 140, 120))
            nvgFill(vg)
        end
    end

    -- "我的排名"底栏
    local myBarY = panelY + panelH - pad - 30
    local myBarH = 30
    nvgBeginPath(vg)
    nvgRoundedRect(vg, listX, myBarY, listW, myBarH, 4)
    nvgFillColor(vg, nvgRGBA(40, 50, 70, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 140, 200, 150))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 180, 255, 255))
    local myRankText = "我的排名: "
    if GS.slimeRevengeRankData and GS.slimeRevengeRankData.myRank then
        local mr = GS.slimeRevengeRankData.myRank
        myRankText = myRankText .. "#" .. mr.rank .. "  伤害: "
        local dmg = mr.damage or 0
        if dmg >= 100000000 then
            myRankText = myRankText .. string.format("%.1f亿", dmg / 100000000)
        elseif dmg >= 10000 then
            myRankText = myRankText .. string.format("%.1f万", dmg / 10000)
        else
            myRankText = myRankText .. tostring(dmg)
        end
    elseif GS.slimeRevengeRankLoading then
        myRankText = myRankText .. "加载中..."
    else
        myRankText = myRankText .. "未上榜"
    end
    nvgText(vg, listX + 8, myBarY + myBarH / 2, myRankText, nil)

    -- 存储面板区域供输入使用
    GS._slimeRankPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }
    GS._slimeRankListRect = { x = listX, y = listY, w = listW, h = listH }
end


-- ====================================================================
-- 迪哈塔大反击：最高伤害奖励面板
-- ====================================================================
function M.drawDihataRevengeRewardPanel()
    if not GS.dihataRevengeRewardPanel then return end
    local vg = M.vg
    local ImageManager = require("ImageManager")

    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    local panelW = math.min(320, sw - 20)
    local panelH = math.min(440, sh - 40)
    local panelX = (sw - panelW) / 2
    local panelY = (sh - panelH) / 2
    local pad = 10
    local cornerR = 8

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(30, 25, 18, 250))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 140, 40, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    local titleH = 36
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 160, 40, 255))
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, "最高伤害奖励", nil)

    -- 关闭按钮
    local closeBtnSize = 28
    local closeX = panelX + panelW - closeBtnSize - 4
    local closeY = panelY + 4
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 160, 200))
    nvgText(vg, closeX + closeBtnSize / 2, closeY + closeBtnSize / 2, "×", nil)
    GS._dihataRewardCloseBtnRect = { x = closeX, y = closeY, w = closeBtnSize, h = closeBtnSize }

    -- 当前累计伤害 / 历史最高
    local infoY = panelY + titleH
    local infoH = 22
    local bestDmg = GS.dihataRevengeBestDmg or 0
    local curDmg = GS.dihataRevengeAccDmg or 0
    local displayDmg = math.max(bestDmg, curDmg)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 195, 185, 220))
    nvgText(vg, panelX + panelW / 2, infoY + infoH / 2, "历史最高伤害: " .. fmtNum(displayDmg), nil)

    -- 列表区域
    local listX = panelX + pad
    local listY = infoY + infoH + 4
    local listW = panelW - pad * 2
    local listH = panelH - titleH - infoH - 4 - pad

    nvgSave(vg)
    nvgScissor(vg, listX, listY, listW, listH)

    local rowH = 38
    local rowGap = 2
    local totalRows = #GS.DIHATA_REVENGE_REWARDS
    local contentH = totalRows * (rowH + rowGap)
    local maxScroll = math.max(0, contentH - listH)
    GS.dihataRevengeRewardScroll = math.max(0, math.min(GS.dihataRevengeRewardScroll or 0, maxScroll))
    local scroll = GS.dihataRevengeRewardScroll

    -- 懒加载云端已领取数据
    if not GS._dihataRevengeRewardLoaded and not GS._dihataRevengeRewardLoading then
        if clientCloud then
            GS._dihataRevengeRewardLoading = true
            clientCloud:Get("dihata_rev_claimed", {
                ok = function(values)
                    GS._dihataRevengeRewardLoading = false
                    GS._dihataRevengeRewardLoaded = true
                    local str = values and values.dihata_rev_claimed
                    if str and str ~= "" then
                        GS.dihataRevengeRewardClaimed = {}
                        for idx in string.gmatch(str, "(%d+)") do
                            GS.dihataRevengeRewardClaimed[tonumber(idx)] = true
                        end
                    end
                    print("[迪哈塔大反击奖励] 已领取数据加载完成: " .. tostring(str))
                end,
                error = function(code, reason)
                    GS._dihataRevengeRewardLoading = false
                    GS._dihataRevengeRewardLoaded = false
                    print("[迪哈塔大反击奖励] 加载失败: " .. tostring(code) .. " " .. tostring(reason))
                end,
            })
        else
            GS._dihataRevengeRewardLoaded = true
        end
    end

    GS._dihataRewardClaimRects = {}
    GS._dihataRewardRowRects = {}

    local iconSize = math.max(16, math.floor(rowH * 0.7))
    local iconPad = 2

    for i, entry in ipairs(GS.DIHATA_REVENGE_REWARDS) do
        local ry = listY - scroll + (i - 1) * (rowH + rowGap)
        if ry + rowH > listY and ry < listY + listH then
            local claimed = GS.dihataRevengeRewardClaimed[i]
            local canClaim = GS._dihataRevengeRewardLoaded and displayDmg >= entry.dmg and not claimed

            nvgBeginPath(vg)
            nvgRoundedRect(vg, listX, ry, listW, rowH, 4)
            if claimed then
                nvgFillColor(vg, nvgRGBA(40, 40, 35, 180))
            elseif canClaim then
                nvgFillColor(vg, nvgRGBA(60, 55, 30, 220))
            else
                nvgFillColor(vg, nvgRGBA(45, 40, 30, 200))
            end
            nvgFill(vg)

            if canClaim then
                nvgStrokeColor(vg, nvgRGBA(220, 180, 60, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end

            local tpl = GS.itemTemplates and GS.itemTemplates[entry.itemId]
            local itemName = tpl and tpl.name or entry.itemId
            local qtyStr = entry.qty > 1 and ("×" .. entry.qty) or ""
            local rarity = tpl and tpl.rarity or "common"
            local rc, gc, bc = 220, 215, 205
            if rarity == "epic" then rc, gc, bc = 180, 130, 255
            elseif rarity == "superior" then rc, gc, bc = 255, 200, 60
            elseif rarity == "rare" then rc, gc, bc = 100, 180, 255
            end

            local iconX = listX + 6
            local iconY = ry + math.floor((rowH - iconSize) / 2)
            local imgH = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
            if imgH and imgH ~= -1 then
                local ip = nvgImagePattern(vg, iconX + iconPad, iconY + iconPad,
                    iconSize - iconPad * 2, iconSize - iconPad * 2, 0, imgH,
                    claimed and 0.5 or 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX + iconPad, iconY + iconPad,
                    iconSize - iconPad * 2, iconSize - iconPad * 2, 2)
                nvgFillPaint(vg, ip)
                nvgFill(vg)
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 220))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            if tpl then
                local rd = GS.RARITY and GS.RARITY[rarity]
                if rd and rd.border then
                    local rbc = rd.border
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, iconX + 1, iconY + 1, iconSize - 2, iconSize - 2, 2)
                    nvgStrokeColor(vg, nvgRGBA(rbc[1], rbc[2], rbc[3], claimed and 100 or 200))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                end
            end

            local textX = iconX + iconSize + 6
            local dmgStr = fmtNum(entry.dmg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if displayDmg >= entry.dmg then
                nvgFillColor(vg, nvgRGBA(180, 220, 140, 255))
            else
                nvgFillColor(vg, nvgRGBA(160, 155, 145, 200))
            end
            nvgText(vg, textX, ry + 4, dmgStr, nil)

            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(rc, gc, bc, claimed and 120 or 255))
            nvgText(vg, textX, ry + rowH - 4, itemName .. qtyStr, nil)

            GS._dihataRewardRowRects[i] = { x = iconX, y = iconY, w = iconSize, h = iconSize, itemId = entry.itemId }

            local btnW2 = 48
            local btnH2 = 22
            local btnX2 = listX + listW - btnW2 - 6
            local btnY2 = ry + (rowH - btnH2) / 2

            if claimed then
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(60, 180, 80, 200))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "已领取", nil)
            elseif canClaim then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 3)
                nvgFillColor(vg, nvgRGBA(50, 160, 60, 230))
                nvgFill(vg)
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 240, 255))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "领取", nil)
                GS._dihataRewardClaimRects[i] = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }
            else
                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 60, 50, 200))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "未达成", nil)
            end
        end
    end

    nvgRestore(vg)

    if contentH > listH then
        local sbW = 3
        local sbX = panelX + panelW - pad - sbW
        local sbTrackH = listH
        local thumbRatio = listH / contentH
        local thumbH = math.max(20, sbTrackH * thumbRatio)
        local thumbY = listY + (scroll / maxScroll) * (sbTrackH - thumbH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbX, thumbY, sbW, thumbH, 1.5)
        nvgFillColor(vg, nvgRGBA(200, 180, 140, 120))
        nvgFill(vg)
    end

    GS._dihataRewardPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }
    GS._dihataRewardListRect = { x = listX, y = listY, w = listW, h = listH }
    GS._dihataRewardMaxScroll = maxScroll
end

-- ====================================================================
-- 迪哈塔大反击：累计伤害排名面板
-- ====================================================================
function M.drawDihataRevengeRankPanel()
    if not GS.dihataRevengeRankPanel then return end
    local vg = M.vg

    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    local panelW = math.min(340, sw - 16)
    local panelH = math.min(480, sh - 30)
    local panelX = (sw - panelW) / 2
    local panelY = (sh - panelH) / 2
    local pad = 10
    local cornerR = 8

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(30, 25, 18, 250))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 140, 40, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    local titleH = 36
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 160, 40, 255))
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, "累计伤害排名", nil)

    local closeBtnSize = 28
    local closeX = panelX + panelW - closeBtnSize - 4
    local closeY = panelY + 4
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 160, 200))
    nvgText(vg, closeX + closeBtnSize / 2, closeY + closeBtnSize / 2, "×", nil)
    GS._dihataRankCloseBtnRect = { x = closeX, y = closeY, w = closeBtnSize, h = closeBtnSize }

    -- Tab 栏
    local tabY = panelY + titleH
    local tabH = 28
    local tabs = GS.DIHATA_RANK_TABS
    local tabCount = #tabs
    local tabW = (panelW - pad * 2) / tabCount
    local currentTab = GS.dihataRevengeRankTab or 0

    GS._dihataRankTabRects = {}
    for i, tab in ipairs(tabs) do
        local tx = panelX + pad + (i - 1) * tabW
        local isActive = (currentTab == (i - 1))

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx + 1, tabY + 1, tabW - 2, tabH - 2, 4)
        if isActive then
            nvgFillColor(vg, nvgRGBA(200, 140, 40, 200))
        else
            nvgFillColor(vg, nvgRGBA(50, 45, 35, 200))
        end
        nvgFill(vg)

        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(40, 30, 10, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 170, 140, 200))
        end
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, tab.label, nil)

        GS._dihataRankTabRects[i] = { x = tx, y = tabY, w = tabW, h = tabH }
    end

    local listY = tabY + tabH + 6
    local listX = panelX + pad
    local listW = panelW - pad * 2
    local listH = panelH - (listY - panelY) - pad - 40
    local itemH = 28
    local gap = 2

    if GS.dihataRevengeRankLoading then
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 140, 200))
        nvgText(vg, panelX + panelW / 2, listY + listH / 2, "加载中...", nil)
    elseif not GS.dihataRevengeRankData or not GS.dihataRevengeRankData.entries or #GS.dihataRevengeRankData.entries == 0 then
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 120, 180))
        nvgText(vg, panelX + panelW / 2, listY + listH / 2, "暂无排名数据", nil)
    else
        local entries = GS.dihataRevengeRankData.entries
        local contentH = #entries * (itemH + gap)
        local maxScroll = math.max(0, contentH - listH)
        local scroll = math.max(0, math.min(GS.dihataRevengeRankScroll or 0, maxScroll))
        GS.dihataRevengeRankScroll = scroll
        GS._dihataRankMaxScroll = maxScroll

        nvgSave(vg)
        nvgScissor(vg, listX, listY, listW, listH)

        local myUserId = clientCloud and clientCloud.userId or 0
        local startY = listY - scroll

        for i, entry in ipairs(entries) do
            local iy = startY + (i - 1) * (itemH + gap)
            if iy + itemH >= listY and iy <= listY + listH then
                local isMe = (entry.userId == myUserId)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, listX, iy, listW, itemH, 4)
                if isMe then
                    nvgFillColor(vg, nvgRGBA(50, 70, 100, 180))
                elseif i % 2 == 0 then
                    nvgFillColor(vg, nvgRGBA(30, 35, 55, 150))
                else
                    nvgFillColor(vg, nvgRGBA(35, 40, 60, 150))
                end
                nvgFill(vg)

                if isMe then
                    nvgStrokeColor(vg, nvgRGBA(80, 140, 220, 150))
                    nvgStrokeWidth(vg, 0.8)
                    nvgStroke(vg)
                end

                local midY = iy + itemH / 2

                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if i <= 3 then
                    local rankColors = {
                        {255, 215, 0},
                        {192, 192, 192},
                        {205, 127, 50},
                    }
                    local rc = rankColors[i]
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
                else
                    nvgFillColor(vg, nvgRGBA(140, 150, 180, 200))
                end
                nvgText(vg, listX + 16, midY, "#" .. i, nil)

                local nameStartX = listX + 32
                if currentTab == 0 and entry.className then
                    local cc = GS.CLASS_COLORS[entry.className] or {160, 160, 160}
                    nvgBeginPath(vg)
                    nvgCircle(vg, nameStartX + 4, midY, 3.5)
                    nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                    nvgFill(vg)
                    nameStartX = nameStartX + 12
                end

                nvgFontSize(vg, 11)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                local nameColor = isMe and nvgRGBA(120, 180, 255, 255) or nvgRGBA(200, 210, 230, 230)
                nvgFillColor(vg, nameColor)
                local displayName = entry.nickname or ("ID:" .. tostring(entry.userId))
                if isMe then displayName = displayName .. " (我)" end
                nvgText(vg, nameStartX, midY, displayName, nil)

                nvgFontSize(vg, 10)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 180, 80, 220))
                local dmgText = tostring(entry.damage or 0)
                if (entry.damage or 0) >= 100000000 then
                    dmgText = string.format("%.1f亿", (entry.damage or 0) / 100000000)
                elseif (entry.damage or 0) >= 10000 then
                    dmgText = string.format("%.1f万", (entry.damage or 0) / 10000)
                end
                nvgText(vg, listX + listW - 4, midY, dmgText, nil)
            end
        end

        nvgRestore(vg)

        if contentH > listH then
            local sbW = 3
            local sbX = panelX + panelW - pad - sbW
            local sbTrackH = listH
            local thumbRatio = listH / contentH
            local thumbH = math.max(20, sbTrackH * thumbRatio)
            local thumbY = listY + (scroll / maxScroll) * (sbTrackH - thumbH)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sbX, thumbY, sbW, thumbH, 1.5)
            nvgFillColor(vg, nvgRGBA(200, 180, 140, 120))
            nvgFill(vg)
        end
    end

    -- "我的排名"底栏
    local myBarY = panelY + panelH - pad - 30
    local myBarH = 30
    nvgBeginPath(vg)
    nvgRoundedRect(vg, listX, myBarY, listW, myBarH, 4)
    nvgFillColor(vg, nvgRGBA(40, 50, 70, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 140, 200, 150))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 180, 255, 255))
    local myRankText = "我的排名: "
    if GS.dihataRevengeRankData and GS.dihataRevengeRankData.myRank then
        local mr = GS.dihataRevengeRankData.myRank
        myRankText = myRankText .. "#" .. mr.rank .. "  伤害: "
        local dmg = mr.damage or 0
        if dmg >= 100000000 then
            myRankText = myRankText .. string.format("%.1f亿", dmg / 100000000)
        elseif dmg >= 10000 then
            myRankText = myRankText .. string.format("%.1f万", dmg / 10000)
        else
            myRankText = myRankText .. tostring(dmg)
        end
    elseif GS.dihataRevengeRankLoading then
        myRankText = myRankText .. "加载中..."
    else
        myRankText = myRankText .. "未上榜"
    end
    nvgText(vg, listX + 8, myBarY + myBarH / 2, myRankText, nil)

    GS._dihataRankPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }
    GS._dihataRankListRect = { x = listX, y = listY, w = listW, h = listH }
end

end  -- sub.init

return sub
