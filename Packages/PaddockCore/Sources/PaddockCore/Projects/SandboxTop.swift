import Foundation

/// What a running sandbox is doing: its load, memory, disk, and busiest processes (backlog doc UI,
/// Resources; PAD-32). sbx has no stats API: its own dashboard runs a short /proc script in each
/// sandbox, and so does Paddock, through `sbx exec`. The scripts need only sh, tr, head, df, sleep
/// (and getconf for the page size, else 4096), so they work in any image, with or without ps.
/// Every line starts with a tag, so a missing tool leaves its line out instead of shifting the rest.
public enum SandboxTop {
    /// The machine: CPUs, page size, load, memory, disk, and one `/proc/stat` line. CPU use is the
    /// difference to the previous sample, so the sidebar's first number comes with the second poll.
    public static let summaryScript = header + #"echo '--- 1'; head -1 /proc/stat"#

    /// The machine and every process: command lines, then two snapshots of `/proc/<pid>/stat` a
    /// second apart, for the CPU each used in that second.
    public static let processScript = header
        + #"for p in /proc/[0-9]*; do c=$(tr '\0\n' '  ' 2>/dev/null < "$p/cmdline" | head -c 300) && "#
        + #"printf 'C %s %s\n' "${p#/proc/}" "$c"; done; "#
        + #"snap() { head -1 /proc/stat; for p in /proc/[0-9]*; do s=$(cat "$p/stat" 2>/dev/null) && "#
        + #"printf 'S %s\n' "$s"; done; }; echo '--- 1'; snap; sleep 1; echo '--- 2'; snap"#

    static let header = #"n=0; while read -r k _; do case $k in cpu[0-9]*) n=$((n+1));; esac; done < /proc/stat; "#
        + #"echo "N $n"; echo "P $(getconf PAGESIZE 2>/dev/null || echo 4096)"; "#
        + #"echo "L $(cat /proc/loadavg)"; "#
        + #"while read -r k v _; do case $k in MemTotal:) t=$v;; MemAvailable:) a=$v;; esac; done < /proc/meminfo; "#
        + #"echo "M $t $a"; df -kP / 2>/dev/null | { read -r _; read -r _ s u _ && echo "D $s $u"; }; "#

    /// `sbx exec` arguments that run `script` in `sandbox`. Never for a sandbox that is not running:
    /// `sbx exec` starts a stopped one.
    public static func arguments(sandbox: String, script: String) -> [String] {
        ["exec", sandbox, "sh", "-c", script]
    }

    /// Whether Paddock may run a script in the sandbox now: only while it runs and no action of
    /// Paddock's (stop, remove, recreate) is under way, since `sbx exec` starts a stopped sandbox.
    /// A stop from outside Paddock that lands while a script starts can still be undone by it; the
    /// event stream ends polling as soon as it reports the stop.
    public static func mayPoll(_ state: SandboxStates.State?, actionRunning: Bool) -> Bool {
        guard case .running? = state else { return false }
        return !actionRunning
    }

    /// Runs `script` in `sandbox` and parses what it prints. The caller checks `mayPoll` first.
    public static func read(_ script: String, in sandbox: String, sbx: URL,
                            runner: ProcessRunner) async throws -> SandboxSample {
        let result = try await runner.run(sbx, arguments: arguments(sandbox: sandbox, script: script))
        guard result.exitCode == 0 else { throw SandboxTopError.failed(sandbox, result.exitCode, result.stderrText) }
        return parse(String(decoding: result.stdout, as: UTF8.self))
    }

