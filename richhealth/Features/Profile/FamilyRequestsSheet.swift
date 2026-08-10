import SwiftUI

/// Half-screen glass bottom sheet listing incoming family (relative) requests with
/// Accept / Decline — mirrors the Doctor incoming-requests UI and the chat-history
/// sheet's presentation ([.medium, .large] + drag indicator). The backend flow
/// existed; there was no surface for the recipient to act on a request.
struct FamilyRequestsSheet: View {
    /// Called after a request is accepted/declined so the caller can refresh its badge.
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var requests: [IncomingFamilyRequest] = []
    @State private var inFlight: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let service = FamilyService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if requests.isEmpty {
                    ContentUnavailableView(
                        "No Requests",
                        systemImage: "person.2",
                        description: Text("You have no pending family requests."))
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(requests) { req in
                                FamilyRequestRow(req: req, isBusy: inFlight.contains(req.id)) { accept in
                                    Task { await respond(req, accept: accept) }
                                }
                            }
                        }
                        .padding(Theme.Spacing.m)
                    }
                }
            }
            .navigationTitle("Family Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
            .task { await load() }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await service.fetchIncomingRequests()
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? "Couldn't load requests."
        }
    }

    private func respond(_ req: IncomingFamilyRequest, accept: Bool) async {
        guard !inFlight.contains(req.id) else { return }   // guard against double-tap
        inFlight.insert(req.id)
        defer { inFlight.remove(req.id) }                  // re-enables the row on failure
        do {
            try await service.respondToRequest(email: req.email, accept: accept)
            requests.removeAll { $0.id == req.id }
            onChanged()
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? "Couldn't update the request."
        }
    }
}

private struct FamilyRequestRow: View {
    let req: IncomingFamilyRequest
    let isBusy: Bool
    let onRespond: (Bool) -> Void

    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(req.name ?? req.email)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Theme.Spacing.s) {
                    Button("Accept") { onRespond(true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandTeal)
                        .font(.caption)
                    Button("Decline") { onRespond(false) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
                .disabled(isBusy)
            }
        }
    }

    private var subtitle: String {
        if let r = req.relationship, !r.isEmpty { return "Wants to connect as \(r)" }
        return "Wants to connect with you as family"
    }
}
