# Coding Standards

本文件定义 Meow Survivors 的项目级代码规范。
这是 Godot 4.6 + GDScript 项目规范，不是通用模板。

## Core Principles

- 代码应服务于已有 GDD，而不是绕过 GDD 自行定义玩法。
- 新功能优先降低耦合，而不是继续扩大大脚本职责。
- 玩法逻辑、UI 展示、流程编排、数据配置应尽量分层。
- 允许渐进式重构，不要求一次性完美架构。

## Naming Conventions

### GDScript

- `class_name`: PascalCase
- 文件名: `snake_case.gd`
- 变量名: `snake_case`
- 函数名: `snake_case`
- 常量名: `UPPER_SNAKE_CASE`
- 信号名: `snake_case`
- 私有辅助字段: 允许 `_name` 风格

### Godot Scenes

- 场景文件名建议与主职责一致
- 可复用实体场景应保持单一职责
- 场景根节点命名应稳定清晰，避免后续脚本依赖混乱

## File Header Expectations

新增或重要脚本建议在文件头注明：

- 脚本职责
- 对应 GDD
- 是否属于临时原型实现

示例：

```gdscript
## Enemy movement and damage handling
## GDD: design/gdd/enemy-system.md
## Notes: MVP prototype implementation
```

## Directory Responsibilities

### `src/core/`

放通用组件、基础能力、可复用系统。

例如：

- `HealthComponent`
- `HitboxComponent`
- `HurtboxComponent`
- 通用 movement / target system

要求：

- 不依赖具体 UI
- 不绑死单一玩法场景
- 尽量可复用

### `src/data/`

放配置、资源加载、数据访问、全局数据脚本。

要求：

- 数据结构清晰
- 避免把复杂玩法流程塞进数据层
- 全局脚本只保留真正的全局状态与统一接口

### `src/game/`

放总控和编排层。

例如：

- `MainGame`
- `WaveManager`
- `SpawnManager`
- `TowerManager`

要求：

- 负责 orchestration，不负责承载所有细节实现
- 优先调用组件/manager，而不是自己实现全部玩法
- 新代码应推动 `main_game.gd` 逐步减负

### `src/gameplay/`

放具体玩法实体与规则执行者。

例如：

- `EnemyBase`
- `Projectile`
- `AutoAttackSystem`

要求：

- 不直接拥有 UI
- 不依赖特定 HUD 结构
- 优先通过信号或回调与上层通信

### `src/ui/`

放 UI 展示、交互、面板逻辑。

要求：

- 不直接拥有核心游戏状态
- 不直接定义玩法规则
- 所有展示数据应来自明确的数据源或信号

## Architecture Rules

- 新功能优先放入正确模块，不要图省事继续堆进 `main_game.gd`。
- 单个脚本如果同时处理输入、生成、伤害、UI、结算，应视为待拆分对象。
- 核心玩法逻辑优先与显示逻辑解耦。
- 跨系统通信优先使用信号、显式接口或 manager 协作。
- 避免使用脆弱的深层节点路径做长期耦合。

## Data And Balance Rules

- 可调数值应尽量数据驱动。
- 临时原型允许少量硬编码，但必须满足至少一条：
  - 很快会迁移到数据层
  - 文件头明确标注为原型
  - 用户已明确接受该临时做法
- 敌人、塔、防御、升级、波次参数优先从数据层或集中配置读取。
- 改动数值时，应说明对应哪个 GDD 或设计意图。

## Godot-Specific Rules

- 运行时高频逻辑避免无意义分配。
- 不要在热路径中滥用字符串查找和重复节点扫描。
- 尽量使用强类型标注提升可读性与安全性。
- 通过 `_ready()` 建立依赖时，要确保节点缺失时有可理解的失败方式。
- 编辑器生成的 `.uid` 文件应正常纳入版本控制。

## Logging And Debugging

- 原型阶段允许有限调试输出。
- 持续保留在主流程里的调试输出需要有意义，避免噪音。
- 发布前应收敛临时 `print`/`print_rich` 调试信息。

## Refactoring Direction

本项目当前的明确重构方向：

- 从 `MainGame` 中持续拆出 manager 和 component
- 将 UI 构建与核心玩法推进分离
- 将塔、防御、波次、反馈等职责继续模块化
- 将硬编码玩法数据逐步迁移到数据层

新提交不得反向扩大耦合。

## Tests And Validation

当前项目可接受“轻测试 + 可运行验证”的方式推进，但至少应提供一种验证方式：

- 主场景运行验证
- 明确复现步骤
- 截图或录像验证 UI
- 数值计算的手工校验
- 后续补充 GUT 测试

如果没有自动化测试，提交说明中必须写清楚如何手动验证。
