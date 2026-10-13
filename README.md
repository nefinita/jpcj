# jx3-calc.jl

JX3（剑网3）**独立数值计算引擎**（Julia）。

单技能伤害公式、连招期望通道与蒙特卡洛击杀率（50k 采样），用于「数值平衡实证」研究。

## 定位

- **独立实现**，不复制任何 GPL 源码。规格来源：`libjpcg_core` 的黑盒行为 + golden 向量。
- 引擎**不含游戏数值**；运行期由数据仓提供（见下）。
- 许可：**Apache-2.0**。

## 目录

```
src/            # Julia 引擎
test/vectors/   # golden 向量（由 tools/export_golden.py 从 jpcg 引擎导出）
tools/          # P0 向量导出工具
```

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
- [ ] P1 单技能公式
- [ ] P2 连招期望通道
- [ ] P3 蒙特卡洛击杀率

## 免责声明

游戏数值权利归原权利人所有。本引擎仅用于研究与技术批评。
