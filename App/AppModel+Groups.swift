import PaddockCore

/// Project groups in the sidebar (PAD-145, backlog doc UI, Project groups).
extension AppModel {
    /// Puts the project in a sidebar group, or in none (kept in its project file).
    func setGroup(_ group: String?, for project: Project) {
        let group = ProjectGroups.normalized(group)
        guard withSaved(project, { self.setGroup(group, for: $0) }) else { return }
        guard var updated = projects.project(named: project.name), updated.group != group else { return }
        updated.group = group
        saveProject(updated, what: "group")
    }
}
