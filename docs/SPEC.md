# JX3 计算引擎规格（SPEC v0.1）

本规格描述 `libjpcg_core`（单技能）与 `libjpcg_combo`（连招/击杀率）的**可观测计算行为**，
作为 `jpcj` 独立实现的唯一依据。凡与 `test/vectors/golden.json` 冲突之处，**以向量为准**。

---

## 0. 约定

- **全程单精度 `f32`**。Julia 实现必须用 `Float32`，中间值**不得**升级到 `Float64`，
  否则截断点结果会漂移（本引擎的取整点是刻意复刻游戏行为的）。
- **`trunc(v) = Float32(UInt32(v))`**：浮点 → `UInt32` 的**饱和截断**（向零取整；Rust 语义下
  负值饱和为 `0`），再转回 `f32`。**仅**出现在 §5 指定的截断点。
- 最终输出为整数：`UInt32(v)`，同样饱和截断。
- **`1024` 制**：破防/防御/化劲/御劲等定标为"×1024"的系数。
- 整数除法：`base_atk() = (base_damage1 + base_damage2) ÷ 2` 为 **u32 整除**。

---

## 1. 输入模型

### 1.1 PlayerConfig

| 字段 | 含义 | 参与计算 |
|---|---|---|
| `jcsx` | 基础属性类型（字符串） | ❌ 仅展示 |
| `jichu_shuxing` | 基础属性点数 | ✅ |
| `jichu_gongji` | 基础攻击 | ✅ |
| `huixin_dengji` | 会心等级 | ✅ |
| `huixin_xiaoguo` | 会效等级 | ✅ |
| `pofang_dengji` | 破防等级 | ✅ |
| `wuqi_shanghai` | 武器伤害 | ✅ |

### 1.2 HostilepileConfig

`waigong_fangyu`、`neigong_fangyu`、`yujin_dengji`、`huajin_dengji`、
`jianshang_bili`（百分数）、`target_hp`、`max_hp`、`current_hp`。

### 1.3 XinfaConfig

`profession`（**决定加载哪个技能表文件**）、`xinfa_name`、`xinfa_nom`（**参与内外功判定**）、
`atk_up`、`pofang_up`、`huixin_up`。

> ⚠️ **重要**：`calculate`（单技能表）中，请求的 `xinfa_config.atk_up` 等**被忽略**——
> 引擎只用 `profession` 定位 `{profession}.toml`，实际心法参数取自该文件的 `[xinfa]` 段。
> 而 `compute_derivatives` **使用请求里的 `xinfa_config`**。两者行为不同，务必区分。

### 1.4 BuffConfig（均百分数）

`base_atk_pct`、`huixin_pct`、`huixiao_pct`、`pofang_pct`、`wushi_fangyu_pct`、`shanghai_pct`、
`mode_is_point`（**不参与计算**）。

### 1.5 CoefficientConfig（8 个）

`pofang_xishu`、`huixin_xishu`、`huixiao_xishu`、`yujin_xishu`、`yuhui_xishu`、
`huajin_xishu`、`fangyu_xishu`、`pvp_global_jianshang`（最后一个是乘法比例，**非** 1024 制）。

> 缺省回退：DTO 中某系数为 `0` 时回退到所选值集的等级常数；`pvp_global_jianshang` **不回退**。
> golden 向量已显式传全 8 个字段（`live-130`），故向量自包含、不依赖值集回退。

### 1.6 Skilltype（单技能）

`skill_name`、`skill_id`、`sub_id`、`base_damage1`、`base_damage2`、`atk_xishu(f32)`、
`watk_xishu(u32,%)`、`hit_up(%)`、`huixin_up(%)`、`huixiao_up(%)`、`wushifangyu(1024制)`、
`zhenshishanghai`、`lost_hp_zhenshishanghai(f32)`、`dot_flag`、`dot_interval(f32)`、
`dot_duration(f32)`、`dot_up(f32)`、`has_critical_strike(bool)`。
（`group`/`weapon_request`/`design_effect`/`kind_type`/`cast_mode`/`effect_type`/`jihuoqixue` 不参与计算。）

