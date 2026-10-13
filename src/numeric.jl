# ============================================================================
# numeric.jl — 数值语义助手
#
# 复刻 Rust `f32 as u32` 的**饱和截断**语义：
#   - 向零取整（trunc）
#   - 负值 → 0
#   - 超过 u32 上限 → 饱和为 typemax
# Julia 的 `UInt32(3.7)` 会抛 InexactError，故必须显式处理。
# ============================================================================

"""复刻 Rust `v as u32`：饱和截断（负 → 0，上溢 → typemax）。"""
@inline function to_u32(v::Float32)::UInt32
    v <= 0f0 && return UInt32(0)
    # f32 无法精确表示 2^32-1；>= 2^32 视为饱和上界
    v >= 4294967296f0 && return typemax(UInt32)
    return UInt32(trunc(v))
end

"""`trunc(v) = Float32(UInt32(v))`（SPEC §0 的截断点专用）。"""
@inline trunc32(v::Float32)::Float32 = Float32(to_u32(v))

"""技能基础伤害 = (base_damage1 + base_damage2) ÷ 2（u32 整除）。"""
@inline base_atk(b1::UInt32, b2::UInt32)::UInt32 = (b1 + b2) ÷ UInt32(2)

"""`x^n`（二进制幂，对齐 LLVM `llvm.powi` / Rust `f32::powi`）。"""
@inline function powi(x::Float32, n::Integer)::Float32
    e = abs(Int(n))
    e == 0 && return 1f0
    result = 1f0
    base = x
    while e > 0
        if isodd(e)
            result *= base
        end
        e >>= 1
        e > 0 && (base *= base)
    end
    n < 0 ? 1f0 / result : result
end

"""Dot 总跳数（SPEC §5）；非 Dot 返回 0。四舍五入（half away from zero，对齐 Rust）。"""
@inline function dot_jump_count(dot_interval::Float32, dot_duration::Float32)::UInt32
    if dot_interval > 0f0 && dot_duration >= dot_interval
        to_u32(round(dot_duration / dot_interval, RoundNearestTiesAway))
    else
        UInt32(0)
    end
end
