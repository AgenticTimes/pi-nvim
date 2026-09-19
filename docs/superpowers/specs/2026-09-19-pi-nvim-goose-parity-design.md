# pi.nvim — 交互与功能清单（对照 goose.nvim）

- 日期：2026-09-19
- 状态：待用户审查
- 仓库：`~/source/pi.nvim`
- 大脑：`pi --mode rpc`（不自研 agent loop）
- 编辑：Host Tools 经 Neovim API（先改再审）

## 0. 与 goose 的差异（先读）

| | goose.nvim | pi.nvim（本项目） |
|--|------------|-------------------|
| Agent | Goose CLI（写磁盘为主） | `pi --mode rpc` |
| 改文件 | CLI 写盘 → `checktime` | **tool → Neovim buffer API** |
| 审阅 | Diff tab + revert | Diff + **Accept 移出列表** / Reject 还原 |
| UI | Input + Output 双窗 | 同构双窗 + pending 文件列表 |
| 默认不嵌 TUI | 是 | 是（`:Pi` TUI 非目标） |

Spike 已验证：真实 `tool_execution_start` → `nvim_buf_set_lines` → diff-mode → 多文件列表 → Accept 移除。

---

## 1. 架构总览（对齐 goose 模块名）

```
用户 / 键位 / :Pi*
        ↓
┌───────────────────────────────────────┐
│ api          公开动作（toggle/run/…）   │
├───────────────────────────────────────┤
│ ui           chat 输出 + input + 布局   │
│ context      当前文件/选区/@/诊断       │
│ session      会话状态 + touched[]      │
│ client       pi RPC JSONL              │
│ host_tools   执行 nvim_* tool 回传      │
│ review       diff / accept / reject    │
│ events       User PiEvent / 日志       │
└───────────────────────────────────────┘
        ↕ stdio
   pi --mode rpc + extensions/nvim_host_tools.ts
```

**扩展（pi 进程内）：** 禁用/覆盖内置 `edit`/`write`/`read`，注册 `nvim_*`，经 `extension_ui_request` 交给宿主。

---

## 2. 交互流程（主路径）

```
1. 打开 UI（toggle / open_input）
2. 自动带上 context（当前文件、选区、诊断）
3. 用户输入（可 @ 文件）→ <CR> 发送 prompt
4. pi agent_start → 流式渲染到 output
5. tool_execution_start(nvim_*) → host 改 buffer → 记入 pending
6. 自动/手动打开 review：BEFORE|AFTER + 文件列表
7. 用户 a Accept（保留并移出列表）/ r Reject（还原并移出）
8. ]f/[f 翻文件；全部处理完 → review 清空
9. agent_end；可继续对话或 stop
```

---

## 3. 功能清单（goose → pi.nvim）

图例：`P0` 第一期必须 · `P1` 紧随 · `P2` 以后 · `N/A` 不跟 goose 或改语义

### 3.1 UI / 布局

| 功能 | goose | pi.nvim | 优先级 |
|------|-------|---------|--------|
| Toggle 打开/关闭 UI | `<leader>gg` | `:Pi` / 可配置 keymap | P0 |
| Input 窗（多行） | 有 | 有 | P0 |
| Output/Chat 窗（流式消息） | 有 | 有 | P0 |
| 关闭 UI | `<leader>gq` | 有 | P0 |
| 焦点在 goose ↔ 编辑器间切换 | `<leader>gt` | 有 | P0 |
| Input ↔ Output 切换 | `<tab>` | 有 | P0 |
| 全屏 toggle | `<leader>gf` | 有 | P1 |
| float / split 布局配置 | 有 | 有 | P1 |
| Pending 文件列表（多文件） | 弱（靠 diff tab） | **一等公民** | P0 |
| Tool 事件可见（日志/侧栏） | 部分 | **一等公民** | P0 |

### 3.2 发送与控制

| 功能 | goose | pi.nvim | 优先级 |
|------|-------|---------|--------|
| 提交 prompt | `<CR>` | 同 | P0 |
| Stop / abort | `<C-c>` | `abort` RPC | P0 |
| Steer / follow-up（busy 时） | 有限 | pi `steer` / `followUp` | P1 |
| Prompt 历史 ↑↓ | 有 | 有 | P1 |
| `:PiRun` / 新会话跑一句 | GooseRun* | 有 | P1 |
| 消息间跳转 `]]` `[[` | 有 | 有 | P1 |

### 3.3 Context

| 功能 | goose | pi.nvim | 优先级 |
|------|-------|---------|--------|
| 当前文件路径 | 自动 | 自动 | P0 |
| Visual 选区 | 自动 | `@this` / 发送时附带 | P0 |
| 当前 buffer 诊断 | 自动 | `@diagnostics` | P0 |
| `@` 提文件（picker） | 有 | 有（fzf/telescope） | P0 |
| `@buffer` / `@visible` | — | 有（pi.neovim 已有占位） | P1 |
| `#` skills 补全 | goose skills | 映射 pi skills（若 RPC 可得） | P2 |
| `/` slash 命令补全 | goose | pi `get_commands` | P1 |

