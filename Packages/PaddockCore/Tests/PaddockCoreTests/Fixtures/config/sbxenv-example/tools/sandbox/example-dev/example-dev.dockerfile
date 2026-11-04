# Files this mixin adds to the Claude Code workload. A mixin's last stage is FROM scratch:
# only what it copies in is added, and its ENV merges into the composed image (PATH by
# appending). System packages are not here but in the kit's install hook, since a mixin's
# layer would replace the workload's dpkg state wholesale. mise's settings (trust, yes,
# quiet, azure-cli off) are in the kit's lifecycle files, since the trust path is known only
# at create.
FROM jdxcode/mise:2026.10.4 AS mise

FROM scratch
COPY --from=mise /usr/local/bin/mise /usr/local/bin/mise

# pnpm keeps its store on the sandbox's disk, not in the bind-mounted tree.
ENV pnpm_config_store_dir=/home/agent/.local/share/pnpm/store \
    PATH=/home/agent/.local/share/mise/shims
