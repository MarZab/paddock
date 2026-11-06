# Files this mixin adds to sbx's Claude Code workload. A mixin's last stage is FROM scratch: only
# what it copies in is added, and its ENV merges into the composed image (PATH by appending).
# System packages and Swift are in the kit's install hook, since a mixin's layer would replace the
# workload's dpkg state wholesale; mise's settings are in its startup hook, since the workspace
# path is known only then.
FROM jdxcode/mise:2026.10.4@sha256:1e0a39bc5a3b089b9b9305b6cd53e5d32ed5327e6241db5ec412fc2eabd44b02 AS mise

# Node for backlog.md (mise's npm backend): sbx's agent images have none. Paddock's own node kit
# (NodeKit.image) copies the same files, so a sandbox Paddock creates with both gets one Node.
FROM node:26.13.0-bookworm-slim@sha256:bc0a2afd3b74ce12222fc8bab99271e66257f021078f5f4a5d687a77d280c1d9 AS node
RUN mkdir -p /out/usr/local/bin /out/usr/local/lib \
 && cp -a /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /out/usr/local/bin/ \
 && cp -a /usr/local/lib/node_modules /out/usr/local/lib/ \
 && lib=$(dirname "$(readlink -f /usr/lib/*-linux-gnu/libatomic.so.1)") \
 && mkdir -p "/out$lib" && cp -a "$lib"/libatomic.so.1* "/out$lib/"

FROM scratch
COPY --from=mise /usr/local/bin/mise /usr/local/bin/mise
COPY --from=node /out/ /
# mise's shims for every process, not only interactive shells (the agent's Bash tool is neither
# interactive nor a login shell).
ENV PATH=/home/agent/.local/share/mise/shims