---

## 2. 等级常数与值集

`LevelConstant` = 上述 8 系数。当前两套值集（真源 `data/values/*.toml`）：

| 值集 | 等级 | pofang | huixin | huixiao | yujin | yuhui | huajin | fangyu | pvp |
|---|---|---|---|---|---|---|---|---|---|
| `live-130` | 130 | 225957.6 | 197703.0 | 72844.2 | 197703.0 | 55123.2 | 30115.8 | 126007.2 | 0.9 |
| `cszj-exp-260908` | 50 | 10378.17 | 9512.91 | 3504.60 | 19025.82 | 9422.82 | 5148.00 | 10802.88 | 0.9 |

---

## 3. 面板换算

**玩家侧**
```
B_pofang = UInt32(Float32(pofang_dengji * 1024) / pofang_xishu)          # 1024 制
B_huixin = Float32(huixin_dengji) / huixin_xishu                          # f32 小数
B_huixiao = UInt32(Float32(huixin_xiaoguo) * 1024 / huixiao_xishu)        # 1024 制
```

**目标侧**（`ws` = 无视防御合计，见 §5.0）
```
def_w = Float32(waigong_fangyu) * (1 - Float32(ws) / 1024)
防外 = UInt32(def_w * 1024 / (def_w + fangyu_xishu))
def_n = Float32(neigong_fangyu) * (1 - Float32(ws) / 1024)
防内 = UInt32(def_n * 1024 / (def_n + fangyu_xishu))
化劲 = UInt32((Float32(huajin_dengji) / (Float32(huajin_dengji) + huajin_xishu) + 102.0/1024.0) * 1024)
御劲会效减免 = UInt32(Float32(yujin_dengji) * 1024 / yuhui_xishu)         # 1024 制
御劲会心减免 = Float32(yujin_dengji) / yujin_xishu                        # f32 小数
```

**内外功判定**：`xinfa_nom ∈ {"根骨", "元气", "gengu", "yuanqi"}` → 内功（用 `防内`），否则外功（用 `防外`）。

---

## 4. 伤害链 Y → B → I → G → H → Q

### 4.0 公共量

```
ws       = skilltype.wushifangyu + UInt32(buff.wushi_fangyu_pct * 1024 / 100.0)   # 无视防御合计
atk      = UInt32( (Float32(jichu_gongji) + Float32(jichu_shuxing) * xinfa.atk_up)
                   * (1.0 + buff.base_atk_pct/100.0) )                            # 含心法+阵眼
crit_core = max(0.0, B_huixin + buff.huixin_pct/100.0 - 御劲会心减免)
crit     = crit_core + skilltype.huixin_up/100.0                                  # 仅 Q 段用，可为负→由 q 公式处理
sh       = 1.0 + buff.shanghai_pct/100.0
```

### 4.1 Y（破防系数段）
```
pofang = B_pofang + UInt32(buff.pofang_pct * 1024 / 100.0)
Y = 1024 + pofang - UInt32( Float32(1024 + pofang) * (Float32(防) / 1024.0) )
```
（**注意整数加法顺序**：先 `1024 + pofang`（u32），再转 f32。）

### 4.2 B（攻击段）
`B = atk`

### 4.3 I（技能基础伤害段）
```
I = base_atk()
  + UInt32(Float32(atk) * atk_xishu)
  + UInt32(Float32(wuqi_shanghai) * Float32(watk_xishu) / 100.0)
```

### 4.4 G（破防/减伤后命中段）
```
g = trunc( Float32(I) * (1.0 + hit_up/100.0) * sh * (Float32(Y)/1024.0) )
g = trunc( g * (1.0 - Float32(化劲)/1024.0) )
G = UInt32( g * pvp_global_jianshang * (1.0 - Float32(jianshang_bili)/100.0) )
```
（**两个 `trunc` 之后**才做最终 `UInt32` 转换。）

### 4.5 H（会心段）
```
buff_hx = buff.huixiao_pct * 1024.0 / 100.0
H = G + UInt32( Float32(G)
                * (0.75 + (Float32(B_huixiao) + buff_hx)/1024.0 + huixiao_up/100.0)
                * (1.0 - Float32(御劲会效减免)/1024.0) )
```

