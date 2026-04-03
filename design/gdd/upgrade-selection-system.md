# 升级选择系统 (Upgrade Selection System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 成长的爽感（升级瞬间的爽快感+构筑感）+ 策略有深度（3选1的有意义的权衡）

---

## Overview

升级选择系统是游戏中负责管理"升级时机→候选展示→玩家选择→效果应用"的 Progression 系统。
它订阅经验系统的 `level_up_requested(new_level)` 信号，在升级触发时暂停游戏碰撞、
从升级池系统拉取 3 个候选升级、展示升级面板供玩家选择、将选择的升级应用到对应目标系统、
关闭面板并恢复碰撞、最后调用 `confirm_level_up()` 确认经验重置。

这是游戏核心循环（移动 → 攻击 → 杀敌 → 升级 → 构筑）中**"构筑"环节的驱动器**。
没有升级选择系统，升级只是数值变化，玩家无法"主动选择变强的方向"。这个系统的核心价值
是让玩家每次升级都经历一个"阅读选项 → 评估当前run状态 → 做出决策 → 立刻看到结果"的决策循环。

MVP 阶段行为固定为 3 选 1，不支持跳过、不支持重抽、不支持多升级批量弹出。
面板打开期间游戏世界完全暂停（碰撞暂停、拾取物暂停移动、敌人停止行为）。

**核心职责**：监听升级事件 → 暂停游戏 → 请求候选 → 展示面板 → 接收玩家选择 →
应用升级 → 关闭面板 → 恢复游戏 → 确认升级完成。

**核心接口**：
- `signal upgrade_panel_opened(level: int)` — 面板已打开
- `signal upgrade_chosen(upgrade_id: String)` — 玩家确认选择了升级
- `signal upgrade_panel_closed()` — 面板已关闭
- `open_upgrade_panel(level: int)` — 打开升级面板（由信号自动触发，也可手动调用）
- `is_panel_active() -> bool` — 面板是否在打开状态
- `apply_selected_upgrade(upgrade: UpgradeDefinition) -> void` — 应用选中的升级

---

## Player Fantasy

升级选择系统是游戏中**最具"主动决策感"的瞬间**——不同于自动攻击的被动输出、
不同于移动操作的常规执行，升级面板弹出的那一刻，玩家停下来思考"我要选什么"。
这是 run-based 游戏最核心的心理钩子，也是"再来一局"的成瘾源泉。

**情感目标**：

- 面板弹出一瞬间 → 期待感 + 兴奋感 + "看看这次给我什么好东西"
- 阅读选项 → 权衡感 + 策略感 + "这个好还是那个好"
- 点击选中 → 确认感 + 满足感 + "对，这就是我需要的"
- 面板关闭回到游戏 → 立即验证感 + "马上试试新能力"

**玩家应该感受到**：

- 每次升级都是一次"有分量的决策"，而不是闭眼随便点。
- 3 个选项中至少 2 个是有价值的，不会被逼着选一个"明显不想要的"。
- 选完之后能**立刻**在游戏中感受到差别（数值变高、外观变化、多了一个子弹等等）。
- 面板弹出时游戏暂停，给自己充分的思考时间，不存在"选慢了吃亏"的焦虑。

**玩家不应该感受到**：

- 选项之间差距太大，有一个明显碾压其他两个（伪选择）。
- 选项描述看不懂，不知道选了会有什么效果。
- 选了之后感觉不到差别（数值太小或视觉反馈太弱）。
- 因为选项太烂被迫跳过波次或重新开始。

---

## Detailed Design

### Core Rules

#### 规则 1：升级触发流程

```
经验系统 level_up_requested(new_level) 信号触发
    ↓
升级选择系统._on_level_up_requested(new_level)
    ↓
调用 pause_game_collision() — 碰撞系统切换到 UI_Only 模式
    ↓
调用 upgrade_panel_opened.emit(new_level)
    ↓
调用 UpgradePoolSystem.get_upgrade_candidates(run_state, count=3)
    ↓
渲染升级面板（3张卡片，每张显示图标、名称、描述、稀有度颜色）
    ↓
等待玩家点击选择（游戏暂停，无时间限制）
    ↓
玩家点击一张卡片
    ↓
apply_selected_upgrade(selected_upgrade)
    ↓
调用 upgrade_chosen.emit(selected_upgrade.upgrade_id)
    ↓
调用 upgrade_pool.mark_upgrade_taken(selected_upgrade.upgrade_id, run_state)
    ↓
关闭面板 → upgrade_panel_closed.emit()
    ↓
调用 resume_game_collision() — 碰撞系统恢复到 Active 模式
    ↓
调用 XPSystem.confirm_level_up() — 重置经验为0，允许继续累积
```

