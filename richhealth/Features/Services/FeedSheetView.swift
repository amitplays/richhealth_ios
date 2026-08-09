import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
private final class FeedSheetVM {
    var items: [FeedItem] = []
    var currentPage = 1
    var totalPages = 1
    var isLoading = false
    var isLoadingMore = false
    var selectedType: String? = nil  // nil = all, "article", "news", "podcast"

    private let service = FeedService()

    var hasMore: Bool { currentPage < totalPages }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        currentPage = 1
        guard let r = try? await service.fetchFeed(page: 1, limit: 20, type: selectedType) else { return }
        items = r.items
        totalPages = r.totalPages
        currentPage = r.page
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = currentPage + 1
        guard let r = try? await service.fetchFeed(page: next, limit: 20, type: selectedType) else { return }
        items.append(contentsOf: r.items)
        currentPage = r.page
        totalPages = r.totalPages
    }

    func changeFilter(_ type: String?) async {
        selectedType = type
        await load()
    }
}

// MARK: - View

struct FeedSheetView: View {
    @State private var vm = FeedSheetVM()

    private let types: [(label: String, value: String?)] = [
        ("All",      nil),
        ("Articles", "article"),
        ("News",     "news"),
        ("Podcasts", "podcast"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Type filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(types, id: \.label) { tab in
                            Button(tab.label) {
                                Task { await vm.changeFilter(tab.value) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.xs)
                            .foregroundStyle(vm.selectedType == tab.value ? .white : Theme.brandTeal) // white: contrast on teal chip
                            .glassEffect(
                                vm.selectedType == tab.value
                                    ? .regular.tint(Theme.brandTeal).interactive()
                                    : .regular.interactive(),
                                in: .capsule
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                }
                .background(.regularMaterial)

                Group {
                    if vm.isLoading {
                        feedSkeleton
                    } else if vm.items.isEmpty {
                        ContentUnavailableView("No Articles", systemImage: "newspaper")
                    } else {
                        feedList
                    }
                }
            }
            .navigationTitle("Health Feed")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await vm.load() }
    }

    // MARK: - List

    private var feedList: some View {
        List {
            ForEach(vm.items) { item in
                FeedItemRow(item: item)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear {
                        if item.id == vm.items.last?.id {
                            Task { await vm.loadMore() }
                        }
                    }
            }

            if vm.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.load() }
    }

    // MARK: - Skeleton

    private var feedSkeleton: some View {
        List {
            ForEach(0..<8, id: \.self) { _ in
                FeedItemRow(item: .placeholder)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .skeleton(isActive: true)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Feed item row

private struct FeedItemRow: View {
    let item: FeedItem

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    // Thumbnail
                    AsyncImage(url: URL(string: item.imageUrl)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .foregroundStyle(.fill)
                            .overlay(Image(systemName: iconName).foregroundStyle(.tertiary))
                    }
                    .frame(width: 72, height: 72) // feed thumbnail
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.button))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)

                        if let reason = item.reason, !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: Theme.Spacing.xs) {
                            Text(item.category)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if !item.type.isEmpty {
                                Text("· \(item.type.capitalized)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if item.isProOnly {
                                StatusPill(text: "Pro")
                            }
                        }
                    }
                }
            }
        }
    }

    private var iconName: String {
        switch item.type {
        case "podcast": return "mic.fill"
        case "news":    return "newspaper"
        default:        return "doc.text"
        }
    }
}
