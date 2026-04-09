# Contributing

本文件说明 Meow Survivors 项目的提交、分支、合并与验证约定。

## Before You Change Anything

开始修改前，请先确认：

- 是否存在对应的 `design/gdd/*.md`
- 是否会影响多个系统
- 是否需要同步更新文档
- 是否只是原型临时改动

如果改动影响玩法行为，应在说明中标出对应设计文档。

## Branching

建议使用短生命周期功能分支开发，再合并回 `main`。

推荐命名：

- `feat/<topic>`
- `fix/<topic>`
- `refactor/<topic>`
- `docs/<topic>`

示例：

- `feat/wave-balance`
- `fix/enemy-hitbox`
- `refactor/main-game-split`
- `docs/project-rules`

## Commit Convention

建议使用 Conventional Commits：

- `feat:`
- `fix:`
- `refactor:`
- `docs:`
- `chore:`
- `test:`

示例：

- `feat: add tower manager for placement flow`
- `fix: prevent enemy hitbox from damaging twice`
- `refactor: split spawn logic out of main game`
- `docs: add project-specific agent rules`

## Pull Request Expectations

每个 PR 至少应说明：

- 改动目的
- 影响范围
- 对应的 GDD 或设计来源
- 验证方式
- 是否包含文档更新

建议模板：

### Summary

简述这次改动做了什么。

### Design Source

对应的 GDD、设计讨论或架构决策。

### Files Changed

列出关键文件和职责变化。

### Validation

说明如何验证：

- 主场景运行
- 手动复现步骤
- 截图
- 数值校验
- 测试结果

### Risks

说明潜在风险、已知限制或后续待做项。

## Validation Checklist

合并前至少确认：

- Godot 项目可正常打开
- `scenes/game/main_game.tscn` 可运行
- 没有新增明显报错
- 新功能与现有流程兼容
- 必要时同步更新设计文档或规则文档

## Documentation Sync Rules

出现以下情况时，应该同步更新文档：

- 新增系统或显著改变系统边界
- 修改关键玩法规则
- 调整数值逻辑来源
- 改变目录结构或协作流程
- 新增长期约束或开发规范

通常涉及更新：

- `design/gdd/*.md`
- `docs/architecture/*.md`
- `AGENTS.md`
- `.Codex/docs/coding-standards.md`

## Refactoring Rules

重构类改动应特别说明：

- 为什么要重构
- 是否改变行为
- 是否只是搬移职责
- 哪些地方以后仍需继续拆分

对于 `main_game.gd` 相关重构，优先目标应是减耦和分责，而不是纯形式整理。

## Temporary Prototype Code

项目当前处于原型实现阶段，允许存在临时代码，但提交时应尽量说明：

- 这是临时方案还是正式方案
- 未来会迁移到哪里
- 是否故意先硬编码以验证手感

如果临时实现会长期保留，就不应继续当作“临时”处理。

## What Not To Do

- 没有设计依据就修改核心玩法
- 不说明验证方式就提交较大改动
- 把多个无关主题混进同一个 PR
- 在没有说明的情况下做大范围结构迁移
- 让文档与实现长期失配
