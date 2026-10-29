import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [DubProject] = []
    @Published private(set) var lastError: String?

    private let fileURL: URL
    private let fileManager: FileManager
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL = AppFiles.projectsFile, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        AppFiles.ensureDirectories()
        load()
    }

    var sortedProjects: [DubProject] {
        projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    var projectCount: Int { projects.count }
    var exportCount: Int { projects.reduce(0) { $0 + $1.exports.count } }
    var totalDubSeconds: Double { projects.reduce(0) { $0 + $1.speechDuration } }
    var totalStorageBytes: Int64 { AppFiles.directorySize(AppFiles.root) }

    func project(id: UUID) -> DubProject? {
        projects.first { $0.id == id }
    }

    func upsert(_ project: DubProject, immediate: Bool = false) {
        var value = project
        value.touch()
        if let index = projects.firstIndex(where: { $0.id == value.id }) {
            projects[index] = value
        } else {
            projects.append(value)
            AppFiles.createProjectDirectories(value.id)
        }
        if immediate {
            flush()
        } else {
            scheduleSave()
        }
    }

    func delete(_ project: DubProject) {
        projects.removeAll { $0.id == project.id }
        AppFiles.removeProjectData(project.id)
        flush()
    }

    func delete(id: UUID) {
        guard let project = project(id: id) else { return }
        delete(project)
    }

    func duplicate(_ project: DubProject, newTitle: String) -> DubProject {
        var copy = project
        copy.id = UUID()
        copy.title = newTitle
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.isDemo = false
        copy.exports = []
        copy.stage = .draft
        copy.segments = project.segments.map { segment in
            var value = segment
            value.id = UUID()
            return value
        }
        copy.recalculateStage()

        try? fileManager.createDirectory(at: AppFiles.projectExportDirectory(copy.id), withIntermediateDirectories: true)
        let oldDirectory = AppFiles.projectMediaDirectory(project.id)
        let newDirectory = AppFiles.projectMediaDirectory(copy.id)
        if fileManager.fileExists(atPath: oldDirectory.path) {
            try? fileManager.copyItem(at: oldDirectory, to: newDirectory)
        } else {
            try? fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        }
        upsert(copy, immediate: true)
        return copy
    }

    func clearAllProjects() {
        projects.removeAll()
        AppFiles.removeAllProjectData()
        flush()
    }

    func clearExports() {
        for index in projects.indices {
            projects[index].exports.removeAll()
            projects[index].recalculateStage()
        }
        AppFiles.removeExports()
        flush()
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persist()
    }

    func reload() {
        load()
    }

    private func load() {
        AppFiles.ensureDirectories()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            projects = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([DubProject].self, from: data)
            projects = decoded.sorted { $0.updatedAt > $1.updatedAt }
            lastError = nil
        } catch {
            projects = []
            lastError = error.localizedDescription
            let backup = fileURL
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: fileURL, to: backup)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(projects.sorted { $0.updatedAt > $1.updatedAt })
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
