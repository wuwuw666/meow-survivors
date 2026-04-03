# 结算系统 (Settlement System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 成长的爽感（结算时的成就感回顾）+ 可爱即正义（结算画面风格）

## Overview

结算系统（Settlement System）在**游戏结束时**展示本局游戏的统计数据和结果。触发时机：玩家 HP 归零。结算面板是玩家对本局体验的"句号"——展示击杀数、存活波次、获得金币/经验、升级次数等统计信息，并提供"再来一局"的快速重开按钮。

**核心职责**：数据收集 → 结算面板展示 → 重开/返回

**核心接口**:
- `trigger_settlement(reason: String) -> void`
- `show_settlement() -> void`
- `signal restart_requested() -> void`
- `signal main_menu_requested() -> void`

---

## Player Fantasy

**情感目标：失败的安慰 + 成就的回顾 + 再来的动力**

玩家死亡后会有一小段沮丧——但结算面板的任务是把"失败"重新定义为"我又试了一次，这次我打到了第 X 波，拿到 Y 金币，下次一定能走更远"。通过展示本局的成就（"击杀了 100+ 敌人！""升级了  次！"），让玩家觉得自己其实挺强的。

**玩家应该感受到**：
- "哇原来我杀了这么多怪——其实我挺能的"
- "我到了第 8 波——差一点就过 10 波了"
- "金币攒了好多——下次可以先放个塔"
- "再来一局的按钮好显眼——点一下就开始"

**玩家不应该感受到**：
- "我又死了——好烦"（结算画面太负面）
- "这些数据什么意思？"（统计信息不清晰）
- "怎么重开？找不到按钮"（操作不明确）

---

## Detailed Rules

### 规则 1：触发时机

```
玩家HP归零 (生命值系统发出 player_died 信号):
    → 等待 1.0s (死亡动画: 猫咪倒下/星星飞走)
    → 游戏暂停 (get_tree().paused = true)
    → 结算系统收集所有统计数据
    → 播放结算面板 (OVERLAY_Layer)
```

### 规则 2：统计数据收集

结算系统在游戏运行期间持续监听各类事件，积累统计数据：

```gdscript
class_name SettlementData
extends Resource

var survived_waves: int = 0            # 存活波次数 (波次系统)
var total_enemies_killed: int = 0      # 总击杀数 (监听 enemy_died)
var total_damage_dealt: int = 0        # 总伤害 (监听所有伤害事件)
var total_damage_received: int = 0     # 总受伤 (监听玩家受伤)
var max_level_reached: int = 1         # 最高等级 (监听 level_up)
var total_upgrades_selected: int = 0   # 升级次数 (监听 upgrade_selected)
var total_coins_earned: int = 0        # 总金币 (监听 coins_picked_up)
var total_coins_spent: int = 0         # 总花费 (监听 deduct_coins)
var total_xp_earned: int = 0           # 总经验 (监听 xp 拾取)
var towers_placed: int = 0             # 放置塔数 (监听 tower_placed)
var highest_single_damage: int = 0     # 单次最高伤害 (监听伤害事件)
var boss_killed: bool = false          # 是否击杀 Boss (监听 boss death)
var game_over_reason: String = ""      # 死亡原因 (player_died)
var game_duration_sec: float = 0.0    # 游戏时长 (计时)
```

### 规则 3：结算面板 UI

```
全屏遮罩 (半透明深蓝 #1a1a2e, 70% alpha)
居中面板 (圆角 16px, 400×500px):

┌──────────── 喵族幸存者 ────────────┐
│                                    │
│    💔 "猫咪倒下了..."              │
│    (根据存活波次变化文案, 见规则4)  │
│                                    │
│  ──── 本局统计 ────                │
│  🌊  存活波次: 第 8 波             │
│  💀  击杀敌人: 85                  │
│  ⚔️  造成伤害: 1,250              │
│  ⭐  最高等级: Lv.7                │
│  🐟  获得金币: 120                 │
│  🏗️  放置防御塔: 3 座              │
│  ⏱️  游戏时长: 4:32                │
│                                    │
│  ──── 成就 ────                    │
│  🏆  "百杀达人" — 单局击杀 50+     │
│                                    │
│  [🔄 再来一局]     [🏠 返回主页]   │
│                                    │
└────────────────────────────────────┘

交互:
    点击"再来一局" → emit restart_requested → 游戏重新开始
    点击"返回主页" → emit main_menu_requested → 返回主菜单
    按 ESC → 同"返回主页"
```

### 规则 4：动态文案 (根据表现变化)

| 存活波次 | 标题文案 | 副标题 |
|---------|---------|--------|
| 0-2 | "猫咪还睡着..." | "别放弃,再试试?" |
| 3-5 | "猫咪努力了一下" | "不错的尝试!" |
| 6-8 | "猫咪战斗到了最后!" | "差一点就通关了!" |
| 9 | "猫咪就差一点点!" | "再试一次一定能行!" |
| 10+ (通关) | "🎉 猫咪守护住了仓库!" | "恭喜你通关了! 要不要挑战无尽模式?" |

