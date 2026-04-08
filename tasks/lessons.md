# Lessons Learned

## UI 系统 (UI System)

### 响应式 UI 适配 (Responsive UI)

- **锚点优于绝对坐标**: 在 Godot 中开发 UI 时，严禁使用像素绝对坐标定位。必须使用 `Anchors` 配合 `Margins`（或组件内部的 `Container` 自动布局），以确保在窗口缩放时布局不塌陷。
- **CanvasItems 模式**: 对于大多数 2D 游戏，`display/window/stretch/mode = "canvas_items"` 是平衡画质与缩放性能的最优解。
- **多比例考虑**: 即使初期只考虑 16:9，也应从规则层面强制要求居中锚定和边缘锚定，以应对未来可能的 21:9 或移动端适配。
