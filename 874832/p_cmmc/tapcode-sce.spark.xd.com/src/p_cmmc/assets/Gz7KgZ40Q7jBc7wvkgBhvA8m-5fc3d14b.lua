-- ============================================================
-- 纵跃魔塔 - 地图编辑器模块
-- ============================================================

-- 地图编辑器状态
-- ============================================================
mapEditor = {
    floor = 1,
    totalFloors = 25,
    brush = "W",
    tab = 1,
    floors = {},       -- floors[n] = grid[r][c]
    isDragging = false,
    message = "",
    msgTimer = 0,
    toolbarRects = {},  -- 工具栏按钮区域
    tabRects = {},      -- 标签区域
    paletteRects = {},  -- 调色板瓦片区域
    gridRects = nil,    -- {x, y, cellSize} 网格布局信息
    loaded = false,
    -- 撤销系统
    undoStack = {},     -- { {type="tiles", floor=n, changes={{r,c,oldCh},...}}, {type="clearFloor", floor=n, oldGrid=grid}, ... }
    undoGroupOpen = false, -- 拖拽绘制时，一次拖拽合并为一组
}

-- 编辑器瓦片分类标签页（存入 mapEditor 减少顶层 local 数量）
mapEditor.tabs = {
    {name = "基础",     tiles = {"W", ".", "P", "U", "D", "$"}},
    {name = "怪物",     tiles = {"1","2","4","3","p","F","I","5","6","O","k","8","9","Z","A","C","J","X","L","N","7"}},
    {name = "物品",     tiles = {"h", "H", "z", "j", "a", "m", "s", "v", "c", "d", "g", "q", "x", "G"}},
    {name = "门钥匙",   tiles = {"y","b","r","Y","B","R"}},
    {name = "技能宝石", tiles = {"S","V","K","T","E","M","Q","f","i","l","t","n","o","e","w"}},
}

-- 编辑器瓦片显示信息（名称+回退色）
mapEditor.tileInfo = {
    ["W"] = {name = "墙",   r = 85,  g = 75,  b = 105},
    ["."] = {name = "空地", r = 65,  g = 62,  b = 80},
    ["P"] = {name = "起点", r = 50,  g = 200, b = 50},
    ["U"] = {name = "上楼", r = 80,  g = 180, b = 80},
    ["D"] = {name = "下楼", r = 180, g = 140, b = 80},
    ["$"] = {name = "商店", r = 255, g = 200, b = 50},
    ["y"] = {name = "黄钥", r = 255, g = 220, b = 50},
    ["b"] = {name = "蓝钥", r = 80,  g = 160, b = 255},
    ["r"] = {name = "红钥", r = 255, g = 60,  b = 60},
    ["Y"] = {name = "黄门", r = 200, g = 180, b = 40},
    ["B"] = {name = "蓝门", r = 60,  g = 120, b = 220},
    ["R"] = {name = "红门", r = 200, g = 40,  b = 40},
    ["1"] = {name = "绿史", r = 60,  g = 200, b = 60},
    ["2"] = {name = "红史", r = 220, g = 60,  b = 60},
    ["p"] = {name = "黑史", r = 120, g = 100, b = 140},
    ["3"] = {name = "骷兵", r = 200, g = 200, b = 200},
    ["4"] = {name = "蝙蝠", r = 160, g = 60,  b = 200},
    ["F"] = {name = "地精", r = 160, g = 120, b = 80},
    ["I"] = {name = "幽灵", r = 220, g = 220, b = 240},
    ["5"] = {name = "法师", r = 180, g = 80,  b = 220},
    ["6"] = {name = "骷战", r = 220, g = 210, b = 180},
    ["O"] = {name = "石像", r = 180, g = 180, b = 200},
    ["k"] = {name = "狂战", r = 220, g = 80,  b = 60},
    ["8"] = {name = "兽面", r = 180, g = 120, b = 60},
    ["9"] = {name = "石头", r = 160, g = 160, b = 140},
    ["Z"] = {name = "恶骑", r = 200, g = 50,  b = 50},
    ["A"] = {name = "暗骑", r = 100, g = 80,  b = 140},
    ["C"] = {name = "守卫", r = 180, g = 40,  b = 40},
    ["J"] = {name = "史王", r = 60,  g = 255, b = 80},
    ["X"] = {name = "章鱼", r = 255, g = 80,  b = 20},
    ["L"] = {name = "巨龙", r = 220, g = 200, b = 160},
    ["N"] = {name = "吸血", r = 140, g = 40,  b = 200},
    ["7"] = {name = "魔王", r = 255, g = 20,  b = 20},
    ["h"] = {name = "血+50", r = 220, g = 100, b = 100},
    ["H"] = {name = "血100", r = 200, g = 140, b = 200},
    ["z"] = {name = "血300", r = 80,  g = 200, b = 120},
    ["a"] = {name = "攻+1", r = 255, g = 150, b = 150},
    ["j"] = {name = "攻+2", r = 255, g = 100, b = 80},
    ["m"] = {name = "攻+4", r = 255, g = 60,  b = 60},
    ["s"] = {name = "攻+8", r = 220, g = 40,  b = 40},
    ["v"] = {name = "攻15", r = 180, g = 20,  b = 20},
    ["d"] = {name = "防+1", r = 150, g = 180, b = 255},
    ["c"] = {name = "防+2", r = 80,  g = 140, b = 255},
    ["g"] = {name = "防+4", r = 60,  g = 100, b = 255},
    ["q"] = {name = "防+8", r = 40,  g = 60,  b = 220},
    ["x"] = {name = "防15", r = 20,  g = 40,  b = 180},
    ["G"] = {name = "遗物", r = 255, g = 180, b = 60},
    ["S"] = {name = "圣盾", r = 100, g = 200, b = 255},
    ["V"] = {name = "吸血", r = 220, g = 50,  b = 80},
    ["K"] = {name = "暴击", r = 255, g = 160, b = 30},
    ["T"] = {name = "坚韧", r = 80,  g = 180, b = 80},
    ["E"] = {name = "贪婪", r = 255, g = 220, b = 50},
    ["M"] = {name = "灵能", r = 120, g = 160, b = 255},
    ["Q"] = {name = "多抽", r = 180, g = 220, b = 100},
    ["f"] = {name = "烈焰", r = 255, g = 100, b = 30},
    ["i"] = {name = "寒冰", r = 100, g = 200, b = 255},
    ["l"] = {name = "圣光", r = 255, g = 230, b = 80},
    ["t"] = {name = "雷霆", r = 180, g = 100, b = 255},
    ["n"] = {name = "节能", r = 80,  g = 220, b = 180},
    ["o"] = {name = "嗜血", r = 200, g = 40,  b = 60},
    ["e"] = {name = "余韵", r = 160, g = 120, b = 255},
    ["w"] = {name = "汲取", r = 60,  g = 180, b = 220},
}

-- 角色选择界面动画计时器
-- charAnimTimer / charAnimFrameIdx 存放在 charSelect 表中
charSelect.animTimer = 0
charSelect.animFrameIdx = 1

-- 商店系统
local shopOpen = false
local shopItems = {}       -- 当前商店商品列表
local shopScroll = 0       -- 商店滚动偏移
local shopItemRects = {}   -- 商品点击区域（每帧重建）
local shopCloseRect = nil  -- 关闭按钮区域


-- 地图编辑器函数
-- ============================================================

--- 创建空网格（外圈墙壁，内部空地）
function editorCreateEmptyGrid()
    local g = {}
    for r = 1, GRID do
        g[r] = {}
        for c = 1, GRID do
            if r == 1 or r == GRID or c == 1 or c == GRID then
                g[r][c] = "W"
            else
                g[r][c] = "."
            end
        end
    end
    return g
end

--- 获取当前层的网格（不存在则创建）
function editorGetGrid()
    if not mapEditor.floors[mapEditor.floor] then
        mapEditor.floors[mapEditor.floor] = editorCreateEmptyGrid()
    end
    return mapEditor.floors[mapEditor.floor]
end

--- 网格转字符串数组（用于保存）
function editorGridToStrings(g)
    local lines = {}
    for r = 1, GRID do
        local row = ""
        for c = 1, GRID do
            row = row .. (g[r][c] or ".")
        end
        lines[r] = row
    end
    return lines
end

--- 字符串数组转网格（用于加载）
function editorStringsToGrid(lines)
    local g = {}
    for r = 1, GRID do
        g[r] = {}
        local rowStr = lines[r] or "WWWWWWWWWWW"
        for c = 1, GRID do
            g[r][c] = rowStr:sub(c, c)
            if g[r][c] == "" or g[r][c] == " " then g[r][c] = "." end
        end
    end
    return g
end

--- 显示编辑器消息
function editorShowMessage(text)
    mapEditor.message = text
    mapEditor.msgTimer = 2.0
end

--- 从 JSON 数据中解析地图，支持两种格式：
--- 格式A (data/map.json): { totalFloors, maps: [{floor, data:[...]}, ...] }
--- 格式B (edited_maps.json): { totalFloors, floors: {"1":[...], "2":[...], ...} }
--- @return table|nil mapData 按层号索引的行字符串数组 { [1]={"WWW...","W.W...",...}, ... }
--- @return number totalFloors
function parseMapJson(data)
    if not data then return nil, 0 end
    local totalFloors = data.totalFloors or 25
    local mapData = {}
    if data.maps then
        -- 格式A: maps 数组
        for _, entry in ipairs(data.maps) do
            local f = entry.floor
            if f and entry.data then
                mapData[f] = entry.data
            end
        end
    elseif data.floors then
        -- 格式B: floors 字典
        for fStr, lines in pairs(data.floors) do
            local f = tonumber(fStr)
            if f then
                mapData[f] = lines
            end
        end
    end
    return mapData, totalFloors
end

--- 从 cache 资源路径加载 data/map.json
--- @return table|nil mapData, number totalFloors
function loadMapJsonFromCache()
    local file = cache:GetFile("data/map.json")
    if not file then
        log:Write(LOG_WARNING, "[MapData] data/map.json 不存在于资源路径")
        return nil, 0
    end
    local str = file:ReadString()
    file:Close()
    if not str or str == "" then return nil, 0 end
    local ok, data = pcall(_cjson.decode, str)
    if not ok or not data then
        log:Write(LOG_ERROR, "[MapData] data/map.json JSON解码失败: " .. tostring(data))
        return nil, 0
    end
    local mapData, totalFloors = parseMapJson(data)
    ---@cast mapData table
    ---@type number
    local count = 0
    for _ in pairs(mapData) do count = count + 1 end
    log:Write(LOG_INFO, "[MapData] 从 data/map.json 加载了 " .. count .. " 层地图 (共 " .. totalFloors .. " 层)")
    return mapData, totalFloors
end

--- 从 FixedMaps 加载地图到编辑器（回退方案）
function editorLoadMaps()
    -- 优先从 data/map.json 加载
    local mapData, totalFloors = loadMapJsonFromCache()
    if mapData and next(mapData) then
        mapEditor.totalFloors = totalFloors
        mapEditor.floors = {}
        for f, lines in pairs(mapData) do
            mapEditor.floors[f] = editorStringsToGrid(lines)
        end
        mapEditor.floor = 1
        mapEditor.loaded = true
        editorShowMessage("已从 map.json 加载 " .. mapEditor.totalFloors .. " 层地图")
        return
    end
    -- 回退到 FixedMaps.lua
    local ok, fm = pcall(require, "FixedMaps")
    if not ok or not fm then
        editorShowMessage("加载地图失败")
        return
    end
    mapEditor.totalFloors = fm.TOTAL_FLOORS or 25
    mapEditor.floors = {}
    for f = 1, mapEditor.totalFloors do
        if fm.data[f] then
            mapEditor.floors[f] = editorStringsToGrid(fm.data[f])
        end
    end
    mapEditor.floor = 1
    mapEditor.loaded = true
    editorShowMessage("已从 FixedMaps 加载 " .. mapEditor.totalFloors .. " 层地图")
end

--- 保存编辑地图到沙盒 JSON 文件
function editorSaveMaps()
    local data = {totalFloors = mapEditor.totalFloors, floors = {}}
    local floorCount = 0
    for f = 1, mapEditor.totalFloors do
        if mapEditor.floors[f] then
            data.floors[tostring(f)] = editorGridToStrings(mapEditor.floors[f])
            floorCount = floorCount + 1
        end
    end
    log:Write(LOG_INFO, "[MapEditor] 保存: 总层数=" .. mapEditor.totalFloors .. ", 有数据的层=" .. floorCount)
    -- 打印第1层前3行用于验证
    if data.floors["1"] then
        for i = 1, math.min(3, #data.floors["1"]) do
            log:Write(LOG_INFO, "[MapEditor] 第1层第" .. i .. "行: " .. data.floors["1"][i])
        end
    end
    local encOk, jsonStr = pcall(_cjson.encode, data)
    if not encOk then
        log:Write(LOG_ERROR, "[MapEditor] JSON编码失败: " .. tostring(jsonStr))
        editorShowMessage("保存失败：JSON编码错误")
        return
    end
    log:Write(LOG_INFO, "[MapEditor] JSON长度=" .. #jsonStr)
    local file = File("edited_maps.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
        -- 立即回读验证
        local vf = File("edited_maps.json", FILE_READ)
        if vf:IsOpen() then
            local vstr = vf:ReadString()
            vf:Close()
            log:Write(LOG_INFO, "[MapEditor] 回读验证: 长度=" .. #vstr .. ", 匹配=" .. tostring(#vstr == #jsonStr))
        else
            log:Write(LOG_WARNING, "[MapEditor] 回读验证失败: 无法打开文件")
        end
        editorShowMessage("已保存 " .. mapEditor.totalFloors .. " 层地图")
    else
        log:Write(LOG_ERROR, "[MapEditor] 文件打开写入失败")
        editorShowMessage("保存失败：无法写入文件")
    end
end

--- 从沙盒 JSON 文件加载编辑地图
function editorLoadSavedMaps()
    local exists = fileSystem:FileExists("edited_maps.json")
    log:Write(LOG_INFO, "[MapEditor] 加载: fileExists=" .. tostring(exists))
    if not exists then return false end
    local file = File("edited_maps.json", FILE_READ)
    if not file:IsOpen() then
        log:Write(LOG_ERROR, "[MapEditor] 加载: 文件无法打开")
        return false
    end
    local str = file:ReadString()
    file:Close()
    log:Write(LOG_INFO, "[MapEditor] 加载: 读取长度=" .. (str and #str or 0))
    if not str or str == "" then return false end
    local ok, data = pcall(_cjson.decode, str)
    if not ok or not data then
        log:Write(LOG_ERROR, "[MapEditor] 加载: JSON解码失败: " .. tostring(data))
        return false
    end
    mapEditor.totalFloors = data.totalFloors or 25
    mapEditor.floors = {}  -- 清空旧数据，避免新旧混杂
    local loadedCount = 0
    for fStr, lines in pairs(data.floors or {}) do
        local f = tonumber(fStr)
        if f then
            mapEditor.floors[f] = editorStringsToGrid(lines)
            loadedCount = loadedCount + 1
        end
    end
    -- 打印第1层前3行用于验证
    if mapEditor.floors[1] then
        for i = 1, math.min(3, GRID) do
            local row = ""
            for c = 1, GRID do row = row .. mapEditor.floors[1][i][c] end
            log:Write(LOG_INFO, "[MapEditor] 加载第1层第" .. i .. "行: " .. row)
        end
    end
    log:Write(LOG_INFO, "[MapEditor] 加载完成: " .. loadedCount .. " 层")
    mapEditor.floor = 1  -- 重置到第1层
    return true
end

--- 导出地图JSON（与 data/map.json 同格式）
--- 同时写入沙箱文件 + 日志，AI助手可从反馈日志中自动提取
function editorExportJson()
    local data = {
        totalFloors = mapEditor.totalFloors,
        grid = GRID,
        maps = {}
    }
    local floorCount = 0
    for f = 1, mapEditor.totalFloors do
        if mapEditor.floors[f] then
            local lines = editorGridToStrings(mapEditor.floors[f])
            table.insert(data.maps, { floor = f, data = lines })
            floorCount = floorCount + 1
        end
    end
    local encOk, jsonStr = pcall(_cjson.encode, data)
    if not encOk then
        editorShowMessage("导出失败：JSON编码错误")
        return
    end

    -- 1. 写入沙箱文件（可被AI助手通过反馈系统读取）
    local file = File("map_export.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
        log:Write(LOG_INFO, "[MapEditor] 已写入 map_export.json (" .. #jsonStr .. " bytes)")
    end

    -- 2. 同时写入日志（备用提取方式）
    log:Write(LOG_INFO, "[MAP_EXPORT:START]")
    local chunkSize = 4000
    for i = 1, #jsonStr, chunkSize do
        log:Write(LOG_INFO, "[MAP_EXPORT]" .. jsonStr:sub(i, i + chunkSize - 1))
    end
    log:Write(LOG_INFO, "[MAP_EXPORT:END]")

    editorShowMessage("已导出 " .. floorCount .. " 层到 map_export.json\n告诉AI助手: '帮我更新地图'")
end

--- 绘制编辑器中的单个瓦片方块（复用主游戏精灵渲染）
--- @param x number 目标X
--- @param y number 目标Y
--- @param s number 方块尺寸
--- @param ch string 瓦片字符
--- @param selected boolean 是否选中状态
function editorDrawTileBlock(x, y, s, ch, selected)
    local margin = s * 0.03
    local dw = s - margin * 2
    local dh = s - margin * 2
    local dx = x + margin
    local dy = y + margin
    local animSX = ANIM_FRAMES[animFrameIndex] * SPRITE_FRAME_W

    -- 地板背景
    if spr.stair then
        drawSpriteRegion(spr.stair, spr.stairW, spr.stairH,
            3 * SPRITE_FRAME_W, 1 * SPRITE_FRAME_H, SPRITE_FRAME_W, SPRITE_FRAME_H,
            x, y, s, s)
    else
        drawRoundRect(x, y, s, s, 0, 45, 42, 60)
    end

    -- 空地不需要绘制任何东西
    if ch == "." then
        -- 仅显示地板
    elseif ch == "P" then
        -- 起点：绿色标记
        local r2 = s * 0.3
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, x + s / 2, y + s / 2, r2)
        nvgFillColor(nvgCtx, nvgRGBA(50, 200, 50, 200))
        nvgFill(nvgCtx)
        drawTextCenter("P", x + s / 2, y + s / 2, math.max(8, s * 0.4), 255, 255, 255)
    elseif ch == "W" then
        -- 墙壁
        if spr.wall then
            drawSpriteRegion(spr.wall, spr.wallW, spr.wallH,
                0, 0, SPRITE_FRAME_W, SPRITE_FRAME_H, x, y, s, s)
        else
            drawRoundRect(x, y, s, s, 1, 85, 75, 105)
        end
    elseif ch == "U" then
        -- 上楼
        if spr.stair then
            drawSpriteRegion(spr.stair, spr.stairW, spr.stairH,
                336, 288, SPRITE_FRAME_W, SPRITE_FRAME_H, dx, dy, dw, dh)
        else
            drawRoundRect(dx, dy, dw, dh, 3, 80, 180, 80)
            drawTextCenter("\u{2B06}", x + s / 2, y + s / 2, math.max(8, s * 0.4), 255, 255, 255)
        end
    elseif ch == "D" then
        -- 下楼
        if spr.stair then
            drawSpriteRegion(spr.stair, spr.stairW, spr.stairH,
                288, 288, SPRITE_FRAME_W, SPRITE_FRAME_H, dx, dy, dw, dh)
        else
            drawRoundRect(dx, dy, dw, dh, 3, 180, 140, 80)
            drawTextCenter("\u{2B07}", x + s / 2, y + s / 2, math.max(8, s * 0.4), 255, 255, 255)
        end
    elseif isMonster(ch) then
        -- 怪物
        local m = MONSTER_DEF[ch]
        local spriteData = m.sprite and spriteImages[m.sprite]
        if spriteData then
            local sy = (m.spriteRow or 0) * SPRITE_FRAME_H
            drawSpriteRegion(spriteData.handle, spriteData.w, spriteData.h,
                animSX, sy, SPRITE_FRAME_W, SPRITE_FRAME_H, dx, dy, dw, dh)
        else
            local inner = s * 0.3
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, x + s / 2, y + s / 2, inner)
            nvgFillColor(nvgCtx, nvgRGBA(m.r, m.g, m.b, 255))
            nvgFill(nvgCtx)
            drawTextCenter(m.name:sub(1, 3), x + s / 2, y + s / 2, math.max(7, s * 0.3), 255, 255, 255)
        end
        -- 显示怪物数据（HP/ATK/DEF）
        local statFs = math.max(5, s * 0.18)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(nvgCtx, statFs)
        -- 背景条
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, x, y + dh - statFs * 1.3, s, statFs * 1.4)
        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 160))
        nvgFill(nvgCtx)
        -- 数据文字
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 220))
        local statTxt = m.hp .. "/" .. m.atk .. "/" .. m.def
        nvgText(nvgCtx, x + s / 2, y + dh - statFs * 1.2, statTxt)
    elseif isKey(ch) then
        -- 钥匙
        local keyColMap = { ["y"] = 0, ["b"] = 1, ["r"] = 2 }
        local kc = keyColMap[ch]
        if spr.key and kc then
            drawSpriteRegion(spr.key, spr.keyW, spr.keyH,
                kc * SPRITE_FRAME_W, 0, SPRITE_FRAME_W, SPRITE_FRAME_H, dx, dy, dw, dh)
        else
            local k = KEY_DEF[ch]
            drawRoundRect(dx, dy, dw, dh, 3, k.r, k.g, k.b)
            drawTextCenter("K", x + s / 2, y + s / 2, math.max(7, s * 0.3), 255, 255, 255)
        end
    elseif isDoor(ch) then
        -- 门
        local doorColMap = { Y = 0, B = 1, R = 2 }
        local dc = doorColMap[ch] or 0
        if spr.door then
            drawSpriteRegion(spr.door, spr.doorW, spr.doorH,
                dc * SPRITE_FRAME_W, 0, SPRITE_FRAME_W, SPRITE_FRAME_H, x, y, s, s)
        else
            local d = DOOR_DEF[ch]
            drawRoundRect(x, y, s, s, 3, d.r, d.g, d.b, 240)
        end
    elseif isItem(ch) then
        -- 物品
        local itemDef = ITEM_DEF[ch]
        if itemDef and itemDef.sprite and spr.gemStones then
            -- 新宝石系列：使用 $2 (4).png
            local gemCols = 3
            local gemFrameW = spr.gemStonesW / gemCols
            local gemFrameH = spr.gemStonesH / 4
            drawSpriteRegion(spr.gemStones, spr.gemStonesW, spr.gemStonesH,
                (itemDef.spriteCol or 0) * gemFrameW, (itemDef.spriteRow or 0) * gemFrameH,
                gemFrameW, gemFrameH, dx, dy, dw, dh)
        elseif spr.item then
            local itemFrameMap = {
                ["a"] = {col = 0, row = 0},
                ["d"] = {col = 1, row = 0},
                ["h"] = {col = 0, row = 1},
                ["H"] = {col = 1, row = 1},
                ["z"] = {col = 2, row = 1},
            }
            local frame = itemFrameMap[ch]
            if frame then
                drawSpriteRegion(spr.item, spr.itemW, spr.itemH,
                    frame.col * SPRITE_FRAME_W, frame.row * SPRITE_FRAME_H,
                    SPRITE_FRAME_W, SPRITE_FRAME_H, dx, dy, dw, dh)
            else
                local ti = mapEditor.tileInfo[ch]
                if ti then
                    drawRoundRect(dx, dy, dw, dh, 3, ti.r, ti.g, ti.b)
                    drawTextCenter(ti.name, x + s / 2, y + s / 2, math.max(7, s * 0.28), 255, 255, 255)
                end
            end
        else
            local ti = mapEditor.tileInfo[ch]
            if ti then
                drawRoundRect(dx, dy, dw, dh, 3, ti.r, ti.g, ti.b)
                drawTextCenter(ti.name, x + s / 2, y + s / 2, math.max(7, s * 0.28), 255, 255, 255)
            end
        end
    elseif ch == SHOP_NPC_CHAR then
        -- 商店
        local r2 = s * 0.35
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, x + s / 2, y + s / 2, r2)
        nvgFillColor(nvgCtx, nvgRGBA(60, 40, 20, 220))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 80, 200))
        nvgStrokeWidth(nvgCtx, math.max(1, s * 0.04))
        nvgStroke(nvgCtx)
        drawTextCenter("$", x + s / 2, y + s / 2, math.max(8, s * 0.4), 255, 220, 80)
    else
        -- 技能/宝石/遗物等：色块 + 文字
        local ti = mapEditor.tileInfo[ch]
        if ti then
            local r2 = s * 0.32
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, x + s / 2, y + s / 2, r2)
            nvgFillColor(nvgCtx, nvgRGBA(math.floor(ti.r * 0.4), math.floor(ti.g * 0.4), math.floor(ti.b * 0.4), 220))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(ti.r, ti.g, ti.b, 200))
            nvgStrokeWidth(nvgCtx, math.max(1, s * 0.04))
            nvgStroke(nvgCtx)
            drawTextCenter(ti.name:sub(1, 3), x + s / 2, y + s / 2, math.max(7, s * 0.3), ti.r, ti.g, ti.b)
        else
            drawRoundRect(dx, dy, dw, dh, 2, 100, 100, 100)
            drawTextCenter(ch, x + s / 2, y + s / 2, math.max(7, s * 0.3), 255, 255, 255)
        end
    end

    -- 选中高亮边框
    if selected then
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, x, y, s, s)
        nvgStrokeColor(nvgCtx, nvgRGBA(255, 255, 100, 220))
        nvgStrokeWidth(nvgCtx, math.max(2, s * 0.06))
        nvgStroke(nvgCtx)
    end
