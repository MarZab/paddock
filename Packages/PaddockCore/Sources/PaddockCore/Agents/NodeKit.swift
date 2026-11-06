import Foundation

/// Node.js for Paddock's kits (backlog doc Kits, Node). sbx 0.51's agents are v3 kits on images
/// without Node (Claude Code is a native binary there), yet Paddock's status, voice, and browser
/// helpers and sbx's own Playwright kit run on it: without Node they fail at install ("npm: not
/// found", "env: 'node'"; `mise run capture:cli kits`, 2026-11-04; PAD-73.2). No kit of sbx's or Docker's
/// provides Node, so this one copies it from Node's official image: `node`, `npm`, and `npx` in
/// `/usr/local`, and `libatomic.so.1`, which Node 26 needs and the agents' images lack ("error
/// while loading shared libraries: libatomic.so.1"), into the system's own library folder.
public enum NodeKit {
    public static let directoryName = "paddock-node"
    /// Node 26 LTS (a version many projects pin), the bookworm build: built against an
    /// older glibc, so it runs on the agents' images too. Pinned by digest.
    public static let image = "node:26.13.0-bookworm-slim@sha256:bc0a2afd3b74ce12222fc8bab99271e66257f021078f5f4a5d687a77d280c1d9"

    public static func directory(in paths: PaddockPaths) -> String {
        paths.kits + "/" + directoryName
    }

    public static var spec: String {
        #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        # Its files come from paddock-node.dockerfile beside this file.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Node.js (Paddock)
        description: Node.js, npm, and npx for Paddock's kits and sbx's Playwright kit.
        provides: [paddock-node]

        """#
    }

    /// The kit's files: its last stage is `FROM scratch`, so only Node's own files are added.
    public static var dockerfile: String {
        """
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        FROM \(image) AS node
        RUN mkdir -p /out/usr/local/bin /out/usr/local/lib \\
         && cp -a /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /out/usr/local/bin/ \\
         && cp -a /usr/local/lib/node_modules /out/usr/local/lib/ \\
         && lib=$(dirname "$(readlink -f /usr/lib/*-linux-gnu/libatomic.so.1)") \\
         && mkdir -p "/out$lib" && cp -a "$lib"/libatomic.so.1* "/out$lib/"

        FROM scratch
        COPY --from=node /out/ /

        """
    }

    /// Writes the kit if it is missing or differs. Returns the kit directory.
    @discardableResult
    public static func install(in paths: PaddockPaths) throws -> String {
        try KitFile.write(spec, to: directory(in: paths), dockerfile: dockerfile)
    }
}