#### 规则 2：升级面板展示规则

| 属性 | MVP 默认值 | 说明 |
|------|-----------|------|
| **候选数量** | 3 | 始终展示 3 张卡片，由升级池系统保证至少有 3 个合法候选 |
| **布局** | 水平排列 | 3 张卡片并排居中显示 |
| **卡片内容** | 图标(占位) + 名称 + 1行描述 + 稀有度色标 | 从左到右依次为图标、名称、描述，稀有度通过边框/底色区分 |
| **稀有度颜色** | Common: 灰色, Rare: 蓝色, Epic: 紫色 | 与升级池系统定义的稀有度对应 |
| **高亮反馈** | 鼠标悬停时卡片放大 5% + 发光边框 | 视觉确认当前光标指向的选项 |
| **选择确认** | 单击即确认，无二次确认弹窗 | 追求爽快感，减少操作阻力 |

#### 规则 3：升级应用规则

升级选择后，系统将升级的 `effects` 字典应用到对应的目标：

| effect 前缀 | 目标系统 | 应用方式 |
|------------|---------|---------|
| `hero_` | 自动攻击系统 | 修改主角攻击参数（伤害、攻速、投射物数量等） |
| `tower_` | 防御塔系统 | 修改所有现有塔和未来新塔的参数（伤害、范围、攻速等） |
| `hp_` / `survival_` | 生命值系统 | 修改最大生命、回复率等 |
| `defense_` | 生命值系统 | 修改受到伤害减免比例等 |
| `hybrid_` | 多个系统 | 按 effect 字典中的子键分别应用 |

应用时序：先应用全局参数（如生命值上限），再应用行为参数（如攻速），最后
触发重计算（如当前/最大生命百分比刷新）。

#### 规则 4：面板期间的游戏体验

| 方面 | 规则 |
|------|------|
| **碰撞检测** | 切换到 `UI_Only` 模式，游戏世界碰撞全部暂停 |
| **拾取物** | 升级面板打开瞬间，场上所有拾取物停止移动，保持在当前位置 |
| **敌人** | 敌人停止移动和攻击行为，保持在当前位置和当前帧动画 |
| **玩家** | 玩家停止移动输入响应，保持在当前位置 |
| **计时器** | 游戏内计时器暂停（波次计时、攻击冷却计时等） |
| **音效** | 游戏世界音效淡出（可选，MVP 可不做淡出，直接静音） |

#### 规则 5：不可跳过

MVP 阶段玩家**必须从 3 个选项中选择一个**，没有跳过按钮。这是为了保证：
- 每次升级都产生实际的 build 变化
- 不会出现"跳过升级毫无惩罚"的退化策略
- 升级池系统负责保证候选质量（如果候选太烂，是升级池的问题，不是选择系统的问题）

### States and Transitions

| 状态 | 描述 | 行为 |
|------|------|------|
| **Idle** | 面板未打开，正常游戏 | 不响应选择输入，等待升级信号 |
| **Opening** | 动画过渡中（面板滑入） | 碰撞已暂停，候选正在生成，不接受点击 |
| **Ready** | 面板已展示，等待玩家选择 | 接受鼠标悬停和点击，游戏暂停 |
| **Selecting** | 玩家点击了卡片（确认动画播放中） | 不接受二次点击，播放升级应用动画 |
| **Closing** | 动画过渡中（面板淡出） | 碰撞未恢复，等待动画结束 |

**状态转换**：

| 当前状态 | 触发事件 | 目标状态 |
|----------|----------|----------|
| Idle | `level_up_requested` 信号 | Opening |
| Opening | 候选收到 + 面板动画完成 | Ready |
| Ready | 玩家点击卡片 | Selecting |
| Selecting | 升级应用完成 + 确认动画完成 | Closing |
| Closing | 面板动画完成 + 碰撞恢复 | Idle |

### Interactions with Other Systems

| 系统 | 交互方向 | 数据接口 | 说明 |
|------|---------|---------|------|
| **经验系统** | 经验 → 升级选择 | `signal level_up_requested(new_level)` | 触发升级面板打开的唯一信号源 |
| **经验系统** | 升级选择 → 经验 | `confirm_level_up()` | 玩家选择完成后调用，重置经验为0 |
| **升级池系统** | 升级池 → 升级选择 | `get_upgrade_candidates(run_state, 3)` | 提供 3 个候选 `UpgradeDefinition` |
| **升级池系统** | 升级选择 → 升级池 | `mark_upgrade_taken(id, run_state)` | 标记已选升级，更新池状态 |
| **碰撞检测系统** | 升级选择 → 碰撞 | `pause_game_collision()` / `resume_game_collision()` | 面板打开/关闭时切换碰撞模式 |
| **自动攻击系统** | 升级选择 → 自动攻击 | `apply_effects(effects_dict)` | 应用 `hero_` 前缀的升级效果 |
| **防御塔系统** | 升级选择 → 防御塔 | `apply_effects(effects_dict)` | 应用 `tower_` 前缀的升级效果 |
| **生命值系统** | 升级选择 → 生命值 | `apply_effects(effects_dict)` | 应用 `hp_` / `survival_` / `defense_` 前缀的升级效果 |
| **UI系统** | 升级选择 → UI | 面板渲染、卡片布局、稀有度着色 | 升级面板本身的视觉渲染 |

