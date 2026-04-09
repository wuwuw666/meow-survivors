# Design Review: 喵族幸存者 (Meow Survivors)

*Review Date: 2026-04-01*
*Reviewer: Claude Code*
*Document: game-concept.md*

---

## Completeness: 6/8 sections

| 章节 | 状态 |
|------|------|
| ✅ Overview | Elevator Pitch — 清晰，10秒测试通过 |
| ✅ Player Fantasy | Core Fantasy — 情感定位准确 |
| ❌ Detailed Rules | 缺失 — 缺少具体机制定义 |
| ❌ Formulas | 缺失 — 没有数学公式 |
| ❌ Edge Cases | 缺失 — 边界情况未定义 |
| ⚠️ Dependencies | 隐含在 Core Mechanics，但未结构化 |
| ⚠️ Tuning Knobs | 隐含在 Open Questions，未结构化 |
| ⚠️ Acceptance Criteria | 隐含在 MVP Definition，未结构化 |

---

## Verdict: NEEDS REVISION

### 缺失的关键机制定义

| 缺失项 | 影响 |
|--------|------|
| 猫咪移动方式 | WASD？鼠标点击？摇杆？ |
| 自动攻击规则 | 攻击范围？目标选择逻辑？攻击频率？ |
| 敌人移动路径 | 固定路线？追向玩家？随机？ |
| 塔位交互 | 何时可以放塔？塔是否可移除？ |
| 升级选择触发 | 经验满触发？每波结束固定触发？ |
| 胜利/失败条件 | 血量归零失败？通关第N波算胜利？ |

### 高优先级补充项

1. **Detailed Rules** — 补充移动、攻击、塔位、升级机制
2. **Formulas** — 补充经验获取、敌人成长、升级效果公式

### 中优先级补充项

3. **Edge Cases** — 玩家被包围、所有塔位占满等
4. **Tuning Knobs** — 敌人密度、升级频率等参数

---

## 下一步

1. 补充关键机制定义（简要即可）
2. 运行 `/map-systems` 拆分系统
3. 运行 `/prototype 移动攻击` 原型验证