end

--- 绘制编辑器界面
function drawEditorScreen()
    -- 背景
    drawRoundRect(0, 0, logicalW, logicalH, 0, 18, 16, 30)

    -- 如果尚未加载地图，自动加载
    if not mapEditor.loaded then
        -- 先尝试加载沙盒中已保存的地图
        if not editorLoadSavedMaps() then
            editorLoadMaps()
        else
            mapEditor.loaded = true
            editorShowMessage("已加载保存的编辑地图")
        end
    end

    -- 布局计算
    local pad = math.max(4, logicalW * 0.01)
    local toolbarH = math.max(36, logicalH * 0.065)
    local tabBarH = math.max(30, logicalH * 0.045)
    local paletteH = math.max(50, logicalH * 0.14)
    local msgH = math.max(20, logicalH * 0.035)
    local gridAreaH = logicalH - toolbarH - tabBarH - paletteH - msgH - pad * 2
    local cs = math.floor(math.min(gridAreaH / GRID, (logicalW - pad * 2) / GRID))
    local gridTotalW = cs * GRID
    local gridTotalH = cs * GRID
    local gx = math.floor((logicalW - gridTotalW) / 2)
    local gy = math.floor(toolbarH + (gridAreaH - gridTotalH) / 2)
    mapEditor.gridRects = {x = gx, y = gy, cellSize = cs}

    -- ========== 工具栏 ==========
    drawRoundRect(0, 0, logicalW, toolbarH, 0, 30, 25, 50, 240)
    local tbFs = math.max(11, toolbarH * 0.38)
    local tbSmFs = math.max(9, toolbarH * 0.30)
    mapEditor.toolbarRects = {}

    -- 标题
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvgCtx, tbFs)
    nvgFillColor(nvgCtx, nvgRGBA(220, 200, 255, 255))
    nvgText(nvgCtx, pad + 4, toolbarH / 2, "地图编辑器")

    -- 层数显示和切换
    local floorText = mapEditor.floor .. "/" .. mapEditor.totalFloors .. "F"
    local floorX = logicalW * 0.38
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvgCtx, tbFs)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 140, 255))
    nvgText(nvgCtx, floorX, toolbarH / 2, floorText)

    -- 累计ATK/DEF预估（假设前面层全吃）- 显示在"地图编辑器"文字下方
    local cumAtk, cumDef, cumHp = 10, 10, 1000  -- 基础属性
    for f = 1, mapEditor.floor do
        local grid = mapEditor.floors[f]
        if grid then
            for r = 1, GRID do
                for c = 1, GRID do
                    local ch = grid[r][c]
                    local item = ITEM_DEF[ch]
                    if item then
                        if item.type == "atk" then cumAtk = cumAtk + item.amount
                        elseif item.type == "def" then cumDef = cumDef + item.amount
                        elseif item.type == "hp" then cumHp = cumHp + item.amount end
                    end
                end
            end
        end
    end
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, math.max(8, tbSmFs * 0.85))
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local statY = toolbarH / 2 + tbFs * 0.5
    nvgFillColor(nvgCtx, nvgRGBA(80, 255, 120, 220))
    nvgText(nvgCtx, pad + 4, statY, "HP:" .. cumHp)
    local hpW = nvgTextBounds(nvgCtx, 0, 0, "HP:" .. cumHp)
    nvgFillColor(nvgCtx, nvgRGBA(255, 120, 80, 220))
    nvgText(nvgCtx, pad + 4 + hpW + 6, statY, "A:" .. cumAtk)
    local atkW = nvgTextBounds(nvgCtx, 0, 0, "A:" .. cumAtk)
    nvgFillColor(nvgCtx, nvgRGBA(80, 160, 255, 220))
    nvgText(nvgCtx, pad + 4 + hpW + 6 + atkW + 6, statY, "D:" .. cumDef)

    -- < > 按钮
    local arrowW = math.max(24, toolbarH * 0.7)
    local arrowH = math.max(22, toolbarH * 0.6)
    local arrowY = (toolbarH - arrowH) / 2

    local prevX = floorX - 50 - arrowW
    drawRoundRect(prevX, arrowY, arrowW, arrowH, 4, 60, 50, 90)
    drawTextCenter("<", prevX + arrowW / 2, arrowY + arrowH / 2, tbSmFs, 200, 200, 220)
    mapEditor.toolbarRects.prevFloor = {x = prevX, y = arrowY, w = arrowW, h = arrowH}

    local nextX = floorX + 50
    drawRoundRect(nextX, arrowY, arrowW, arrowH, 4, 60, 50, 90)
    drawTextCenter(">", nextX + arrowW / 2, arrowY + arrowH / 2, tbSmFs, 200, 200, 220)
    mapEditor.toolbarRects.nextFloor = {x = nextX, y = arrowY, w = arrowW, h = arrowH}

    -- 右侧按钮组
    local btnW = math.max(32, logicalW * 0.08)
    local btnH2 = math.max(22, toolbarH * 0.58)
    local btnY2 = (toolbarH - btnH2) / 2
    local btnGap2 = math.max(4, logicalW * 0.01)
    local rightX = logicalW - pad - 4

    -- 返回按钮
    rightX = rightX - btnW
    drawRoundRect(rightX, btnY2, btnW, btnH2, 4, 140, 50, 50)
    drawTextCenter("返回", rightX + btnW / 2, btnY2 + btnH2 / 2, tbSmFs, 255, 220, 220)
    mapEditor.toolbarRects.back = {x = rightX, y = btnY2, w = btnW, h = btnH2}

    -- 保存按钮
    rightX = rightX - btnW - btnGap2
    drawRoundRect(rightX, btnY2, btnW, btnH2, 4, 50, 120, 60)
    drawTextCenter("保存", rightX + btnW / 2, btnY2 + btnH2 / 2, tbSmFs, 200, 255, 200)
    mapEditor.toolbarRects.save = {x = rightX, y = btnY2, w = btnW, h = btnH2}

    -- 导出按钮
    rightX = rightX - btnW - btnGap2
    drawRoundRect(rightX, btnY2, btnW, btnH2, 4, 50, 90, 130)
    drawTextCenter("导出", rightX + btnW / 2, btnY2 + btnH2 / 2, tbSmFs, 180, 220, 255)
    mapEditor.toolbarRects.exportJson = {x = rightX, y = btnY2, w = btnW, h = btnH2}

    -- 撤销按钮
    rightX = rightX - btnW - btnGap2
    local undoAlpha = #mapEditor.undoStack > 0 and 255 or 120
    drawRoundRect(rightX, btnY2, btnW, btnH2, 4, 100, 80, 50)
    drawTextCenter("撤销", rightX + btnW / 2, btnY2 + btnH2 / 2, tbSmFs, 255, 220, 160, undoAlpha)
    mapEditor.toolbarRects.undo = {x = rightX, y = btnY2, w = btnW, h = btnH2}

    -- 清空按钮
    rightX = rightX - btnW - btnGap2
    drawRoundRect(rightX, btnY2, btnW, btnH2, 4, 80, 60, 100)
    drawTextCenter("清空", rightX + btnW / 2, btnY2 + btnH2 / 2, tbSmFs, 200, 180, 220)
    mapEditor.toolbarRects.clear = {x = rightX, y = btnY2, w = btnW, h = btnH2}

    -- ========== 网格区 ==========
    local grid = editorGetGrid()
    -- 网格背景
    drawRoundRect(gx - 2, gy - 2, gridTotalW + 4, gridTotalH + 4, 4, 35, 30, 55, 200)
    for r = 1, GRID do
        for c = 1, GRID do
            local tx = gx + (c - 1) * cs
            local ty = gy + (r - 1) * cs
            editorDrawTileBlock(tx, ty, cs, grid[r][c], false)
            -- 网格线
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, tx, ty, cs, cs)
            nvgStrokeColor(nvgCtx, nvgRGBA(80, 70, 110, 60))
            nvgStrokeWidth(nvgCtx, 0.5)
            nvgStroke(nvgCtx)
        end
    end

    -- ========== 标签栏 ==========
    local tabBarY = gy + gridTotalH + pad
    drawRoundRect(0, tabBarY, logicalW, tabBarH, 0, 28, 24, 48, 220)
    mapEditor.tabRects = {}
    local tabW = math.floor((logicalW - pad * 2) / #mapEditor.tabs)
    local tabFs = math.max(9, tabBarH * 0.48)
    for ti = 1, #mapEditor.tabs do
        local tx = pad + (ti - 1) * tabW
        local isSel = (mapEditor.tab == ti)
        if isSel then
            drawRoundRect(tx + 2, tabBarY + 2, tabW - 4, tabBarH - 4, 4, 70, 55, 120)
        end
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(nvgCtx, tabFs)
        if isSel then
            nvgFillColor(nvgCtx, nvgRGBA(255, 230, 180, 255))
        else
            nvgFillColor(nvgCtx, nvgRGBA(160, 150, 180, 200))
        end
        nvgText(nvgCtx, tx + tabW / 2, tabBarY + tabBarH / 2, mapEditor.tabs[ti].name)
        mapEditor.tabRects[ti] = {x = tx, y = tabBarY, w = tabW, h = tabBarH}
    end

    -- ========== 调色板 ==========
    local palY = tabBarY + tabBarH + 2
    local palH = logicalH - palY - msgH
    drawRoundRect(0, palY, logicalW, palH, 0, 22, 18, 38, 220)
    mapEditor.paletteRects = {}

    local tiles = mapEditor.tabs[mapEditor.tab].tiles
    local maxPalTile = math.min(math.max(28, palH * 0.65), 64)
    local palCols = math.max(1, math.floor((logicalW - pad * 2) / (maxPalTile + 4)))
    local palTileS = math.min(maxPalTile, (logicalW - pad * 2) / palCols - 4)
    local palRows = math.ceil(#tiles / palCols)
    local palStartX = math.floor((logicalW - palCols * (palTileS + 4)) / 2) + 2
    local palStartY = palY + math.max(2, (palH - palRows * (palTileS + 4)) / 2) + 2

    for idx, tch in ipairs(tiles) do
        local pr = math.ceil(idx / palCols)
        local pc = ((idx - 1) % palCols) + 1
        local px = palStartX + (pc - 1) * (palTileS + 4)
        local py = palStartY + (pr - 1) * (palTileS + 4)
        local isBrush = (mapEditor.brush == tch)
        editorDrawTileBlock(px, py, palTileS, tch, isBrush)
        -- 瓦片名称标签（小字）
        local labelFs = math.max(6, palTileS * 0.22)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(nvgCtx, labelFs)
        nvgFillColor(nvgCtx, nvgRGBA(180, 170, 200, 200))
        local ti = mapEditor.tileInfo[tch]
        if ti then
            nvgText(nvgCtx, px + palTileS / 2, py + palTileS + 1, ti.name)
        end
        mapEditor.paletteRects[idx] = {x = px, y = py, w = palTileS, h = palTileS, tile = tch}
    end

    -- ========== 当前笔刷指示 ==========
    local brushInfo = mapEditor.tileInfo[mapEditor.brush]
    if brushInfo then
        local brushFs = math.max(9, msgH * 0.55)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(nvgCtx, brushFs)
        nvgFillColor(nvgCtx, nvgRGBA(180, 170, 200, 200))
        -- 怪物笔刷：显示详细数据
        local mdef = MONSTER_DEF[mapEditor.brush]
        if mdef then
            local skillTxt = ""
            if mdef.skill then skillTxt = " | " .. (mdef.skill.name or "") .. ":" .. (mdef.skill.desc or "") end
            local statTxt = string.format("%s [%s] HP:%d ATK:%d DEF:%d G:%d%s",
                mdef.name, mapEditor.brush, mdef.hp, mdef.atk, mdef.def, mdef.gold, skillTxt)
            nvgText(nvgCtx, pad + 4, logicalH - msgH / 2, statTxt)
        else
            local itemDef = ITEM_DEF[mapEditor.brush]
            if itemDef then
                nvgText(nvgCtx, pad + 4, logicalH - msgH / 2, "笔刷: " .. itemDef.name .. " (" .. itemDef.type .. "+" .. itemDef.amount .. ")")
            else
                nvgText(nvgCtx, pad + 4, logicalH - msgH / 2, "笔刷: " .. brushInfo.name .. " [" .. mapEditor.brush .. "]")
            end
        end
    end

    -- ========== 消息提示 ==========
    if mapEditor.msgTimer > 0 and mapEditor.message ~= "" then
        local msgAlpha = math.min(255, math.floor(mapEditor.msgTimer * 255))
        local msgFs2 = math.max(10, msgH * 0.6)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(nvgCtx, msgFs2)
        nvgFillColor(nvgCtx, nvgRGBA(100, 255, 100, msgAlpha))
        nvgText(nvgCtx, logicalW / 2, logicalH - msgH / 2, mapEditor.message)
    end
end

local UNDO_MAX = 200  -- 撤销栈上限

--- 推入一条撤销记录（自动限制栈深度）
function editorUndoPush(entry)
    table.insert(mapEditor.undoStack, entry)
    if #mapEditor.undoStack > UNDO_MAX then
        table.remove(mapEditor.undoStack, 1)
    end
end

--- 开始一组拖拽绘制（一次鼠标按下→拖拽→松开 = 一组）
function editorUndoBeginGroup()
    mapEditor.undoGroupOpen = true
    editorUndoPush({ type = "tiles", floor = mapEditor.floor, changes = {} })
end

--- 结束拖拽绘制组（移除空操作）
function editorUndoEndGroup()
    mapEditor.undoGroupOpen = false
    local stack = mapEditor.undoStack
    if #stack > 0 and stack[#stack].type == "tiles" and #stack[#stack].changes == 0 then
        table.remove(stack, #stack)
    end
end

--- 执行撤销
function editorUndo()
    local stack = mapEditor.undoStack
    if #stack == 0 then
        editorShowMessage("没有可撤销的操作")
        return
    end
    local entry = table.remove(stack, #stack)
    if entry.type == "tiles" then
        -- 还原单个瓦片变更
        if mapEditor.floor ~= entry.floor then
            mapEditor.floor = entry.floor
        end
        local grid = editorGetGrid()
        for i = #entry.changes, 1, -1 do
            local ch = entry.changes[i]
            grid[ch[1]][ch[2]] = ch[3]
        end
        editorShowMessage("撤销了 " .. #entry.changes .. " 个瓦片")
    elseif entry.type == "clearFloor" then
        -- 还原整层清空
        mapEditor.floors[entry.floor] = entry.oldGrid
        if mapEditor.floor ~= entry.floor then
            mapEditor.floor = entry.floor
        end
        editorShowMessage("撤销了清空第 " .. entry.floor .. " 层")
    end
end

--- 在网格中放置瓦片
function editorPlaceTile(lx, ly)
    local gr = mapEditor.gridRects
    if not gr then return end
    local gx2 = gr.x
    local gy2 = gr.y
    local cs2 = gr.cellSize
    local col = math.floor((lx - gx2) / cs2) + 1
    local row = math.floor((ly - gy2) / cs2) + 1
    if row >= 1 and row <= GRID and col >= 1 and col <= GRID then
        local grid = editorGetGrid()
        local oldCh = grid[row][col]
        if oldCh ~= mapEditor.brush then
            grid[row][col] = mapEditor.brush
            -- 记录到当前撤销组
            local stack = mapEditor.undoStack
            if mapEditor.undoGroupOpen and #stack > 0 and stack[#stack].type == "tiles" then
                table.insert(stack[#stack].changes, { row, col, oldCh })
            else
                -- 非拖拽的单次放置
                editorUndoPush({ type = "tiles", floor = mapEditor.floor, changes = { { row, col, oldCh } } })
            end
        end
    end
end

--- 处理编辑器点击
function handleEditorClick(lx, ly)
    -- 工具栏按钮
    local tb = mapEditor.toolbarRects
    if tb.back then
        local r = tb.back
        if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
            playSfx("btn", 0.5)
            gameState = "title"
            playTitleBgm()
            return
        end
    end
    if tb.save then
        local r = tb.save
        if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
            playSfx("btn", 0.5)
            editorSaveMaps()
            return
        end
    end
    if tb.exportJson then
        local r = tb.exportJson
        if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
            playSfx("btn", 0.5)
            editorExportJson()
            return
        end
    end
    if tb.undo then
        local r = tb.undo
        if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
            playSfx("btn", 0.5)
            editorUndo()
            return
        end
    end
    if tb.clear then
        local r = tb.clear
        if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
            playSfx("btn", 0.5)
            -- 记录清空前的整层数据用于撤销
            local oldGrid = editorGetGrid()
            local backup = {}
            for row = 1, GRID do
                backup[row] = {}
                for col = 1, GRID do
                    backup[row][col] = oldGrid[row][col]
                end
            end
            editorUndoPush({ type = "clearFloor", floor = mapEditor.floor, oldGrid = backup })
            mapEditor.floors[mapEditor.floor] = editorCreateEmptyGrid()
            editorShowMessage("已清空第 " .. mapEditor.floor .. " 层")
            return
        end
    end
    if tb.prevFloor then
        local r = tb.prevFloor
        if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
            playSfx("btn", 0.5)
            if mapEditor.floor > 1 then
                mapEditor.floor = mapEditor.floor - 1
            end
            return
        end
    end
    if tb.nextFloor then
        local r = tb.nextFloor
        if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
            playSfx("btn", 0.5)
            if mapEditor.floor < mapEditor.totalFloors then
                mapEditor.floor = mapEditor.floor + 1
            end
            return
        end
    end


    -- 标签栏
    for ti, tr in ipairs(mapEditor.tabRects) do
        if lx >= tr.x and lx <= tr.x + tr.w and ly >= tr.y and ly <= tr.y + tr.h then
            playSfx("btn", 0.5)
            mapEditor.tab = ti
            return
        end
    end

    -- 调色板
    for _, pr in ipairs(mapEditor.paletteRects) do
        if lx >= pr.x and lx <= pr.x + pr.w and ly >= pr.y and ly <= pr.y + pr.h then
            mapEditor.brush = pr.tile
            return
        end
    end

    -- 网格区域：放置瓦片并开始拖拽
    local gr = mapEditor.gridRects
    if gr then
        local gx2 = gr.x
        local gy2 = gr.y
        local cs2 = gr.cellSize
        if lx >= gx2 and lx < gx2 + cs2 * GRID and ly >= gy2 and ly < gy2 + cs2 * GRID then
            mapEditor.isDragging = true
            editorUndoBeginGroup()
            editorPlaceTile(lx, ly)
            return
        end
    end
end

--- 处理编辑器拖拽移动
function handleEditorMove(lx, ly)
    if mapEditor.isDragging then
        editorPlaceTile(lx, ly)
    end
end

--- 处理编辑器拖拽释放
function handleEditorRelease()
    if mapEditor.isDragging then
        editorUndoEndGroup()
    end
    mapEditor.isDragging = false
end

--- 绘制视频背景（cover模式铺满），返回是否成功绘制
function drawVideoBg()
    if not titleVideo or not titleVideo:IsReady() then return false end
    local tex = titleVideo:GetTexture()
    if not tex then return false end
    if not titleVideoImg and nvgCreateVideo then
        titleVideoImg = nvgCreateVideo(nvgCtx, tex)
    end
    if not titleVideoImg or titleVideoImg <= 0 then return false end
    local videoW = titleVideo:GetVideoWidth()
    local videoH = titleVideo:GetVideoHeight()
    local imgAspect = videoW / videoH
    local scrAspect = logicalW / logicalH
    local bgW, bgH
    if scrAspect > imgAspect then
        bgW = logicalW
        bgH = logicalW / imgAspect
    else
        bgH = logicalH
        bgW = logicalH * imgAspect
    end
    local bgX = (logicalW - bgW) / 2
    local bgY = (logicalH - bgH) / 2
    local bgPat = nvgImagePattern(nvgCtx, bgX, bgY, bgW, bgH, 0, titleVideoImg, 1.0)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, logicalW, logicalH)
    nvgFillPaint(nvgCtx, bgPat)
    nvgFill(nvgCtx)
    return true
end

--- 绘制标题画面
function drawTitleScreen()
    -- 背景：优先使用视频，回退到静态图
    if not drawVideoBg() then
        if spr.bgTitle then
            local imgAspect = spr.bgTitleW / spr.bgTitleH
            local scrAspect = logicalW / logicalH
            local bgW, bgH
            if scrAspect > imgAspect then
                bgW = logicalW
                bgH = logicalW / imgAspect
            else
                bgH = logicalH
                bgW = logicalH * imgAspect
            end
            local bgX = (logicalW - bgW) / 2
            local bgY = (logicalH - bgH) / 2
            local bgPat = nvgImagePattern(nvgCtx, bgX, bgY, bgW, bgH, 0, spr.bgTitle, 1.0)
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, 0, 0, logicalW, logicalH)
            nvgFillPaint(nvgCtx, bgPat)
            nvgFill(nvgCtx)
        else
            drawRoundRect(0, 0, logicalW, logicalH, 0, 12, 10, 25)
        end
    end

    local centerX = logicalW / 2
    local titleFs = math.max(24, math.min(logicalW * 0.09, 48))

    -- ====== 标题文字（厚涂风格） ======
    do
        local titleY = logicalH * 0.20
        local mainFs = math.max(36, math.min(logicalW * 0.16, 80))
        local titleStr = "纵 跃 魔 塔"
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 层1：远距离外发光（大范围柔光）
        nvgFontSize(nvgCtx, mainFs * 1.05)
        for _, off in ipairs({{0,-3},{0,3},{-3,0},{3,0},{-2,-2},{2,-2},{-2,2},{2,2}}) do
            nvgFillColor(nvgCtx, nvgRGBA(255, 140, 0, 40))
            nvgText(nvgCtx, centerX + off[1] * 2, titleY + off[2] * 2, titleStr)
        end

        -- 层2：黑色粗描边
        nvgFontSize(nvgCtx, mainFs)
        local strokeW = math.max(2, mainFs * 0.07)
        for angle = 0, 330, 30 do
            local rad = math.rad(angle)
            local ox = math.cos(rad) * strokeW
            local oy = math.sin(rad) * strokeW
            nvgFillColor(nvgCtx, nvgRGBA(10, 5, 0, 230))
            nvgText(nvgCtx, centerX + ox, titleY + oy, titleStr)
        end

        -- 层3：暗金内描边
        local innerStroke = strokeW * 0.5
        for angle = 0, 330, 45 do
            local rad = math.rad(angle)
            local ox = math.cos(rad) * innerStroke
            local oy = math.sin(rad) * innerStroke
            nvgFillColor(nvgCtx, nvgRGBA(160, 90, 10, 200))
            nvgText(nvgCtx, centerX + ox, titleY + oy, titleStr)
        end

        -- 层4：主体渐变色（金色→亮黄）
        nvgFillColor(nvgCtx, nvgRGBA(255, 210, 60, 255))
        nvgText(nvgCtx, centerX, titleY, titleStr)

        -- 层5：顶部高光
        nvgFillColor(nvgCtx, nvgRGBA(255, 250, 200, 80))
        nvgText(nvgCtx, centerX, titleY - 1, titleStr)

        -- ====== 英文副标题 ======
        local enFs = math.max(11, mainFs * 0.30)
        local enY = titleY + mainFs * 0.65
        local enStr = "VERTICAL  LEAP  TOWER"
        nvgFontSize(nvgCtx, enFs)

        -- 英文描边
        local enStroke = math.max(1, enFs * 0.08)
        for angle = 0, 315, 45 do
            local rad = math.rad(angle)
            nvgFillColor(nvgCtx, nvgRGBA(10, 5, 0, 200))
            nvgText(nvgCtx, centerX + math.cos(rad) * enStroke, enY + math.sin(rad) * enStroke, enStr)
        end

        -- 英文主体（淡金色）
        nvgFillColor(nvgCtx, nvgRGBA(220, 190, 130, 220))
        nvgText(nvgCtx, centerX, enY, enStr)

        -- ====== 装饰线 ======
        local lineW = mainFs * 1.8
        local lineY = enY + enFs * 0.9
        nvgBeginPath(nvgCtx)
        nvgMoveTo(nvgCtx, centerX - lineW / 2, lineY)
        nvgLineTo(nvgCtx, centerX + lineW / 2, lineY)
        nvgStrokeColor(nvgCtx, nvgRGBA(200, 160, 60, 100))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)
    end

    -- ====== 按钮区域（垂直居中于屏幕下半部分） ======
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local btnW = math.min(logicalW * 0.50, 220)
    local btnH = math.max(42, titleFs * 1.3)
    local btnFs = math.max(15, titleFs * 0.5)
    local hasSave = hasSaveFile()
    local btnGap = math.max(14, btnH * 0.4)
    -- 计算按钮组总高度，使其整体居中在屏幕 55%-75% 区域
    local totalBtnH = hasSave and (btnH * 2 + btnGap) or btnH
    local btnGroupY = logicalH * 0.65 - totalBtnH / 2

    local btnX = centerX - btnW / 2
    local btnY = btnGroupY

    -- 开始游戏按钮
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, btnX, btnY, btnW, btnH, 8)
    nvgFillColor(nvgCtx, nvgRGBA(240, 190, 50, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, btnX, btnY, btnW, btnH, 8)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 60, 100))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    nvgFontSize(nvgCtx, btnFs)
    nvgFillColor(nvgCtx, nvgRGBA(40, 20, 0, 255))
    nvgText(nvgCtx, centerX, btnY + btnH / 2, "开 始 游 戏")

    menuRects.title.startBtn = {x = btnX, y = btnY, w = btnW, h = btnH}
    menuRects.title.continueBtn = nil

    -- 继续游戏按钮（仅有存档时显示）
    if hasSave then
        local cBtnY = btnY + btnH + btnGap
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btnX, cBtnY, btnW, btnH, 8)
        nvgFillColor(nvgCtx, nvgRGBA(50, 100, 160, 230))
        nvgFill(nvgCtx)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btnX, cBtnY, btnW, btnH, 8)
        nvgStrokeColor(nvgCtx, nvgRGBA(100, 170, 240, 100))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)

        nvgFontSize(nvgCtx, btnFs)
        nvgFillColor(nvgCtx, nvgRGBA(220, 230, 255, 255))
        nvgText(nvgCtx, centerX, cBtnY + btnH / 2, "继 续 游 戏")
        menuRects.title.continueBtn = {x = btnX, y = cBtnY, w = btnW, h = btnH}
    end

    -- 图鉴 / 角色按钮（开发模式下额外显示编辑按钮）
    local smallBtnW = math.min(logicalW * 0.24, 100)
    local smallBtnH = math.max(30, btnH * 0.65)
    local smallBtnGap = math.max(6, logicalW * 0.02)
    local smallBtnCount = SHOW_EDITOR_BUTTON and 3 or 2
    local smallRowW = smallBtnW * smallBtnCount + smallBtnGap * (smallBtnCount - 1)
    local smallRowX = centerX - smallRowW / 2
    local smallBtnY = btnGroupY + totalBtnH + btnGap * 1.5
    local smallFs = math.max(11, btnFs * 0.7)
    menuRects.title.editorBtn = nil

    -- 图鉴按钮（左）
    local galleryBtnX = smallRowX
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, galleryBtnX, smallBtnY, smallBtnW, smallBtnH, 6)
    nvgFillColor(nvgCtx, nvgRGBA(60, 50, 80, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, galleryBtnX, smallBtnY, smallBtnW, smallBtnH, 6)
    nvgStrokeColor(nvgCtx, nvgRGBA(160, 140, 200, 180))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    nvgFontSize(nvgCtx, smallFs)
    nvgFillColor(nvgCtx, nvgRGBA(220, 210, 245, 255))
    nvgText(nvgCtx, galleryBtnX + smallBtnW / 2, smallBtnY + smallBtnH / 2, "图鉴")
    menuRects.title.galleryBtn = {x = galleryBtnX, y = smallBtnY, w = smallBtnW, h = smallBtnH}

    local charBtnX
    if SHOW_EDITOR_BUTTON then
        -- 编辑按钮（中，仅开发模式显示）
        local editorBtnX = smallRowX + smallBtnW + smallBtnGap
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, editorBtnX, smallBtnY, smallBtnW, smallBtnH, 6)
        nvgFillColor(nvgCtx, nvgRGBA(50, 65, 80, 255))
        nvgFill(nvgCtx)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, editorBtnX, smallBtnY, smallBtnW, smallBtnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(100, 180, 200, 180))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)
        nvgFontSize(nvgCtx, smallFs)
        nvgFillColor(nvgCtx, nvgRGBA(160, 220, 240, 255))
        nvgText(nvgCtx, editorBtnX + smallBtnW / 2, smallBtnY + smallBtnH / 2, "编辑")
        menuRects.title.editorBtn = {x = editorBtnX, y = smallBtnY, w = smallBtnW, h = smallBtnH}
        charBtnX = smallRowX + (smallBtnW + smallBtnGap) * 2
    else
        charBtnX = smallRowX + smallBtnW + smallBtnGap
    end

    -- 角色按钮（右）
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, charBtnX, smallBtnY, smallBtnW, smallBtnH, 6)
    nvgFillColor(nvgCtx, nvgRGBA(60, 50, 80, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, charBtnX, smallBtnY, smallBtnW, smallBtnH, 6)
    nvgStrokeColor(nvgCtx, nvgRGBA(200, 160, 80, 180))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    nvgFontSize(nvgCtx, smallFs)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 160, 255))
    nvgText(nvgCtx, charBtnX + smallBtnW / 2, smallBtnY + smallBtnH / 2, "角色")
    menuRects.title.charBtn = {x = charBtnX, y = smallBtnY, w = smallBtnW, h = smallBtnH}

    -- 底部 Game Jam 说明（带边框）
    local noteFs = math.max(9, logicalH * 0.022)
    local noteW = math.min(logicalW * 0.7, 260)
    local noteH = noteFs * 3.2
    local noteX = centerX - noteW / 2
    local noteY = logicalH * 0.87

    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, noteX, noteY, noteW, noteH, 6)
    nvgFillColor(nvgCtx, nvgRGBA(20, 15, 30, 160))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(180, 150, 80, 140))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    nvgFontSize(nvgCtx, noteFs)
    nvgFillColor(nvgCtx, nvgRGBA(220, 190, 120, 220))
    nvgText(nvgCtx, centerX, noteY + noteH * 0.35, "21天制造新星 GameJam 作品")
    nvgFontSize(nvgCtx, noteFs * 0.85)
    nvgFillColor(nvgCtx, nvgRGBA(160, 150, 130, 180))
    nvgText(nvgCtx, centerX, noteY + noteH * 0.7, "内容持续完善中，感谢试玩！")