---

## Formulas

### 公式 1：面板弹出延迟（动画时序）

为避免升级事件到面板弹出之间的"断层感"，设计一个微小的延迟让过渡更流畅：

```
panel_open_delay_ms = 250ms
```

**体验意图**：升级触发到面板展示的 250ms 延迟让玩家有一个"升级了！"的瞬间认知窗口。
太短（<100ms）→ 面板突兀弹出，来不及反应升级事件。太长（>500ms）→ 玩家觉得"卡了一下"。

### 公式 2：升级效果应用公式

每个升级的 `effects` 是一个字典，键名表示目标参数，键值表示修改方式和数值：

```
effects = {
    "hero_damage": {"type": "percent_additive", "value": 0.20},     # +20% 伤害
    "hero_attack_speed": {"type": "percent_additive", "value": 0.15}, # +15% 攻速
    "tower_damage": {"type": "percent_additive", "value": 0.18},    # +18% 塔伤害
    "hp_max": {"type": "flat_additive", "value": 20},               # +20 最大生命
    "tower_cost_multiplier": {"type": "percent_additive", "value": -0.10}  # -10% 塔成本
}
```

**效果类型定义**：

| type | 计算方式 | 适用场景 | 示例 |
|------|---------|---------|------|
| **flat_additive** | `base_value + Σ flat_bonuses` | 生命值、固定数值 | `hp_max: base + 20 + 25` |
| **percent_additive** | `base_value × (1 + Σ percent_bonuses)` | 伤害、攻速、成本百分比 | `damage: base × (1 + 0.20 + 0.15)` |
| **flat_set** | `value`（直接设置） | 解锁新能力、改变阈值 | `unlock_projectile: true` |

> **P0 修复说明**：旧版将 "multiplicative" 和 "additive" 混用。实际语义为 "percent_additive"（百分比加成叠加到乘数池）和 "flat_additive"（固定值累加）。"multiplicative" 命名易误导开发人员以为加成是相乘叠加。

**复合效果计算（percent_additive 类型）**：

```
effective_damage = base_damage × (1 + Σ percent_bonuses)
```

示例计算：
- 基础伤害 = 10
- 升级1: Sharp Fishbones 第1层 `+20%`
- 升级2: Sharp Fishbones 第2层 `+15%`（叠层递减值）
- 最终伤害 = `10 × (1 + 0.20 + 0.15) = 10 × 1.35 = 13.5`

> **P0 修复说明**：叠层升级的 value 由升级池系统根据当前叠层数计算后传递。升级选择系统不自行计算叠层值。具体规则见下节。

**复合效果计算（flat_additive 类型）**：

```
effective_max_hp = base_max_hp + Σ flat_bonuses
```

示例计算：
- 基础最大生命 = 100
- 升级1: `+20` flat
- 升级2: `+25` flat（九条命第2层，per_stack_gain = +5）
- 最终最大生命 = `100 + 20 + 25 = 145`

### 公式 2.1：叠层升级的值计算（P0 修复）

叠层升级（Stackable）每次被选择时，应用的实际值由 **升级池系统** 计算并传递给升级选择系统。计算规则遵循 upgrade-pool-system §5 的叠层公式：

```
effect_value(stack) = base_value + per_stack_gain × (stack - 1)
```

其中：
- `stack` = 当前选择的层数（1 = 第一次拿，2 = 第二次拿...）
- `base_value` = 该升级首次选择时的效果值
- `per_stack_gain` = 后续每一层的递增值（通常 < base_value）

**示例**（Sharp Fishbones，base_value = 20%，per_stack_gain = 15%）：
- 第1次选择：应用 +20% → total bonus = 20%
- 第2次选择：应用 +15% → total bonus = 35%
- 第3次选择：应用 +15% → total bonus = 50%

**升级选择系统的职责**：
1. 从升级池获取候选时，升级池已根据当前 stack 计算出正确的 effect.value
2. 升级选择系统只负责应用该 effect.value，不自行计算叠层
3. 应用时通过 `apply_effect(key, effect)` 将值传递给目标系统的 bonus 池

