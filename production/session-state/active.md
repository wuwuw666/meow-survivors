# Active Session State

*Last Updated: 2026-04-01*
*Project: 喵族幸存者 (Meow Survivors)*

---

## 项目进度

### ✅ 已完成
- [x] 头脑风暴完成 — 游戏概念确定
- [x] 引擎配置完成 — Godot 4.6 (本地路径: F:\godot)

### 📋 当前状态
- **下一步**: 设计文档审查 + 系统拆分

---

## 游戏概念摘要

### 《喵族幸存者》(Meow Survivors)

**类型**: 幸存者类 + 塔防 (Auto-fire + Tower Placement)
**平台**: Steam (PC)
**开发者**: 单人
**预估规模**: 中等 (3-6个月)

**核心玩法**:
- 控制猫咪英雄在战场移动
- 自动攻击敌人
- 放置防御塔辅助防守
- 波次系统 + 升级选择
- Build驱动的成长循环

**设计支柱**:
1. 🐱 可爱即正义 — 所有视觉元素必须可爱温暖
2. 📈 成长的爽感 — 频繁感受到变强
3. 🧠 策略有深度 — build选择有意义

**目标玩家**: Achievers + Explorers (成就者/探索者)
**参考游戏**: 又一个僵尸幸存者、植物大战僵尸、吸血鬼幸存者

---

## 技术栈

| 项目 | 值 |
|-----|---|
| **引擎** | Godot 4.6 stable |
| **本地路径** | F:\godot\Godot_v4.6-stable_win64.exe |
| **语言** | GDScript (主), C++ GDExtension (性能) |
| **目标帧率** | 60 FPS |
| **最大同屏敌人** | 50-100 |
| **命名规范** | PascalCase类, snake_case变量 |

---

## 核心文件位置

| 文件 | 路径 |
|-----|------|
| 游戏概念文档 | `design/gdd/game-concept.md` |
| 技术偏好 | `.claude/docs/technical-preferences.md` |
| 引擎版本参考 | `docs/engine-reference/godot/VERSION.md` |
| 主配置 | `CLAUDE.md` |

---

## 下一步计划

1. `/design-review design/gdd/game-concept.md` — 验证文档完整性
2. `/map-systems` — 拆分为系统，规划开发顺序
3. `/prototype 移动攻击` — 原型验证核心玩法
4. `/sprint-plan new` — 规划第一个开发冲刺

---

## MVP 定义

**核心假设**: 玩家觉得"移动 + 自动攻击 + 升级选择 + 塔位放置"的循环有趣。

**MVP内容**:
- 1只猫咪英雄
- 3种防御塔 (攻击/控制/辅助)
- 5种敌人
- 10个升级选项
- 1张地图
- 10波敌人
- 基本UI

---

## 已知风险

- Build平衡性 (太简或太难)
- 大量敌人同屏性能
- 单人开发内容量管理

---

## 开发限制

- 单人开发
- 目标平台: Steam PC
- 付费游戏模式
- 不做: 复杂操作、黑暗画风、多人PVP
