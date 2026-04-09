# Document Reorganization Plan

本文件定义 Meow Survivors 当前文档体系的整理目标、迁移范围与执行顺序。

## Why Reorganize

当前仓库中的文档存在三类内容混放的问题：

- 项目自身设计文档
- 项目协作与流程文档
- Claude Code Game Studios 模板和参考文档

这会带来几个问题：

- 项目主文档与模板参考文档边界不清
- 设计文档和评审文档放在同一层级
- Godot 项目实际使用的规则与模板规则混杂
- 后续查找“哪个文件是当前项目权威来源”成本较高

本次整理目标不是大规模重写，而是建立清晰分类，让设计、实现、流程、参考资料各自归位。

## Target Structure

```text
design/
  gdd/                  # 系统设计文档
  concept/              # 游戏概念、核心循环、设计支柱
  reviews/              # 设计评审结果

docs/
  process/              # 协作流程、开发流程、整理计划
  architecture/         # 架构决策、模块边界、重构计划
  reference/
    engine/
      godot/            # 本项目使用的 Godot 参考资料
    examples/           # 示例会话、参考范例
    archive/            # 历史归档或暂不使用资料

production/
  gate-checks/          # 阶段检查记录
  session-logs/         # 过程日志
  session-state/        # 临时状态

.Codex/docs/            # 项目级协作与代码规范入口
.claude/                # 模板系统与原始参考，不作为项目主规则入口
```

## Classification Rules

### `design/`

用于表达“游戏应该如何工作”。

应放入：

- 游戏概念
- 系统设计
- 数值规则
- 玩家体验目标
- 设计评审结果

不应放入：

- 协作规则
- 提交流程
- 通用模板说明
- 引擎 API 参考

### `docs/process/`

用于表达“项目如何协作与推进”。

应放入：

- 协作原则
- 开发流程
- 文档整理计划
- 工作协议

### `docs/architecture/`

用于表达“项目为什么这样实现”。

应放入：

- ADR
- 模块边界说明
- 重构计划
- 技术选型说明

### `docs/reference/`

用于表达“项目查阅时会参考什么”。

应放入：

- Godot 版本参考
- 参考示例
- 不直接参与当前实现决策的历史材料

### `production/`

用于表达“项目推进过程中生成的记录”。

应放入：

- gate check
- session logs
- 阶段性检查记录

不应放入长期设计规范或项目总规则。

## Current To Target Mapping

### Design Documents

保留在原位：

- `design/gdd/auto-attack-system.md`
- `design/gdd/coin-system.md`
- `design/gdd/collision-detection-system.md`
- `design/gdd/damage-calculation-system.md`
- `design/gdd/difficulty-curve-system.md`
- `design/gdd/enemy-spawn-system.md`
- `design/gdd/enemy-system.md`
- `design/gdd/health-system.md`
- `design/gdd/input-system.md`
- `design/gdd/map-system.md`
- `design/gdd/movement-system.md`
- `design/gdd/settlement-system.md`
- `design/gdd/systems-index.md`
- `design/gdd/target-selection-system.md`
- `design/gdd/tower-placement-system.md`
- `design/gdd/tower-system.md`
- `design/gdd/ui-system.md`
- `design/gdd/upgrade-pool-system.md`
- `design/gdd/upgrade-selection-system.md`
- `design/gdd/wave-system.md`
- `design/gdd/xp-system.md`

建议迁移：

- `design/gdd/game-concept.md` -> `design/concept/game-concept.md`
- `design/gdd/design-review-game-concept.md` -> `design/reviews/design-review-game-concept.md`

理由：

- `game-concept.md` 属于概念层，不属于单个系统 GDD
- `design-review-game-concept.md` 属于评审结果，不属于系统设计正文

### Process Documents

建议迁移：

- `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` -> `docs/process/COLLABORATIVE-DESIGN-PRINCIPLE.md`
- `docs/WORKFLOW-GUIDE.md` -> `docs/process/WORKFLOW-GUIDE.md`

建议新增：

- `docs/process/document-reorganization-plan.md`
- `docs/process/document-map.md`

### Architecture Documents

建议迁移：

- `docs/refactor-checklist.md` -> `docs/architecture/refactor-checklist.md`

后续应新增：

- `docs/architecture/README.md`
- `docs/architecture/adr/`

### Reference Documents

建议迁移：

