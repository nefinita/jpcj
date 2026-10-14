# ============================================================================
# forward.jl — 唯一可微前向（SPEC §4/§5）
#
# 单一前向实现，供三处复用：
#   - skill.jl::calc_skill        取伤害值
#   - derivatives.jl              经 ForwardDiff 自动求导（straight-through 截断）
#   - combo.jl                    取 g/h/q/crit/jumps
#
# 截断点使用 `trunc_st`：**前向取值截断、反向直通**（导数按 1 传），
# 以复现 JPCG 的「截断值 + 连续敏感度」混合导数语义（决策 Option 1）。
# ============================================================================

import ForwardDiff

"""straight-through 截断（值模式）：等价原 `trunc32`。"""
@inline trunc_st(x::Float32)::Float32 = Float32(to_u32(x))
@inline trunc_st(x::Float64)::Float64 = Float64(to_u32(x))

"""straight-through 截断（AD 模式）：值取截断，偏导直通。"""
@inline function trunc_st(x::ForwardDiff.Dual)
    v = ForwardDiff.value(x)
    x - v + Float32(to_u32(v))
end

"""
前向核心（对属性类型泛化）：返回各段中间量。
`js/jg/hd/hxg/pd/wq` 为 6 个玩家属性（Float32 或 Dual）。
"""
function _core(js, jg, hd, hxg, pd, wq, h::Hostile, x::Xinfa, b::Buff, c::Coeff, s::Skill)
    # ---- 面板 / 防御 ----
    ws = Float32(s.wushifangyu) + trunc_st(b.wushi_fangyu_pct * 1024f0 / 100f0)
    fy = is_neigong(x.xinfa_nom) ? h.neigong_fangyu : h.waigong_fangyu
    def = Float32(fy) * (1f0 - ws / 1024f0)
    fangyu = trunc_st(def * 1024f0 / (def + c.fangyu_xishu))

    b_pofang = trunc_st(pd * 1024f0 / c.pofang_xishu)
    b_huixin = hd / c.huixin_xishu
    b_huixiao = trunc_st(hxg * 1024f0 / c.huixiao_xishu)

    # ---- Y：破防系数段 ----
    pf = b_pofang + trunc_st(b.pofang_pct * 1024f0 / 100f0)
    Y = 1024f0 + pf - trunc_st((1024f0 + pf) * (fangyu / 1024f0))

    # ---- B：攻击段 ----
    B = trunc_st((jg + js * x.atk_up) * (1f0 + b.base_atk_pct / 100f0))

    # ---- I：技能基础伤害段 ----
    I = Float32(base_atk(s.base_damage1, s.base_damage2)) +
        trunc_st(B * s.atk_xishu) +
        trunc_st(wq * Float32(s.watk_xishu) / 100f0)

    # ---- G：破防/减伤后命中段 ----
    sh = 1f0 + b.shanghai_pct / 100f0
    hj = trunc_st((Float32(h.huajin_dengji) / (Float32(h.huajin_dengji) + c.huajin_xishu) +
                   102f0 / 1024f0) * 1024f0)
    g1 = trunc_st(I * (1f0 + Float32(s.hit_up) / 100f0) * sh * (Y / 1024f0))
    g2 = trunc_st(g1 * (1f0 - hj / 1024f0))
    G = trunc_st(g2 * c.pvp_global_jianshang * (1f0 - Float32(h.jianshang_bili) / 100f0))

    # ---- H：会心段 ----
    hx = b_huixiao
    yj_hx = trunc_st(Float32(h.yujin_dengji) * 1024f0 / c.yuhui_xishu)
    H = G + trunc_st(G * (0.75f0 + (hx + b.huixiao_pct * 1024f0 / 100f0) / 1024f0 +
                          Float32(s.huixiao_up) / 100f0) * (1f0 - yj_hx / 1024f0))

    # ---- Q：期望段 ----
    crit = max(0f0, b_huixin + b.huixin_pct / 100f0 - Float32(h.yujin_dengji) / c.yujin_xishu) +
           Float32(s.huixin_up) / 100f0
    Q = trunc_st(G * (1f0 - crit) + H * crit)

    dot_n = dot_jump_count(s.dot_interval, s.dot_duration)
    (Y = Y, b_atk = B, i_skill = I, g = G, h = H, crit = crit, q = Q, dot_n = dot_n)
end

"""Dot 等比和因子（SPEC §8）。"""
@inline function dot_factor(s::Skill)::Float32
    n = dot_jump_count(s.dot_interval, s.dot_duration)
    if n == UInt32(0)
        1f0
    elseif s.dot_up == 0f0
        Float32(n)
    else
        (powi(1f0 + s.dot_up, Int(n)) - 1f0) / s.dot_up
    end
end

"""值模式前向：返回整数化结果 + dot 每跳。"""
struct ForwardInfo
    y::UInt32
    b_atk::UInt32
    i_skill::UInt32
    g::UInt32
    h::UInt32
    crit::Float32
    q::UInt32
    jumps::Vector{UInt32}
    dot_n::UInt32
end

function _forward(p::Player, h::Hostile, x::Xinfa, b::Buff, c::Coeff, s::Skill)::ForwardInfo
    r = _core(Float32(p.jichu_shuxing), Float32(p.jichu_gongji), Float32(p.huixin_dengji),
              Float32(p.huixin_xiaoguo), Float32(p.pofang_dengji), Float32(p.wuqi_shanghai),
              h, x, b, c, s)
    n = r.dot_n
    jumps = UInt32[]
    if n > UInt32(0)
        up = s.dot_up
        for k in 0:(Int(n) - 1)
            factor = up > 0f0 ? powi(1f0 + up, k) : 1f0
            push!(jumps, to_u32(r.q * factor))
        end
    end
    qq = isempty(jumps) ? to_u32(r.q) : sum(jumps)
    ForwardInfo(to_u32(r.Y), to_u32(r.b_atk), to_u32(r.i_skill), to_u32(r.g), to_u32(r.h),
                Float32(r.crit), qq, jumps, n)
end
