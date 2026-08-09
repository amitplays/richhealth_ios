import SwiftUI

/// Non-sensitive constants used inside the legal content. ⚠️ Replace the support email with a
/// real address, and have the Privacy Policy / Terms text reviewed by counsel before release.
enum LegalInfo {
    static let supportEmail = "support@richhealth.ai"
    static let lastUpdated  = "August 2026"
}

/// Glass bottom-drawer hub for legal & privacy (Profile → Settings → Legal & Privacy).
/// Every item opens IN-APP content — no external browser links.
struct LegalHubSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    emergencyCard

                    row(icon: "hand.raised.fill", title: "Privacy Policy") { privacyPolicy }
                    row(icon: "doc.text.fill", title: "Terms of Use") { termsOfUse }
                    row(icon: "cross.case.fill", title: "Medical Disclaimer") { medicalDisclaimer }
                    row(icon: "questionmark.circle.fill", title: "Support") { support }

                    Text("RichHealth v\(appVersion)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, Theme.Spacing.s)
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Legal & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)   // iOS 26 glass drawer (CLAUDE.md §C5)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Rows

    private func row<Destination: View>(icon: String, title: String,
                                        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            GlassCard {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(Theme.brandTeal)
                        .frame(width: Theme.IconSize.card)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var emergencyCard: some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "cross.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.brandTeal)
                    .frame(width: Theme.IconSize.card)
                Text("In a medical emergency, call your local emergency number immediately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - In-app documents

    private var privacyPolicy: some View {
        LegalDocumentView(
            title: "Privacy Policy",
            intro: "This policy explains what RichHealth collects, how we use it, and the choices you have.",
            sections: [
                ("Information we collect",
                 "• Account details you provide (name, email, phone).\n• Health information you enter — symptoms, measurements, medications, medical reports, and cycle logs.\n• Apple Health & Apple Watch data you choose to sync (e.g. heart rate, steps, sleep).\n• Limited usage analytics — which features you use, as event counts only. This never includes your health data.\n• Basic device and app information."),
                ("How we use your information",
                 "To provide and personalize the app's features, generate the AI insights you request, keep your account secure, and improve the app. We do not use your health information for advertising, and we never sell it."),
                ("AI processing",
                 "When you use Richie, report analysis, health analysis, or NutriCheck, the relevant text or document is sent to trusted AI providers to generate a response. We share only what is needed to perform the task you requested."),
                ("Apple Health",
                 "With your permission, RichHealth reads selected Apple Health / Apple Watch data to display it and — when you choose — save it to your record. It is never used for advertising and never sold. You can revoke access anytime in the Health app or iOS Settings."),
                ("Storage & security",
                 "Your data is stored on secure servers and transmitted over encrypted connections (HTTPS)."),
                ("Sharing",
                 "We share information only with services you actively enable (for example, a doctor you connect) and with the AI providers described above. We do not sell your data or share it with data brokers."),
                ("Your choices",
                 "You can view and edit your data in the app, revoke Apple Health access at any time, and delete your account and associated data from Settings."),
                ("Children",
                 "RichHealth is not intended for children under 16."),
                ("Contact",
                 "Questions about privacy? Email \(LegalInfo.supportEmail).")
            ]
        )
    }

    private var termsOfUse: some View {
        LegalDocumentView(
            title: "Terms of Use",
            intro: "Please read these terms before using RichHealth.",
            sections: [
                ("Wellness, not medical care",
                 "RichHealth provides general wellness and informational content only. It is not a medical device and does not provide medical advice, diagnosis, or treatment, and using it does not create a doctor–patient relationship. Always consult a qualified healthcare professional. In an emergency, call your local emergency number."),
                ("Your responsibilities",
                 "Provide accurate information, keep your login secure, and use the app lawfully. Do not rely on the app for medical decisions."),
                ("Subscriptions",
                 "RichHealth Pro is an auto-renewing subscription sold through Apple. Payment is charged to your Apple ID, renews unless cancelled at least 24 hours before the end of the period, and can be managed or cancelled in Settings → Apple ID → Subscriptions."),
                ("Acceptable use",
                 "Don't misuse the app, attempt to disrupt it, or use it to harm others."),
                ("Disclaimers & liability",
                 "The app and its AI outputs are provided \"as is\" and may be inaccurate. To the extent permitted by law, RichHealth is not liable for decisions made based on the app."),
                ("Changes & termination",
                 "We may update the app and these terms. We may suspend access for violations. You can stop using the app and delete your account at any time."),
                ("Contact",
                 "Questions about these terms? Email \(LegalInfo.supportEmail).")
            ]
        )
    }

    private var medicalDisclaimer: some View {
        LegalDocumentView(
            title: "Medical Disclaimer",
            intro: nil,
            sections: [
                ("Informational use only",
                 "RichHealth provides general wellness and informational content only. It is not a medical device and does not provide medical advice, diagnosis, or treatment."),
                ("AI may be inaccurate",
                 "The insights, analyses, and AI responses in this app — including Richie, report analysis, health analysis, and NutriCheck — are for general information and may be inaccurate. Always consult a qualified healthcare professional about your health and before making any medical decision."),
                ("Emergencies",
                 "If you think you may have a medical emergency, call your local emergency number immediately. Do not rely on this app in emergencies.")
            ]
        )
    }

    private var support: some View {
        LegalDocumentView(
            title: "Support",
            intro: "We're here to help.",
            sections: [
                ("Get in touch",
                 "Email us at \(LegalInfo.supportEmail) and we'll respond as soon as we can."),
                ("Common topics",
                 "• Manage your subscription — Settings → Apple ID → Subscriptions.\n• Apple Health access — iOS Settings → Privacy & Security → Health → RichHealth.\n• Delete your account — Profile → Settings.")
            ]
        )
    }
}

// MARK: - Reusable in-app legal document

private struct LegalDocumentView: View {
    let title: String
    let intro: String?
    let sections: [(String, String)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if let intro {
                    Text(intro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(sections, id: \.0) { section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(section.0).font(.headline)
                        Text(section.1).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text("Last updated: \(LegalInfo.lastUpdated)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, Theme.Spacing.s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { LegalHubSheet() }
