using Test
using JSON3
using jpcj

# golden 回归：需要数据目录（含 shuxing/）指向与导出向量时相同的数据。
data_dir = get(ENV, "JX3_DATA_DIR", "")
vectors_path = joinpath(@__DIR__, "vectors", "golden.json")

attr_ids = (
    "jichu_shuxing"  => :d_jichu_shuxing,
    "jichu_gongji"   => :d_jichu_gongji,
    "huixin_dengji"  => :d_huixin_dengji,
    "huixin_xiaoguo" => :d_huixin_xiaoguo,
    "pofang_dengji"  => :d_pofang_dengji,
    "wuqi_shanghai"  => :d_wuqi_shanghai,
)

function parse_player(r)
    Player(
        jichu_shuxing  = UInt32(r.jichu_shuxing),
        jichu_gongji   = UInt32(r.jichu_gongji),
        huixin_dengji  = UInt32(r.huixin_dengji),
        huixin_xiaoguo = UInt32(r.huixin_xiaoguo),
        pofang_dengji  = UInt32(r.pofang_dengji),
        wuqi_shanghai  = UInt32(r.wuqi_shanghai),
    )
end

function parse_hostile(r)
    Hostile(
        waigong_fangyu = UInt32(r.waigong_fangyu),
        neigong_fangyu = UInt32(r.neigong_fangyu),
        yujin_dengji   = UInt32(r.yujin_dengji),
        huajin_dengji  = UInt32(r.huajin_dengji),
        jianshang_bili = UInt32(r.jianshang_bili),
        target_hp      = UInt32(get(r, :target_hp, 0)),
        max_hp         = UInt32(get(r, :max_hp, 0)),
        current_hp     = UInt32(get(r, :current_hp, 0)),
    )
end

function parse_buff(r)
    Buff(
        base_atk_pct     = Float32(r.base_atk_pct),
        huixin_pct       = Float32(r.huixin_pct),
        huixiao_pct      = Float32(r.huixiao_pct),
        pofang_pct       = Float32(r.pofang_pct),
        wushi_fangyu_pct = Float32(r.wushi_fangyu_pct),
        shanghai_pct     = Float32(r.shanghai_pct),
        mode_is_point    = Bool(r.mode_is_point),
    )
end

function parse_coeff(r)
    Coeff(
        pofang_xishu         = Float32(r.pofang_xishu),
        huixin_xishu         = Float32(r.huixin_xishu),
        huixiao_xishu        = Float32(r.huixiao_xishu),
        yujin_xishu          = Float32(r.yujin_xishu),
        yuhui_xishu          = Float32(r.yuhui_xishu),
        huajin_xishu         = Float32(r.huajin_xishu),
        fangyu_xishu         = Float32(r.fangyu_xishu),
        pvp_global_jianshang = Float32(r.pvp_global_jianshang),
    )
end

function parse_xinfa(r)
    Xinfa(
        profession = String(r.profession),
        xinfa_name = String(get(r, :xinfa_name, "")),
        xinfa_nom  = String(get(r, :xinfa_nom, "")),
        atk_up     = Float32(r.atk_up),
        pofang_up  = Float32(r.pofang_up),
        huixin_up  = Float32(r.huixin_up),
    )
end

if isempty(data_dir) || !isdir(data_dir)
    @info "JX3_DATA_DIR 未设置或不存在，跳过 golden 回归（仅跑基础测试）" data_dir
    @testset "jpcj 基础" begin
        @test to_u32(3.7f0) == UInt32(3)
        @test to_u32(-1f0) == UInt32(0)
        @test base_atk(UInt32(160), UInt32(200)) == UInt32(180)
    end