end

--- 绘制统一图鉴（标题页）
function drawCodex()
    if not codex.open then return end

    -- 统计各分类数量
    local cardCount = 0
    for _, cdef in pairs(CARD_DEF) do
        if (cdef.rarity and cdef.type ~= "item") or cdef.type == "curse" then cardCount = cardCount + 1 end
    end
    local itemCardCount = 0
    for _, cdef in pairs(CARD_DEF) do
        if cdef.type == "item" then itemCardCount = itemCardCount + 1 end
    end
    local monsterCount = 0
    for _ in pairs(MONSTER_DEF) do monsterCount = monsterCount + 1 end
    local gemCount = 0
    for _ in pairs(GEM_DEF) do gemCount = gemCount + 1 end
    local relicCount = 0
    for _ in pairs(SKILL_DEF) do relicCount = relicCount + 1 end
    for _ in pairs(RELIC_DEF) do relicCount = relicCount + 1 end
    local CODEX_TABS = {"卡牌 " .. cardCount, "物品 " .. itemCardCount, "怪物 " .. monsterCount, "宝石 " .. gemCount, "遗物 " .. relicCount}

    -- 全屏遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 180)

    -- 面板参数（自适应大屏幕）
    local maxPanelW = logicalW > 800 and 720 or (logicalW > 500 and 560 or 420)
    local maxPanelH = logicalH > 700 and 750 or 600
    local panelW = math.min(logicalW * 0.92, maxPanelW)
    local panelH = math.min(logicalH * 0.88, maxPanelH)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2
    local titleH = math.max(32, panelH * 0.06)
    local tabH = math.max(30, panelH * 0.055)
    local footerH = 0

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 10, 25, 22, 45, 250)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(140, 120, 200, 180))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 标题
    local titleFs = math.max(14, titleH * 0.55)
    drawTextCenter("图 鉴", px + panelW / 2, py + titleH / 2, titleFs, 220, 200, 255)

    -- === Tab 栏 ===
    codex.tabRects = {}
    local tabY = py + titleH
    local tabW = math.floor((panelW - 20) / #CODEX_TABS)
    local tabFs = math.max(11, tabH * 0.48)
    for ti = 1, #CODEX_TABS do
        local tx = px + 10 + (ti - 1) * tabW
        local isSel = (codex.tab == ti)
        -- Tab 背景
        if isSel then
            drawRoundRect(tx, tabY, tabW, tabH, 0, 60, 50, 90, 255)
        end
        -- Tab 文字
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(nvgCtx, tabFs)
        nvgFillColor(nvgCtx, nvgRGBA(isSel and 255 or 160, isSel and 220 or 160, isSel and 80 or 180, 255))
        nvgText(nvgCtx, tx + tabW / 2, tabY + tabH / 2, CODEX_TABS[ti])
        -- 选中指示条
        if isSel then
            nvgBeginPath(nvgCtx)
            local indW = math.min(tabW * 0.5, 40)
            nvgRoundedRect(nvgCtx, tx + (tabW - indW) / 2, tabY + tabH - 3, indW, 3, 1.5)
            nvgFillColor(nvgCtx, nvgRGBA(255, 200, 60, 255))
            nvgFill(nvgCtx)
        end
        codex.tabRects[ti] = {x = tx, y = tabY, w = tabW, h = tabH}
    end
    -- Tab 底部分隔线
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, px + 10, tabY + tabH)
    nvgLineTo(nvgCtx, px + panelW - 10, tabY + tabH)
    nvgStrokeColor(nvgCtx, nvgRGBA(140, 120, 200, 80))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 内容区域
    local contentTop = tabY + tabH
    local contentH = panelH - titleH - tabH - footerH
    local totalContentH = 0

    -- === Tab 1: 卡牌 ===
    if codex.tab == 1 then
        codex.cardRects = {}
        codex.filterRects = {}

        -- 构建角色专属卡集合（每个角色独立）
        local charExclSets = {}  -- charExclSets[charIndex] = {cardId=true, ...}
        local allExclusive = {}  -- 所有角色专属卡的合集
        for ci, ch in ipairs(CHARACTER_LIST) do
            charExclSets[ci] = {}
            if ch.exclusive then
                for _, cid in ipairs(ch.exclusive) do
                    charExclSets[ci][cid] = true
                    allExclusive[cid] = true
                end
            end
        end

        -- 筛选按钮：全部 + 各角色名 + 通用
        -- filter值：0=全部, 1..N=角色index, N+1=通用
        local filterLabels = {"全部"}
        for _, ch in ipairs(CHARACTER_LIST) do
            table.insert(filterLabels, ch.name)
        end
        table.insert(filterLabels, "通用")
        local filterCount = #filterLabels
        local universalFilter = filterCount - 1  -- 通用的filter值

        local filterGap = 4
        local filterRowGap = 3
        -- 分两行：每行的按钮数量
        local row1Count = math.ceil(filterCount / 2)
        local row2Count = filterCount - row1Count
        local filterRowH = math.max(20, contentH * 0.04)
        local filterFs = math.max(9, filterRowH * 0.55)
        local filterBarH = filterRowH * 2 + filterRowGap + 6

        codex.filterRects = {}
        for row = 1, 2 do
            local rowStart = (row == 1) and 1 or (row1Count + 1)
            local rowEnd   = (row == 1) and row1Count or filterCount
            local rowN = rowEnd - rowStart + 1
            local btnW = math.max(36, math.floor((panelW - 12 - (rowN - 1) * filterGap) / rowN))
            local totalW = rowN * btnW + (rowN - 1) * filterGap
            local startX = px + (panelW - totalW) / 2
            local fy = contentTop + 3 + (row - 1) * (filterRowH + filterRowGap)
            for i = 0, rowN - 1 do
                local fi = rowStart + i
                local fx = startX + i * (btnW + filterGap)
                local filterVal = fi - 1
                local isSel = (codex.cardFilter == filterVal)
                if isSel then
                    drawRoundRect(fx, fy, btnW, filterRowH, 8, 100, 80, 180, 220)
                else
                    drawRoundRect(fx, fy, btnW, filterRowH, 8, 50, 40, 80, 140)
                end
                nvgFontFace(nvgCtx, "sans")
                nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(nvgCtx, filterFs)
                nvgFillColor(nvgCtx, isSel and nvgRGBA(255, 240, 200, 255) or nvgRGBA(160, 150, 180, 200))
                nvgText(nvgCtx, fx + btnW / 2, fy + filterRowH / 2, filterLabels[fi])
                codex.filterRects[fi] = {x = fx, y = fy, w = btnW, h = filterRowH, filter = filterVal}
            end
        end
        contentTop = contentTop + filterBarH
        contentH = contentH - filterBarH

        local rarityOrder = {"common", "uncommon", "rare", "epic", "legendary", "curse"}
        local groups = {}
        for _, r in ipairs(rarityOrder) do groups[r] = {} end
        for cid, cdef in pairs(CARD_DEF) do
            -- 筛选逻辑
            if codex.cardFilter > 0 then
                if codex.cardFilter == universalFilter then
                    -- 通用：排除所有角色专属卡
                    if allExclusive[cid] then goto continue end
                else
                    -- 特定角色：只显示该角色专属卡
                    if not charExclSets[codex.cardFilter] or not charExclSets[codex.cardFilter][cid] then goto continue end
                end
            end

            if cdef.type == "curse" then
                table.insert(groups["curse"], {id = cid, def = cdef})
            elseif cdef.rarity and cdef.type ~= "item" then
                table.insert(groups[cdef.rarity], {id = cid, def = cdef})
            end
            ::continue::
        end
        for _, r in ipairs(rarityOrder) do
            table.sort(groups[r], function(a, b) return a.def.name < b.def.name end)
        end

        local gap = 4
        local pad = 6
        local maxCols = logicalW > 800 and 8 or (logicalW > 500 and 6 or 5)
        -- 先按放大前尺寸算出原始列数，再用原始列数反推卡牌宽度以填满面板
        local baseCardH2 = math.floor(math.max(100, math.min(logicalH * 0.2, 145)))
        local baseCardW2 = math.floor(baseCardH2 * 0.68)
        local cols = math.max(2, math.min(maxCols, math.floor((panelW - pad * 2) / (baseCardW2 + gap))))
        -- 用确定的列数反推卡牌宽度，让卡牌填满面板
        local cardW2 = math.floor(((panelW - pad * 2) - (cols - 1) * gap) / cols)
        local cardH2 = math.floor(cardW2 / 0.68)
        local gridW = cols * cardW2 + (cols - 1) * gap
        local startX = px + (panelW - gridW) / 2
        local sectionGap = 6
        local labelH = math.max(22, cardH2 * 0.2)

        for _, r in ipairs(rarityOrder) do
            local grp = groups[r]
            if #grp > 0 then
                totalContentH = totalContentH + labelH + sectionGap
                local rows = math.ceil(#grp / cols)
                totalContentH = totalContentH + rows * (cardH2 + gap)
            end
        end
        totalContentH = totalContentH + 10

        local scrollMax = math.max(0, totalContentH - contentH)
        codex.scroll = math.max(0, math.min(codex.scroll, scrollMax))

        nvgSave(nvgCtx)
        nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)
        local curY = contentTop + 6 - codex.scroll

        for _, r in ipairs(rarityOrder) do
            local grp = groups[r]
            if #grp > 0 then
                local rd = RARITY_DEF[r]
                if curY + labelH > contentTop - labelH and curY < contentTop + contentH then
                    local labelFs = math.max(10, labelH * 0.55)
                    nvgFontFace(nvgCtx, "sans")
                    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFontSize(nvgCtx, labelFs)
                    nvgFillColor(nvgCtx, nvgRGBA(rd.r, rd.g, rd.b, 230))
                    nvgText(nvgCtx, startX + 2, curY + labelH / 2, rd.name .. " (" .. #grp .. ")")
                    nvgBeginPath(nvgCtx)
                    nvgMoveTo(nvgCtx, startX, curY + labelH - 2)
                    nvgLineTo(nvgCtx, startX + gridW, curY + labelH - 2)
                    nvgStrokeColor(nvgCtx, nvgRGBA(rd.r, rd.g, rd.b, 80))
                    nvgStrokeWidth(nvgCtx, 1)
                    nvgStroke(nvgCtx)
                end
                curY = curY + labelH + sectionGap
                for idx, card in ipairs(grp) do
                    local col = (idx - 1) % cols
                    local row = math.floor((idx - 1) / cols)
                    local cx = startX + col * (cardW2 + gap)
                    local cy = curY + row * (cardH2 + gap)
                    if cy + cardH2 >= contentTop and cy <= contentTop + contentH then
                        drawCard(cx, cy, cardW2, cardH2, {id = card.id}, card.id == codex.selectedCard, false)
                        table.insert(codex.cardRects, {id = card.id, x = cx, y = cy, w = cardW2, h = cardH2})
                    end
                end
                local rows = math.ceil(#grp / cols)
                curY = curY + rows * (cardH2 + gap)
            end
        end
        nvgRestore(nvgCtx)

        if scrollMax > 0 then
            local barH = math.max(20, contentH * (contentH / (totalContentH + 10)))
            local barY = contentTop + (contentH - barH) * (codex.scroll / scrollMax)
            drawRoundRect(px + panelW - 6, barY, 3, barH, 2, 140, 120, 200, 120)
        end

    -- === Tab 2: 怪物 ===
    elseif codex.tab == 2 then
        -- === Tab 2: 物品卡牌 ===
        local itemList = {}
        for cid, cdef in pairs(CARD_DEF) do
            if cdef.type == "item" then
                table.insert(itemList, {id = cid, def = cdef})
            end
        end
        table.sort(itemList, function(a, b) return a.def.name < b.def.name end)

        local cardW = math.min(panelW - 24, 380)
        local cardH = math.max(56, logicalH * 0.09)
        local gap = 8
        totalContentH = #itemList * (cardH + gap) + 20

        local scrollMax = math.max(0, totalContentH - contentH)
        codex.scroll = math.max(0, math.min(codex.scroll, scrollMax))

        nvgSave(nvgCtx)
        nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)
        local curY = contentTop + 6 - codex.scroll
        local startX = px + (panelW - cardW) / 2
        local fs = math.max(12, cardH * 0.3)

        for _, entry in ipairs(itemList) do
            if curY + cardH > contentTop - cardH and curY < contentTop + contentH then
                -- 背景
                drawRoundRect(startX, curY, cardW, cardH, 6, 40, 35, 55, 220)
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, startX, curY, cardW, cardH, 6)
                nvgStrokeColor(nvgCtx, nvgRGBA(entry.def.r or 180, entry.def.g or 180, entry.def.b or 180, 120))
                nvgStrokeWidth(nvgCtx, 1)
                nvgStroke(nvgCtx)
                -- 名称
                nvgFontFace(nvgCtx, "sans")
                nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFontSize(nvgCtx, fs)
                nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 255))
                nvgText(nvgCtx, startX + 12, curY + cardH * 0.35, entry.def.name)
                -- 描述
                nvgFontSize(nvgCtx, fs * 0.8)
                nvgFillColor(nvgCtx, nvgRGBA(200, 190, 220, 220))
                nvgText(nvgCtx, startX + 12, curY + cardH * 0.7, entry.def.desc or "")
            end
            curY = curY + cardH + gap
        end
        nvgRestore(nvgCtx)

    elseif codex.tab == 3 then
        -- 收集所有怪物并分组
        local normals, bosses = {}, {}
        for mid, mdef in pairs(MONSTER_DEF) do
            local entry = {id = mid, def = mdef}
            if mdef.boss then table.insert(bosses, entry) else table.insert(normals, entry) end
        end
        table.sort(normals, function(a, b) return a.def.hp < b.def.hp end)
        table.sort(bosses, function(a, b) return a.def.hp < b.def.hp end)

        local rowH = math.max(54, logicalH * 0.08)
        local labelH = math.max(22, rowH * 0.45)
        local sectionGap = 6
        totalContentH = labelH + sectionGap + #normals * rowH + 10
            + labelH + sectionGap + #bosses * rowH + 10

        local scrollMax = math.max(0, totalContentH - contentH)
        codex.scroll = math.max(0, math.min(codex.scroll, scrollMax))

        nvgSave(nvgCtx)
        nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)
        local curY = contentTop + 6 - codex.scroll
        local innerW = panelW - 24
        local startX = px + 12

        -- 绘制怪物分组
        local function drawMonsterGroup(title, list, titleR, titleG, titleB)
            -- 分组标签
            if curY + labelH > contentTop - 10 and curY < contentTop + contentH then
                local labelFs = math.max(10, labelH * 0.6)
                nvgFontFace(nvgCtx, "sans")
                nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFontSize(nvgCtx, labelFs)
                nvgFillColor(nvgCtx, nvgRGBA(titleR, titleG, titleB, 230))
                nvgText(nvgCtx, startX + 2, curY + labelH / 2, title .. " (" .. #list .. ")")
                nvgBeginPath(nvgCtx)
                nvgMoveTo(nvgCtx, startX, curY + labelH - 2)
                nvgLineTo(nvgCtx, startX + innerW, curY + labelH - 2)
                nvgStrokeColor(nvgCtx, nvgRGBA(titleR, titleG, titleB, 80))
                nvgStrokeWidth(nvgCtx, 1)
                nvgStroke(nvgCtx)
            end
            curY = curY + labelH + sectionGap

            local fs = math.max(10, rowH * 0.28)
            local smallFs = math.max(8, fs * 0.78)
            local tinyFs = math.max(7, fs * 0.65)
            for _, entry in ipairs(list) do
                if curY + rowH >= contentTop and curY <= contentTop + contentH then
                    local m = entry.def
                    -- 行背景
                    drawRoundRect(startX, curY, innerW, rowH - 2, 4, 35, 30, 55, 255)
                    -- BOSS 金色边框
                    if m.boss then
                        nvgBeginPath(nvgCtx)
                        nvgRoundedRect(nvgCtx, startX, curY, innerW, rowH - 2, 4)
                        nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 60, 180))
                        nvgStrokeWidth(nvgCtx, 1.5)
                        nvgStroke(nvgCtx)
                    end

                    -- 怪物精灵图
                    local sprSize = rowH - 6
                    local sprX = startX + 3
                    local sprY = curY + 1
                    local sprData = m.sprite and spriteImages[m.sprite]
                    if sprData then
                        local sy = (m.spriteRow or 0) * SPRITE_FRAME_H
                        drawSpriteRegion(sprData.handle, sprData.w, sprData.h,
                            0, sy, SPRITE_FRAME_W, SPRITE_FRAME_H,
                            sprX, sprY, sprSize, sprSize)
                    else
                        nvgBeginPath(nvgCtx)
                        nvgCircle(nvgCtx, sprX + sprSize / 2, sprY + sprSize / 2, sprSize * 0.35)
                        nvgFillColor(nvgCtx, nvgRGBA(m.r, m.g, m.b, 255))
                        nvgFill(nvgCtx)
                    end

                    -- 名称
                    local textLeft = startX + sprSize + 8
                    nvgFontFace(nvgCtx, "sans")
                    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFontSize(nvgCtx, fs)
                    nvgFillColor(nvgCtx, nvgRGBA(240, 240, 255, 255))
                    nvgText(nvgCtx, textLeft, curY + rowH * 0.22, m.name)

                    -- 属性行: HP / ATK / DEF
                    nvgFontSize(nvgCtx, smallFs)
                    local statX = textLeft
                    nvgFillColor(nvgCtx, nvgRGBA(255, 120, 120, 220))
                    nvgText(nvgCtx, statX, curY + rowH * 0.48, "HP:" .. m.hp)
                    statX = statX + innerW * 0.2
                    nvgFillColor(nvgCtx, nvgRGBA(255, 180, 80, 220))
                    nvgText(nvgCtx, statX, curY + rowH * 0.48, "ATK:" .. m.atk)
                    statX = statX + innerW * 0.2
                    nvgFillColor(nvgCtx, nvgRGBA(100, 180, 255, 220))
                    nvgText(nvgCtx, statX, curY + rowH * 0.48, "DEF:" .. m.def)

                    -- 第三行: 金币/经验 + 技能描述
                    nvgFontSize(nvgCtx, tinyFs)
                    local line3X = textLeft
                    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 80, 180))
                    nvgText(nvgCtx, line3X, curY + rowH * 0.74, "G:" .. (m.gold or 0))
                    line3X = line3X + innerW * 0.12
                    nvgFillColor(nvgCtx, nvgRGBA(120, 220, 160, 180))
                    nvgText(nvgCtx, line3X, curY + rowH * 0.74, "EXP:" .. (m.exp or 0))

                    -- 技能描述（第三行右侧）
                    if m.skill then
                        line3X = line3X + innerW * 0.16
                        nvgFillColor(nvgCtx, nvgRGBA(200, 180, 255, 200))
                        nvgText(nvgCtx, line3X, curY + rowH * 0.74, "[" .. m.skill.name .. "] " .. m.skill.desc)
                    end

                    -- 技能标签（右上角）
                    if m.skill then
                        nvgFontSize(nvgCtx, tinyFs)
                        local skillText = m.skill.name
                        local tw = nvgTextBounds(nvgCtx, 0, 0, skillText)
                        local tagW = tw + 8
                        local tagH = tinyFs + 4
                        local tagX = startX + innerW - tagW - 4
                        local tagY = curY + 3
                        drawRoundRect(tagX, tagY, tagW, tagH, 3, 80, 60, 120, 255)
                        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(nvgCtx, nvgRGBA(220, 200, 255, 255))
                        nvgText(nvgCtx, tagX + tagW / 2, tagY + tagH / 2, skillText)
                        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    end
                end
                curY = curY + rowH
            end
        end

        drawMonsterGroup("普通怪物", normals, 180, 200, 220)
        curY = curY + 10
        drawMonsterGroup("BOSS", bosses, 255, 100, 80)
        nvgRestore(nvgCtx)

        if scrollMax > 0 then
            local barH = math.max(20, contentH * (contentH / (totalContentH + 10)))
            local barY = contentTop + (contentH - barH) * (codex.scroll / scrollMax)
            drawRoundRect(px + panelW - 6, barY, 3, barH, 2, 140, 120, 200, 120)
        end

    -- === Tab 4: 宝石 ===
    elseif codex.tab == 4 then
        local gemList = {}
        for gid, gdef in pairs(GEM_DEF) do
            table.insert(gemList, {id = gid, def = gdef})
        end
        table.sort(gemList, function(a, b) return a.def.name < b.def.name end)

        local gemCardW = math.min(panelW - 24, 380)
        local gemCardH = math.max(56, logicalH * 0.09)
        local gap = 8
        local tipH = math.max(20, logicalH * 0.035)
        totalContentH = tipH + 6 + #gemList * (gemCardH + gap) + 20

        local scrollMax = math.max(0, totalContentH - contentH)
        codex.scroll = math.max(0, math.min(codex.scroll, scrollMax))

        nvgSave(nvgCtx)
        nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)
        local curY = contentTop + 6 - codex.scroll
        local startX = px + (panelW - gemCardW) / 2
        local fs = math.max(12, gemCardH * 0.3)
        local descFs = math.max(9, fs * 0.75)
        local iconSize = math.max(28, gemCardH * 0.5)

        -- 顶部说明
        if curY + tipH > contentTop - 10 and curY < contentTop + contentH then
            local tipFs = math.max(9, tipH * 0.6)
            nvgFontFace(nvgCtx, "sans")
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(nvgCtx, tipFs)
            nvgFillColor(nvgCtx, nvgRGBA(160, 150, 200, 180))
            nvgText(nvgCtx, px + panelW / 2, curY + tipH / 2, "镶嵌宝石的卡牌被消耗时，宝石效果仍会触发")
        end
        curY = curY + tipH + 6

        for _, gem in ipairs(gemList) do
            if curY + gemCardH >= contentTop and curY <= contentTop + contentH then
                local g = gem.def
                -- 卡片背景
                drawRoundRect(startX, curY, gemCardW, gemCardH, 6, 35, 30, 55, 255)
                -- 左侧边框色条
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, startX, curY, 4, gemCardH, 2)
                nvgFillColor(nvgCtx, nvgRGBA(g.r, g.g, g.b, 255))
                nvgFill(nvgCtx)

                -- 图标
                local iconX = startX + 8 + iconSize / 2
                local iconY = curY + gemCardH / 2
                if not (g.iconId and spr.drawIcon(g.iconId, iconX, iconY, iconSize, 1.0)) then
                    nvgFontFace(nvgCtx, "sans")
                    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFontSize(nvgCtx, iconSize * 0.7)
                    nvgFillColor(nvgCtx, nvgRGBA(g.r, g.g, g.b, 255))
                    nvgText(nvgCtx, iconX, iconY, g.icon)
                end

                -- 名称
                local textX = startX + 16 + iconSize
                nvgFontFace(nvgCtx, "sans")
                nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFontSize(nvgCtx, fs)
                nvgFillColor(nvgCtx, nvgRGBA(g.r, g.g, g.b, 255))
                nvgText(nvgCtx, textX, curY + gemCardH * 0.35, g.name)

                -- 效果描述
                nvgFontSize(nvgCtx, descFs)
                nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 230))
                nvgText(nvgCtx, textX, curY + gemCardH * 0.7, g.desc)
            end
            curY = curY + gemCardH + gap
        end
        nvgRestore(nvgCtx)

        if scrollMax > 0 then
            local barH = math.max(20, contentH * (contentH / (totalContentH + 10)))
            local barY = contentTop + (contentH - barH) * (codex.scroll / scrollMax)
            drawRoundRect(px + panelW - 6, barY, 3, barH, 2, 140, 120, 200, 120)
        end
    -- === Tab 5: 遗物 ===
    elseif codex.tab == 5 then
        local items = {}
        for k, s in pairs(SKILL_DEF) do
            table.insert(items, {key = k, name = s.name, desc = s.desc, icon = s.icon, iconId = s.iconId, r = s.r, g = s.g, b = s.b})
        end
        for k, r in pairs(RELIC_DEF) do
            table.insert(items, {key = k, name = r.name, desc = r.desc, icon = r.icon, iconId = r.iconId, r = r.r, g = r.g, b = r.b})
        end
        table.sort(items, function(a, b) return a.name < b.name end)

        local cardW = math.min(panelW - 24, 380)
        local cardH = math.max(56, logicalH * 0.09)
        local gap = 8
        totalContentH = #items * (cardH + gap) + 20

        local scrollMax = math.max(0, totalContentH - contentH)
        codex.scroll = math.max(0, math.min(codex.scroll, scrollMax))

        nvgSave(nvgCtx)
        nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)
        local curY = contentTop + 6 - codex.scroll
        local startX = px + (panelW - cardW) / 2
        local fs = math.max(12, cardH * 0.3)
        local descFs = math.max(9, fs * 0.75)
        local iconSize = math.max(28, cardH * 0.5)

        for _, it in ipairs(items) do
            if curY + cardH >= contentTop and curY <= contentTop + contentH then
                drawRoundRect(startX, curY, cardW, cardH, 6, 35, 30, 55, 255)
                -- 左侧色条
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, startX, curY, 4, cardH, 2)
                nvgFillColor(nvgCtx, nvgRGBA(it.r, it.g, it.b, 255))
                nvgFill(nvgCtx)

                -- 图标
                local iconX = startX + 8 + iconSize / 2
                local iconY = curY + cardH / 2
                if not (it.iconId and spr.drawIcon(it.iconId, iconX, iconY, iconSize, 1.0)) then
                    nvgFontFace(nvgCtx, "sans")
                    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFontSize(nvgCtx, iconSize * 0.7)
                    nvgFillColor(nvgCtx, nvgRGBA(it.r, it.g, it.b, 255))
                    nvgText(nvgCtx, iconX, iconY, it.icon)
                end

                -- 名称
                local textX = startX + 16 + iconSize
                nvgFontFace(nvgCtx, "sans")
                nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFontSize(nvgCtx, fs)
                nvgFillColor(nvgCtx, nvgRGBA(it.r, it.g, it.b, 255))
                nvgText(nvgCtx, textX, curY + cardH * 0.35, it.name)

                -- 描述（处理换行：只取第一行）
                local descText = it.desc:match("^([^\n]+)") or it.desc
                nvgFontSize(nvgCtx, descFs)
                nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 230))
                nvgText(nvgCtx, textX, curY + cardH * 0.7, descText)
            end
            curY = curY + cardH + gap
        end
        nvgRestore(nvgCtx)

        if scrollMax > 0 then
            local barH = math.max(20, contentH * (contentH / (totalContentH + 10)))
            local barY = contentTop + (contentH - barH) * (codex.scroll / scrollMax)
            drawRoundRect(px + panelW - 6, barY, 3, barH, 2, 140, 120, 200, 120)
        end
    end

    codex.panelRect = {x = px, y = py, w = panelW, h = panelH}

    -- === 选中卡牌放大预览 + 关键词 ===
    if codex.selectedCard then
        local selDef = CARD_DEF[codex.selectedCard]
        if selDef then
            -- 半透明遮罩
            drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 140)
            -- 放大卡牌
            local prevH = math.min(logicalH * 0.55, 300)
            local prevW = math.floor(prevH * 0.68)
            local prevX = (logicalW - prevW) / 2
            local prevY = (logicalH - prevH) / 2
            drawCard(prevX, prevY, prevW, prevH, {id = codex.selectedCard}, true, false)
            -- 关键词解释框（卡牌上方）
            local tips = collectKeywordTips(selDef)
            if #tips > 0 then
                local glossMaxW = math.min(math.max(prevW * 1.2, 180), logicalW - 20, 280)
                local glossX = prevX + (prevW - glossMaxW) / 2
                glossX = math.max(5, math.min(glossX, logicalW - glossMaxW - 5))
                local glossFs = math.max(10, prevH * 0.05)
                local glossBottomY = prevY - 6
                drawKeywordGlossary(tips, glossX, glossBottomY, glossMaxW, glossFs, true)
            end
            -- 提示文字（卡牌下方）
            local hintY = prevY + prevH + 10
            nvgFontFace(nvgCtx, "sans")
            nvgFontSize(nvgCtx, math.max(11, prevH * 0.045))
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 180))
            nvgText(nvgCtx, logicalW / 2, hintY, "点击任意处关闭")
        else
            codex.selectedCard = nil
        end
    end
