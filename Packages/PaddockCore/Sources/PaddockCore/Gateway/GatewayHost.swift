import Foundation

/// Runs the app's gateway listeners: one per project that uses a local model, on the project's
/// own port (backlog doc ModelGateway). Call `shutdown()` before releasing it.
public actor GatewayHost {
    public struct Listener: Sendable, Equatable {
        public let port: Int
        public let model: String
    }

    private let gateway: ModelGateway
    private var bound: [UUID: (listener: Listener, gateway: BoundGateway, task: Task<Void, Never>)] = [:]

    public init(models: AppConfig.Models, log: @escaping @Sendable (GatewayLogEntry) -> Void) {
        gateway = ModelGateway(configuration: .init(models: models), log: log)
    }

    public var listeners: [UUID: Listener] { bound.mapValues(\.listener) }

    /// Makes the running listeners match `projects`: one for each local-model project with a
    /// gateway port, none for anything else. Returns the projects whose listener failed to start.
    @discardableResult
    public func sync(_ projects: [Project], app: AppConfig) async -> [String: String] {
        var wanted: [UUID: (project: Project, listener: Listener)] = [:]
        for project in projects {
            if case .local(let model)? = app.provider(named: project.provider), let port = project.gatewayPort {
                wanted[project.id] = (project, Listener(port: port, model: model))
            }
        }
        for (id, entry) in bound where wanted[id]?.listener != entry.listener {
            await entry.gateway.stop()
            entry.task.cancel()
            bound[id] = nil
        }
        var failures: [String: String] = [:]
        for (id, entry) in wanted where bound[id] == nil {
            do {
                let binding = GatewayBinding(projectID: id, projectName: entry.project.name, model: entry.listener.model)
                let listener = try await gateway.bind(port: entry.listener.port, binding: binding)
                let task = Task { _ = try? await listener.serve() }
                bound[id] = (entry.listener, listener, task)
            } catch {
                failures[entry.project.name] = String(describing: error)
            }
        }
        return failures
    }

    public func shutdown() async {
        for entry in bound.values {
            await entry.gateway.stop()
            entry.task.cancel()
        }
        bound = [:]
        try? await gateway.shutdown()
    }
}
