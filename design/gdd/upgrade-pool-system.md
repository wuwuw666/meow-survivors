# 升级池系统 (Upgrade Pool System)

> **Status**: Approved
> **Author**: [user + agents]
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 成长的爽感 + 策略有深度

---

## Overview

升级池系统是一个纯数据驱动的候选库系统，负责定义“一局 run 里有哪些升级可能出现、何时可以出现、哪些升级彼此联动、哪些升级不能重复或不能同时出现”。它本身不负责弹出选择面板，而是向升级选择系统提供一组经过过滤和加权后的候选升级。

这个系统存在的意义，是把“每次升级都明显变强”和“每局 build 走向不同”同时成立。没有升级池系统，升级选择会变成随机发牌，要么很快出现最优解，要么给一堆无效选项，既破坏成长爽感，也破坏策略深度。升级池系统的职责，就是保证每次给到玩家的 3-4 个选项都“值得思考”，同时维持 build 的主题感、成长节奏和可重玩性。

**核心接口**:
- `get_upgrade_candidates(run_state: Dictionary, request_count: int) -> Array[UpgradeOption]`
- `mark_upgrade_taken(upgrade_id: String, run_state: Dictionary) -> void`
- `get_upgrade_definition(upgrade_id: String) -> UpgradeDefinition`

---

## Player Fantasy

升级池系统服务的是“每次拿升级都能立刻感到变强”的正反馈，以及“这局我要往哪个方向构筑”的主动决策感。玩家不应该把升级看成普通数值菜单，而应该把它感受到为“猫咪战斗风格逐步成型”的过程。

**情感目标**:
- 每次升级都要有明确价值，而不是为了凑数点一个无感选项。
- 玩家要能逐渐识别 build 方向，比如“普攻流”、“塔流”、“生存流”、“混合协同流”。
- 强 synergy 需要被鼓励，但不能快到 2-3 次升级就固定成唯一最优解。

**玩家应该感受到**:
- “这次选完，下波我马上能感觉到强。”
- “我是在主动构筑，而不是被随机数牵着走。”
- “哪怕这次没刷到最想要的，也还有合理备选。”

**玩家不应该感受到**:
- 连续两三次给出完全无关、无用的升级。
- 同一套最优组合每局都稳定刷出来。
- 选项描述看起来强，实际拿到后感知很弱。

---

## Detailed Design

### Core Rules

#### 1. 升级池组成

MVP 的升级池按功能分为 4 大类：

| 类别 | 作用 | 目标体验 |
|------|------|----------|
| **Hero Offense** | 强化主角自动攻击 | 让玩家直接感到输出提升 |
| **Tower Power** | 强化塔的输出、控制或部署效率 | 让塔位决策更有意义 |
| **Survival** | 提供生命、防护、回复、容错 | 让玩家在高压波次保持生存空间 |
| **Hybrid / Synergy** | 连接英雄与塔，或强化已有方向 | 让 build 有组合感而不是堆数值 |

MVP 建议总升级数量为 `10-14` 个定义项，其中：
- 4 个英雄进攻类
- 3 个塔类
- 3 个生存类
- 2-4 个联动类

#### 2. 升级稀有度

每个升级定义一个稀有度，用于控制出现概率和强度。

| 稀有度 | 说明 | 设计原则 |
|--------|------|----------|
| **Common** | 常见基础强化 | 早期高频出现，保证稳健成长 |
| **Rare** | 明显改变 build 走向 | 中期开始更常见 |
| **Epic** | 强 synergy 或高影响升级 | 需要前置条件或波次门槛 |

MVP 不建议上来就做过多稀有度层级，避免调参复杂化。

#### 3. 候选生成规则

每次升级请求时，升级池系统按以下顺序生成候选：

1. 从所有升级定义中筛出“当前 run 状态下可出现”的升级。
2. 去掉已经达到最大层数的升级。
3. 去掉与当前已拿升级冲突的升级。
4. 对剩余升级按权重抽取，优先保证类别分布不过于单一。
5. 生成 `3` 个默认候选；若后续设计允许，可在特殊奖励下生成第 `4` 个候选。

