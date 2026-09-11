-- ============================================================
-- MapGenerator.lua — 魔塔随机地图生成器 v2
-- 使用迷宫雕刻法生成类似手工地图的走廊+房间布局
-- ============================================================
local MapGenerator = {}

local GRID = 11
local TOTAL_FLOORS = 50
local DIRS = {{-1,0},{1,0},{0,-1},{0,1}}

-- 前置声明（定义在文件后部）
local BOSS_TEMPLATES

-- ============================================================
-- 随机数工具
-- ============================================================
local function randInt(a, b) return math.random(a, b) end
local function randPick(t) return t[randInt(1, #t)] end
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = randInt(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

-- ============================================================
-- 网格工具
-- ============================================================
local function inBounds(r, c)
    return r >= 2 and r <= GRID - 1 and c >= 2 and c <= GRID - 1
end

--- 创建全墙网格（内部全是墙，后续通过雕刻打通）
local function createFullGrid()
    local g = {}
    for r = 1, GRID do
        g[r] = {}
        for c = 1, GRID do
            g[r][c] = 'W'
        end
    end
    return g
end

local function countFloor(g)
    local n = 0
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            if g[r][c] ~= 'W' then n = n + 1 end
        end
    end
    return n
end

-- ============================================================
-- BFS 工具
-- ============================================================
local function bfsDistance(g, sr, sc, passSet)
    local dist = {}
    for r = 1, GRID do
        dist[r] = {}
        for c = 1, GRID do dist[r][c] = -1 end
    end
    dist[sr][sc] = 0
    local queue = {{sr, sc}}
    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        local d0 = dist[cur[1]][cur[2]]
        for _, d in ipairs(DIRS) do
            local nr, nc = cur[1] + d[1], cur[2] + d[2]
            if inBounds(nr, nc) and dist[nr][nc] == -1 then
                local ch = g[nr][nc]
                local blocked = (ch == 'W')
                if not blocked and (ch == 'Y' or ch == 'B' or ch == 'R') then
                    if not (passSet and passSet[nr .. "," .. nc]) then
                        blocked = true
                    end
                end
                if not blocked then
                    dist[nr][nc] = d0 + 1
                    queue[#queue + 1] = {nr, nc}
                end
            end
        end
    end
    return dist
end

local function getReachableEmpty(g, dist)
    local cells = {}
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            if dist[r][c] >= 0 and g[r][c] == '.' then
                cells[#cells + 1] = {r = r, c = c, d = dist[r][c]}
            end
        end
    end
    return cells
end

local function isConnectedFloor(g)
    ---@type number|nil
    local sr = nil
    ---@type number|nil
    local sc = nil
    ---@type number
    local total = 0
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            if g[r][c] ~= 'W' then
                total = total + 1
                if not sr then
                    sr = r
                    sc = c
                end
            end
        end
    end
    if not sr or not sc then return false end
    local visited = {}
    for r = 1, GRID do visited[r] = {} end
    ---@type number[][]
    local queue = {{sr, sc}}
    visited[sr][sc] = true
    local head, reached = 1, 0
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        reached = reached + 1
        for _, d in ipairs(DIRS) do
            local nr, nc = cur[1] + d[1], cur[2] + d[2]
            if inBounds(nr, nc) and not visited[nr][nc] and g[nr][nc] ~= 'W' then
                visited[nr][nc] = true
                queue[#queue + 1] = {nr, nc}
            end
        end
    end
    return reached == total
end

-- ============================================================
-- 阶段 1: 迷宫雕刻 (DFS recursive backtracker, step=1)
-- 在 9×9 内部区域雕刻走廊
-- ============================================================
local function carveMaze(g, startR, startC)
    g[startR][startC] = '.'
    local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
    shuffle(dirs)
    for _, d in ipairs(dirs) do
        -- step=1: 只走1格（而非经典迷宫的2格），产生更密集的走廊
        local nr, nc = startR + d[1], startC + d[2]
        if inBounds(nr, nc) and g[nr][nc] == 'W' then
            -- 检查新格子周围已打通的格子数（不含来源格）
            local openNeighbors = 0
            for _, d2 in ipairs(DIRS) do
                local ar, ac = nr + d2[1], nc + d2[2]
                if inBounds(ar, ac) and g[ar][ac] ~= 'W' then
                    openNeighbors = openNeighbors + 1
                end
            end
            -- 只有1个已打通邻居（即来源格）时才雕刻，保证走廊不会太开阔
            if openNeighbors <= 1 then
                carveMaze(g, nr, nc)
            end
        end
    end
end

-- ============================================================
-- 阶段 2: 开拓房间和额外通道
-- ============================================================

--- 在迷宫中开辟小房间（2×2 或 2×3 的空地）
local function carveRooms(g, count)
    local attempts = 0
    local carved = 0
    while carved < count and attempts < 80 do
        attempts = attempts + 1
        local rr = randInt(3, GRID - 3)
        local rc = randInt(3, GRID - 3)
        -- 2×2 或 2×3 随机
        local rw = randInt(2, 3)
        local rh = 2
        if randInt(1, 2) == 1 then rw, rh = rh, rw end

        -- 检查：房间区域至少有一个已打通格子（与迷宫连通），且不全是空地
        local hasFloor = false
        local hasWall = false
        local ok = true
        for dr = 0, rh - 1 do
            for dc = 0, rw - 1 do
                local cr, cc = rr + dr, rc + dc
                if not inBounds(cr, cc) then ok = false; break end
                if g[cr][cc] == 'W' then hasWall = true
                else hasFloor = true end
            end
            if not ok then break end
        end
        if ok and hasFloor and hasWall then
            for dr = 0, rh - 1 do
                for dc = 0, rw - 1 do
                    g[rr + dr][rc + dc] = '.'
                end
            end
            carved = carved + 1
        end
    end
end

--- 打通额外连接，减少死胡同、增加回路
local function carveExtraPassages(g, count)
    local walls = {}
    for r = 3, GRID - 2 do
        for c = 3, GRID - 2 do
            if g[r][c] == 'W' then
                -- 检查这个墙两侧是否有空地（打通后连接两个区域）
                for _, d in ipairs(DIRS) do
                    local ar, ac = r + d[1], c + d[2]
                    local br, bc = r - d[1], c - d[2]
                    if inBounds(ar, ac) and inBounds(br, bc)
                       and g[ar][ac] ~= 'W' and g[br][bc] ~= 'W' then
                        walls[#walls + 1] = {r, c}
                        break
                    end
                end
            end
        end
    end
    shuffle(walls)
    local opened = 0
    for _, w in ipairs(walls) do
        if opened >= count then break end
        g[w[1]][w[2]] = '.'
        opened = opened + 1
    end
end

-- ============================================================
-- 阶段 3: 放置楼梯
-- ============================================================
local function placeStairs(g, floor)
    local entryR, entryC, exitR, exitC

    -- 收集所有空地
    local floors = {}
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            if g[r][c] == '.' then
                floors[#floors + 1] = {r, c}
            end
        end
    end

    if floor == 1 then
        -- 入口(P)放左下角附近，出口(U)放右上角附近
        -- 找最接近 (10,2) 的空地
        table.sort(floors, function(a, b)
            local da = math.abs(a[1] - 10) + math.abs(a[2] - 2)
            local db = math.abs(b[1] - 10) + math.abs(b[2] - 2)
            return da < db
        end)
        entryR, entryC = floors[1][1], floors[1][2]
        g[entryR][entryC] = 'P'

        -- 出口找最远的空地
        local dist = bfsDistance(g, entryR, entryC, nil)
        local bestD, bestR, bestC = 0, 2, 10
        for r = 2, GRID - 1 do
            for c = 2, GRID - 1 do
                if g[r][c] == '.' and dist[r][c] > bestD then
                    bestD = dist[r][c]
                    bestR, bestC = r, c
                end
            end
        end
        exitR, exitC = bestR, bestC
        g[exitR][exitC] = 'U'

    elseif BOSS_TEMPLATES[floor] then
        -- Boss 层只有下楼梯
        table.sort(floors, function(a, b)
            local da = math.abs(a[1] - 6) + math.abs(a[2] - 2)
            local db = math.abs(b[1] - 6) + math.abs(b[2] - 2)
            return da < db
        end)
        entryR, entryC = floors[1][1], floors[1][2]
        g[entryR][entryC] = 'D'
        exitR, exitC = nil, nil
    else
        -- 普通层：D和U放在BFS距离最远的两个空地
        -- 先随机选入口
        local idx = randInt(1, #floors)
        entryR, entryC = floors[idx][1], floors[idx][2]
        g[entryR][entryC] = 'D'

        -- 出口选BFS最远的
        local dist = bfsDistance(g, entryR, entryC, nil)
        local bestD = 0
        exitR, exitC = entryR, entryC
        for r = 2, GRID - 1 do
            for c = 2, GRID - 1 do
                if g[r][c] == '.' and dist[r][c] > bestD then
                    bestD = dist[r][c]
                    exitR, exitC = r, c
                end
            end
        end
        g[exitR][exitC] = 'U'
    end

    return entryR, entryC, exitR, exitC
end

-- ============================================================
-- 阶段 4: 识别走廊瓶颈放门
-- ============================================================
local function findChokepoints(g, entryR, entryC, exitR, exitC)
    -- BFS找入口到出口的路径上的瓶颈（只有2个非墙邻居的格子）
    local chokepoints = {}
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            if g[r][c] == '.' then
                -- 不在楼梯旁边
                local nearStair = false
                for _, d in ipairs(DIRS) do
                    local nr, nc = r + d[1], c + d[2]
                    if inBounds(nr, nc) then
                        local ch = g[nr][nc]
                        if ch == 'P' or ch == 'D' or ch == 'U' then
                            nearStair = true; break
                        end
                    end
                end
                if not nearStair then
                    local openCount = 0
                    for _, d in ipairs(DIRS) do
                        local nr, nc = r + d[1], c + d[2]
                        if inBounds(nr, nc) and g[nr][nc] ~= 'W' then
                            openCount = openCount + 1
                        end
                    end
                    -- 恰好2个通道邻居 = 走廊瓶颈
                    if openCount == 2 then
                        -- 验证：移除此格后是否断开连通
                        g[r][c] = 'W'
                        local connected = isConnectedFloor(g)
                        g[r][c] = '.'
                        if not connected then
                            -- 这是真正的瓶颈
                            local dist = bfsDistance(g, entryR, entryC, nil)
                            chokepoints[#chokepoints + 1] = {r = r, c = c, d = dist[r][c]}
                        end
                    end
                end
            end
        end
    end
    -- 按距入口远近排序
    table.sort(chokepoints, function(a, b) return a.d < b.d end)
    return chokepoints
end

-- ============================================================
-- 阶段 5: 放置钥匙和门
-- ============================================================
local function getDoorColors(floor)
    if floor <= 15 then return {"Y"}
    elseif floor <= 31 then return {"Y", "B"}
    elseif floor <= 40 then return {"B"}
    else return {"B", "R"}
    end
end

local function getDoorCount(floor)
    if floor <= 5 then return randInt(1, 1)
    elseif floor <= 15 then return randInt(1, 2)
    else return randInt(1, 3)
    end
end

local function placeKeyDoors(g, floor, chokepoints, entryR, entryC)
    local colors = getDoorColors(floor)
    local numDoors = math.min(getDoorCount(floor), #chokepoints)

    local placedDoors = {}

    -- 从瓶颈中选合适的放门
    for i = 1, math.min(numDoors, #chokepoints) do
        local cp = chokepoints[i]
        if g[cp.r][cp.c] ~= '.' then goto continueDoor end

        local color = randPick(colors)
        -- 放门
        g[cp.r][cp.c] = color
        -- 在门前方（入口侧）找空地放钥匙
        local distNow = bfsDistance(g, entryR, entryC, nil)
        local keyCandidates = getReachableEmpty(g, distNow)
        if #keyCandidates < 1 then
            g[cp.r][cp.c] = '.'  -- 撤回
        else
            local keyCh = string.lower(color)
            -- 选距离适中的位置放钥匙（不要太近也不要太远）
            table.sort(keyCandidates, function(a, b) return a.d < b.d end)
            local keyIdx = math.min(#keyCandidates, math.max(1, math.floor(#keyCandidates * 0.5)))
            local pos = keyCandidates[keyIdx]
            g[pos.r][pos.c] = keyCh
            placedDoors[#placedDoors + 1] = {r = cp.r, c = cp.c}
        end
        ::continueDoor::
    end

    -- 额外钥匙 1-2 把（放在可达区域，作为备用）
    local passSet = {}
    for _, pd in ipairs(placedDoors) do
        passSet[pd.r .. "," .. pd.c] = true
    end
    local distAll = bfsDistance(g, entryR, entryC, passSet)
    local allEmpty = getReachableEmpty(g, distAll)
    local extraCount = randInt(1, 2)
    for _ = 1, extraCount do
        if #allEmpty > 0 then
            local color = randPick(colors)
            local pos = randPick(allEmpty)
            if g[pos.r][pos.c] == '.' then
                g[pos.r][pos.c] = string.lower(color)
            end
        end
    end
end

-- ============================================================
-- 怪物池
-- ============================================================
local MONSTER_TIERS = {
    {1,  10, {"1", "2"}},
    {6,  18, {"2", "3", "4"}},
    {14, 26, {"5", "6"}},
    {22, 36, {"8", "9"}},
    {32, 48, {"9", "A", "C"}},
}

local function getMonsterPool(floor)
    local pool = {}
    local seen = {}
    for _, t in ipairs(MONSTER_TIERS) do
        if floor >= t[1] and floor <= t[2] then
            for _, m in ipairs(t[3]) do
                if not seen[m] then
                    pool[#pool + 1] = m
                    seen[m] = true
                end
            end
        end
    end
    if #pool == 0 then pool = {"1"} end
    return pool
end

local function getMonsterCount(floor)
    if floor <= 5 then return randInt(2, 3)
    elseif floor <= 20 then return randInt(3, 4)
    else return randInt(3, 5)
    end
end

local function isMonsterCh(ch)
    local m = {["1"]=1,["2"]=1,["3"]=1,["4"]=1,["5"]=1,["6"]=1,["7"]=1,["8"]=1,["9"]=1,A=1,C=1,J=1,L=1,N=1,X=1}
    return m[ch] ~= nil
end

local function hasAdjacentMonster(g, r, c)
    for _, d in ipairs(DIRS) do
        local nr, nc = r + d[1], c + d[2]
        if inBounds(nr, nc) and isMonsterCh(g[nr][nc]) then
            return true
        end
    end
    return false
end

-- ============================================================
-- 判断是否是有价值的物品（钥匙、宝石、血瓶、技能、附魔石、商店）
-- ============================================================
local function isValuable(ch)
    local valuables = {
        y=1, b=1, r=1,           -- 钥匙
        a=1, d=1,                -- 攻防宝石
        h=1, H=1,                -- 血瓶
        S=1, V=1, K=1, T=1, E=1, -- 技能
        f=1, i=1, l=1, t=1, n=1, o=1, e=1, -- 附魔石
        ['$']=1,                 -- 商店
    }
    return valuables[ch] ~= nil
end

-- ============================================================
-- 阶段 6: 放置怪物（守护物品优先）
-- 策略：先在有价值物品的入口方向邻格放守卫怪，剩余配额放走廊巡逻怪
-- ============================================================
local function placeMonsters(g, floor, entryR, entryC)
    if BOSS_TEMPLATES[floor] then return end

    local pool = getMonsterPool(floor)
    local count = getMonsterCount(floor)

    local passAll = {}
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            local ch = g[r][c]
            if ch == 'Y' or ch == 'B' or ch == 'R' then
                passAll[r .. "," .. c] = true
            end
        end
    end
    local dist = bfsDistance(g, entryR, entryC, passAll)

    local placed = 0
    local usedCells = {}

    -- === 第一步：在有价值物品前方放守卫怪 ===
    -- 收集所有有价值物品
    local treasures = {}
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            if isValuable(g[r][c]) and dist[r][c] > 0 then
                treasures[#treasures + 1] = {r = r, c = c, d = dist[r][c]}
            end
        end
    end
    -- 按距离降序（远处的高价值物品优先守卫）
    table.sort(treasures, function(a, b) return a.d > b.d end)

    for _, tr in ipairs(treasures) do
        if placed >= count then break end

        -- 找这个物品的邻格中，离入口更近的那个空地（= 入口方向的守卫位）
        local bestGuard = nil
        local bestDist = 999
        for _, d in ipairs(DIRS) do
            local nr, nc = tr.r + d[1], tr.c + d[2]
            if inBounds(nr, nc) and g[nr][nc] == '.' and dist[nr][nc] >= 0
               and dist[nr][nc] < tr.d  -- 离入口更近 = 在物品前方
               and not usedCells[nr .. "," .. nc]
               and not hasAdjacentMonster(g, nr, nc) then
                if dist[nr][nc] < bestDist then
                    bestDist = dist[nr][nc]
                    bestGuard = {r = nr, c = nc}
                end
            end
        end
        if bestGuard then
            g[bestGuard.r][bestGuard.c] = randPick(pool)
            usedCells[bestGuard.r .. "," .. bestGuard.c] = true
            placed = placed + 1
        end
    end

    -- === 第二步：剩余配额放走廊巡逻怪 ===
    if placed < count then
        local candidates = {}
        for r = 2, GRID - 1 do
            for c = 2, GRID - 1 do
                if g[r][c] == '.' and dist[r][c] > 1
                   and not usedCells[r .. "," .. c] then
                    candidates[#candidates + 1] = {r = r, c = c, d = dist[r][c]}
                end
            end
        end
        table.sort(candidates, function(a, b) return a.d > b.d end)

        for _, cell in ipairs(candidates) do
            if placed >= count then break end
            if not hasAdjacentMonster(g, cell.r, cell.c) then
                g[cell.r][cell.c] = randPick(pool)
                placed = placed + 1
            end
        end
    end
end

-- ============================================================
-- 阶段 7: 放置物品
-- ============================================================
local function getItemBudget(floor)
    local items = {}
    -- 小血瓶
    local hCount = floor <= 20 and randInt(1, 2) or randInt(1, 2)
    for _ = 1, hCount do items[#items + 1] = 'h' end
    -- 大血瓶
    if floor >= 10 and randInt(1, 3) <= 2 then items[#items + 1] = 'H' end
    -- 攻击宝石
    if randInt(1, 3) <= 2 then items[#items + 1] = 'a' end
    -- 防御宝石
    if randInt(1, 3) <= 2 then items[#items + 1] = 'd' end
    return items
end

local function placeItems(g, floor, entryR, entryC)
    if BOSS_TEMPLATES[floor] then return end
    local items = getItemBudget(floor)
    local passAll = {}
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            local ch = g[r][c]
            if ch == 'Y' or ch == 'B' or ch == 'R' then
                passAll[r .. "," .. c] = true
            end
        end
    end
    local dist = bfsDistance(g, entryR, entryC, passAll)
    local candidates = getReachableEmpty(g, dist)

    -- 优先放在死胡同（只有1个非墙邻居的空地 = 探索奖励）
    local deadEnds = {}
    local others = {}
    for _, cell in ipairs(candidates) do
        local openN = 0
        for _, d in ipairs(DIRS) do
            local nr, nc = cell.r + d[1], cell.c + d[2]
            if inBounds(nr, nc) and g[nr][nc] ~= 'W' then
                openN = openN + 1
            end
        end
        if openN == 1 then
            deadEnds[#deadEnds + 1] = cell
        else
            others[#others + 1] = cell
        end
    end
    shuffle(deadEnds)
    shuffle(others)

    -- 合并：死胡同优先
    local allSlots = {}
    for _, c in ipairs(deadEnds) do allSlots[#allSlots + 1] = c end
    for _, c in ipairs(others) do allSlots[#allSlots + 1] = c end

    for i, item in ipairs(items) do
        if i <= #allSlots then
            g[allSlots[i].r][allSlots[i].c] = item
        end
    end
end

-- ============================================================
-- 阶段 8: 特殊物品（商店、技能、附魔宝石）
-- ============================================================
local SHOP_FLOORS = {5, 10, 15, 20, 25, 30, 35, 40, 45}

local SKILL_SCHEDULE = {
    {floor = 5,  char = 'S'},
    {floor = 10, char = 'V'},
    {floor = 10, char = 'K'},
    {floor = 20, char = 'K'},
    {floor = 30, char = 'T'},
    {floor = 40, char = 'E'},
}

local GEM_SCHEDULE = {
    {floor = 5,  char = 'f'},
    {floor = 8,  char = 'i'},
    {floor = 15, char = 't'},
    {floor = 20, char = 'n'},
    {floor = 25, char = 'o'},
    {floor = 30, char = 'f'},
    {floor = 30, char = 'i'},
    {floor = 35, char = 'l'},
    {floor = 35, char = 't'},
    {floor = 40, char = 'n'},
    {floor = 40, char = 'o'},
    {floor = 25, char = 'e'},
    {floor = 45, char = 'e'},
}

local RELIC_SCHEDULE = {
    {floor = 3, char = 'G'},  -- 宝石工匠锤：第3层（在第5层首颗宝石之前）
}

local function placeSpecials(g, floor, entryR, entryC)
    if BOSS_TEMPLATES[floor] then return end

    local passAll = {}
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            local ch = g[r][c]
            if ch == 'Y' or ch == 'B' or ch == 'R' then
                passAll[r .. "," .. c] = true
            end
        end
    end
    local dist = bfsDistance(g, entryR, entryC, passAll)

    local function placeOnEmpty(ch)
        local cells = getReachableEmpty(g, dist)
        shuffle(cells)
        for _, cell in ipairs(cells) do
            g[cell.r][cell.c] = ch
            return true
        end
        return false
    end

    for _, sf in ipairs(SHOP_FLOORS) do
        if floor == sf then placeOnEmpty('$'); break end
    end
    for _, sk in ipairs(SKILL_SCHEDULE) do
        if floor == sk.floor then placeOnEmpty(sk.char) end
    end
    for _, gem in ipairs(GEM_SCHEDULE) do
        if floor == gem.floor then placeOnEmpty(gem.char) end
    end
    for _, rl in ipairs(RELIC_SCHEDULE) do
        if floor == rl.floor then placeOnEmpty(rl.char) end
    end
end

-- ============================================================
-- 连通性验证（模拟拾钥开门到达出口）
-- ============================================================
local function validateFloor(g, floor, entryR, entryC)
    local exitR, exitC
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            local ch = g[r][c]
            if ch == 'U' then exitR, exitC = r, c end
            -- Boss 层以 Boss 怪物位置为"出口"（打败即通关该层）
            if BOSS_TEMPLATES[floor] and isMonsterCh(ch) then exitR, exitC = r, c end
        end
    end
    if BOSS_TEMPLATES[floor] then
        if not exitR then return true end
    end
    if not exitR and not BOSS_TEMPLATES[floor] then return false end

    -- 模拟 BFS 拾钥开门
    ---@type table<string, number>
    local keys = {y = 0, b = 0, r = 0}
    local visited = {}
    for r = 1, GRID do visited[r] = {} end
    local blockedDoors = {}
    local queue = {{entryR, entryC}}
    visited[entryR][entryC] = true

    local progress = true
    while progress do
        progress = false
        local head = 1
        while head <= #queue do
            local cur = queue[head]; head = head + 1
            local ch = g[cur[1]][cur[2]]
            if ch == 'y' then keys.y = keys.y + 1
            elseif ch == 'b' then keys.b = keys.b + 1
            elseif ch == 'r' then keys.r = keys.r + 1
            end
            for _, d in ipairs(DIRS) do
                local nr, nc = cur[1] + d[1], cur[2] + d[2]
                if inBounds(nr, nc) and not visited[nr][nc] then
                    local nch = g[nr][nc]
                    if nch == 'W' then
                        -- skip
                    elseif nch == 'Y' or nch == 'B' or nch == 'R' then
                        local keyNeeded = string.lower(nch)
                        if keys[keyNeeded] > 0 then
                            keys[keyNeeded] = keys[keyNeeded] - 1
                            visited[nr][nc] = true
                            queue[#queue + 1] = {nr, nc}
                            progress = true
                        else
                            blockedDoors[nr .. "," .. nc] = {nr, nc, nch}
                        end
                    else
                        visited[nr][nc] = true
                        queue[#queue + 1] = {nr, nc}
                    end
                end
            end
        end
        -- 收集 key 并排序，确保遍历顺序确定性
        local doorKeys = {}
        for k in pairs(blockedDoors) do doorKeys[#doorKeys + 1] = k end
        table.sort(doorKeys)
        local newBlocked = {}
        for _, k in ipairs(doorKeys) do
            local door = blockedDoors[k]
            local keyNeeded = string.lower(door[3])
            if keys[keyNeeded] > 0 and not visited[door[1]][door[2]] then
                keys[keyNeeded] = keys[keyNeeded] - 1
                visited[door[1]][door[2]] = true
                queue = {{door[1], door[2]}}
                progress = true
            else
                newBlocked[k] = door
            end
        end
        blockedDoors = newBlocked
    end

    if exitR and not visited[exitR][exitC] then return false end
    return true
end

-- ============================================================
-- 网格转字符串
-- ============================================================
local function gridToStrings(g)
    local result = {}
    for r = 1, GRID do
        local row = ""
        for c = 1, GRID do
            row = row .. g[r][c]
        end
        result[r] = row
    end
    return result
end

-- ============================================================
-- Boss 层固定模板
-- ============================================================
BOSS_TEMPLATES = {
    -- 第10层：史莱姆王 (J) - 开阔竞技场
    [10] = {
        "WWWWWWWWWWW",
        "Wh.......hW",
        "W...W.W...W",
        "W.........W",
        "W....J....W",
        "WD........W",
        "W.........W",
        "W...a.d...W",
        "W...W.W...W",
        "Wh.......hW",
        "WWWWWWWWWWW",
    },
    -- 第20层：骨龙 (L) - 龙巢
    [20] = {
        "WWWWWWWWWWW",
        "WH...Y...HW",
        "W.WWW.WWW.W",
        "W.W.....W.W",
        "W....L....W",
        "WD...Y....W",
        "W.........W",
        "W.Wa.d.W..W",
        "W.WWW.WWW.W",
        "WH.......HW",
        "WWWWWWWWWWW",
    },
    -- 第30层：暗影巫妖 (N) - 暗黑神殿
    [30] = {
        "WWWWWWWWWWW",
        "WH.......HW",
        "W.WWWBWWW.W",
        "W.WH.a.HW.W",
        "W.B...N.B.W",
        "WD....B...W",
        "W.W.....W.W",
        "W.WH.d.HW.W",
        "W.WWWWWWW.W",
        "WH.......HW",
        "WWWWWWWWWWW",
    },
    -- 第40层：炎魔将军 (X) - 炎狱要塞
    [40] = {
        "WWWWWWWWWWW",
        "WH.......HW",
        "W.WWWRWWW.W",
        "W.WH.a.HW.W",
        "W.R...X.R.W",
        "WD....R...W",
        "W.W.....W.W",
        "W.WH.d.HW.W",
        "W.WWWWWWW.W",
        "WH.......HW",
        "WWWWWWWWWWW",
    },
    -- 第50层：魔王 (7) - 魔王宝座
    [50] = {
        "WWWWWWWWWWW",
        "WH.......HW",
        "W.WWWRWWW.W",
        "W.WH.a.HW.W",
        "W.R...7.R.W",
        "WD....R...W",
        "W.W.....W.W",
        "W.WH.d.HW.W",
        "W.WWWWWWW.W",
        "WH.......HW",
        "WWWWWWWWWWW",
    },
}

-- ============================================================
-- 安全回退模板
-- ============================================================
local function generateSafeTemplate(floor)
    local g = createFullGrid()
    -- 雕一个简单的十字走廊
    for c = 2, GRID - 1 do g[6][c] = '.' end
    for r = 2, GRID - 1 do g[r][6] = '.' end
    -- 四角各开一个 2x2 房间
    for _, corner in ipairs({{2,2},{2,8},{8,2},{8,8}}) do
        g[corner[1]][corner[2]] = '.'
        g[corner[1]][corner[2]+1] = '.'
        g[corner[1]+1][corner[2]] = '.'
        g[corner[1]+1][corner[2]+1] = '.'
    end

    local entryR, entryC = placeStairs(g, floor)
    local pool = getMonsterPool(floor)
    local placed = 0
    for r = 2, GRID - 1 do
        for c = 2, GRID - 1 do
            if g[r][c] == '.' and placed < 3 and not hasAdjacentMonster(g, r, c) then
                g[r][c] = randPick(pool)
                placed = placed + 1
            end
        end
    end
    -- 放一个血瓶
    for r = GRID - 1, 2, -1 do
        for c = GRID - 1, 2, -1 do
            if g[r][c] == '.' then g[r][c] = 'h'; goto doneItem end
        end
    end
    ::doneItem::
    return gridToStrings(g)
end

-- ============================================================
-- 生成单层（核心流程）
-- ============================================================
local MAX_RETRIES = 30

local function tryGenerateFloor(floor)
    local g = createFullGrid()

    -- 阶段 1: 迷宫雕刻
    -- 从随机内部点开始DFS
    local startR = randInt(2, GRID - 1)
    local startC = randInt(2, GRID - 1)
    carveMaze(g, startR, startC)

    -- 确保有足够空地（至少30格，9x9=81格中的37%）
    local floorCount = countFloor(g)
    if floorCount < 30 then return nil end

    -- 阶段 2: 开辟小房间 + 额外通道
    carveRooms(g, randInt(2, 4))
    carveExtraPassages(g, randInt(2, 4))

    -- 检查连通性
    if not isConnectedFloor(g) then return nil end

    -- 阶段 3: 放置楼梯
    local entryR, entryC, exitR, exitC = placeStairs(g, floor)

    -- 阶段 4: 找瓶颈放门
    if exitR then
        local chokepoints = findChokepoints(g, entryR, entryC, exitR, exitC)
        placeKeyDoors(g, floor, chokepoints, entryR, entryC)
    end

    -- 阶段 5-7: 先放物品和特殊，再放怪物守护
    placeItems(g, floor, entryR, entryC)
    placeSpecials(g, floor, entryR, entryC)
    placeMonsters(g, floor, entryR, entryC)

    -- 最终验证
    if not validateFloor(g, floor, entryR, entryC) then return nil end

    return gridToStrings(g)
end

function MapGenerator.generateFloor(floor, seed)
    -- Boss 层使用固定模板
    if BOSS_TEMPLATES[floor] then
        return BOSS_TEMPLATES[floor]
    end
    -- 每层独立种子：确保某层的重试不影响其他层
    if seed then
        math.randomseed(seed + floor * 9973)
    end
    for _ = 1, MAX_RETRIES do
        local result = tryGenerateFloor(floor)
        if result then return result end
    end
    return generateSafeTemplate(floor)
end

function MapGenerator.generateAllFloors(baseSeed)
    local allMaps = {}
    for f = 1, TOTAL_FLOORS do
        allMaps[f] = MapGenerator.generateFloor(f, baseSeed)
    end
    return allMaps
end

return MapGenerator
