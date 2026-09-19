/**
 * Feasibility spike: route a "tool" action to the Neovim host via RPC
 * extension_ui_request / extension_ui_response (ctx.ui.input).
 *
 * Load with: pi --mode rpc -e ./extensions/host_nvim_demo.ts --no-extensions --no-session
 * Trigger:   prompt message "/nvim_host_demo"
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const HOST_TITLE = "__nvim_host__";

type HostOp = {
  op: "append_line";
  text: string;
};

export default function (pi: ExtensionAPI) {
  // Command path — no LLM needed (good for CI / local spike)
  pi.registerCommand("nvim_host_demo", {
    description: "Ask Neovim host to append a line via extension_ui bridge",
    handler: async (_args, ctx) => {
      const op: HostOp = {
        op: "append_line",
        text: `pi→nvim ok @ ${new Date().toISOString()}`,
      };
      // title = host marker; placeholder = JSON op for Neovim to execute
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        ctx.ui.notify("nvim host cancelled / no response", "error");
        return;
      }
      ctx.ui.notify(`nvim host result: ${raw}`, "info");
    },
  });

  // Tool path — same bridge; LLM can call this when tools are enabled
  pi.registerTool({
    name: "nvim_append_line",
    label: "nvim_append_line",
    description:
      "Append a line to the Neovim demo scratch buffer (executed by the host IDE, not the filesystem).",
    parameters: Type.Object({
      text: Type.String({ description: "Line text to append in Neovim" }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const op: HostOp = { op: "append_line", text: params.text };
      const raw = await ctx.ui.input(HOST_TITLE, JSON.stringify(op));
      if (raw === undefined) {
        return {
          content: [{ type: "text", text: "host cancelled" }],
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
