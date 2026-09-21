# 部署「已发布游戏镜像」避坑说明（给 Agent）

适用场景：把发布平台的资源镜像（内容寻址包：`assets/{uuid}-{hash}{ext}` + `manifest.json`）
还原成本地可构建的 UrhoX 项目。以下每一条都是本轮实际踩过的坑。

## 1. 镜像还原映射（先查 manifest，别猜）

manifest 的 `files[].fs_path` 按扩展名路由：

| fs_path | 目标目录 |
|---|---|
| `*.lua`（如 `main.lua`、`xxx/*.lua`） | `scripts/` |
| `image/ audio/ data/ Fonts/ *.png/wav/json/ttf/xml` | `assets/` |
| `settings.json` | `.project/settings.json` 的 `@runtime` 段 |
| `project.json`（包外层） | 只取内容元数据，**身份字段剔除**（见 §3） |

资源根规则：运行时路径 `image/x.png` = 磁盘 `assets/image/x.png`（`asset_dirs` 默认
`["../assets","../scripts"]`）。

## 2. 镜像常是「部分导出」，缺文件按 manifest 从 CDN 补

manifest 有 N 条、本地只有 M 条很常见。缺失条目直接下载：
`{CDN}/src/{project_id}/assets/{uuid}-{hash}{ext}`，逐个校验 `size` 与 manifest 一致。
本轮 528 个 png/wav 全部这样补回，100% 成功。别因为"缺 63%"就判定不可部署。

## 3. 🔴 原作者的发布身份绝不能带进项目

镜像 `project.json` 里的 `app_id / developer_id / miniapp_id / author.id / icon /
gameplay_demo_video_source` 属于**原作者**。部署到别人的工作区必须剔除，只保留游戏内容
元数据（标题、描述、category、横竖屏）。校验手段：

- `build` 工具会把 `project_id` 改成本工作区分配的值（如 `m_xxxx`）——这是正常的；
- `recover_publish_config` 返回「无已发布 App 映射」= 干净的新项目，符合预期；
- `list_tap_developers` 可确认当前账号身份。留着外来 app_id，发布动作会打到别人的 App。

## 4. `.project/resources.json` 镜像里没有，必须自己创建

缺它 build 直接报「找不到 resources.json」。这是构建期配置，不进发布包。
保守做法（与原包行为一致）：

```json
{ "preload_groups": [], "groups": { "default": ["**"] } }
```

## 5. 🔴 Web 预览报「引擎文件 URL 缺失」= sources.engine 填错地址

加载链（`index.min.js` 实测逻辑）：
`latest.json.engine → {version}/engine-<hash>.json → base_url → stable.json →
engine manifest → getFileUrl("UrhoXRuntime.js"/".wasm")`。

关键区分（**别照 manifest 键名猜 URL**）：

| 源 | 地址 | 内容 |
|---|---|---|
| WASM 运行时宿主 | `…/src/engine/` | `UrhoXRuntime.js/.wasm/.data`，仅此 4 文件 |
| 引擎资源包 | `…/src/engine-res/` | Lua/urhox-libs/材质 1000+ 文件，**无 wasm** |
| 官方公共资源 | `…/src/official-res/` | 官方预制资源 |

`.project/settings.json` 应配三条：`sources.engine → src/engine/`（保留键，喂 bootstrap，
产物生成 `engine-<hash>.json` + `latest.json.engine`），`sources.engine-res` 与
`sources.official-res` → 进 manifest.sources（运行时 DWP 按需拉取）。

**金标准：直接读线上原包的 `…/src/{project_id}/latest.json` 和
`engine-{engine哈希}.json`，它 base_url 指哪就抄哪。**
验证手段：build 后产物 `dist/latest.json` 的 `engine` 哈希应与原包一致
（本轮还原后两边同为 `ef9e23e2`），再模拟加载链确认 `UrhoXRuntime.js/.wasm` 可下载。

## 6. LSP 报错会拦截 build：常见为整数类型误推导

`self.x = 0` 会被推导成 integer，后面赋浮点 → `assign-type-mismatch` 阻断构建。
最小修复：初值写 `0.0`（Lua 语义不变）。改完必须过
`lua_lsp_client textDocument/diagnostic severity=1` 再 build。

## 7. 构建与验证流程

1. 每次改 `scripts/` 后必须调 MCP `build` 工具（禁止手写构建脚本、禁止动 `dist/`）。
2. 产物校验：manifest 每条 `{uuid}-{hash}{ext}` 都应能在 `dist/assets/` 命中；
   `latest.json` 含 `engine` 字段。
3. 运行验证用 `run-lua-validate`（validate 模式）：只信 JSON 报告并**过滤噪音**
   （`[ShaderError] shadercache_runtime/...`、Frame time spike）；
   真判据是 `lua_errors=0、resource_errors=0、missing_resources=[]`。
   若游戏自带 SelfTest，确认其 PASS。

## 8. 别多加目录 / 别被「看起来空」误导

- 除 `scripts/ assets/ .project/` 外不要往工作区根加常驻目录（截图、暂存、clone 副本
  用完即删）。发布素材 `game_material/` 属可选项，删除后 `.project/project.json`
  不要留指向它的死引用。
- `dist/` 在 `.gitignore` 里、且构建系统每次把它设成 `root:root 755/644`（预览服务托管
  所需）——文件树「看不见/看起来空」是显示过滤和权限设计，不是产物为空。用
  `find dist -type f | wc -l` 实证，别据此重建。

## 9. 广告/内购等运营能力按需同步

游戏代码调 `sdk:ShowRewardVideoAd` 时走 `setup-ads` skill + `get_ad_config`；
新项目未发布时它报「缺 app_id/developer_id」是**正确状态**，不要为通过检查去伪造身份，
代码里有 SDK 判空降级即可正常试玩。