### 3.4 Session / 模型

| 功能 | goose | pi.nvim | 优先级 |
|------|-------|---------|--------|
| 持续会话（同 workspace） | 有 | pi session | P0 |
| 新会话 | open_input_new_session | `new_session` | P0 |
| 选择已有会话 | select_session | `switch_session` + picker | P1 |
| 切换 model / provider | configure_provider | `cycle_model` / `set_model` | P1 |
| thinking level | — | `cycle_thinking_level` | P1 |
| Inspect session JSON | 有 | 可选 | P2 |
| Chat vs Auto 模式 | 有（禁 tool） | `--no-tools` / 仅 host tools | P1 |
| Approve / smart_approve | goose 工具审批 | P2（可后接 host confirm） | P2 |

### 3.5 Review / Diff（本项目核心增强）

| 功能 | goose | pi.nvim | 优先级 |
|------|-------|---------|--------|
| 打开 diff | `gd` | 自动 + `:PiDiff` | P0 |
| 下一文件 / 上一文件 | `g]` `g[` | `]f` `[f` | P0 |
| 关闭 diff | `gc` | 有 | P0 |
| Hunk 导航 | diff `]c` `[c` | 同 | P0 |
| Revert 当前文件 | `grt` | **Reject**（还原 BEFORE） | P0 |
| Revert 全部 | `gra` | Reject all | P0 |
| **Accept 当前文件** | 无明确 | **`a`：保留 + 移出 pending** | P0 |
| Accept all | 无 | 有 | P1 |
| Accept 后可选 `:w` | — | 默认写入 | P0 |
| 多文件 pending 列表 | 弱 | **列表 + 计数** | P0 |

策略（已定）：**先改再审（A）** — tool 立刻改 buffer，再 Accept/Reject。

### 3.6 Host Tools（pi 侧，goose 无对等）

| Tool | 行为 | 优先级 |
|------|------|--------|
| `nvim_replace_in_buffer` | 精确替换 → buffer | P0 |
| `nvim_read_buffer` | 读 buffer（含未保存） | P0 |
| `nvim_open` / `nvim_goto` | 打开文件 / 跳转 | P1 |
| 禁用内置 `edit`/`write`/`read` | 防写盘旁路 | P0 |
| bash | 仍可用 pi 内置或受限 | P1 |

### 3.7 明确不做（相对 goose）

- 嵌 pi 原生 TUI 作默认 UI  
- 自研 LLM loop / 重写整颗 pi  
- Goose recipes / Block MCP 配置 UI（除非 pi 已有等价）  
- 以「写盘 + checktime」为主路径  

---

## 4. 建议默认键位（可配置，勿占死 Leader 冲突）

全局（示例，最终以 `setup().keymap` 为准）：

| 动作 | 建议 |
|------|------|
| Toggle UI | `<leader>ai`（与现配置习惯对齐） |
| 新会话输入 | `<leader>aI` |
| Diff / Review | `<leader>ad` |
| 下一/上一文件 | `<leader>a]` / `<leader>a[` |
| Accept / Reject 当前 | `a` / `r`（仅 review buffer-local） |
| Stop | `<C-c>`（input 窗） |

窗内：`<CR>` 发送、`@` mention、`<Tab>` 切 pane、`]]`/`[[` 消息。

---

## 5. 实现分期

### Wave 1 — MVP（可日常用）

1. `client` + `extensions/nvim_host_tools.ts`（replace/read + 禁内置文件工具）  
2. `ui`：input + output float/split  
3. `context`：当前文件 / 选区 / 诊断 / `@`  
4. `session` + `review`：pending 列表、diff、accept/reject、`]f`/`[f`  
5. `api`：toggle / stop / new_session / run  
6. 测试：沿用 spike 的单文件 + 多文件 + accept 场景  

### Wave 2

- steer/follow-up、历史、fullscreen、session picker、model/thinking cycle、slash 补全  

### Wave 3

- approve 流、skills `#`、更细 hunk-level accept、HTML export 等  

---

## 6. Spike → 产品映射

| Spike | 产品模块 |
|-------|----------|
| `demo_toolcall_ui.lua` | client + host_tools + 单文件 review |
| `demo_multifile_ui.lua` | session.touched + review 列表 + accept/reject |
| `extensions/nvim_replace_tool.ts` | `extensions/nvim_host_tools.ts` |

---

## 7. 成功标准（MVP）

1. 不嵌 TUI，纯 Neovim 键位完成一轮「提问 → toolcall → 改代码 → 看见 diff」。  
2. 日志/事件能看到 `tool_execution_start`。  
3. ≥3 文件进入 pending；`a` 后该项从列表消失；`r` 还原内容。  
4. 内置 pi `edit`/`write` 不落盘改项目（或已被覆盖）。  

---

## 8. 待用户确认

请确认本清单后进入 **implementation plan（writing-plans）**，再按 Wave 1 编码。

可选调整（若有，直接说）：

- 默认 keymap 前缀（`<leader>ai` vs `<leader>p` …）  
- Accept 是否默认 `:w`  
- Wave 1 是否必须含 `@` picker（建议必须）  
