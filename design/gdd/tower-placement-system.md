# 塔位放置系统 (Tower Placement System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 策略有深度（何时放、放哪里、放什么）+ 可爱即正义（放置动画/反馈）

## Overview

塔位放置系统（Tower Placement System）是玩家在**游戏世界中放置防御塔**的交互桥梁。地图预定义了有限数量的塔位（固定 slot），玩家选择空闲塔位 → 选择塔类型 → 验证金币 → 塔实例化出现在塔位上。系统负责处理整个放置意图链路，包括范围预览、验证反馈和状态管理。

MVP 不支持自由建造——玩家只能在地图标记的塔位上放置。这简化了放置逻辑并保证了视觉一致性。

**核心职责**：接收放置意图 → 塔位状态管理 → 协调塔系统/金币系统 → 视觉反馈（范围预览/放置动画）

**核心接口**：
- `place_tower(slot_id: int, tower_type: String) -> bool`
- `remove_tower(slot_id: int) -> bool`
- `get_slot_data(slot_id: int) -> Dictionary`
- `signal tower_placed(slot_id: int, tower_type: String)`
- `signal tower_placement_failed(slot_id: int, reason: String)`

---

## Player Fantasy

**情感目标：阵地建设的掌控感 + "我的防线成型了"的视觉满足**

塔位放置系统让玩家有"我在建设阵地"的感觉。明确的塔位标记让玩家清楚"哪里可以放塔"——不是瞎找。鼠标悬停时显示范围预览帮助决策——"这个位置能不能覆盖到关键路径？"——这是策略深度的核心来源。

**玩家应该感受到**：
- "地图上清楚地标着哪里能放塔——空位有标记"
- "鼠标移过去就能看到塔的作用范围——我知道放下去能覆盖哪些区域"
- "放下去的时候'啾'的一下塔就出现了——很有建设感"
- "金币不够时马上告诉我——不要点了半天没反应"

**玩家不应该感受到**：
- "这塔位在哪？完全看不出来"
- "我点了怎么没反应？"（金币不足或状态不对，但没提示）
- "放了塔但不知道覆盖哪些敌人"
- "我想放这里但系统不让，为什么？"

**参考**：植物大战僵尸（格子化塔位、范围预览清晰）、Kingdom Rush（固定塔位、视觉标记明显）

---

## Detailed Rules

### 规则 1：塔位状态

每个塔位由地图系统定义，包含位置坐标和运行时状态：

| 状态 | 含义 | 可交互 | 视觉表现 |
|------|------|--------|---------|
| **EMPTY** | 空闲，可放置 | 是 | 空平台/地基图标，鼠标悬停高亮 |
| **OCCUPIED** | 已有塔在运行 | 是（查看/升级） | 塔模型，悬停显示范围预览 |
| **LOCKED** | 未解锁（v1.0） | 否 | 灰色锁图标 |

> MVP 不做 LOCKED——所有塔位初始 EMPTY。v1.0 可通过条件解锁额外塔位。

```gdscript
class_name TowerSlotData
extends Resource

@export var id: int = 0
@export var position: Vector2 = Vector2.ZERO
@export var state: String = "EMPTY"  # EMPTY / OCCUPIED / LOCKED
var tower_node: Node = null  # OCCUPIED 时指向塔实例
```

### 规则 2：放置交互流程

```
1. 鼠标悬停空塔位
   → 塔位高亮 (发光/脉冲动画)
   → 显示"点击放置"提示
   → 发出 tower_slot_hovered(slot_id) 信号

2. 鼠标点击空塔位
   → 弹出塔类型选择面板 (HUD 层级)
   → 显示 3 种可选塔: 名称、图标、费用、简述
   → 金币不足的塔灰色不可选

3. 玩家选择一种塔类型并确认
   → 验证:
     a. slot 状态仍然是 EMPTY (防并发)
     b. 玩家金币 >= 放置费用
     c. tower_type 在数据表中有效
   → 通过 → 执行放置 (规则 3)
   → 失败 → 提示原因，关闭面板

4. 放置成功
   → 播放放置动画 (塔弹出 + 粒子特效)
   → slot 状态 → OCCUPIED
   → 关闭选择面板
```

**选择面板示意**：
```
┌────────────── 选择防御塔 ──────────────┐
│  🐟 小鱼干     🧶 毛线球     🌿 猫薄荷  │
│  单体输出      范围减速      伤害加成   │
│  15 dmg       8+减速30%     范围+15%   │
│  10 金币       15 金币       20 金币   │
│  [放置]       [放置]        [放置(灰)]  │
└────────────────────────────────────────┘
```

### 规则 3：放置执行