### 公式 3：当前生命值百分比刷新

当升级修改了 `hp_max` 时，当前生命值按比例缩放以保持相同的健康百分比：

```
hp_ratio = current_hp / old_max_hp
new_current_hp = round(hp_ratio × new_max_hp)
```

示例计算：
- `old_max_hp = 100`, `current_hp = 60`, hp_ratio = 0.6
- `new_max_hp = 120`（升级 +20 后）
- `new_current_hp = round(0.6 × 120) = 72`

这保证了玩家不会因为升级了生命值而"突然感觉掉了一截血"，也不会"白嫖"满血。

### 公式 4：升级选择到面板渲染的时间预算

```
total_open_time_ms = candidate_fetch_ms + render_ms + open_delay_ms

其中：
  candidate_fetch_ms < 5ms    — 升级池系统查询候选（纯数据操作，应极快）
  render_ms < 10ms            — 面板和卡片渲染（3张简单UI卡片）
  open_delay_ms = 250ms       — 故意延迟的过渡时间

total_open_time_ms < 270ms    — 从升级到面板可操作，玩家感知的总延迟
```

---

## Edge Cases

| # | 边界情况 | 触发条件 | 处理方式 |
|---|---------|---------|---------|
| EC-01 | **升级池候选不足 3 个** | 几乎所有升级都被拿满了，升级池返回少于 3 个合法候选 | 升级选择系统**展示全部返回的候选**（即使只有1-2个），不设"空卡片"占位；玩家仍必须从可用选项中选择 |
| EC-02 | **面板打开期间收到新的 level_up_requested** | 极端情况下经验连续溢出，经验系统想触发第二次升级 | **忽略后续信号**，队列不堆积；当前升级面板关闭后，如果 `current_xp >= threshold` 仍满足，经验系统会再次触发（见经验系统 EC-01/EC-02） |
| EC-03 | **玩家在游戏暂停/菜单打开时升级** | 理论上不应发生，因为暂停时碰撞系统不触发拾取 | 防御性处理：如果 `is_panel_active()` 为 true，直接返回，不重复打开 |
| EC-04 | **升级效果应用失败（目标系统未准备好）** | 目标系统未初始化或 effect 键名不匹配 | 记录 `push_warning("UpgradeSelectionSystem: failed to apply effect '%s'" % key)`，跳过该 effect，不影响其他效果的应用；整体升级仍视为成功 |
| EC-05 | **面板打开期间玩家最小化游戏窗口** | Alt-Tab 或最小化窗口 | 面板保持打开状态，游戏保持在暂停模式；窗口恢复后面板依然可操作（因为碰撞系统也保持在 UI_Only 模式） |
| EC-06 | **升级面板动画被打断** | 面板滑入动画未完成时收到异常事件 | 状态机不允许从 Opening 状态跳过 Ready 阶段；动画中断后立即进入 Ready 状态 |
| EC-07 | **升级效果需要新塔/新技能解锁** | 选了"解锁新塔类型"类升级 | 升级选择系统通知防御塔系统注册新的塔类型，并刷新地图上可用的塔位类型 |
| EC-08 | **升级面板在 2 秒内没有响应输入** | 面板打开后玩家未操作 2 秒 | MVP 不做自动关闭或超时处理；升级面板无超时，玩家可以无限时间思考 |
| EC-09 | **升级面板关闭时 resume_game_collision() 失败** | 碰撞系统内部异常 | 强制调用一次恢复，使用 `ensure_game_collision_resumed()` 安全方法；记录错误日志 |
| EC-10 | **升级效果包含"立即治疗"类效果** | 选择升级后立即回血 | 在 `apply_selected_upgrade()` 中先应用 `hp_` 类效果，在应用完成后刷新生命值显示 |

### 退化策略分析

| 退化策略 | 描述 | 缓解措施 |
|----------|------|---------|
| **跳过升级** | 如果可以跳过，玩家可能永远不选生存向升级，导致游戏过于简单或过于随机 | MVP 不可跳过，强制选择 |
| **重抽选项直到满意的** | 如果支持 reroll，玩家可以无限重抽直到出现最优解 | MVP 不支持 reroll；v1.0 可引入受限 reroll（每局限1-2次） |
| **最优解锁定** | 如果某个升级明显强于其他所有选项，每次升级都选它 | 升级池系统通过权重和稀有度控制出现频率；升级选择系统无法控制候选质量，依赖上游系统保证质量 |
| **连续升级面板导致体验中断** | 如果升级间隔太短（每 5 秒弹一次面板），会破坏游戏节奏 | 这不是选择系统的问题，而是经验系统的 `BASE_XP` 和敌人经验掉落需要调优。选择系统保证面板操作尽可能高效（<3秒完成选择） |

