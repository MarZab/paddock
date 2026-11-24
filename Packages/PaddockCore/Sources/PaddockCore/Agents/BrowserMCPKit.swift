import Foundation

/// Paddock's Playwright MCP kit, on the browser kit (backlog doc Browser, Playwright MCP; PAD-141,
/// PAD-142, split off in PAD-147): `@playwright/mcp` on the same Playwright as the browser kit's
/// playwright-cli, so it uses that kit's Chromium build and downloads no other. One server for the
/// sandbox (`BrowserKit.mcpLauncher`), localhost only, with a kept profile and the extensions in
/// `BrowserKit.mcpExtensions`, registered with Claude Code on every start. Its own kit because it
/// keeps logins across restarts and writes an entry into Claude Code's config, which not every
/// project wants. Its pages show in the Playwright tab through the browser kit's watcher.
public enum BrowserMCPKit {
    /// sbx names a local kit after its folder, and the names in one sandbox must differ.
    public static let directoryName = "paddock-browser-mcp"

    public static func directory(in paths: PaddockPaths) -> String {
        paths.kits + "/" + directoryName
    }

    public static var spec: String {
        let launcher = Data(BrowserKit.mcpLauncher.utf8).base64EncodedString()
        return #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Playwright MCP (Paddock)
        description: "Read this before you use the mcp__\#(BrowserKit.mcpServerName)__ browser tools: one shared browser with a kept profile."
        provides: [paddock-browser-mcp]

        capabilities:
          # npm, for the install.
          - type: com.docker.sandbox/network-policy@2
            config:
              install:
                allow: [registry.npmjs.org:443]
          - type: com.docker.sandbox/lifecycle@1
            config:
              install:
                - command: |
                    set -eu
                    if [ -n "${HTTP_PROXY:-}" ]; then
                      npm config set proxy "$HTTP_PROXY"
                      npm config set https-proxy "$HTTP_PROXY"
                    fi
                    npm install --global --no-fund --no-audit --loglevel=error "\#(BrowserKit.mcpPackage)@\#(BrowserKit.mcpVersion)"
                    mkdir -p "$(dirname \#(BrowserKit.realMCP))"
                    ln -sf "$(readlink -f "$(command -v playwright-mcp)")" \#(BrowserKit.realMCP)
                    printf '%s' '\#(launcher)' | base64 -d > \#(BrowserKit.mcpLauncherPath)
                    chmod 755 \#(BrowserKit.mcpLauncherPath)
                  user: "0"
                  # A hook sees only the environment it names: npm's global bin is on the image's PATH.
                  env: [PATH, HOME, HTTP_PROXY, HTTPS_PROXY, NO_PROXY]
                  description: Install Playwright MCP \#(BrowserKit.mcpVersion) (npm \#(BrowserKit.mcpPackage)) and Paddock's MCP launcher
              startup:
                # The sandbox's one Playwright MCP server (localhost only), and Claude Code's entry for it.
                - command: [\#(BrowserKit.mcpLauncherPath), start]
                  user: "1000"
                  description: Start Playwright MCP on localhost:\#(BrowserKit.mcpPort) (kept profile, extensions)
                - command:
                    - sh
                    - -c
                    - '\#(BrowserKit.registerMCPScript)'
                  user: "1000"
                  description: Register Playwright MCP with Claude Code
          - type: com.docker.sandbox/agent-context@1
            config:
              content: |
                ## Playwright MCP (Paddock)

                - In Claude Code a browser also comes as MCP tools (`mcp__\#(BrowserKit.mcpServerName)__*`). It is
                  one browser for every agent in this sandbox, and it keeps its profile (logins, cookies)
                  across sandbox restarts: open a tab of your own, leave other tabs alone, and never type
                  passwords or keys into it (ask the operator to log in). The operator sees its pages
                  live in the Playwright tab; tell them the page you mean.
                - Chromium extensions for it: put each unpacked extension (a folder with its
                  `manifest.json`) in `\#(BrowserKit.mcpExtensions)`, then run `paddock-browser-mcp restart`
                  (it closes the browser: say so first). `paddock-browser-mcp status` lists them.
                - Port \#(BrowserKit.mcpPort) is taken.

        """#
    }

    /// Writes the kit if it is missing or differs. Returns the kit directory.
    @discardableResult
    public static func install(in paths: PaddockPaths) throws -> String {
        try KitFile.write(spec, to: directory(in: paths))
    }
}
