import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MediaPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: Localization
    var onPicked: (URL, MediaInfo) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isInspecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    SheetHeader(
                        title: loc.t("studio.addMedia"),
                        subtitle: loc.t("import.subtitle"),
                        onClose: { dismiss() }
                    )
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $photoItem, matching: .videos) {
                            pickerTile(
                                symbol: "photo.on.rectangle.angled",
                                title: loc.t("import.fromPhotos"),
                                tint: AppTheme.goldDeep
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                        Button {
                            showFileImporter = true
                        } label: {
                            pickerTile(
                                symbol: "folder",
                                title: loc.t("import.fromFiles"),
                                tint: AppTheme.tealDeep
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                    if let errorMessage {
                        InlineBanner(kind: .error, text: errorMessage)
                    }
                    Spacer()
                }
                .padding(20)
                if isInspecting {
                    LoadingOverlay(text: loc.t("import.analyzing"))
                }
            }
            .navigationBarHidden(true)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await inspectFile(url) }
            case .failure(let error):
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await inspectPhoto(item) }
        }
        .presentationDetents([.medium, .large])
    }

    private func pickerTile(symbol: String, title: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private func inspectPhoto(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isInspecting = true
            errorMessage = nil
        }
        do {
            guard let movie = try await item.loadTransferable(type: MovieTransferable.self) else {
                throw MediaError.invalidFile
            }
            let info = try await MediaImporter.inspect(url: movie.url)
            await MainActor.run {
                isInspecting = false
                onPicked(movie.url, info)
                dismiss()
            }
        } catch {
            await MainActor.run {
                isInspecting = false
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
            }
        }
    }

    private func inspectFile(_ url: URL) async {
        await MainActor.run {
            isInspecting = true
            errorMessage = nil
        }
        do {
            let staged = try await Task.detached(priority: .userInitiated) {
                try MediaImporter.stageImport(from: url)
            }.value
            let info = try await MediaImporter.inspect(url: staged)
            await MainActor.run {
                isInspecting = false
                onPicked(staged, info)
                dismiss()
            }
        } catch {
            await MainActor.run {
                isInspecting = false
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
            }
        }
    }
}
