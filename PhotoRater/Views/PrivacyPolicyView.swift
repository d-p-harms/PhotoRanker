import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader("Data Collection")
                    Text("We only collect the photos you choose to analyze along with minimal usage metadata. No personal information is required to use PhotoRater.")
                        .font(.body)

                    SectionHeader("Photo Processing")
                    Text("Your photos are processed using our AI models to generate rankings and recommendations. Processing may occur on device or on secure servers.")
                        .font(.body)

                    SectionHeader("Storage")
                    Text("Photos and analysis results are temporarily stored in Firebase to sync across your devices. Data is retained for up to 30 days then automatically deleted.")
                        .font(.body)

                    SectionHeader("Sharing")
                    Text("We do not sell or share your photos or personal data with any third parties. Data is used solely to provide the app's core functionality.")
                        .font(.body)

                    SectionHeader("User Rights")
                    Text("You may request deletion of your stored photos at any time from the account screen. For any privacy questions contact us at support@photorater.app.")
                        .font(.body)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Decline") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Accept") {
                        PrivacyPolicyManager.shared.acceptPrivacyPolicy()
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func SectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.top)
    }
}

#Preview {
    PrivacyPolicyView()
}