else
    doc = JSON3.read(read(vectors_path, String))
    vectors = doc.vectors

    @testset "golden 回归（$(length(vectors)) 向量）" begin
        n_skill_ok = 0
        n_skill_bad = 0
        n_deriv_bad = 0
        fails = String[]
        for v in vectors
            req = v.request
            p = parse_player(req.player)
            h = parse_hostile(req.hostile)
            b = parse_buff(req.buff)
            c = parse_coeff(req.coefficient)
            x_req = parse_xinfa(req.xinfa_config)
            profession = String(v.profession)

            # calculate：心法取自数据文件（SPEC §1.3）
            x, skills = load_skill_table(data_dir, profession)
            expected = v.calculate
            @test length(skills) == length(expected)
            for i in eachindex(skills)
                exp = expected[i]
                got = calc_skill(p, h, x, b, c, skills[i])
                ok = got.y == UInt32(exp.y) && got.b == UInt32(exp.b) && got.i == UInt32(exp.i) &&
                     got.n == UInt32(exp.n) && got.h == UInt32(exp.h) && got.q == UInt32(exp.q) &&
                     got.dot_jumps == UInt32.(collect(exp.dot_jumps))
                if ok
                    n_skill_ok += 1
                else
                    n_skill_bad += 1
                    if length(fails) < 20
                        push!(fails, "[$(profession)/$(v.scenario)] $(skills[i].skill_name): " *
                            "got(y=$(got.y),b=$(got.b),i=$(got.i),n=$(got.n),h=$(got.h),q=$(got.q)) " *
                            "exp(y=$(exp.y),b=$(exp.b),i=$(exp.i),n=$(exp.n),h=$(exp.h),q=$(exp.q))")
                    end
                end
            end

            # derivatives：使用请求心法（SPEC §1.3）
            exp_d = v.derivatives.derivatives
            for i in eachindex(skills)
                ds = calc_derivatives(p, h, x_req, b, c, skills[i])
                for (id, field) in attr_ids
                    entry = nothing
                    for e in exp_d
                        if String(e.attr_id) == id
                            entry = e
                            break
                        end
                    end
                    entry === nothing && continue
                    exp_val = Float32(entry.per_skill[i].derivative)
                    got_val = getfield(ds, field)
                    if !(abs(got_val - exp_val) < 1f-6)
                        n_deriv_bad += 1
                        if length(fails) < 40
                            push!(fails, "[$(profession)/$(v.scenario)] d_$(id) $(skills[i].skill_name): got $got_val exp $exp_val")
                        end
                    end
                end
            end
        end
        @info "技能段: ok=$n_skill_ok bad=$n_skill_bad; 导数不合规=$n_deriv_bad"
        for f in fails
            @error f
        end
        @test n_skill_bad == 0
        @test n_deriv_bad == 0
    end

    # ---- P2/P3 连招回归 ----
    combo_path = joinpath(@__DIR__, "vectors", "combo_golden.json")
    if isfile(combo_path)
        cdoc = JSON3.read(read(combo_path, String))
        cvecs = cdoc.vectors
        @testset "combo 回归（$(length(cvecs)) 向量）" begin
            n_exp_total = 0
            n_exp_bad = 0
            mc_fail = 0
            cfails = String[]
            for v in cvecs
                p = parse_player(v.player)
                h = parse_hostile(v.hostile)
                b = parse_buff(v.buff)
                c = parse_coeff(v.coefficient)
                x = parse_xinfa(v.xinfa)
                _, skills_all = load_skill_table(data_dir, String(v.profession))
                idxs = [Int(s.index) + 1 for s in v.steps]
                skills = skills_all[idxs]
                r = calculate_combo(skills, p, h, x, b, c; samples=50_000, seed=20261014)
                exp = v.expected
                for i in eachindex(skills)
                    e = exp.steps[i]
                    n_exp_total += 1
                    ok = r.steps[i].g_damage == UInt32(e.g_damage) &&
                         r.steps[i].h_damage == UInt32(e.h_damage) &&
                         r.steps[i].q_damage == UInt32(e.q_damage) &&
                         r.steps[i].dot_jumps == UInt32.(collect(e.dot_jumps)) &&
                         abs(r.steps[i].crit_rate - Float32(e.crit_rate)) < 1f-6 &&
                         abs(r.steps[i].cumulative_mean - Float64(e.cumulative_mean_wan) * 10000.0) < 1e-3 &&
                         abs(r.steps[i].lost_hp_zhenshi_damage - Float64(e.lost_hp_zhenshi_damage)) < 1e-6
                    if !ok
                        n_exp_bad += 1
                        if length(cfails) < 20
                            push!(cfails, "[$(v.profession)/$(v.scenario)] step $i: " *
                                "got(g=$(r.steps[i].g_damage),h=$(r.steps[i].h_damage),q=$(r.steps[i].q_damage)," *
                                "mean=$(r.steps[i].cumulative_mean),lost=$(r.steps[i].lost_hp_zhenshi_damage)) " *
                                "exp(g=$(e.g_damage),h=$(e.h_damage),q=$(e.q_damage)," *
                                "mean_wan=$(e.cumulative_mean_wan),lost=$(e.lost_hp_zhenshi_damage))")
                        end
                    end
                end
                if abs(r.final_kill_prob - Float64(exp.final_kill_prob)) > 0.02
                    mc_fail += 1
                    if length(cfails) < 40
                        push!(cfails, "[$(v.profession)/$(v.scenario)] kill_prob got $(r.final_kill_prob) exp $(exp.final_kill_prob)")
                    end
                end
            end
            @info "combo 期望: total=$n_exp_total bad=$n_exp_bad; MC 超差=$mc_fail"
            for f in cfails
                @error f
            end
            @test n_exp_bad == 0
            @test mc_fail == 0
        end
    end
end