end

--- 绘制模式选择界面
function drawGameBg()
    drawRoundRect(0, 0, logicalW, logicalH, 0, 15, 12, 30)
end

function drawModeSelect()
    if not drawVideoBg() then
        if spr.bgMode then
            local imgAspect = spr.bgModeW / spr.bgModeH
            local scrAspect = logicalW / logicalH
            local bgW, bgH
            if scrAspect > imgAspect then
                bgW = logicalW
                bgH = logicalW / imgAspect
            else
                bgH = logicalH
                bgW = logicalH * imgAspect
            end
            local bgX = (logicalW - bgW) / 2
            local bgY = (logicalH - bgH) / 2
            local bgPat = nvgImagePattern(nvgCtx, bgX, bgY, bgW, bgH, 0, spr.bgMode, 1.0)
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, 0, 0, logicalW, logicalH)
            nvgFillPaint(nvgCtx, bgPat)
            nvgFill(nvgCtx)
        else
            drawGameBg()
        end
    end

    menuRects.mode.modes = {}
    menuRects.mode.difficulties = {}
    menuRects.mode.nextBtn = nil
    menuRects.mode.backBtn = nil

    local centerX = logicalW / 2
    local titleFs = math.max(18, math.min(logicalW * 0.065, 32))

    -- 外围阴影面板（全屏，四周留10px）
    do
        local panelMargin = 10
        local panelX = panelMargin
        local panelY = panelMargin
        local panelW = logicalW - panelMargin * 2
        local panelH = logicalH - panelMargin * 2
        local panelR = 14
        -- 阴影层
        local shadowOff = 6
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + shadowOff, panelY + shadowOff, panelW, panelH, panelR)
        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 100))
        nvgFill(nvgCtx)
        -- 面板主体
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, panelR)
        nvgFillColor(nvgCtx, nvgRGBA(20, 16, 35, 200))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(120, 110, 160, 120))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
    end

    -- 标题
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvgCtx, titleFs)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 80, 255))
    nvgText(nvgCtx, centerX, logicalH * 0.10, "选择模式")

    -- 模式卡片
    local cardW = math.min(logicalW * 0.38, 170)
    local cardH = math.max(88, logicalH * 0.28)
    local gap = math.max(12, logicalW * 0.04)
    local modeLabels = {"随机地图", "固定地图"}
    local modeDescs  = {"敬请期待", "经典固定地图\n探索每一层的奥秘"}
    local modeIcons  = {"🎲", "📋"}
    local modeIconIds = {"mode_random", "mode_fixed"}
    local modeColors = {{120, 180, 255}, {180, 220, 100}}

    for m = 1, 2 do
        local mx = centerX + (m == 1 and -(cardW + gap / 2) or (gap / 2))
        local my = logicalH * 0.20
        local isDisabled = (m == 1)  -- 随机地图敬请期待
        local isSel = (charSelect.selectedMode == m) and not isDisabled
        local mc = modeColors[m]

        -- 卡片背景
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, mx, my, cardW, cardH, 8)
        if isDisabled then
            nvgFillColor(nvgCtx, nvgRGBA(30, 28, 38, 255))
        elseif isSel then
            nvgFillColor(nvgCtx, nvgRGBA(math.floor(mc[1] * 0.15 + 25), math.floor(mc[2] * 0.15 + 20), math.floor(mc[3] * 0.15 + 40), 255))
        else
            nvgFillColor(nvgCtx, nvgRGBA(35, 30, 50, 255))
        end
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(mc[1], mc[2], mc[3], isDisabled and 50 or (isSel and 255 or 120)))
        nvgStrokeWidth(nvgCtx, isSel and 2.5 or 1)
        nvgStroke(nvgCtx)

        -- 选中标记
        if isSel then
            local checkR = math.max(8, cardW * 0.07)
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, mx + cardW - checkR - 6, my + checkR + 6, checkR)
            nvgFillColor(nvgCtx, nvgRGBA(mc[1], mc[2], mc[3], 255))
            nvgFill(nvgCtx)
            local ckFs = math.max(8, checkR * 1.2)
            nvgFontSize(nvgCtx, ckFs)
            nvgFillColor(nvgCtx, nvgRGBA(20, 20, 30, 255))
            nvgText(nvgCtx, mx + cardW - checkR - 6, my + checkR + 6, "✓")
        end

        -- 图标（优先图片，回退 emoji）
        local iconFs = math.max(24, cardH * 0.25)
        local iconSize = math.max(36, cardH * 0.32)
        local iconAlpha = isDisabled and 0.3 or (isSel and 1.0 or 0.7)
        if not spr.drawIcon(modeIconIds[m], mx + cardW / 2, my + cardH * 0.30, iconSize, iconAlpha) then
            nvgFontSize(nvgCtx, iconFs)
            nvgFillColor(nvgCtx, nvgRGBA(mc[1], mc[2], mc[3], isDisabled and 80 or (isSel and 255 or 180)))
            nvgText(nvgCtx, mx + cardW / 2, my + cardH * 0.30, modeIcons[m])
        end

        -- 标签
        local lblFs = math.max(12, titleFs * 0.6)
        nvgFontSize(nvgCtx, lblFs)
        nvgFillColor(nvgCtx, nvgRGBA(240, 240, 255, isDisabled and 100 or (isSel and 255 or 200)))
        nvgText(nvgCtx, mx + cardW / 2, my + cardH * 0.55, modeLabels[m])

        -- 描述（多行）
        local descFs = math.max(9, titleFs * 0.38)
        nvgFontSize(nvgCtx, descFs)
        nvgFillColor(nvgCtx, nvgRGBA(160, 160, 180, isDisabled and 100 or 180))
        local descLines = {}
        for line in modeDescs[m]:gmatch("[^\n]+") do table.insert(descLines, line) end
        for dl, dline in ipairs(descLines) do
            nvgText(nvgCtx, mx + cardW / 2, my + cardH * 0.70 + (dl - 1) * descFs * 1.4, dline)
        end

        table.insert(menuRects.mode.modes, {x = mx, y = my, w = cardW, h = cardH, mode = m})
    end

    -- 难度选择
    local diffTitleY = logicalH * 0.52
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvgCtx, math.max(12, titleFs * 0.48))
    nvgFillColor(nvgCtx, nvgRGBA(230, 225, 255, 230))
    nvgText(nvgCtx, centerX, diffTitleY, "选择难度")

    local diffGap = math.max(6, logicalW * 0.018)
    local diffW = math.min((logicalW - 36 - diffGap * 2) / 3, 116)
    local diffH = math.max(46, logicalH * 0.075)
    local diffStartX = centerX - (diffW * 3 + diffGap * 2) / 2
    local diffY = diffTitleY + math.max(16, titleFs * 0.65)
    local diffColors = {{120, 220, 130}, {245, 195, 70}, {240, 95, 85}}

    for i, diff in ipairs(DIFFICULTY_DEF) do
        local dx = diffStartX + (i - 1) * (diffW + diffGap)
        local dc = diffColors[i]
        local isSel = (charSelect.selectedDifficulty or 1) == i

        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, dx, diffY, diffW, diffH, 7)
        if isSel then
            nvgFillColor(nvgCtx, nvgRGBA(math.floor(dc[1] * 0.18 + 30), math.floor(dc[2] * 0.18 + 24), math.floor(dc[3] * 0.18 + 38), 245))
        else
            nvgFillColor(nvgCtx, nvgRGBA(34, 30, 48, 235))
        end
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(dc[1], dc[2], dc[3], isSel and 255 or 120))
        nvgStrokeWidth(nvgCtx, isSel and 2 or 1)
        nvgStroke(nvgCtx)

        local nameFs = math.max(11, titleFs * 0.42)
        nvgFontSize(nvgCtx, nameFs)
        nvgFillColor(nvgCtx, nvgRGBA(245, 245, 255, isSel and 255 or 215))
        nvgText(nvgCtx, dx + diffW / 2, diffY + diffH * 0.32, diff.name)

        local descFs = math.max(7, titleFs * 0.28)
        nvgFontSize(nvgCtx, descFs)
        nvgFillColor(nvgCtx, nvgRGBA(185, 185, 205, isSel and 230 or 175))
        local lineY = diffY + diffH * 0.62
        local lineIdx = 0
        for line in diff.desc:gmatch("[^\n]+") do
            nvgText(nvgCtx, dx + diffW / 2, lineY + lineIdx * descFs * 1.15, line)
            lineIdx = lineIdx + 1
        end

        if isSel then
            local markR = math.max(5, diffH * 0.14)
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, dx + diffW - markR - 5, diffY + markR + 5, markR)
            nvgFillColor(nvgCtx, nvgRGBA(dc[1], dc[2], dc[3], 255))
            nvgFill(nvgCtx)
            nvgFontSize(nvgCtx, math.max(7, markR * 1.3))
            nvgFillColor(nvgCtx, nvgRGBA(20, 18, 28, 255))
            nvgText(nvgCtx, dx + diffW - markR - 5, diffY + markR + 5, "✓")
        end

        table.insert(menuRects.mode.difficulties, {x = dx, y = diffY, w = diffW, h = diffH, difficulty = i})
    end

    -- 下一步按钮
    local btnW = math.min(logicalW * 0.4, 180)
    local btnH = math.max(34, titleFs * 1.6)
    local btnX = centerX - btnW / 2
    local btnY = logicalH * 0.74

    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, btnX, btnY, btnW, btnH, 8)
    nvgFillColor(nvgCtx, nvgRGBA(240, 190, 50, 255))
    nvgFill(nvgCtx)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, btnX, btnY, btnW, btnH, 8)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 60, 100))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    nvgFontSize(nvgCtx, math.max(13, titleFs * 0.6))
    nvgFillColor(nvgCtx, nvgRGBA(40, 20, 0, 255))
    nvgText(nvgCtx, centerX, btnY + btnH / 2, "选择角色 →")

    menuRects.mode.nextBtn = {x = btnX, y = btnY, w = btnW, h = btnH}

    -- 返回按钮
    local backFs = math.max(11, titleFs * 0.45)
    local backW = math.min(80, logicalW * 0.2)
    local backH = math.max(26, backFs * 2)
    local backX = centerX - backW / 2
    local backY = btnY + btnH + 12

    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, backX, backY, backW, backH, 5)
    nvgFillColor(nvgCtx, nvgRGBA(60, 55, 80, 255))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(120, 115, 140, 255))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    nvgFontSize(nvgCtx, backFs)
    nvgFillColor(nvgCtx, nvgRGBA(210, 210, 230, 255))
    nvgText(nvgCtx, centerX, backY + backH / 2, "← 返回")

    menuRects.mode.backBtn = {x = backX, y = backY, w = backW, h = backH}