### 4.6 Q（期望段）
```
Q = UInt32( Float32(G) * (1.0 - crit) + Float32(H) * crit )
```

**单技能输出映射（注意 `b`/`i` 与字母含义相反）**：
```
y = Y
b = I      # 技能基础伤害段（内部 I）
i = B      # 攻击段（内部 B）
n = G      # 普通命中段
h = H
q = Q
```
（DTO 中 `n` = 普通命中，`b`/`i` 的名字与其字母含义相反——以本映射为准。）

> `zhenshishanghai`（固定真实伤害）与 `lost_hp_zhenshishanghai`（追加真伤系数）
> **不并入 Q**，作为独立字段透传（见 §6）。

---

## 5. Dot

```
n = (dot_interval > 0 && dot_duration >= dot_interval)
      ? UInt32(round(dot_duration / dot_interval))     # round = 四舍五入
      : 0
```
- `n == 0`（非 Dot）：`dot_jumps = []`，`q = Q`
- `n > 0`（Dot）：
  ```
  jumps[k] = UInt32( Float32(Q) * (1.0 + dot_up)^k ),  k = 0 .. n-1   # dot_up=0 时每跳相等
  q = Σ jumps
  ```

---

## 6. 真伤

### 6.1 固定真伤 `zhenshishanghai`
引擎**不并入**伤害链，仅在结果里透传该字段（客户端自行处理）。

### 6.2 追加真伤（`lost_hp_zhenshishanghai`）
```
lost_hp_append(max_hp, current_hp_after) =
    lost_hp_zhenshishanghai <= 0 ? 0
                                 : max(0, max_hp - current_hp_after) * lost_hp_zhenshishanghai   # f64
```
- 单技能面板无 hp 上下文 → 恒 `0`。
- 连招层（§7）在每步**结算后**传入剩余血量（语义 A）。

---

## 7. 连招（`jpcg_combo`）

### 7.0 hp 语义
```
max_hp > 0            → 总血量 = max_hp；初始 = (current_hp>0 && current_hp<=max_hp) ? current_hp : max_hp
否则 target_hp > 0     → 满血模型（总血 = 初始 = target_hp）
否则（都 0）           → 无血量推进、无真伤，击杀率恒 1.0
```

### 7.1 期望通道
按连招顺序：
```
damage = hp 存在 ? q_cal_with_hp(cur, max) : q_cal()
crit   = crit_core + skilltype.huixin_up/100.0
g,h,q  = f64(G), f64(H), f64(Q)
lost   = damage.lost_hp_zhenshi_damage
# 血量推进（实际扣血 = 期望伤害 + 追加真伤）
after  = max(cur - q, 0.0)
cur    = max(after - lost, 0.0)
cum_mean += q + lost
cum_var  += variance ; cum_std = sqrt(cum_var)
```
**方差**
```
无质(has_critical_strike) → 0
Dot                        → Σ_k (h_k - g_k)^2 · p · (1-p)，其中 r_k = j_k / j_0，
                             g_k = G·r_k，h_k = H·r_k（j_0=0 时 r_k=1）
普通                       → (H - G)^2 · p · (1-p)
其中 p = crit_rate
```

### 7.2 蒙特卡洛通道（击杀率）
- `hp` 不存在 → 每步 `kill_prob = 1.0`
- 否则 `n = max(samples, 1)`（默认 `samples = 50000`），RNG 用 `StdRng`（可固定 `seed`）
- 对每条路径（`cur = hp0`）：
  ```
  每步伤害 dmg =
      无质        → Q
      Dot         → Σ_k ( rng < p ? dot_jumps_h[k] : dot_jumps_g[k] )   # 逐跳独立判定
      普通        → rng < p ? H : G
  after = max(cur - dmg, 0)
  lost  = lost_coeff > 0 ? lost_hp_append(hp_max, after) : 0
  cur   = max(after - lost, 0)
  若 cur <= 0 → kills_at[i] += 1 并跳出本路径
  ```
  其中 `dot_jumps_g[k] = UInt32(G·r_k)`、`dot_jumps_h[k] = UInt32(H·r_k)`，`r_k = j_k/j_0`。
