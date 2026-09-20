# Ask 浮窗与选择器叠放

## 完整行为（Archive 后）

当 `pi://input` ask 浮窗打开时，用户触发的命令/技能/文件选择器必须叠在 ask **之上**，且 ask 窗口保持打开。

### 触发

| 输入 | 行为 |
| --- | --- |
| ask 内容为空（或仅空白）时按配置的 slash 键（默认 `/`） | 打开 slash command 选择器 |
| ask 内按 `#`（配置键） | 打开 skill 选择器 |
| ask 内按 `@` | 打开项目文件选择器 |

### 叠放规则

1. 打开任意上述选择器前：若 ask 已开，将 ask 窗口 `zindex` 降到 **40**（低于常见 telescope/`vim.ui.select` 浮层 ≈100）。
2. 选择器关闭后（选中或取消）：将 ask `zindex` 恢复为 **60**；若 ask 仍开，聚焦 `pi://input` 并进入插入模式（与现 `@` 路径一致）。
3. 整个过程 **不得** 关闭或重建 ask 浮窗。

### 实现约束

- `pi.ui` 提供单一入口（如 `with_picker(fn)`）：封装降 zindex → `fn`（通常 `vim.schedule` + `vim.ui.select`）→ 回调里恢复。
- `pi.slash.pick`、`pi.skills.pick`、`pi.context.pick_file` 必须经该入口；禁止各自复制不一致的 zindex 逻辑。
- 无 ask 打开时，选择器行为与现网一致（不强制改 zindex）。

### 可见结果

- 用户能完整阅读选择器列表与 prompt，不被 ask 边框/正文挡住。
- 选中后文本插入 ask（slash/skill/路径），可继续编辑并提交。
