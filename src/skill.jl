# ============================================================================
# skill.jl — 单技能伤害链 Y→B→I→G→H→Q + dot（SPEC §4/§5）
# ============================================================================

"""
单技能完整计算。返回 `DamageResult(y, b, i, n=G, h, q, dot_jumps)`。
"""
function calc_skill(p::Player, h::Hostile, x::Xinfa, b::Buff, c::Coeff, s::Skill)::DamageResult
    ws = wushifangyu_total(s, b)
    fy = is_neigong(x.xinfa_nom) ? h.neigong_fangyu : h.waigong_fangyu
    fangyu = guo_fangyu(fy, ws, c)

    # ---- Y：破防系数段（注意 1024+pofang 先做 UInt32 加法）----
    pf = b_pofang(p, c) + to_u32(b.pofang_pct * 1024f0 / 100f0)
    Y = N1024 + pf - to_u32(Float32(N1024 + pf) * (Float32(fangyu) / 1024f0))

    # ---- B：攻击段 ----
    B = to_u32((Float32(p.jichu_gongji) + Float32(p.jichu_shuxing) * x.atk_up) *
               (1f0 + b.base_atk_pct / 100f0))

    # ---- I：技能基础伤害段 ----
    I = base_atk(s.base_damage1, s.base_damage2) +
        to_u32(Float32(B) * s.atk_xishu) +
        to_u32(Float32(p.wuqi_shanghai) * Float32(s.watk_xishu) / 100f0)

    # ---- G：破防/减伤后命中段（两处 trunc32）----
    sh = 1f0 + b.shanghai_pct / 100f0
    hj = guo_huajin(h, c)
    g = trunc32(Float32(I) * (1f0 + Float32(s.hit_up) / 100f0) * sh * (Float32(Y) / 1024f0))
    g = trunc32(g * (1f0 - Float32(hj) / 1024f0))
    G = to_u32(g * c.pvp_global_jianshang * (1f0 - Float32(h.jianshang_bili) / 100f0))

    # ---- H：会心段 ----
    hx = b_huixiao(p, c)
    buff_hx = b.huixiao_pct * 1024f0 / 100f0
    yj_hx = guo_yujin_huixiao(h, c)
    H = G + to_u32(Float32(G) *
                   (0.75f0 + (Float32(hx) + buff_hx) / 1024f0 + Float32(s.huixiao_up) / 100f0) *
                   (1f0 - Float32(yj_hx) / 1024f0))

    # ---- Q：期望段 ----
    crit = guo_huixin(p, h, b, c) + Float32(s.huixin_up) / 100f0
    Q = to_u32(Float32(G) * (1f0 - crit) + Float32(H) * crit)

    # ---- Dot ----
    n = dot_jump_count(s.dot_interval, s.dot_duration)
    jumps = UInt32[]
    if n > UInt32(0)
        up = s.dot_up
        for k in 0:(Int(n) - 1)
            factor = up > 0f0 ? powi(1f0 + up, k) : 1f0
            push!(jumps, to_u32(Float32(Q) * factor))
        end
    end
    qq = isempty(jumps) ? Q : sum(jumps)

    # 输出映射：DTO 的 b=技能基础段(内部 I)，i=攻击段(内部 B)，n=G（SPEC §4.6）
    DamageResult(Y, I, B, G, H, qq, jumps)
end
