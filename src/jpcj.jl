"""
    jpcj

JPCJ —— 剑网3 PVP 计算器（Julia 版）。独立数值计算引擎：单技能公式、连招期望与蒙特卡洛击杀率。

设计依据：`docs/SPEC.md`（`libjpcg_core` / `libjpcg_combo` 的可观测行为）。
**独立实现**，不复制任何 GPL 源码；Apache-2.0。

- P1 单技能：`calc_skill` / `calc_derivatives`（本文件已实现）
- P2/P3 连招 + 击杀率：`combo.jl`（待实现）
"""
module jpcj

include("numeric.jl")
include("types.jl")
include("panel.jl")
include("skill.jl")
include("derivatives.jl")
include("data.jl")

export Player, Hostile, Xinfa, Buff, Coeff, Skill, DamageResult, DerivativeSet
export calc_skill, calc_derivatives
export to_u32, trunc32, base_atk, dot_jump_count, is_neigong
export load_skill_table, load_value_sets, load_coeff

end # module jpcj
