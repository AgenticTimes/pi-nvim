---
generated_from_state_version: 11
---

# Verification

## Current result

- Result: **Passed**
- Assurance: **skill-coordinated**
- Goal cycle: 1
- Iteration: 2
- Verifier attempt: 1
- Completed: 2026-09-20T13:03:47.710Z
- Summary: with_picker drops ask zindex for / # @; private refocus avoids inject_yank wipe; tests 20 passed.

## Acceptance

| ID | Result | Source | Criterion | Reason |
| --- | --- | --- | --- | --- |
| A1 | passed | brief.md | A1: Ask 打开且内容为空时按 `/`，slash 列表完整可见、可滚动选择，不被 ask 遮挡。 | Empty ask / → slash.pick → with_picker; zindex 40 during select |
| A2 | passed | brief.md | A2: Ask 打开时按 `#`，skill 列表完整可见；取消或选中后 ask 仍开着且可继续输入。 | Ask # → skills.pick → with_picker; ask stays open |
| A3 | passed | brief.md | A3: Ask 打开时按 `@` 选文件，行为与现有一致（列表在 ask 之上；选完插入路径并回到 ask）。 | Ask @ → pick_file → with_picker; path insert + refocus |
| A4 | passed | brief.md | A4: 选择取消（Esc）后 ask `zindex` 恢复为默认，再次打开 picker 仍可见。 | done() restores zindex 60 on cancel/select |
| A5 | passed | specs/ask-picker-overlay/spec.md | 当 `pi://input` ask 浮窗打开时，用户触发的命令/技能/文件选择器必须叠在 ask **之上**，且 ask 窗口保持打开。 | Ask stays open; no close/reopen |
| A6 | passed | specs/ask-picker-overlay/spec.md | \| 输入 \| 行为 \| | Spec table header artifact; covered by A1-A3 |
| A7 | passed | specs/ask-picker-overlay/spec.md | \| ask 内容为空（或仅空白）时按配置的 slash 键（默认 `/`） \| 打开 slash command 选择器 \| | Table row: empty / opens slash; covered by A1 |
| A8 | passed | specs/ask-picker-overlay/spec.md | \| ask 内按 `#`（配置键） \| 打开 skill 选择器 \| | Table row: # opens skills; covered by A2 |
| A9 | passed | specs/ask-picker-overlay/spec.md | \| ask 内按 `@` \| 打开项目文件选择器 \| | Table row: @ opens files; covered by A3 |
| A10 | passed | specs/ask-picker-overlay/spec.md | 打开任意上述选择器前：若 ask 已开，将 ask 窗口 `zindex` 降到 **40**（低于常见 telescope/`vim.ui.select` 浮层 ≈100）。 | PICKER_BEHIND_Z=40 when ask open |
| A11 | passed | specs/ask-picker-overlay/spec.md | 选择器关闭后（选中或取消）：将 ask `zindex` 恢复为 **60**；若 ask 仍开，聚焦 `pi://input` 并进入插入模式（与现 `@` 路径一致）。 | Restore 60 + private refocus_input_win (not open_input) |
| A12 | passed | specs/ask-picker-overlay/spec.md | 整个过程 **不得** 关闭或重建 ask 浮窗。 | No ask close/rebuild in picker path |
| A13 | passed | specs/ask-picker-overlay/spec.md | `pi.ui` 提供单一入口（如 `with_picker(fn)`）：封装降 zindex → `fn`（通常 `vim.schedule` + `vim.ui.select`）→ 回调里恢复。 | ui.with_picker single entry |
| A14 | passed | specs/ask-picker-overlay/spec.md | `pi.slash.pick`、`pi.skills.pick`、`pi.context.pick_file` 必须经该入口；禁止各自复制不一致的 zindex 逻辑。 | slash/skills/pick_file all use with_picker |
| A15 | passed | specs/ask-picker-overlay/spec.md | 无 ask 打开时，选择器行为与现网一致（不强制改 zindex）。 | No zindex change when ask closed |
| A16 | passed | specs/ask-picker-overlay/spec.md | 用户能完整阅读选择器列表与 prompt，不被 ask 边框/正文挡住。 | Ask behind picker via lowered zindex |
| A17 | passed | specs/ask-picker-overlay/spec.md | 选中后文本插入 ask（slash/skill/路径），可继续编辑并提交。 | Insert text into ask after select |

## Checks

_No Runtime checks were recorded._

## Blockers

_None._

## Risks and skipped work

_None reported._

## Previous iterations

| Goal cycle | Iteration | Attempt | Outcome | Unresolved | Summary | Completed |
| ---: | ---: | ---: | --- | --- | --- | --- |
| 1 | 1 | 1 | recovery | — | Verifier found focus_input shadowed by open_input; with_picker may wipe ask draft via inject_yank. Revising. | 2026-09-20T13:01:14.785Z |
| 1 | 2 | 1 | pass | — | with_picker drops ask zindex for / # @; private refocus avoids inject_yank wipe; tests 20 passed. | 2026-09-20T13:03:47.710Z |

## Conclusion

with_picker drops ask zindex for / # @; private refocus avoids inject_yank wipe; tests 20 passed.