```gdscript
func place_tower(slot_id: int, tower_type: String) -> bool:
    var slot = _get_slot(slot_id)
    if slot == null:
        return false

    # 验证 1: 状态
    if slot.state != "EMPTY":
        emit_tower_placement_failed(slot_id, "slot_not_empty")
        return false

    # 验证 2: 金币
    var tower_data = _tower_system.get_tower_data(tower_type)
    if _gold_system.player_coins < tower_data.place_cost:
        emit_tower_placement_failed(slot_id, "insufficient_coins")
        return false

    # 执行扣费
    _gold_system.deduct_coins(tower_data.place_cost)

    # 调用塔系统创建
    var tower_node = _tower_system.place_tower(tower_type, slot.position)
    if tower_node == null:
        _gold_system.refund_coins(tower_data.place_cost)
        emit_tower_placement_failed(slot_id, "tower_create_failed")
        return false

    # 更新槽位状态
    slot.state = "OCCUPIED"
    slot.tower_node = tower_node

    # 发出信号 & 特效
    emit_signal("tower_placed", slot_id, tower_type)
    _play_place_effect(slot.position)

    return true
```

### 规则 4：范围预览

鼠标悬停在**空塔位**上时，预览当前选中塔类型的射程：

```
悬停空塔位 + 选择面板中选中了塔类型:
    在塔位位置绘制半透明圆形范围指示器
    半径 = tower_data.tower_range
    颜色:
        攻击塔 (fish_shooter): 绿色半透明
        控制塔 (yarn_launcher): 紫色半透明
        辅助塔 (catnip_aura): 金色半透明
    透明度 = 0.3 (可配置)

鼠标移开:
    范围指示器消失
```

**辅助塔的特殊预览**：除了圆形范围环，还要高亮范围内已有的友方目标（玩家英雄、其他塔），让玩家一眼看出"放下去能加成到谁"。

### 规则 5：移除流程

MVP 阶段**不支持移除塔**——放置后不可撤回。

**理由**：
1. 简化 MVP 范围——移除+返还是一个额外决策链
2. 增加"放错位置的成本"是策略张力的一部分
3. 玩家可以在升级面板关闭期间再放

**v1.0 扩展**：右键点击已有塔 → 弹出确认 "确定移除？返还 50% 金币" → 确认后拆除。

### 规则 6: 升级交互流程

```
1. 鼠标悬停已有塔 (OCCUPIED slot)
   → 塔位底部显示"可升级"提示 (如果金币 >= 升级费用)
   → 显示范围预览

2. 点击已有塔
   → 弹出塔信息面板:
     - 当前类型和等级
     - 当前属性 (伤害/射程/攻速)
     - 可升级选项及费用
     - "升级"按钮 (金币不足时灰显)

3. 点击"升级"
   → 验证金币
   → 扣费
   → 调用 _tower_system.upgrade_tower()
   → 播放升级特效 (金光一闪 + 数字飘出)
   → 更新面板显示

4. 塔已到满级 (level 3)
   → 显示"已满级"，隐藏升级按钮
```

---

## Formulas

### 公式 1：升级费用递增

```
upgrade_cost = base_upgrade_cost × (1 + current_level × 0.5) 向上取整

level 0 → 1: ceil(5 × 1.0) = 5 金币
level 1 → 2: ceil(5 × 1.5) = 8 金币
level 2 → 3: ceil(5 × 2.0) = 10 金币

总计从 0 → 3: 5 + 8 + 10 = 23 金币
```

### 公式 2：变量汇总

| 变量 | 类型 | 默认值 | 安全范围 | 说明 |
|------|------|--------|---------|------|
| `slot_count` | int | 5 | 3-8 | MVP 每张地图 5 个塔位 |
| `preview_alpha` | float | 0.3 | 0.1-0.5 | 范围预览透明度 |
| `highlight_pulse_speed` | float | 2.0 Hz | 1.0-4.0 | 空塔位脉冲高亮频率 |
| `base_upgrade_cost` | int | 5 | 3-15 | 基础升级费用 |
| `place_anim_duration` | float | 0.3s | 0.15-0.6s | 塔放置弹出动画时长 |

---

## Edge Cases

| 编号 | 边界情况 | 处理方式 |
|------|---------|---------|
| EC-01 | 金币不足时点击空塔位 | 打开选择面板但所有塔灰色，底部显示"金币不足! 当前: X, 需要至少: Y" |
| EC-02 | 面板打开时波次开始 | 面板保持打开(游戏不暂停)，玩家仍可边战斗边放置 |
| EC-03 | 快速连点同一空塔位 | 第一次点击打开面板后，后续点击被面板遮挡处理，不会重复触发 |
| EC-04 | 选择塔类型后塔系统创建失败 | 返还金币，提示"放置失败"，slot 保持 EMPTY |
| EC-05 | 鼠标悬停时塔位被其他系统占用 | 理论上不会发生——slot 状态是唯一真理源，放置是原子操作 |
| EC-06 | 范围预览超出屏幕边界 | 正常显示——Godot 的 draw 方法会自动裁剪到视口 |
| EC-07 | 辅助塔预览高亮所有友方目标 | 只高亮在 AuraZone 内的目标，不覆盖整个屏幕 |
| EC-08 | 放置期间游戏暂停/升级面板弹出 | 放置面板被覆盖在升级面板之下，放置操作暂停，面板关闭后恢复 |

