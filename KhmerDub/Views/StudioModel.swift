import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class StudioModel: ObservableObject {
    enum TranslationMode {
        case all
        case emptyOnly
    }

    @Published var project: DubProject {
        didSet { scheduleSave() }
    }
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcriptionPhase: TranscriptionPhase?
    @Published private(set) var transcriptionProgress: Double = 0
    @Published private(set) var transcriptionError: String?

    @Published private(set) var isTranslating = false
    @Published private(set) var translationProgress: Double = 0
    @Published private(set) var translationError: String?

    @Published private(set) var isExporting = false
    @Published private(set) var exportPhase: ExportPhase?
    @Published private(set) var exportProgress: Double = 0
    @Published private(set) var exportError: String?
    @Published private(set) var lastExport: DubExportResult?
    @Published private(set) var isSavingPhoto = false

    private weak var settings: AppSettings?
    private weak var store: ProjectStore?
    private weak var localization: Localization?
    private weak var toasts: ToastCenter?
    private var saveTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var configured = false

    init(project: DubProject) {
        self.project = project
    }

    func configure(
        settings: AppSettings,
        store: ProjectStore,
        localization: Localization,
        toasts: ToastCenter
    ) {
        guard !configured else { return }
        configured = true
        self.settings = settings
        self.store = store
        self.localization = localization
        self.toasts = toasts
    }

    var includedTranslatedSegments: [DubSegment] {
        project.segments
            .filter { $0.isIncluded && $0.isTranslated && $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    var speakerNames: [String] {
        Array(Set(project.segments.map(\.speaker).filter { !$0.trimmed.isEmpty })).sorted()
    }

    var hasMedia: Bool { AppFiles.mediaURL(for: project) != nil }

    // MARK: - Persistence

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        store?.upsert(project, immediate: true)
    }

    func refreshStage() {
        project.recalculateStage()
        scheduleSave()
    }

    func scheduleSave() {
        guard configured else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.store?.upsert(self.project)
        }
    }

    // MARK: - Segments

    @discardableResult
    func addSegment(at time: Double) -> UUID {
        let start = max(0, min(time, project.duration > 0 ? max(0, project.duration - 0.5) : time))
        let preferredEnd = project.duration > 0
            ? min(project.duration, start + 3.0)
            : start + 3.0
        let segment = DubSegment.blank(
            start: start,
            end: preferredEnd,
            speaker: localization?.t("segment.speakerPlaceholder") ?? "Speaker 1",
            voice: project.defaultVoice,
            rate: project.voiceRate,
            pitch: project.voicePitch
        )
        project.segments.append(segment)
        project.segments.sort { $0.start < $1.start }
        project.recalculateStage()
        persistNow()
        return segment.id
    }

    @discardableResult
    func duplicateSegment(id: UUID) -> UUID? {
        guard let index = project.segments.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = project.segments[index]
        copy.id = UUID()
        copy.start += 0.1
        copy.end = max(copy.start + 0.5, copy.end + 0.1)
        project.segments.append(copy)
        project.segments.sort { $0.start < $1.start }
        project.recalculateStage()
        persistNow()
        return copy.id
    }

    func deleteSegment(id: UUID) {
        project.segments.removeAll { $0.id == id }
        project.recalculateStage()
        persistNow()
    }

    @discardableResult
    func splitSegment(id: UUID) -> UUID? {
        guard let index = project.segments.firstIndex(where: { $0.id == id }) else { return nil }
        let segment = project.segments[index]
        let midpoint = (segment.start + segment.end) / 2
        guard segment.end - segment.start >= 0.8 else { return nil }
        var first = segment
        first.end = midpoint
        var second = segment
        second.id = UUID()
        second.start = midpoint
        project.segments[index] = first
        project.segments.append(second)
        project.segments.sort { $0.start < $1.start }
        project.recalculateStage()
        persistNow()
        return second.id
    }

    func applyVoiceToAll(voice: VoiceChoice, rate: Double? = nil, pitch: Double? = nil) {
        project.defaultVoice = voice
        if let rate { project.voiceRate = rate.clamped(to: 0.5...2.0) }
        if let pitch { project.voicePitch = pitch.clamped(to: 0.5...2.0) }
        for index in project.segments.indices {
            project.segments[index].voice = voice
            if let rate { project.segments[index].rate = rate.clamped(to: 0.5...2.0) }
            if let pitch { project.segments[index].pitch = pitch.clamped(to: 0.5...2.0) }
        }
        persistNow()
        toasts?.show(localization?.t("toast.saved") ?? "Saved")
    }

    func applyVoice(voice: VoiceChoice, toSpeaker speaker: String) {
        for index in project.segments.indices where project.segments[index].speaker == speaker {
            project.segments[index].voice = voice
        }
        persistNow()
    }

    func resetVoice(for id: UUID) {
        guard let index = project.segments.firstIndex(where: { $0.id == id }) else { return }
        project.segments[index].voice = project.defaultVoice
        project.segments[index].rate = project.voiceRate
        project.segments[index].pitch = project.voicePitch
        persistNow()
    }

    func setStart(_ value: Double, for id: UUID) {
        guard let index = project.segments.firstIndex(where: { $0.id == id }) else { return }
        let limit = project.duration > 0 ? project.duration : max(value + 0.5, 1)
        let start = value.clamped(to: 0...max(0, limit - 0.1))
        project.segments[index].start = start
        if project.segments[index].end <= start + 0.1 {
            project.segments[index].end = min(limit, start + 0.5)
        }
        project.segments.sort { $0.start < $1.start }
    }

    func setEnd(_ value: Double, for id: UUID) {
        guard let index = project.segments.firstIndex(where: { $0.id == id }) else { return }
        let limit = project.duration > 0 ? project.duration : max(value, 1)
        let minimum = project.segments[index].start + 0.1
        project.segments[index].end = value.clamped(to: minimum...max(minimum, limit))
    }

    func clearTranslationError() {
        translationError = nil
    }

    func clearTranscriptionError() {
        transcriptionError = nil
    }

    // MARK: - Media

    func ensureWaveform() async {
        guard project.waveform.isEmpty else { return }
        guard let url = AppFiles.mediaURL(for: project) else { return }
        do {
            let values = try await WaveformGenerator.generate(from: url, bars: 112)
            if !values.isEmpty {
                project.waveform = values
                scheduleSave()
            }
        } catch {
            project.waveform = WaveformFallback.stable(seed: project.id.uuidString, count: 96)
            scheduleSave()
        }
    }

    func addMedia(stagedURL: URL, info: MediaInfo) async throws {
        try MediaImporter.addMedia(stagedURL: stagedURL, info: info, to: &project)
        project.recalculateStage()
        if let url = AppFiles.mediaURL(for: project) {
            let values = try? await WaveformGenerator.generate(from: url, bars: 112)
            if let values, !values.isEmpty {
                project.waveform = values
            } else {
                project.waveform = WaveformFallback.stable(seed: project.id.uuidString, count: 96)
            }
        }
        persistNow()
    }

    // MARK: - Transcription

    func startTranscription(replace: Bool) {
        guard !isTranscribing else { return }
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            await self?.runTranscription(replace: replace)
        }
    }

    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
    }

    private func runTranscription(replace: Bool) async {
        guard let settings, let localization else { return }
        guard let mediaURL = AppFiles.mediaURL(for: project) else {
            transcriptionError = localization.t("transcribe.demoNoMedia")
            return
        }
        guard let configuration = settings.aiConfiguration else {
            transcriptionError = localization.t("error.missingKey")
            return
        }
        isTranscribing = true
        transcriptionError = nil
        transcriptionPhase = .extracting
        transcriptionProgress = 0
        defer {
            isTranscribing = false
            transcriptionPhase = nil
            transcriptionTask = nil
        }
        do {
            let service = OpenAIService(configuration: configuration)
            let lines = try await service.transcribe(
                mediaURL: mediaURL,
                duration: project.duration,
                language: project.sourceLanguage
            ) { [weak self] phase, value in
                self?.transcriptionPhase = phase
                self?.transcriptionProgress = value.clamped(to: 0...1)
            }
            try Task.checkCancellation()
            if replace {
                project.segments.removeAll()
            }
            let speaker = localization.t("segment.speakerPlaceholder")
            let newSegments = lines.map { line in
                DubSegment(
                    start: max(0, line.start),
                    end: max(line.start + 0.2, line.end),
                    speaker: speaker,
                    originalText: line.text.trimmed,
                    translatedText: "",
                    voice: project.defaultVoice,
                    rate: project.voiceRate,
                    pitch: project.voicePitch
                )
            }
            project.segments.append(contentsOf: newSegments)
            project.segments.sort { $0.start < $1.start }
            project.recalculateStage()
            persistNow()
            Haptics.success()
            toasts?.show(localization.f("transcribe.segmentsFound", newSegments.count))
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                transcriptionError = ErrorPresenter.message(for: error, localization: localization)
                Haptics.error()
            }
        }
    }

    // MARK: - Translation

    func startTranslation(mode: TranslationMode) {
        guard !isTranslating else { return }
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            await self?.runTranslation(mode: mode)
        }
    }

    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        isTranslating = false
    }

    private func runTranslation(mode: TranslationMode) async {
        guard let settings, let localization else { return }
        guard let configuration = settings.aiConfiguration else {
            translationError = localization.t("error.missingKey")
            return
        }
        let eligible = project.segments.filter { segment in
            guard !segment.originalText.trimmed.isEmpty else { return false }
            switch mode {
            case .all: return true
            case .emptyOnly: return !segment.isTranslated
            }
        }
        guard !eligible.isEmpty else {
            translationError = localization.t("error.empty")
            return
        }
        isTranslating = true
        translationError = nil
        translationProgress = 0.08
        defer {
            isTranslating = false
            translationTask = nil
        }
        do {
            let service = OpenAIService(configuration: configuration)
            translationProgress = 0.2
            let translations = try await service.translate(
                segments: eligible,
                sourceLanguage: project.sourceLanguage,
                style: project.style,
                glossary: settings.glossary,
                preserveNames: true
            )
            try Task.checkCancellation()
            translationProgress = 0.86
            for index in project.segments.indices {
                let id = project.segments[index].id
                if let text = translations[id]?.trimmed, !text.isEmpty {
                    project.segments[index].translatedText = text
                }
            }
            project.recalculateStage()
            translationProgress = 1
            persistNow()
            Haptics.success()
            toasts?.show(localization.t("translate.done"))
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                translationError = ErrorPresenter.message(for: error, localization: localization)
                Haptics.error()
            }
        }
    }

    func startTranslateSegment(id: UUID) {
        guard !isTranslating else { return }
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            await self?.runTranslateSegment(id: id)
        }
    }

    private func runTranslateSegment(id: UUID) async {
        guard let settings, let localization else { return }
        guard let configuration = settings.aiConfiguration else {
            translationError = localization.t("error.missingKey")
            return
        }
        guard let index = project.segments.firstIndex(where: { $0.id == id }) else { return }
        let segment = project.segments[index]
        guard !segment.originalText.trimmed.isEmpty else {
            translationError = localization.t("error.empty")
            return
        }
        isTranslating = true
        translationError = nil
        translationProgress = 0.2
        defer {
            isTranslating = false
            translationTask = nil
        }
        do {
            let service = OpenAIService(configuration: configuration)
            let translations = try await service.translate(
                segments: [segment],
                sourceLanguage: project.sourceLanguage,
                style: project.style,
                glossary: settings.glossary,
                preserveNames: true
            )
            try Task.checkCancellation()
            if let text = translations[id]?.trimmed, !text.isEmpty {
                if let currentIndex = project.segments.firstIndex(where: { $0.id == id }) {
                    project.segments[currentIndex].translatedText = text
                }
                project.recalculateStage()
                translationProgress = 1
                persistNow()
                Haptics.success()
                toasts?.show(localization.t("translate.singleDone"))
            } else {
                throw AIServiceError.emptyResponse
            }
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                translationError = ErrorPresenter.message(for: error, localization: localization)
                Haptics.error()
            }
        }
    }

    func startPolish(id: UUID) {
        guard !isTranslating else { return }
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            await self?.runPolish(id: id)
        }
    }

    private func runPolish(id: UUID) async {
        guard let settings, let localization else { return }
        guard let configuration = settings.aiConfiguration else {
            translationError = localization.t("error.missingKey")
            return
        }
        guard
            let index = project.segments.firstIndex(where: { $0.id == id }),
            project.segments[index].isTranslated
        else {
            translationError = localization.t("error.noTranslatedText")
            return
        }
        isTranslating = true
        translationError = nil
        translationProgress = 0.25
        defer {
            isTranslating = false
            translationTask = nil
        }
        do {
            let service = OpenAIService(configuration: configuration)
            let text = try await service.polishKhmer(
                project.segments[index].translatedText,
                style: project.style
            )
            try Task.checkCancellation()
            if let currentIndex = project.segments.firstIndex(where: { $0.id == id }) {
                project.segments[currentIndex].translatedText = text
            }
            project.recalculateStage()
            translationProgress = 1
            persistNow()
            Haptics.success()
            toasts?.show(localization.t("translate.singleDone"))
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                translationError = ErrorPresenter.message(for: error, localization: localization)
                Haptics.error()
            }
        }
    }

    // MARK: - Subtitles (SRT)

    @discardableResult
    func importSRT(url: URL, replace: Bool = false) -> Int {
        do {
            let loadedSegments = try SubtitleImporter.load(
                from: url,
                defaultVoice: project.defaultVoice,
                rate: project.voiceRate,
                pitch: project.voicePitch,
                speaker: localization?.t("segment.speakerPlaceholder") ?? "Speaker 1"
            )
            guard !loadedSegments.isEmpty else { return 0 }
            if replace {
                project.segments = loadedSegments
            } else {
                project.segments.append(contentsOf: loadedSegments)
            }
            project.segments.sort { $0.start < $1.start }
            project.recalculateStage()
            persistNow()
            Haptics.success()
            if let localization {
                toasts?.show(localization.f("srt.importedCount", loadedSegments.count))
            }
            return loadedSegments.count
        } catch {
            if let localization {
                toasts?.show(localization.t("srt.importFailed"))
            }
            return 0
        }
    }

    // MARK: - Export

    func startExport(format: ExportFormat, includeSubtitles: Bool) {
        guard !isExporting else { return }
        exportTask?.cancel()
        exportTask = Task { [weak self] in
            await self?.runExport(format: format, includeSubtitles: includeSubtitles)
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
    }

    private func runExport(format: ExportFormat, includeSubtitles: Bool) async {
        guard let settings, let localization else { return }
        guard includedTranslatedSegments.count > 0 else {
            exportError = localization.t("error.noTranslatedText")
            return
        }
        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "KhmerDub.Export") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
        isExporting = true
        exportError = nil
        exportProgress = 0
        exportPhase = .voices
        lastExport = nil
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
            isExporting = false
            exportPhase = nil
            exportTask = nil
        }
        do {
            project.includeSubtitles = includeSubtitles
            let result = try await DubExporter.shared.export(
                project: project,
                settings: settings,
                format: format,
                includeSubtitles: includeSubtitles
            ) { [weak self] phase, value in
                self?.exportPhase = phase
                self?.exportProgress = value.clamped(to: 0...1)
            }
            try Task.checkCancellation()
            let now = Date()
            var records: [ExportRecord] = [
                ExportRecord(
                    fileName: result.url.lastPathComponent,
                    kind: result.kind,
                    createdAt: now,
                    duration: result.duration,
                    fileSize: result.fileSize
                )
            ]
            if let subtitleURL = result.subtitleURL {
                records.append(
                    ExportRecord(
                        fileName: subtitleURL.lastPathComponent,
                        kind: .subtitle,
                        createdAt: now,
                        duration: result.duration,
                        fileSize: fileSize(at: subtitleURL)
                    )
                )
            }
            project.exports.append(contentsOf: records)
            project.stage = .exported
            project.touch()
            persistNow()
            lastExport = result
            Haptics.success()
            toasts?.show(localization.t("toast.exported"))
        } catch {
            if !(error is CancellationError) {
                exportError = ErrorPresenter.message(for: error, localization: localization)
                Haptics.error()
            }
        }
    }

    func saveLastVideoToPhotos() async {
        guard let localization, let lastExport else { return }
        guard lastExport.kind == .video else {
            exportError = localization.t("export.videoNeedsMedia")
            return
        }
        isSavingPhoto = true
        exportError = nil
        defer { isSavingPhoto = false }
        do {
            try await PhotoLibrarySaver.saveVideo(at: lastExport.url)
            Haptics.success()
            toasts?.show(localization.t("toast.photoSaved"))
        } catch {
            exportError = ErrorPresenter.message(for: error, localization: localization)
            Haptics.error()
        }
    }

    func clearExportError() {
        exportError = nil
    }

    func deleteExport(_ record: ExportRecord) {
        let url = AppFiles.exportURL(for: project, fileName: record.fileName)
        try? FileManager.default.removeItem(at: url)
        project.exports.removeAll { $0.id == record.id }
        if let lastExport, lastExport.url.lastPathComponent == record.fileName {
            self.lastExport = nil
        }
        project.recalculateStage()
        persistNow()
    }

    private func persistNow() {
        saveTask?.cancel()
        saveTask = nil
        store?.upsert(project, immediate: true)
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
