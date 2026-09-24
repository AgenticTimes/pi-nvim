/**
 * Host tools for Neovim: replace/read/open/goto via extension_ui bridge.
 * Spawn with builtins enabled (no --no-builtin-tools). Prefer excluding
 * disk edit/write so mutations go through nvim_* and Accept/Reject works:
 *   pi --mode rpc --no-extensions -e ./extensions/nvim_host_tools.ts \
 *     --exclude-tools edit,write
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export const HOST_TITLE = "__nvim_host__";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "nvim_replace_in_buffer",
    label: "nvim_replace_in_buffer",
    description:
      "Preferred for edits in Neovim: replace exact text in a host buffer (includes unsaved changes; Accept/Reject applies). Use instead of edit/write when the file may be open.",
    parameters: Type.Object({
      path: Type.String({ description: "File path relative to cwd or absolute" }),
      old_text: Type.String({ description: "Exact text to find" }),
      new_text: Type.String({ description: "Replacement text" }),
    }),
    async execute(_id, p, _s, _u, ctx) {
      const op = {
        op: "replace_in_buffer",
        path: p.path,
        old_text: p.old_text,
        new_text: p.new_text,
      };
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        return {
          content: [{ type: "text", text: "host cancelled" }],
          details: { ok: false },
        };
      }
      return {
        content: [{ type: "text", text: String(raw) }],
        details: { ok: true },
      };
    },
  });

  pi.registerTool({
    name: "nvim_read_buffer",
    label: "nvim_read_buffer",
    description:
      "Preferred for reading open files: return Neovim buffer text (includes unsaved changes). Use instead of read when the file may be open in the editor.",
    parameters: Type.Object({
      path: Type.String({ description: "File path relative to cwd or absolute" }),
    }),
    async execute(_id, p, _s, _u, ctx) {
      const op = { op: "read_buffer", path: p.path };
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        return {
          content: [{ type: "text", text: "host cancelled" }],
          details: { ok: false },
        };
      }
      return {
        content: [{ type: "text", text: String(raw) }],
        details: { ok: true },
      };
    },
  });

  pi.registerTool({
    name: "nvim_open",
    label: "nvim_open",
    description: "Open a file in Neovim (host) and optionally jump to a line.",
    parameters: Type.Object({
      path: Type.String({ description: "File path relative to cwd or absolute" }),
      line: Type.Optional(Type.Number({ description: "1-based line number" })),
      col: Type.Optional(Type.Number({ description: "0-based column" })),
    }),
    async execute(_id, p, _s, _u, ctx) {
      const op = { op: "open", path: p.path, line: p.line, col: p.col };
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        return {
          content: [{ type: "text", text: "host cancelled" }],
          details: { ok: false },
        };
      }
      return {
        content: [{ type: "text", text: String(raw) }],
        details: { ok: true },
      };
    },
  });

  pi.registerTool({
    name: "nvim_goto",
    label: "nvim_goto",
    description: "Jump cursor to path:line in Neovim (reuse window if already open).",
    parameters: Type.Object({
      path: Type.String({ description: "File path relative to cwd or absolute" }),
      line: Type.Optional(Type.Number({ description: "1-based line number" })),
      col: Type.Optional(Type.Number({ description: "0-based column" })),
    }),
    async execute(_id, p, _s, _u, ctx) {
      const op = { op: "goto", path: p.path, line: p.line, col: p.col };
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        return {
          content: [{ type: "text", text: "host cancelled" }],
          details: { ok: false },
        };
      }
      return {
        content: [{ type: "text", text: String(raw) }],
        details: { ok: true },
      };
    },
  });
}