#### 4. 重复与层级规则

升级按重复方式分为三类：

| 类型 | 规则 | 示例 |
|------|------|------|
| **Single Pick** | 一局内只能拿一次 | 解锁分裂弹、塔攻击溅射 |
| **Stackable** | 可重复拿多次，直到层数上限 | +攻击、+攻速、+最大生命 |
| **Branch Upgrade** | 需要先拿前置升级 | 塔暴击强化需要已有塔攻击强化 |

#### 5. 保底规则

为了避免随机质量过低，系统加入软保底：

- 如果本次候选中没有任何与玩家当前 build 方向匹配的升级，则至少替换 1 个候选为匹配项。
- 如果玩家连续 `2` 次没有看到某个核心类别的可用升级，则提高该类别下一次出现权重。
- 前 `3` 次升级中至少出现 `1` 个英雄输出类和 `1` 个生存或塔类选项，避免开局卡死方向。

#### 6. Build 方向标签

每个升级定义可拥有一个或多个标签：

| 标签 | 含义 |
|------|------|
| `hero_attack` | 偏主角普攻成长 |
| `hero_speed` | 偏攻击频率/投射节奏 |
| `tower_damage` | 偏塔输出 |
| `tower_control` | 偏塔控制/范围 |
| `survival` | 偏容错 |
| `hybrid` | 强化英雄与塔的联动 |

升级池系统会记录玩家已选升级标签分布，用于判断“当前 build 倾向”。

### States and Transitions

升级池系统本身也是无状态数据系统，但在 run 中会被升级选择系统反复调用。可视为以下运行状态：

| 状态 | 描述 | 触发条件 | 输出 |
|------|------|----------|------|
| **Ready** | 本局开始后，可供查询 | run_start | 等待请求候选 |
| **Offering** | 正在生成一组候选 | level_up_request | 返回候选列表 |
| **Updated** | 玩家已选择升级，池内状态已更新 | upgrade_taken | 更新 run_state 和记忆 |
| **Exhausted** | 某一方向可用升级耗尽 | 某类或某定义达到上限 | 回退到其他可用项 |

**状态切换规则**:

| 当前状态 | 触发事件 | 目标状态 |
|----------|----------|----------|
| Ready | level_up_request | Offering |
| Offering | candidate_list_returned | Ready |
| Ready | upgrade_taken | Updated |
| Updated | state_refresh_complete | Ready |

### Interactions with Other Systems

| 系统 | 交互方向 | 数据接口 | 说明 |
|------|----------|----------|------|
| **升级选择系统** | 升级池 -> 升级选择 | `get_upgrade_candidates()` | 升级选择系统是主消费者，负责展示并让玩家选择 |
| **经验系统** | 经验 -> 升级选择 -> 升级池 | `level_up_request` | 经验系统触发升级机会，但不参与候选内容 |
| **自动攻击系统** | 升级池 -> 自动攻击 | `upgrade_effects` | 部分升级直接修改主角攻击参数 |
| **防御塔系统** | 升级池 -> 防御塔 | `upgrade_effects` | 部分升级强化塔的伤害、范围或行为 |
| **生命值系统** | 升级池 -> 生命值 | `upgrade_effects` | 生存类升级修改生命、防护或回复 |
| **UI系统** | 升级池 -> UI | `title`, `description`, `rarity`, `icon_id` | 用于升级卡片展示 |

**UpgradeDefinition 建议结构**:

```gdscript
class_name UpgradeDefinition

var upgrade_id: String
var display_name: String
var description: String
var category: String
var rarity: String
var tags: Array[String]
var max_stacks: int
var current_weight: float
var min_wave: int
var prerequisites: Array[String]
var excludes: Array[String]
var effects: Dictionary
```

---

## Formulas

### 1. 变量定义

