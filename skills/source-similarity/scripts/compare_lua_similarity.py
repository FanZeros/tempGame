#!/usr/bin/env python3
"""Compare published-game Lua with a local scripts/ tree.

The published side is a Maker/TapTap download mirror. Lua files are stored as
content-addressed assets (`<uuid>-<hash>.lua`). Original paths come from the
package manifest `files[].fs_path`.

Usage:
    python3 compare_lua_similarity.py --game <app_or_project_dir> --scripts <scripts_dir>
    python3 compare_lua_similarity.py --game 856061 --scripts /path/to/scripts --format json
"""

import argparse
import difflib
import hashlib
import json
import os
import re
import sys


SKIP_PARTS = ("engine-res", "engine-startup", "official-res")


def load_json(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return json.load(f)


def find_manifest(game_root):
    hits = []
    for base, dirs, files in os.walk(game_root):
        rel = os.path.relpath(base, game_root).replace("\\", "/")
        parts = rel.split("/")
        if any(part in parts for part in SKIP_PARTS):
            dirs[:] = []
            continue
        for name in files:
            if re.match(r"^manifest-[0-9a-f]+\.json$", name):
                hits.append(os.path.join(base, name))
    if not hits:
        return None
    hits.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return hits[0]


def find_asset_dir(manifest_path):
    version_dir = os.path.dirname(manifest_path)
    sibling = os.path.join(os.path.dirname(version_dir), "assets")
    if os.path.isdir(sibling):
        return sibling
    for base, dirs, files in os.walk(os.path.dirname(version_dir)):
        rel = os.path.relpath(base, os.path.dirname(version_dir)).replace("\\", "/")
        if any(part in rel.split("/") for part in SKIP_PARTS):
            dirs[:] = []
            continue
        if os.path.basename(base) == "assets":
            return base
    return None


def asset_path(asset_dir, entry):
    ext = entry.get("ext") or ""
    uuid = entry.get("uuid") or ""
    hashes = [entry.get("hash"), entry.get("hash@windows")]
    for digest in hashes:
        if not digest:
            continue
        path = os.path.join(asset_dir, f"{uuid}-{digest}{ext}")
        if os.path.isfile(path):
            return path
    return None


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    if data.startswith(b"\x1bLua"):
        return None
    return data.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def norm_lines(text, drop_blank):
    lines = [line.rstrip() for line in text.split("\n")]
    if lines and lines[-1] == "":
        lines = lines[:-1]
    if drop_blank:
        lines = [line for line in lines if line.strip()]
    return lines


def sha256(text):
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


def line_ratio(left, right):
    if left == right:
        return 1.0
    if not left or not right:
        return 0.0
    return difflib.SequenceMatcher(a=left, b=right, autojunk=False).ratio()


def topdir(path):
    return path.split("/")[0] if "/" in path else "(root)"


def is_tooling(path):
    return path.startswith("_proc/") or "/_proc/" in path


def collect_local(scripts_dir):
    local = {}
    for root, dirs, files in os.walk(scripts_dir):
        dirs[:] = [name for name in dirs if name != ".git"]
        for name in files:
            if not name.endswith(".lua"):
                continue
            full = os.path.join(root, name)
            rel = os.path.relpath(full, scripts_dir).replace("\\", "/")
            text = read_text(full)
            if text is None:
                continue
            lines = norm_lines(text, drop_blank=False)
            local[rel] = {
                "sha": sha256(text),
                "lines": lines,
                "lines_nb": norm_lines(text, drop_blank=True),
                "nlines": len(lines),
            }
    return local


def collect_published(manifest_path, asset_dir):
    manifest = load_json(manifest_path)
    published = {}
    missing = []
    bytecode = []
    for entry in manifest.get("files") or []:
        if entry.get("ext") != ".lua":
            continue
        rel = entry.get("fs_path")
        if not rel:
            continue
        path = asset_path(asset_dir, entry)
        info = {"present": path is not None, "declared_size": entry.get("size") or 0}
        if path is None:
            missing.append(rel)
            published[rel] = info
            continue
        text = read_text(path)
        if text is None:
            bytecode.append(rel)
            info["kind"] = "bytecode"
            published[rel] = info
            continue
        lines = norm_lines(text, drop_blank=False)
        info.update({
            "kind": "text",
            "sha": sha256(text),
            "lines": lines,
            "lines_nb": norm_lines(text, drop_blank=True),
            "nlines": len(lines),
        })
        published[rel] = info
    return manifest, published, missing, bytecode


def compare(published, local):
    pub_paths = set(published)
    loc_paths = set(local)
    both = sorted(pub_paths & loc_paths)
    only_pub = sorted(pub_paths - loc_paths)
    only_loc = sorted(loc_paths - pub_paths)

    pair_weight = 0
    pair_sim = 0.0
    pair_nb_weight = 0
    pair_nb_sim = 0.0
    exact_same = []
    divergent = []
    ratio_by_path = {}
    dir_stats = {}

    for rel in both:
        pub = published[rel]
        loc = local[rel]
        if pub.get("kind") != "text":
            continue
        if pub["sha"] == loc["sha"]:
            ratio = 1.0
            ratio_nb = 1.0
            exact_same.append(rel)
        else:
            ratio = line_ratio(pub["lines"], loc["lines"])
            ratio_nb = line_ratio(pub["lines_nb"], loc["lines_nb"])
            divergent.append({
                "path": rel,
                "similarity": ratio,
                "published_lines": pub["nlines"],
                "local_lines": loc["nlines"],
            })
        weight = max(pub["nlines"], loc["nlines"], 1)
        pair_weight += weight
        pair_sim += ratio * weight
        weight_nb = max(len(pub["lines_nb"]), len(loc["lines_nb"]), 1)
        pair_nb_weight += weight_nb
        pair_nb_sim += ratio_nb * weight_nb
        ratio_by_path[rel] = ratio
        bucket = dir_stats.setdefault(topdir(rel), {"files": 0, "exact": 0, "weight": 0, "sim": 0.0})
        bucket["files"] += 1
        bucket["weight"] += weight
        bucket["sim"] += ratio * weight
        if ratio == 1.0:
            bucket["exact"] += 1

    pub_lines = 0
    pub_matched = 0.0
    exact_pub_lines = 0
    for rel, info in published.items():
        if info.get("kind") != "text":
            continue
        pub_lines += info["nlines"]
        pub_matched += ratio_by_path.get(rel, 0.0) * info["nlines"]
        if info["sha"] in {item["sha"] for item in local.values()}:
            exact_pub_lines += info["nlines"]

    loc_lines = 0
    loc_matched = 0.0
    game_lines = 0
    game_matched = 0.0
    exact_loc_lines = 0
    pub_shas = {info["sha"] for info in published.values() if info.get("sha")}
    for rel, info in local.items():
        loc_lines += info["nlines"]
        matched = ratio_by_path.get(rel, 0.0) * info["nlines"]
        loc_matched += matched
        if not is_tooling(rel):
            game_lines += info["nlines"]
            game_matched += matched
        if info["sha"] in pub_shas:
            exact_loc_lines += info["nlines"]

    present = sum(1 for info in published.values() if info.get("kind") == "text")
    shared = (pub_matched + loc_matched) / 2.0
    dice = (2.0 * shared / (pub_lines + loc_lines)) if (pub_lines + loc_lines) else 0.0
    divergent.sort(key=lambda item: item["similarity"])
    dirs = []
    for name, bucket in dir_stats.items():
        dirs.append({
            "dir": name,
            "files": bucket["files"],
            "exact": bucket["exact"],
            "similarity": bucket["sim"] / bucket["weight"] if bucket["weight"] else 0.0,
            "weight_lines": bucket["weight"],
        })
    dirs.sort(key=lambda item: item["weight_lines"], reverse=True)
    return {
        "published_text_files": present,
        "published_lines": pub_lines,
        "local_files": len(local),
        "local_lines": loc_lines,
        "local_game_files": sum(1 for rel in local if not is_tooling(rel)),
        "local_game_lines": game_lines,
        "same_path": len(both),
        "exact_same_path": len(exact_same),
        "only_published": only_pub,
        "only_local": only_loc,
        "path_overlap_published": (len(both) / present) if present else 0.0,
        "path_overlap_local": (len(both) / len(local)) if local else 0.0,
        "path_jaccard": (len(both) / len(pub_paths | loc_paths)) if (pub_paths or loc_paths) else 0.0,
        "paired_weighted_similarity": (pair_sim / pair_weight) if pair_weight else 0.0,
        "paired_weighted_similarity_noblank": (pair_nb_sim / pair_nb_weight) if pair_nb_weight else 0.0,
        "coverage_published": (pub_matched / pub_lines) if pub_lines else 0.0,
        "coverage_local": (loc_matched / loc_lines) if loc_lines else 0.0,
        "coverage_local_excl_proc": (game_matched / game_lines) if game_lines else 0.0,
        "symmetric_dice": dice,
        "exact_line_pct_published": (exact_pub_lines / pub_lines) if pub_lines else 0.0,
        "exact_line_pct_local": (exact_loc_lines / loc_lines) if loc_lines else 0.0,
        "dirs": dirs,
        "most_divergent": divergent[:25],
    }


def pct(value):
    return f"{value * 100:.1f}%"


def render_text(report):
    lines = [
        f"published: {report['published_text_files']} lua / {report['published_lines']} lines",
        f"local: {report['local_files']} lua / {report['local_lines']} lines",
        f"same path: {report['same_path']}  exact: {report['exact_same_path']}",
        f"only published: {len(report['only_published'])}  only local: {len(report['only_local'])}",
        f"symmetric similarity: {pct(report['symmetric_dice'])}",
        f"published covered by local: {pct(report['coverage_published'])}",
        f"local covered by published: {pct(report['coverage_local'])}",
        f"paired-file similarity: {pct(report['paired_weighted_similarity'])}",
        f"exact line share: published {pct(report['exact_line_pct_published'])} / local {pct(report['exact_line_pct_local'])}",
        "",
        "dir similarity:",
    ]
    for item in report["dirs"]:
        lines.append(
            f"  {item['dir']}: files={item['files']} exact={item['exact']} "
            f"sim={pct(item['similarity'])} lines~{item['weight_lines']}"
        )
    lines.append("")
    lines.append("most divergent:")
    for item in report["most_divergent"][:15]:
        lines.append(
            f"  {pct(item['similarity']):>7}  pub={item['published_lines']:5d} "
            f"loc={item['local_lines']:5d}  {item['path']}"
        )
    return "\n".join(lines)


def main(argv):
    parser = argparse.ArgumentParser(description="Compare published Lua mirror with local scripts.")
    parser.add_argument("--game", required=True, help="Published game root, app dir, or manifest path")
    parser.add_argument("--scripts", required=True, help="Local scripts directory")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--out", help="Optional output path")
    args = parser.parse_args(argv)

    game = args.game
    manifest_path = game if os.path.isfile(game) else find_manifest(game)
    if not manifest_path:
        print(f"manifest not found under {game}", file=sys.stderr)
        return 2
    asset_dir = find_asset_dir(manifest_path)
    if not asset_dir:
        print(f"assets dir not found for {manifest_path}", file=sys.stderr)
        return 2
    if not os.path.isdir(args.scripts):
        print(f"scripts dir not found: {args.scripts}", file=sys.stderr)
        return 2

    manifest, published, missing, bytecode = collect_published(manifest_path, asset_dir)
    local = collect_local(args.scripts)
    report = compare(published, local)
    report.update({
        "manifest": manifest_path,
        "asset_dir": asset_dir,
        "scripts": os.path.abspath(args.scripts),
        "project_id": manifest.get("project_id"),
        "entry": manifest.get("entry"),
        "manifest_lua": sum(1 for item in (manifest.get("files") or []) if item.get("ext") == ".lua"),
        "missing": missing,
        "bytecode": bytecode,
    })
    text = json.dumps(report, ensure_ascii=False, indent=2) if args.format == "json" else render_text(report)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
            if not text.endswith("\n"):
                f.write("\n")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
