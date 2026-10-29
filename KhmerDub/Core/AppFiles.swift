import Foundation

enum AppFiles {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var root: URL {
        documents.appendingPathComponent("KhmerDub", isDirectory: true)
    }

    static var projectsFile: URL {
        root.appendingPathComponent("projects.json")
    }

    static var mediaRoot: URL {
        root.appendingPathComponent("Media", isDirectory: true)
    }

    static var exportsRoot: URL {
        root.appendingPathComponent("Exports", isDirectory: true)
    }

    static var voiceLabRoot: URL {
        root.appendingPathComponent("VoiceLab", isDirectory: true)
    }

    static var tempRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KhmerDub", isDirectory: true)
    }

    static var exportsDirectoryForSharing: URL {
        exportsRoot
    }

    static func ensureDirectories() {
        for url in [root, mediaRoot, exportsRoot, voiceLabRoot, tempRoot] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func projectMediaDirectory(_ projectID: UUID) -> URL {
        mediaRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    static func projectExportDirectory(_ projectID: UUID) -> URL {
        exportsRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    static func createProjectDirectories(_ projectID: UUID) {
        try? FileManager.default.createDirectory(
            at: projectMediaDirectory(projectID),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: projectExportDirectory(projectID),
            withIntermediateDirectories: true
        )
    }

    static func mediaURL(for project: DubProject) -> URL? {
        guard let fileName = project.mediaFileName else { return nil }
        let url = projectMediaDirectory(project.id).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func thumbnailURL(for project: DubProject) -> URL? {
        guard let fileName = project.thumbnailFileName else { return nil }
        let url = projectMediaDirectory(project.id).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func exportURL(for project: DubProject, fileName: String) -> URL {
        projectExportDirectory(project.id).appendingPathComponent(fileName)
    }

    static func removeProjectData(_ projectID: UUID) {
        try? FileManager.default.removeItem(at: projectMediaDirectory(projectID))
        try? FileManager.default.removeItem(at: projectExportDirectory(projectID))
    }

    static func removeExports() {
        try? FileManager.default.removeItem(at: exportsRoot)
        try? FileManager.default.createDirectory(at: exportsRoot, withIntermediateDirectories: true)
    }

    static func removeAllProjectData() {
        try? FileManager.default.removeItem(at: root)
        ensureDirectories()
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }

    static func makeTempURL(extension ext: String) -> URL {
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    static func cleanTemporaryFiles() {
        try? FileManager.default.removeItem(at: tempRoot)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }
}
