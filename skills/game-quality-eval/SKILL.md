---
name: game-quality-eval
description: >
  UrhoX/TapMaker 游戏下载包镜像（客户端缓存导出）的质量评估器。对形如
  app_id/项目代号/CDN域名/src/{engine-res, engine-startup, official-res, 项目代号} 的
  游戏包做自动化取数与打分：元数据完整度、内容规模、资源健康、首屏体验、代码组织
  五个维度各 20 分，输出总分 + 分级（S/A/B/C/D）+ 问题清单（Markdown/JSON）。
  内置脚本 scripts/evaluate_game.py 支持单游戏与批量模式，自动处理双平台哈希变体、
  分层资源归因、镜像部分导出等边界。
  Use when users need to (1) 评估某个 UrhoX 游戏的质量, (2) 给游戏打分/出质量报告,
  (3) 批量对比多个游戏包的优劣, (4) 分析 tempGame 这类下载包镜像的结构,
  (5) 检查游戏包资源健康（缺失/重复/超大文件）, (6) 评估商店元数据完整度。
  SKIP when: 评估对象是 Maker 工程源码（scripts/ 源码树）而非发布下载包；
  或用户想要的是运行时性能压测而非静态包体质量。
---

# UrhoX 游戏下载包镜像质量评估

## 一、评估对象与目录结构

评估对象是 Maker/TapTap 管线发布后的**客户端下载缓存镜像**（如 tempGame 仓库），结构：

```
<app_id>/                              ← TapTap 应用 ID（如 818989）
  <项目代号>/                           ← 如 p_qigc / p_cjwc
    <CDN域名>/src/
      engine-res/<版本>/assets/        ← 引擎共享资源层（stable.json 钉版本）
      engine-startup/<版本>/assets/    ← 引擎启动层（含引擎自己的启动 Lua）
      official-res/<版本>/assets/      ← 官方资源层
      <项目代号>/
        <版本>/                        ← manifest-*.json + version.json
        assets/                        ← 游戏自身哈希资源（<uuid>-<hash><ext>）
        icon.png / project.json        ← 元数据
```

关键事实：
- 清单格式与 Maker 工程完全同构：files[uuid/fs_path/hash/hash@windows/size/groups/source]
  + preload_groups（#blocking/#config/#engine-res…）+ entry main.lua
- 游戏逻辑是**源码 Lua 随包分发**（非字节码），可直接静态分析
- 一个清单条目有 `hash` 与 `hash@windows` 两个变体（不同平台打包后的内容哈希不同），
  磁盘文件名里的哈希可能是其中任一变体——**校验存在性必须双查**
- 镜像通常是**部分导出**（客户端按需下载，只含已拉取的资源），磁盘文件数少于清单条目数
  属正常现象，不代表游戏质量差

## 二、使用方法

```bash
# 评估单个游戏（--game 指向 app_id 下的项目目录，或任意含 project.json 的根）
python3 scripts/evaluate_game.py --game /path/to/818989/p_qigc

# 批量评估仓库里所有游戏（自动发现）
python3 scripts/evaluate_game.py --repo /path/to/tempGame

# JSON 格式（供程序消费）
python3 scripts/evaluate_game.py --repo /path/to/tempGame --format json

# 报告落盘
python3 scripts/evaluate_game.py --repo /path/to/tempGame --out quality_report.md
```

## 三、评估维度与打分标准（总分 100）

### 1. 元数据完整度（20 分）
| 项 | 分值 |
|---|---|
| 标题非空 | 4 |
| 描述 ≥20 字（≥10 字得 2） | 4 |
| 分类 category 非空 | 3 |
| 商店截图 ≥3 张（1-2 张得 2） | 4 |
| 横竖封面齐全（缺 1 得 1） | 2 |
| 玩法演示视频 | 2 |
| 图标 | 1 |

### 2. 内容规模（20 分）
- Lua 总行数：≥20k→10 / ≥10k→8 / ≥5k→6 / ≥2k→4 / ≥500→2 / 其他→1
- 游戏层资源数：≥500→5 / ≥200→4 / ≥100→3 / ≥30→2 / 其他→1
- 游戏层资源体积：≥150MB→5 / ≥80MB→4 / ≥40MB→3 / ≥10MB→2 / 其他→1

### 3. 资源健康（20 分，只扣游戏自身可归因项）
- 同哈希多副本（重复内容）：每组 -1，上限 -4
- 超大单资源（>20MB）：每个 -1，上限 -4
- 注意：清单 vs 磁盘的差异是**镜像导出完整性**问题，只出 [提示] 不扣分
  （镜像本来就可能部分导出，不是游戏的错）

### 4. 首屏体验（20 分）
- #blocking 组文件数：≤50→10 / ≤120→7 / ≤300→4 / 更多→2
- #blocking 组体积：≤30MB→10 / ≤80MB→7 / ≤150MB→4 / 更多→2
- #blocking 跨所有资源层统计（客户端启动前全量下载，不分来源）

### 5. 代码组织（20 分）
- Lua 模块数：≥10→6 / ≥5→4 / 其他→2
- 总行数：≥20k→8 / ≥10k→6 / ≥5k→4 / ≥1k→2 / 其他→1
- 注释率：≥3%→3 / ≥1%→2 / 其他→1
- 最大单模块：≤300KB→3 / ≤600KB→2 / 更大→1 并出 [中] 拆分建议

### 分级
总分 ≥85 S ｜ ≥70 A ｜ ≥55 B ｜ ≥40 C ｜ <40 D

## 四、报告结构

Markdown 报告包含：游戏身份（标题/app_id/项目代号/版本/引擎/分类/作者）、
总分与分级、五维度得分表、规模画像（代码/资源/清单量化数据）、问题清单
（[高]/[中]/[低]/[提示] 四级）。`--format json` 输出同结构机器可读版。

## 五、实现要点与已踩坑（改脚本前必读）

1. **分层归因**：assets 目录按所在路径归入 engine/startup/official/game 四层；
   game 层的判定不能只看第一层目录（版本目录下的 assets 可能为空），必须合并
   同层全部 assets 目录（收集列表而非 setdefault 覆盖）
2. **双平台哈希变体**：磁盘文件名可能是 `hash` 或 `hash@windows` 任一变体，
   存在性校验必须双查；更稳妥的做法是先建 uuid→磁盘哈希 索引再比对
3. **引擎启动脚本不算游戏代码**：engine-startup/assets 里的 Lua（两个游戏完全相同，
   ~4 个文件/3000 行）是引擎启动层，混入会严重污染代码规模统计
4. **#blocking 跨层统计**：首屏下载不分来源，所有层的 #blocking 资源都算
5. **清单文件筛选**：manifest-*.json 只在游戏版本目录找（排除 engine-res/
   engine-startup/official-res 层，避免误抓引擎清单）
6. **文件系统一致性**：NAS 挂载（如工作区）读写可能返回过期/不一致状态——
   对同一文件的"写入→校验"必须在同一次调用内完成，跨调用的读取可能拿到旧版本
7. **heredoc 写文件的转义坑**：通过 bash heredoc 写含 `\!=` 的脚本会被转义成 `\\!=`
   导致语法错误——用 python chr(33) 拼接或 Write 工具规避

## 六、扩展方向

- 运行时验证：用 run-lua-validate / Playwright 实跑游戏补静态评估无法覆盖的维度
  （启动时长、实际渲染、玩法完整性）
- 代码深评：对最大模块做圈复杂度/重复代码检测（如 radon/jscpd）
- 对比模式：多游戏同维度雷达图对比（数据已由 --format json 输出）