- 累计击杀率 `probs[i] = (Σ_{m≤i} kills_at[m]) / n`
- `p_of(crit) = clamp(crit, 0, 1)`

### 7.3 输出
```
final_kill_prob      = 末步 kill_prob
total_expected_damage = cum_mean
total_expected_damage_wan = cum_mean / 10000.0
kill_prob_curve[i]   = (i+1, round(kill_prob_i * 10000.0) / 100.0)     # 百分数，2 位小数
```

---

## 8. 导数（6 属性）

`q_cal_with_derivatives` 与 `q_cal` 完全等价的 Q，另算偏导（**连续近似，忽略截断**）。

公共因子：
```
dg_di2 = (1 + hit_up/100) * sh * (Y/1024) * (1 - 化劲/1024) * pvp * (1 - jianshang_bili/100)
h_factor   = 0.75 + (B_huixiao + buff_hx)/1024 + huixiao_up/100
yj_factor  = 1 - 御劲会效减免/1024
dh_dg  = 1 + h_factor * yj_factor
dq_dg  = (1 - crit) + crit * dh_dg
dq_dh  = crit
dq_di2 = dg_di2 * dq_dg
```

| 属性 | ∂Q/∂attr |
|---|---|
| `jichu_gongji` | `dq_di2 * atk_xishu * (1 + base_atk_pct/100)` |
| `jichu_shuxing` | `dq_di2 * atk_xishu * atk_up * (1 + base_atk_pct/100)` |
| `huixin_dengji` | `(H - G) / huixin_xishu` |
| `huixin_xiaoguo` | `dq_dh * G * yj_factor/1024 * (1024/huixiao_xishu)` |
| `pofang_dengji` | `dq_dg * dg_dy * (1 - 防/1024) * (1024/pofang_xishu)`，`dg_dy = I*(1+hit_up/100)*sh/1024 * (1-化劲/1024)*pvp*(1-jianshang_bili/100)` |
| `wuqi_shanghai` | `dq_di2 * watk_xishu/100` |

**Dot 缩放**：非 Dot = 1；`dot_up=0` = `n`；否则 `((1+dot_up)^n - 1)/dot_up`，乘以全部 6 个偏导。

**`compute_derivatives`（host）**：对该门派**全部技能**求和；按 `total_derivative` 降序；
输出 `crit_vs_pofang`（会心等级 vs 破防等级谁总导更大）与 `top3`。
注意：此路径使用请求 `xinfa_config` 的 `atk_up`（与 §1.3 差异）。

---

## 9. 校验

`test/vectors/golden.json`（由 `tools/export_golden.py` 生成）：
108 条向量 = 28 门派 × 4 情景；每条含 `request`（输入）、`calculate`（期望输出）、`derivatives`。

- 整数段（`y/b/i/n/h/q/dot_jumps`）：**必须精确相等**
- 导数：`|Δ| < 1e-6`

---

## 10. 已知问题 / 实现注意

1. **`calculate` 用心法来自数据文件**（§1.3），请求里的 `atk_up` 等不生效；`compute_derivatives` 反之。
   独立引擎必须复刻这一不确定行为。
2. **`trunc` 是浮点→整数的饱和截断**（负值→0），且只在 §4.4 两个点出现。
3. **`zhenshishanghai` 不参与 Q/连招伤害**，仅透传。
4. **Dot 的 `round` 为四舍五入**（非截断）。
5. 蒙特卡洛 RNG 为 Rust `StdRng`；独立引擎无法逐路径复现（除非移植同一 RNG），
   故击杀率只要求**统计等价**。

---

## 11. 溯源

- 规格依据：`jpcg` 仓 `crates/jpcg_core`（单技能）与 `crates/jpcg_combo`（连招）的可观测行为。
- 向量来源：`libjpcg_core`（`live-130` 全系数显式传入）。
- 本规格为**独立实现的行为描述**，不复制任何源码。
