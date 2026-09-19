#!/usr/bin/env node
/**
 * Minimal pi --mode rpc double for unit tests.
 * Reads JSONL from stdin; writes JSONL to stdout.
 *
 * Scripted behaviors:
 * - any command with id → response success
 * - prompt containing FORCE_HOST_EDIT → extension_ui_request replace on demo path
 * - prompt containing FORCE_READ → extension_ui_request read_buffer
 */
import readline from "node:readline";

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

rl.on("line", (line) => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }

  if (msg.id && msg.type) {
    emit({
      type: "response",
      id: msg.id,
      command: msg.type,
      success: true,
      data: msg.type === "get_state" ? { status: "idle" } : undefined,
    });
  }

  if (msg.type === "prompt") {
    const text = String(msg.message || "");
    emit({ type: "agent_start" });

    if (text.includes("FORCE_HOST_EDIT")) {
      const op = {
        op: "replace_in_buffer",
        path: text.match(/PATH=(\S+)/)?.[1] || "demo/sample.lua",
        old_text: text.match(/OLD=(.+?)(?:\n|$)/)?.[1] || 'return "hello"',
        new_text: text.match(/NEW=(.+?)(?:\n|$)/)?.[1] || 'return "world"',
      };
      emit({
        type: "tool_execution_start",
        toolCallId: "call_fake_1",
        toolName: "nvim_replace_in_buffer",
        args: op,
      });
      emit({
        type: "extension_ui_request",
        id: "ui-fake-1",
        method: "input",
        title: "__nvim_host__",
        placeholder: JSON.stringify(op),
      });
      // wait for extension_ui_response before ending — handled below
      return;
    }

    emit({ type: "agent_end" });
  }

  if (msg.type === "extension_ui_response") {
    emit({
      type: "tool_execution_end",
      toolCallId: "call_fake_1",
      toolName: "nvim_replace_in_buffer",
      isError: false,
      result: { content: [{ type: "text", text: String(msg.value || "") }] },
    });
    emit({ type: "agent_end" });
  }

  if (msg.type === "abort") {
    emit({ type: "agent_end" });
  }

  if (msg.type === "steer" || msg.type === "follow_up") {
    emit({
      type: "response",
      id: msg.id || msg.type,
      command: msg.type,
      success: true,
    });
  }

  if (msg.type === "cycle_model") {
    emit({
      type: "response",
      id: msg.id || "cycle-model",
      command: "cycle_model",
      success: true,
      data: { model: { id: "fake-model" }, thinkingLevel: "off", isScoped: false },
    });
  }

  if (msg.type === "cycle_thinking_level") {
    emit({
      type: "response",
      id: msg.id || "cycle-think",
      command: "cycle_thinking_level",
      success: true,
      data: { level: "high" },
    });
  }
});
