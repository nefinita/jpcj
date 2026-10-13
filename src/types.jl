# ============================================================================
# types.jl — 输入模型（SPEC §1）
# 全部使用 Float32 / UInt32，切勿升级到 Float64。
# ============================================================================

Base.@kwdef struct Player
    jichu_shuxing::UInt32 = 0
    jichu_gongji::UInt32 = 0
    huixin_dengji::UInt32 = 0
    huixin_xiaoguo::UInt32 = 0
    pofang_dengji::UInt32 = 0
    wuqi_shanghai::UInt32 = 0
end

Base.@kwdef struct Hostile
    waigong_fangyu::UInt32 = 0
    neigong_fangyu::UInt32 = 0
    yujin_dengji::UInt32 = 0
    huajin_dengji::UInt32 = 0
    jianshang_bili::UInt32 = 0
    target_hp::UInt32 = 0
    max_hp::UInt32 = 0
    current_hp::UInt32 = 0
end

Base.@kwdef struct Xinfa
    profession::String = ""
    xinfa_name::String = ""
    xinfa_nom::String = ""
    atk_up::Float32 = 0f0
    pofang_up::Float32 = 0f0
    huixin_up::Float32 = 0f0
end

Base.@kwdef struct Buff
    base_atk_pct::Float32 = 0f0
    huixin_pct::Float32 = 0f0
    huixiao_pct::Float32 = 0f0
    pofang_pct::Float32 = 0f0
    wushi_fangyu_pct::Float32 = 0f0
    shanghai_pct::Float32 = 0f0
    mode_is_point::Bool = false
end

Base.@kwdef struct Coeff
    pofang_xishu::Float32 = 0f0
    huixin_xishu::Float32 = 0f0
    huixiao_xishu::Float32 = 0f0
    yujin_xishu::Float32 = 0f0
    yuhui_xishu::Float32 = 0f0
    huajin_xishu::Float32 = 0f0
    fangyu_xishu::Float32 = 0f0
    pvp_global_jianshang::Float32 = 0f0
end

Base.@kwdef struct Skill
    skill_name::String = ""
    skill_id::UInt32 = 0
    sub_id::UInt32 = 0
    base_damage1::UInt32 = 0
    base_damage2::UInt32 = 0
    atk_xishu::Float32 = 0f0
    watk_xishu::UInt32 = 0
    hit_up::UInt32 = 0
    huixin_up::UInt32 = 0
    huixiao_up::UInt32 = 0
    wushifangyu::UInt32 = 0
    zhenshishanghai::UInt32 = 0
    lost_hp_zhenshishanghai::Float32 = 0f0
    dot_flag::UInt8 = 0x00
    dot_interval::Float32 = 0f0
    dot_duration::Float32 = 0f0
    dot_up::Float32 = 0f0
    has_critical_strike::Bool = false
end

"""单技能伤害结果（SPEC §4.6）。`n` 为普通命中段（内部 G）。"""
struct DamageResult
    y::UInt32
    b::UInt32
    i::UInt32
    n::UInt32
    h::UInt32
    q::UInt32
    dot_jumps::Vector{UInt32}
end

"""6 属性偏导（SPEC §8）。"""
Base.@kwdef struct DerivativeSet
    d_jichu_shuxing::Float32 = 0f0
    d_jichu_gongji::Float32 = 0f0
    d_huixin_dengji::Float32 = 0f0
    d_huixin_xiaoguo::Float32 = 0f0
    d_pofang_dengji::Float32 = 0f0
    d_wuqi_shanghai::Float32 = 0f0
end
