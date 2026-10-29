import SwiftUI

struct ProjectsView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var toasts: ToastCenter

    @State private var path: [UUID] = []
    @State private var showImport = false
    @State private var search = ""
    @State private var filter: ProjectFilter = .all
    @State private var sort: ProjectSort = .recent
    @State private var deleteTarget: DubProject?

    private var projects: [DubProject] {
        var result = store.sortedProjects
        let query = search.trimmed.lowercased()
        if !query.isEmpty {
            result = result.filter { project in
                if project.title.lowercased().contains(query) { return true }
                if project.notes.lowercased().contains(query) { return true }
                return project.segments.contains { segment in
                    segment.originalText.lowercased().contains(query) ||
                    segment.translatedText.lowercased().contains(query) ||
                    segment.speaker.lowercased().contains(query)
                }
            }
        }
        switch filter {
        case .all:
            break
        case .draft:
            result = result.filter { $0.stage == .draft }
        case .progress:
            result = result.filter { $0.stage == .transcribed || $0.stage == .translated }
        case .exported:
            result = result.filter { $0.stage == .exported }
        }
        switch sort {
        case .recent:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .duration:
            result.sort { $0.duration > $1.duration }
        }
        return result
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        searchField
                        filterBar
                        if store.projects.isEmpty {
                            emptyProjects
                        } else if projects.isEmpty {
                            EmptyStateView(
                                symbol: "magnifyingglass",
                                title: loc.t("projects.noMatch"),
                                body: loc.t("projects.empty.body")
                            )
                            .appCard()
                        } else {
                            projectList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { id in
                StudioView(projectID: id)
            }
            .sheet(isPresented: $showImport) {
                ImportView { id in
                    path.append(id)
                }
                .environmentObject(settings)
                .environmentObject(loc)
                .environmentObject(store)
                .environmentObject(toasts)
            }
            .alert(
                Text(loc.t("projects.delete.title")),
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { value in if !value { deleteTarget = nil } }
                )
            ) {
                Button(role: .cancel) {
                    deleteTarget = nil
                } label: {
                    Text(loc.t("common.cancel"))
                }
                Button(role: .destructive) {
                    if let target = deleteTarget {
                        store.delete(target)
                        toasts.show(loc.t("toast.deleted"))
                        Haptics.success()
                    }
                    deleteTarget = nil
                } label: {
                    Text(loc.t("common.delete"))
                }
            } message: {
                Text(loc.t("projects.delete.message"))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t("projects.title"))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(loc.t("projects.subtitle"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Button {
                showImport = true
                Haptics.tap()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x20180A))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.goldGradient))
                    .shadow(color: AppTheme.gold.opacity(0.25), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text(loc.t("home.newDub")))
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
            TextField(loc.t("projects.search"), text: $search)
                .font(.system(size: 14, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ProjectFilter.allCases) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filter = item
                            }
                            Haptics.selection()
                        } label: {
                            Text(loc.t(item.localizationKey))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(filter == item ? Color(hex: 0x20180A) : AppTheme.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(filter == item ? AppTheme.gold : AppTheme.surface)
                                        .overlay(
                                            Capsule()
                                                .stroke(filter == item ? Color.clear : AppTheme.border, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text("\(projects.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Menu {
                    ForEach(ProjectSort.allCases) { item in
                        Button {
                            sort = item
                        } label: {
                            if sort == item {
                                Label(loc.t(item.localizationKey), systemImage: "checkmark")
                            } else {
                                Text(loc.t(item.localizationKey))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(loc.t(sort.localizationKey))
                    }
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var projectList: some View {
        LazyVStack(spacing: 11) {
            ForEach(projects) { project in
                HStack(spacing: 6) {
                    NavigationLink(value: project.id) {
                        ProjectRowView(project: project)
                    }
                    .buttonStyle(.plain)
                    ProjectMenuButton(
                        onDuplicate: { duplicate(project) },
                        onDelete: { deleteTarget = project }
                    )
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )
                .contextMenu {
                    Button {
                        duplicate(project)
                    } label: {
                        Label(loc.t("projects.duplicate"), systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        deleteTarget = project
                    } label: {
                        Label(loc.t("common.delete"), systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyProjects: some View {
        EmptyStateView(
            symbol: "rectangle.stack.badge.plus",
            title: loc.t("projects.empty.title"),
            body: loc.t("projects.empty.body"),
            actionTitle: loc.t("projects.emptyAction"),
            action: { showImport = true }
        )
        .appCard()
    }

    private func duplicate(_ project: DubProject) {
        let title = loc.f("projects.copyName", project.title)
        _ = store.duplicate(project, newTitle: title)
        toasts.show(loc.t("toast.saved"))
        Haptics.success()
    }
}

enum ProjectFilter: String, CaseIterable, Identifiable {
    case all
    case draft
    case progress
    case exported

    var id: String { rawValue }
    var localizationKey: String { "projects.filter.\(rawValue)" }
}

enum ProjectSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case duration

    var id: String { rawValue }
    var localizationKey: String { "projects.sort.\(rawValue)" }
}
