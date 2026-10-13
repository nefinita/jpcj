# ============================================================================
# panel.jl — 面板换算（SPEC §3）
# ============================================================================

const N1024 = UInt32(1024)

"""破防等级 → 破防系数（1024 制）。"""
@inline b_pofang(p::Player, c::Coeff)::UInt32 =
    to_u32(Float32(p.pofang_dengji * N1024) / c.pofang_xishu)

"""会心等级 → 会心率（f32 小数）。"""
@inline b_huixin(p::Player, c::Coeff)::Float32 =
    Float32(p.huixin_dengji) / c.huixin_xishu

"""会效等级 → 会效系数（1024 制）。"""
@inline b_huixiao(p::Player, c::Coeff)::UInt32 =
    to_u32(Float32(p.huixin_xiaoguo) * 1024f0 / c.huixiao_xishu)

"""内功判定：根骨/元气（含英文兼容）。"""
@inline is_neigong(nom::AbstractString)::Bool =
    nom in ("根骨", "元气", "gengu", "yuanqi")

"""防御系数（1024 制）：def = fangyu × (1 - ws/1024)；def×1024/(def+fangyu_xishu)。"""
@inline function guo_fangyu(fangyu::UInt32, ws::UInt32, c::Coeff)::UInt32
    def = Float32(fangyu) * (1f0 - Float32(ws) / 1024f0)
    to_u32(def * 1024f0 / (def + c.fangyu_xishu))
end

"""无视防御合计 = 技能 wushifangyu + buff 百分比（1024 制）。"""
@inline function wushifangyu_total(s::Skill, b::Buff)::UInt32
    s.wushifangyu + to_u32(b.wushi_fangyu_pct * 1024f0 / 100f0)
end

"""化劲减伤（1024 制）：(huajin/(huajin+huajin_xishu) + 102/1024) × 1024。"""
@inline function guo_huajin(h::Hostile, c::Coeff)::UInt32
    hj = Float32(h.huajin_dengji)
    to_u32((hj / (hj + c.huajin_xishu) + 102f0 / 1024f0) * 1024f0)
end

"""御劲 → 会心伤害减免（1024 制）。"""
@inline guo_yujin_huixiao(h::Hostile, c::Coeff)::UInt32 =
    to_u32(Float32(h.yujin_dengji) * 1024f0 / c.yuhui_xishu)

"""御劲 → 会心率减免（f32 小数）。"""
@inline guo_yujin_huixin(h::Hostile, c::Coeff)::Float32 =
    Float32(h.yujin_dengji) / c.yujin_xishu

"""会心率（含 buff，扣御劲，下限 0）——SPEC §4.0 的 crit_core。"""
@inline function guo_huixin(p::Player, h::Hostile, b::Buff, c::Coeff)::Float32
    player_crit = b_huixin(p, c) + b.huixin_pct / 100f0
    reduce = guo_yujin_huixin(h, c)
    player_crit >= reduce ? (player_crit - reduce) : 0f0
end