| 变量 | 含义 | 默认值 / 范围 |
|------|------|----------------|
| `W_base` | 升级基础权重 | `1.0` |
| `RarityMult` | 稀有度权重倍率 | Common `1.0`, Rare `0.65`, Epic `0.35` |
| `TagMatchBonus` | 与当前 build 标签匹配时的额外倍率 | `+0.35` |
| `MissingCategoryBonus` | 当前 run 缺少某类别时的补偿倍率 | `+0.50` |
| `RepeatPenalty` | 已经出现过但未选择时的衰减倍率 | `-0.25` |
| `StackPenalty` | 已拿该升级若仍可叠层时的递减倍率 | 每层 `-0.15` |
| `WaveGateBonus` | 达到波次门槛后的稀有项放宽倍率 | `+0.20` |

### 2. 基础候选权重公式

```text
final_weight = W_base
             * RarityMult
             * (1 + TagMatchBonus_if_applicable)
             * (1 + MissingCategoryBonus_if_applicable)
             * (1 - RepeatPenalty_if_recently_offered)
             * (1 - StackPenalty * current_stack_count)
```

说明：
- 若某项不适用，对应倍率视为 `1.0`。
- 若升级被前置条件锁定或已到最大层数，则直接权重为 `0`。

### 3. 标签匹配计算

系统根据已选升级统计 build 倾向标签：

```text
tag_score(tag) = count_of_taken_upgrades_with_tag(tag)
primary_build_tag = tag with highest score
```

若候选升级包含当前 `primary_build_tag`，则：

```text
tag_match_multiplier = 1 + TagMatchBonus
```

若候选升级同时拥有 `hybrid` 标签且与主标签相关，再额外给 `+0.10`。

### 4. 类别保底修正

如果当前 run 的已选升级中，某一大类数量明显偏低：

```text
if category_count(category) == 0 after level >= 2:
    category_multiplier = 1 + MissingCategoryBonus
else:
    category_multiplier = 1.0
```

目标不是强行平均分布，而是防止某一局完全刷不到塔类或生存类。

### 5. 叠层成长公式

对于可叠层升级，效果建议使用线性成长，避免早期读不懂：

```text
effect_value(stack) = base_value + per_stack_gain * (stack - 1)
```

示例：
- `Sharp Fishbones`：基础 `+20%` 主角伤害，每次重复 `+15%`
- 第 1 层：`+20%`
- 第 2 层：`+35%`
- 第 3 层：`+50%`

### 6. 候选数量规则

```text
candidate_count = 3
if milestone_reward == true:
    candidate_count = 4
```

默认所有普通升级给 `3` 选 `1`，里程碑奖励或特殊机制可给 `4` 选 `1`。

### 7. 示例权重计算

假设某 Rare 升级：
- 稀有度 Rare，`RarityMult = 0.65`
- 匹配当前主 build 标签，`TagMatchBonus = +0.35`
- 当前该类别尚未出现，`MissingCategoryBonus = +0.50`
- 本局尚未拿过，也未最近出现

则：

```text
final_weight = 1.0 * 0.65 * 1.35 * 1.50 = 1.31625
```

说明：虽然 Rare 基础更难出，但当它恰好补足玩家 build 时，仍然会被明显抬高。

### 8. MVP 示例升级表

| ID | 名称 | 类别 | 稀有度 | 层数 | 主要效果 |
|----|------|------|--------|------|----------|
| U01 | 锋利小鱼干 | Hero Offense | Common | 3 | 提高主角伤害 |
| U02 | 疯狂连抓 | Hero Offense | Common | 3 | 提高主角攻速 |
| U03 | 分裂猫爪 | Hero Offense | Rare | 1 | 普攻额外分裂一次 |
| U04 | 锁定猎手 | Hero Offense | Rare | 1 | 提高对最近目标的单体输出 |
| U05 | 猫塔火力校准 | Tower Power | Common | 3 | 提高塔伤害 |
| U06 | 粘人猫薄荷 | Tower Power | Rare | 2 | 塔攻击附加减速/控制 |
| U07 | 扩建猫窝 | Tower Power | Rare | 1 | 降低部署成本或提高塔位效率 |
| U08 | 九条命 | Survival | Common | 2 | 提高最大生命 |
| U09 | 柔软肉垫 | Survival | Common | 2 | 降低所受伤害或提高闪避容错 |
| U10 | 呼噜恢复 | Survival | Rare | 1 | 波间回复或击杀恢复 |
| U11 | 主塔共鸣 | Hybrid | Epic | 1 | 主角攻击命中后强化塔输出 |
| U12 | 猫咪战术联动 | Hybrid | Epic | 1 | 已部署塔越多，主角或塔获得额外加成 |

