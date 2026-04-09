# Systems Index: 喵族幸存者 (Meow Survivors)

> **Status**: Draft  
> **Created**: 2026-04-01  
> **Last Updated**: 2026-04-09  
> **Source Concept**: design/concept/game-concept.md

---

## Overview

《喵族幸存者》当前被定义为一款**塔防主导的波次生存游戏**。  
核心循环不是“角色一个人越打越强”，而是：

**围绕固定塔位建立防线 → 角色移动补位与支援 → 敌人按波次推进 → 经验升级强化角色与塔阵 → 防线逐步成型**

系统设计的目标是支撑以下三件事：

- **塔阵构筑是真正的主决策层**
- **角色成长与塔成长互相放大**
- **MVP 以 4-8 分钟短局验证核心循环**

当前共识别 22 个系统，其中 20 个属于 MVP 或 MVP 周边设计范围；但在优先级表达上，当前项目应明确以**塔、防线、波次、经验升级**为主轴，而不是以角色 auto-fire 为主轴。

设计支柱约束：

- **可爱即正义**：所有玩家可见系统都必须保持温暖、清晰、讨喜
- **成长的爽感**：升级必须带来明显的角色或防线变化
- **策略有深度**：塔位、升级、补位都必须形成真实权衡

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | 输入系统 | Core | MVP | Approved | design/gdd/input-system.md | — |
| 2 | 碰撞检测系统 | Core | MVP | Approved | design/gdd/collision-detection-system.md | — |
| 3 | 伤害计算系统 | Core | MVP | Approved | design/gdd/damage-calculation-system.md | — |
| 4 | 难度曲线系统 | Meta | MVP | Approved | design/gdd/difficulty-curve-system.md | — |
| 5 | 地图系统 | Meta | MVP | Approved | design/gdd/map-system.md | — |
| 6 | 升级池系统 | Progression | MVP | Approved | design/gdd/upgrade-pool-system.md | — |
| 7 | 移动系统 | Core | MVP | Approved | design/gdd/movement-system.md | 输入系统, 地图系统 |
| 8 | 生命值系统 | Core | MVP | Approved | design/gdd/health-system.md | 碰撞检测系统 |
| 9 | 目标选择系统 | Core | MVP | Approved | design/gdd/target-selection-system.md | 碰撞检测系统 |
| 10 | 经验系统 | Progression | MVP | Designed | design/gdd/xp-system.md | 碰撞检测系统 |
| 11 | 金币系统 | Economy | MVP | Designed | design/gdd/coin-system.md | 碰撞检测系统 |
| 12 | 防御塔系统 | Gameplay | MVP | Designed | design/gdd/tower-system.md | 目标选择, 伤害计算, 生命值 |
| 13 | 塔位放置系统 | Gameplay | MVP | Designed | design/gdd/tower-placement-system.md | 地图系统, 防御塔系统, 金币系统 |
| 14 | 波次系统 | Gameplay | MVP | Designed | design/gdd/wave-system.md | 敌人生成, 难度曲线 |
| 15 | 敌人系统 | Gameplay | MVP | Designed | design/gdd/enemy-system.md | 生命值, 伤害计算, 移动系统 |
| 16 | 敌人生成系统 | Gameplay | MVP | Designed | design/gdd/enemy-spawn-system.md | 敌人系统, 波次系统 |
| 17 | 自动攻击系统 | Gameplay | MVP | Designed | design/gdd/auto-attack-system.md | 目标选择, 生命值, 伤害计算 |
| 18 | 升级选择系统 | Progression | MVP | Designed | design/gdd/upgrade-selection-system.md | 经验系统, 升级池系统 |
| 19 | UI系统 | UI | MVP | Designed | design/gdd/ui-system.md | 生命值, 经验, 金币, 波次 |
| 20 | 结算系统 | UI | MVP | Designed | design/gdd/settlement-system.md | 波次, 金币, 经验 |
| 21 | 存档系统 | Persistence | v1.0 | Not Started | — | — |
| 22 | 解锁系统 | Progression | v1.0 | Not Started | — | 存档系统, 金币系统 |

---

## Categories

| Category | Description | Systems in this project |
|----------|-------------|-------------------------|
| **Core** | 为战斗、碰撞、目标选择、角色控制提供基础能力 | 输入、碰撞检测、伤害计算、移动、生命值、目标选择 |
| **Gameplay** | 直接决定一局手感与防线结构的系统 | 防御塔、塔位放置、波次、敌人、敌人生成、自动攻击 |
| **Progression** | 负责局内成长与选择的系统 | 经验、升级池、升级选择、解锁 |
| **Economy** | 负责资源流转 | 金币 |
| **Persistence** | 负责长期保存与解锁 | 存档 |
| **UI** | 玩家感知与操作界面 | UI、结算 |
| **Meta** | 对局外或高层配置系统 | 难度曲线、地图 |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | 必须支撑“塔阵构筑 + 移动补位 + 经验成长 + 波次推进”的核心循环 | First playable prototype | Design FIRST |
| **v1.0** | 在 MVP 验证成立后，再补齐长期留存、解锁与扩展内容 | v1.0 release | Design after MVP complete |

---

## Dependency Map

### Foundation Layer

