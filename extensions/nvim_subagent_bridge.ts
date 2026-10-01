/**
 * Forward pi-subagents lifecycle to Neovim via setWidget("__nvim_subagent__", [json]).
 *
 * Only real spawns open windows. Tool updates/results are stripped to human text
 * (never dump launchContractDigest / capabilities JSON into the viewer).
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export const WIDGET_KEY = "__nvim_subagent__";

type Payload = Record<string, unknown>;

const META_RE =
  /launchContractDigest|"details"\s*:\s*\{|Executable agents \(capabilities\)|Package agents\n|Builtin agents\n|outputState"|"artifactPaths"/;

/** Pull plain assistant/tool text; never JSON.stringify whole envelopes. */
function extractHumanText(content: unknown, depth = 0): string {
  if (depth > 6 || content == null) return "";
  if (typeof content === "string") {
    const t = content.trim();
    if ((t.startsWith("{") || t.startsWith("[")) && t.length > 2) {
      try {
        return extractHumanText(JSON.parse(t), depth + 1);
      } catch {
        return META_RE.test(t) ? "" : content;
      }
    }
    return META_RE.test(content) ? "" : content;
  }
  if (Array.isArray(content)) {
    return content
      .map((b) => {
        if (b && typeof b === "object" && "text" in (b as object)) {
          return String((b as { text: unknown }).text ?? "");
        }
        return extractHumanText(b, depth + 1);
      })
      .filter(Boolean)
      .join("\n");
  }
  if (typeof content === "object") {
    const o = content as Record<string, unknown>;
    if (o.content !== undefined) return extractHumanText(o.content, depth + 1);
    if (typeof o.text === "string") return extractHumanText(o.text, depth + 1);
    if (typeof o.summary === "string") return extractHumanText(o.summary, depth + 1);
    if (typeof o.output === "string") return extractHumanText(o.output, depth + 1);
    // Prefer child result outputs when present
    if (Array.isArray(o.results)) {
      return (o.results as unknown[])
        .map((r) => {
          if (r && typeof r === "object") {
            const row = r as Record<string, unknown>;
            return extractHumanText(
              row.finalOutput ?? row.output ?? row.text ?? row.content,
              depth + 1,
            );
          }
          return "";
        })
        .filter(Boolean)
        .join("\n\n");
    }
    if (typeof o.finalOutput === "string") return extractHumanText(o.finalOutput, depth + 1);
    return "";
  }
  return "";
}

/** Drop fan-out / mission bookkeeping lines from tool text. */
function cleanReply(text: string): string {
  return text
    .split("\n")
    .filter((line) => {
      const t = line.trim();
      if (!t) return false;
      if (/^Run fan-out:/i.test(t)) return false;
      if (/^Mission:\s*[0-9a-f-]{8,}/i.test(t)) return false;
      if (/^\(running\.\.\.\)$/i.test(t)) return false;
      return true;
    })
    .join("\n")
    .trim();
}

function firstOutputPath(details: unknown): string | undefined {
  if (!details || typeof details !== "object") return undefined;
  const d = details as Record<string, unknown>;
  const arts = d.artifacts;
  if (arts && typeof arts === "object") {
    const a = arts as Record<string, unknown>;
    if (typeof a.outputPath === "string") return a.outputPath;
  }
  const results = d.results;
  if (Array.isArray(results)) {
    for (const r of results) {
      if (!r || typeof r !== "object") continue;
      const row = r as Record<string, unknown>;
      const ap = row.artifactPaths;
      if (ap && typeof ap === "object") {
        const p = (ap as Record<string, unknown>).outputPath;
        if (typeof p === "string" && p) return p;
      }
      if (typeof row.outputPath === "string") return row.outputPath;
    }
  }
  return undefined;
}

function artifactsDirFromPath(outputPath: string | undefined): string | undefined {
  if (!outputPath) return undefined;
  const i = outputPath.lastIndexOf("/");
  return i > 0 ? outputPath.slice(0, i) : undefined;
}

function isAsyncDetach(summary: string): boolean {
  return /async run is detached|running in the background|native completion notification|Do not run sleep\/polling/i.test(
    summary,
  );
}

function parseAsyncRunId(summary: string): string | undefined {
  const m = summary.match(/\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]/i);
  return m?.[1];
}