---

## Dependencies

### 上游依赖（升级选择系统依赖的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **经验系统** | 硬依赖 | `signal level_up_requested(new_level: int)` | 升级面板触发的唯一信号源 |
| **升级池系统** | 硬依赖 | `get_upgrade_candidates(run_state, count) -> Array[UpgradeDefinition]` | 提供候选升级列表 |
| **碰撞检测系统** | 硬依赖 | `pause_game_collision()` / `resume_game_collision()` | 面板打开/关闭时切换碰撞模式 |

### 下游依赖（依赖升级选择系统的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **自动攻击系统** | 硬依赖 | `apply_effects(effects_dict)` | 消费 `hero_` 前缀的升级效果 |
| **防御塔系统** | 硬依赖 | `apply_effects(effects_dict)` | 消费 `tower_` 前缀的升级效果 |
| **生命值系统** | 硬依赖 | `apply_effects(effects_dict)` | 消费 `hp_` / `survival_` / `defense_` 前缀的升级效果 |
| **UI系统** | 软依赖 | 面板渲染数据（升级卡片信息） | 用于升级面板的视觉呈现 |
| **结算系统** | 软依赖 | `get_taken_upgrades() -> Array[String]` | 游戏结束时展示本局选择的升级 |

### 接口定义

```gdscript
# UpgradeSelectionSystem.gd
# 升级选择系统 — 全局 Autoload 单例
# 挂载路径: /root/UpgradeSelectionSystem

extends Node

# ---------- 信号（对外发出）----------
## 升级面板已打开，传入触发升级的等级
signal upgrade_panel_opened(level: int)

## 玩家确认选择了一个升级
signal upgrade_chosen(upgrade_id: String)

## 升级面板已关闭，游戏恢复正常
signal upgrade_panel_closed()

# ---------- 内部依赖（在 _ready 中绑定）----------
var _xp_system: Node          # XPSystem Autoload
var _upgrade_pool: Node       # UpgradePoolSystem Autoload
var _collision: Node          # CollisionDetection System Autoload
var _auto_attack: Node        # AutoAttackSystem Autoload
var _tower_system: Node       # TowerSystem Autoload
var _health_system: Node      # HealthSystem Autoload

var _is_panel_active: bool = false
var _current_candidates: Array = []

func _ready() -> void:
    _xp_system = get_node("/root/XPSystem")
    _upgrade_pool = get_node("/root/UpgradePoolSystem")
    _collision = get_node("/root/CollisionDetectionSystem")
    _auto_attack = get_node("/root/AutoAttackSystem")
    _tower_system = get_node("/root/TowerSystem")
    _health_system = get_node("/root/HealthSystem")

    _xp_system.level_up_requested.connect(_on_level_up_requested)

# ---------- 公开接口 ----------
## 返回升级面板是否正在展示
func is_panel_active() -> bool:
    return _is_panel_active

## 返回当前展示的候选列表（供UI系统读取）
func get_current_candidates() -> Array:
    return _current_candidates

## 玩家点击了一张升级卡片后调用
## upgrade: 玩家选择的 UpgradeDefinition
func on_upgrade_card_clicked(upgrade: Variant) -> void:
    if not _is_panel_active:
        return
    _apply_upgrade(upgrade)
    _close_panel()

# ---------- 内部方法 ----------
func _on_level_up_requested(new_level: int) -> void:
    if _is_panel_active:
        push_warning("UpgradeSelectionSystem: panel already active, ignoring level_up_requested")
        return
    _open_panel(new_level)

func _open_panel(level: int) -> void:
    _is_panel_active = true
    _collision.pause_game_collision()
    upgrade_panel_opened.emit(level)

    # 从升级池获取候选
    var run_state = _get_run_state()
    _current_candidates = _upgrade_pool.get_upgrade_candidates(run_state, 3)
    # 此处发出信号通知UI渲染面板（由UI系统监听 upgrade_panel_opened）

func _apply_upgrade(upgrade: Variant) -> void:
    var effects = upgrade.effects
    for key in effects:
        var effect = effects[key]
        var applied = false

        if key.begins_with("hero_"):
            applied = _auto_attack.apply_effect(key, effect)
        elif key.begins_with("tower_"):
            applied = _tower_system.apply_effect(key, effect)
        elif key.begins_with("hp_") or key.begins_with("survival_") or key.begins_with("defense_"):
            applied = _health_system.apply_effect(key, effect)
        elif key.begins_with("hybrid_"):
            applied = _apply_hybrid_effect(key, effect)
        else:
            push_warning("UpgradeSelectionSystem: unknown effect key '%s'" % key)
            applied = false

        if not applied:
            push_warning("UpgradeSelectionSystem: failed to apply effect '%s'" % key)

    upgrade_chosen.emit(upgrade.upgrade_id)
    _upgrade_pool.mark_upgrade_taken(upgrade.upgrade_id, _get_run_state())

func _apply_hybrid_effect(key: String, effect: Dictionary) -> bool:
    # hybrid 效果可能同时涉及多个系统，按子键分发
    for sub_key in effect:
        var sub_effect = effect[sub_key]
        if sub_key.begins_with("hero_"):
            _auto_attack.apply_effect(sub_key, sub_effect)
        elif sub_key.begins_with("tower_"):
            _tower_system.apply_effect(sub_key, sub_effect)
        elif sub_key.begins_with("hp_") or sub_key.begins_with("survival_"):
            _health_system.apply_effect(sub_key, sub_effect)
    return true

func _close_panel() -> void:
    _is_panel_active = false
    _current_candidates = []
    upgrade_panel_closed.emit()
    _collision.resume_game_collision()
    _xp_system.confirm_level_up()

func _get_run_state() -> Dictionary:
    # 从各系统收集当前 run 状态
    return {
        "level": _xp_system.get_level(),
        "taken_upgrades": _get_taken_upgrade_ids(),
        "current_wave": _get_current_wave(),
        # 更多状态由各系统接口提供
    }

func _get_taken_upgrade_ids() -> Array[String]:
    # 从 _upgrade_pool 或 run_state 获取已选升级ID列表
    return []

func _get_current_wave() -> int:
    # 从波次系统获取当前波次
    return 0
```