1. **输入系统**：接收玩家操作
2. **碰撞检测系统**：提供伤害、拾取、命中等检测能力
3. **伤害计算系统**：统一计算伤害、buff、效果修正
4. **难度曲线系统**：定义敌人与波次强度曲线
5. **地图系统**：定义地图结构与塔位分布
6. **升级池系统**：定义可选升级内容
7. **存档系统**：v1.0 的长期持久化基础

### Combat Core Layer

1. **移动系统**：驱动角色补位与走位
2. **生命值系统**：驱动角色、敌人、塔相关伤害结果
3. **目标选择系统**：支撑角色和塔的目标选择
4. **经验系统**：提供主要成长入口
5. **金币系统**：提供布防成本与经济节奏

### Defense Layer

1. **防御塔系统**：当前主轴系统，定义塔的运行逻辑与联动
2. **塔位放置系统**：将地图塔位与塔系统连接起来
3. **波次系统**：调度每波节奏与敌潮推进
4. **敌人系统**：定义敌人行为和对防线的压力
5. **敌人生成系统**：将敌人节奏落地到实际场景
6. **自动攻击系统**：角色支援输出系统，不再作为唯一核心主角系统
7. **升级选择系统**：让经验成长转化为局内决策

### Presentation Layer

1. **UI系统**：显示血量、经验、金币、波次、塔位与升级界面
2. **结算系统**：提供一局结束后的反馈与重开动机

---

## Recommended Design Order

当前项目的推荐设计顺序，应该围绕“先把塔防主轴站住”来排：

| Order | System | Why it matters first |
|-------|--------|----------------------|
| 1 | 地图系统 | 先决定塔位数量与布局，才能决定防线骨架 |
| 2 | 防御塔系统 | 明确塔的主定位，决定整个项目的玩法重心 |
| 3 | 塔位放置系统 | 把地图与塔系统连起来，形成可操作的布防层 |
| 4 | 波次系统 | 建立局内节奏，验证短局是否成立 |
| 5 | 敌人系统 | 决定防线面对的压力形态 |
| 6 | 敌人生成系统 | 把波次与压力实际落到场景中 |
| 7 | 经验系统 | 建立局内成长主轴 |
| 8 | 升级选择系统 | 让成长进入策略决策 |
| 9 | 自动攻击系统 | 明确角色如何支援防线 |
| 10 | UI系统 | 把所有关键决策信息清晰地展示给玩家 |

说明：

- 这不代表底层系统不重要，而是说明**设计关注顺序**应围绕主玩法展开
- 当前版本不建议再把 auto-fire 当作第一玩法支柱来驱动全局设计

---

## Circular Dependencies

- 当前设计目标仍然是单向依赖，不希望形成“角色成长必须先定义塔成长、塔成长又必须先定义角色成长”的循环锁死
- 角色与塔的联动是玩法层联动，不应变成文档层的循环依赖混乱

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| 防御塔系统 | Design | 如果塔没有真正成为主角，整个项目定位会重新滑回传统幸存者 | 先用原型验证“塔阵是否真的影响胜负” |
| 波次系统 | Design | 如果波次停顿太重或太轻，短局节奏都会失衡 | 重点验证 4-8 分钟局时和波次呼吸感 |
| 升级选择系统 | Design | 如果升级只强化角色，会削弱塔防主导感 | 限制升级内容，让其明确服务防线成长 |
| 地图系统 | Design | 塔位数量和位置如果设计失误，会直接摧毁策略深度 | 先验证 3-5 个关键塔位是否成立 |
| 碰撞检测系统 | Technical | 多敌人、多弹丸、多塔同屏性能敏感 | 提前压测与约束弹丸数量 |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 22 |
| MVP-facing systems | 20 |
| Current design focus | Tower-first short-run prototype |
| Long-term systems intentionally deprioritized | Save / Unlock / Heavy Meta |

---

## Current Interpretation Notes

为避免后续协作再次偏回旧方向，这里明确记录当前解释：

1. **塔防主导**
塔与塔位系统是当前玩法主轴，角色只承担支援、补位和运营职责。

2. **经验升级是主要成长入口**
局内成长优先通过经验升级驱动；波次结束可以有短整理，但不应再次成为主升级入口。

3. **控制不是独立主塔类别**
控制优先作为输出塔的效果分支、升级分支或弹丸属性存在。

4. **MVP 先做短局**
当前目标不是做长局留存，而是先验证 4-8 分钟是否好玩。

5. **先不做重 meta**
解锁、存档、永久成长保留为长期方向，但不应反向干扰当前核心循环判断。

---

## Next Steps

- [x] 重写 `design/concept/game-concept.md` 以匹配塔防主导方向
- [x] 重写 `design/gdd/tower-system.md` 以匹配“输出塔 + 辅助塔”结构
- [ ] 重写 `design/gdd/wave-system.md`，使其服务短局与经验升级主轴
- [ ] 重写 `design/gdd/ui-system.md`，让 UI 更明确服务塔阵信息和升级决策
- [ ] 检查 `design/gdd/upgrade-selection-system.md` 是否仍然过度偏向角色成长
- [ ] 用 Godot 原型验证：塔阵是否真的比角色本体更影响胜负