function parseAsyncAgent(summary: string): string | undefined {
  const m = summary.match(/Async:\s*(\S+)\s*\[/i);
  return m?.[1];
}

/** True when this tool call is actually spawning work (not status/guide/list). */
function isSpawnArgs(args: Record<string, unknown>): boolean {
  const action = args.action != null ? String(args.action) : "";
  if (action && !["run", "spawn", ""].includes(action)) {
    return false;
  }
  if (args.workflow || args.workflowScript || args.workflowScriptPath) return true;
  const agent = args.agent || args.subagent_type || args.subagentType;
  const task = args.task || args.prompt || args.description;
  return Boolean(agent || task);
}

export default function (pi: ExtensionAPI) {
  let lastCtx: ExtensionContext | undefined;
  const lastPushAt = new Map<string, number>();
  const toolToRun = new Map<string, string>();
  /** toolCallIds that are real spawns (open a window) */
  const spawnTools = new Set<string>();

  const remember = (_e: unknown, ctx: ExtensionContext) => {
    lastCtx = ctx;
  };

  /** pi-subagents lazy-hides `subagent` behind subagents_enable; nvim always wants it. */
  const ensureSubagentActive = (event?: {
    systemPromptOptions?: { selectedTools?: string[] };
    systemPrompt?: string;
  }, reason = "?") => {
    try {
      const getAll = (pi as { getAllTools?: () => { name: string }[] }).getAllTools;
      const getActive = (pi as { getActiveTools?: () => string[] }).getActiveTools;
      const setActive = (pi as { setActiveTools?: (names: string[]) => void }).setActiveTools;
      if (typeof getActive !== "function" || typeof setActive !== "function") {
        console.error(`[nvim_subagent_bridge] ensure skip (${reason}): no get/setActiveTools`);
        return;
      }
      const all = typeof getAll === "function" ? getAll.call(pi) : null;
      const allNames = Array.isArray(all) ? all.map((t) => t?.name).filter(Boolean) : [];
      // Only bail when we positively know subagent is not registered.
      if (allNames.length > 0 && !allNames.includes("subagent")) {
        console.error(`[nvim_subagent_bridge] ensure skip (${reason}): subagent not registered; have=${allNames.join(",")}`);
        return;
      }
      const active = [...(getActive.call(pi) || [])];
      if (!Array.isArray(active)) return;
      const next = [...new Set([...active, "subagent", "subagents_enable", "bg_wait", "subagent_supervisor"])];
      if (next.length !== active.length || !active.includes("subagent")) {
        setActive.call(pi, next);
        console.error(
          `[nvim_subagent_bridge] ensure (${reason}): activated subagent; before=${active.join(",")} after=${getActive.call(pi).join(",")}`,
        );
      } else {
        console.error(`[nvim_subagent_bridge] ensure (${reason}): already active`);
      }
      const opts = event?.systemPromptOptions;
      if (opts) {
        const cur = opts.selectedTools ?? [...next];
        opts.selectedTools = [...new Set([...cur, "subagent", "subagents_enable"])];
      }
    } catch (e) {
      console.error(`[nvim_subagent_bridge] ensure error (${reason}):`, e);
    }
  };

  const push = (payload: Payload, ctx?: ExtensionContext, throttleKey?: string) => {
    const c = ctx ?? lastCtx;
    if (!c?.hasUI) return;
    if (throttleKey) {
      const now = Date.now();
      const prev = lastPushAt.get(throttleKey) ?? 0;
      if (now - prev < 500 && payload.op === "status") return;
      lastPushAt.set(throttleKey, now);
    }
    try {
      c.ui.setWidget(WIDGET_KEY, [JSON.stringify({ v: 1, ts: Date.now(), ...payload })]);
    } catch {
      // ignore
    }
  };

  pi.on("session_start", (e, ctx) => {
    remember(e, ctx);
    ensureSubagentActive(undefined, "session_start");
    setTimeout(() => ensureSubagentActive(undefined, "session_start+0"), 0);
    setTimeout(() => ensureSubagentActive(undefined, "session_start+50"), 50);
  });
  pi.on("agent_start", (e, ctx) => {
    remember(e, ctx);
    ensureSubagentActive(undefined, "agent_start");
  });
  pi.on("turn_start", (e, ctx) => {
    remember(e, ctx);
    ensureSubagentActive(undefined, "turn_start");
  });
  pi.on("before_agent_start", (event) => {
    const ev = event as {
      systemPromptOptions?: { selectedTools?: string[] };
      systemPrompt?: string;
    };
    ensureSubagentActive(ev, "before_agent_start");
    const nudge =
      "\n\n[nvim] The `subagent` tool is active. When the user asks to use a subagent/delegate, call subagent({agent, task, async:false}) directly — do not claim it is unavailable.";
    if (typeof ev.systemPrompt === "string" && !ev.systemPrompt.includes("[nvim] The `subagent` tool is active")) {
      return { systemPrompt: ev.systemPrompt + nudge };
    }
  });

  pi.on("tool_execution_start", (event, ctx) => {
    lastCtx = ctx;
    const name = String(event.toolName || "");
    if (name !== "subagent" && name !== "Agent") return;
    const args = (event as { args?: Record<string, unknown> }).args || {};
    if (!isSpawnArgs(args)) return;
    const toolCallId = String(event.toolCallId || "");
    if (toolCallId) spawnTools.add(toolCallId);
    const asyncLaunch = Boolean(args.async || args.run_in_background || args.runInBackground);
    if (asyncLaunch) return;
    push(
      {
        op: "started",
        source: "tool",
        toolCallId: event.toolCallId,
        runId: toolCallId,
        agent: String(args.agent || args.subagent_type || args.subagentType || "subagent"),
        goal: String(args.task || args.prompt || args.description || "").slice(0, 120),
        async: false,
      },
      ctx,
    );
  });

  pi.on("tool_execution_update", (event, ctx) => {
    lastCtx = ctx;
    const name = String(event.toolName || "");
    if (name !== "subagent" && name !== "Agent") return;
    const toolCallId = String(event.toolCallId || "");
    if (toolCallId && !spawnTools.has(toolCallId) && !toolToRun.has(toolCallId)) return;
    const runId = toolToRun.get(toolCallId) || toolCallId;
    const text = extractHumanText((event as { partialResult?: unknown }).partialResult).trim();
    if (!text || text === "(running...)" || isAsyncDetach(text) || META_RE.test(text)) return;
    // Only short progress lines in the viewer — not envelopes
    if (text.startsWith("{") || text.length > 500) return;
    push(
      {
        op: "status",
        source: "tool",
        runId,
        toolCallId: event.toolCallId,
        text: text.slice(0, 400),
      },
      ctx,
      runId || "tool",
    );
  });

  pi.on("tool_execution_end", (event, ctx) => {
    lastCtx = ctx;
    const name = String(event.toolName || "");
    if (name !== "subagent" && name !== "Agent") return;
    const toolCallId = String(event.toolCallId || "");
    const raw = (event as { content?: unknown }).content ?? (event as { result?: unknown }).result;
    const details = (event as { details?: unknown }).details;
    const summary = cleanReply(extractHumanText(details ?? raw) || extractHumanText(raw));
    const blob =
      typeof raw === "string"
        ? raw
        : (() => {
            try {
              return JSON.stringify(raw ?? "");
            } catch {
              return summary;
            }
          })();
    const isError = Boolean((event as { isError?: boolean }).isError);
    const wasSpawn = spawnTools.has(toolCallId) || toolToRun.has(toolCallId);
    const outputPath = firstOutputPath(details);
    const asyncDir = artifactsDirFromPath(outputPath);

    if (!isError && isAsyncDetach(blob)) {
      const full = blob;
      const runId = parseAsyncRunId(full) || toolCallId;
      if (toolCallId) {
        toolToRun.set(toolCallId, runId);
        spawnTools.add(toolCallId);
      }
      push(
        {
          op: "started",
          source: "tool-async",
          toolCallId,
          runId,
          agent: parseAsyncAgent(full) || "subagent",
          goal: "",
          async: true,
          asyncDir,
          outputPath,
        },
        ctx,
      );
      return;
    }

    // Management / list / enable: no window
    if (!wasSpawn) return;

    const runId =
      toolToRun.get(toolCallId) ||
      (details && typeof details === "object" && typeof (details as { runId?: unknown }).runId === "string"
        ? String((details as { runId: string }).runId)
        : toolCallId);
    const clean = summary && !META_RE.test(summary) ? summary.slice(0, 4000) : isError ? summary.slice(0, 500) : "";
    push(
      {
        op: "complete",
        source: "tool",
        runId,
        toolCallId,
        success: !isError,
        summary: clean || (isError ? "failed" : "done"),
        failedFast: /Unknown agent:/i.test(summary),
        asyncDir,
        outputPath,
      },
      ctx,
    );
    spawnTools.delete(toolCallId);
  });

  const onAsyncStarted = (data: unknown) => {
    const d = (data || {}) as Record<string, unknown>;
    const runId = String(d.id || d.runId || "");
    push({
      op: "started",
      source: "async",
      runId,
      agent: String(d.agent || (Array.isArray(d.agents) ? d.agents[0] : "") || "async"),
      goal: String(d.goal || d.task || "").slice(0, 120),
      asyncDir: d.asyncDir,
      sessionRoot: d.sessionRoot,
      mode: d.mode,
      cwd: d.cwd,
      async: true,
    });
  };

  const onChildStatus = (data: unknown) => {
    const d = (data || {}) as Record<string, unknown>;
    const runId = String(d.childRunId || d.runId || d.childId || "");
    if (d.status === "started") {
      push({
        op: "started",
        source: "child",
        runId,
        parentRunId: d.runId,
        childId: d.childId,
        agent: d.agent,
        label: d.label,
        asyncDir: d.asyncDir,
        phase: d.phase,
      });
      return;
    }
    push(
      {
        op: "status",
        source: "child",
        runId,
        parentRunId: d.runId,
        status: d.status,
        agent: d.agent,
        label: d.label,
        asyncDir: d.asyncDir,
        phase: d.phase,
      },
      undefined,
      runId || "child",
    );
  };

  const onComplete = (data: unknown, source: string) => {
    const d = (data || {}) as Record<string, unknown>;
    const summary = extractHumanText(d.summary ?? d.output ?? d);
    push({
      op: "complete",
      source,
      runId: String(d.id || d.runId || ""),
      agent: d.agent,
      success: d.success !== false && d.state !== "failed",
      summary: (summary && !META_RE.test(summary) ? summary : String(d.summary || "")).slice(0, 8000),
      sessionFile: d.sessionFile,
      asyncDir: d.asyncDir,
      state: d.state,
    });
  };

  pi.events.on("subagent:async-started", onAsyncStarted);
  pi.events.on("subagent:child-status", onChildStatus);
  pi.events.on("subagent:async-complete", (d) => onComplete(d, "async"));
  pi.events.on("subagent:foreground-complete", (d) => onComplete(d, "foreground"));
}