### 下游系统的 effect 应用接口契约

每个被升级效果修改的系统必须实现以下接口：

```gdscript
# 效果应用接口契约（每个目标系统必须实现）
func apply_effect(effect_key: String, effect: Dictionary) -> bool:
    # effect: {"type": "additive"/"multiplicative"/"flat_set", "value": Variant}
    # 返回 true 表示成功应用，false 表示失败（键不匹配或类型错误）
    pass

func get_effect_bonuses(effect_prefix: String) -> Dictionary:
    # 返回当前该 prefix 下所有已应用的升级加成汇总
    # 用于 UI 展示和结算统计
    pass
```

---

## Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响面 | 说明 |
|--------|------|--------|---------|--------|------|
| `candidate_count` | int | 3 | 2-4 | 决策复杂度 | 每次升级展示多少个选项。MVP 固定为 3；v1.0 可考虑特殊情况下给第 4 个选项。过少（2个）决策太受限，过多（4+）决策疲劳 |
| `panel_open_delay_ms` | int | 250 | 100-500 | 面板弹出流畅感 | 从升级触发到面板可操作之间的过渡延迟。太短没有"升级！"的认知窗口，太长感觉卡顿 |
| `card_hover_scale` | float | 1.05 | 1.02-1.10 | 悬停反馈的视觉强度 | 鼠标悬停卡片时的放缩倍率。过低看不出来，过高显得夸张 |
| `card_select_animation_ms` | int | 300 | 150-500 | 选择确认的节奏感 | 点击卡片后的确认动画时长。太短缺乏反馈，太长拖慢节奏 |
| `allow_skip` | bool | false | true / false | 玩家自由度 | MVP 不允许跳过。v1.0 可考虑引入"跳过但消耗资源"机制 |
| `allow_reroll` | bool | false | true / false | 随机性控制 | MVP 不支持重抽。v1.0 可引入每局限次数的 reroll |
| `panel_input_timeout_ms` | int | 0（无限制） | 0-30000 | 面板超时策略 | 面板打开后多久自动关闭/跳过。MVP 无超时（玩家可以无限思考）；如 playtest 发现玩家挂机可设置超时 |
| `upgrade_application_order` | enum | HP_FIRST | HP_FIRST / EFFECTS_FIRST / PARALLEL | 升级效果的生效时序 | HP_FIRST = 先算生命值变化再算其他效果（避免玩家选 +HP 后发现血量没按比例缩放）。MVP 默认 HP_FIRST |

**调参优先级建议**：

1. **优先调 `candidate_count`** — 直接决定决策复杂度，是最重要的 knob
2. **其次调 `panel_open_delay_ms`** — 影响面板弹出的"感觉"，容易 playtest 感知
3. **最后调动画相关参数** (`card_select_animation_ms`, `card_hover_scale`) — 纯感受型参数

**与经验系统的参数交互**：
- `candidate_count` 需要和经验系统的 `BASE_XP` 配合调。如果升级太频繁（`BASE_XP` 太小），
  `candidate_count=3` 可能让玩家频繁做决策；升级间隔较长时可以适当增加 `candidate_count`
