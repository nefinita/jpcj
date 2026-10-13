#!/usr/bin/env python3
"""P2/P3 — 从 libjpcg_combo 导出连招 golden 向量（黑盒行为规格）。

连招的 steps 用「门派技能表索引」表示（不内嵌游戏数值在向量里）；
独立引擎测试时按索引从数据目录重建技能。

用法：
    python3 tools/export_combo_golden.py \
        --data  /path/to/jpcg/data \
        --lib   /path/to/jpcg/target/release/libjpcg_combo.so \
        --out   test/vectors/combo_golden.json
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:  # pragma: no cover
    print("需要 Python 3.11+（tomllib）", file=sys.stderr)
    raise SystemExit(2)

LIB_NAMES = {
    "darwin": "libjpcg_combo.dylib",
    "linux": "libjpcg_combo.so",
    "win32": "jpcg_combo.dll",
}

COEFFICIENT = {
    "pofang_xishu": 225957.6,
    "huixin_xishu": 197703.0,
    "huixiao_xishu": 72844.2,
    "yujin_xishu": 197703.0,
    "yuhui_xishu": 55123.2,
    "huajin_xishu": 30115.8,
    "fangyu_xishu": 126007.2,
    "pvp_global_jianshang": 0.9,
}

PLAYER = {
    "jcsx": "根骨",
    "jichu_shuxing": 21371,
    "jichu_gongji": 64329,
    "huixin_dengji": 61877,
    "huixin_xiaoguo": 2925,
    "pofang_dengji": 109160,
    "wuqi_shanghai": 0,
}

BASE_HOSTILE = {
    "waigong_fangyu": 15176,
    "neigong_fangyu": 21388,
    "yujin_dengji": 5047,
    "huajin_dengji": 59402,
    "jianshang_bili": 0,
}

# hp 情景：覆盖 满血 target_hp / max+current / 部分血量 / 无血量
HP_SCENARIOS = [
    {"name": "target_hp_full", "target_hp": 2_000_000, "max_hp": 0, "current_hp": 0},
    {"name": "max_current_full", "target_hp": 0, "max_hp": 2_000_000, "current_hp": 2_000_000},
    {"name": "max_current_partial", "target_hp": 0, "max_hp": 2_000_000, "current_hp": 1_500_000},
    {"name": "no_hp", "target_hp": 0, "max_hp": 0, "current_hp": 0},
    # 低血量：覆盖击杀率 (0,1) 区间，供 MC 统计校验
    {"name": "target_hp_low", "target_hp": 200_000, "max_hp": 0, "current_hp": 0},
    {"name": "max_current_low", "target_hp": 0, "max_hp": 200_000, "current_hp": 200_000},
]

MAX_STEPS = 10  # 每连招取前 N 个技能


def find_lib(arg: str | None) -> str:
    cands = [arg] if arg else []
    name = LIB_NAMES.get(sys.platform)
    if name:
        cands += [f"target/release/{name}", f"target/debug/{name}"]
    for c in cands:
        if c and os.path.isfile(c):
            return c
    raise SystemExit("找不到 libjpcg_combo，请传 --lib 或先 cargo build --release -p jpcg_combo")


class Combo:
    def __init__(self, path: str):
        self.lib = ctypes.CDLL(path)
        self.lib.jpcg_combo_handle_create.restype = ctypes.c_void_p
        self.lib.jpcg_combo_handle_create.argtypes = [ctypes.c_char_p]
        self.lib.jpcg_combo_handle_free.argtypes = [ctypes.c_void_p]
        self.lib.jpcg_combo_call.restype = ctypes.c_void_p
        self.lib.jpcg_combo_call.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        self.lib.jpcg_combo_last_error.restype = ctypes.c_void_p
        self.lib.jpcg_combo_free_string.argtypes = [ctypes.c_void_p]
        self.handle = self.lib.jpcg_combo_handle_create(b"{}")
        if not self.handle:
            raise SystemExit("jpcg_combo_handle_create 失败")

    def call(self, method: str, request: dict) -> dict:
        resp = self.lib.jpcg_combo_call(
            self.handle, method.encode(),
            json.dumps(request, ensure_ascii=False).encode(),
        )
        if not resp:
            err_ptr = self.lib.jpcg_combo_last_error()
            err = ctypes.string_at(err_ptr).decode() if err_ptr else "未知错误"
            if err_ptr:
                self.lib.jpcg_combo_free_string(err_ptr)
            raise RuntimeError(f"[{method}] {err}")
        text = ctypes.string_at(resp).decode()
        self.lib.jpcg_combo_free_string(resp)
        return json.loads(text)

    def close(self):
        if self.handle:
            self.lib.jpcg_combo_handle_free(self.handle)
            self.handle = None


def skill_dto(sk: dict) -> dict:
    """把 shuxing toml 的 [[skill]] 条目转成 SkillPoolItemDTO。"""
    return {
        "skill_name": sk.get("skill_name", ""),
        "skill_id": sk.get("skill_id", 0),
        "sub_id": sk.get("sub_id", 0),
        "base_damage1": sk.get("base_damage1", 0),
        "base_damage2": sk.get("base_damage2", 0),
        "atk_xishu": sk.get("atk_xishu", 0.0),
        "watk_xishu": sk.get("watk_xishu", 0),
        "hit_up": sk.get("hit_up", 0),
        "huixin_up": sk.get("huixin_up", 0),
        "huixiao_up": sk.get("huixiao_up", 0),
        "wushifangyu": sk.get("wushifangyu", 0),
        "wushihuajin": sk.get("wushihuajin", 0),
        "dot_flag": sk.get("dot_flag", 0),
        "dot_interval": sk.get("dot_interval", 0.0),
        "dot_duration": sk.get("dot_duration", 0.0),
        "dot_up": sk.get("dot_up", 0.0),
        "wushijianshang": sk.get("wushijianshang", 0),
        "zhenshishanghai": sk.get("zhenshishanghai", 0),
        "has_critical_strike": sk.get("has_critical_strike", False),
        "lost_hp_zhenshishanghai": sk.get("lost_hp_zhenshishanghai", 0.0),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--lib", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-steps", type=int, default=MAX_STEPS)
    args = ap.parse_args()

    data_dir = Path(args.data).resolve()
    os.environ["JPCG_DATA_DIR"] = str(data_dir)

    shuxing = sorted(p for p in (data_dir / "shuxing").glob("*.toml") if not p.name.startswith("_"))
    if not shuxing:
        raise SystemExit(f"未在 {data_dir}/shuxing 找到门派 toml")

    combo_lib = Combo(find_lib(args.lib))
    vectors = []
    try:
        for path in shuxing:
            with open(path, "rb") as f:
                doc = tomllib.load(f)
            x = doc.get("xinfa", {})
            xinfa = {
                "profession": path.stem,
                "xinfa_name": x.get("xinfa_name", path.stem),
                "xinfa_nom": x.get("xinfa_nom", "根骨"),
                "atk_up": float(x.get("atk_up", 1.0)),
                "pofang_up": float(x.get("pofang_up", 1.0)),
                "huixin_up": float(x.get("huixin_up", 0.0)),
            }
            skills = doc.get("skill", [])
            if not skills:
                continue
            idx = list(range(min(len(skills), args.max_steps)))
            steps_ref = [{"index": i, "skill_name": skills[i].get("skill_name", "")} for i in idx]
            steps_dto = [{"skill": skill_dto(skills[i]), "overrides": None} for i in idx]

            for sc in HP_SCENARIOS:
                hostile = {**BASE_HOSTILE, **{k: sc[k] for k in ("target_hp", "max_hp", "current_hp")}}
                request = {
                    "steps": steps_dto,
                    "player": PLAYER,
                    "hostile": hostile,
                    "xinfa": xinfa,
                    "buff": {
                        "base_atk_pct": 0.0, "huixin_pct": 0.0, "huixiao_pct": 0.0,
                        "pofang_pct": 0.0, "wushi_fangyu_pct": 0.0,
                        "shanghai_pct": 0.0, "mode_is_point": False,
                    },
                    "coefficient": COEFFICIENT,
                    "value_set": None,
                }
                result = combo_lib.call("calculate_combo", request)
                vectors.append({
                    "profession": path.stem,
                    "scenario": sc["name"],
                    "player": PLAYER,
                    "hostile": hostile,
                    "xinfa": xinfa,
                    "buff": request["buff"],
                    "coefficient": COEFFICIENT,
                    "steps": steps_ref,
                    "expected": result,
                })
            print(f"  {path.stem}: {len(idx)} 步 × {len(HP_SCENARIOS)} 情景")
    finally:
        combo_lib.close()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({
            "meta": {
                "source": "libjpcg_combo",
                "scenarios": [s["name"] for s in HP_SCENARIOS],
                "note": "steps 为门派技能表索引；期望输出由 jpcg 连招引擎产生。"
                        "kill_prob 为非确定性蒙特卡洛（默认 50k 无固定种子），仅作统计参照。",
            },
            "vectors": vectors,
        }, f, ensure_ascii=False, indent=1)
    print(f"==> 写入 {out}（{len(vectors)} 向量）")


if __name__ == "__main__":
    main()
