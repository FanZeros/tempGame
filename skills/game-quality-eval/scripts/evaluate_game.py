"""UrhoX 游戏下载包镜像质量评估器。

评估对象：Maker/TapTap 管线发布后的客户端下载缓存镜像，结构形如：
    <app_id>/<project_slug>/<host>/src/
        engine-res/     引擎共享资源层（stable.json 钉版本）
        engine-startup/ 引擎启动层
        official-res/   官方资源层
        <project_slug>/
            <version>/  manifest-*.json + version.json
            assets/     哈希资源（<uuid>-<hash><ext>）
            icon.png / project.json

用法：
    python3 evaluate_game.py --game <游戏根目录> [--format md|json] [--out <报告路径>]
    python3 evaluate_game.py --repo <含多个游戏目录的仓库根> [--format md]

输出：分维度打分 + 总分 + 分级 + 问题清单（Markdown 或 JSON）。
"""

import argparse
import json
import os
import re


LAYERS = ('engine', 'startup', 'official', 'game')


def find_games(repo_root):
    games = []
    for app_id in sorted(os.listdir(repo_root)):
        app_dir = os.path.join(repo_root, app_id)
        if not os.path.isdir(app_dir) or app_id.startswith('.'):
            continue
        for slug in sorted(os.listdir(app_dir)):
            slug_dir = os.path.join(app_dir, slug)
            pj = None
            for base, dirs, files in os.walk(slug_dir):
                if 'project.json' in files:
                    pj = os.path.join(base, 'project.json')
                    break
            if pj:
                games.append({'app_id': app_id, 'slug': slug, 'root': slug_dir, 'project_json': pj})
    return games


def load_json(path):
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            return json.load(f)
    except Exception:
        return None


def find_manifest(game_root):
    hits = []
    for base, dirs, files in os.walk(game_root):
        rel = os.path.relpath(base, game_root)
        parts = rel.replace('\\', '/').split('/')
        if 'engine-res' in parts or 'engine-startup' in parts or 'official-res' in parts:
            dirs[:] = []
            continue
        for f in files:
            if re.match(r'^manifest-[0-9a-f]+\.json$', f):
                hits.append(os.path.join(base, f))
    return sorted(hits)


def find_version_json(game_root):
    for base, dirs, files in os.walk(game_root):
        rel = os.path.relpath(base, game_root)
        parts = rel.replace('\\', '/').split('/')
        if 'engine-res' in parts or 'engine-startup' in parts or 'official-res' in parts:
            dirs[:] = []
            continue
        if 'version.json' in files:
            return os.path.join(base, 'version.json')
    return None


def layer_of(parts):
    """根据相对路径判断资产目录属于哪一层。"""
    if 'engine-res' in parts:
        return 'engine'
    if 'engine-startup' in parts:
        return 'startup'
    if 'official-res' in parts:
        return 'official'
    return 'game'


def find_asset_dirs(game_root):
    """返回 {layer: [assets 目录列表]}，同层可有多个目录，全部纳入统计。"""
    out = {k: [] for k in LAYERS}
    for base, dirs, files in os.walk(game_root):
        if os.path.basename(base) == 'assets':
            rel = os.path.relpath(base, game_root).replace('\\', '/')
            layer = layer_of(rel.split('/'))
            out[layer].append(base)
    return out


HASH_RE = re.compile(r'-([0-9a-f]{8})\.[A-Za-z0-9]+$')


def file_hash_part(name):
    m = HASH_RE.search(name)
    return m.group(1) if m else None