---

## Dependencies

### 上游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **防御塔系统** | 硬依赖 | `place_tower(type, pos)`, `upgrade_tower(node, type)`, `get_tower_data(type)` | 创建/升级/查询塔实例 |
| **金币系统** | 硬依赖 | `player_coins`, `deduct_coins()`, `refund_coins()` | 放置/升级费用管理 |
| **地图系统** | 硬依赖 | `get_tower_slots() -> Array[TowerSlotData]` | 获取所有塔位定义 |
| **输入系统** | 软依赖 | 鼠标点击/悬停事件 | 接收玩家放置意图 |

### 下游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **UI 系统** | 软依赖 | `signal tower_placed`, `tower_placement_failed` | 选择面板、范围预览、放置特效 |
| **音频系统** | 软依赖 | 信号触发 | 播放放置/升级音效 |

---

## Tuning Knobs

| 参数 | 默认值 | 范围 | 影响 |
|------|--------|------|------|
| `slot_count` | 5 | 3-8 | <3 策略太单一；>8 地图太满且金币压力大 |
| 塔放置费用（3 种） | 10/15/20 | 5-50 | 第 1 波后约 20 金币，放 1-2 座基础塔合理 |
| `base_upgrade_cost` | 5 | 3-15 | <3 升级太随意失去决策感；>10 玩家升不起 |
| `preview_alpha` | 0.3 | 0.1-0.5 | 太高挡视野；太低看不清范围 |
| `place_anim_duration` | 0.3s | 0.15-0.6s | 太快无感；太慢拖节奏 |

**金币验证**：第 1 波≈10 只怪×2 金=20 金
- 1 座 fish(10) + 1 座 yarn(15) = 25 → 第 1 波不够
- 1 座 fish(10) = 10 → 够，剩 10 金
- 1 座 catnip(20) = 20 → 刚好花光
- 设计上第 1 波后应能放 1 座基础塔，辅助塔需要攒

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-TP-01 | 空塔位高亮 | 鼠标悬停 EMPTY slot | 发光边框出现+"点击放置"文字 |
| AC-TP-02 | 打开选择面板 | 点击 EMPTY slot | 弹出 3 种塔选择面板，显示名称/费用/效果 |
| AC-TP-03 | 金币不足提示 | 金币<10 时点击 EMPTY slot | 面板打开但所有选项灰显，底部显示"金币不足" |
| AC-TP-04 | 放置鱼干发射器 | 金币>=10, 选择 fish, 确认 | 塔出现在 slot 位置，slot→OCCUPIED，扣 10 金 |
| AC-TP-05 | 放置毛线球发射器 | 金币>=15 选择 yarn 确认 | 塔出现，扣 15 金，弹丸带减速属性 |
| AC-TP-06 | 范围预览攻击塔 | 悬停空 slot 并选中 fish | 绿色半透明圆出现，半径=180px |
| AC-TP-07 | 范围预览辅助塔 | 悬停空 slot 并选中 catnip | 金色半透明圆出现，范围内友方目标高亮 |
| AC-TP-08 | 放置失败返还金币 | 塔系统创建失败 | 金币退还，slot 保持 EMPTY，提示错误 |
| AC-TP-09 | 已占塔位不重复放置 | 点击 OCCUPIED slot | 不打开放置面板 |
| AC-TP-10 | 塔升级 | 点击 OCCUPIED slot → 升级 | 塔等级+1，属性提升，金币扣除 |
| AC-TP-11 | 满级塔不显示升级 | 点击 level=3 的塔 | 面板显示"已满级"，无升级按钮 |
| AC-TP-12 | tower_placed 信号 | 监听信号 | 每次成功放置恰好 1 次，参数(slot_id, tower_type) 正确 |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-TP-I01 | 塔位+金币系统 | 放置鱼干塔 | 金币-10, HUD 实时更新 |
| AC-TP-I02 | 塔位+塔系统 | 放置后检查场景树 | 塔节点存在且位置正确，在"tower"Group 中 |
| AC-TP-I03 | 塔位+地图系统 | 地图加载后检查 | 所有 slot 位置正确，数量=地图定义的 slot_count |
| AC-TP-I04 | 塔位+UI 系统 | 悬停空 slot | 范围预览圆出现，大小匹配塔类型射程 |
