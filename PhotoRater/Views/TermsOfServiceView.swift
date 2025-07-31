import SwiftUI

struct TermsOfServiceView: View {
    var onAccept: () -> Void = {}
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Service Description")
                            .font(.headline)
                        Text("PhotoRater provides AI-based recommendations on the quality and dating profile suitability of your photos. Results are generated automatically and may not always be accurate.")
                        Text("User Obligations")
                            .font(.headline)
                        Text("You agree to use PhotoRater responsibly and only upload photos that you own or have permission to use. Users must be at least 17 years old.")
                        Text("Prohibited Content")
                            .font(.headline)
                        Text("Uploading inappropriate, explicit, or illegal images is strictly forbidden and will result in immediate account termination.")
                        Text("Payments")
                            .font(.headline)
                        Text("Subscriptions and credit purchases are processed through Apple. All sales are final and subject to Apple's terms.")
                        Text("Liability")
                            .font(.headline)
                        Text("PhotoRater's AI analysis is provided \"as is\" without warranty of accuracy. We are not liable for any actions taken based on the recommendations.")
                    }
                    .padding()
                }

                HStack(spacing: 20) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Decline")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.red)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    Button(action: {
                        onAccept()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Accept")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    TermsOfServiceView()
}