def analyze(game):
    root = game['root']
    issues = []

    pj = load_json(game['project_json']) or {}
    tp = pj.get('taptap_publish', {}) or {}
    assets_meta = pj.get('assets', {}) or {}

    meta = {
        'title': tp.get('title') or pj.get('project_id'),
        'description': tp.get('description') or '',
        'category': tp.get('category') or '',
        'orientation': tp.get('screen_orientation') or '',
        'app_id': tp.get('app_id') or game['app_id'],
        'version': pj.get('version'),
        'author_id': (pj.get('author') or {}).get('id'),
    }
    s_meta = 0
    if meta['title']:
        s_meta += 4
    else:
        issues.append(('高', '缺少游戏标题（taptap_publish.title）'))
    desc_len = len(meta['description'])
    if desc_len >= 20:
        s_meta += 4
    elif desc_len >= 10:
        s_meta += 2
    else:
        issues.append(('低', '游戏描述过短（%d 字符），影响商店页转化' % desc_len))
    if meta['category']:
        s_meta += 3
    else:
        issues.append(('低', '未设置游戏分类 category'))
    shots = len(assets_meta.get('screenshot_urls') or assets_meta.get('screenshots') or [])
    if shots >= 3:
        s_meta += 4
    elif shots >= 1:
        s_meta += 2
        issues.append(('低', '商店截图不足 3 张（当前 %d 张）' % shots))
    else:
        issues.append(('中', '完全缺少商店截图'))
    covers = sum(1 for k in ('cover_horizontal', 'cover_vertical') if assets_meta.get(k))
    s_meta += 2 if covers == 2 else (1 if covers == 1 else 0)
    if covers < 2:
        issues.append(('低', '横竖封面不全（%d/2）' % covers))
    if assets_meta.get('gameplay_demo_video_source') or tp.get('gameplay_demo_video_source'):
        s_meta += 2
    else:
        issues.append(('低', '缺少玩法演示视频'))
    if assets_meta.get('icon') or assets_meta.get('icon_url') or tp.get('icon'):
        s_meta += 1

    vj_path = find_version_json(game['root'])
    vj = load_json(vj_path) if vj_path else {}
    version = vj.get('version') or meta['version'] or ''
    build = vj.get('build', 0)
    manifests = find_manifest(game['root'])
    manifest = load_json(manifests[0]) if manifests else {}
    files = manifest.get('files', []) or []

    asset_dirs = find_asset_dirs(game['root'])

    # 分层磁盘索引：hash -> 出现次数；game 层单独做内容统计
    disk = {k: {} for k in LAYERS}
    game_bytes = 0
    ext_count = {}
    largest = []
    for layer, dirs in asset_dirs.items():
        for ad in dirs:
            for base, dirs2, fs in os.walk(ad):
                for f in fs:
                    fp = os.path.join(base, f)
                    try:
                        sz = os.path.getsize(fp)
                    except OSError:
                        continue
                    hp = file_hash_part(f)
                    if hp:
                        disk[layer][hp] = disk[layer].get(hp, 0) + 1
                    if layer == 'game':
                        game_bytes += sz
                        ext = os.path.splitext(f)[1].lower()
                        ext_count[ext] = ext_count.get(ext, 0) + 1
                        largest.append((sz, fp))
    largest.sort(reverse=True)

    # 清单条目按 source 分层核对缺失
    missing = []
    dup_groups = {}
    for f in files:
        hp = f.get('hash')
        if not hp:
            continue
        layer = f.get('source') or 'game'
        if layer not in disk:
            layer = 'game'
        hpw = f.get('hash@windows')
        found = hp in disk[layer] or hp in disk['engine'] or hp in disk['startup'] or hp in disk['official']
        if not found and hpw:
            found = hpw in disk[layer] or hpw in disk['engine'] or hpw in disk['startup'] or hpw in disk['official']
        if not found:
            missing.append(f)
    for layer in LAYERS:
        for hp, cnt in disk[layer].items():
            if cnt > 1:
                dup_groups[hp] = cnt

    # 代码规模：只统计 game 层（引擎启动脚本不算游戏代码）
    lua_files = []
    lua_lines = 0
    lua_comment = 0
    if asset_dirs.get('game'):
        for ad in asset_dirs['game']:
            for base, dirs, fs in os.walk(ad):
                for f in fs:
                    if f.lower().endswith('.lua'):
                        fp = os.path.join(base, f)
                        try:
                            sz = os.path.getsize(fp)
                            with open(fp, 'r', encoding='utf-8', errors='replace') as fh:
                                for line in fh:
                                    lua_lines += 1
                                    if line.lstrip().startswith('--'):
                                        lua_comment += 1
                            lua_files.append((sz, fp))
                        except OSError:
                            continue
    lua_files.sort(reverse=True)
    comment_ratio = (lua_comment / lua_lines * 100) if lua_lines else 0

    # 首屏：#blocking 组跨所有层（客户端启动前全量下载）
    blocking_files = 0
    blocking_bytes = 0
    for f in files:
        groups = f.get('groups') or []
        if '#blocking' in groups:
            blocking_files += 1
            blocking_bytes += f.get('size') or 0

    s_code = 0
    if len(lua_files) >= 10:
        s_code += 6
    elif len(lua_files) >= 5:
        s_code += 4
    else:
        s_code += 2
    if lua_lines >= 20000:
        s_code += 8
    elif lua_lines >= 10000:
        s_code += 6
    elif lua_lines >= 5000:
        s_code += 4
    elif lua_lines >= 1000:
        s_code += 2
    else:
        s_code += 1
    if comment_ratio >= 3:
        s_code += 3
    elif comment_ratio >= 1:
        s_code += 2
    else:
        s_code += 1
    if lua_files and lua_files[0][0] <= 300 * 1024:
        s_code += 3
    elif lua_files and lua_files[0][0] <= 600 * 1024:
        s_code += 2
    else:
        s_code += 1
        if lua_files:
            issues.append(('中', '存在超大单模块（最大 %d KB），建议拆分' % (lua_files[0][0] // 1024)))

    s_content = 0
    if lua_lines >= 20000:
        s_content += 10
    elif lua_lines >= 10000:
        s_content += 8
    elif lua_lines >= 5000:
        s_content += 6
    elif lua_lines >= 2000:
        s_content += 4
    elif lua_lines >= 500:
        s_content += 2
    else:
        s_content += 1
    n_assets = sum(ext_count.values())
    if n_assets >= 500:
        s_content += 5
    elif n_assets >= 200:
        s_content += 4
    elif n_assets >= 100:
        s_content += 3
    elif n_assets >= 30:
        s_content += 2
    else:
        s_content += 1
    gb = game_bytes / 1024 / 1024
    if gb >= 150:
        s_content += 5
    elif gb >= 80:
        s_content += 4
    elif gb >= 40:
        s_content += 3
    elif gb >= 10:
        s_content += 2
    else:
        s_content += 1

    s_asset = 20
    # 清单 vs 磁盘差异属于"镜像导出完整性"，不计入游戏质量分，仅提示
    if len(missing) > 0:
        ratio = len(missing) / max(1, len(files)) * 100
        issues.append(('提示', '镜像为部分导出：%d/%d 个清单资源不在包内（%0.1f%%），不影响游戏质量评分' % (len(missing), len(files), ratio)))
    if len(dup_groups) > 0:
        s_asset -= min(4, len(dup_groups))
        issues.append(('低', '发现 %d 组重复内容文件（同哈希多副本），可清理节省包体' % len(dup_groups)))
    big = [x for x in largest if x[0] > 20 * 1024 * 1024]
    if big:
        s_asset -= min(4, len(big))
        for sz, fp in big[:3]:
            issues.append(('中', '超大单资源 %0.1fMB：%s' % (sz / 1024 / 1024, os.path.basename(fp))))

    s_preload = 0
    if blocking_files <= 50:
        s_preload += 10
    elif blocking_files <= 120:
        s_preload += 7
    elif blocking_files <= 300:
        s_preload += 4
    else:
        s_preload += 2
        issues.append(('中', '#blocking 首屏文件数偏多（%d 个），影响首次进入速度' % blocking_files))
    pmb = blocking_bytes / 1024 / 1024
    if pmb <= 30:
        s_preload += 10
    elif pmb <= 80:
        s_preload += 7
    elif pmb <= 150:
        s_preload += 4
    else:
        s_preload += 2
        issues.append(('中', '#blocking 首屏体积偏大（%0.1fMB），建议拆分到后台下载' % pmb))

    scores = {'元数据完整度': max(0, s_meta), '内容规模': max(0, s_content),
              '资源健康': max(0, s_asset), '首屏体验': max(0, s_preload), '代码组织': max(0, s_code)}
    total = sum(scores.values())
    grade = 'S' if total >= 85 else 'A' if total >= 70 else 'B' if total >= 55 else 'C' if total >= 40 else 'D'

    details = {
        'version': version, 'build': build, 'engine': vj.get('engine'),
        'lua': {'files': len(lua_files), 'lines': lua_lines, 'comment_ratio': round(comment_ratio, 2),
                'largest_kb': (lua_files[0][0] // 1024) if lua_files else 0},
        'assets': {'count': n_assets, 'bytes': game_bytes, 'ext_count': ext_count,
                   'largest_mb': round(largest[0][0] / 1024 / 1024, 1) if largest else 0},
        'manifest': {'files': len(files), 'missing': len(missing), 'dup_groups': len(dup_groups),
                     'blocking_files': blocking_files, 'blocking_mb': round(pmb, 1)},
        'layers': {k: len(v) for k, v in asset_dirs.items()},
        'meta_raw': meta,
    }

    return {'game': {'app_id': game['app_id'], 'slug': game['slug'], 'root': game['root']},
            'meta': meta, 'scores': scores, 'total': total, 'grade': grade,
            'issues': issues, 'details': details}


def render_md(r):
    m = r['meta']
    d = r['details']
    out = []
    out.append('# 游戏质量评估报告：%s（%s / %s）' % (m['title'], r['game']['app_id'], r['game']['slug']))
    out.append('')
    out.append('- 版本：%s（build %s） | 引擎：%s | 分类：%s %s | 作者ID：%s' %
               (d['version'], d['build'], d.get('engine') or '-', m['category'] or '-', m['orientation'] or '-', m['author_id'] or '-'))
    out.append('- 总分：**%d / 100（%s 级）**' % (r['total'], r['grade']))
    out.append('')
    out.append('| 维度 | 得分 | 满分 |')
    out.append('|---|---|---|')
    full = {'元数据完整度': 20, '内容规模': 20, '资源健康': 20, '首屏体验': 20, '代码组织': 20}
    for k, v in r['scores'].items():
        out.append('| %s | %d | %d |' % (k, v, full[k]))
    out.append('')
    out.append('## 规模画像')
    out.append('')
    out.append('- 代码：%d 个 Lua 模块，共 %d 行（注释率 %s%%），最大单模块 %s KB' %
               (d['lua']['files'], d['lua']['lines'], d['lua']['comment_ratio'], d['lua']['largest_kb']))
    out.append('- 游戏层资源：%d 个文件，类型分布 %s' %
               (d['assets']['count'],
                ', '.join('%s×%d' % (k, v) for k, v in sorted(d['assets']['ext_count'].items(), key=lambda x: -x[1])[:6])))
    out.append('- 清单：%d 条资源记录；缺失 %d；重复组 %d；首屏（#blocking）%d 个文件 / %s MB' %
               (d['manifest']['files'], d['manifest']['missing'], d['manifest']['dup_groups'],
                d['manifest']['blocking_files'], d['manifest']['blocking_mb']))
    out.append('')
    out.append('## 问题清单')
    out.append('')
    if r['issues']:
        for sev, msg in r['issues']:
            out.append('- [%s] %s' % (sev, msg))
    else:
        out.append('（未发现明显问题）')
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--game', help='单个游戏根目录（含 project_slug/project.json）')
    g.add_argument('--repo', help='含多个游戏的仓库根目录')
    ap.add_argument('--format', choices=['md', 'json'], default='md')
    ap.add_argument('--out', help='报告输出路径（缺省打印到 stdout）')
    args = ap.parse_args()

    if args.repo:
        games = find_games(args.repo)
    else:
        base = os.path.normpath(args.game)
        slug = os.path.basename(base)
        app_id = os.path.basename(os.path.dirname(base))
        pj = None
        for b, dirs, fs in os.walk(base):
            if 'project.json' in fs:
                pj = os.path.join(b, 'project.json')
                break
        games = [{'app_id': app_id, 'slug': slug, 'root': base, 'project_json': pj}]

    reports = []
    for gme in games:
        try:
            reports.append(analyze(gme))
        except Exception as e:
            reports.append({'game': gme, 'scores': {}, 'total': 0, 'grade': '评估失败',
                            'issues': [('高', '评估器异常：%s' % e)], 'meta': {}, 'details': {}})

    if args.format == 'json':
        out = json.dumps(reports, ensure_ascii=False, indent=1)
    else:
        out = '\n\n---\n\n'.join(render_md(r) for r in reports)

    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            f.write(out)
        print('report written:', args.out)
    else:
        print(out)


if __name__ == '__main__':
    main()