- 经验系统的 `BASE_XP=50` 意味着前几波就会频繁升级，此时 `candidate_count` 应该足够小以减少疲劳

**极端值测试**：
- `candidate_count = 1` → 伪选择（实际上没有选择），失去系统意义
- `candidate_count = 5` → 决策负荷过高，每次升级需要比较 5 张卡片
- `panel_open_delay_ms = 0` → 面板瞬间弹出，升级触发感太突兀
- `panel_open_delay_ms = 1000` → 玩家觉得"卡了1秒"

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 前置条件 | 操作步骤 | Pass 标准 |
|----|-------|---------|---------|----------|
| AC-01 | 升级面板触发 | 经验系统经验满阈值 | 触发 `level_up_requested(new_level)` | 面板在 270ms 内打开，展示 3 张候选卡片 |
| AC-02 | 卡片内容渲染 | 面板已打开 | 检查 3 张卡片内容 | 每张卡片显示图标、名称、一行描述、稀有度色标 |
| AC-03 | 稀有度着色 | 面板已打开，含 Common/Rare/Epic 候选 | 检查卡片边框/底色 | Common=灰色, Rare=蓝色, Epic=紫色 |
| AC-04 | 悬停反馈 | 面板 Ready 状态 | 鼠标移动到卡片上 | 卡片放大 5% 并发光，移开后恢复原状 |
| AC-05 | 选择升级 | 面板 Ready 状态 | 点击一张卡片 | 升级效果应用 → 面板关闭 → 碰撞恢复 → 经验重置为0 |
| AC-06 | 游戏暂停验证 | 面板已打开 | 检查游戏世界中敌人/拾取物/玩家 | 全部静止不动，不响应游戏世界输入 |
| AC-07 | 游戏恢复验证 | 面板已关闭 | 检查游戏世界 | 敌人恢复移动和攻击，拾取物恢复吸附，玩家恢复移动控制 |
| AC-08 | 经验重置 | 升级选择完成 | 调用 `confirm_level_up()` 后检查 | `current_xp = 0`，继续拾取经验正常累积 |
| AC-09 | 面板防重复打开 | 面板已处于 Opening 或 Ready 状态 | 再次触发 `level_up_requested` | 忽略信号，不弹出新面板，输出警告 |
| AC-10 | `is_panel_active()` 准确性 | 面板各状态 | 调用 `is_panel_active()` | Opening/Ready/Selecting 返回 `true`，Idle/Closing 返回 `false` |

### 升级效果应用专项测试

| ID | 测试项 | 前置条件 | 操作步骤 | Pass 标准 |
|----|-------|---------|---------|----------|
| AC-UPG-01 | hero_damage 效果应用 | 选择 `hero_damage` percent_additive +20% 升级 | 检查主角基础伤害 | 基础伤害 × 1.20 |
| AC-UPG-02 | hero_attack_speed 效果应用 | 选择 `hero_attack_speed` percent_additive +15% 升级 | 检查主角攻击冷却 | 攻击间隔 = 基础间隔 ÷ (1 + 0.15) = 基础间隔 ÷ 1.15 |
| AC-UPG-03 | tower_damage 效果应用 | 选择 `tower_damage` percent_additive +18% 升级 | 检查所有已部署塔的伤害 | 所有塔伤害 × 1.18 |
| AC-UPG-04 | hp_max flat_additive 效果应用 | 选择 `hp_max` +20 升级 | 检查最大生命和当前生命 | `max_hp = 原max_hp + 20`，`current_hp` 按比例缩放 |
| AC-UPG-05 | 生命值比例保持 | 当前 `hp = 60/100`，选择 `hp_max +40` | 检查新的当前/最大生命 | `max_hp = 140`, `current_hp = 84`（60% 比例保持） |
| AC-UPG-06 | percent_additive 叠加 | 已有 hero_damage +20%，再选 +15% | 检查最终伤害 | `base × (1 + 0.20 + 0.15) = base × 1.35` |
| AC-UPG-07 | 叠层升级值计算 | 第二次选择 Sharp Fishbones | 检查效果值 | 应用 +15%（非首次的 +20%），由升级池计算后传递 |
| AC-UPG-08 | 未知 effect 键跳过 | 升级包含未知前缀的 effect | 选择该升级 | 记录警告跳过未知 effect，其余 effect 正常应用 |
| AC-UPG-09 | 已选升级标记 | 选择升级后 | 检查升级池状态 | `mark_upgrade_taken()` 已调用，该升级不再出现在候选池 |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-INT-01 | 经验系统 → 升级选择 | 经验满阈值触发 `level_up_requested(2)` | 面板在 270ms 内打开，展示 3 张候选 |
| AC-INT-02 | 升级选择 → 碰撞检测 | 面板打开 | 碰撞系统状态为 `UI_Only`，敌人不触发任何碰撞 |
| AC-INT-03 | 升级选择 → 碰撞恢复 | 面板关闭 | 碰撞系统状态恢复为 `Active`，敌人碰撞正常响应 |
| AC-INT-04 | 升级选择 → 经验重置 | 选择完毕 | `XPSystem.current_xp = 0`，可继续拾取经验 |
| AC-INT-05 | 升级选择 → 自动攻击 | 选择 hero_damage 升级 | 主角下一次攻击的伤害值正确反映了升级效果 |
| AC-INT-06 | 升级选择 → 防御塔 | 选择 tower_damage 升级 | 所有已部署塔的下一发攻击伤害值正确 |
| AC-INT-07 | 升级选择 → 生命值 | 选择 hp_max 升级 | 生命值系统 `max_hp` 立即更新，血条重新渲染 |
| AC-INT-08 | 结算系统集成 | 游戏结束 | `get_taken_upgrades()` 返回本局选择的升级ID列表 |

