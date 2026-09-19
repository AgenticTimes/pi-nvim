/**
 * Host-edit tool for Neovim. LLM must call this tool; execute() asks the host
 * via extension_ui (ctx.ui.input) — no filesystem write.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export const HOST_TITLE = "__nvim_host__";

const params = Type.Object({
  path: Type.String({ description: "File path relative to cwd or absolute" }),
  old_text: Type.String({ description: "Exact text to find in the Neovim buffer" }),
  new_text: Type.String({ description: "Replacement text" }),
});

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "nvim_replace_in_buffer",
    label: "nvim_replace_in_buffer",
    description:
      "Replace exact text in a file that is open (or will be opened) in the Neovim host. " +
      "Does NOT write via the filesystem; the IDE applies the edit to the buffer.",
    parameters: params,
    async execute(_toolCallId, p, _signal, _onUpdate, ctx) {
      const op = {
        op: "replace_in_buffer",
        path: p.path,
        old_text: p.old_text,
        new_text: p.new_text,
      };
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        return {
          content: [{ type: "text", text: "Neovim host cancelled the edit" }],
          details: { ok: false },
        };
      }
      return {
        content: [{ type: "text", text: String(raw) }],
        details: { ok: true, raw },
      };
    },
  });
}