    /// Parses either script's output. Lines it does not know are skipped.
    public static func parse(_ text: String) -> SandboxSample {
        var sample = SandboxSample()
        var snapshot = -1
        var stats: [[Int32: ProcessStat]] = [[:], [:]]
        var commands: [Int32: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("--- ") {
                snapshot = (Int(line.dropFirst(4)) ?? 1) - 1
                continue
            }
            if line.hasPrefix("cpu ") {
                let times = line.split(separator: " ").dropFirst().compactMap { Int($0) }
                guard times.count >= 4 else { continue }
                let cpu = CPUTimes(total: times.reduce(0, +), idle: times[3] + (times.count > 4 ? times[4] : 0))
                if snapshot == 0 { sample.cpu = cpu } else if snapshot == 1 { sample.cpuLater = cpu }
                continue
            }
            guard line.count > 2, line.dropFirst().first == " " else { continue }
            let rest = line.dropFirst(2)
            switch line.first {
            case "N": sample.cpus = Int(rest) ?? 0
            case "P": sample.pageSize = Int(rest) ?? 4096
            case "L":
                let loads = rest.split(separator: " ").prefix(3).compactMap { Double($0) }
                if loads.count == 3 { sample.load = loads }
            case "M":
                let numbers = rest.split(separator: " ").compactMap { Int($0) }
                if numbers.count == 2 { sample.memoryTotalKiB = numbers[0]; sample.memoryAvailableKiB = numbers[1] }
            case "D":
                let numbers = rest.split(separator: " ").compactMap { Int($0) }
                if numbers.count == 2 { sample.diskTotalKiB = numbers[0]; sample.diskUsedKiB = numbers[1] }
            case "C":
                let parts = rest.split(separator: " ", maxSplits: 1)
                if let pid = parts.first.flatMap({ Int32($0) }) {
                    commands[pid] = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                }
            case "S":
                if (0...1).contains(snapshot), let stat = ProcessStat(rest) { stats[snapshot][stat.pid] = stat }
            default: break
            }
        }
        sample.processes = processes(stats[0], stats[1], commands: commands, sample: sample)
        return sample
    }

    /// Processes in both snapshots, with the CPU they used between them (in cores: 1 is one CPU busy).
    private static func processes(_ first: [Int32: ProcessStat], _ second: [Int32: ProcessStat],
                                  commands: [Int32: String], sample: SandboxSample) -> [SandboxProcess] {
        guard let before = sample.cpu, let after = sample.cpuLater, sample.cpus > 0 else { return [] }
        // The second between the snapshots in clock ticks per CPU, from the machine's own counter.
        let ticks = Double(after.total - before.total) / Double(sample.cpus)
        guard ticks > 0 else { return [] }
        return second.values.compactMap { stat in
            guard let earlier = first[stat.pid] else { return nil }
            let used = Double(stat.cpuTicks - earlier.cpuTicks) / ticks
            let command = commands[stat.pid].flatMap { $0.isEmpty ? nil : $0 } ?? "[\(stat.name)]"
            return SandboxProcess(pid: stat.pid, ppid: stat.ppid, name: stat.name, cores: max(0, used),
                                  residentBytes: stat.residentPages * sample.pageSize, command: command)
        }
        .sorted { $0.cores != $1.cores ? $0.cores > $1.cores : $0.residentBytes > $1.residentBytes }
    }

    /// Processes by app, busiest first: an app is a program, or for an interpreter the script it
    /// runs (`node .../vite.js` is vite), so Chromium's dozen processes are one row.
    public static func apps(_ processes: [SandboxProcess]) -> [SandboxApp] {
        let groups = Dictionary(grouping: processes) { appName($0.command, fallback: $0.name) }
        return groups.map { SandboxApp(name: $0.key, processes: $0.value.sorted { $0.cores > $1.cores }) }
            .sorted { $0.cores != $1.cores ? $0.cores > $1.cores : $0.residentBytes > $1.residentBytes }
    }

    static let interpreters: Set<String> = ["node", "python", "python3", "sh", "bash", "dash", "zsh", "ruby", "perl",
                                            "bun", "deno", "java", "env"]

