# Outcome

Ask 打开时，`/` slash、`#` skill、`@` 文件选择器都叠在 ask 浮窗之上，可选、可读，选完后 focus 回到 ask。

# Scope

- Ask 打开期间所有从 ask 触发的 `vim.ui.select` / telescope 选择器：降低 ask `zindex`（约 40），选择结束后恢复（约 60）并 refocus ask。
- 抽出公共 helper，替换 `context.pick_file` 内联逻辑；`slash` / `skills` 走同一路径。
- 回归：空 ask 按 `/` 能看见 command 列表（不再被 ask 挡住）。

# Non-goals

- Ask `@` omnifunc / 高亮（前序 #2）。
- Review tab-diff / `q` 关回编辑器（前序 #4）。
- Context chips / agent todos（前序 #5）。
- 改 telescope 全局默认 zindex。
- 关闭 ask 再开 picker（已验证会破坏布局）。

# Acceptance examples

- A1: Ask 打开且内容为空时按 `/`，slash 列表完整可见、可滚动选择，不被 ask 遮挡。
- A2: Ask 打开时按 `#`，skill 列表完整可见；取消或选中后 ask 仍开着且可继续输入。
- A3: Ask 打开时按 `@` 选文件，行为与现有一致（列表在 ask 之上；选完插入路径并回到 ask）。
- A4: 选择取消（Esc）后 ask `zindex` 恢复为默认，再次打开 picker 仍可见。

# Constraints and invariants

- Ask 窗口在 picker 期间保持存在，不 `close`/`reopen`。
- Picker 结束后若 ask 仍开，必须 `startinsert` / 聚焦 `pi://input`。
- 不依赖具体 UI 插件：`vim.ui.select`（含 dressing/telescope ui-select）均适用。

# Decisions

- D1: 沿用 `@` 已验证方案：ask `zindex` 临时降到 40（telescope≈100），回调恢复 60；不关闭 ask。
- D2: 公共 API：`ui.with_picker(run)`（或等价名），在 `slash.pick` / `skills.pick` / `context.pick_file` 共用。
- D3: 本变更不含前序 #2/#4/#5；截图问题优先修 overlay。

# Open questions

（无）

# Verification expectations

- 手工：Ask → `/`、`#`、`@` 各一轮（选中 + Esc）。
- 自动化：为 `with_picker` / slash 在 mock `ui.select` 下断言调用前后 `set_input_zindex` 顺序（若现有测试框架可覆盖）。
