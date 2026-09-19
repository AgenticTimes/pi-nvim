/**
 * Host tools for Neovim: replace/read via extension_ui bridge.
 * Spawn with:
 *   pi --mode rpc --no-extensions --no-builtin-tools \
 *     -t nvim_replace_in_buffer,nvim_read_buffer \
 *     -e ./extensions/nvim_host_tools.ts
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export const HOST_TITLE = "__nvim_host__";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "nvim_replace_in_buffer",
    label: "nvim_replace_in_buffer",
    description:
      "Replace exact text in a Neovim buffer (host IDE applies the edit; does not write via agent filesystem tools).",
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
    description: "Read file contents from the Neovim host buffer (includes unsaved changes).",
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
}