**成就解锁 (MVP 简化)**:
| 成就 | 条件 | 显示 |
|------|------|------|
| "百杀达人" | 总击杀 ≥ 50 | 🏆 显示在结算面板 |
| "金币达人" | 总金币 ≥ 100 | 🏆 |
| "升级狂人" | 总升级 ≥ 8 | 🏆 |
| "Boss 猎手" | boss_killed = true | 🏆 |
| "速通猫" | 10 波通关且游戏时长 < 300s | 🏆 |

MVP 成就无持久存储——仅当展示，不解锁长期内容。v1.0 可接入解锁系统做持久成就。

### 规则 5：快速重开

```
点击"再来一局":
    emit restart_requested()
    → 波次系统重置 (wave = 1)
    → 玩家 HP 重置
    → 玩家金币重置为基础值 (如 0)
    → 所有塔和敌人清空
    → 升级状态清空
    → 游戏恢复 (get_tree().paused = false)
    → 进入第一波

点击"返回主页":
    emit main_menu_requested()
    → 切换到主菜单场景
```

---

## Formulas

### 公式 1：游戏时长格式化

```
format_duration(seconds: float) -> String:
    minutes = floor(seconds / 60)
    secs = floor(seconds % 60)
    return str(minutes) + ":" + str(secs).pad_zeros(2)

示例:
    272s → "4:32"
    61s  → "1:01"
```

### 公式 2：变量汇总

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `death_anim_duration` | float | 1.0s | 玩家死亡到结算面板弹出的延迟 |
| `settlement_bg_alpha` | float | 0.7 | 结算面板背景透明度 |
| `panel_width` | int | 400 | 结算面板宽度 px |
| `panel_height` | int | 500 | 结算板高度 px |

---

## Edge Cases

| 编号 | 边界情况 | 处理方式 |
|------|---------|---------|
| EC-01 | 玩家 0.1s 就死了 (极罕见) | 结算面板仍然弹出，显示 0 统计数据 + "猫咪还睡着..." |
| EC-02 | 结算面板弹出时又收到事件 | 游戏已暂停，不再收集新事件 |
| EC-03 | 统计数据超大值 (无尽模式几百波) | 数字用逗号分隔 (1,234) |
| EC-04 | 玩家快速连点"再来一局" | restart_requested 只响应第一次，后续忽略 |
| EC-05 | 返回主页时有未保存数据 | MVP 无存档系统，不处理；v1.0 结算前自动保存解锁 |

---

## Dependencies

| 上游系统 | 依赖类型 | 接口 | 说明 |
|---------|---------|------|------|
| **生命值系统** | 上游 | `player_died` | 触发结算 |
| **波次系统** | 软依赖 | `get_current_wave()` | 读取存活波次 |
| **金币系统** | 软依赖 | `total_coins_earned` 统计 | 统计展示 |
| **经验系统** | 软依赖 | `total_xp_earned`, `max_level` | 统计展示 |
| **UI 系统** | 软依赖 | OVERLAY_Layer 渲染 | 结算面板显示在最高层级 |
| **防御塔系统** | 软依赖 | `towers_placed` 统计 | 统计展示 |

| 下游系统 | 依赖类型 | 接口 | 说明 |
|---------|---------|------|------|
| **游戏主控** | 硬依赖 | `restart_requested`, `main_menu_requested` | 处理重/返回 |
| **存档系统** | 软依赖 (v1.0) | 解锁数据写入 | v1.0 结算后保存解锁 |
| **解锁系统** | 软依赖 (v1.0) | 成就检查 | v1.0 结算时检查并解锁成就 |

---

## Acceptance Criteria

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-SE-01 | 死亡触发结算 | 玩家 HP 归零 | 1 秒后弹出结算面板，游戏暂停 |
| AC-SE-02 | 统计数据正确 | 存活到第 5 波后死亡 | "存活波次: 第 5 波" |
| AC-SE-03 | 击杀数统计 | 本局击杀 10 只怪后死亡 | "击杀敌人: 10" |
| AC-SE-04 | 等级统计 | 升到 Lv.3 后死亡 | "最高等级: Lv.3" |
| AC-SE-05 | 游戏时长统计 | 运行 4:32 后死亡 | "游戏时长: 4:32" |
| AC-SE-06 | 动态案 | 存活 0-2 波 | 显示"猫咪还睡着..." |
| AC-SE-07 | 动态文案 | 存活 10 波 (通关) | 显示"🎉 猫咪守住了仓库!" |
| AC-SE-08 | 成就显示 | 击杀 ≥ 50 | "百杀达人" 成就显示 |
| AC-SE-09 | 快速重开 | 点击"再来一局" | 游戏重置，从第 1 波开始 |
| AC-SE-10 | 返回主页 | 点击"返回主页" | 切换到主菜单场景 |
| AC-SE-11 | 数字格式化 | 金币 1,250 | 显示 "1,250" 而非 "1250" |
| AC-SE-12 | settlement UI 风格 | 目测检查 | 圆角 16px, 深蓝背景, 可爱图标, 符合 UI 风格定义 |
