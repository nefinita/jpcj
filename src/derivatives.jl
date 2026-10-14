# ============================================================================
# derivatives.jl — 6 属性偏导（SPEC §8）
#
# 由 ForwardDiff 对 forward.jl 的单一前向自动求导（前向模式）。
# 截断点用 `trunc_st`（straight-through），故复现 JPCG 的
# 「截断值 + 连续敏感度」混合导数语义；乘 dot 等比和因子与 JPCG 同口径。
# ============================================================================

"""单技能 6 属性偏导 ∂Q/∂attr。"""
function calc_derivatives(p::Player, h::Hostile, x::Xinfa, b::Buff, c::Coeff,
                          s::Skill)::DerivativeSet
    v0 = Float32[p.jichu_shuxing, p.jichu_gongji, p.huixin_dengji,
                 p.huixin_xiaoguo, p.pofang_dengji, p.wuqi_shanghai]
    g = ForwardDiff.gradient(
        z -> _core(z[1], z[2], z[3], z[4], z[5], z[6], h, x, b, c, s).q, v0)
    df = dot_factor(s)
    DerivativeSet(g[1] * df, g[2] * df, g[3] * df, g[4] * df, g[5] * df, g[6] * df)
end