end

--- 绘制角色选择界面
function drawCharSelect()
    -- 加载角色预览图（仅一次）
    if not charSelect.loaded and nvgCtx then
        for i, char in ipairs(CHARACTER_LIST) do
            local h = nvgCreateImage(nvgCtx, char.sprite, NVG_IMAGE_NEAREST)
            charSelect.charPreviews[i] = (h ~= -1 and h ~= 0) and h or nil
        end
        charSelect.loaded = true
    end

    -- 背景
    if not drawVideoBg() then
        drawRoundRect(0, 0, logicalW, logicalH, 0, 15, 12, 30)
    end

    charSelectRects.arrowLeft = nil
    charSelectRects.arrowRight = nil
    charSelectRects.startBtn = nil
    charSelectRects.backBtn = nil

    local centerX = logicalW / 2
    local titleFs = math.max(18, math.min(logicalW * 0.065, 32))
    local isPortrait = logicalH > logicalW

    -- 外围阴影面板（全屏，四周留10px）
    do
        local panelMargin = 10
        local panelX = panelMargin
        local panelY = panelMargin
        local panelW = logicalW - panelMargin * 2
        local panelH = logicalH - panelMargin * 2
        local panelR = 14
        -- 阴影层
        local shadowOff = 6
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX + shadowOff, panelY + shadowOff, panelW, panelH, panelR)
        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 100))
        nvgFill(nvgCtx)
        -- 面板主体
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, panelR)
        nvgFillColor(nvgCtx, nvgRGBA(20, 16, 35, 200))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(120, 110, 160, 120))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
    end

    -- 标题
    local titleY = logicalH * 0.04
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvgCtx, titleFs)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 80, 255))
    nvgText(nvgCtx, centerX, titleY, "角色页面")

    -- ===== 角色单行展示 + 左右箭头切换 =====
    local numChars = #CHARACTER_LIST
    local selIdx = charSelect.selectedChar

    -- 角色卡片尺寸（放大）
    local cellW = math.min(logicalW * 0.28, 110)
    local cellH = cellW * 1.45
    local arrowSize = math.max(28, cellW * 0.4)
    local arrowPad = math.max(12, logicalW * 0.05)

    local vGap = 20
    local charAreaY = titleY + titleFs / 2 + vGap
    local charAreaCenterY = charAreaY + cellH / 2

    -- 左箭头
    local arrowLeftX = centerX - cellW / 2 - arrowPad - arrowSize
    local arrowY = charAreaCenterY - arrowSize / 2
    local canLeft = selIdx > 1
    nvgFontSize(nvgCtx, arrowSize)
    nvgFillColor(nvgCtx, canLeft and nvgRGBA(255, 220, 80, 255) or nvgRGBA(80, 75, 100, 100))
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvgCtx, arrowLeftX + arrowSize / 2, charAreaCenterY, "◀")
    charSelectRects.arrowLeft = canLeft and {x = arrowLeftX, y = arrowY, w = arrowSize, h = arrowSize} or nil

    -- 右箭头
    local arrowRightX = centerX + cellW / 2 + arrowPad
    local canRight = selIdx < numChars
    nvgFillColor(nvgCtx, canRight and nvgRGBA(255, 220, 80, 255) or nvgRGBA(80, 75, 100, 100))
    nvgText(nvgCtx, arrowRightX + arrowSize / 2, charAreaCenterY, "▶")
    charSelectRects.arrowRight = canRight and {x = arrowRightX, y = arrowY, w = arrowSize, h = arrowSize} or nil

    -- 当前选中角色卡片（居中）
    local cx = centerX - cellW / 2
    local cy = charAreaY
    local char = CHARACTER_LIST[selIdx]

    -- 选中高亮框
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, cx - 2, cy - 2, cellW + 4, cellH + 4, 6)
    nvgFillColor(nvgCtx, nvgRGBA(255, 200, 60, 80))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 220, 80, 255))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 角色精灵（行走动画）
    local animCol = ANIM_FRAMES[charSelect.animFrameIdx]
    local sf = getCharSpriteFrame(selIdx)
    if sf then
        local sx = sf.offsetX + animCol * sf.frameW
        ---@type number
        local sy = sf.offsetY
        local sprSize = math.min(cellW * 0.8, cellH * 0.45)
        local ratio = sf.frameH / sf.frameW
        local dw = sprSize
        local dh = sprSize * ratio
        if dh > cellH * 0.50 then dh = cellH * 0.50; dw = dh / ratio end
        local sprX = cx + (cellW - dw) / 2
        local sprY = cy + cellH * 0.06
        drawSpriteRegion(sf.handle, sf.imgW, sf.imgH, sx, sy, sf.frameW, sf.frameH, sprX, sprY, dw, dh)
    end

    -- 角色名
    local nameFs = math.max(14, cellW * 0.18)
    nvgFontSize(nvgCtx, nameFs)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 80, 255))
    nvgText(nvgCtx, cx + cellW / 2, cy + cellH * 0.68, char.name)

    -- 被动技能小标签
    local sk = SKILL_DEF[char.passive]
    if sk then
        local skFs = math.max(10, cellW * 0.14)
        nvgFontSize(nvgCtx, skFs)
        nvgFillColor(nvgCtx, nvgRGBA(sk.r, sk.g, sk.b, 255))
        nvgText(nvgCtx, cx + cellW / 2, cy + cellH * 0.82, sk.name)
    end

    -- 锁定角色：卡片半透明遮罩 + 锁图标
    if char.id ~= "axe-warrior" then
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cx, cy, cellW, cellH, 5)
        nvgFillColor(nvgCtx, nvgRGBA(10, 8, 20, 140))
        nvgFill(nvgCtx)
        local lockIconFs = math.max(18, cellW * 0.28)
        nvgFontSize(nvgCtx, lockIconFs)
        nvgFillColor(nvgCtx, nvgRGBA(120, 115, 140, 220))
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvgCtx, cx + cellW / 2, cy + cellH * 0.45, "🔒")
    end

    -- 页码指示器 (如 3/7)
    local pageFs = math.max(10, titleFs * 0.42)
    nvgFontSize(nvgCtx, pageFs)
    nvgFillColor(nvgCtx, nvgRGBA(160, 160, 180, 180))
    nvgText(nvgCtx, centerX, cy + cellH + vGap / 2 + pageFs / 2, selIdx .. "/" .. numChars)

    -- ===== 选中角色详情 =====
    local detailY = cy + cellH + vGap + pageFs + vGap
    local selChar = CHARACTER_LIST[charSelect.selectedChar]
    local selSkill = SKILL_DEF[selChar.passive]
    local detailFs = math.max(10, titleFs * 0.5)
    local isLocked = selChar.id ~= "axe-warrior"

    if isLocked then
        -- 敬请期待提示
        local lockFs = math.max(20, titleFs * 1.0)
        local lockY = detailY + logicalH * 0.12
        nvgFontSize(nvgCtx, lockFs)
        nvgFillColor(nvgCtx, nvgRGBA(120, 115, 140, 200))
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvgCtx, centerX, lockY, "🔒 敬请期待")
        local subFs = math.max(11, titleFs * 0.4)
        nvgFontSize(nvgCtx, subFs)
        nvgFillColor(nvgCtx, nvgRGBA(100, 95, 120, 160))
        nvgText(nvgCtx, centerX, lockY + lockFs + 8, "该角色尚未开放")
    else

    -- 被动技能
    if selSkill then
        nvgFontSize(nvgCtx, detailFs)
        nvgFillColor(nvgCtx, nvgRGBA(selSkill.r, selSkill.g, selSkill.b, 255))
        nvgText(nvgCtx, centerX, detailY, "被动: " .. selSkill.name .. " - " .. selSkill.desc)
        detailY = detailY + detailFs + vGap
    end

    -- 初始卡组（复用 drawCard 展示）
    nvgFontSize(nvgCtx, detailFs * 0.9)
    nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 200))
    nvgText(nvgCtx, centerX, detailY, "初始卡组:")
    detailY = detailY + detailFs / 2 + vGap / 2

    local cards = selChar.startCards
    local numCards = #cards
    local miniCardH = math.max(90, math.min(logicalH * 0.25, 170))
    local miniCardW = math.floor(miniCardH * 0.68)
    local cardGap = 4
    local maxRowW = logicalW * 0.95
    local perRow = math.max(1, math.floor((maxRowW + cardGap) / (miniCardW + cardGap)))
    local rowCount = math.ceil(numCards / perRow)

    for row = 0, rowCount - 1 do
        local startIdx = row * perRow + 1
        local endIdx = math.min(numCards, (row + 1) * perRow)
        local rowNum = endIdx - startIdx + 1
        local rowW = rowNum * miniCardW + (rowNum - 1) * cardGap
        local rowStartX = centerX - rowW / 2
        for ci = startIdx, endIdx do
            local col = ci - startIdx
            local mcx = rowStartX + col * (miniCardW + cardGap)
            drawCard(mcx, detailY, miniCardW, miniCardH, {id = cards[ci], usesLeft = -1}, false, false)
        end
        detailY = detailY + miniCardH + 2
    end
    detailY = detailY + 6

    end -- isLocked

    -- ===== 返回 + 开始冒险（固定在屏幕底部） =====
    local btnH = math.max(34, titleFs * 1.6)
    local btnY = logicalH - btnH - math.max(12, logicalH * 0.03)
    local gap = 10
    local totalW = math.min(logicalW * 0.85, 300)
    local backW = totalW * 0.32
    local startW = totalW * 0.64
    local rowX = centerX - (backW + gap + startW) / 2

    -- 返回按钮（左）
    local backX = rowX
    local backFs = math.max(11, titleFs * 0.45)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, backX, btnY, backW, btnH, 8)
    nvgFillColor(nvgCtx, nvgRGBA(50, 45, 70, 200))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(100, 95, 120, 150))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    nvgFontSize(nvgCtx, backFs)
    nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 200))
    nvgText(nvgCtx, backX + backW / 2, btnY + btnH / 2, "← 返回")
    charSelectRects.backBtn = {x = backX, y = btnY, w = backW, h = btnH}

    -- 开始冒险按钮（右）
    local btnX = backX + backW + gap
    if isLocked then
        -- 锁定角色：灰色按钮
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btnX, btnY, startW, btnH, 8)
        nvgFillColor(nvgCtx, nvgRGBA(60, 55, 75, 200))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(80, 75, 100, 150))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)
        nvgFontSize(nvgCtx, math.max(13, titleFs * 0.6))
        nvgFillColor(nvgCtx, nvgRGBA(100, 95, 120, 180))
        nvgText(nvgCtx, btnX + startW / 2, btnY + btnH / 2, "敬请期待")
        charSelectRects.startBtn = nil
    else
        local pulse = math.sin(os.clock() * 3) * 0.15 + 0.85
        local glowA = math.floor(pulse * 40)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btnX - 4, btnY - 4, startW + 8, btnH + 8, 12)
        nvgFillColor(nvgCtx, nvgRGBA(255, 200, 60, glowA))
        nvgFill(nvgCtx)

        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btnX, btnY, startW, btnH, 8)
        nvgFillColor(nvgCtx, nvgRGBA(240, 190, 50, 255))
        nvgFill(nvgCtx)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btnX, btnY, startW, btnH, 8)
        nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 60, 100))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)

        nvgFontSize(nvgCtx, math.max(13, titleFs * 0.6))
        nvgFillColor(nvgCtx, nvgRGBA(40, 20, 0, 255))
        nvgText(nvgCtx, btnX + startW / 2, btnY + btnH / 2, "开始冒险")
        charSelectRects.startBtn = {x = btnX, y = btnY, w = startW, h = btnH}
    end
end

--- 绘制战斗预估信息
function drawCombatPreview()
    -- 检查玩家面朝方向的怪物（上下左右相邻格子）
    local dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
    local previewInfo = {}

    for _, d in ipairs(dirs) do
        local nr = player.row + d[1]
        local nc = player.col + d[2]
        if nr >= 1 and nr <= GRID and nc >= 1 and nc <= GRID then
            local tile = maps[player.floor][nr][nc]
            if isMonster(tile) then
                local m = MONSTER_DEF[tile]
                local result = calcCombat(tile)
                local crit = calcCritical(tile)
                table.insert(previewInfo, {
                    name = m.name,
                    hpLoss = result.hpLoss,
                    canWin = result.canWin,
                    critAtk = crit and crit.critAtk or 0,
                    hpSave = crit and crit.hpSave or 0,
                    skillName = m.skill and m.skill.name or nil,
                })
            end
        end
    end

    if #previewInfo == 0 then return end
    -- 邻接多怪时不显示预估（会触发群战，单独预估无意义）
    if #previewInfo > 1 then return end

    -- 绘制预估面板
    local fs = math.max(10, cellSize * 0.32)
    local lineH = fs + 4
    local panelH = lineH * #previewInfo + 10
    local panelW = fs * 12
    local px = gridX + cellSize * GRID + 4
    -- 如果超出屏幕右边，放到左边
    if px + panelW > logicalW then
        px = gridX - panelW - 4
    end
    if px < 0 then px = 4 end
    local py = gridY

    drawRoundRect(px, py, panelW, panelH, 4, 40, 35, 60, 200)

    for i, info in ipairs(previewInfo) do
        local ty = py + 5 + (i - 1) * lineH + lineH / 2
        local prefix = info.name
        if info.skillName then
            prefix = prefix .. "[" .. info.skillName .. "]"
        end
        if info.canWin then
            local critStr = ""
            if info.critAtk > 0 then
                critStr = " 临+" .. info.critAtk .. "省" .. info.hpSave
            end
            drawTextLeft(prefix .. " -" .. info.hpLoss .. critStr, px + 6, ty, fs, 255, 200, 100)
        else
            local critStr = ""
            if info.critAtk > 0 then
                critStr = " 需攻+" .. info.critAtk
            end
            drawTextLeft(prefix .. " 无法战胜!" .. critStr, px + 6, ty, fs, 255, 80, 80)
        end
    end
end

