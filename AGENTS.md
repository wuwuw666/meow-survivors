# Meow Survivors Agent Guide

本文件是本项目的人类协作者与 Codex/代理协作者的总入口。

## Project Identity

- Project: Meow Survivors
- Genre: 幸存者 + 塔防混合玩法
- Engine: Godot 4.6
- Language: GDScript
- Current Stage: MVP 原型实现中
- Main Scene: `res://scenes/game/main_game.tscn`

## Source Of Truth

修改任何功能前，按以下优先级读取上下文：

1. `design/gdd/*.md`
2. `docs/architecture/*.md`
3. `.Codex/docs/*.md`
4. `CONTRIBUTING.md`

规则说明：
- 玩法规则、系统边界、数值意图，以 `design/gdd/*.md` 为准。
- 技术实现决策、模块边界、重构方向，以 `docs/architecture/*.md` 为准。
- 协作方式、代码规范、目录约定，以本文件和 `.Codex/docs/*.md` 为准。
- 如果文档与实现不一致，不要直接假设代码一定正确。先标记差异，再和用户确认是修文档还是修实现。

## Project Structure

### Runtime

- `src/core/`: 通用基础组件与低耦合系统
- `src/data/`: 数据访问、配置载入、全局数据脚本
- `src/game/`: 游戏总控、流程编排、manager
- `src/gameplay/`: 敌人、弹丸、攻击等具体玩法实体
- `src/ui/`: UI 逻辑与展示脚本
- `scenes/`: Godot 场景文件
- `assets/`: 美术、音频、配置数据等资源

### Design And Docs

- `design/gdd/`: 系统设计文档，当前项目的核心设计来源
- `design/concept/`: 游戏概念、设计支柱、体验目标
- `design/reviews/`: 设计评审记录
- `docs/process/`: 协作流程、开发流程、项目规则说明
- `docs/architecture/`: 架构决策、模块边界、重构计划
- `docs/reference/`: 参考资料、外部资料整理
- `production/`: 里程碑、gate check、session log 等生产管理内容

## Current Codebase Reality

当前代码库不是从零开始的理想结构，协作者必须基于现状工作：

- `main_game.gd` 仍承担较多总控职责。
- 项目正在逐步将大脚本拆分到 `src/game/`、`src/core/`、`src/gameplay/`。
- 新功能默认不要继续把无关职责堆进 `main_game.gd`。
- 重构应以减耦、提取 manager、明确信号边界为主，而不是大范围一次性重写。

## Collaboration Rules

本项目采用用户驱动协作，不采用无确认的自主执行。

默认流程：

1. 先读相关设计文档和代码
2. 给出方案或草稿
3. 获得用户确认
4. 再写入文件或修改代码
5. 修改后说明影响范围与验证方式

必须遵守：

- 在使用写入或编辑工具前，先明确说明要改哪些文件。
- 多文件修改要先给出变更范围摘要。
- 没有用户明确要求时，不提交 commit，不创建 PR。
- 遇到设计文档和代码冲突时，先暂停并说明冲突点。

## Design Workflow

涉及玩法、数值、系统规则的工作时：

1. 先查 `design/gdd/` 对应文档
2. 如果已有文档，先遵循文档实现
3. 如果实现需要偏离文档，先记录差异
4. 如果文档缺失，再补设计草稿
5. 设计确认后再进入实现

## Implementation Workflow

涉及代码实现时：

- 先确认对应 GDD 或明确说明“当前没有对应 GDD”
- 新增逻辑优先放入正确模块，而不是就近塞进现有大文件
- UI 变化不要直接侵入核心玩法逻辑
- 数值与敌人参数优先走数据层
- 新 manager 或 component 要解释职责边界

## Godot-Specific Expectations

- 保持 scene/script 对应关系清晰。
- 避免通过脆弱的深层节点路径耦合系统。
- 优先使用信号、组件、manager 分离职责。
- 对运行时频繁调用逻辑，注意 Godot 4.6 下的性能与分配开销。
- 不直接手改 `project.godot` 的复杂配置，除非明确知道影响范围。

## Required Project Docs

本项目长期维护以下核心入口文件：

- `AGENTS.md`
- `.Codex/docs/coding-standards.md`
- `docs/process/COLLABORATIVE-DESIGN-PRINCIPLE.md`
- `CONTRIBUTING.md`

如果这些文件与当前项目实际情况不符，应优先更新。
