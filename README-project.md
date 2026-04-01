# 喵族幸存者 (Meow Survivors)

可爱猫咪塔防幸存者游戏 — 用 Claude Code Game Studios 开发中

## 游戏简介

**类型**: 幸存者类 + 塔防 (Auto-fire + Tower Placement)
**平台**: Steam (PC)
**开发者**: 单人
**引擎**: Godot 4.6

玩家控制猫咪英雄在战场上移动，自动攻击敌人，放置防御塔辅助防守。通过选择升级构建强力build，在波次递增的敌潮中存活并变强。

## 核心玩法

```
移动定位 → 自动攻击 → 击杀敌人 → 获得经验 → 选择升级 → Build变强 → 更难敌人 → 循环
```

- 🐱 控制可爱的猫咪英雄
- ⚔️ 自动攻击涌来的敌人
- 🗼 放置防御塔辅助输出
- 📈 每波结束选择升级
- 🏆 在无尽敌潮中存活

## 设计支柱

1. **可爱即正义** — 所有视觉元素温暖可爱
2. **成长的爽感** — 频繁感受变强
3. **策略有深度** — build选择有意义

## 项目状态

- [x] 游戏概念设计
- [x] 引擎配置 (Godot 4.6)
- [ ] 系统拆分
- [ ] 核心原型
- [ ] MVP开发

## 开发文档

- [游戏概念](design/gdd/game-concept.md) — 完整设计文档
- [当前状态](production/session-state/active.md) — 开发进度
- [技术偏好](.claude/docs/technical-preferences.md) — 代码规范

## 开始开发

1. 克隆仓库
2. 安装 [Godot 4.6](https://godotengine.org/download)
3. 运行 Claude Code: `claude`
4. 读取 `production/session-state/active.md` 恢复上下文
5. 根据状态继续开发

## 技术栈

| 项目 | 值 |
|-----|---|
| 引擎 | Godot 4.6 |
| 语言 | GDScript |
| 目标帧率 | 60 FPS |
| 命名规范 | PascalCase类, snake_case变量 |

## 许可证

MIT License
