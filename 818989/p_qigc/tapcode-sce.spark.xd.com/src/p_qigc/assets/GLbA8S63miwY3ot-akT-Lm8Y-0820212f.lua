-- ====================================================================
-- data/Dialogues.lua - 对话数据表（数据驱动）
-- ====================================================================
-- 纯数据模块：定义所有对话内容和触发条件
-- 用法: local Dialogues = require("data.Dialogues")
-- ====================================================================
-- 字段说明:
--   building   : string        触发建筑 key（如 "blacksmith"）
--   priority   : number        优先级（越大越优先，同建筑取最高）
--   once       : boolean       true = 只触发一次，记录到 dialogueFlags
--   condition  : function(GS)  额外条件函数（nil = 无额外条件）
--   lines      : table         { {speaker=, text=}, ... } 对话行
--   onComplete : function(GS)  对话结束后回调（可选，给奖励等）
-- ====================================================================

return {

    -- ================================================================
    -- 铁匠铺
    -- ================================================================
    blacksmith_first_visit = {
        building = "blacksmith",
        priority = 100,
        once = true,
        lines = {
            { speaker = "斯特朗", text = "哟，你是那小子吧？" },
        },
    },

    -- ================================================================
    -- 药剂店
    -- ================================================================
    potion_shop_first_visit = {
        building = "potion_shop",
        priority = 100,
        once = true,
        lines = {
            { speaker = "莉娜", text = "……" },
        },
    },

    -- ================================================================
    -- 首饰店
    -- ================================================================
    jewelry_shop_first_visit = {
        building = "jewelry_shop",
        priority = 100,
        once = true,
        lines = {
            { speaker = "朱莉", text = "欢迎光……咦？你是新来的冒险者？" },
        },
    },

    -- ================================================================
    -- 盔甲铺
    -- ================================================================
    armor_shop_first_visit = {
        building = "armor_shop",
        priority = 100,
        once = true,
        lines = {
            { speaker = "迪芬", text = "你就是昨天芙蕾雅带回来的冒险者吧？很高兴见到你。" },
        },
    },

    -- ================================================================
    -- 酒馆
    -- ================================================================
    tavern_first_visit = {
        building = "tavern",
        priority = 100,
        once = true,
        lines = {
            { speaker = "爱丽丝", text = "欢迎光临！冒险者！" },
        },
    },

    -- ================================================================
    -- 布告栏
    -- ================================================================
    bulletin_board_first_visit = {
        building = "bulletin_board",
        priority = 100,
        once = true,
        lines = {
            { speaker = "旁白", text = "（一块孤零零的木板贴满了各式各样的愿望。）" },
        },
    },

    -- ================================================================
    -- 事件：苏醒时 - 对话 1（芙蕾雅登场）
    -- ================================================================
    event_awakening_1 = {
        building = nil,
        priority = 0,
        once = false,
        lines = {
            { speaker = "？？？", text = "你们这些怪物……" },
            { speaker = "？？？", text = "给我让开！" },
        },
    },

    -- ================================================================
    -- 事件：苏醒时 - 对话 2（芙蕾雅与玩家）
    -- ================================================================
    event_awakening_2 = {
        building = nil,
        priority = 0,
        once = false,
        lines = {
            { speaker = "？？？", text = "还好赶上了，阿妮塔保佑。" },
            { speaker = "？？？", text = "我是来接你的，你还好吗？" },
            { speaker = "？？？", text = "雨太大了，而且外面到处都是魔物。" },
            { speaker = "？？？", text = "跟我来，我们先回镇上。" },
        },
    },

    -- ================================================================
    -- 事件：苏醒时 - 对话 3（已迁移到 Event_Awakening.lua 的动态对话）
    -- ================================================================

    -- ================================================================
    -- 好感度对话（进入建筑时自动触发，优先级低于事件和首访对话）
    -- lines 为函数，根据当前好感度等级返回对应台词
    -- ================================================================

    -- 芙蕾雅（冒险者公会会长 → guild_master_office）
    freya_favor = {
        building = "guild_master_office",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "你好。",
                "你好，有什么事吗？",
                "你好，请坐。",
                "{玩家}，你来了，最近如何？有没有公会能帮忙的？",
                "{玩家}，你来了。等我一下，我在处理这些文件。不，不要，你不用走，我马上就好。",
                "{玩家}……你来了，我正在想你，快点过来。",
                "（脸红）{爱称}……",
            }
            local level = GS.getNPCFavorLevel("guild_master")
            return { { speaker = "芙蕾雅", text = level == 0 and "……" or texts[level] } }
        end,
    },

    -- 妮可（冒险者公会接待 → guild）
    nicole_favor = {
        building = "guild",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "欢迎来到冒险者公会！要看失物招领吗？还是要看一下\"广告机\"呢？",
                "欢迎来到冒险者公会！要看失物招领吗？还是要看一下\"广告机\"呢？",
                "欢迎来到冒险者公会！要看失物招领吗？还是要看一下\"广告机\"呢？",
                "欢迎！{玩家}，今天需要做什么？和我说就行了！要看一下\"广告机\"吗？",
                "欢迎！今天过得好吗？虽然公会的任务也很重要，但{玩家}还是要多休息啊！不要老是看\"广告机\"了！",
                "{玩家}！哇，我刚好想到你，你就来了！你是来看我的对吧？可别说是来看\"广告机\"的！",
                "{爱称}，你来了！下班后要一起回家吗？",
            }
            local level = GS.getNPCFavorLevel("guild_receptionist")
            return { { speaker = "妮可", text = level == 0 and "……" or texts[level] } }
        end,
    },

    -- 朱莉（首饰店店长 → jewelry_shop）
    julie_favor = {
        building = "jewelry_shop",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "欢迎光临，要看一下首饰吗？宝石是仿制品，但如果相信的话也能获得力量。",
                "欢迎光临，要看一下首饰吗？宝石是仿制品，但如果相信的话也能获得力量。",
                "欢迎光临，要看一下首饰吗？宝石是仿制品，但如果相信的话也能获得力量。",
                "{玩家}，来看看新制作的首饰吗？这些都是我的孩子们。",
                "{玩家}，欢迎，今天有带来什么漂亮的石头吗？",
                "{玩家}，快来看看这块宝石，它好漂亮……啊，对不起，你有正事吧？",
                "{爱称}，想我了吗……我想你了。",
            }
            local level = GS.getNPCFavorLevel("jewelry_shop_owner")
            return { { speaker = "朱莉", text = level == 0 and "……" or texts[level] } }
        end,
    },

    -- 莉娜（药剂店店长 → potion_shop）
    lina_favor = {
        building = "potion_shop",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "……",
                "你好。",
                "你好。",
                "你好，还是药水？",
                "你好，你看上去很健康，太好了。",
                "{玩家}，药剂一定要准备充足，不然的话，我……会担心的。",
                "{爱称}！",
            }
            local level = GS.getNPCFavorLevel("potion_shop_owner")
            return { { speaker = "莉娜", text = level == 0 and "……" or texts[level] } }
        end,
    },

    -- 爱丽丝（酒馆接待 → tavern）
    alice_favor = {
        building = "tavern",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "欢迎来到红杯酒馆，我们这里有最好的姜啤酒和蜂蜜狼肋排，要试试哪个呢？",
                "欢迎来到红杯酒馆，我们这里有最好的姜啤酒和蜂蜜狼肋排，要试试哪个呢？",
                "欢迎来到红杯酒馆，我们这里有最好的姜啤酒和蜂蜜狼肋排，要试试哪个呢？",
                "{玩家}！快过来，我给你留了最新鲜的姜啤酒，不要说出去哦。",
                "{玩家}，你来啦！你是来看安吉莉娅的吗？",
                "{玩家}，你来啦！好希望自己和安吉莉娅一样漂亮，那样的话你也……不，没什么。",
                "{爱称}！呀！你怎么过来了？我正好有许多话想和你说！",
            }
            local level = GS.getNPCFavorLevel("tavern_keeper")
            return { { speaker = "爱丽丝", text = level == 0 and "……" or texts[level] } }
        end,
    },

    -- 斯特朗（铁匠铺铁匠 → blacksmith，上限珍视）
    strong_favor = {
        building = "blacksmith",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "买武器？在那边，自己看吧。",
                "买武器？在那边，自己看吧。",
                "买武器？在那边，自己看吧。",
                "哟，{玩家}，我看你的武器需要保养了。",
                "哟，{玩家}，我看你的武器需要保养了。拿过来，我来帮你……好了，这下可以把他们打扁了。",
            }
            local level = GS.getNPCFavorLevel("blacksmith_owner")
            return { { speaker = "斯特朗", text = level == 0 and "……" or texts[level] } }
        end,
    },

    -- 迪芬（盔甲铺店长 → armor_shop，上限珍视）
    difen_favor = {
        building = "armor_shop",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "盔甲，盔甲，最好的盔甲。",
                "盔甲，盔甲，最好的盔甲。",
                "盔甲……{玩家}，是你啊，来买防具吗？",
                "{玩家}，不要轻视防具的重要性。",
                "{玩家}，让我看看你的防具状态，嗯，还不错。答应我，别太容易就死了。",
            }
            local level = GS.getNPCFavorLevel("armor_shop_owner")
            return { { speaker = "迪芬", text = level == 0 and "……" or texts[level] } }
        end,
    },

    -- 安吉莉娅（酒馆舞女 → 首次见面）
    dancer_first_visit = {
        building = "tavern_dancefloor",
        priority = 100,
        once = true,
        lines = {
            { speaker = "安吉莉娅", text = "你好，我记得你的名字，{玩家}，对吧？我是安吉莉娅。" },
        },
        onComplete = function(GS)
            GS.learnNPCName("tavern_dancer")
        end,
    },

    -- 安吉莉娅（酒馆舞女 → tavern_dancefloor 视角，好感度对话）
    angelica_favor = {
        building = "tavern_dancefloor",
        priority = 10,
        lines = function()
            local GS = require("GameState")
            local texts = {
                "{玩家}，请一定要多来看我哦。",
                "{玩家}，你来了，看来你很喜欢这里的氛围呢。",
                "{玩家}，来看我的表演了吗？今天我怎么样？我有进步吗？",
                "{玩家}，今天怎么有空过来？最近的冒险还顺利吗？",
                "{玩家}，你来了。让我陪你一会儿，在下一首音乐响起之前……其实，我有些累。",
                "{玩家}……今天我的表现怎么样？我真的希望你能喜欢，但日复一日如此，你也会厌倦吧。",
                "{爱称}……今天的我怎么样？你还爱我吗？",
            }
            local level = GS.getNPCFavorLevel("tavern_dancer")
            return { { speaker = "安吉莉娅", text = level == 0 and "……" or texts[level] } }
        end,
    },
}
