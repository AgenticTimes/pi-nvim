/**
 * Demo extension: ask Neovim host to apply a real buffer edit (not FS write).
 * Trigger: /nvim_edit_sample
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HOST_TITLE = "__nvim_host__";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("nvim_edit_sample", {
    description: "Ask Neovim to edit demo/sample.lua greet() via buffer API",
    handler: async (_args, ctx) => {
      const op = {
        op: "replace_in_buffer",
        // Neovim resolves this relative to the demo root we pass as cwd
        path: "demo/sample.lua",
        old_text: '  return "hello, " .. tostring(name)',
        new_text: '  return "hi from pi→nvim, " .. tostring(name)',
      };
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        ctx.ui.notify("nvim host cancelled", "error");
        return;
      }
      ctx.ui.notify(`nvim edit result: ${raw}`, "info");
    },
  });
}
