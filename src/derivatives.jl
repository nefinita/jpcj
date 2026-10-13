# ============================================================================
# derivatives.jl — 6 属性偏导（SPEC §8，连续近似，不做任何截断）
# ============================================================================

"""
单技能 6 属性偏导 ∂Q/∂attr。与 `calc_skill` 共享正向各段，再走连续近似。
"""
function calc_derivatives(p::Player, h::Hostile, x::Xinfa, b::Buff, c::Coeff, s::Skill)::DerivativeSet
    # ---- 正向（整数段，与 calc_skill 同源）----
    ws = wushifangyu_total(s, b)
    fy = is_neigong(x.xinfa_nom) ? h.neigong_fangyu : h.waigong_fangyu
    fangyu = guo_fangyu(fy, ws, c)

    pf = b_pofang(p, c) + to_u32(b.pofang_pct * 1024f0 / 100f0)
    Y = N1024 + pf - to_u32(Float32(N1024 + pf) * (Float32(fangyu) / 1024f0))
    B = to_u32((Float32(p.jichu_gongji) + Float32(p.jichu_shuxing) * x.atk_up) *
               (1f0 + b.base_atk_pct / 100f0))
    I = base_atk(s.base_damage1, s.base_damage2) +
        to_u32(Float32(B) * s.atk_xishu) +
        to_u32(Float32(p.wuqi_shanghai) * Float32(s.watk_xishu) / 100f0)

    sh = 1f0 + b.shanghai_pct / 100f0
    hj = guo_huajin(h, c)
    g = trunc32(Float32(I) * (1f0 + Float32(s.hit_up) / 100f0) * sh * (Float32(Y) / 1024f0))
    g = trunc32(g * (1f0 - Float32(hj) / 1024f0))
    G = to_u32(g * c.pvp_global_jianshang * (1f0 - Float32(h.jianshang_bili) / 100f0))

    hx = b_huixiao(p, c)
    buff_hx = b.huixiao_pct * 1024f0 / 100f0
    yj_hx = guo_yujin_huixiao(h, c)
    H = G + to_u32(Float32(G) *
                   (0.75f0 + (Float32(hx) + buff_hx) / 1024f0 + Float32(s.huixiao_up) / 100f0) *
                   (1f0 - Float32(yj_hx) / 1024f0))
    crit = guo_huixin(p, h, b, c) + Float32(s.huixin_up) / 100f0
    dot_n = dot_jump_count(s.dot_interval, s.dot_duration)

    # ---- 连续中间量 ----
    i_hit = Float32(I)
    g_damage = Float32(G)
    h_damage = Float32(H)
    y_val = Float32(Y)
    hit_up = Float32(s.hit_up) / 100f0
    huajin_f = Float32(hj)
    pvp = c.pvp_global_jianshang
    jianshang = Float32(h.jianshang_bili) / 100f0
    huixiao_f = Float32(hx)
    yj_hx_f = Float32(yj_hx)
    buff_huixiao_f = b.huixiao_pct * 1024f0 / 100f0

    # ---- 公共导数因子 ----
    dg_di2 = (1f0 + hit_up) * sh * (y_val / 1024f0) * (1f0 - huajin_f / 1024f0) * pvp * (1f0 - jianshang)
    h_factor = 0.75f0 + (huixiao_f + buff_huixiao_f) / 1024f0 + Float32(s.huixiao_up) / 100f0
    yj_factor = 1f0 - yj_hx_f / 1024f0
    dh_dg = 1f0 + h_factor * yj_factor
    dq_dg = (1f0 - crit) + crit * dh_dg
    dq_dh = crit
    dq_di2 = dg_di2 * dq_dg

    # ---- 各属性偏导 ----
    db_d_jg = 1f0 + b.base_atk_pct / 100f0
    d_jichu_gongji = dq_di2 * s.atk_xishu * db_d_jg
    db_d_js = x.atk_up * db_d_jg
    d_jichu_shuxing = dq_di2 * s.atk_xishu * db_d_js
    d_huixin_dengji = (h_damage - g_damage) * (1f0 / c.huixin_xishu)
    dhuixiao_d_hx = 1024f0 / c.huixiao_xishu
    dh_dhuixiao = g_damage * yj_factor / 1024f0
    d_huixin_xiaoguo = dq_dh * dh_dhuixiao * dhuixiao_d_hx
    dpofang_d_pd = 1024f0 / c.pofang_xishu
    dy_dpofang = 1f0 - Float32(fangyu) / 1024f0
    dg_dy = i_hit * (1f0 + hit_up) * sh / 1024f0 * (1f0 - huajin_f / 1024f0) * pvp * (1f0 - jianshang)
    d_pofang_dengji = dq_dg * dg_dy * dy_dpofang * dpofang_d_pd
    di2_d_wq = Float32(s.watk_xishu) / 100f0
    d_wuqi_shanghai = dq_di2 * di2_d_wq

    # ---- Dot 等比和缩放 ----
    dot_factor = if dot_n == UInt32(0)
        1f0
    elseif s.dot_up == 0f0
        Float32(dot_n)
    else
        (powi(1f0 + s.dot_up, Int(dot_n)) - 1f0) / s.dot_up
    end

    DerivativeSet(
        d_jichu_shuxing * dot_factor,
        d_jichu_gongji * dot_factor,
        d_huixin_dengji * dot_factor,
        d_huixin_xiaoguo * dot_factor,
        d_pofang_dengji * dot_factor,
        d_wuqi_shanghai * dot_factor,
    )
end