    static func appName(_ command: String, fallback: String) -> String {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first, !first.hasPrefix("[") else { return fallback }
        let program = (first as NSString).lastPathComponent
        // An interpreter is named by its script: the first argument that is not an option.
        if interpreters.contains(program) || program.hasPrefix("python") || program.hasPrefix("node") {
            if let script = words.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                var name = (script as NSString).lastPathComponent
                for suffix in [".js", ".mjs", ".cjs", ".py", ".sh", ".rb"] where name.hasSuffix(suffix) {
                    name = String(name.dropLast(suffix.count))
                }
                return name.isEmpty ? program : name
            }
        }
        return program.isEmpty ? fallback : program
    }
}

public enum SandboxTopError: Error, Equatable, CustomStringConvertible {
    case failed(String, Int32, String)

    public var description: String {
        switch self {
        case .failed(let sandbox, let code, let stderr): "Could not read \(sandbox)'s load (exit \(code)): \(stderr)"
        }
    }
}

public struct CPUTimes: Sendable, Equatable {
    public let total: Int
    public let idle: Int
}

/// One sample of a sandbox.
public struct SandboxSample: Sendable, Equatable {
    public var cpus = 0
    public var pageSize = 4096
    /// 1, 5, and 15 minute load averages.
    public var load: [Double] = []
    public var memoryTotalKiB = 0
    public var memoryAvailableKiB = 0
    public var diskTotalKiB = 0
    public var diskUsedKiB = 0
    /// The machine's CPU counters (the first snapshot), and a second later for the process script.
    public var cpu: CPUTimes?
    public var cpuLater: CPUTimes?
    public var processes: [SandboxProcess] = []

    public init() {}

    public var memoryUsedKiB: Int { max(0, memoryTotalKiB - memoryAvailableKiB) }

    /// The share of all CPUs busy between `earlier` and this sample's counters (or within this
    /// sample, for the process script), 0 to 1; nil without two readings.
    public func cpuBusy(since earlier: CPUTimes? = nil) -> Double? {
        let (from, to): (CPUTimes?, CPUTimes?) = cpuLater != nil ? (cpu, cpuLater) : (earlier, cpu)
        guard let from, let to, to.total > from.total else { return nil }
        let total = Double(to.total - from.total)
        return min(1, max(0, 1 - Double(to.idle - from.idle) / total))
    }
}

public struct SandboxProcess: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let ppid: Int32
    /// The kernel's short name (`comm`).
    public let name: String
    /// CPUs it kept busy in the measured second: 1 is one whole CPU.
    public let cores: Double
    public let residentBytes: Int
    public let command: String

    public var id: Int32 { pid }
}

public struct SandboxApp: Sendable, Equatable, Identifiable {
    public let name: String
    public let processes: [SandboxProcess]

    public var id: String { name }
    public var cores: Double { processes.reduce(0) { $0 + $1.cores } }
    public var residentBytes: Int { processes.reduce(0) { $0 + $1.residentBytes } }
}

/// The fields of `/proc/<pid>/stat` Paddock reads. The name is in parentheses and may hold spaces
/// or parentheses itself, so the fields after it are counted from the last `)`.
struct ProcessStat: Equatable {
    let pid: Int32
    let name: String
    let ppid: Int32
    /// utime + stime, in clock ticks.
    let cpuTicks: Int
    let residentPages: Int

    init?(_ line: Substring) {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close,
              let pid = Int32(line[..<open].trimmingCharacters(in: .whitespaces)) else { return nil }
        let fields = line[line.index(after: close)...].split(separator: " ")
        // After the name: state(0) ppid(1) ... utime(11) stime(12) ... rss(21).
        guard fields.count > 21, let ppid = Int32(fields[1]), let utime = Int(fields[11]), let stime = Int(fields[12]),
              let rss = Int(fields[21]) else { return nil }
        self.pid = pid
        self.name = String(line[line.index(after: open)..<close])
        self.ppid = ppid
        self.cpuTicks = utime + stime
        self.residentPages = rss
    }
}