---

## Edge Cases

| 边界情况 | 处理方式 |
|----------|----------|
| 当前可用升级不足 3 个 | 返回所有可用项，并允许升级选择系统显示少于 3 个候选 |
| 玩家已将大量 Common 升级叠满 | 自动提升 Rare/Epic 可见率，避免后期卡住 |
| 一个升级定义缺失描述或效果数据 | 禁止进入候选池，并记录为数据错误 |
| 前置升级未拿到，但高阶升级被强行抽中 | 权重视为 0，不可出现 |
| 同一升级连续两次都出现在候选里 | 第二次出现时应用 `RepeatPenalty`，降低刷屏感 |
| 玩家 build 极度偏科，只拿输出不拿生存 | 系统可以提高生存类权重，但不能强制替换所有输出选项 |
| 某个 Epic 升级太强，几乎拿到就赢 | 优先下调权重和提高前置条件，其次削弱数值 |
| 某类别长期无人选择 | 视为该类别设计价值不足，需要调整描述、体感或强度，而不是只加权重 |
| 升级效果与已有系统未对接 | 升级定义不能进入 Approved 状态，必须先明确 effect 接口 |

---

## Dependencies

### 上游依赖

升级池系统是 Progression 层的基础数据系统，原则上不依赖运行时战斗系统，但需要以下输入：

| 依赖项 | 类型 | 用途 |
|--------|------|------|
| **游戏概念文档** | 设计依赖 | 决定 build 多样性和成长爽感目标 |
| **难度曲线系统** | 软依赖 | 决定稀有项何时可以进入候选池 |
| **自动攻击 / 防御塔 / 生命值系统的属性接口** | 硬依赖 | 升级效果必须能落到具体参数上 |

### 下游依赖

| 系统 | 依赖类型 | 数据接口 | 说明 |
|------|----------|----------|------|
| **升级选择系统** | 硬依赖 | `get_upgrade_candidates()` | 没有升级池，升级选择系统无法给出合理选项 |
| **自动攻击系统** | 硬依赖 | `effects.hero_attack_*` | 消费英雄进攻类升级 |
| **防御塔系统** | 硬依赖 | `effects.tower_*` | 消费塔类升级 |
| **生命值系统** | 硬依赖 | `effects.hp_*`, `effects.defense_*` | 消费生存类升级 |
| **UI系统** | 软依赖 | `display_name`, `description`, `rarity`, `icon_id` | 展示升级卡片内容 |

### 接口定义

```gdscript
class_name UpgradePoolSystem

func get_upgrade_candidates(run_state: Dictionary, request_count: int = 3) -> Array[UpgradeDefinition]
func mark_upgrade_taken(upgrade_id: String, run_state: Dictionary) -> void
func get_upgrade_definition(upgrade_id: String) -> UpgradeDefinition
```

---

## Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响 |
|--------|------|--------|----------|------|
| `common_weight` | float | 1.0 | 0.8-1.2 | Common 出现频率 |
| `rare_weight` | float | 0.65 | 0.45-0.80 | Rare 出现频率 |
| `epic_weight` | float | 0.35 | 0.20-0.50 | Epic 出现频率 |
| `tag_match_bonus` | float | 0.35 | 0.15-0.50 | build 成型速度 |
| `missing_category_bonus` | float | 0.50 | 0.20-0.70 | 防卡类别效果 |
| `repeat_penalty` | float | 0.25 | 0.10-0.40 | 减少重复刷脸 |
| `stack_penalty` | float | 0.15 | 0.05-0.25 | 控制同一升级反复出现 |
| `candidate_count` | int | 3 | 3-4 | 决策密度 |
| `early_game_common_bias` | float | 0.30 | 0.10-0.50 | 前期稳定成长感 |
| `milestone_extra_choice` | bool | true | true/false | 里程碑波是否多给一个选项 |

