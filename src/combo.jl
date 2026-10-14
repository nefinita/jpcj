# ============================================================================
# combo.jl — 连招编排：期望通道 + 蒙特卡洛击杀率（SPEC §7）
# ============================================================================

import Random

"""单个连招步骤的结果。"""
struct ComboStepResult
    skill_name::String
    g_damage::UInt32
    h_damage::UInt32
    q_damage::UInt32
    crit_rate::Float32
    cumulative_mean::Float64
    cumulative_std::Float64
    kill_prob::Float64
    dot_jumps::Vector{UInt32}
    has_critical_strike::Bool
    zhenshishanghai::UInt32
    lost_hp_zhenshi_damage::Float64
end

struct ComboResult
    steps::Vector{ComboStepResult}
    total_expected_damage::Float64
    total_expected_damage_wan::Float64
    final_kill_prob::Float64
    kill_prob_curve::Vector{Tuple{Int,Float64}}
end

"""血量模型（当前 / 总）；无血量语义返回 `nothing`。"""
function hp_preset(h::Hostile)
    if h.max_hp > 0
        maxv = Float64(h.max_hp)
        cur = (h.current_hp > 0 && Float64(h.current_hp) <= maxv) ? Float64(h.current_hp) : maxv
        return (cur, maxv)
    elseif h.target_hp > 0
        t = Float64(h.target_hp)
        return (t, t)
    else
        return nothing
    end
end

"""追加真伤：max(0, max_hp - after) × coeff（f64）。"""
@inline function lost_hp_append(coeff::Float64, max_hp::UInt32, after::UInt32)::Float64
    coeff <= 0.0 && return 0.0
    lost = max(Float64(max_hp) - Float64(after), 0.0)
    lost * coeff
end

# MC 步模型：预构建
struct _StepModel
    g_damage::UInt32
    h_damage::UInt32
    q_damage::UInt32
    crit_rate::Float32
    has_critical_strike::Bool
    lost_coeff::Float64
    dot_jumps_g::Vector{UInt32}
    dot_jumps_h::Vector{UInt32}
end

"""
连招计算。`samples` 默认 50000。返回 `ComboResult`。
"""
function calculate_combo(skills::Vector{Skill}, p::Player, h::Hostile, x::Xinfa,
                         b::Buff, c::Coeff; samples::Int=50_000, seed=nothing)::ComboResult
    n_steps = length(skills)
    hp = hp_preset(h)

    steps = Vector{ComboStepResult}(undef, n_steps)
    models = Vector{_StepModel}(undef, n_steps)

    cum_mean = 0.0
    cum_var = 0.0
    ec_cur = hp === nothing ? nothing : hp[1]
    ec_max = hp === nothing ? nothing : hp[2]

    for (i, s) in enumerate(skills)
        fi = _forward(p, h, x, b, c, s)
        q = Float64(fi.q)
        lost = 0.0
        if hp !== nothing
            after = max(ec_cur - q, 0.0)
            lost = lost_hp_append(Float64(s.lost_hp_zhenshishanghai), UInt32(ec_max), to_u32(after))
            ec_cur = max(after - lost, 0.0)
        end
        crit = fi.crit

        g = Float64(fi.g)
        hh = Float64(fi.h)
        pr = Float64(crit)

        # 方差
        variance = if s.has_critical_strike
            0.0
        elseif s.dot_flag > 0
            j = fi.jumps
            if isempty(j)
                (hh - g)^2 * pr * (1.0 - pr)
            else
                base = Float64(j[1])
                acc = 0.0
                for jk in j
                    r = base > 0.0 ? Float64(jk) / base : 1.0
                    gk = g * r
                    hk = hh * r
                    acc += (hk - gk)^2 * pr * (1.0 - pr)
                end
                acc
            end
        else
            (hh - g)^2 * pr * (1.0 - pr)
        end

        # dot 逐跳 g/h
        djg = UInt32[]
        djh = UInt32[]
        if s.dot_flag > 0 && !isempty(fi.jumps)
            base = Float64(fi.jumps[1])
            for jk in fi.jumps
                r = base > 0.0 ? Float64(jk) / base : 1.0
                push!(djg, to_u32(g * r))
                push!(djh, to_u32(hh * r))
            end
        end

        cum_mean += q + lost
        cum_var += variance

        models[i] = _StepModel(fi.g, fi.h, fi.q, crit, s.has_critical_strike,
                               Float64(s.lost_hp_zhenshishanghai), djg, djh)
        steps[i] = ComboStepResult(s.skill_name, fi.g, fi.h, fi.q, crit,
                                   cum_mean, sqrt(cum_var), 0.0, fi.jumps,
                                   s.has_critical_strike, s.zhenshishanghai, lost)
    end

    # ---- 蒙特卡洛通道 ----
    if hp === nothing
        for i in 1:n_steps
            steps[i] = _with_kill(steps[i], 1.0)
        end
    else
        hp0, hp_max = hp
        n = max(samples, 1)
        rng = seed === nothing ? Random.MersenneTwister() : Random.MersenneTwister(seed)
        kills_at = zeros(Int, n_steps)
        for _ in 1:n
            cur = hp0
            for i in 1:n_steps
                m = models[i]
                dmg = if m.has_critical_strike
                    Float64(m.q_damage)
                elseif !isempty(m.dot_jumps_g)
                    ssum = 0.0
                    pcl = clamp(Float64(m.crit_rate), 0.0, 1.0)
                    for k in eachindex(m.dot_jumps_g)
                        ssum += rand(rng) < pcl ? Float64(m.dot_jumps_h[k]) : Float64(m.dot_jumps_g[k])
                    end
                    ssum
                else
                    pcl = clamp(Float64(m.crit_rate), 0.0, 1.0)
                    rand(rng) < pcl ? Float64(m.h_damage) : Float64(m.g_damage)
                end
                after = max(cur - dmg, 0.0)
                lost = m.lost_coeff > 0.0 ? lost_hp_append(m.lost_coeff, to_u32(hp_max), to_u32(after)) : 0.0
                cur = max(after - lost, 0.0)
                if cur <= 0.0
                    kills_at[i] += 1
                    break
                end
            end
        end
        acc = 0
        for i in 1:n_steps
            acc += kills_at[i]
            steps[i] = _with_kill(steps[i], acc / n)
        end
    end

    curve = Tuple{Int,Float64}[(i, round(steps[i].kill_prob * 10000.0) / 100.0) for i in 1:n_steps]
    ComboResult(steps, cum_mean, cum_mean / 10000.0,
                n_steps == 0 ? 0.0 : steps[end].kill_prob, curve)
end

@inline function _with_kill(s::ComboStepResult, kp::Float64)
    ComboStepResult(s.skill_name, s.g_damage, s.h_damage, s.q_damage, s.crit_rate,
                    s.cumulative_mean, s.cumulative_std, kp, s.dot_jumps,
                    s.has_critical_strike, s.zhenshishanghai, s.lost_hp_zhenshi_damage)
end
