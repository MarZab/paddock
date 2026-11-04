import Foundation

/// The agent-context of Paddock's `status` kit: how the sandbox is defined, what Paddock refuses
/// in a project's files, and the build-output guidance (PAD-71). It lives in a kit Paddock ships,
/// so the files Paddock writes for a project (`SandboxFiles`) name nothing of Paddock's.
enum SandboxGuide {
    /// What the agent reads (PAD-71): keep what it builds off the folder the Mac shares.
    static var context: String {
        let refused = ProjectEnvironment.refusedKeys.keys.filter { $0 != "workspace" }.sorted().joined(separator: ", ")
        let options = ProjectEnvironment.allowedOptions.sorted().joined(separator: ", ")
        let prefixes = ProjectEnvironment.paddockEnvPrefixes.joined(separator: ", ")
        let capabilities = ProjectEnvironment.allowedCapabilities.sorted().joined(separator: ", ")
        return """
        ## This sandbox (Paddock)

        It is defined by `sbxenv.yaml` and the kit in `tools/sandbox/` in this project. A change
        applies only after the operator confirms it in Paddock and recreates the sandbox, which
        keeps only the project folder. Every edit to either file, or to a file in the kit's
        folder, asks the operator again, so batch your edits.

        Docker's docs:

        - Environment files (`sbxenv.yaml`): \(SandboxFiles.environmentFilesURL)
        - Kits (the file in `tools/sandbox/`): \(SandboxFiles.kitsURL), spec at \(SandboxFiles.kitSpecURL)
        - Everything else: \(SandboxFiles.docsURL)

        ### What Paddock refuses

        Paddock does not apply a project file that has any of these; it shows them to the operator
        instead, and nothing is created until they are gone:

        - the keys \(refused) (`lifecycle` would run commands on the operator's Mac; secrets and
          credentials are the operator's, through `sbx secret`)
        - `sandboxOptions` other than \(options)
        - `env` names starting with \(prefixes) (Paddock sets those)
        - a `workspace` other than this folder; extra folders must pass Paddock's folder checks
        - kits other than sbx's own (`docker.io/sbx/...`, `docker.io/docker/sbx-kit-...`) and this
          project's own (`./...`, inside this folder)
        - capabilities in the project's own kit other than \(capabilities)
        - ports on Paddock's own services or the Docker API, or bound anywhere but 127.0.0.1
        - hosts that are every host (`**`, `*`) or the operator's Mac

        The network is sbx's global rules plus the hosts the project's kits name, which the
        operator can decline one by one. A host the sandbox cannot reach is blocked by a rule:
        ask the operator rather than working around it.

        ### Try a change the way Paddock applies it

        Paddock runs `sbx env create sbxenv.yaml <its own overlay> --name <project>
        --skip-host-commands --force`. The overlay (its gateway and kits) lives where you cannot
        reach it, so the operator can run the same thing from a terminal on the Mac (sbx is not
        available in this sandbox) with `tools/sandbox/run.sh` (`plan`, `create`, `run`, `rm`),
        which Paddock writes with the project's files. It uses the project's name and the overlay
        when it exists, so `create` and `run` replace the sandbox Paddock manages, you included;
        `RUN_SANDBOX_NAME=other` tries the files in a sandbox of their own. If the project has no
        such script, ask the operator before adding one.

        `plan` changes nothing, so start there. The test sandbox has no gateway and no models.

        ### Keep build output out of the project folder

        The project folder is shared with the operator's Mac. Output built here (Linux) breaks
        the Mac's own builds in the same folder and the other way round (native Node modules,
        `bin`, `obj`). Point build output and dependency stores at the sandbox's own disk
        (your home, /tmp), with environment set in the kit's dockerfile (`ENV`), never in a
        file the Mac reads too (`.npmrc`, `Directory.Build.props` without a condition):

        - .NET: `UseArtifactsOutput=true` and `ArtifactsPath=/home/agent/.cache/build/artifacts`
          move `bin` and `obj` there.
        - pnpm: `npm_config_store_dir` and `npm_config_virtual_store_dir` under
          `/home/agent/.cache`; run `pnpm install` again afterwards.
        - Other tools: their cache, output, or artifacts setting. Check each took effect.
        """
    }
}
