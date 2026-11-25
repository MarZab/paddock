// Builds Paddock's A2UI host (tools/tasks/vendor/a2ui-web.sh) inside the A2UI Playground's checkout,
// so its catalog compiles with its own aliases and styles. Lazily loaded parts (code grammars,
// diagrams, maps) stay chunks of their own, loaded only when a surface uses them.
import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const app = path.resolve(__dirname, "..");
/** The playground's maps name tile servers; the page draws them on its own offline style instead. */
const offlineMaps = {
  name: "paddock-offline-maps",
  transform(code: string, id: string) {
    if (!id.replace(/\\/g, "/").endsWith("/renderers/map/geo.ts")) return null;
    const replaced = code.replace(/"https:\/\/[^"]*"/g, 'new URL("map-style.json", document.baseURI).href');
    if (replaced === code) throw new Error("geo.ts has no style URLs any more: check the offline map");
    return { code: replaced, map: null };
  },
};

/**
 * Code blocks highlight with Shiki, which brings a grammar for some 230 languages (most of the
 * page's size). These common ones stay; a block in any other shows as plain monospaced text.
 */
const LANGUAGES = new Set([
  "bash", "shellscript", "shellsession", "powershell", "bat", "json", "jsonc", "json5", "yaml", "toml", "ini", "xml", "html",
  "css", "scss", "javascript", "jsx", "typescript", "tsx", "vue", "svelte", "markdown", "mdx", "python", "ruby", "php", "go",
  "rust", "java", "kotlin", "scala", "swift", "objective-c", "c", "cpp", "csharp", "sql", "graphql", "lua", "r", "dart",
  "dockerfile", "make", "nginx", "diff", "regexp", "csv", "proto", "terraform", "hcl", "elixir", "haskell", "zig",
]);
const fewerLanguages = {
  name: "paddock-fewer-languages",
  enforce: "pre" as const,
  resolveId(source: string) {
    const match = /^@shikijs\/langs\/([a-z0-9-]+)$/.exec(source);
    return match && !LANGUAGES.has(match[1]) ? "\0paddock-no-language" : null;
  },
  load(id: string) {
    return id === "\0paddock-no-language" ? "export default [];" : null;
  },
};

export default defineConfig({
  root: __dirname,
  base: "./",
  publicDir: path.resolve(__dirname, "public"),
  plugins: [react(), offlineMaps, fewerLanguages],
  resolve: {
    alias: [
      { find: /^@\//, replacement: app + "/src/" },
      { find: "next/dynamic", replacement: path.resolve(__dirname, "next-dynamic.tsx") },
    ],
  },
  define: { "process.env.NODE_ENV": JSON.stringify("production"), "process.env": "{}" },
  build: {
    outDir: path.resolve(__dirname, "dist"),
    emptyOutDir: true,
    assetsInlineLimit: 0,
    sourcemap: false,
    chunkSizeWarningLimit: 8000,
    rollupOptions: {
      output: { entryFileNames: "host.js", chunkFileNames: "chunks/[name]-[hash].js", assetFileNames: "assets/[name]-[hash][extname]" },
    },
  },
  css: { postcss: app },
});