### 性能测试

| ID | 测试项 | 测试场景 | Pass 标准 |
|----|-------|---------|----------|
| AC-PERF-01 | 面板渲染性能 | 50个敌人在屏幕上，升级面板打开 | 面板渲染 + 碰撞切换总耗时 < 15ms |
| AC-PERF-02 | 候选获取性能 | 升级池已满状态（大部分升级已选） | `get_upgrade_candidates()` 耗时 < 5ms |
| AC-PERF-03 | 升级应用性能 | 选择包含多个 effect 的升级 | 效果分发 + 应用总耗时 < 5ms |

### Playtest 判据

| ID | 验证项 | Pass 标准 |
|----|-------|-----------|
| AC-PLAY-01 | 决策体感 | 玩家在 80% 的升级节点能在 5 秒内做出选择，不会觉得纠结太久 |
| AC-PLAY-02 | 选项质量 | 玩家在 70% 的升级节点对"至少有两个选项有价值"感到同意 |
| AC-PLAY-03 | 升级后验证 | 玩家选择升级后能在 10 秒内感知到效果变化 |
| AC-PLAY-04 | 暂停体验 | 玩家不会因为"面板弹出打断游戏节奏"而感到不适 |
| AC-PLAY-05 | 无跳过焦虑 | 玩家不会因为"被迫选一个不想要的"而想重开 |

---

## Open Questions

| 问题 | 影响系统 | 建议解决方案 | 决策时间 |
|------|---------|-------------|---------|
| 是否需要"跳过"选项（跳过本次升级、不获得任何东西）？ | 升级选择 + 升级池 | MVP 不引入跳过，确保每次升级都有 build 变化；v1.0 可考虑"跳过但获得少量金币补偿" | MVP 阶段已确认不引入 |
| 是否需要"重抽/ reroll"功能（重新获取一组新的候选）？ | 升级选择 + 升级池 | MVP 不引入；v1.0 可考虑消耗某种资源（金币/专用 reroll token）重抽，每局限1-2次 | v1.0 阶段再议 |
| 升级面板是全屏模态遮罩还是居中悬浮面板？ | UI系统 | MVP 建议居中悬浮面板 + 半透明背景遮罩，保留游戏世界可见以维持沉浸感 | 与 UI 系统设计统一决策 |
| 是否支持键盘/手柄选择（不只是鼠标点击）？ | 输入系统 + UI系统 | MVP 仅支持鼠标点击；v1.0 增加键盘数字键(1/2/3)和手柄方向+确认 | v1.0 阶段再议 |
| 升级效果应用中如果修改了 `hp_max`，当前生命值缩放后出现浮点数，如何取整？ | 生命值系统 | `round()` 四舍五入到最接近的整数；当 `hp_ratio` 恰好在两个整数中间时（如 71.5），向上取整 | 在生命值系统 GDD 中确认 |
| 连续两次升级间隔极短（如1秒内连续升级），两次面板体验是否流畅？ | 经验系统 + 升级选择 | 当前设计第二次升级会在第一次面板关闭后、经验系统检查到依然满足阈值时自动触发。如果太密集可能需要经验系统的溢出丢弃策略来兜底 | 与经验系统联调时确认 |
| v1.0 是否考虑"升级预览"功能（在选择面板中预览下一级可能出现的升级类型）？ | 升级池系统 | 不需要——升级池系统已经通过类别保底和标签匹配保证了候选质量，不需要额外预览 | v1.0 阶段再议 |
