// Media through the sandbox (PAD-152; backlog doc Browser, interactive tabs). The page may load
// only its own origin (its Content-Security-Policy), so before React draws anything, every image,
// video, audio, and poster URL a component sets is turned into one on that origin,
// ./__media/<kind>/<the URL, base64url>: the app answers it through the sandbox (A2UIMedia), a
// web URL fetched there and a relative path read next to the tab's messages. data: and blob: stay.
// An embed (VideoEmbed's YouTube or Vimeo iframe) cannot load on the Mac: its frame shows a card
// with a link instead, which the app opens in the sandbox's browser.

type Kind = "image" | "video" | "audio";

function base64url(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The URL the page may load for `value`, or the value as it is when it needs none. */
export function mediaURL(value: string, kind: Kind): string {
  const text = String(value ?? "").trim();
  if (!text || /^(data|blob):/i.test(text) || text.startsWith("./__media/") || text.startsWith("#")) return text;
  return `./__media/${kind}/${base64url(text)}`;
}

function kindOf(element: Element, attribute: string): Kind | null {
  const tag = element.tagName;
  if (tag === "IMG" || (tag === "VIDEO" && attribute === "poster")) return "image";
  if (tag === "VIDEO") return "video";
  if (tag === "AUDIO") return "audio";
  if (tag === "SOURCE") {
    const parent = element.parentElement?.tagName;
    return parent === "AUDIO" ? "audio" : parent === "VIDEO" ? "video" : "image";
  }
  return null;
}

function patchProperty(prototype: object, property: string) {
  const descriptor = Object.getOwnPropertyDescriptor(prototype, property);
  if (!descriptor?.set || !descriptor.get) return;
  Object.defineProperty(prototype, property, {
    ...descriptor,
    set(this: Element, value: string) {
      const kind = kindOf(this, property);
      descriptor.set!.call(this, kind ? mediaURL(value, kind) : value);
    },
  });
}

function escapeHTML(text: string): string {
  return text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] ?? c);
}

/** What an embed's frame shows: a page of its own, no script, with a link to the embedded page. */
export function embedCard(value: string): string {
  const text = String(value ?? "").trim();
  if (!/^https?:\/\//i.test(text)) return text;
  const url = escapeHTML(text);
  const page = `<!doctype html><meta charset="utf-8"><style>body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;font:14px -apple-system,system-ui,sans-serif;background:#111;color:#eee;text-align:center}a{color:#9cf}</style><div><div>This embed plays in the sandbox's browser.</div><p><a href="${url}" target="_top">${url}</a></p></div>`;
  return "data:text/html;charset=utf-8," + encodeURIComponent(page);
}

export function patchMedia() {
  const frame = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, "src");
  if (frame?.set && frame.get) {
    Object.defineProperty(HTMLIFrameElement.prototype, "src", { ...frame, set(this: Element, value: string) { frame.set!.call(this, embedCard(value)); } });
  }
  patchProperty(HTMLImageElement.prototype, "src");
  patchProperty(HTMLMediaElement.prototype, "src");
  patchProperty(HTMLSourceElement.prototype, "src");
  patchProperty(HTMLVideoElement.prototype, "poster");
  // srcset lists more URLs; the page uses src alone.
  for (const prototype of [HTMLImageElement.prototype, HTMLSourceElement.prototype]) {
    Object.defineProperty(prototype, "srcset", { configurable: true, get: () => "", set: () => {} });
  }
  const setAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (this: Element, name: string, value: string) {
    const lower = name.toLowerCase();
    if (lower === "srcset" && kindOf(this, "src")) return;
    if (lower === "src" && this.tagName === "IFRAME") return setAttribute.call(this, name, embedCard(value));
    const kind = lower === "src" || lower === "poster" ? kindOf(this, lower) : null;
    return setAttribute.call(this, name, kind ? mediaURL(value, kind) : value);
  };
}
