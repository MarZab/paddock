// Paddock's A2UI tab (backlog doc Browser, interactive tabs; PAD-152): CopilotKit's Gen UI 2.0
// renderer with the A2UI Playground's catalog. Paddock gives it the tab's A2UI messages as data
// (window.paddockA2UI.render); it runs no code from them. What the operator does comes back to
// Paddock through one message handler, as JSON: {"kind":"ready"}, {"kind":"action","message":{...}}
// (an A2UI action message), {"kind":"error","message":{...}} (an A2UI error message: what the
// renderer refused or could not draw), {"kind":"problem","text":...} (the page itself). Media goes
// through the sandbox (media.ts); maps draw on an offline style (map-style.json).
import { patchMedia } from "./media";
import "@copilotkit/react-core/v2/styles.css";
import "@/vendor/transitions/ui-generation.css";
import "@/app/globals.css";
import "@/design-systems/design-systems.css";
import { useMemo, useSyncExternalStore } from "react";
import type { ComponentType } from "react";
import { createRoot } from "react-dom/client";
import { AbstractAgent } from "@ag-ui/client";
import type { BaseEvent, RunAgentInput } from "@ag-ui/client";
import { CopilotChatConfigurationProvider, CopilotKitProvider, useCopilotKit } from "@copilotkit/react-core/v2";
import { GENERATIVE_UI_ACTIVITY_TYPE, GENERATIVE_UI_CHAT_TARGET } from "@copilotkit/shared";
import type { A2UIOperation, GenerativeUISurfaceContent } from "@copilotkit/shared";
import { EMPTY } from "rxjs";
import type { Observable } from "rxjs";
import { playgroundUI } from "@/a2ui/catalog/catalog";
import { CATALOG_ID } from "@/a2ui/catalog/ids";
import { DESIGN_SYSTEM_THEMES } from "@/design-systems/themes";

patchMedia();

type Message = Record<string, unknown>;
type Handler = { postMessage(message: string): void };

/** To Paddock: one JSON string. Outside the app (the headless check) into `paddockOutbox`. */
function post(kind: string, body: Record<string, unknown> = {}) {
  const text = JSON.stringify({ kind, ...body });
  const handler = (window as unknown as { webkit?: { messageHandlers?: { paddock?: Handler } } }).webkit?.messageHandlers?.paddock;
  if (handler) handler.postMessage(text);
  else ((window as unknown as { paddockOutbox?: string[] }).paddockOutbox ??= []).push(text);
}

/**
 * The surfaces' agent. A surface hands each user event to an agent run, with the event as an A2UI
 * action message in the run's forwarded props (CopilotKit's forwardEvent); this one passes it to
 * Paddock and ends the run at once.
 */
class PaddockAgent extends AbstractAgent {
  run(input: RunAgentInput): Observable<BaseEvent> {
    const props = (input.forwardedProps ?? {}) as { copilotkit?: { ui?: { metadata?: { extensions?: Record<string, unknown> } } } };
    const action = props.copilotkit?.ui?.metadata?.extensions?.copilotkit_action;
    if (action && typeof action === "object") post("action", { message: action });
    return EMPTY;
  }
}
const AGENTS = { default: new PaddockAgent() };

/** The tab's messages so far. */
let messages: Message[] = [];
const listeners = new Set<() => void>();
const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
};

(window as unknown as { paddockA2UI: unknown }).paddockA2UI = Object.freeze({
  /** Every message of the tab so far, as a JSON array; a longer list applies what is new. */
  render(json: string) {
    try {
      const parsed: unknown = JSON.parse(json);
      if (!Array.isArray(parsed)) throw new Error("not an array of messages");
      messages = parsed.filter((m): m is Message => !!m && typeof m === "object" && !Array.isArray(m));
      for (const listener of listeners) listener();
    } catch (error) {
      post("problem", { text: String(error).slice(0, 500) });
    }
  },
});