**调参原则**:
- 如果玩家反馈“前期升级没什么爽感”，优先提高 Common 强度，而不是只提高 Rare 出现率。
- 如果玩家反馈“build 很难成型”，优先略增 `tag_match_bonus`。
- 如果玩家反馈“每局都差不多”，优先下调 `tag_match_bonus` 或提高分支升级前置。
- 如果玩家反馈“经常被迫点垃圾升级”，优先提高 `missing_category_bonus` 和基础候选质量。

**极端值说明**:
- `tag_match_bonus > 0.50` 容易让 build 过早锁死。
- `epic_weight > 0.50` 会稀释 Common 的稳健成长感。
- `candidate_count = 4` 全程启用会提升决策疲劳，不适合 MVP 默认配置。

---

## Visual/Audio Requirements

- 升级卡片视觉上要足够可爱、明确、易比较，不能像硬核 RPG 表格。
- 稀有度建议通过边框颜色、卡片光效和小图标区别，而不是只靠文字。
- 选中升级时需要有明确“这次真的变强了”的反馈，建议包含一段轻快的确认音效和数值/图标强化提示。

---

## UI Requirements

- 每个升级卡片至少显示：名称、1 行核心效果描述、稀有度、图标。
- 描述必须写玩家可感知结果，少用纯技术参数。例如优先写“主角攻击更快”，再在括号中补充 `+15% 攻速`。
- 若升级有前置或联动，UI 可以在描述底部用短标签展示，例如“塔流”、“生存”、“联动”。
- 当某升级是当前 build 强匹配项时，可考虑轻微提示，但不能直接替玩家决定。

---

## Acceptance Criteria

### 玩法目标

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-01 | 前期成长感 | 前 3 次升级里，玩家至少有 2 次能明显感到自己变强 |
| AC-02 | build 可读性 | 玩家在第 4-6 波前能大致识别自己当前 run 的主方向 |
| AC-03 | 备选质量 | 大多数升级节点里，至少有 2 个选项对当前 run 具有实际价值 |
| AC-04 | 多样性 | 不同 run 中不会稳定出现完全相同的前 5 次升级序列 |

### 数值验证

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-05 | 候选数量 | 默认返回 3 个合法候选；若合法项不足，则返回全部合法项 |
| AC-06 | 前置条件 | 未满足前置时，高阶升级绝不出现 |
| AC-07 | 层数限制 | 达到最大层数的升级不再进入候选池 |
| AC-08 | 类别保底 | 前 3 次升级中至少出现一个输出向和一个非纯输出向选项 |
| AC-09 | 权重生效 | build 匹配项出现率高于完全无关项，但不会达到必出 |

### 集成验证

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-10 | 升级选择系统接入 | 升级选择系统能直接消费候选列表并正确展示 |
| AC-11 | 自动攻击系统接入 | 英雄进攻类升级会正确修改主角攻击参数 |
| AC-12 | 防御塔系统接入 | 塔类升级会正确修改塔的伤害、范围或行为 |
| AC-13 | 生命值系统接入 | 生存类升级会正确修改生命、防护或回复相关参数 |

### Playtest 判据

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-14 | 决策疲劳 | 玩家不会在每次升级时都觉得“4 个都差不多” |
| AC-15 | 体感一致性 | 文案描述为“强”的升级，在实际体验中也应明显偏强 |
| AC-16 | 可重玩性 | 连续 3 局测试中，至少能形成 2 种不同 build 走向 |

---

## Open Questions

- 升级选择是固定每波后触发，还是允许经验满时即时触发，需要和经验系统、升级选择系统一起定。
- MVP 是否需要“移除一个候选后重抽”的轻度操作空间，还是保持纯 3 选 1 更干净。
- 塔类升级是作用于“所有塔”还是“当前已部署塔 + 后续新塔”，需要和塔系统统一。
- Epic 联动升级是否需要绑定里程碑波，避免前期过早出现。