- `docs/examples/README.md` -> `docs/reference/examples/README.md`
- `docs/examples/reverse-document-workflow-example.md` -> `docs/reference/examples/reverse-document-workflow-example.md`
- `docs/examples/session-design-crafting-system.md` -> `docs/reference/examples/session-design-crafting-system.md`
- `docs/examples/session-implement-combat-damage.md` -> `docs/reference/examples/session-implement-combat-damage.md`
- `docs/examples/session-scope-crisis-decision.md` -> `docs/reference/examples/session-scope-crisis-decision.md`

- `docs/engine-reference/README.md` -> `docs/reference/engine/README.md`
- `docs/engine-reference/godot/**` -> `docs/reference/engine/godot/**`

### Non-Project Engine References

当前项目是 Godot 项目，因此以下目录不应继续占据主文档位置：

- `docs/engine-reference/unity/**`
- `docs/engine-reference/unreal/**`

建议处理方式：

方案 A，推荐：

- 保留原内容，但迁移到 `docs/reference/archive/engines/`

方案 B：

- 保留在 `.claude/` 模板体系中，不再作为项目文档的一部分使用

本项目更推荐方案 A，如果你希望仓库主文档区尽量纯净，则可以后续再执行方案 B。

## Root-Level Document Review

### `AGENTS.md`

状态：

- 已改为项目版

作用：

- 项目总入口

### `CONTRIBUTING.md`

状态：

- 已新增项目版

作用：

- 提交流程、PR 规范、验证要求

### `CLAUDE.md`

状态：

- 仍偏模板版

问题：

- 仍引用 `.claude/docs/*`
- 仍含 `[CHOOSE: ...]` 模板占位

建议：

- 后续重写为项目版，和 `AGENTS.md` 分工明确

### `README-project.md`

状态：

- 更接近项目说明而不是模板说明

建议：

二选一：

- 方案 A：升级为项目正式 README，并替换当前根目录 `README.md`
- 方案 B：迁移到 `design/concept/project-overview.md`

推荐方案 A。

### `README.md`

状态：

- 仍主要是 Claude Code Game Studios 模板说明

建议：

- 如果仓库目标是游戏项目本身，应改成项目 README
- 如果仓库目标是“模板 + 游戏实例混合”，则应明确双层结构

### Temporary Root Files

以下文件不应长期留在根目录：

- `tmp_refactor.py`
- `tmp_refactor2.py`
- `tmp_refactor3.py`

建议：

- 若仍有用，迁移到 `tools/tmp/`
- 若已失效，删除

## Migration Principles

执行迁移时应遵守：

1. 先建目标目录，再移动文件
2. 每次只迁移一类文档
3. 迁移后立刻修复引用路径
4. 不在同一步中同时重写内容和迁移位置
5. 先移动高价值项目文档，再处理模板和归档内容

## Recommended Execution Order

### Phase 1: Establish Structure

新建以下目录：

- `design/concept/`
- `design/reviews/`
- `docs/process/`
- `docs/architecture/`
- `docs/reference/`
- `docs/reference/engine/`
- `docs/reference/examples/`
- `docs/reference/archive/`

### Phase 2: Move Project-Owned Docs

先迁移：

- `design/gdd/game-concept.md`
- `design/gdd/design-review-game-concept.md`
- `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md`
- `docs/WORKFLOW-GUIDE.md`
- `docs/refactor-checklist.md`

### Phase 3: Move Reference Docs

再迁移：

- `docs/examples/**`
- `docs/engine-reference/godot/**`

### Phase 4: Archive Non-Project Engine Docs

最后处理：

- `docs/engine-reference/unity/**`
- `docs/engine-reference/unreal/**`

### Phase 5: Update Entrypoints

完成迁移后更新：

- `AGENTS.md`
- `CONTRIBUTING.md`
- `CLAUDE.md`
- `README-project.md`
- 相关设计文档之间的交叉引用

## Definition Of Done

整理完成后，应满足：

- 能明确区分项目文档和模板文档
- 游戏概念、系统设计、设计评审不再混在同一目录
- 协作流程文档、架构文档、参考文档边界清晰
- `AGENTS.md` 中的关键入口路径都真实存在
- 查找“当前项目的权威文档”不需要依赖模板背景知识

## Next Suggested Step

下一步建议优先执行：

1. 创建目标目录
2. 迁移 `game-concept.md` 与 `design-review-game-concept.md`
3. 迁移 `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` 与 `docs/refactor-checklist.md`
4. 修复入口文件的路径引用

这是最低风险、收益最高的一轮整理。
