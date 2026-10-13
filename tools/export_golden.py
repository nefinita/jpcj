#!/usr/bin/env python3
"""P0 — 从 libjpcg_core 导出 golden 向量（黑盒行为规格）。

思路：不修改 jpcg，也不复制其源码；直接经 FFI 调用 `calculate` / `compute_derivatives`，
对「门派 × 参数情景」做扫描，把「输入 → 期望输出」落成 JSON 向量，作为独立引擎
（julia）的回归夹具。

用法：
    python3 tools/export_golden.py \
        --data  /path/to/jpcg/data \
        --lib   /path/to/jpcg/target/release/libjpcg_core.so \
        --out   test/vectors/golden.json

依赖：Python 3.11+（tomllib）、libjpcg_core.so 已构建。
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
    "darwin": "libjpcg_core.dylib",
    "linux": "libjpcg_core.so",
    "win32": "jpcg_core.dll",
}

# 系数（来自 examples/python_demo/quick_calc_test.py 的预设，等级 130）
COEFFICIENT = {
    "pofang_xishu": 225957.6,
    "huixin_xishu": 197703.0,
    "huixiao_xishu": 72844.2,
    "huajin_xishu": 30115.8,
    "fangyu_xishu": 126007.2,
    "pvp_global_jianshang": 0.9,
}


def find_lib(arg: str | None) -> str:
    cands = [arg] if arg else []
    name = LIB_NAMES.get(sys.platform)
    if name:
        cands += [f"target/release/{name}", f"target/debug/{name}"]
    for c in cands:
        if c and os.path.isfile(c):
            return c
    raise SystemExit("找不到 libjpcg_core，请传 --lib 或先 cargo build --release -p jpcg_core")


class Core:
    def __init__(self, path: str):
        self.lib = ctypes.CDLL(path)
        self.lib.jpcg_handle_create.restype = ctypes.c_void_p
        self.lib.jpcg_handle_create.argtypes = [ctypes.c_char_p]
        self.lib.jpcg_handle_free.argtypes = [ctypes.c_void_p]
        self.lib.jpcg_call.restype = ctypes.c_void_p
        self.lib.jpcg_call.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        self.lib.jpcg_last_error.restype = ctypes.c_void_p
        self.lib.jpcg_free_string.argtypes = [ctypes.c_void_p]
        self.lib.jpcg_abi_version.restype = ctypes.c_uint32
        self.handle = self.lib.jpcg_handle_create(b"{}")
        if not self.handle:
            raise SystemExit("jpcg_handle_create 失败")

    def call(self, method: str, request: dict) -> dict:
        resp = self.lib.jpcg_call(
            self.handle,
            method.encode(),
            json.dumps(request, ensure_ascii=False).encode(),
        )
        if not resp:
            err_ptr = self.lib.jpcg_last_error()
            err = ctypes.string_at(err_ptr).decode() if err_ptr else "未知错误"
            if err_ptr:
                self.lib.jpcg_free_string(err_ptr)
            raise RuntimeError(f"[{method}] {err}")
        text = ctypes.string_at(resp).decode()
        self.lib.jpcg_free_string(resp)
        return json.loads(text)

    def close(self):
        if self.handle:
            self.lib.jpcg_handle_free(self.handle)
            self.handle = None


def read_xinfa(path: Path) -> dict:
    with open(path, "rb") as f:
        doc = tomllib.load(f)
    x = doc.get("xinfa", {})
    return {
        "profession": path.stem,
        "xinfa_name": x.get("xinfa_name", path.stem),
        "xinfa_nom": x.get("xinfa_nom", "根骨"),
        "atk_up": float(x.get("atk_up", 1.0)),
        "pofang_up": float(x.get("pofang_up", 1.0)),
        "huixin_up": float(x.get("huixin_up", 0.0)),
    }


# 参数情景：覆盖 会心/破防/武伤 与 有/无 buff、点/百分比、不同目标减伤
SCENARIOS = [
    {
        "name": "base",
        "player": {
            "jichu_shuxing": 21371, "jichu_gongji": 64329,
            "huixin_dengji": 61877, "huixin_xiaoguo": 2925,
            "pofang_dengji": 109160, "wuqi_shanghai": 0,
        },
        "hostile": {
            "waigong_fangyu": 15176, "neigong_fangyu": 21388,
            "yujin_dengji": 5047, "huajin_dengji": 59402,
            "jianshang_bili": 0, "target_hp": 0,
        },
        "buff": {
            "base_atk_pct": 0.0, "huixin_pct": 0.0, "huixiao_pct": 0.0,
            "pofang_pct": 0.0, "wushi_fangyu_pct": 0.0,
            "shanghai_pct": 0.0, "mode_is_point": False,
        },
    },
    {
        "name": "buff_full_point",
        "player": {
            "jichu_shuxing": 21371, "jichu_gongji": 64329,
            "huixin_dengji": 61877, "huixin_xiaoguo": 2925,
            "pofang_dengji": 109160, "wuqi_shanghai": 1500,
        },
        "hostile": {
            "waigong_fangyu": 15176, "neigong_fangyu": 21388,
            "yujin_dengji": 5047, "huajin_dengji": 59402,
            "jianshang_bili": 0, "target_hp": 2_000_000,
        },
        "buff": {
            "base_atk_pct": 10.0, "huixin_pct": 5.0, "huixiao_pct": 8.0,
            "pofang_pct": 3.0, "wushi_fangyu_pct": 6.0,
            "shanghai_pct": 6.0, "mode_is_point": True,
        },
    },
    {
        "name": "high_crit_high_pen",
        "player": {
            "jichu_shuxing": 35000, "jichu_gongji": 90000,
            "huixin_dengji": 90000, "huixin_xiaoguo": 5000,
            "pofang_dengji": 150000, "wuqi_shanghai": 3000,
        },
        "hostile": {
            "waigong_fangyu": 30000, "neigong_fangyu": 30000,
            "yujin_dengji": 12000, "huajin_dengji": 80000,
            "jianshang_bili": 20, "target_hp": 3_000_000,
        },
        "buff": {
            "base_atk_pct": 20.0, "huixin_pct": 12.0, "huixiao_pct": 15.0,
            "pofang_pct": 10.0, "wushi_fangyu_pct": 0.0,
            "shanghai_pct": 10.0, "mode_is_point": False,
        },
    },
    {
        "name": "low_stats",
        "player": {
            "jichu_shuxing": 8000, "jichu_gongji": 20000,
            "huixin_dengji": 10000, "huixin_xiaoguo": 1000,
            "pofang_dengji": 20000, "wuqi_shanghai": 0,
        },
        "hostile": {
            "waigong_fangyu": 5000, "neigong_fangyu": 5000,
            "yujin_dengji": 0, "huajin_dengji": 10000,
            "jianshang_bili": 0, "target_hp": 500_000,
        },
        "buff": {
            "base_atk_pct": 0.0, "huixin_pct": 0.0, "huixiao_pct": 0.0,
            "pofang_pct": 0.0, "wushi_fangyu_pct": 0.0,
            "shanghai_pct": 0.0, "mode_is_point": True,
        },
    },
]


def build_request(xinfa: dict, scenario: dict, jcsx: str) -> dict:
    return {
        "player": {"jcsx": jcsx, **scenario["player"]},
        "hostile": scenario["hostile"],
        "xinfa_config": xinfa,
        "buff": scenario["buff"],
        "coefficient": COEFFICIENT,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="jpcg data 目录（含 shuxing/）")
    ap.add_argument("--lib", required=True, help="libjpcg_core 路径")
    ap.add_argument("--out", required=True, help="输出 JSON 路径")
    ap.add_argument("--no-derivatives", action="store_true", help="跳过导数向量")
    args = ap.parse_args()

    data_dir = Path(args.data).resolve()
    os.environ["JPCG_DATA_DIR"] = str(data_dir)

    shuxing = sorted((data_dir / "shuxing").glob("*.toml"))
    shuxing = [p for p in shuxing if not p.name.startswith("_")]
    if not shuxing:
        raise SystemExit(f"未在 {data_dir}/shuxing 找到门派 toml")

    core = Core(find_lib(args.lib))
    vectors = []
    try:
        abi = core.lib.jpcg_abi_version()
        print(f"abi_version = {abi}, 门派 {len(shuxing)} 个, 情景 {len(SCENARIOS)} 个")
        for path in shuxing:
            xinfa = read_xinfa(path)
            for sc in SCENARIOS:
                req = build_request(xinfa, sc, xinfa["xinfa_nom"])
                results = core.call("calculate", req)
                entry = {
                    "profession": xinfa["profession"],
                    "scenario": sc["name"],
                    "request": req,
                    "calculate": results,
                }
                if not args.no_derivatives:
                    entry["derivatives"] = core.call("compute_derivatives", req)
                vectors.append(entry)
            print(f"  {xinfa['profession']} ({xinfa['xinfa_name']}): {len(SCENARIOS)} 情景")
    finally:
        core.close()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    doc = {
        "meta": {
            "source": "libjpcg_core",
            "abi_version": abi,
            "professions": [p.stem for p in shuxing],
            "scenarios": [s["name"] for s in SCENARIOS],
            "note": "期望输出由 jpcg 引擎产生；供独立引擎回归比对。",
        },
        "vectors": vectors,
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    total_skills = sum(len(v["calculate"]) for v in vectors)
    print(f"==> 写入 {out}")
    print(f"    向量条目 {len(vectors)}, 技能结果 {total_skills}")


if __name__ == "__main__":
    main()
