-- Generated from the recovered original Diggin skill-tree resources.
-- Regenerate with docs/diggin-audit/build_skill_tree_data.py.
return {
    source = "Diggin Godot 4.7 SkillTreeFinal.tscn",
    design_resolution = {
        480,
        270
    },
    ore_names = {
        "Stone",
        "Silver",
        "Gold",
        "Starmetal",
        "Bedrock",
        "Platinum",
        "Iridium",
        "Ruby",
        "Emerald",
        "Diamond",
        "StarDebris",
        "StarStone",
        "FactoryOre",
        "RubyUnsmelted",
        "EmeraldUnsmelted",
        "DiamondUnsmelted",
        "MissionRewardOre",
        "StarBarrier"
    },
    branch_counts = {
        core = 1,
        damage = 29,
        fuel = 30,
        quake = 30,
        world = 31
    },
    nodes = {
        {
            resource_path = "res://Resources/Skill-tree Upgrades/_Core/StartingUpgrade.tres",
            branch = "core",
            name_key = "SKILLTREEUPG_DIGGIN",
            name = "挖到地心！",
            name_en = "Diggin",
            description_key = "SKILLTREEUPG_DIGGIN_DESC",
            description = "开挖！",
            description_en = "Lets go Diggin!",
            icon = "res://Assets/UI/startingUpg.png",
            effect_scene = nil,
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {},
            max_level = 1,
            cost_growth = 0.0,
            id = "UpgradeStart",
            position = {
                0.0,
                0.0
            },
            unlocks = {
                "MiningDamage1",
                "FuelTank1",
                "MiningRate1",
                "FieldOfView1"
            },
            level_to_unlock = 1,
            starting = true,
            demo_locked = false,
            parents = {}
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Stats/MiningDamage1.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_MINE_HARD",
            name = "虎胆矿威",
            name_en = "Mine Hard",
            description_key = "SKILLTREEUPG_MINE_HARD_DESC",
            description = "钻击威力{statAmount}",
            description_en = "{statAmount} Drill hit damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    25.0,
                    47.0,
                    16.0,
                    17.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Drill Damage/DrillDamageUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "drill_damage",
            upgrade_id = "general_stats",
            cost = {
                Stone = 1
            },
            max_level = 10,
            cost_growth = 0.2,
            id = "MiningDamage1",
            position = {
                -40.0,
                0.0
            },
            unlocks = {
                "MovementSpeed1",
                "CritChance1"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "UpgradeStart"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Stats/MovementSpeed1.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_DOUGIE_THE_HEDGEMOLE",
            name = "鼹鼠-道尼克",
            name_en = "Dougie the hedgemole",
            description_key = "SKILLTREEUPG_DOUGIE_THE_HEDGEMOLE_DESC",
            description = "移动速度{statAmount}",
            description_en = "{statAmount} movement speed",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    27.0,
                    5.0,
                    13.0,
                    11.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Movement Speed/MovementSpeedUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 5.0,
            stat_id = "movement_speed",
            upgrade_id = "general_stats",
            cost = {
                Stone = 5
            },
            max_level = 5,
            cost_growth = 0.25,
            id = "MovementSpeed1",
            position = {
                -40.0,
                -40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningDamage1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Crit/CritChance1.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_CRIT_ME_BABY_ONE_MORE_TIME",
            name = "宝贝再暴击一次吧",
            name_en = "Crit me baby one more time",
            description_key = "SKILLTREEUPG_CRIT_ME_BABY_ONE_MORE_TIME_DESC",
            description = "钻头暴击几率{statAmount}",
            description_en = "{statAmount} critical Drill hit chance",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    49.0,
                    48.0,
                    12.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Critical Chance/CriticalChanceUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 2,
            stat_amount = 5.0,
            stat_id = "critical_chance",
            upgrade_id = "general_stats",
            cost = {
                Stone = 6
            },
            max_level = 5,
            cost_growth = 0.3,
            id = "CritChance1",
            position = {
                -80.0,
                0.0
            },
            unlocks = {
                "CritDamage1",
                "DynamiteActive"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningDamage1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Crit/CritDamage1.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_CRITICALER_HIT",
            name = "超级暴击",
            name_en = "Criticaler hit",
            description_key = "SKILLTREEUPG_CRITICALER_HIT_DESC",
            description = "钻头暴击威力{statAmount}",
            description_en = "{statAmount} critical Drill hit damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    71.0,
                    47.0,
                    15.0,
                    17.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Critical Chance/CriticalHitDamageUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 15.0,
            stat_id = "critical_damage_multiplier",
            upgrade_id = "general_stats",
            cost = {
                Stone = 20,
                Silver = 6
            },
            max_level = 5,
            cost_growth = 0.5,
            id = "CritDamage1",
            position = {
                -80.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "CritChance1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Dynamite/DynamiteActive.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_DYNAMITE",
            name = "炸药",
            name_en = "Dynamite",
            description_key = "SKILLTREEUPG_DYNAMITE_DESC",
            description = "定期向空中投掷炸药",
            description_en = "Periodically throw Dynamite in the air",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    93.0,
                    47.0,
                    12.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Dynamite/DynamiteUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 3,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 120,
                Silver = 20
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "DynamiteActive",
            position = {
                -120.0,
                0.0
            },
            unlocks = {
                "DynamiteCooldown",
                "DynamiteDamage",
                "MiningDamage2"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "CritChance1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Stats/MiningDamage2.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_LIVE_FREE_OR_MINE_HARD",
            name = "虎胆矿威4",
            name_en = "Live Free or Mine Hard",
            description_key = "SKILLTREEUPG_LIVE_FREE_OR_MINE_HARD_DESC",
            description = "钻击威力{statAmount}",
            description_en = "{statAmount} Drill hit damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    201.0,
                    47.0,
                    16.0,
                    17.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Drill Damage/DrillDamageUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "drill_damage",
            upgrade_id = "general_stats",
            cost = {
                Stone = 500
            },
            max_level = 15,
            cost_growth = 0.25,
            id = "MiningDamage2",
            position = {
                -160.0,
                0.0
            },
            unlocks = {
                "Feverstone",
                "CritChain"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DynamiteActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Dynamite/DynamiteCooldown.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_MAKING_IT_RAIN",
            name = "天女散雷",
            name_en = "Making it rain",
            description_key = "SKILLTREEUPG_MAKING_IT_RAIN_DESC",
            description = "每{currentAmount}次钻击后投掷一次炸药",
            description_en = "Throw Dynamite every {currentAmount} Drill hits",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    114.0,
                    48.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Dynamite/Stat Upgrades/DynamiteCooldownUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = -10.0,
            stat_id = "cooldown",
            upgrade_id = "dynamite",
            cost = {
                Stone = 150
            },
            max_level = 3,
            cost_growth = 1.0,
            id = "DynamiteCooldown",
            position = {
                -120.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DynamiteActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Dynamite/DynamiteDamage.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_DYNAMIGHTY",
            name = "威震天雷",
            name_en = "DynaMIGHTY",
            description_key = "SKILLTREEUPG_DYNAMIGHTY_DESC",
            description = "炸药爆炸威力{statAmount}",
            description_en = "{statAmount} Dynamite explosion damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    135.0,
                    47.0,
                    15.0,
                    17.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Dynamite/Stat Upgrades/DynamiteDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "damage",
            upgrade_id = "dynamite",
            cost = {
                Stone = 200,
                Silver = 30
            },
            max_level = 3,
            cost_growth = 1.0,
            id = "DynamiteDamage",
            position = {
                -120.0,
                -40.0
            },
            unlocks = {
                "DynamiteAmount",
                "DynamiteRadius"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DynamiteActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Dynamite/DynamiteAmount.tres",
            branch = "damage",
            name_key = "ARTIFACT_CANDLE",
            name = "蜡烛",
            name_en = "Candle",
            description_key = "SKILLTREEUPG_MORE_EXPLODING_STICKS_PLEASE_DESC",
            description = "投掷炸药数量{statAmount}",
            description_en = "{statAmount} Dynamite thrown",
            icon = "res://Assets/Upgrades/artefac.png",
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Dynamite/Stat Upgrades/DynamiteAmountUpgrade.tscn",
            artefact = "res://Resources/Artefacts/ArtefactDynamiteAmount.tres",
            is_artefact = true,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "dynamite",
            cost = {
                Stone = 1500,
                Silver = 200
            },
            max_level = 3,
            cost_growth = 1.0,
            id = "DynamiteAmount",
            position = {
                -120.0,
                -80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DynamiteDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Dynamite/DynamiteRadius.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_NO_AIMING_NEEDED",
            name = "无需瞄准",
            name_en = "No aiming needed",
            description_key = "SKILLTREEUPG_NO_AIMING_NEEDED_DESC",
            description = "炸药爆炸半径{statAmount}",
            description_en = "{statAmount} Dynamite explosion radius",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    178.0,
                    48.0,
                    16.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Dynamite/Stat Upgrades/DynamiteRadiusUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 10.0,
            stat_id = "radius",
            upgrade_id = "dynamite",
            cost = {
                Stone = 1000
            },
            max_level = 3,
            cost_growth = 1.0,
            id = "DynamiteRadius",
            position = {
                -160.0,
                -40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DynamiteDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Stats/MiningDamage3.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_MINE_HARD_WITH_A_VENGEANCE",
            name = "虎胆矿威3",
            name_en = "Mine Hard with a Vengeance",
            description_key = "SKILLTREEUPG_MINE_HARD_WITH_A_VENGEANCE_DESC",
            description = "钻击威力{statAmount}",
            description_en = "{statAmount} Drill hit damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    289.0,
                    47.0,
                    16.0,
                    17.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsDrillDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 33.0,
            stat_id = "drill_damage",
            upgrade_id = "general_stats",
            cost = {
                Stone = 20000
            },
            max_level = 25,
            cost_growth = 0.39,
            id = "MiningDamage3",
            position = {
                -280.0,
                0.0
            },
            unlocks = {
                "DynamiteDamage2",
                "PlatinumBonanza"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FeverstoneDuration",
                "EmeraldRefinery"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/World/AugmentPlatinum.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_AUGMENT_PLATINUM",
            name = "铂金增产",
            name_en = "Augment Platinum",
            description_key = "SKILLTREEUPG_AUGMENT_PLATINUM_DESC",
            description = "挖掘方块獲得的铂金{statAmount}",
            description_en = "{statAmount} Platinum dropped from mined blocks",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    224.0,
                    5.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Augments/Platinum/AugmentPlatinumUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = true,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "additional_amount",
            upgrade_id = "augment_platinum",
            cost = {
                Platinum = 3000,
                Ruby = 40,
                StarDebris = 3
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "AugmentPlatinum",
            position = {
                -160.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "CritChain"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/World/PlatinumBonanza.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_PLATINUM_BONANZA",
            name = "铂金富矿",
            name_en = "Platinum Bonanza",
            description_key = "SKILLTREEUPG_PLATINUM_BONANZA_DESC",
            description = "挖掘后提供5倍铂金的特殊铂金方块",
            description_en = "Special Platinum blocks that give 5X more Platinum when mined",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    531.0,
                    69.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Platinum Bonanza/PlatinumBonanzaUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "platinum_bonanza",
            cost = {
                Platinum = 120000,
                StarDebris = 5
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "PlatinumBonanza",
            position = {
                -320.0,
                0.0
            },
            unlocks = {
                "BouncingBall"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningDamage3"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Dynamite/DynamiteDamage2.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_DYNAMIC_RETURN",
            name = "炸裂回归",
            name_en = "Dynamic Return",
            description_key = "SKILLTREEUPG_DYNAMIC_RETURN_DESC",
            description = "炸药威力{statAmount}",
            description_en = "Increase Dynamite damage by {statAmount}",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    132.0,
                    0.0,
                    22.0,
                    22.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Dynamite/Stat Upgrades/DynamiteDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "damage",
            upgrade_id = "dynamite",
            cost = {
                Stone = 240000,
                Platinum = 25000
            },
            max_level = 5,
            cost_growth = 0.7,
            id = "DynamiteDamage2",
            position = {
                -280.0,
                -40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningDamage3"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Stats/MiningDamage4.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_A_GOOD_DAY_TO_MINE_HARD",
            name = "虎胆矿威5",
            name_en = "A Good Day to Mine Hard",
            description_key = "SKILLTREEUPG_A_GOOD_DAY_TO_MINE_HARD_DESC",
            description = "钻击威力{statAmount}",
            description_en = "{statAmount} Drill hit damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    531.0,
                    47.0,
                    16.0,
                    17.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsDrillDamageStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 110.0,
            stat_id = "drill_damage",
            upgrade_id = "general_stats",
            cost = {
                Stone = 100000000,
                Platinum = 15000000
            },
            max_level = 10,
            cost_growth = 0.5,
            id = "MiningDamage4",
            position = {
                -400.0,
                0.0
            },
            unlocks = {
                "Molenir"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BouncingBall"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Molenir.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_STARMETAL_MOLENIR",
            name = "星之金属：鼹神之锤",
            name_en = "STARMETAL: MOLENIR",
            description_key = "SKILLTREEUPG_STARMETAL_MOLENIR_DESC",
            description = "一把锤子定期飞向你的位置，沿途破坏方块并在抵达时造成范围冲击",
            description_en = "A hammer flies to your location periodically, damaging blocks on the way and crash landing on arrival",
            icon = {
                path = "res://Assets/starUpgrades.png",
                region = {
                    47.0,
                    0.0,
                    20.0,
                    20.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Molenir/MolenirUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 4,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 1000000000,
                Starmetal = 1,
                StarDebris = 10
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Molenir",
            position = {
                -480.0,
                0.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningDamage4"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Bouncing Ball/BouncingBallArtefact.tres",
            branch = "damage",
            name_key = "ARTIFACT_ASTROLABE",
            name = "星盘",
            name_en = "Astrolabe",
            description_key = "SKILLTREEUPG_JUGGLING_101_DESC",
            description = "发射的球数量{statAmount}",
            description_en = "{statAmount} ball launched",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    444.0,
                    47.0,
                    13.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/BouncingBallAmountStatUpgrade1.tscn",
            artefact = "res://Resources/Artefacts/ArtefactBouncyBall.tres",
            is_artefact = true,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "bouncing_ball",
            cost = {
                Stone = 4500000,
                StarDebris = 20
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "BouncingBallArtefact",
            position = {
                -360.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BouncingBall"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Bouncing Ball/BouncingBallBounces.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_BOUNTIFUL_BOUNCING",
            name = "弹弹不休",
            name_en = "Bountiful Bouncing",
            description_key = "SKILLTREEUPG_BOUNTIFUL_BOUNCING_DESC",
            description = "弹力球弹跳持续时间{statAmount}",
            description_en = "{statAmount} ball bounce duration",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    421.0,
                    49.0,
                    16.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/BouncingBallLifetimeStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "lifetime",
            upgrade_id = "bouncing_ball",
            cost = {
                Stone = 400000000,
                Iridium = 16000000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "BouncingBallBounces",
            position = {
                -400.0,
                -40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BouncingBallDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Bouncing Ball/BouncingBallDamage.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_HEAVY_BOUNCE",
            name = "重磅弹跳",
            name_en = "Heavy Bounce",
            description_key = "SKILLTREEUPG_HEAVY_BOUNCE_DESC",
            description = "弹力球弹跳威力{statAmount}",
            description_en = "{statAmount} ball bounce damage",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    157.0,
                    4.0,
                    15.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/BouncingBallDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "damage",
            upgrade_id = "bouncing_ball",
            cost = {
                Stone = 90000000,
                Iridium = 3200000
            },
            max_level = 10,
            cost_growth = 0.6,
            id = "BouncingBallDamage",
            position = {
                -360.0,
                -40.0
            },
            unlocks = {
                "BouncingBallBounces"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BouncingBall"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Bouncing Ball/BouncingBallUnlock.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_BOUNCING_BALL",
            name = "弹力球",
            name_en = "Bouncing Ball",
            description_key = "SKILLTREEUPG_BOUNCING_BALL_DESC",
            description = "定期发射一个撞击方块并弹跳的球",
            description_en = "Launch a ball that damages and bounces off blocks periodically",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    356.0,
                    48.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Bouncing Ball/BouncingBallUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 2,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 22000000,
                Platinum = 2000000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "BouncingBall",
            position = {
                -360.0,
                0.0
            },
            unlocks = {
                "BouncingBallArtefact",
                "BouncingBallDamage",
                "MiningDamage4"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "PlatinumBonanza"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Feverstone/FeverstoneUnlock.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_FEVERSTONE",
            name = "狂热石",
            name_en = "Feverstone",
            description_key = "SKILLTREEUPG_FEVERSTONE_DESC",
            description = "挖掘后进入狂热状态的特殊石头方块",
            description_en = "Special stone blocks that grant FEVER when mined",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    311.0,
                    47.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Feverstone/FeverstoneUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 3000,
                Gold = 200
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Feverstone",
            position = {
                -200.0,
                -40.0
            },
            unlocks = {
                "FeverstoneSpawnRate",
                "FeverstoneDuration"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningDamage2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Crit/CritChain.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_CRITICALEST_HIT",
            name = "终极暴击",
            name_en = "Criticalest hit",
            description_key = "SKILLTREEUPG_CRITICALEST_HIT_DESC",
            description = "钻头暴击威力{statAmount}",
            description_en = "{statAmount} critical Drill hit damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    244.0,
                    47.0,
                    18.0,
                    18.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Critical Chance/CriticalHitDamageUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 15.0,
            stat_id = "critical_damage_multiplier",
            upgrade_id = "general_stats",
            cost = {
                Stone = 400,
                Silver = 150
            },
            max_level = 5,
            cost_growth = 0.3,
            id = "CritChain",
            position = {
                -200.0,
                40.0
            },
            unlocks = {
                "CritChance2",
                "EmeraldRefinery",
                "AugmentPlatinum"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningDamage2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Crit/CritChance2.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_OOPS_I_CRIT_IT_AGAIN",
            name = "哎呀！……我又暴击了",
            name_en = "Oops!... I Crit It Again",
            description_key = "SKILLTREEUPG_OOPS_I_CRIT_IT_AGAIN_DESC",
            description = "钻击暴击几率{statAmount}",
            description_en = "{statAmount} critical Drill hit chance",
            icon = {},
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsCriticalChanceStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 2,
            stat_amount = 5.0,
            stat_id = "critical_chance",
            upgrade_id = "general_stats",
            cost = {
                Stone = 2500,
                Platinum = 800
            },
            max_level = 5,
            cost_growth = 0.3,
            id = "CritChance2",
            position = {
                -200.0,
                80.0
            },
            unlocks = {
                "CritArtefact"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "CritChain"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Crit/CritArtefact.tres",
            branch = "damage",
            name_key = "ARTIFACT_COAL_CLUMP",
            name = "煤块",
            name_en = "Coal Clump",
            description_key = "SKILLTREEUPG_CRITICAL_CRIT_DESC",
            description = "暴击有33%几率对相邻方块造成破坏",
            description_en = "Critical hits have a 33% chance to damage adjacent blocks",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    268.0,
                    49.0,
                    14.0,
                    12.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Critical Crit/CriticalCritUpgrade.tscn",
            artefact = "res://Resources/Artefacts/ArtefactCritThing.tres",
            is_artefact = true,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 7000,
                StarDebris = 15
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "CritArtefact",
            position = {
                -200.0,
                120.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "CritChance2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Feverstone/FeverstoneDuration.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_FEVER_FOREVER",
            name = "永恒狂热",
            name_en = "Fever Forever",
            description_key = "SKILLTREEUPG_FEVER_FOREVER_DESC",
            description = "狂热石提供的狂热持续时间{statAmount}",
            description_en = "{statAmount} Feverstone fever duration",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    333.0,
                    47.0,
                    17.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/FeverstoneDurationStatUpgrade4.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "duration",
            upgrade_id = "feverstone",
            cost = {
                Stone = 4500,
                Platinum = 1000
            },
            max_level = 5,
            cost_growth = 0.35,
            id = "FeverstoneDuration",
            position = {
                -240.0,
                -40.0
            },
            unlocks = {
                "MiningDamage3"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Feverstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Feverstone/FeverstoneSpawnRate.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_FEVEREQUENCY",
            name = "狂热频率",
            name_en = "Feverequency",
            description_key = "SKILLTREEUPG_FEVEREQUENCY_DESC",
            description = "狂热石出现率{statAmount}",
            description_en = "{statAmount} Feverstone spawn rate",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    91.0,
                    4.0,
                    17.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/FeverstoneChanceStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.2,
            stat_id = "chance",
            upgrade_id = "feverstone",
            cost = {
                Stone = 3000,
                Gold = 500
            },
            max_level = 5,
            cost_growth = 0.35,
            id = "FeverstoneSpawnRate",
            position = {
                -200.0,
                -80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Feverstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Emerald Refinery/EmeraldRefineryUnlock.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_REFINE_EMERALD",
            name = "精炼绿宝石",
            name_en = "Refine Emerald",
            description_key = "SKILLTREEUPG_REFINE_EMERALD_DESC",
            description = "宝石精炼厂现在可以精炼绿宝石",
            description_en = "The Gem Refinery can now refine Emeralds",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    70.0,
                    26.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryEmeraldEnabledStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = true,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "emerald_enabled",
            upgrade_id = "refine_ruby",
            cost = {
                Platinum = 15000,
                Ruby = 75,
                FactoryOre = 100
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "EmeraldRefinery",
            position = {
                -240.0,
                40.0
            },
            unlocks = {
                "MiningDamage3",
                "EmeraldSmeltSpeed",
                "EmeraldSmeltMult"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "CritChain"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Emerald Refinery/EmeraldSmeltSpeed.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_EMERALD_POLISH",
            name = "绿宝石打磨",
            name_en = "Emerald Polish",
            description_key = "SKILLTREEUPG_EMERALD_POLISH_DESC",
            description = "宝石精炼厂每{currentAmount}秒精炼一次绿宝石",
            description_en = "The Gem Refinery refines Emeralds every {currentAmount} seconds",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    92.0,
                    26.0,
                    16.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryEmeraldSmeltingRateStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -2.0,
            stat_id = "emerald_smelting_rate",
            upgrade_id = "refine_ruby",
            cost = {
                Gold = 3000,
                Emerald = 20
            },
            max_level = 3,
            cost_growth = 0.2,
            id = "EmeraldSmeltSpeed",
            position = {
                -240.0,
                80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "EmeraldRefinery"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Damage Branch/Emerald Refinery/EmeraldSmeltMult.tres",
            branch = "damage",
            name_key = "SKILLTREEUPG_CLONING_EMERALDS",
            name = "绿宝石复制",
            name_en = "Cloning Emeralds",
            description_key = "SKILLTREEUPG_CLONING_EMERALDS_DESC",
            description = "每精炼一颗绿宝石获得的绿宝石{statAmount}",
            description_en = "{statAmount} Emerald gained per Emerald refined",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    2.0,
                    4.0,
                    15.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryEmeraldMultStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "emerald_mult",
            upgrade_id = "refine_ruby",
            cost = {
                Emerald = 30,
                MissionRewardOre = 225
            },
            max_level = 3,
            cost_growth = 0.25,
            id = "EmeraldSmeltMult",
            position = {
                -280.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "EmeraldRefinery"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Tanks/FuelTank1.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_GAS_GAS_GAS",
            name = "燃料加满！",
            name_en = "GAS GAS GAS",
            description_key = "SKILLTREEUPG_GAS_GAS_GAS_DESC",
            description = "最大燃料{statAmount}",
            description_en = "{statAmount} total Fuel",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    5.0,
                    5.0,
                    12.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Fuel Upgrades/FuelTankUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 5.0,
            stat_id = "fuel_amount",
            upgrade_id = "general_stats",
            cost = {
                Stone = 3
            },
            max_level = 10,
            cost_growth = 0.3,
            id = "FuelTank1",
            position = {
                0.0,
                -40.0
            },
            unlocks = {
                "FuelEfficiency1"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "UpgradeStart"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Efficiency/FuelEfficiency1.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_ITS_A_HYBRID",
            name = "混合动力引擎",
            name_en = "It's a hybrid",
            description_key = "SKILLTREEUPG_ITS_A_HYBRID_DESC",
            description = "每次消耗燃料时保留{statAmount}燃料",
            description_en = "{statAmount} Fuel preserved whenever Fuel is used",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    49.0,
                    7.0,
                    12.0,
                    8.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Fuel Upgrades/FuelEfficiencyUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 10.0,
            stat_id = "fuel_efficiency",
            upgrade_id = "general_stats",
            cost = {
                Stone = 4
            },
            max_level = 10,
            cost_growth = 0.3,
            id = "FuelEfficiency1",
            position = {
                0.0,
                -80.0
            },
            unlocks = {
                "FuelEfficiency2",
                "OverdriveActive"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Efficiency/FuelEfficiency2.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_ITS_A_CHIMERA",
            name = "奇美拉引擎",
            name_en = "It's a Chimera",
            description_key = "SKILLTREEUPG_ITS_A_CHIMERA_DESC",
            description = "每次消耗燃料时保留{statAmount}燃料",
            description_en = "{statAmount} Fuel preserved whenever Fuel is used",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    379.0,
                    7.0,
                    12.0,
                    8.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Fuel Upgrades/FuelEfficiencyUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 10.0,
            stat_id = "fuel_efficiency",
            upgrade_id = "general_stats",
            cost = {
                Stone = 100,
                Silver = 25
            },
            max_level = 15,
            cost_growth = 0.25,
            id = "FuelEfficiency2",
            position = {
                40.0,
                -80.0
            },
            unlocks = {},
            level_to_unlock = 5,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelEfficiency1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Tanks/FuelTank2.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_GAS_GAS_GAS_GAS",
            name = "燃料加满！！",
            name_en = "GAS GAS GAS GAS",
            description_key = "SKILLTREEUPG_GAS_GAS_GAS_GAS_GAS_DESC",
            description = "最大燃料{statAmount}",
            description_en = "{statAmount} total Fuel",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    159.0,
                    5.0,
                    12.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Fuel Upgrades/FuelTank2Upgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "fuel_amount",
            upgrade_id = "general_stats",
            cost = {
                Stone = 350,
                Silver = 60
            },
            max_level = 10,
            cost_growth = 0.3,
            id = "FuelTank2",
            position = {
                0.0,
                -160.0
            },
            unlocks = {
                "RubyRefinery",
                "BulletWorms"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "OverdriveActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Overdrive/OverdriveActive.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_OVERDRIVE",
            name = "超载",
            name_en = "Overdrive",
            description_key = "SKILLTREEUPG_OVERDRIVE_DESC",
            description = "按住[img color=\"dff6f5\"]res://Assets/ControlsUI/lmb.tres[/img]进入超载状态",
            description_en = "Hold [img color=\"dff6f5\"]res://Assets/ControlsUI/lmb.tres[/img] to go into Overdrive",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    69.0,
                    3.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Overdrive/OverdriveUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 1,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 150,
                Silver = 30
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "OverdriveActive",
            position = {
                0.0,
                -120.0
            },
            unlocks = {
                "OverdriveEnergy",
                "FuelTank2",
                "OverdriveStrength"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelEfficiency1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Overdrive/OverdriveStrength.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_MINE_HARD_2",
            name = "超模",
            name_en = "Overpowered",
            description_key = "SKILLTREEUPG_MINE_HARD_2_DESC",
            description = "超载状态下钻头威力{statAmount}",
            description_en = "{statAmount} Drill damage during Overdrive",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    91.0,
                    4.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Overdrive/Stats/OverdriveStrengthUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 15.0,
            stat_id = "overdrive_strength",
            upgrade_id = "overdrive",
            cost = {
                Stone = 200
            },
            max_level = 5,
            cost_growth = 1.0,
            id = "OverdriveStrength",
            position = {
                40.0,
                -120.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "OverdriveActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Overdrive/OverdriveEnergy.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_OVERFUEL",
            name = "超载燃料",
            name_en = "Overfuel",
            description_key = "SKILLTREEUPG_OVERFUEL_DESC",
            description = "最大超载能量{statAmount}",
            description_en = "{statAmount} total Overdrive energy",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    114.0,
                    4.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Overdrive/Stats/OverdriveEnergyAmountUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 2.0,
            stat_id = "overdrive_amount",
            upgrade_id = "overdrive",
            cost = {
                Stone = 800,
                Silver = 120
            },
            max_level = 10,
            cost_growth = 1.0,
            id = "OverdriveEnergy",
            position = {
                -40.0,
                -120.0
            },
            unlocks = {
                "OverdriveRegen"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "OverdriveActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Overdrive/OverdriveRegen.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_LEFTOVERS",
            name = "剩饭",
            name_en = "Leftovers",
            description_key = "SKILLTREEUPG_LEFTOVERS_DESC",
            description = "每秒恢复的超载能量{statAmount}",
            description_en = "{statAmount} Overdrive energy regenerated per second",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    136.0,
                    4.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Overdrive/Stats/OverdriveRegenerationUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 10.0,
            stat_id = "overdrive_regeneration",
            upgrade_id = "overdrive",
            cost = {
                Stone = 1200,
                Gold = 100
            },
            max_level = 5,
            cost_growth = 1.0,
            id = "OverdriveRegen",
            position = {
                -40.0,
                -160.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "OverdriveEnergy"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Ruby Refinery/RubySmeltMult.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_CLONING_RUBIES",
            name = "红宝石复制",
            name_en = "Cloning Rubies",
            description_key = "SKILLTREEUPG_CLONING_RUBIES_DESC",
            description = "每精炼一颗红宝石获得的红宝石{statAmount}",
            description_en = "{statAmount} Ruby gained per Ruby refined",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    115.0,
                    5.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryRubyMultStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "ruby_mult",
            upgrade_id = "refine_ruby",
            cost = {
                Ruby = 30,
                MissionRewardOre = 150
            },
            max_level = 3,
            cost_growth = 0.25,
            id = "RubySmeltMult",
            position = {
                -120.0,
                -200.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "RubySmeltSpeed"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Bullet Worms/BulletWormCount.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_MAG_DUMP",
            name = "倾泻弹匣",
            name_en = "Mag Dump",
            description_key = "SKILLTREEUPG_MAG_DUMP_DESC",
            description = "发射子弹蠕虫{statAmount}条",
            description_en = "{statAmount} Bullet Worm launched",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    244.0,
                    6.0,
                    18.0,
                    11.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/BulletWormsAmountStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "bullet_worms",
            cost = {
                Stone = 36000,
                Platinum = 1800
            },
            max_level = 3,
            cost_growth = 0.8,
            id = "BulletWormCount",
            position = {
                80.0,
                -240.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BulletWormCooldown"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Last Ditch Effort/LastDitchEffort.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_LAST_DITCH_EFFORT",
            name = "背水一战",
            name_en = "Last Ditch Effort",
            description_key = "SKILLTREEUPG_LAST_DITCH_EFFORT_DESC",
            description = "剩余燃料小于或等于5%时，钻击速度翻倍",
            description_en = "Drill hit speed is doubled while remaining Fuel is <= 5%",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    46.0,
                    26.0,
                    18.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Last Ditch Effort/LastDitchEffortUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 70000000,
                Gold = 5000000,
                Emerald = 30
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "LastDitchEffort",
            position = {
                0.0,
                -280.0
            },
            unlocks = {
                "LastDitchArtefact",
                "Laser"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank3",
                "FuelEfficiency3"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Last Ditch Effort/LastDitchArtefact.tres",
            branch = "fuel",
            name_key = "ARTIFACT_SHOVEL",
            name = "铲子",
            name_en = "Shovel",
            description_key = "SKILLTREEUPG_PROCRASTINATION_WORKS_DESC",
            description = "背水一战期间挖掘获得的资源翻倍",
            description_en = "Resources mined during Last Ditch Effort are doubled",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    420.0,
                    3.0,
                    18.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/LastDitchEffortDoubleResourcesStatUpgrade.tscn",
            artefact = "res://Resources/Artefacts/ArtefactLastDitch.tres",
            is_artefact = true,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Emerald = 40,
                StarDebris = 25
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "LastDitchArtefact",
            position = {
                40.0,
                -280.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "LastDitchEffort"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Laser/LaserUnlock.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_OVERHEAT",
            name = "过热",
            name_en = "Overheat",
            description_key = "SKILLTREEUPG_OVERHEAT_DESC",
            description = "按住[img color=\"dff6f5\"]res://Assets/ControlsUI/rmb.tres[/img]从钻头发射远程光束",
            description_en = "Hold [img color=\"dff6f5\"]res://Assets/ControlsUI/rmb.tres[/img] to shoot a ranged beam from your Drill",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    486.0,
                    6.0,
                    18.0,
                    10.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Laser/LaserUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 1,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 70000000,
                Iridium = 850000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Laser",
            position = {
                0.0,
                -320.0
            },
            unlocks = {
                "LaserCapacity",
                "FuelTank4"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "LastDitchEffort"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Tanks/FuelTank4.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_GAS_GAS_GAS_GAS_GAS_GAS",
            name = "燃料加满！！！！",
            name_en = "GAS GAS GAS GAS GAS GAS",
            description_key = "SKILLTREEUPG_GAS_GAS_GAS_GAS_GAS_GAS_DESC",
            description = "最大燃料{statAmount}",
            description_en = "{statAmount} total Fuel",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    554.0,
                    5.0,
                    12.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsFuelAmountStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 50000.0,
            stat_id = "fuel_amount",
            upgrade_id = "general_stats",
            cost = {
                Stone = 40000000,
                Platinum = 2000000
            },
            max_level = 10,
            cost_growth = 0.4,
            id = "FuelTank4",
            position = {
                40.0,
                -320.0
            },
            unlocks = {
                "FuelEfficiency4",
                "AugmentIridium"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Laser"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/World/AugmentIridium.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_AUGMENT_IRIDIUM",
            name = "铱矿增产",
            name_en = "Augment Iridium",
            description_key = "SKILLTREEUPG_AUGMENT_IRIDIUM_DESC",
            description = "挖掘方块获得的铱{statAmount}",
            description_en = "{statAmount} Iridium dropped from mined blocks",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    201.0,
                    5.0,
                    15.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Augments/Iridium/AugmentIridiumUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = true,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "additional_amount",
            upgrade_id = "augment_iridium",
            cost = {
                Iridium = 15000000,
                StarStone = 1
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "AugmentIridium",
            position = {
                80.0,
                -320.0
            },
            unlocks = {
                "IridiumBonanza"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank4"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/World/IridiumBonanza.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_IRIDIUM_BONANZA",
            name = "铱富矿",
            name_en = "Iridium Bonanza",
            description_key = "SKILLTREEUPG_IRIDIUM_BONANZA_DESC",
            description = "挖掘后提供5倍铱的特殊铱矿方块",
            description_en = "Special Iridium blocks that give 5X more Iridium when mined",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    180.0,
                    4.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Iridium Bonanza/IridiumBonanzaUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "iridium_bonanza",
            cost = {
                Iridium = 210000000,
                StarStone = 3
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "IridiumBonanza",
            position = {
                80.0,
                -360.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "AugmentIridium"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Ruby Refinery/RubyRefineryUnlock.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_REFINE_RUBY",
            name = "宝石精炼厂",
            name_en = "The Gem Refinery",
            description_key = "SKILLTREEUPG_REFINE_RUBY_DESC",
            description = "精炼红宝石的建筑",
            description_en = "A building that refines rubies",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    94.0,
                    6.0,
                    10.0,
                    10.0
                }
            },
            effect_scene = "res://Scenes/Buildings/Smelter/BuildingSmelter.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Gold = 4500,
                Platinum = 3500
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "RubyRefinery",
            position = {
                -40.0,
                -200.0
            },
            unlocks = {
                "FuelTank3",
                "RubySmeltSpeed"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Ruby Refinery/RubySmeltSpeed.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_ROCK_POLISH",
            name = "精雕细琢",
            name_en = "Rock Polish",
            description_key = "SKILLTREEUPG_ROCK_POLISH_DESC",
            description = "宝石精炼厂每{currentAmount}秒精炼一次宝石",
            description_en = "The Gem Refinery refines gems every {currentAmount} seconds",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    137.0,
                    5.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryRubySmeltingRateStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -1.0,
            stat_id = "ruby_smelting_rate",
            upgrade_id = "refine_ruby",
            cost = {
                Gold = 700,
                Ruby = 15
            },
            max_level = 3,
            cost_growth = 0.2,
            id = "RubySmeltSpeed",
            position = {
                -80.0,
                -200.0
            },
            unlocks = {
                "RubySmeltMult"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "RubyRefinery"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Bullet Worms/BulletWormsUnlock.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_BULLET_WORMS",
            name = "子弹蠕虫",
            name_en = "Bullet Worms",
            description_key = "SKILLTREEUPG_BULLET_WORMS_DESC",
            description = "定期发射穿透方块的并造成破坏的子弹",
            description_en = "Periodically launch projectiles that pass through blocks and damage them",
            icon = {},
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Worm Bullets/WormBulletUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 2,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "damage",
            upgrade_id = "bullet_worms",
            cost = {
                Stone = 20000,
                Gold = 3000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "BulletWorms",
            position = {
                40.0,
                -200.0
            },
            unlocks = {
                "FuelEfficiency3",
                "BulletWormCooldown"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Bullet Worms/BulletWormCooldown.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_QUICK_RELOAD",
            name = "快速换弹",
            name_en = "Quick Reload",
            description_key = "SKILLTREEUPG_QUICK_RELOAD_DESC",
            description = "每{currentAmount}秒发射一次子弹蠕虫",
            description_en = "Launch Bullet Worms every {currentAmount} seconds",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    201.0,
                    6.0,
                    16.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/BulletWormsCooldownStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -0.5,
            stat_id = "cooldown",
            upgrade_id = "bullet_worms",
            cost = {
                Stone = 25000,
                Gold = 700
            },
            max_level = 5,
            cost_growth = 0.8,
            id = "BulletWormCooldown",
            position = {
                80.0,
                -200.0
            },
            unlocks = {
                "BulletWormCount",
                "BulletWormDamage"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BulletWorms"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Tanks/FuelTank5.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_GAS",
            name = "燃。",
            name_en = "Gas.",
            description_key = "SKILLTREEUPG_GAS_DESC",
            description = "最大燃料{statAmount}",
            description_en = "{statAmount} total Fuel",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    618.0,
                    4.0,
                    14.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsFuelAmountStatUpgrade3.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "fuel_amount",
            upgrade_id = "general_stats",
            cost = {
                Stone = 1875000000,
                Platinum = 95000000
            },
            max_level = 10,
            cost_growth = 0.4,
            id = "FuelTank5",
            position = {
                0.0,
                -400.0
            },
            unlocks = {
                "TheWorm"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "LaserDamage",
                "FuelEfficiency4"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Bullet Worms/BulletWormDamage.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_WORM_OF_HURT",
            name = "痛苦之虫",
            name_en = "Worm of Hurt",
            description_key = "SKILLTREEUPG_WORM_OF_HURT_DESC",
            description = "子弹蠕虫威力{statAmount}",
            description_en = "{statAmount} Bullet Worm damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    223.0,
                    6.0,
                    16.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/BulletWormsDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "damage",
            upgrade_id = "bullet_worms",
            cost = {
                Stone = 27000,
                Gold = 1300
            },
            max_level = 5,
            cost_growth = 0.8,
            id = "BulletWormDamage",
            position = {
                120.0,
                -200.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BulletWormCooldown"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Laser/LaserDamage.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_FEELING_THE_HEAT",
            name = "感受焦灼",
            name_en = "Feeling the Heat",
            description_key = "SKILLTREEUPG_FEELING_THE_HEAT_DESC",
            description = "过热光束威力{statAmount}",
            description_en = "{statAmount} Overheat beam damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    530.0,
                    2.0,
                    18.0,
                    18.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/OverheatLaserStrengthStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "laser_drill_scaling",
            upgrade_id = "overheat",
            cost = {
                Stone = 500000000,
                Iridium = 20000000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "LaserDamage",
            position = {
                -40.0,
                -360.0
            },
            unlocks = {
                "FuelTank5"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "LaserCapacity"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Efficiency/FuelEfficiency4.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_HYBRID_CHIMERA_COMBINATION",
            name = "姑且算是奇美拉混合动力引擎吧",
            name_en = "It's a Hybrid-Chimera Combination of Sorts",
            description_key = "SKILLTREEUPG_HYBRID_CHIMERA_COMBINATION_DESC",
            description = "每次消耗燃料时保留{statAmount}燃料",
            description_en = "{statAmount} Fuel preserved whenever Fuel is used",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    641.0,
                    7.0,
                    14.0,
                    10.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsFuelEfficiencyStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 3.0,
            stat_id = "fuel_efficiency",
            upgrade_id = "general_stats",
            cost = {
                Stone = 300000000,
                Iridium = 7000000,
                Diamond = 4
            },
            max_level = 5,
            cost_growth = 0.3513,
            id = "FuelEfficiency4",
            position = {
                40.0,
                -360.0
            },
            unlocks = {
                "FuelTank5"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank4"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Tanks/FuelTank3.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_GAS_GAS_GAS_GAS_GAS",
            name = "燃料加满！！！",
            name_en = "GAS GAS GAS GAS GAS",
            description_key = "SKILLTREEUPG_GAS_GAS_GAS_GAS_GAS_DESC",
            description = "最大燃料{statAmount}",
            description_en = "{statAmount} total Fuel",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    313.0,
                    5.0,
                    12.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsFuelAmountStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1000.0,
            stat_id = "fuel_amount",
            upgrade_id = "general_stats",
            cost = {
                Stone = 100000,
                Platinum = 3000
            },
            max_level = 10,
            cost_growth = 1.1,
            id = "FuelTank3",
            position = {
                -40.0,
                -240.0
            },
            unlocks = {
                "LastDitchEffort",
                "OverdriveStrength2"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "RubyRefinery"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Overdrive/OverdriveStrength2.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_PEAK_PERFORMANCE",
            name = "这就是巅峰状态",
            name_en = "this is what peak performance looks like",
            description_key = "SKILLTREEUPG_PEAK_PERFORMANCE_DESC",
            description = "超载状态下钻头威力{statAmount}",
            description_en = "{statAmount} Drill damage during Overdrive",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    22.0,
                    22.0,
                    22.0,
                    22.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Overdrive/Stats/OverdriveStrengthUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 10.0,
            stat_id = "overdrive_strength",
            upgrade_id = "overdrive",
            cost = {
                Stone = 60000,
                Iridium = 2800
            },
            max_level = 5,
            cost_growth = 0.7,
            id = "OverdriveStrength2",
            position = {
                -80.0,
                -240.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank3"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Efficiency/FuelEfficiency3.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_STILL_A_CHIMERA",
            name = "还是奇美拉引擎",
            name_en = "Still a Chimera",
            description_key = "SKILLTREEUPG_STILL_A_CHIMERA_DESC",
            description = "每次消耗燃料时保留{statAmount}燃料",
            description_en = "{statAmount} Fuel preserved whenever Fuel is used",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    576.0,
                    6.0,
                    14.0,
                    10.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsFuelEfficiencyStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 15.0,
            stat_id = "fuel_efficiency",
            upgrade_id = "general_stats",
            cost = {
                Stone = 130000,
                Platinum = 5500
            },
            max_level = 15,
            cost_growth = 0.33,
            id = "FuelEfficiency3",
            position = {
                40.0,
                -240.0
            },
            unlocks = {
                "LastDitchEffort"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BulletWorms"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Laser/LaserCapacity.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_HEAT_CAPACITY",
            name = "热容",
            name_en = "Heat Capacity",
            description_key = "SKILLTREEUPG_HEAT_CAPACITY_DESC",
            description = "最大过热能量{statAmount}",
            description_en = "{statAmount} total Overheat energy",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    442.0,
                    3.0,
                    18.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/OverheatLaserAmountStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 5.0,
            stat_id = "laser_amount",
            upgrade_id = "overheat",
            cost = {
                Stone = 140000000,
                Iridium = 3500000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "LaserCapacity",
            position = {
                -40.0,
                -320.0
            },
            unlocks = {
                "LaserDamage",
                "LaserChargeSpeed"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Laser"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/Laser/LaserChargeSpeed.tres",
            branch = "fuel",
            name_key = "ARTIFACT_LENS",
            name = "透镜",
            name_en = "Lens",
            description_key = "SKILLTREEUPG_HEAT_TRANSFER_DESC",
            description = "每挖一个方块获得{statAmount}过热能量",
            description_en = "{statAmount} Overheat energy gained per block mined",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    529.0,
                    2.0,
                    19.0,
                    18.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/OverheatEnergyPerDrillHitStatUpgrade1.tscn",
            artefact = "res://Resources/Artefacts/ArtefactLaser.tres",
            is_artefact = true,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.1,
            stat_id = "energy_per_drill_hit",
            upgrade_id = "overheat",
            cost = {
                Stone = 52000000,
                Iridium = 2100000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "LaserChargeSpeed",
            position = {
                -80.0,
                -320.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "LaserCapacity"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Fuel Branch/TheWorm.tres",
            branch = "fuel",
            name_key = "SKILLTREEUPG_LUMBRICUS",
            name = "星之金属：地龙王",
            name_en = "STARMETAL: LUMBRICUS",
            description_key = "SKILLTREEUPG_LUMBRICUS_DESC",
            description = "巨型蠕虫会定期出现",
            description_en = "You will be visited by THE WORM periodically",
            icon = {
                path = "res://Assets/starUpgrades.png",
                region = {
                    0.0,
                    0.0,
                    20.0,
                    20.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/The Worm/TheWormUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 2,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Starmetal = 1,
                Iridium = 200000000,
                StarStone = 3
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "TheWorm",
            position = {
                0.0,
                -480.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FuelTank5"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Stats/MiningRate1.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_EFFICIENCY_I",
            name = "效率 I",
            name_en = "Efficiency I",
            description_key = "SKILLTREEUPG_EFFICIENCY_I_DESC",
            description = "钻头每秒钻击{statAmount}次",
            description_en = "{statAmount} Drill hits per second",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    5.0,
                    72.0,
                    12.0,
                    11.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Drill Mining Rate/DrillMiningRateUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 5.0,
            stat_id = "drill_speed",
            upgrade_id = "general_stats",
            cost = {
                Stone = 10
            },
            max_level = 8,
            cost_growth = 0.3,
            id = "MiningRate1",
            position = {
                40.0,
                0.0
            },
            unlocks = {
                "ShockwaveActive"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "UpgradeStart"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/World/AugmentStone.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_AUGMENT_STONE",
            name = "石头增产",
            name_en = "Augment Stone",
            description_key = "SKILLTREEUPG_AUGMENT_STONE_DESC",
            description = "挖掘方块获得的石头{statAmount}",
            description_en = "{statAmount} Stone dropped from mined blocks",
            icon = {
                path = "res://Assets/Tilesets/augments.png",
                region = {
                    48.0,
                    5.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Augments/Stone/AugmentStoneUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = true,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "additional_amount",
            upgrade_id = "augment_stone",
            cost = {
                Stone = 150,
                Silver = 30
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "AugmentStone",
            position = {
                120.0,
                0.0
            },
            unlocks = {
                "AugmentSilver",
                "Fuelstone"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "ShockwaveActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/World/AugmentSilver.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_AUGMENT_IRON",
            name = "白银增产",
            name_en = "Augment Silver",
            description_key = "SKILLTREEUPG_AUGMENT_IRON_DESC",
            description = "挖掘方块获得的白银{statAmount}",
            description_en = "{statAmount} Silver dropped from mined blocks",
            icon = {
                path = "res://Assets/Tilesets/augments.png",
                region = {
                    25.0,
                    5.0,
                    16.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Augments/Silver/AugmentSilverUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = true,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "additional_amount",
            upgrade_id = "augment_iron",
            cost = {
                Stone = 600,
                Silver = 300
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "AugmentSilver",
            position = {
                120.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "AugmentStone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/World/FuelstoneUnlock.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_FUELSTONE",
            name = "燃料石",
            name_en = "Fuelstone",
            description_key = "SKILLTREEUPG_FUELSTONE_DESC",
            description = "挖掘后恢复燃料的特殊石头方块",
            description_en = "Special stone blocks that restore Fuel when mined",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    135.0,
                    70.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Fuelstone/FuelstoneUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 3000,
                Silver = 400
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Fuelstone",
            position = {
                160.0,
                0.0
            },
            unlocks = {
                "FuelstoneFrequency",
                "MiningRate2",
                "SilverBonanza"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "AugmentStone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/World/FuelstoneFrequency.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_FOSSIL_FUELS_ARE_FOR_SUCKERS",
            name = "化石燃料早过时啦",
            name_en = "Fossil Fuels are for suckers",
            description_key = "SKILLTREEUPG_FOSSIL_FUELS_ARE_FOR_SUCKERS_DESC",
            description = "燃料石出现率{statAmount}",
            description_en = "{statAmount} Fuelstone spawn chance",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    114.0,
                    70.0,
                    15.0,
                    15.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Fuelstone/FuelstoneFrequencyUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "chance",
            upgrade_id = "fuelstone",
            cost = {
                Stone = 500,
                Platinum = 100
            },
            max_level = 5,
            cost_growth = 0.35,
            id = "FuelstoneFrequency",
            position = {
                160.0,
                -40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Fuelstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Shockwave/ShockwaveActive.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_SHOCKWAVE",
            name = "冲击波",
            name_en = "Shockwave",
            description_key = "SKILLTREEUPG_SHOCKWAVE_DESC",
            description = "定期释放一次强力地震",
            description_en = "Release a powerful quake periodically",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    27.0,
                    70.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Shockwave/ShockwaveUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 4,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 45,
                Silver = 6
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "ShockwaveActive",
            position = {
                80.0,
                0.0
            },
            unlocks = {
                "ShockwaveDamage",
                "AugmentStone"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningRate1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Shockwave/ShockwaveDamage.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_SHOCKINGGGG",
            name = "太震撼了！！！",
            name_en = "SHOCKINGGGG!!!",
            description_key = "SKILLTREEUPG_SHOCKINGGGG_DESC",
            description = "冲击波威力{statAmount}",
            description_en = "{statAmount} Shockwave damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    45.0,
                    70.0,
                    18.0,
                    15.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Shockwave/ShockwaveDamageUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "damage",
            upgrade_id = "shockwave",
            cost = {
                Stone = 60
            },
            max_level = 5,
            cost_growth = 1.0,
            id = "ShockwaveDamage",
            position = {
                80.0,
                40.0
            },
            unlocks = {
                "ShockwaveRadius"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "ShockwaveActive"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Shockwave/ShockwaveRadius.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_CATCH_THE_WAVE_DUDE",
            name = "随波而动吧，老兄",
            name_en = "Catch the wave, dude",
            description_key = "SKILLTREEUPG_CATCH_THE_WAVE_DUDE_DESC",
            description = "冲击波半径{statAmount}",
            description_en = "{statAmount} Shockwave radius",
            icon = "res://Assets/UI/shockwav.png",
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Shockwave/ShockwaveRadiusUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 10.0,
            stat_id = "radius",
            upgrade_id = "shockwave",
            cost = {
                Stone = 90,
                Silver = 12
            },
            max_level = 3,
            cost_growth = 1.0,
            id = "ShockwaveRadius",
            position = {
                80.0,
                80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "ShockwaveDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Aftershocks/AftershocksUnlock.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_AFTERSHOCKS",
            name = "余震",
            name_en = "Aftershocks",
            description_key = "SKILLTREEUPG_AFTERSHOCKS_DESC",
            description = "定期使用一次同时破坏多个相连方块的钻击",
            description_en = "Periodically use a Drill hit that also damages multiple connected blocks",
            icon = {
                path = "res://Assets/Player Assets/Sprite-0001.png",
                region = {
                    0.0,
                    0.0,
                    22.0,
                    22.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Aftershocks/AftershocksUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 4,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 20000,
                Platinum = 4000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Aftershocks",
            position = {
                240.0,
                0.0
            },
            unlocks = {
                "AftershockDamage",
                "AftershockAmount"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningRate2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Aftershocks/AftershockAmount.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_SHOCK_OUT",
            name = "震个痛快",
            name_en = "Shock Out",
            description_key = "SKILLTREEUPG_SHOCK_OUT_DESC",
            description = "每次触发的余震次数{statAmount}",
            description_en = "{statAmount} Aftershocks per trigger",
            icon = {},
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/AftershocksAmountStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "aftershocks",
            cost = {
                Stone = 45000,
                Gold = 3500
            },
            max_level = 3,
            cost_growth = 0.8,
            id = "AftershockAmount",
            position = {
                240.0,
                40.0
            },
            unlocks = {
                "DiamondRefinery"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Aftershocks"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Diamond Refinery/DiamondRefineryUnlock.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_REFINE_DIAMOND",
            name = "精炼钻石",
            name_en = "Refine Diamond",
            description_key = "SKILLTREEUPG_REFINE_DIAMOND_DESC",
            description = "宝石精炼厂现在可以精炼钻石",
            description_en = "The Gem Refinery can now refine Diamonds",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    26.0,
                    5.0,
                    13.0,
                    12.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryDiamondEnabledStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = true,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "diamond_enabled",
            upgrade_id = "refine_ruby",
            cost = {
                Iridium = 200000,
                Emerald = 120,
                FactoryOre = 240
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "DiamondRefinery",
            position = {
                280.0,
                40.0
            },
            unlocks = {
                "DiamondSmeltSpeed",
                "DiamondSmeltMult"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "AftershockAmount"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/World/SilverBonanza.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_IRON_BONANZA",
            name = "白银富矿",
            name_en = "Silver Bonanza",
            description_key = "SKILLTREEUPG_IRON_BONANZA_DESC",
            description = "挖掘后提供5倍白银的特殊白银方块",
            description_en = "Special Silver blocks that give 5X more Silver when mined",
            icon = {},
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Silver Bonanza/SilverBonanzaUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "iron_bonanza",
            cost = {
                Silver = 4000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "SilverBonanza",
            position = {
                160.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Fuelstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Aftershocks/AftershockDamage.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_SHOCK_THE_HOUSE",
            name = "震翻全场",
            name_en = "Shock the House",
            description_key = "SKILLTREEUPG_SHOCK_THE_HOUSE_DESC",
            description = "余震造成基础钻击威力的{currentAmount}%",
            description_en = "Aftershocks deal {currentAmount}% of your base Drill hit damage",
            icon = {},
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/AftershocksDamageDrillHitStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 2,
            stat_amount = 20.0,
            stat_id = "damage",
            upgrade_id = "aftershocks",
            cost = {
                Stone = 66000,
                Iridium = 1800
            },
            max_level = 5,
            cost_growth = 0.8,
            id = "AftershockDamage",
            position = {
                240.0,
                -40.0
            },
            unlocks = {
                "AftershockArtefact",
                "Shrapnel",
                "AftershockSpread"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Aftershocks"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Aftershocks/AftershockSpread.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_SHOCK_AND_ROLL",
            name = "震荡摇滚",
            name_en = "Shock and Roll",
            description_key = "SKILLTREEUPG_SHOCK_AND_ROLL_DESC",
            description = "余震破坏的方块数量{statAmount}",
            description_en = "{statAmount} blocks damaged by Aftershocks",
            icon = {},
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/AftershocksTilesStatUpgrade2.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "tiles",
            upgrade_id = "aftershocks",
            cost = {
                Stone = 90000,
                Iridium = 5000
            },
            max_level = 3,
            cost_growth = 0.8,
            id = "AftershockSpread",
            position = {
                200.0,
                -40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "AftershockDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Shrapnel/ShrapnelUnlock.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_SHRAPNEL_DEBRIS",
            name = "碎岩弹片",
            name_en = "Shrapnel Debris",
            description_key = "SKILLTREEUPG_SHRAPNEL_DEBRIS_DESC",
            description = "定期发射碎岩，破坏经过路径上的方块",
            description_en = "Periodically launch fragments that damage blocks they pass over",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    93.0,
                    49.0,
                    12.0,
                    12.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Shrapnels/ShrapnelsUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 1,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 3800000,
                Iridium = 380000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Shrapnel",
            position = {
                280.0,
                -40.0
            },
            unlocks = {
                "ShrapnelDamage",
                "ShrapnelCount"
            },
            level_to_unlock = 5,
            starting = false,
            demo_locked = false,
            parents = {
                "AftershockDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Aftershocks/AftershockArtefact.tres",
            branch = "quake",
            name_key = "ARTIFACT_AMULET",
            name = "护身符",
            name_en = "Amulet",
            description_key = "SKILLTREEUPG_CHAIN_REACTION_DESC",
            description = "每{currentAmount}次余震中有1次范围提升至3倍",
            description_en = "1 in {currentAmount} Aftershocks has 3 times more reach",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    223.0,
                    70.0,
                    17.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/AftershocksAftershockArtefactStatUpgrade.tscn",
            artefact = "res://Resources/Artefacts/ArtefactAftershocks.tres",
            is_artefact = true,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 5.0,
            stat_id = "crit_proc",
            upgrade_id = "aftershocks",
            cost = {
                Iridium = 80000,
                StarDebris = 25
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "AftershockArtefact",
            position = {
                240.0,
                -80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "AftershockDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Shrapnel/ShrapnelCount.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_DREG_HEAP",
            name = "碎渣堆",
            name_en = "Dreg Heap",
            description_key = "SKILLTREEUPG_DREG_HEAP_DESC",
            description = "发射的碎岩弹片数量{statAmount}",
            description_en = "{statAmount} Shrapnel Debris fragment launched",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    333.0,
                    71.0,
                    15.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/ShrapnelsAmountStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "shrapnel_debris",
            cost = {
                Stone = 150000000,
                Iridium = 1500000
            },
            max_level = 10,
            cost_growth = 0.7,
            id = "ShrapnelCount",
            position = {
                280.0,
                -80.0
            },
            unlocks = {
                "ShrapnelRange"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Shrapnel"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Shrapnel/ShrapnelDamage.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_RUBBLE_TROUBLE",
            name = "碎石惹的祸",
            name_en = "Rubble Trouble",
            description_key = "SKILLTREEUPG_RUBBLE_TROUBLE_DESC",
            description = "碎岩弹片威力{statAmount}",
            description_en = "{statAmount} Shrapnel Debris fragment damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    356.0,
                    71.0,
                    16.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/ShrapnelsDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "damage",
            upgrade_id = "shrapnel_debris",
            cost = {
                Stone = 160000000,
                Iridium = 5000000
            },
            max_level = 5,
            cost_growth = 0.7,
            id = "ShrapnelDamage",
            position = {
                320.0,
                -40.0
            },
            unlocks = {
                "MiningSpeed"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Shrapnel"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Shrapnel/ShrapnelRange.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_DUST_TO_DUST",
            name = "尘归尘",
            name_en = "Dust to Dust",
            description_key = "SKILLTREEUPG_DUST_TO_DUST_DESC",
            description = "每{currentAmount}次钻击发射一次碎岩弹片",
            description_en = "Shrapnel Debris fire every {currentAmount} Drill hits",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    379.0,
                    71.0,
                    15.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/ShrapnelsCooldownStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -1.0,
            stat_id = "cooldown",
            upgrade_id = "shrapnel_debris",
            cost = {
                Stone = 140000000,
                Iridium = 3000000
            },
            max_level = 3,
            cost_growth = 0.7,
            id = "ShrapnelRange",
            position = {
                320.0,
                -80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "ShrapnelCount"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Stats/MiningRate2.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_EFFICIENCY_II",
            name = "效率 II",
            name_en = "Efficiency II",
            description_key = "SKILLTREEUPG_EFFICIENCY_II_DESC",
            description = "钻头每秒钻击{statAmount}次",
            description_en = "{statAmount} Drill hits per second",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    158.0,
                    70.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsDrillSpeedStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 2.0,
            stat_id = "drill_speed",
            upgrade_id = "general_stats",
            cost = {
                Stone = 2000,
                Gold = 500
            },
            max_level = 8,
            cost_growth = 0.25,
            id = "MiningRate2",
            position = {
                200.0,
                0.0
            },
            unlocks = {
                "Aftershocks",
                "GoldBonanza"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Fuelstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/World/GoldBonanza.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_GOLD_BONANZA",
            name = "黄金富矿",
            name_en = "Gold Bonanza",
            description_key = "SKILLTREEUPG_GOLD_BONANZA_DESC",
            description = "挖掘后提供5倍黄金的特殊黄金方块",
            description_en = "Special Gold blocks that give 5X more Gold when mined",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    487.0,
                    47.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Gold Bonanza/GoldenBonanzaUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "gold_bonanza",
            cost = {
                Gold = 1200000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "GoldBonanza",
            position = {
                200.0,
                40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningRate2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Boomerang/BoomerangSpawnRate.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_REBOUND_KING",
            name = "灌镐高手",
            name_en = "Rebound King",
            description_key = "SKILLTREEUPG_REBOUND_KING_DESC",
            description = "每{currentAmount}次钻击投掷一次回旋镐",
            description_en = "Throw a Pickarang every {currentAmount} Drill hits",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    511.0,
                    70.0,
                    16.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/PickarangCooldownStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -0.5,
            stat_id = "cooldown",
            upgrade_id = "pickarang",
            cost = {
                Stone = 2500000000,
                Iridium = 1750000000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "BoomerangSpawnRate",
            position = {
                400.0,
                40.0
            },
            unlocks = {
                "BoomerangArtefact"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Boomerang"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Boomerang/BoomerangArtefact.tres",
            branch = "quake",
            name_key = "ARTIFACT_INSTRUMENT",
            name = "乐器",
            name_en = "Instrument",
            description_key = "SKILLTREEUPG_TWO_BOOMERANGS_DESC",
            description = "投掷回旋镐{statAmount}把",
            description_en = "{statAmount} Pickarang thrown",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    465.0,
                    70.0,
                    17.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/PickarangAmountStatUpgrade.tscn",
            artefact = "res://Resources/Artefacts/ArtefactBoomerang.tres",
            is_artefact = true,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "pickarang",
            cost = {
                Diamond = 60,
                StarStone = 30
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "BoomerangArtefact",
            position = {
                400.0,
                80.0
            },
            unlocks = {},
            level_to_unlock = 5,
            starting = false,
            demo_locked = false,
            parents = {
                "BoomerangSpawnRate"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Boomerang/BoomerangUnlock.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_PICKARANG",
            name = "回旋镐",
            name_en = "Pickarang",
            description_key = "SKILLTREEUPG_PICKARANG_DESC",
            description = "定期向你朝向的方向投掷回旋镐",
            description_en = "Periodically throw a boomerang pickaxe in the direction you're looking",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    490.0,
                    70.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Boomerang Pick/BoomerangPickaxeUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 2,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 1000000000,
                Iridium = 120000000
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Boomerang",
            position = {
                400.0,
                0.0
            },
            unlocks = {
                "BoomerangDamage",
                "MiningRate3",
                "BoomerangSpawnRate"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningSpeed"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Boomerang/BoomerangDamage.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_FIRST_PICK",
            name = "最佳首选",
            name_en = "First Pick",
            description_key = "SKILLTREEUPG_FIRST_PICK_DESC",
            description = "回旋镐威力{statAmount}",
            description_en = "{statAmount} Pickarang damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    465.0,
                    70.0,
                    17.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/PickarangDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 30.0,
            stat_id = "damage",
            upgrade_id = "pickarang",
            cost = {
                Stone = 1250000000,
                Iridium = 250000000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "BoomerangDamage",
            position = {
                400.0,
                -40.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Boomerang"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Stats/MiningRate3.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_EFFICIENCY_IV",
            name = "效率 IV",
            name_en = "Efficiency IV",
            description_key = "SKILLTREEUPG_EFFICIENCY_IV_DESC",
            description = "钻头每秒钻击{statAmount}次",
            description_en = "{statAmount} Drill hits per second",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    444.0,
                    70.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsDrillSpeedStatUpgrade3.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 2.0,
            stat_id = "drill_speed",
            upgrade_id = "general_stats",
            cost = {
                Stone = 12000000000,
                Iridium = 2000000000,
                Diamond = 25
            },
            max_level = 1,
            cost_growth = 0.5,
            id = "MiningRate3",
            position = {
                440.0,
                0.0
            },
            unlocks = {
                "TermiteDrones"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Boomerang"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/TermiteDrones.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_MYRMIDRONES",
            name = "星之金属：无人机军团",
            name_en = "STARMETAL: MYRMIDRONES",
            description_key = "SKILLTREEUPG_MYRMIDRONES_DESC",
            description = "无人机跟随你的光标并破坏沿途的方块。每秒追加一架无人机",
            description_en = "Your cursor is followed by drones that damage blocks they pass over. Launch an additional drone every second",
            icon = {
                path = "res://Assets/starUpgrades.png",
                region = {
                    70.0,
                    0.0,
                    20.0,
                    20.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Termite Drone/TermiteDroneUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Starmetal = 1,
                Platinum = 500000000,
                StarStone = 3
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "TermiteDrones",
            position = {
                520.0,
                0.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "MiningRate3"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Diamond Refinery/DiamondSmeltSpeed.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_DIAMOND_POLISH",
            name = "钻石打磨",
            name_en = "Diamond Polish",
            description_key = "SKILLTREEUPG_DIAMOND_POLISH_DESC",
            description = "宝石精炼厂每{currentAmount}秒精炼一次钻石",
            description_en = "The Gem Refinery refines Diamonds every {currentAmount} seconds",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    70.0,
                    5.0,
                    14.0,
                    12.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryDiamondSmeltingRateStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -4.0,
            stat_id = "diamond_smelting_rate",
            upgrade_id = "refine_ruby",
            cost = {
                Platinum = 280000,
                Diamond = 20
            },
            max_level = 3,
            cost_growth = 0.2,
            id = "DiamondSmeltSpeed",
            position = {
                320.0,
                40.0
            },
            unlocks = {
                "MiningSpeed"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DiamondRefinery"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Diamond Refinery/DiamondSmeltMult.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_CLONING_DIAMONDS",
            name = "钻石复制",
            name_en = "Cloning Diamonds",
            description_key = "SKILLTREEUPG_CLONING_DIAMONDS_DESC",
            description = "每精炼一颗钻石获得的钻石{statAmount}",
            description_en = "{statAmount} Diamond gained per Diamond refined",
            icon = {
                path = "res://Assets/Tilesets/moreUIpgradesimage.png",
                region = {
                    48.0,
                    5.0,
                    15.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/RefineryDiamondMultStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "diamond_mult",
            upgrade_id = "refine_ruby",
            cost = {
                Diamond = 40,
                MissionRewardOre = 350
            },
            max_level = 3,
            cost_growth = 0.25,
            id = "DiamondSmeltMult",
            position = {
                280.0,
                80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DiamondRefinery"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/Quake Branch/Stats/MiningSpeed.tres",
            branch = "quake",
            name_key = "SKILLTREEUPG_EFFICIENCY_III",
            name = "效率 III",
            name_en = "Efficiency III",
            description_key = "SKILLTREEUPG_EFFICIENCY_III_DESC",
            description = "钻头每秒攻击{statAmount}次",
            description_en = "{statAmount} Drill hits per second",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    554.0,
                    70.0,
                    14.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsDrillSpeedStatUpgrade2.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 2.0,
            stat_id = "drill_speed",
            upgrade_id = "general_stats",
            cost = {
                Stone = 200000000,
                Iridium = 7000000
            },
            max_level = 3,
            cost_growth = 0.5,
            id = "MiningSpeed",
            position = {
                360.0,
                0.0
            },
            unlocks = {
                "Boomerang"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "ShrapnelDamage",
                "DiamondSmeltSpeed"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Stats/FieldOfView1.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_MINER_VISION",
            name = "矿工视觉",
            name_en = "Miner Vision",
            description_key = "SKILLTREEUPG_MINER_VISION_DESC",
            description = "可见方块范围半径{statAmount}",
            description_en = "{statAmount} visible block radius",
            icon = {
                path = "res://Assets/Tilesets/fov.png",
                region = {
                    4.0,
                    2.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/FOV/FovUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 16.0,
            stat_id = "fov_radius",
            upgrade_id = "general_stats",
            cost = {
                Silver = 5
            },
            max_level = 3,
            cost_growth = 0.4,
            id = "FieldOfView1",
            position = {
                0.0,
                40.0
            },
            unlocks = {
                "WorldSize1"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "UpgradeStart"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/World Size/WorldSize2.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_WIDTHERING_HEIGHTS",
            name = "呼啸宽庄",
            name_en = "Widthering Heights",
            description_key = "SKILLTREEUPG_WIDTHERING_HEIGHTS_DESC",
            description = "世界宽度{statAmount}",
            description_en = "{statAmount} world width",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    201.0,
                    30.0,
                    16.0,
                    7.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/WorldWidthUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 2.0,
            stat_id = "world_width",
            upgrade_id = "general_stats",
            cost = {
                Stone = 7000,
                Gold = 1200
            },
            max_level = 3,
            cost_growth = 0.4,
            id = "WorldSize2",
            position = {
                0.0,
                200.0
            },
            unlocks = {
                "DrillDrones",
                "AugmentGold"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Boomstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Drones/DrillDronesUnlock.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_DRILL_DRONES",
            name = "钻头无人机",
            name_en = "Drill Drones",
            description_key = "SKILLTREEUPG_DRILL_DRONES_DESC",
            description = "飞行钻头跟随你并挖掘周围的随机方块",
            description_en = "Flying drills follow you and mine random nearby blocks",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    225.0,
                    27.0,
                    12.0,
                    12.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Drill Drones/DrillDronesUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 2,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 130000,
                Platinum = 25000,
                FactoryOre = 60
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "DrillDrones",
            position = {
                0.0,
                240.0
            },
            unlocks = {
                "DrillDroneCount",
                "DrillDroneSpeed",
                "DrillDroneDamage",
                "FieldOfView2"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "WorldSize2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Boomstone/BoomstoneUnlock.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_BOOMSTONE",
            name = "爆爆石",
            name_en = "Boomstone",
            description_key = "SKILLTREEUPG_BOOMSTONE_DESC",
            description = "挖掘后会爆炸的特殊石头方块",
            description_en = "Special stone blocks that explode when mined",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    114.0,
                    26.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/BoomstoneUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 3,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 3500,
                Gold = 350
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Boomstone",
            position = {
                0.0,
                160.0
            },
            unlocks = {
                "BoomstoneSpawnRate",
                "WorldSize2",
                "BoomstoneRange"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Collector"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/World/AugmentGold.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_AUGMENT_GOLD",
            name = "黄金增产",
            name_en = "Augment Gold",
            description_key = "SKILLTREEUPG_AUGMENT_GOLD_DESC",
            description = "挖掘方块获得的黄金{statAmount}",
            description_en = "{statAmount} Gold dropped from mined blocks",
            icon = {
                path = "res://Assets/Tilesets/augments.png",
                region = {
                    3.0,
                    4.0,
                    16.0,
                    15.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Augments/Gold/AugmentGoldUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = true,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "additional_amount",
            upgrade_id = "augment_gold",
            cost = {
                Gold = 9000,
                StarDebris = 11
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "AugmentGold",
            position = {
                40.0,
                200.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "WorldSize2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Collector/CollectorUnlock.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_THE_COLLECTOR",
            name = "收集者",
            name_en = "The Collector",
            description_key = "SKILLTREEUPG_THE_COLLECTOR_DESC",
            description = "在你挖矿时生产铝的建筑",
            description_en = "A building that produces Alum while you mine",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    269.0,
                    5.0,
                    12.0,
                    13.0
                }
            },
            effect_scene = "res://Scenes/Buildings/Factory/BuildingFactory.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Silver = 80,
                Gold = 30
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "Collector",
            position = {
                0.0,
                120.0
            },
            unlocks = {
                "CollectorSpeed",
                "Boomstone"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "WorldSize1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Stats/FieldOfView2.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_MINER_HEARING",
            name = "矿工听觉",
            name_en = "Miner Hearing",
            description_key = "SKILLTREEUPG_MINER_HEARING_DESC",
            description = "可见范围半径{statAmount}",
            description_en = "{statAmount} visible block radius",
            icon = {
                path = "res://Assets/Tilesets/fov.png",
                region = {
                    26.0,
                    3.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsFovRadiusStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 16.0,
            stat_id = "fov_radius",
            upgrade_id = "general_stats",
            cost = {
                Stone = 300000,
                Gold = 15000
            },
            max_level = 3,
            cost_growth = 0.4,
            id = "FieldOfView2",
            position = {
                40.0,
                280.0
            },
            unlocks = {
                "WorldSize3",
                "DrillMissiles"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillDrones"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/World Size/WorldSize3.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_HIDDEN_IN_THE_WIDTHS",
            name = "宽不可测",
            name_en = "Hidden in the Widths",
            description_key = "SKILLTREEUPG_HIDDEN_IN_THE_WIDTHS_DESC",
            description = "世界宽度{statAmount}",
            description_en = "{statAmount} world width",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    486.0,
                    29.0,
                    18.0,
                    9.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsWorldWidthStatUpgrade2.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 2.0,
            stat_id = "world_width",
            upgrade_id = "general_stats",
            cost = {
                Stone = 5000000,
                Platinum = 420000,
                Emerald = 40
            },
            max_level = 3,
            cost_growth = 0.5,
            id = "WorldSize3",
            position = {
                80.0,
                280.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FieldOfView2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Collector/CollectorMult.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_COLLECTORS_EDITION",
            name = "收藏版",
            name_en = "Collector's Edition",
            description_key = "SKILLTREEUPG_COLLECTORS_EDITION_DESC",
            description = "收集者生产的铝{statAmount}",
            description_en = "{statAmount} Alum produced by the Collector",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    69.0,
                    70.0,
                    16.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/TheCollectorProductionAmountStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "production_amount",
            upgrade_id = "the_collector",
            cost = {
                FactoryOre = 50,
                MissionRewardOre = 100
            },
            max_level = 3,
            cost_growth = 0.25,
            id = "CollectorMult",
            position = {
                -80.0,
                120.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "CollectorSpeed"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Boomstone/BoomstoneDamage.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_STICKS_AND_EXPLODING_STONES",
            name = "棍棒和爆爆石会伤人",
            name_en = "Sticks and (exploding) stones",
            description_key = "SKILLTREEUPG_STICKS_AND_EXPLODING_STONES_DESC",
            description = "爆爆石爆炸威力{statAmount}",
            description_en = "{statAmount} Boomstone explosion damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    158.0,
                    26.0,
                    16.0,
                    17.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Boomstone/Stats/BoomstoneDamageUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 15.0,
            stat_id = "damage",
            upgrade_id = "boomstone",
            cost = {
                Stone = 6000,
                Platinum = 1400
            },
            max_level = 5,
            cost_growth = 0.8,
            id = "BoomstoneDamage",
            position = {
                -80.0,
                160.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "BoomstoneSpawnRate"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Boomstone/BoomstoneSpawnRate.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_ROCK_ROCK_BOMB_ROCK",
            name = "石头，剪刀，嘣！",
            name_en = "rock, rock, bomb, rock",
            description_key = "SKILLTREEUPG_ROCK_ROCK_BOMB_ROCK_DESC",
            description = "爆爆石出现率{statAmount}",
            description_en = "{statAmount} Boomstone spawn chance",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    135.0,
                    25.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Boomstone/Stats/BoomstoneSpawnRateUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "chance",
            upgrade_id = "boomstone",
            cost = {
                Stone = 4500,
                Gold = 490
            },
            max_level = 5,
            cost_growth = 0.8,
            id = "BoomstoneSpawnRate",
            position = {
                -40.0,
                160.0
            },
            unlocks = {
                "BoomstoneDamage"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Boomstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Collector/CollectorSpeed.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_COLLECTATHON",
            name = "收集马拉松",
            name_en = "Collectathon",
            description_key = "SKILLTREEUPG_COLLECTATHON_DESC",
            description = "收集者每{currentAmount}秒生产一次铝",
            description_en = "The Collector produces Alum every {currentAmount} seconds",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    291.0,
                    5.0,
                    13.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/TheCollectorProductionRateStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -2.0,
            stat_id = "production_rate",
            upgrade_id = "the_collector",
            cost = {
                Silver = 120,
                FactoryOre = 25
            },
            max_level = 3,
            cost_growth = 0.25,
            id = "CollectorSpeed",
            position = {
                -40.0,
                120.0
            },
            unlocks = {
                "CollectorMult"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Collector"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Drones/DrillDroneSpeed.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_PEREGREEN_V5",
            name = "游隼V5",
            name_en = "Peregreen V5",
            description_key = "SKILLTREEUPG_PEREGREEN_V5_DESC",
            description = "钻头无人机每秒钻击{statAmount}次",
            description_en = "{statAmount} Drill Drone hits per second",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    246.0,
                    27.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillDronesAttackSpeedStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 0.5,
            stat_id = "attack_speed",
            upgrade_id = "drill_drones",
            cost = {
                Stone = 270000,
                Platinum = 17000
            },
            max_level = 5,
            cost_growth = 0.7,
            id = "DrillDroneSpeed",
            position = {
                40.0,
                240.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillDrones"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Drones/DrillDroneCount.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_DRONE_ZONE",
            name = "无人机领域",
            name_en = "Drone zone",
            description_key = "SKILLTREEUPG_DRONE_ZONE_DESC",
            description = "钻头无人机{statAmount}架",
            description_en = "{statAmount} Drill Drone",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    290.0,
                    25.0,
                    14.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillDronesAmountStatUpgrade2.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "drill_drones",
            cost = {
                Stone = 160000,
                Platinum = 9000
            },
            max_level = 3,
            cost_growth = 0.7,
            id = "DrillDroneCount",
            position = {
                -40.0,
                240.0
            },
            unlocks = {
                "DrillDroneArtefact"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillDrones"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/FallingPickaxe.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_PICKRUN",
            name = "星之金属：巨镐奔袭",
            name_en = "STARMETAL: PICKRUN",
            description_key = "SKILLTREEUPG_PICKRUN_DESC",
            description = "迪格比会定期投掷一把巨型镐子",
            description_en = "Digby throws a gigantic pickaxe periodically",
            icon = {
                path = "res://Assets/starUpgrades.png",
                region = {
                    24.0,
                    0.0,
                    20.0,
                    20.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Falling Pickaxe/FallingPickaxeUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 2,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Starmetal = 1,
                Iridium = 200000000,
                StarDebris = 10
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "FallingPickaxe",
            position = {
                0.0,
                480.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FieldOfView4"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Stats/FieldOfView4.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_MINER_SNIFF",
            name = "矿工嗅觉",
            name_en = "Miner Sniff",
            description_key = "SKILLTREEUPG_MINER_SNIFF_DESC",
            description = "可见方块范围半径{statAmount}",
            description_en = "{statAmount} visible block radius",
            icon = {
                path = "res://Assets/Tilesets/fov.png",
                region = {
                    49.0,
                    3.0,
                    16.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsFovRadiusStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 16.0,
            stat_id = "fov_radius",
            upgrade_id = "general_stats",
            cost = {
                Stone = 1000000000
            },
            max_level = 5,
            cost_growth = 0.5,
            id = "FieldOfView4",
            position = {
                0.0,
                400.0
            },
            unlocks = {
                "FallingPickaxe"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillMissileAoE",
                "SpinningPickaxeCount"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Drones/DrillDroneArtefact.tres",
            branch = "world",
            name_key = "ARTIFACT_TENT_PEG",
            name = "帐篷地钉",
            name_en = "Tent Peg",
            description_key = "SKILLTREEUPG_LAST_DITCH_BUT_DRONES_DESC",
            description = "燃料耗尽时，钻头无人机会爆炸",
            description_en = "Drill Drones explode when you run out of Fuel",
            icon = {
                path = "res://Assets/Upgrades/artifacts.png",
                region = {
                    71.0,
                    5.0,
                    12.0,
                    13.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillDronesLastDitchStatUpgrade1.tscn",
            artefact = "res://Resources/Artefacts/ArtefactLastDitchDrillDrones.tres",
            is_artefact = true,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "last_ditch",
            upgrade_id = "drill_drones",
            cost = {
                Platinum = 70000,
                StarDebris = 20
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "DrillDroneArtefact",
            position = {
                -80.0,
                240.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillDroneCount"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Drones/DrillDroneDamage.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_OP_UAV",
            name = "超模无人机",
            name_en = "OP UAV",
            description_key = "SKILLTREEUPG_OP_UAV_DESC",
            description = "钻头无人机威力{statAmount}",
            description_en = "{statAmount} Drill Drone damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    269.0,
                    27.0,
                    16.0,
                    15.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillDronesDamageStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "damage",
            upgrade_id = "drill_drones",
            cost = {
                Stone = 330000,
                Iridium = 30000
            },
            max_level = 5,
            cost_growth = 0.7,
            id = "DrillDroneDamage",
            position = {
                -40.0,
                280.0
            },
            unlocks = {
                "SpinningPickaxe",
                "BoomstoneDamage2"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillDrones"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Boomstone/BoomstoneDamage2.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_BOOMING_RETURN",
            name = "劲爆回归",
            name_en = "Booming Return",
            description_key = "SKILLTREEUPG_BOOMING_RETURN_DESC",
            description = "爆爆石威力{statAmount}",
            description_en = "Increase Boomstone damage by {statAmount}",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    88.0,
                    66.0,
                    22.0,
                    22.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Boomstone/Stats/BoomstoneDamageUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 15.0,
            stat_id = "damage",
            upgrade_id = "boomstone",
            cost = {
                Stone = 9000000,
                Platinum = 420000
            },
            max_level = 5,
            cost_growth = 0.7,
            id = "BoomstoneDamage2",
            position = {
                -80.0,
                280.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillDroneDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Missiles/DrillMissilesUnlock.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_DRILL_MISSILE",
            name = "钻头导弹",
            name_en = "Drill Missile",
            description_key = "SKILLTREEUPG_DRILL_MISSILE_DESC",
            description = "爆炸钻弹会定期轰击屏幕上的随机位置",
            description_en = "Explosive projectiles periodically strike random spots on the screen",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    556.0,
                    24.0,
                    10.0,
                    18.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Drill Missiles/DrillMissilesUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 3,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 2000000000,
                Iridium = 200000000,
                FactoryOre = 200
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "DrillMissiles",
            position = {
                40.0,
                320.0
            },
            unlocks = {
                "DrillMissileSpawnRate",
                "DrillMissileAoE"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FieldOfView2"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Missiles/DrillMissileSpawnRate.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_CLOUDY_WITH_A_CHANCE_OF_MISSILES",
            name = "天降导弹",
            name_en = "Cloudy With a Chance of Missiles",
            description_key = "SKILLTREEUPG_CLOUDY_WITH_A_CHANCE_OF_MISSILES_DESC",
            description = "每{currentAmount}秒落下一枚钻头导弹",
            description_en = "Drill Missiles fall every {currentAmount} seconds",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    534.0,
                    23.0,
                    14.0,
                    18.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillMissilesCooldownStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = -0.5,
            stat_id = "cooldown",
            upgrade_id = "drill_missile",
            cost = {
                Stone = 500000000,
                Iridium = 500000000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "DrillMissileSpawnRate",
            position = {
                80.0,
                320.0
            },
            unlocks = {
                "DrillMissileArtefact",
                "DrillMissileDamage"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillMissiles"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Missiles/DrillMissileArtefact.tres",
            branch = "world",
            name_key = "ARTIFACT_FIREWORK",
            name = "烟花",
            name_en = "Firework",
            description_key = "SKILLTREEUPG_DRILLMISSILEAMOUNT_DESC",
            description = "钻头导弹{statAmount}枚",
            description_en = "{statAmount} Drill Missile",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    509.0,
                    24.0,
                    15.0,
                    17.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillMissilesAmountStatUpgrade.tscn",
            artefact = "res://Resources/Artefacts/ArtefactDrillMissile.tres",
            is_artefact = true,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "drill_missile",
            cost = {
                Iridium = 25000000,
                StarStone = 30
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "DrillMissileArtefact",
            position = {
                120.0,
                320.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillMissileSpawnRate"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/World Size/WorldSize4.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_HOW_DID_WIDTH_GET_HERE",
            name = "怎么宽到这来的？",
            name_en = "How Did Width Get Here?",
            description_key = "SKILLTREEUPG_HOW_DID_WIDTH_GET_HERE_DESC",
            description = "世界宽度{statAmount}",
            description_en = "{statAmount} world width",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    618.0,
                    29.0,
                    18.0,
                    9.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/GeneralStatsWorldWidthStatUpgrade4.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 2.0,
            stat_id = "world_width",
            upgrade_id = "general_stats",
            cost = {
                Stone = 70000000,
                Gold = 50000000
            },
            max_level = 3,
            cost_growth = 0.5,
            id = "WorldSize4",
            position = {
                -80.0,
                320.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "SpinningPickaxe"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Spinning Pickaxe/SpinningPickaxeUnlock.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_PICKAXE_ORBIT",
            name = "飞旋镐",
            name_en = "Pickaxe Orbit",
            description_key = "SKILLTREEUPG_PICKAXE_ORBIT_DESC",
            description = "一把漂浮镐子环绕你并破坏方块",
            description_en = "A floating pickaxe that circles you and damages blocks",
            icon = {
                path = "res://Assets/Tilesets/restOfUpgrades.png",
                region = {
                    114.0,
                    70.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Active Upgrades/Spinning Pickaxe/SpinningPickaxeUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = false,
            hide_stat = false,
            damage_source = 2,
            upgrade_type = 0,
            stat_amount = 0.0,
            stat_id = "",
            upgrade_id = "general_stats",
            cost = {
                Stone = 20000000,
                Iridium = 2100000,
                FactoryOre = 120
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "SpinningPickaxe",
            position = {
                -40.0,
                320.0
            },
            unlocks = {
                "WorldSize4",
                "SpinningPickaxeCount",
                "SpinningPickaxeDamage"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillDroneDamage"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Missiles/DrillMissileAoE.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_GROUND_ZERO",
            name = "爆炸原点",
            name_en = "Ground Zero",
            description_key = "SKILLTREEUPG_GROUND_ZERO_DESC",
            description = "钻头导弹爆炸半径{statAmount}",
            description_en = "{statAmount} Drill Missile explosion radius",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    595.0,
                    23.0,
                    20.0,
                    18.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillMissilesExplosionRadiusStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "explosion_radius",
            upgrade_id = "drill_missile",
            cost = {
                Stone = 720000000,
                Iridium = 700000000
            },
            max_level = 3,
            cost_growth = 0.6,
            id = "DrillMissileAoE",
            position = {
                40.0,
                360.0
            },
            unlocks = {
                "FieldOfView4"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillMissiles"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Drill Missiles/DrillMissileDamage.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_GOING_BALLISTIC",
            name = "暴走弹道",
            name_en = "Going Ballistic",
            description_key = "SKILLTREEUPG_GOING_BALLISTIC_DESC",
            description = "钻头导弹爆炸威力{statAmount}",
            description_en = "{statAmount} Drill Missile explosion damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    574.0,
                    23.0,
                    16.0,
                    19.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/DrillMissilesDamageStatUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "damage",
            upgrade_id = "drill_missile",
            cost = {
                Stone = 600000000,
                Iridium = 300000000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "DrillMissileDamage",
            position = {
                80.0,
                360.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "DrillMissileSpawnRate"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Spinning Pickaxe/SpinningPickaxeDamage.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_BATTLEPICKAXE",
            name = "战“镐”",
            name_en = "Battle(pick)axe",
            description_key = "SKILLTREEUPG_BATTLEPICKAXE_DESC",
            description = "漂浮镐子威力{statAmount}",
            description_en = "{statAmount} floating pickaxe damage",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    464.0,
                    25.0,
                    18.0,
                    18.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/PickaxeOrbitDamageStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "damage",
            upgrade_id = "pickaxe_orbit",
            cost = {
                Stone = 100000000,
                Iridium = 3000000
            },
            max_level = 5,
            cost_growth = 0.6,
            id = "SpinningPickaxeDamage",
            position = {
                0.0,
                320.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "SpinningPickaxe"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Spinning Pickaxe/SpinningPickaxeCount.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_PICK_ME_UP",
            name = "提起镐来",
            name_en = "Pick-me-up",
            description_key = "SKILLTREEUPG_PICK_ME_UP_DESC",
            description = "漂浮镐{statAmount}把",
            description_en = "{statAmount} floating pickaxe",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    421.0,
                    25.0,
                    17.0,
                    16.0
                }
            },
            effect_scene = "res://Resources/Skill-tree Upgrades/Basic Stat Upgrades/Generated/PickaxeOrbitAmountStatUpgrade1.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 1.0,
            stat_id = "amount",
            upgrade_id = "pickaxe_orbit",
            cost = {
                Stone = 600000000,
                Iridium = 12000000
            },
            max_level = 3,
            cost_growth = 0.6,
            id = "SpinningPickaxeCount",
            position = {
                -40.0,
                360.0
            },
            unlocks = {
                "FieldOfView4"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "SpinningPickaxe"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/Boomstone/BoomstoneRange.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_EXPLOSION_EROSION",
            name = "爆炸侵蚀",
            name_en = "Explosion erosion",
            description_key = "SKILLTREEUPG_EXPLOSION_EROSION_DESC",
            description = "爆爆石爆炸半径{statAmount}",
            description_en = "{statAmount} Boomstone explosion radius",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    180.0,
                    27.0,
                    14.0,
                    14.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/Boomstone/Stats/BoomstoneRadiusUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 1,
            stat_amount = 20.0,
            stat_id = "radius",
            upgrade_id = "boomstone",
            cost = {
                Stone = 6000,
                Platinum = 700
            },
            max_level = 3,
            cost_growth = 0.8,
            id = "BoomstoneRange",
            position = {
                40.0,
                160.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "Boomstone"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/World Size/WorldSize1.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_WE_NEED_TO_DIG_WIDER",
            name = "或许需要……挖宽一点？",
            name_en = "We need to dig… wider?",
            description_key = "SKILLTREEUPG_WE_NEED_TO_DIG_WIDER_DESC",
            description = "世界宽度{statAmount}",
            description_en = "{statAmount} world width",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    25.0,
                    30.0,
                    16.0,
                    7.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/World Modification Upgrades/WorldWidthUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 0,
            stat_amount = 2.0,
            stat_id = "world_width",
            upgrade_id = "general_stats",
            cost = {
                Stone = 80,
                Silver = 10
            },
            max_level = 3,
            cost_growth = 0.35,
            id = "WorldSize1",
            position = {
                0.0,
                80.0
            },
            unlocks = {
                "ResourceTripler",
                "Collector"
            },
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "FieldOfView1"
            }
        },
        {
            resource_path = "res://Resources/Skill-tree Upgrades/World Branch/World/ResourceTripler.tres",
            branch = "world",
            name_key = "SKILLTREEUPG_TRIPLE_TROUBLE",
            name = "三倍惊喜",
            name_en = "Triple trouble",
            description_key = "SKILLTREEUPG_TRIPLE_TROUBLE_DESC",
            description = "获得资源三倍化的几率{statAmount}",
            description_en = "{statAmount} chance to triple any resource gained",
            icon = {
                path = "res://Assets/UI/skilltreeNew.png",
                region = {
                    47.0,
                    27.0,
                    16.0,
                    10.0
                }
            },
            effect_scene = "res://Scenes/Upgrades/Resource Tripler/ResourceTriplerUpgrade.tscn",
            artefact = nil,
            is_artefact = false,
            is_stat = true,
            hide_stat = false,
            damage_source = 0,
            upgrade_type = 2,
            stat_amount = 5.0,
            stat_id = "chance",
            upgrade_id = "triple_trouble",
            cost = {
                Stone = 400,
                Gold = 18
            },
            max_level = 1,
            cost_growth = 0.2,
            id = "ResourceTripler",
            position = {
                -40.0,
                80.0
            },
            unlocks = {},
            level_to_unlock = 1,
            starting = false,
            demo_locked = false,
            parents = {
                "WorldSize1"
            }
        }
    }
}
