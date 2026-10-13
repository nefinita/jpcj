# ============================================================================
# data.jl — 数据加载（shuxing 技能表 / values 等级常数）
# 数据由外部提供（环境变量 JX3_DATA_DIR 指向含 shuxing/ 与 values/ 的目录）。
# ============================================================================

import TOML

"""读取某门派的技能表：返回 (Xinfa, Vector{Skill})。"""
function load_skill_table(dir::AbstractString, profession::AbstractString)
    path = joinpath(dir, "shuxing", "$(profession).toml")
    doc = TOML.parsefile(path)
    x = get(doc, "xinfa", Dict{String,Any}())
    xinfa = Xinfa(
        profession = String(profession),
        xinfa_name = String(get(x, "xinfa_name", "")),
        xinfa_nom  = String(get(x, "xinfa_nom", "")),
        atk_up     = Float32(get(x, "atk_up", 1.0)),
        pofang_up  = Float32(get(x, "pofang_up", 1.0)),
        huixin_up  = Float32(get(x, "huixin_up", 0.0)),
    )
    skills = Skill[]
    for sk in get(doc, "skill", [])
        push!(skills, Skill(
            skill_name              = String(get(sk, "skill_name", "")),
            skill_id                = UInt32(get(sk, "skill_id", 0)),
            sub_id                  = UInt32(get(sk, "sub_id", 0)),
            base_damage1            = UInt32(get(sk, "base_damage1", 0)),
            base_damage2            = UInt32(get(sk, "base_damage2", 0)),
            atk_xishu               = Float32(get(sk, "atk_xishu", 0.0)),
            watk_xishu              = UInt32(get(sk, "watk_xishu", 0)),
            hit_up                  = UInt32(get(sk, "hit_up", 0)),
            huixin_up               = UInt32(get(sk, "huixin_up", 0)),
            huixiao_up              = UInt32(get(sk, "huixiao_up", 0)),
            wushifangyu             = UInt32(get(sk, "wushifangyu", 0)),
            zhenshishanghai         = UInt32(get(sk, "zhenshishanghai", 0)),
            lost_hp_zhenshishanghai = Float32(get(sk, "lost_hp_zhenshishanghai", 0.0)),
            dot_flag                = UInt8(get(sk, "dot_flag", 0)),
            dot_interval            = Float32(get(sk, "dot_interval", 0.0)),
            dot_duration            = Float32(get(sk, "dot_duration", 0.0)),
            dot_up                  = Float32(get(sk, "dot_up", 0.0)),
            has_critical_strike     = Bool(get(sk, "has_critical_strike", false)),
        ))
    end
    return xinfa, skills
end

"""读取值集清单：返回 (默认 id, Dict{id=>file})。"""
function load_value_sets(dir::AbstractString)
    idx = TOML.parsefile(joinpath(dir, "values", "index.toml"))
    default = String(get(idx, "default", ""))
    sets = Dict{String,String}()
    for vs in get(idx, "value_sets", [])
        sets[String(vs["id"])] = String(vs["file"])
    end
    return default, sets
end

"""读取某值集的等级常数（8 系数）。"""
function load_coeff(dir::AbstractString, id::AbstractString)
    _, sets = load_value_sets(dir)
    doc = TOML.parsefile(joinpath(dir, "values", sets[String(id)]))
    Coeff(
        pofang_xishu          = Float32(doc["pofang_xishu"]),
        huixin_xishu          = Float32(doc["huixin_xishu"]),
        huixiao_xishu         = Float32(doc["huixiao_xishu"]),
        yujin_xishu           = Float32(doc["yujin_xishu"]),
        yuhui_xishu           = Float32(doc["yuhui_xishu"]),
        huajin_xishu          = Float32(doc["huajin_xishu"]),
        fangyu_xishu          = Float32(doc["fangyu_xishu"]),
        pvp_global_jianshang  = Float32(doc["pvp_global_jianshang"]),
    )
end
