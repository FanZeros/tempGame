local C = {}
C.DEFINITIONS = {
    {id="cross", name="十字开凿", branch="giant", icon="ShockwaveActive", every=6,
        text="每6次有效钻击，十字切开周围4格。"},
    {id="pierce", name="钻脉贯穿", branch="giant", icon="DrillMissiles", every=7,
        text="每7次有效钻击，沿准星贯穿后方2格。"},
    {id="fan", name="扇形铲头", branch="giant", icon="SpinningPickaxe", every=8,
        text="每8次有效钻击，在前方展开扇形破岩。"},
    {id="fracture", name="定点碎甲", branch="giant", icon="MiningDamage2", every=1,
        text="连续钻击同一格3次，追加一次碎甲打击；换目标重计。"},
    {id="salvage", name="岩屑回炉", branch="drone", icon="FuelEfficiency1", every=8, breaks=true,
        text="钻头亲手破坏8格后回收燃料；技能破矿不计。"},
    {id="battery", name="钻击充能", branch="drone", icon="LaserCapacity", every=5,
        text="每5次有效钻击，为自动激光恢复少量能量。"},
    {id="magnet", name="磁吸钻环", branch="drone", icon="Collector", every=7,
        text="每7次有效钻击，把附近掉落物吸向自己。"},
    {id="vent", name="紧急排热", branch="drone", icon="OverdriveActive", every=10,
        text="每10次有效钻击，缩短一件已装备世界树道具的剩余冷却。"},
    {id="repel", name="逆冲钻压", branch="mole", icon="ShockwaveRadius", every=12,
        text="每12次有效钻击，反向气压击退追击巨物。"},
    {id="frost", name="霜痕钻头", branch="mole", icon="FeverstoneDuration", every=9,
        text="每9次有效钻击，减速附近小怪，留出换位时间。"},
    {id="parry", name="钻头格挡", branch="mole", icon="LastDitchEffort", every=6,
        text="每6次有效钻击，击碎附近敌方弹幕。"},
    {id="turn", name="转向震荡", branch="mole", icon="Aftershocks", every=1,
        text="有效钻击之间转向超过90度，触发近身震荡。"},
    {id="radar", name="裂隙探针", branch="worm", icon="FieldOfView1", every=6,
        text="每6次有效钻击，接近层底时揭示出口。"},
    {id="seam", name="矿缝追踪", branch="worm", icon="CollectorSpeed", every=8,
        text="每8次有效钻击，追击目标旁同种矿石，最多2格。"},
    {id="counter", name="近身反钻", branch="worm", icon="BulletWorms", every=7,
        text="每7次有效钻击，自动反击距离最近的小怪。"},
    {id="echo", name="回旋掘痕", branch="worm", icon="Boomerang", every=10,
        text="每10次有效钻击，在钻头侧后方追加回旋切割。"},
}
C.BY_ID = {}
for _, d in ipairs(C.DEFINITIONS) do C.BY_ID[d.id] = d end

function C.ReplaceNodes(tree)
    local branches, counters = {}, {}
    for _, d in ipairs(C.DEFINITIONS) do
        branches[d.branch] = branches[d.branch] or {}
        table.insert(branches[d.branch], d)
    end
    for _, node in ipairs(tree.NODES) do
        if node.stat and (node.early or #node.parents > 0) then
            counters[node.branch] = (counters[node.branch] or 0) + 1
            local d = branches[node.branch][(counters[node.branch]-1)%4+1]
            node.stat, node.value, node.stats = nil, nil, nil
            node.mechanicId = d.id
            node.name = d.name .. (node.early and "·入门" or "·进阶")
            node.effect = d.text
            if not node.early then node.icon = d.icon end
        end
    end
end

function C.Ranks(tree, state)
    local ranks = {}
    for _, node in ipairs(tree.NODES) do
        if node.mechanicId then
            ranks[node.mechanicId] = (ranks[node.mechanicId] or 0) + math.min(node.maxLevel,
                math.max(0, tonumber((state.worldTreeLevels or {})[node.id]) or 0))
        end
    end
    return ranks
end
function C.Describe(id, rank)
    local d = C.BY_ID[id]
    if not d then return "" end
    local effects = {
        cross="3阶追加前方一格，6阶追加斜角；最多8格。",
        pierce="每2阶多贯穿1格，最多6格。",
        fan="每3阶加宽扇面，最多7格。",
        fracture="提高碎甲威力，6阶改为连续钻击2次触发。",
        salvage="每阶多恢复0.2%燃料，单次最多3%；冷却6秒。",
        battery="提高激光充能；激光冷却时改为排热，不跳过冷却。",
        magnet="每阶扩大4像素吸附范围；不改变人物位置。",
        vent="每阶多减少0.1秒；不凭空释放未装备道具。",
        repel="每阶多击退0.7像素；冷却6秒，不能无限推远。",
        frost="每阶多减速0.12秒，范围同步扩展。",
        parry="每阶多挡1颗敌弹，单次最多8颗；不挡Boss红框。",
        turn="更高阶强化近身破岩，需主动转向；冷却1.5秒。",
        radar="每阶提前16像素探知出口；不自动破坏出口。",
        seam="每2阶多追踪1格同类矿石，最多8格。",
        counter="提高反击威力和锁敌距离；不伤害未接近的小怪。",
        echo="3/6阶扩展侧后方切割，最多6格。",
    }
    return "当前" .. rank .. "阶；本节点每级+1阶。" .. effects[id]
end
return C
