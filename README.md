# jpcj

**JPCJ** —— 剑网3 PVP 计算器（**J**ulia 版）。JPCG 的 Julia 独立实现。

单技能伤害公式、连招期望通道与蒙特卡洛击杀率（50k 采样），用于「数值平衡实证」研究。

## 定位

- **独立实现**，不复制任何 GPL 源码。规格来源：JPCG（`libjpcg_core` / `libjpcg_combo`）的黑盒行为 + golden 向量。
- 引擎**不含游戏数值**；运行期由外部数据目录提供（环境变量 `JX3_DATA_DIR`）。
- 许可：**Apache-2.0**。

## 目录

```
src/            # Julia 引擎
docs/SPEC.md    # 行为规格（独立实现依据）
test/vectors/   # golden 向量（由 tools/export_golden.py 从 JPCG 引擎导出）
tools/          # 向量导出工具
```

## 使用

```julia
using jpcj

data_dir = ENV["JX3_DATA_DIR"]           # 含 shuxing/ 与 values/
xinfa, skills = load_skill_table(data_dir, "mowen")
coeff = load_coeff(data_dir, "live-130")

player  = Player(jichu_gongji = 64329, jichu_shuxing = 21371,
                 huixin_dengji = 61877, huixin_xiaoguo = 2925, pofang_dengji = 109160)
hostile = Hostile(waigong_fangyu = 15176, neigong_fangyu = 21388,
                  yujin_dengji = 5047, huajin_dengji = 59402)
buff    = Buff()

r = calc_skill(player, hostile, xinfa, buff, coeff, skills[1])
println((r.y, r.b, r.i, r.n, r.h, r.q))
```

## 测试

```sh
JX3_DATA_DIR=/path/to/data julia --project=. -e 'using Pkg; Pkg.test()'
```

未设置 `JX3_DATA_DIR` 时跳过 golden 回归，仅跑基础测试。

## Golden 向量

`test/vectors/golden.json` 由 `tools/export_golden.py` 生成：对「门派 × 参数情景」调用
`libjpcg_core` 的 `calculate` / `compute_derivatives`，记录「输入 → 期望输出」。

重新生成：

```sh
python3 tools/export_golden.py \
    --data  <jpcg>/data \
    --lib   <jpcg>/target/release/libjpcg_core.so \
    --out   test/vectors/golden.json
```

## 状态

- [x] P0 骨架 + golden 向量（108 向量 / 6820 技能结果）
- [x] P1 单技能公式 + 导数（golden 回归）
- [x] P2 连招期望通道（162 向量 / 1620 步）
- [x] P3 蒙特卡洛击杀率（统计等价，50k 采样）
- [ ] P7 时间轴（GCD/调息/吟唱）记时连招 —— 设计见 [`docs/TIMING.md`](docs/TIMING.md)，**待数据取证后实现**

## 免责声明

游戏数值权利归原权利人所有。本引擎仅用于研究与技术批评。
