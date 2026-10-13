"""
    JX3Calc

JX3（剑网3）独立数值计算引擎 —— 单技能公式、连招期望与蒙特卡洛击杀率。

设计目标：
- **独立实现**：不复制任何 GPL 源码；以 `libjpcg_core` 的黑盒行为 + golden 向量为规格。
- **开箱可复现**：`Manifest.toml` 锁定依赖；golden 向量随仓提供。

当前状态：P0（骨架 + golden 向量）。P1 起逐步填充公式实现。
"""
module JX3Calc

# P1：单技能公式（base/atk/会心/破防/减伤/真伤/dot）
# P2：连招编排 + 期望通道（累计/方差 + 追加真伤）
# P3：蒙特卡洛击杀率（50k 采样）

end # module