--- 绘制战斗动画
function drawBattleAnim()
    if not battle.active then return end

    -- 面板尺寸（卡牌独立在底部，面板只放战斗内容）
    local isPortrait = logicalH > logicalW
    local monsterNum = #battle.monsters
    local pw = math.min(logicalW * 0.95, monsterNum > 1 and 540 or 480)
    local battleH = pw * (monsterNum > 2 and 0.95 or (monsterNum > 1 and 0.90 or 0.88))
    local ph = battleH + 8 + 22  -- +22 额外空间容纳状态栏
    local px = (logicalW - pw) / 2
    local py = isPortrait
        and ((logicalH - ph) / 2 - logicalH * 0.16)  -- 竖屏：居中偏上，给底部卡牌留空间
        or  ((logicalH - ph) / 2 - logicalH * 0.19)   -- 横屏：居中上移，给底部卡牌留更多空间

    -- 半透明遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 180)

    -- 面板背景
    drawRoundRect(px, py, pw, ph, 8, 30, 28, 50, 240)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, pw, ph, 8)
    nvgStrokeColor(nvgCtx, nvgRGBA(100, 140, 220, 180))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    local fs = math.max(11, ph * 0.09)
    local spriteSize = math.min(pw * 0.30, ph * 0.6)
    local midY = py + ph * 0.42

    -- === 倍速按钮（面板右上角） ===
    do
        local spd = battle.speed or 1
        local spdFs = math.max(9, fs * 0.7)
        local spdBtnW = spdFs * 2.8
        local spdBtnH = spdFs * 1.6
        local spdBtnX = px + pw - spdBtnW - 6
        local spdBtnY = py + 6
        -- 按倍速等级着色：1x=蓝灰, 2x=青蓝, 3x=金橙
        local bgR, bgG, bgB, bgA
        local stR, stG, stB
        local tR, tG, tB
        if spd == 3 then
            bgR, bgG, bgB, bgA = 140, 80, 20, 220
            stR, stG, stB = 255, 200, 80
            tR, tG, tB = 255, 230, 100
        elseif spd == 2 then
            bgR, bgG, bgB, bgA = 30, 90, 130, 220
            stR, stG, stB = 80, 200, 255
            tR, tG, tB = 100, 220, 255
        else
            bgR, bgG, bgB, bgA = 45, 45, 65, 180
            stR, stG, stB = 100, 110, 160
            tR, tG, tB = 160, 170, 210
        end
        drawRoundRect(spdBtnX, spdBtnY, spdBtnW, spdBtnH, 4, bgR, bgG, bgB, bgA)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, spdBtnX, spdBtnY, spdBtnW, spdBtnH, 4)
        nvgStrokeColor(nvgCtx, nvgRGBA(stR, stG, stB, 200))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
        local spdLabel = spd == 1 and "1x" or (spd .. "x")
        drawTextCenter(spdLabel, spdBtnX + spdBtnW / 2, spdBtnY + spdBtnH * 0.35, spdFs, tR, tG, tB)
        battle._speedBtn = {x = spdBtnX, y = spdBtnY, w = spdBtnW, h = spdBtnH}
    end

    -- === 左侧: 玩家 ===
    local plX = px + pw * 0.2
    local plShake = (battle.phase == "monster_atk") and battle.shakeOffset or 0
    local isPlayerHit = battle.phase == "monster_atk" and battle.atkIndex >= 1 and battle.timer < 0.5
    if spr.player then
        -- 未选卡朝前，选中卡牌朝右，攻击阶段朝右
        local battleFacing = "down"
        if battle.phase == "player_atk" or battle.phase == "card_effect" then
            battleFacing = "right"
        elseif battle.selectedCard then
            battleFacing = "right"
        end
        local facingSY = plSpr.oy + (plSpr.frow[battleFacing] or 0) * plSpr.fh
        local plSprX = plX - spriteSize / 2 + plShake
        local plSprY = midY - spriteSize / 2
        drawSpriteRegion(spr.player, spr.playerW, spr.playerH,
            getAnimSX(), facingSY, plSpr.fw, plSpr.fh,
            plSprX, plSprY, spriteSize, spriteSize)
        -- 受击红色闪烁叠加
        if isPlayerHit and not battle.guardActive then
            local flashAlpha = math.floor(180 * (1 - battle.timer / (BATTLE_ROUND_DURATION * 0.7)))
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, plSprX, plSprY, spriteSize, spriteSize, 4)
            nvgFillColor(nvgCtx, nvgRGBA(255, 30, 30, flashAlpha))
            nvgFill(nvgCtx)
        end
    else
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, plX + plShake, midY, spriteSize * 0.4)
        local plR = isPlayerHit and 255 or 70
        nvgFillColor(nvgCtx, nvgRGBA(plR, 140, 255, 255))
        nvgFill(nvgCtx)
        drawTextCenter("勇", plX + plShake, midY, fs * 1.2, 255, 255, 255)
    end

    -- 玩家HP条（带拖尾，圆角胶囊形）
    local barW = pw * 0.28
    local barH = math.max(12, ph * 0.07)
    local barR = math.floor(barH * 0.5)
    local plBarX = plX - barW / 2
    local plBarY = midY + spriteSize / 2 + 6
    -- HP变化追赶
    local trailSpeed = 2.0  -- 每秒追赶速率
    local dt = time:GetTimeStep() * (battle.speed or 1)
    if battle.displayPlayerHP > battle.playerHP then
        battle.displayPlayerHP = battle.playerHP  -- 受伤立即刷新
    elseif battle.displayPlayerHP < battle.playerHP then
        battle.displayPlayerHP = math.min(battle.playerHP, battle.displayPlayerHP + (battle.playerStartHP * trailSpeed * dt))
    end
    drawBarBg(plBarX, plBarY, barW, barH, barR)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, plBarX, plBarY, barW, barH, barR)
    nvgStrokeColor(nvgCtx, nvgRGBA(60, 180, 80, 120))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    -- 拖尾条（橙黄渐变）
    local plTrailFill = math.max(0, math.min(1, battle.displayPlayerHP / battle.playerStartHP))
    if math.abs(battle.displayPlayerHP - battle.playerHP) > 0.5 then
        drawGradientBar(plBarX, plBarY, barW * plTrailFill, barH, barR, 230, 180, 50)
    end
    -- 实际HP条（绿色渐变 + 低血量变红）
    local plHPFill = math.max(0, math.min(1, battle.playerHP / battle.playerStartHP))
    local hpR, hpG, hpB
    if plHPFill > 0.5 then
        hpR, hpG, hpB = 60, 210, 70
    elseif plHPFill > 0.25 then
        hpR, hpG, hpB = 230, 200, 50
    else
        hpR, hpG, hpB = 220, 60, 50
    end
    drawGradientBar(plBarX, plBarY, barW * plHPFill, barH, barR, hpR, hpG, hpB)
    local hpLabel = "HP:" .. math.floor(battle.playerHP)
    local labelY = plBarY + barH + fs * 0.6
    local labelFs = fs * 0.85
    nvgFontSize(nvgCtx, labelFs)
    nvgFontFace(nvgCtx, "sans")
    -- 攻击动画期间预扣显示护盾值（结算在timer>=1.0，但视觉上立即反映）
    local displayShieldHP = battle.shieldHP
    if battle.phase == "monster_atk" and (battle.atkShieldAbsorb or 0) > 0 then
        displayShieldHP = math.max(0, battle.shieldHP - battle.atkShieldAbsorb)
    end
    if displayShieldHP > 0 then
        local shieldNumLabel = " " .. displayShieldHP
        local hpW = nvgTextBounds(nvgCtx, 0, 0, hpLabel)
        local shieldNumW = nvgTextBounds(nvgCtx, 0, 0, shieldNumLabel)
        local iconSz = fs * 0.9
        local totalW = hpW + iconSz + shieldNumW
        local startX = plX - totalW / 2
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(100, 255, 100, 255))
        nvgText(nvgCtx, startX, labelY, hpLabel)
        -- 盾牌用IconSet图标
        spr.drawIcon("status_shield", startX + hpW + iconSz / 2, labelY, iconSz)
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(130, 200, 255, 255))
        nvgText(nvgCtx, startX + hpW + iconSz, labelY, shieldNumLabel)
    else
        drawTextCenter(hpLabel, plX, labelY, labelFs, 100, 255, 100)
    end

    -- 选中卡牌时显示玩家侧预览（回复/格挡/蓄力等）
    if battle.selectedCard and battle.phase == "waiting_for_card" then
        local selCard = battle.hand[battle.selectedCard]
        if selCard then
            local plPreview = nil
            local plPR, plPG, plPB = 100, 255, 100
            local plPreviewAtHP = false
            if selCard.id == "heal" then
                plPreviewAtHP = true
                local baseHeal = player.def
                if selCard.gem == "holy" then baseHeal = math.floor(baseHeal * 1.5) end
                local healAmt = math.min(baseHeal, battle.playerStartHP - battle.playerHP)
                if healAmt > 0 then
                    plPreview = "+" .. math.floor(healAmt)
                else
                    plPreview = "+0"
                    plPR, plPG, plPB = 180, 180, 180
                end
            elseif selCard.id == "drain" then
                plPreviewAtHP = true
                local ti = battle.targetIdx or getFirstAliveMonster()
                if ti then
                    local d = applyGemDmg(math.max(0, battle.monsters[ti].playerDmg), selCard.gem)
                    -- 暴击/易伤/怒火加成
                    if player.skills.crit and not battle.critUsed and d > 0 then d = math.floor(d * 1.5) end
                    local drainMo = ti and battle.monsters[ti] or nil
                    if drainMo and drainMo.effects and drainMo.effects.vulnerable and drainMo.effects.vulnerable > 0 then d = math.floor(d * 1.5) end
                    local pvFury3 = battle.fury or 0
                    if pvFury3 > 0 then d = math.floor(d * (1 + pvFury3 * 0.1)) end
                    if battle.powerNext then d = d * 2 end
                    if selCard.gem == "blood" then d = math.floor(d * 1.1) end
                    local healAmt = math.min(d, battle.playerStartHP - battle.playerHP)
                    if healAmt > 0 then
                        plPreview = "+" .. math.floor(healAmt)
                    else
                        plPreview = "+0"
                        plPR, plPG, plPB = 180, 180, 180
                    end
                end
            elseif selCard.id == "guard" then
                plPreview = "伤害→1"
                plPR, plPG, plPB = 100, 160, 255
            elseif selCard.id == "power" then
                plPreview = "下次x2"
                plPR, plPG, plPB = 255, 180, 50
            elseif selCard.id == "reflect" then
                plPreview = selCard.gem == "holy" and "反弹75%" or "反弹50%"
                plPR, plPG, plPB = 200, 220, 255
            elseif selCard.id == "defend" then
                local shieldAmt = player.def
                if selCard.gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
                plPreview = "盾+" .. shieldAmt
                plPR, plPG, plPB = 80, 140, 200
            elseif selCard.id == "shield" then
                local shieldAmt = player.def * 2
                if selCard.gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
                plPreview = "盾+" .. shieldAmt
                plPR, plPG, plPB = 60, 180, 220
            end
            if plPreview then
                local plPrevFs = fs * 0.75
                if plPreviewAtHP then
                    -- 治愈/吸取：显示在HP文字右侧
                    local hpTextY = plBarY + barH + fs * 0.6
                    drawTextLeft(plPreview, plX + barW / 2 + 2, hpTextY, plPrevFs, plPR, plPG, plPB, 230)
                else
                    drawTextCenter(plPreview, plX, midY - spriteSize / 2 - plPrevFs * 0.8, plPrevFs, plPR, plPG, plPB, 230)
                end
            end
        end
    end

    -- 玩家MP条（圆角方形）
    local mpBarY = plBarY + barH + fs * 1.4
    drawBarBg(plBarX, mpBarY, barW, barH, barR)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, plBarX, mpBarY, barW, barH, barR)
    nvgStrokeColor(nvgCtx, nvgRGBA(80, 80, 200, 120))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    local mpFill = battle.maxMp > 0 and math.max(0, battle.mp / battle.maxMp) or 0
    -- 选中卡牌时高亮预扣MP部分
    local selMpCost = 0
    if battle.selectedCard and battle.phase == "waiting_for_card" then
        local selC = battle.hand[battle.selectedCard]
        if selC then
            local def = CARD_DEF[selC.id]
            if def then selMpCost = getCardCost(selC) end
        end
    end
    if selMpCost > 0 and battle.maxMp > 0 then
        -- 先画当前MP（蓝色渐变）
        local afterMp = math.max(0, battle.mp - selMpCost)
        local afterFill = afterMp / battle.maxMp
        -- 预扣部分用闪烁的橙红色
        drawGradientBar(plBarX, mpBarY, barW * mpFill, barH, barR, 60, 80, 220)
        local costAlpha = math.floor(150 + 80 * math.sin(battle.timer * 6))
        drawGradientBar(plBarX + barW * afterFill, mpBarY, barW * (mpFill - afterFill), barH, barR, 255, 140, 50, costAlpha)
        -- 显示扣除后的MP
        if battle.mp >= selMpCost then
            drawTextCenter("MP:" .. afterMp .. "/" .. battle.maxMp, plX, mpBarY + barH + fs * 0.6, fs * 0.75, 255, 180, 80)
        else
            drawTextCenter("MP:" .. battle.mp .. "/" .. battle.maxMp, plX, mpBarY + barH + fs * 0.6, fs * 0.75, 255, 80, 80)
        end
    else
        drawGradientBar(plBarX, mpBarY, barW * mpFill, barH, barR, 60, 80, 220)
        drawTextCenter("MP:" .. battle.mp .. "/" .. battle.maxMp, plX, mpBarY + barH + fs * 0.6, fs * 0.75, 130, 130, 255)
    end

    -- === 玩家状态图标（MP下方，纯图标 + 数值角标） ===
    battle._statusRects = {}
    do
        local statuses = {}
        -- 圣盾：首回合未消耗时显示
        if battle.hasShield then
            local hasPreemptive = false
            for _, m in ipairs(battle.monsters) do
                if m.alive and m.preemptive then hasPreemptive = true; break end
            end
            local shieldRound = hasPreemptive and 0 or 1
            if battle.round <= shieldRound then
                table.insert(statuses, {icon = "🔰", iconId = "status_shield", name = "圣盾", desc = "首回合免疫所有伤害", r = 100, g = 220, b = 255})
            end
        end
        -- 暴击：首击未使用时显示
        if player.skills.crit and not battle.critUsed then
            table.insert(statuses, {icon = "⚔", iconId = "skill_greatsword", name = "暴击", desc = "下次攻击伤害×1.5", r = 255, g = 160, b = 30})
        end
        -- 蓄力
        if battle.powerNext then
            table.insert(statuses, {icon = "⚡", iconId = "status_power", name = "蓄力", desc = "下次攻击伤害翻倍", r = 255, g = 180, b = 40})
        end
        -- 格挡
        if battle.guardActive then
            table.insert(statuses, {icon = "🛡", iconId = "status_shield", name = "格挡", desc = "本回合受到的伤害降为1", r = 100, g = 160, b = 255})
        end
        -- 反射
        if battle.reflectActive then
            table.insert(statuses, {icon = "🪞", iconId = "status_reflect", name = "反射", desc = "本回合将受到的伤害反弹给敌人", r = 200, g = 220, b = 255})
        end
        -- 不朽
        if battle.immortalActive then
            table.insert(statuses, {icon = "✟", iconId = "status_immortal", name = "不朽", desc = "HP不会降至0以下", r = 255, g = 240, b = 100})
        end
        -- 荆棘
        if (battle.thornsActive or 0) > 0 then
            table.insert(statuses, {icon = "🌿", iconId = "status_thorns", name = "荆棘", badge = tostring(battle.thornsActive), desc = "反弹 " .. battle.thornsActive .. " 点伤害给攻击者", r = 120, g = 220, b = 80})
        end
        -- 战吼加攻
        if (battle.warCryAtk or 0) > 0 then
            table.insert(statuses, {icon = "🔥", iconId = "status_burn", name = "战吼", badge = "" .. battle.warCryAtk, desc = "攻击力增加 " .. battle.warCryAtk, r = 255, g = 120, b = 60})
        end
        if (battle.frenzyAtk or 0) > 0 then
            table.insert(statuses, {icon = "🩸", iconId = "status_burn", name = "狂暴", badge = "" .. battle.frenzyAtk, desc = "嗜血狂暴 攻击力增加 " .. battle.frenzyAtk, r = 180, g = 20, b = 30})
        end
        if battle.bloodFrenzyHeal then
            table.insert(statuses, {icon = "🧛", iconId = "status_burn", name = "吸血", badge = "1", desc = "本回合攻击吸血20%", r = 160, g = 30, b = 50})
        end
        if battle.berserkerRageActive then
            table.insert(statuses, {icon = "💥", iconId = "status_vulnerable", name = "易伤", badge = "1", desc = "本回合受伤+30%", r = 255, g = 180, b = 60})
        end
        if battle.undyingActive then
            table.insert(statuses, {icon = "💪", iconId = "status_undying", name = "不屈", badge = "1", desc = "本回合HP不会低于1", r = 180, g = 50, b = 30})
        end
        if (battle.bloodScentTurns or 0) > 0 then
            table.insert(statuses, {icon = "👃", iconId = "status_blood_scent", name = "嗜血本能", badge = "" .. battle.bloodScentTurns, desc = "击杀敌人时怒火+3并回复10%HP 剩余" .. battle.bloodScentTurns .. "回合", r = 190, g = 30, b = 40})
        end
        if battle.titanSkipActive then
            table.insert(statuses, {icon = "🚫", iconId = "status_exhausted", name = "疲劳", badge = "1", desc = "本回合无法使用攻击牌", r = 120, g = 120, b = 120})
        end
        if (battle.fury or 0) > 0 then
            local furyPct = battle.fury * 10
            table.insert(statuses, {icon = "🔥", iconId = "status_berserk", name = "怒火", badge = "" .. battle.fury, desc = "怒火 攻击伤害+" .. furyPct .. "% 回合结束减半", r = 255, g = 80, b = 20})
        end
        -- 诅咒减攻（负面）
        if (battle.curseAtkLoss or 0) > 0 then
            table.insert(statuses, {icon = "💀", iconId = "status_curse", name = "诅咒", badge = "-" .. battle.curseAtkLoss, desc = "攻击力降低 " .. battle.curseAtkLoss, r = 200, g = 80, b = 80})
        end
        -- 虚弱减防（负面）
        if (battle.curseDefLoss or 0) > 0 then
            table.insert(statuses, {icon = "💔", iconId = "status_frail", name = "虚弱", badge = "-" .. battle.curseDefLoss, desc = "防御力降低 " .. battle.curseDefLoss, r = 90, g = 60, b = 130})
        end
        -- 迷雾减抽（负面）
        if (battle.fogDrawLoss or 0) > 0 then
            table.insert(statuses, {icon = "🌫", iconId = "status_fog", name = "迷雾", badge = "-" .. battle.fogDrawLoss, desc = "下回合少抽 " .. battle.fogDrawLoss .. " 张牌", r = 100, g = 100, b = 120})
        end

        if #statuses > 0 then
            local stY = mpBarY + barH + fs * 1.3
            local stIconFs = math.max(14, fs * 0.85)
            local stGap = math.max(2, stIconFs * 0.08)
            local stX = plBarX

            for _, st in ipairs(statuses) do
                local cx = stX + stIconFs * 0.5
                -- 图标
                local iconDrawn = st.iconId and spr.drawIcon(st.iconId, cx, stY, stIconFs, nil, true)
                if not iconDrawn then
                    -- fallback: 彩色圆底+文字
                    drawRoundRect(cx - stIconFs * 0.4, stY - stIconFs * 0.4, stIconFs * 0.8, stIconFs * 0.8, stIconFs * 0.2, st.r, st.g, st.b, 80)
                    nvgFontSize(nvgCtx, stIconFs * 0.6)
                    nvgFontFace(nvgCtx, "sans")
                    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(nvgCtx, nvgRGBA(st.r, st.g, st.b, 240))
                    nvgText(nvgCtx, cx, stY, st.icon)
                end
                -- 数值角标（右下角，无背景）
                if st.badge then
                    local badgeFs = math.max(8, stIconFs * 0.45)
                    local bx = cx + stIconFs * 0.3
                    local by = stY + stIconFs * 0.3
                    nvgFontSize(nvgCtx, badgeFs)
                    nvgFontFace(nvgCtx, "sans")
                    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    -- 描边效果（深色轮廓）
                    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 220))
                    for ox = -1, 1 do for oy = -1, 1 do
                        if ox ~= 0 or oy ~= 0 then nvgText(nvgCtx, bx + ox, by + oy, st.badge) end
                    end end
                    nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 255))
                    nvgText(nvgCtx, bx, by, st.badge)
                end
                -- 记录点击区域
                table.insert(battle._statusRects, {
                    x = stX, y = stY - stIconFs * 0.55,
                    w = stIconFs, h = stIconFs * 1.1,
                    st = st,
                })
                stX = stX + stIconFs + stGap
            end
        end
    end

    -- === 右侧: 怪物（支持多个） ===
    battle._monsterRects = {}
    battle._moEffectRects = {}
    local monsterCount = #battle.monsters
    local aliveCount = 0
    for _, mo in ipairs(battle.monsters) do
        if mo.alive then aliveCount = aliveCount + 1 end
    end
    -- 确保 targetIdx 指向存活怪物
    if battle.targetIdx then
        local tmo = battle.monsters[battle.targetIdx]
        if not tmo or not tmo.alive then
            battle.targetIdx = getFirstAliveMonster() or 1
        end
    end

    -- 根据怪物数量调整布局
    local moAreaX = px + pw * 0.55  -- 怪物区域起始X
    local moAreaW = pw * 0.42       -- 怪物区域宽度
    local moSpriteSize = spriteSize
    if monsterCount > 1 then
        moSpriteSize = math.max(spriteSize * 0.5, math.min(spriteSize * 0.75, moAreaW / monsterCount * 0.9))
    end
    local moBarWEach = math.min(barW, moAreaW / monsterCount - 4)

    for mi, mo in ipairs(battle.monsters) do
        -- 计算每个怪物的水平位置（均匀分布）
        local moX
        if monsterCount == 1 then
            moX = px + pw * 0.8
        else
            moX = moAreaX + moAreaW * (mi - 0.5) / monsterCount
        end

        -- 死亡怪物半透明
        local moAlpha = mo.alive and 255 or 60
        local moShake = (battle.phase == "player_atk" and mo.shakeOffset ~= 0) and mo.shakeOffset or 0

        -- 绘制怪物精灵
        local spriteData = mo.sprite and spriteImages[mo.sprite]
        if spriteData then
            local sy = (mo.spriteRow or 0) * SPRITE_FRAME_H
            local sx = mo.alive and getAnimSX() or 0  -- 死亡怪物停止动画
            nvgGlobalAlpha(nvgCtx, moAlpha / 255)
            drawSpriteRegion(spriteData.handle, spriteData.w, spriteData.h,
                sx, sy, SPRITE_FRAME_W, SPRITE_FRAME_H,
                moX - moSpriteSize / 2 + moShake, midY - moSpriteSize / 2, moSpriteSize, moSpriteSize)
            nvgGlobalAlpha(nvgCtx, 1.0)
        else
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, moX + moShake, midY, moSpriteSize * 0.35)
            nvgFillColor(nvgCtx, nvgRGBA(220, 60, 60, moAlpha))
            nvgFill(nvgCtx)
            drawTextCenter(mo.name:sub(1, 3), moX + moShake, midY, fs * 0.9, 255, 255, 255, moAlpha)
        end



        -- 记录怪物点击区域（用于切换目标）
        table.insert(battle._monsterRects, {
            x = moX - moSpriteSize / 2, y = midY - moSpriteSize / 2,
            w = moSpriteSize, h = moSpriteSize, idx = mi,
        })

        -- 玩家选中的攻击目标高亮（waiting_for_card阶段，多怪物时显示）
        if monsterCount > 1 and battle.targetIdx == mi and mo.alive and battle.phase == "waiting_for_card" then
            local tAlpha = math.floor(140 + 60 * math.sin(battle.timer * 5))
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, moX - moSpriteSize / 2 - 3, midY - moSpriteSize / 2 - 3,
                moSpriteSize + 6, moSpriteSize + 6, 4)
            nvgStrokeColor(nvgCtx, nvgRGBA(255, 220, 60, tAlpha))
            nvgStrokeWidth(nvgCtx, 2)
            nvgStroke(nvgCtx)
            -- 目标指示文字
            local indicatorFs = math.max(7, fs * 0.55)
            drawTextCenter("▼目标", moX, midY - moSpriteSize / 2 - indicatorFs * 0.6, indicatorFs, 255, 220, 60)
        end

        -- 当前攻击怪物红色描边（仅边缘发光，内部挖空）
        if battle.phase == "monster_atk" and battle.atkIndex == mi and mo.alive then
            local hlAlpha = math.floor(160 + 70 * math.sin(battle.timer * 8))
            local glow = 5
            local sprX = moX - moSpriteSize / 2
            local sprY = midY - moSpriteSize / 2
            local paint = nvgBoxGradient(nvgCtx,
                sprX, sprY, moSpriteSize, moSpriteSize,
                1, glow,
                nvgRGBA(255, 50, 40, hlAlpha), nvgRGBA(255, 50, 40, 0))
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, sprX - glow * 2, sprY - glow * 2,
                moSpriteSize + glow * 4, moSpriteSize + glow * 4)
            nvgRect(nvgCtx, sprX + 1, sprY + 1, moSpriteSize - 2, moSpriteSize - 2)
            nvgPathWinding(nvgCtx, NVG_HOLE)
            nvgFillPaint(nvgCtx, paint)
            nvgFill(nvgCtx)
        end

        -- 死亡标记
        if not mo.alive then
            drawTextCenter("X", moX, midY, moSpriteSize * 0.6, 255, 50, 50, 180)
        end

        -- 怪物攻击伤害标签（精灵上方，有目标指示时再上移）
        if mo.alive then
            local dmgFs = monsterCount > 2 and (fs * 0.55) or (fs * 0.7)
            local hasIndicator = monsterCount > 1 and battle.targetIdx == mi and battle.phase == "waiting_for_card"
            local dmgY = midY - moSpriteSize / 2 - dmgFs * 0.6
            if hasIndicator then
                dmgY = dmgY - dmgFs * 0.9
            end

            -- 怪物技能名称（伤害上方，点击可查看详情）
            if mo.skill then
                local skillFs = math.max(8, dmgFs * 0.72)
                local skillY = dmgY - dmgFs * 0.9
                nvgFontSize(nvgCtx, skillFs)
                nvgFontFace(nvgCtx, "sans")
                nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvgCtx, nvgRGBA(255, 200, 100, 210))
                nvgText(nvgCtx, moX, skillY, mo.skill.name)
                -- 记录点击区域
                local skTextW = nvgTextBounds(nvgCtx, 0, 0, mo.skill.name)
                local skHitW = math.max(skTextW + 10, dmgFs * 2.5)
                local skHitH = skillFs * 2.0
                table.insert(battle._moEffectRects, {
                    x = moX - skHitW / 2, y = skillY - skHitH / 2,
                    w = skHitW, h = skHitH,
                    st = {name = mo.skill.name, desc = mo.skill.desc, iconId = nil, r = 255, g = 200, b = 100, icon = "⚔"},
                })
            end

            -- 怪物ATK: 图标+数字
            local iconSz2 = dmgFs * 0.85
            local dmgNumStr = tostring(mo.dmg)
            local dmgNumW = nvgTextBounds(nvgCtx, 0, 0, dmgNumStr)
            local dmgTotalW = iconSz2 + dmgNumW
            local dmgStartX = moX - dmgTotalW / 2
            local dr, dg, db, da = 255, 100, 80, 220
            if mo.dmg <= 0 then dr, dg, db, da = 120, 120, 120, 180
            elseif mo.effects and mo.effects.weaken then dr, dg, db, da = 150, 130, 220, 230 end
            spr.drawIcon("icon_atk", dmgStartX + iconSz2 / 2, dmgY, iconSz2, da / 255)
            nvgFontSize(nvgCtx, dmgFs)
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, nvgRGBA(dr, dg, db, da))
            nvgText(nvgCtx, dmgStartX + iconSz2, dmgY, dmgNumStr)
        end

        -- 怪物HP条（带拖尾，圆角方形）
        local moBarX2 = moX - moBarWEach / 2
        local moBarY2 = midY + moSpriteSize / 2 + 4
        local mBarH = math.max(10, barH * 0.85)
        local mBarR = math.floor(mBarH * 0.5)
        -- 拖尾平滑追赶（带延迟停留）
        if mo.displayHP > mo.hp then
            -- 受伤：先停留0.4秒再开始追赶
            if not mo._trailDelay then mo._trailDelay = 0.4 end
            if mo._trailDelay > 0 then
                mo._trailDelay = mo._trailDelay - dt
            else
                mo.displayHP = math.max(mo.hp, mo.displayHP - (mo.maxHP * 0.8 * dt))
            end
        elseif mo.displayHP < mo.hp then
            mo.displayHP = math.min(mo.hp, mo.displayHP + (mo.maxHP * trailSpeed * dt))
            mo._trailDelay = nil
        else
            mo._trailDelay = nil
        end
        if mo.alive or mo.hp > 0 then
            drawBarBg(moBarX2, moBarY2, moBarWEach, mBarH, mBarR, moAlpha)
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, moBarX2, moBarY2, moBarWEach, mBarH, mBarR)
            nvgStrokeColor(nvgCtx, nvgRGBA(200, 60, 60, math.floor(moAlpha * 0.45)))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
            -- 拖尾条
            local moTrailFill = math.max(0, math.min(1, mo.displayHP / mo.maxHP))
            if math.abs(mo.displayHP - mo.hp) > 0.5 then
                drawGradientBar(moBarX2, moBarY2, moBarWEach * moTrailFill, mBarH, mBarR, 230, 180, 50, moAlpha)
            end
            -- 实际HP条（红色渐变）
            local moHPFill = math.max(0, mo.hp / mo.maxHP)
            drawGradientBar(moBarX2, moBarY2, moBarWEach * moHPFill, mBarH, mBarR, 220, 50, 45, moAlpha)
            -- 选中卡牌时预扣伤害高亮
            if battle.selectedCard and battle.phase == "waiting_for_card" and mo.alive then
                local selC = battle.hand[battle.selectedCard]
                if selC then
                    local prevDmg = 0
                    local isTarget = (mi == (battle.targetIdx or getFirstAliveMonster()))
                    local pDmg = applyGemDmg(math.max(0, mo.playerDmg), selC.gem)
                    -- 暴击/易伤/怒火加成（与实际伤害计算一致）
                    if player.skills.crit and not battle.critUsed and pDmg > 0 then pDmg = math.floor(pDmg * 1.5) end
                    if mo.effects and mo.effects.vulnerable and mo.effects.vulnerable > 0 then pDmg = math.floor(pDmg * 1.5) end
                    local pvFury = battle.fury or 0
                    if pvFury > 0 then pDmg = math.floor(pDmg * (1 + pvFury * 0.1)) end
                    if selC.id == "strike" or selC.id == "drain" then
                        if isTarget then
                            prevDmg = pDmg
                            if selC.id == "strike" and battle.armorStanceNext then
                                local abDmg2 = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                                prevDmg = applyGemDmg(math.max(0, abDmg2), selC.gem)
                                if player.skills.crit and not battle.critUsed and prevDmg > 0 then prevDmg = math.floor(prevDmg * 1.5) end
                                if mo.effects and mo.effects.vulnerable and mo.effects.vulnerable > 0 then prevDmg = math.floor(prevDmg * 1.5) end
                                if pvFury > 0 then prevDmg = math.floor(prevDmg * (1 + pvFury * 0.1)) end
                            end
                            if battle.powerNext then prevDmg = prevDmg * 2 end
                        end
                    elseif selC.id == "heavyStrike" or selC.id == "cleave" then
                        if isTarget then prevDmg = math.floor(pDmg * 1.5); if battle.powerNext then prevDmg = prevDmg * 2 end end
                    elseif selC.id == "haste" then
                        if isTarget then prevDmg = pDmg * 2; if battle.powerNext then prevDmg = prevDmg * 2 end end
                    elseif selC.id == "execute" then
                        if isTarget then
                            if mo.hp <= mo.maxHP * 0.2 then prevDmg = mo.hp else prevDmg = pDmg end
                        end
                    elseif selC.id == "armorBreak" then
                        if isTarget then
                            local abDmg = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                            abDmg = applyGemDmg(math.max(0, abDmg), selC.gem)
                            if player.skills.crit and not battle.critUsed and abDmg > 0 then abDmg = math.floor(abDmg * 1.5) end
                            if mo.effects and mo.effects.vulnerable and mo.effects.vulnerable > 0 then abDmg = math.floor(abDmg * 1.5) end
                            if (battle.fury or 0) > 0 then abDmg = math.floor(abDmg * (1 + (battle.fury or 0) * 0.1)) end
                            if battle.powerNext then abDmg = abDmg * 2 end
                            prevDmg = abDmg
                        end
                    elseif selC.id == "rend" or selC.id == "savageBash" then
                        if isTarget then
                            local mult = selC.id == "rend" and 0.5 or 0.6
                            prevDmg = math.floor(pDmg * mult); if battle.powerNext then prevDmg = prevDmg * 2 end
                        end
                    elseif selC.id == "oblivion" then
                        if isTarget then prevDmg = math.floor(mo.hp * 0.5) end
                    elseif selC.id == "rampage" then
                        if isTarget then prevDmg = math.floor(pDmg * 0.5) * 3; if battle.powerNext then prevDmg = prevDmg * 2 end end
                    elseif selC.id == "furyCleave" then
                        if isTarget then
                            local mult = ((battle.fury or 0) >= 3) and 1.2 or 0.8
                            prevDmg = math.floor(pDmg * mult); if battle.powerNext then prevDmg = prevDmg * 2 end
                        end
                    elseif selC.id == "thunder" then
                        prevDmg = 15
                    elseif selC.id == "firestorm" then
                        local mult = CARD_DEF[selC.id].mult or 1.0
                        prevDmg = math.floor(pDmg * mult); if battle.powerNext then prevDmg = prevDmg * 2 end
                    end
                    if prevDmg > 0 then
                        local afterHP = math.max(0, mo.hp - prevDmg)
                        local afterFill = afterHP / mo.maxHP
                        local costAlpha = math.floor(150 + 80 * math.sin(battle.timer * 6))
                        drawGradientBar(moBarX2 + moBarWEach * afterFill, moBarY2,
                            moBarWEach * (moHPFill - afterFill), mBarH, mBarR, 255, 255, 80, costAlpha)
                    end
                end
            end
            -- HP数字
            local hpFs = monsterCount > 2 and (fs * 0.6) or (fs * 0.75)
            drawTextCenter(math.max(0, math.floor(mo.hp)) .. "", moX, moBarY2 + mBarH + hpFs * 0.5, hpFs, 255, 100, 100, moAlpha)

            -- （技能描述已移至伤害上方显示，点击可查看详情）
        end

        -- 选中卡牌时显示预计伤害
        if battle.selectedCard and battle.phase == "waiting_for_card" and mo.alive then
            local selCard = battle.hand[battle.selectedCard]
            if selCard then
                local previewText = nil
                local previewR, previewG, previewB = 255, 80, 80
                local isTarget = (mi == (battle.targetIdx or getFirstAliveMonster())) -- 是否为当前目标
                local pDmg = applyGemDmg(math.max(0, mo.playerDmg), selCard.gem)
                -- 暴击/易伤/怒火加成（与实际伤害计算一致）
                if player.skills.crit and not battle.critUsed and pDmg > 0 then pDmg = math.floor(pDmg * 1.5) end
                if mo.effects and mo.effects.vulnerable and mo.effects.vulnerable > 0 then pDmg = math.floor(pDmg * 1.5) end
                local pvFury2 = battle.fury or 0
                if pvFury2 > 0 then pDmg = math.floor(pDmg * (1 + pvFury2 * 0.1)) end

                if selCard.id == "strike" or selCard.id == "drain" then
                    if isTarget then
                        local d = pDmg
                        -- 破甲之力：无视DEF，重新计算
                        if selCard.id == "strike" and battle.armorStanceNext then
                            local abDmg = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                            d = applyGemDmg(math.max(0, abDmg), selCard.gem)
                            if player.skills.crit and not battle.critUsed and d > 0 then d = math.floor(d * 1.5) end
                            if mo.effects and mo.effects.vulnerable and mo.effects.vulnerable > 0 then d = math.floor(d * 1.5) end
                            if pvFury2 > 0 then d = math.floor(d * (1 + pvFury2 * 0.1)) end
                        end
                        if battle.powerNext then d = d * 2 end
                        previewText = "-" .. d
                    end
                elseif selCard.id == "heavyStrike" or selCard.id == "cleave" then
                    if isTarget then
                        local d = math.floor(pDmg * 1.5)
                        if battle.powerNext then d = d * 2 end
                        previewText = "-" .. d
                    end
                elseif selCard.id == "haste" then
                    if isTarget then
                        local d = pDmg
                        if battle.powerNext then d = d * 2 end
                        previewText = "-" .. d .. "x2"
                    end
                elseif selCard.id == "execute" then
                    if isTarget then
                        if mo.hp <= mo.maxHP * 0.2 then
                            previewText = "击杀!"
                        else
                            previewText = "-" .. pDmg
                        end
                    end
                elseif selCard.id == "armorBreak" then
                    if isTarget then
                        local abDmg = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                        abDmg = applyGemDmg(math.max(0, abDmg), selCard.gem)
                        if player.skills.crit and not battle.critUsed and abDmg > 0 then abDmg = math.floor(abDmg * 1.5) end
                        if mo.effects and mo.effects.vulnerable and mo.effects.vulnerable > 0 then abDmg = math.floor(abDmg * 1.5) end
                        if (battle.fury or 0) > 0 then abDmg = math.floor(abDmg * (1 + (battle.fury or 0) * 0.1)) end
                        if battle.powerNext then abDmg = abDmg * 2 end
                        previewText = "-" .. abDmg
                    end
                elseif selCard.id == "rend" or selCard.id == "savageBash" then
                    if isTarget then
                        local mult = selCard.id == "rend" and 0.5 or 0.6
                        local d = math.floor(pDmg * mult)
                        if battle.powerNext then d = d * 2 end
                        previewText = "-" .. d
                    end
                elseif selCard.id == "oblivion" then
                    if isTarget then previewText = "-" .. math.floor(mo.hp * 0.5) end
                elseif selCard.id == "rampage" then
                    if isTarget then
                        local d = math.floor(pDmg * 0.5)
                        if battle.powerNext then d = d * 2 end
                        previewText = "-" .. d .. "x3"
                    end
                elseif selCard.id == "furyCleave" then
                    if isTarget then
                        local mult = ((battle.fury or 0) >= 3) and 1.2 or 0.8
                        local d = math.floor(pDmg * mult)
                        if battle.powerNext then d = d * 2 end
                        previewText = "-" .. d
                    end
                elseif selCard.id == "thunder" then
                    previewText = "-15"
                elseif selCard.id == "firestorm" then
                    local d = pDmg
                    if battle.powerNext then d = d * 2 end
                    previewText = "-" .. d
                elseif selCard.id == "heal" then
                    -- 不显示怪物上的伤害
                elseif selCard.id == "guard" then
                    -- 不显示
                elseif selCard.id == "defend" then
                    -- 不显示（护盾类）
                elseif selCard.id == "poison" then
                    previewText = "毒3回合"
                    previewR, previewG, previewB = 120, 220, 60
                elseif selCard.id == "venomBlade" then
                    if isTarget then
                        local d = pDmg
                        if battle.powerNext then d = d * 2 end
                        previewText = "-" .. d .. " 毒"
                    end
                elseif selCard.id == "power" then
                    -- 不显示
                elseif selCard.id == "weaken" then
                    previewText = "ATK减半"
                    previewR, previewG, previewB = 150, 130, 220
                elseif selCard.id == "reflect" then
                    -- 不显示
                end

                -- 暴击标记：预估文本后加 !
                if previewText and player.skills.crit and not battle.critUsed and mo.playerDmg > 0 then
                    previewText = previewText .. "!"
                end
                if previewText then
                    local prevFs = monsterCount > 2 and (fs * 0.6) or (fs * 0.85)
                    local hpFsLocal = monsterCount > 2 and (fs * 0.6) or (fs * 0.75)
                    local prevY = moBarY2 + mBarH + hpFsLocal * 1.2 + prevFs * 0.3
                    drawTextCenter(previewText, moX, prevY, prevFs, previewR, previewG, previewB, 230)
                end
            end
        end

        -- 每个怪物的持续效果小图标（HP条下方）
        local effIconY = midY + moSpriteSize / 2 + mBarH + fs * 1.2
        local effIconSize = math.max(10, fs * 0.72)
        local effIconGap = math.max(2, effIconSize * 0.18)
        local effIcons = {}
        if mo.alive then
            if mo.effects.poison and mo.effects.poison > 0 then
                table.insert(effIcons, {iconId = "status_poison", value = tostring(mo.effects.poison), r = 120, g = 200, b = 60,
                    name = "中毒", desc = "每回合受到" .. mo.effects.poison .. "点伤害，层数逐回合递减"})
            end
            if mo.effects.weaken then
                table.insert(effIcons, {iconId = "status_weaken", value = tostring(mo.effects.weaken.turns), r = 150, g = 130, b = 200,
                    name = "削弱", desc = "攻击力减半，剩余" .. mo.effects.weaken.turns .. "回合"})
            end
            if mo.effects.vulnerable and mo.effects.vulnerable > 0 then
                table.insert(effIcons, {iconId = "status_vulnerable", value = tostring(mo.effects.vulnerable), r = 255, g = 130, b = 30,
                    name = "易伤", desc = "受到伤害增加50%，剩余" .. mo.effects.vulnerable .. "回合"})
            end
        end
        if #effIcons > 0 then
            local startX = moX - (#effIcons * effIconSize + (#effIcons - 1) * effIconGap) / 2 + effIconSize / 2
            for ei, eff in ipairs(effIcons) do
                local iconX = startX + (ei - 1) * (effIconSize + effIconGap)
                if not spr.drawIcon(eff.iconId, iconX, effIconY, effIconSize, moAlpha / 255) then
                    drawRoundRect(iconX - effIconSize / 2, effIconY - effIconSize / 2, effIconSize, effIconSize, 3, eff.r, eff.g, eff.b, math.floor(moAlpha * 0.65))
                end
                local badgeFs = math.max(6, effIconSize * 0.45)
                local badgeX = iconX + effIconSize * 0.32
                local badgeY = effIconY + effIconSize * 0.32
                nvgFontFace(nvgCtx, "sans")
                nvgFontSize(nvgCtx, badgeFs)
                nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, math.floor(moAlpha * 0.85)))
                for ox = -1, 1 do
                    for oy = -1, 1 do
                        if ox ~= 0 or oy ~= 0 then nvgText(nvgCtx, badgeX + ox, badgeY + oy, eff.value) end
                    end
                end
                nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, moAlpha))
                nvgText(nvgCtx, badgeX, badgeY, eff.value)
                -- 记录点击区域
                table.insert(battle._moEffectRects, {
                    x = iconX - effIconSize * 0.8, y = effIconY - effIconSize * 0.8,
                    w = effIconSize * 1.6, h = effIconSize * 1.6,
                    st = {name = eff.name, desc = eff.desc, iconId = eff.iconId, r = eff.r, g = eff.g, b = eff.b, icon = ""},
                })
            end
        end
    end

    -- === VS 文字（玩家和第一个怪物中间） ===
    do
        local firstMoX
        if monsterCount == 1 then
            firstMoX = px + pw * 0.8
        else
            firstMoX = moAreaX + moAreaW * 0.5 / monsterCount
        end
        local vsX = (plX + firstMoX) / 2
        local vsFs = math.max(14, fs * 1.1)
        local vsAlpha = math.floor(180 + 50 * math.sin(battle.timer * 3))
        drawTextCenter("VS", vsX, midY, vsFs, 255, 200, 80, vsAlpha)
    end

    -- === 顶部标题栏 ===
    local centerX = px + pw / 2
    local titleFs = fs * 0.9
    local titleY = py + titleFs * 0.7
    drawRoundRect(px + 4, py + 2, pw - 8, titleFs * 1.3, 4, 50, 40, 80, 200)
    local titleLabel = "第 " .. (battle.round + 1) .. " 回合"
    drawTextCenter(titleLabel, px + pw / 2, titleY, titleFs, 255, 220, 100)

    -- === 顶部提示区（标题栏下方） ===
    local tipY = titleY + titleFs * 1.0
    local tipFs = fs * 0.95

    if battle.phase == "card_effect" and battle.effectText ~= "" then
        drawRoundRect(px + 8, tipY - tipFs * 0.5, pw - 16, tipFs * 1.4, 4, 60, 50, 20, 200)
        drawTextCenter(battle.effectText, centerX, tipY + tipFs * 0.15, tipFs, 255, 255, 100, 230)
    elseif battle.effectTimer > 0 and battle.phase == "waiting_for_card" then
        drawRoundRect(px + 8, tipY - tipFs * 0.5, pw - 16, tipFs * 1.4, 4, 50, 30, 10, 180)
        drawTextCenter(battle.effectText, centerX, tipY + tipFs * 0.15, tipFs * 0.9, 255, 150, 80, math.min(255, math.floor(battle.effectTimer * 500)))
    elseif battle.phase == "result" then
        local totalGoldShow = battle.totalGold
        if player.skills.greed then totalGoldShow = totalGoldShow * 2 end
        drawRoundRect(px + 8, tipY - tipFs * 0.5, pw - 16, tipFs * 1.4, 4, 50, 50, 10, 200)
        drawTextCenter("胜利！金币+" .. totalGoldShow, centerX, tipY + tipFs * 0.15, tipFs, 255, 220, 50)
    end

    -- 怪物攻击伤害提示（在角色精灵附近显示）
    if battle.phase == "monster_atk" and battle.atkIndex >= 1 and battle.timer < 0.6 then
        local atkTextY = midY - spriteSize * 0.5
        if battle.guardActive then
            drawTextCenter("格挡！", plX, atkTextY, fs, 100, 160, 255, 220)
        elseif battle.atkShielded then
            drawTextCenter("圣盾！", plX, atkTextY, fs, 100, 200, 255, 220)
        elseif (battle.atkShieldAbsorb or 0) > 0 then
            local absorbed = battle.atkShieldAbsorb
            local remain = (battle.atkActualDmg or 0)
            if remain > 0 then
                -- 护盾被击破，显示溢出的HP伤害（红色）
                drawTextCenter("-" .. remain, plX, atkTextY, fs * 1.5, 255, 50, 50, 240)
                spr.drawIcon("status_shield", plX - fs * 0.8, atkTextY - fs * 1.4, fs * 0.8)
                drawTextCenter("-" .. absorbed, plX + fs * 0.3, atkTextY - fs * 1.4, fs * 0.9, 130, 200, 255, 180)
            else
                -- 护盾完全吸收，显示护盾减少量
                spr.drawIcon("status_shield", plX - fs * 0.7, atkTextY, fs * 1.0)
                drawTextCenter("-" .. absorbed, plX + fs * 0.4, atkTextY, fs * 1.2, 130, 200, 255, 230)
            end
        elseif (battle.atkActualDmg or 0) > 0 then
            drawTextCenter("-" .. battle.atkActualDmg, plX, atkTextY, fs * 1.5, 255, 50, 50, 240)
        else
            drawTextCenter("MISS", plX, atkTextY, fs, 150, 150, 255, 220)
        end
    end

    -- === 浮动伤害/治疗文字 ===
    for _, ft in ipairs(floatTexts) do
        local progress = ft.timer / ft.duration  -- 0→1
        local ftAlpha = math.floor(255 * math.max(0, 1 - progress * progress))  -- 先快后慢淡出
        local floatUp = progress * fs * 2  -- 上飘距离
        local ftFs = fs * 1.4 * (1 + (1 - progress) * 0.15)  -- 初始稍大，逐渐回缩
        local ftX, ftY
        if ft.targetIdx then
            -- 怪物上方
            local fmi = ft.targetIdx
            if monsterCount == 1 then
                ftX = px + pw * 0.8
            else
                ftX = moAreaX + moAreaW * (fmi - 0.5) / monsterCount
            end
            ftY = midY - moSpriteSize * 0.5 - floatUp
        else
            -- 玩家上方
            ftX = plX
            ftY = midY - spriteSize * 0.5 - floatUp
        end
        drawTextCenter(ft.text, ftX, ftY, ftFs, ft.r, ft.g, ft.b, ftAlpha)
    end

    -- VS 和回合信息已移至顶部标题栏

    -- 持续效果指示器（全局效果：蓄力/反射）
    local effectY = py + battleH - fs * 1.5
    local effectX = px + 8
    local effFs = math.max(7, fs * 0.7)
    if battle.powerNext then
        drawTextLeft("蓄力!", effectX, effectY, effFs, 255, 120, 40)
        effectX = effectX + effFs * 4
    end
    if battle.reflectActive then
        drawTextLeft("反射!", effectX, effectY, effFs, 200, 220, 255)
    end

    -- === 选中卡牌时记录关键词（绘制在卡牌区域之后） ===
    battle._selectedTips = nil
    if battle.selectedCard and battle.phase == "waiting_for_card" and cardDrag.active then
        local selC = battle.hand[battle.selectedCard]
        if selC then
            local cdef = CARD_DEF[selC.id]
            if cdef then
                local tips = collectKeywordTips(cdef)
                if #tips > 0 then
                    battle._selectedTips = tips
                end
            end
        end
    end

    -- === 底部卡牌手牌区域（扇形布局，参考RM CardSystem） ===
    local numCards = #battle.hand
    if numCards > 0 and battle.phase ~= "result" then
        local isPortraitCard = logicalH > logicalW
        local cardH = isPortraitCard
            and math.max(120, math.min(logicalW * 0.38, 165))  -- 竖屏：适中大小
            or  math.max(130, math.min(logicalH * 0.27, 180))
        cardH = math.floor(cardH * 0.9 * (cardDev.p.cardScale or 1.0))
        local cardW = math.floor(cardH * 0.68)

        -- 扇形参数
        local fanRadius = isPortraitCard
            and math.max(220, logicalW * 0.8)                  -- 竖屏：适中半径
            or  math.max(250, logicalH * 0.55)
        local arcCenterX = logicalW / 2
        local arcCenterY = logicalH + fanRadius * 0.78      -- 圆心在屏幕下方
        local maxAngle = isPortraitCard and 30 or 35          -- 竖屏：适当展开
        local anglePerCard = isPortraitCard and 7 or 8        -- 竖屏：适中间隔
        local selectedLiftY = cardH * 0.25                    -- 选中上浮距离
        local hoverLiftY = cardH * 0.12                       -- 悬浮上浮距离（比选中小）
        local selectedRotRatio = 0.25                         -- 选中旋转修正（趋于水平）
        local selectedScale = 1.2                             -- 选中缩放
        local hoverScale = 1.08                               -- 悬浮缩放（轻微放大）
        local animSpeed = 1.0 - ((1.0 - 0.18) ^ (battle.speed or 1)) -- 动画插值速度（倍速加速）

        local spreadAngle = math.min(maxAngle, (numCards - 1) * anglePerCard)
        local selIdx = battle.selectedCard

        -- 清理多余动画状态
        while #cardAnims > numCards do table.remove(cardAnims) end

        -- 计算每张牌的目标位置并插值
        for i = 1, numCards do
            local t = numCards > 1 and ((i - 1) / (numCards - 1)) or 0.5
            local angleDeg = -spreadAngle / 2 + t * spreadAngle
            local rad = math.rad(angleDeg)
            local tx = arcCenterX + fanRadius * math.sin(rad)
            local ty = arcCenterY - fanRadius * math.cos(rad)
            local trot = rad
            local tscale = 1.0

            -- 选中：上浮 + 缩放；悬浮：轻微上浮 + 轻微缩放
            if selIdx == i and not (cardDrag.active and cardDrag.cardIndex == i) then
                ty = ty - selectedLiftY
            elseif battle.hoveredCard == i and selIdx ~= i and not (cardDrag.active and cardDrag.cardIndex == i) then
                ty = ty - hoverLiftY
                tscale = hoverScale
            end

            -- 初始化或平滑插值
            if not cardAnims[i] then
                -- 发牌动画：新牌从牌库位置（左下角）飞入
                if cardDealAnim.active and i >= cardDealAnim.startIdx then
                    local dealIdx = i - cardDealAnim.startIdx  -- 第几张新牌（从0开始）
                    local delay = dealIdx * cardDealAnim.delayPerCard
                    cardAnims[i] = {x = 30, y = logicalH + 50, rot = 0, scale = 0.3, dealDelay = delay}
                else
                    cardAnims[i] = {x = tx, y = ty, rot = trot, scale = tscale}
                end
            else
                local a = cardAnims[i]
                -- 发牌延迟：等待延迟结束后才开始移动
                if a.dealDelay and a.dealDelay > 0 then
                    a.dealDelay = a.dealDelay - time:GetTimeStep() * (battle.speed or 1)
                else
                    a.dealDelay = nil
                    a.x = a.x + (tx - a.x) * animSpeed
                    a.y = a.y + (ty - a.y) * animSpeed
                    a.rot = a.rot + (trot - a.rot) * animSpeed
                    a.scale = a.scale + (tscale - a.scale) * animSpeed
                end
            end
        end

        -- 发牌动画结束检测
        if cardDealAnim.active then
            local allArrived = true
            for i = cardDealAnim.startIdx, cardDealAnim.startIdx + cardDealAnim.count - 1 do
                local a = cardAnims[i]
                if a and a.dealDelay and a.dealDelay > 0 then
                    allArrived = false
                    break
                end
            end
            if allArrived then
                cardDealAnim.active = false
            end
        end

        -- 牌库/弃牌计数 + 结束回合按钮（屏幕最底部）
        if battle.phase == "waiting_for_card" then
            local baseCardH = cardH / (cardDev.p.cardScale or 1.0)  -- 用未缩放尺寸计算UI
            local counterFs = math.max(9, baseCardH * 0.11)
            local bottomY = logicalH - counterFs * 1.8
            -- 牌库按钮（可点击查看）
            local deckText = "牌库:" .. #battle.deck
            local deckTW = counterFs * #deckText * 0.55
            local deckX, deckY = 8, bottomY - counterFs * 0.6
            local deckBtnW = math.max(deckTW, counterFs * 3.5)
            local deckBtnH = counterFs * 1.4
            drawRoundRect(deckX - 2, deckY, deckBtnW, deckBtnH, 3, 40, 50, 80, 160)
            drawTextLeft(deckText, deckX + 2, deckY + deckBtnH * 0.55, counterFs, 150, 180, 220)
            battle._deckRect = {x = deckX - 2, y = deckY, w = deckBtnW, h = deckBtnH}

            -- 弃牌按钮（右侧，可点击查看）
            local discText = "弃牌:" .. #battle.discard
            local discBtnW = math.max(counterFs * 3.5, counterFs * #discText * 0.55)
            local discX = logicalW - discBtnW - 6
            drawRoundRect(discX - 2, deckY, discBtnW, deckBtnH, 3, 60, 40, 50, 160)
            drawTextLeft(discText, discX + 2, deckY + deckBtnH * 0.55, counterFs, 180, 150, 150)
            battle._discardRect = {x = discX - 2, y = deckY, w = discBtnW, h = deckBtnH}

            -- 结束回合 + 逃跑按钮（屏幕最底部）
            local btnW = math.max(80, logicalW * 0.26)
            local btnH = math.max(30, counterFs * 2.8)
            local gap = 8
            local totalW = btnW * 2 + gap
            local startX = logicalW / 2 - totalW / 2
            local btnY = logicalH - btnH - counterFs * 1.5

            -- 结束回合按钮（左）
            local endX = startX
            battle._endTurnBtn = {x = endX, y = btnY, w = btnW, h = btnH}
            drawRoundRect(endX, btnY, btnW, btnH, 4, 60, 50, 90, 220)
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, endX, btnY, btnW, btnH, 4)
            nvgStrokeColor(nvgCtx, nvgRGBA(140, 130, 200, 200))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
            local btnFs = math.max(10, btnH * 0.35)
            drawTextCenter("结束回合", endX + btnW / 2, btnY + btnH * 0.35, btnFs, 220, 210, 255)
            local subFs = math.max(7, btnFs * 0.7)
            drawTextCenter("恢复" .. battle.mpRegen .. "MP", endX + btnW / 2, btnY + btnH * 0.72, subFs, 130, 130, 255)

            -- 逃跑按钮（右）
            local fleeX = startX + btnW + gap
            battle._fleeBtn = {x = fleeX, y = btnY, w = btnW, h = btnH}
            local fleeConfirm = battle.fleeConfirm or false
            local fleeBgR = fleeConfirm and 130 or 90
            local fleeBgG = fleeConfirm and 40 or 50
            local fleeBgB = fleeConfirm and 40 or 50
            drawRoundRect(fleeX, btnY, btnW, btnH, 4, fleeBgR, fleeBgG, fleeBgB, 220)
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, fleeX, btnY, btnW, btnH, 4)
            nvgStrokeColor(nvgCtx, nvgRGBA(fleeConfirm and 255 or 200, 130, 130, 200))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
            if fleeConfirm then
                drawTextCenter("确认逃跑?", fleeX + btnW / 2, btnY + btnH * 0.35, btnFs, 255, 100, 100)
                drawTextCenter("被攻击一次", fleeX + btnW / 2, btnY + btnH * 0.72, subFs, 255, 180, 130)
            else
                drawTextCenter("逃跑", fleeX + btnW / 2, btnY + btnH * 0.5, btnFs, 255, 200, 200)
            end
        end

        -- 绘制顺序：未选中从左到右，选中最后（置顶）
        local drawOrder = {}
        for i = 1, numCards do
            if i ~= selIdx and not (cardDrag.active and cardDrag.cardIndex == i) then
                table.insert(drawOrder, i)
            end
        end
        if selIdx and selIdx >= 1 and selIdx <= numCards
           and not (cardDrag.active and cardDrag.cardIndex == selIdx) then
            table.insert(drawOrder, selIdx)
        end

        for _, i in ipairs(drawOrder) do
            local a = cardAnims[i]
            if a then
                local sw = cardW * a.scale
                local sh = cardH * a.scale
                nvgSave(nvgCtx)
                nvgTranslate(nvgCtx, a.x, a.y)    -- 锚点：卡牌底部中心
                nvgRotate(nvgCtx, a.rot)
                drawCard(-sw / 2, -sh, sw, sh, battle.hand[i], selIdx == i, false)
                -- consumeOne 选择模式视觉反馈
                if battle.consumeSelect then
                    local cs = battle.consumeSelect
                    if i == cs.cardIndex then
                        -- 源卡牌：半透明遮罩
                        nvgBeginPath(nvgCtx)
                        nvgRoundedRect(nvgCtx, -sw / 2, -sh, sw, sh, 5)
                        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 120))
                        nvgFill(nvgCtx)
                    else
                        -- 可选卡牌：发光边框
                        local pulse = 0.6 + 0.4 * math.sin(os.clock() * 4)
                        local alpha = math.floor(180 * pulse)
                        nvgBeginPath(nvgCtx)
                        nvgRoundedRect(nvgCtx, -sw / 2 - 2, -sh - 2, sw + 4, sh + 4, 6)
                        nvgStrokeColor(nvgCtx, nvgRGBA(255, 220, 80, alpha))
                        nvgStrokeWidth(nvgCtx, 2.5)
                        nvgStroke(nvgCtx)
                    end
                end
                nvgRestore(nvgCtx)
            end
        end

        -- 拖拽中的卡牌
        if cardDrag.active and cardDrag.cardIndex >= 1 and cardDrag.cardIndex <= numCards then
            -- 拖动时不显示原位占位框
            -- 浮动卡牌跟随手指（无旋转，放大）
            local dragCard = battle.hand[cardDrag.cardIndex]
            local ds = selectedScale
            local dsw = cardW * ds
            local dsh = cardH * ds
            local dcx = cardDrag.curX - dsw * cardDrag.offsetX
            local dcy = cardDrag.curY - dsh * cardDrag.offsetY
            drawCard(dcx, dcy, dsw, dsh, dragCard, true, true)
        end

    end

    -- === 选中卡牌的关键词解释框（绘制在所有卡牌之上） ===
    if battle._selectedTips and battle.selectedCard and cardAnims[battle.selectedCard] then
        local sa = cardAnims[battle.selectedCard]
        local glossFs = math.max(7, fs * 0.42)
        local glossW = math.min(180, logicalW * 0.35)
        -- 计算选中卡牌的屏幕位置
        local isPortraitGl = logicalH > logicalW
        local selCardBaseH = isPortraitGl
            and math.max(120, math.min(logicalW * 0.38, 165))
            or  math.max(130, math.min(logicalH * 0.27, 180))
        selCardBaseH = math.floor(selCardBaseH * (cardDev.p.cardScale or 1.0))
        local selCardW = math.floor(selCardBaseH * 0.68)
        local selCardH = selCardBaseH
        local selScale = 1.2  -- selectedScale

        -- 拖拽时跟随拖拽位置，否则跟随扇形动画位置
        local anchorX, anchorY
        if cardDrag.active and cardDrag.cardIndex == battle.selectedCard then
            local dsw = selCardW * selScale
            local dsh = selCardH * selScale
            anchorX = cardDrag.curX - dsw * cardDrag.offsetX + dsw / 2
            anchorY = cardDrag.curY - dsh * cardDrag.offsetY
        else
            anchorX = sa.x
            anchorY = sa.y - selCardH * (sa.scale or 1)
        end

        local renderW = selCardW * selScale
        local renderH = selCardH * selScale
        local cardRight = anchorX + renderW * 0.5
        local cardLeft = anchorX - renderW * 0.5
        local cardTop = anchorY
        -- 默认放右侧，空间不够放左侧
        local glossGap = 2
        local glossX
        if cardRight + glossGap + glossW < logicalW - 5 then
            glossX = cardRight + glossGap
        else
            glossX = cardLeft - glossW - glossGap
        end
        local glossY = math.max(5, cardTop)
        drawKeywordGlossary(battle._selectedTips, glossX, glossY, glossW, glossFs)
    end

    -- 弃牌动画：手牌飞向弃牌堆（必须在 numCards 条件外，因为弃牌后手牌为空）
    if cardDiscardAnim.active then
        cardDiscardAnim.timer = cardDiscardAnim.timer + time:GetTimeStep() * (battle.speed or 1)
        local progress = cardDiscardAnim.timer / cardDiscardAnim.duration
        if progress >= 1.0 then
            cardDiscardAnim.active = false
            cardDiscardAnim.cards = {}
        else
            local isPortraitDA = logicalH > logicalW
            local daCardH = isPortraitDA
                and math.max(120, math.min(logicalW * 0.38, 165))
                or  math.max(130, math.min(logicalH * 0.27, 180))
            daCardH = math.floor(daCardH * (cardDev.p.cardScale or 1.0))
            local daCardW = math.floor(daCardH * 0.68)
            local discardTargetX = logicalW / 2
            local discardTargetY = logicalH + 60
            for ci, dc in ipairs(cardDiscardAnim.cards) do
                local cardDelay = (ci - 1) * 0.06
                local cardProgress = math.max(0, (cardDiscardAnim.timer - cardDelay) / (cardDiscardAnim.duration - cardDelay))
                cardProgress = math.min(1.0, cardProgress)
                local t = 1 - (1 - cardProgress) * (1 - cardProgress)
                local cx = dc.startX + (discardTargetX - dc.startX) * t
                local cy = dc.startY + (discardTargetY - dc.startY) * t
                local cr = dc.startRot + (0.5 - dc.startRot) * t
                local cs = dc.startScale * (1 - t * 0.5)
                local alpha = math.max(0, 1 - t * 0.9)
                if alpha > 0.01 then
                    local sw = daCardW * cs
                    local sh = daCardH * cs
                    nvgSave(nvgCtx)
                    nvgGlobalAlpha(nvgCtx, alpha)
                    nvgTranslate(nvgCtx, cx, cy)
                    nvgRotate(nvgCtx, cr)
                    drawCard(-sw / 2, -sh, sw, sh, dc.cardInfo, false, false)
                    nvgRestore(nvgCtx)
                end
            end
        end
    end

    -- === 诅咒卡植入动画（从怪物位置飞到手牌区域） ===
    if curseInsertAnim.active then
        curseInsertAnim.timer = curseInsertAnim.timer + time:GetTimeStep() * (battle.speed or 1)
        local totalDur = curseInsertAnim.flyDuration + curseInsertAnim.holdDuration
        if curseInsertAnim.timer >= totalDur then
            curseInsertAnim.active = false
            curseInsertAnim.cards = {}
        else
            local isPortraitCI = logicalH > logicalW
            -- 增大卡牌尺寸
            local ciCardH = isPortraitCI
                and math.max(160, math.min(logicalW * 0.45, 220))
                or  math.max(170, math.min(logicalH * 0.32, 230))
            local ciCardW = math.floor(ciCardH * 0.68)

            -- 目标位置：屏幕中央偏下
            local targetX = logicalW / 2
            local targetY = logicalH * 0.45

            for ci, cc in ipairs(curseInsertAnim.cards) do
                local cardDelay = cc.delay or 0
                local elapsed = curseInsertAnim.timer - cardDelay
                if elapsed > 0 then
                    local flyDur = curseInsertAnim.flyDuration - cardDelay
                    local flyT = math.min(1.0, elapsed / math.max(0.01, flyDur))
                    -- ease-out: 先快后慢
                    local t = 1 - (1 - flyT) * (1 - flyT)

                    -- 起点：从怪物位置获取
                    local startX = logicalW * 0.75
                    local startY = logicalH * 0.35
                    if battle._monsterRects and battle._monsterRects[cc.monsterIdx] then
                        local mr = battle._monsterRects[cc.monsterIdx]
                        startX = mr.x + mr.w / 2
                        startY = mr.y + mr.h / 2
                    end

                    local cx, cy, scale, rot
                    if flyT < 1.0 then
                        -- 飞行阶段
                        cx = startX + (targetX - startX) * t
                        cy = startY + (targetY - startY) * t
                        scale = 0.3 + 0.7 * t
                        rot = (1 - t) * 0.3
                    else
                        -- 停留展示阶段：卡牌在中央静止展示
                        cx = targetX
                        cy = targetY
                        scale = 1.0
                        rot = 0

                        -- 多张卡牌横向排开
                        local totalCards = #curseInsertAnim.cards
                        if totalCards > 1 then
                            local spacing = ciCardW * 0.4
                            local offsetX = (ci - 1 - (totalCards - 1) / 2) * spacing
                            cx = cx + offsetX
                        end
                    end

                    -- 透明度：飞行阶段淡入，停留阶段完全不透明，最后淡出
                    local alpha = 1.0
                    if flyT < 1.0 then
                        alpha = math.min(1.0, t * 3)
                    else
                        -- 停留阶段最后 0.2 秒淡出
                        local holdElapsed = elapsed - math.max(0.01, flyDur)
                        local fadeStart = curseInsertAnim.holdDuration - 0.2
                        if holdElapsed > fadeStart then
                            alpha = 1.0 - (holdElapsed - fadeStart) / 0.2
                        end
                    end

                    if alpha > 0.01 then
                        local sw = ciCardW * scale
                        local sh = ciCardH * scale
                        nvgSave(nvgCtx)
                        nvgGlobalAlpha(nvgCtx, alpha)
                        nvgTranslate(nvgCtx, cx, cy)
                        nvgRotate(nvgCtx, rot)
                        drawCard(-sw / 2, -sh / 2, sw, sh, {id = cc.cardId}, true, false)
                        nvgRestore(nvgCtx)
                    end
                end
            end
        end
    end
end

-- ============================================================
