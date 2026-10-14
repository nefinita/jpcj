# ============================================================================
# skill.jl — 单技能伤害（SPEC §4/§5）
# 前向实现统一在 forward.jl（`_forward`），此处仅做结果映射。
# ============================================================================

"""
单技能完整计算。返回 `DamageResult(y, b, i, n=G, h, q, dot_jumps)`。
（DTO 的 b=技能基础段, i=攻击段, n=普通命中；见 SPEC §4.6）
"""
function calc_skill(p::Player, h::Hostile, x::Xinfa, b::Buff, c::Coeff, s::Skill)::DamageResult
    f = _forward(p, h, x, b, c, s)
    DamageResult(f.y, f.i_skill, f.b_atk, f.g, f.h, f.q, f.jumps)
end