/** The surface a message is about. */
function surfaceOf(message: Message): string | undefined {
  for (const [key, value] of Object.entries(message)) {
    if (key === "version" || !value || typeof value !== "object") continue;
    const id = (value as { surfaceId?: unknown }).surfaceId;
    if (typeof id === "string") return id;
  }
  return undefined;
}

function Surfaces() {
  const all = useSyncExternalStore(subscribe, () => messages);
  const { copilotkit } = useCopilotKit();
  const Base = copilotkit.renderActivityMessages.find((r) => r.activityType === GENERATIVE_UI_ACTIVITY_TYPE)?.render as
    | ComponentType<Record<string, unknown>>
    | undefined;
  const bySurface = useMemo(() => {
    const groups = new Map<string, Message[]>();
    for (const message of all) {
      const id = surfaceOf(message);
      if (!id) continue;
      if ("deleteSurface" in message) groups.delete(id);
      else groups.set(id, [...(groups.get(id) ?? []), message]);
    }
    return groups;
  }, [all]);
  if (!Base) return null;
  return (
    <>
      {[...bySurface.entries()].map(([id, operations]) => (
        <Surface key={id} id={id} operations={operations} Base={Base} />
      ))}
    </>
  );
}

function Surface({ id, operations, Base }: { id: string; operations: Message[]; Base: ComponentType<Record<string, unknown>> }) {
  const content = useMemo<GenerativeUISurfaceContent>(
    () => ({
      surfaceId: id,
      target: GENERATIVE_UI_CHAT_TARGET,
      catalogId: CATALOG_ID,
      operations: operations as unknown as A2UIOperation[],
      status: "ready",
      rejected: [],
    }),
    [id, operations],
  );
  const message = useMemo(
    () => ({ id: `paddock:${id}`, role: "activity" as const, activityType: GENERATIVE_UI_ACTIVITY_TYPE, content: content as unknown as Message }),
    [content, id],
  );
  return (
    <div className="paddock-surface" data-surface={id}>
      <CopilotChatConfigurationProvider threadId={`paddock-${id}`}>
        <Base activityType={GENERATIVE_UI_ACTIVITY_TYPE} content={content} message={message} agent={undefined} />
      </CopilotChatConfigurationProvider>
    </div>
  );
}

/** A2UI's error codes for what CopilotKit's renderer reports. */
const ERROR_CODES: Record<string, string> = {
  props: "VALIDATION_FAILED", operation: "VALIDATION_FAILED", render: "RENDER_FAILED", function: "FUNCTION_FAILED", event: "EVENT_FAILED",
};
let lastError = "";

function reportError(info: { kind: string; surfaceId: string; componentId?: string; error: Error }) {
  const message = {
    version: "1.0",
    error: {
      code: ERROR_CODES[info.kind] ?? "RENDER_FAILED",
      surfaceId: info.surfaceId,
      ...(info.componentId ? { path: info.componentId } : {}),
      message: String(info.error?.message ?? info.error).slice(0, 1000),
    },
  };
  // The same error again (a re-render) goes once.
  const text = JSON.stringify(message);
  if (text === lastError) return;
  lastError = text;
  post("error", { message });
}

/** The page's own offline map style, for the standard Map (theme.mapStyle). */
const MAP_STYLE = new URL("map-style.json", document.baseURI).href;

function Host() {
  const generativeUI = useMemo(
    () => ({
      ui: playgroundUI,
      theme: { ...DESIGN_SYSTEM_THEMES.copilotkit, mapStyle: MAP_STYLE, dark: { ...(DESIGN_SYSTEM_THEMES.copilotkit as { dark?: object }).dark, mapStyle: MAP_STYLE } },
      errorBoundary: { onError: reportError },
    }),
    [],
  );
  return (
    <CopilotKitProvider agents__unsafe_dev_only={AGENTS} generativeUI={generativeUI} enableInspector={false} showDevConsole={false}>
      <Surfaces />
    </CopilotKitProvider>
  );
}

window.addEventListener("error", (event) => post("problem", { text: String(event.message).slice(0, 500) }));
const root = document.getElementById("root");
if (root) createRoot(root).render(<Host />);
post("ready");
