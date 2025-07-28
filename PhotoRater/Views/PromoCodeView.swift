// PromoCodeView.swift
// Fixed UI for entering and redeeming promo codes

import SwiftUI

struct PromoCodeView: View {
    @StateObject private var promoManager = PromoCodeManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var promoCode = ""
    @State private var showingSuccessAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Promo Code")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Enter your promo code to unlock credits")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Input section
                VStack(spacing: 16) {
                    TextField("Enter promo code", text: $promoCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .font(.headline)
                        .textCase(.uppercase)
                        .onSubmit {
                            if !promoCode.isEmpty {
                                redeemCode()
                            }
                        }
                    
                    Button(action: redeemCode) {
                        HStack {
                            if promoManager.isValidating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            
                            Text(promoManager.isValidating ? "Validating..." : "Redeem Code")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            promoCode.isEmpty ? Color.gray : Color.green
                        )
                        .cornerRadius(10)
                    }
                    .disabled(promoCode.isEmpty || promoManager.isValidating)
                }
                .padding(.horizontal, 20)
                
                // Feedback message
                if let message = promoManager.redemptionMessage {
                    VStack(spacing: 12) {
                        Text(message)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(promoManager.isSuccess ? .green : .red)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(
                                (promoManager.isSuccess ? Color.green : Color.red).opacity(0.1)
                            )
                            .cornerRadius(10)
                        
                        if promoManager.isSuccess {
                            Button("Continue") {
                                presentationMode.wrappedValue.dismiss()
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Info section
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to get promo codes:")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        PromoInfoRow(icon: "envelope.fill", text: "Follow us on social media for exclusive codes")
                        PromoInfoRow(icon: "megaphone.fill", text: "Sign up for our newsletter")
                        PromoInfoRow(icon: "person.3.fill", text: "Refer friends to earn bonus credits")
                        PromoInfoRow(icon: "gift.fill", text: "Special launch promotions")
                    }
                }
                .padding(.horizontal, 20)
                
                // Debug info for development (remove for production)
                #if DEBUG
                VStack(alignment: .leading, spacing: 8) {
                    Text("🔧 Development Codes:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["APPSTORE2025", "REVIEWER", "LAUNCH50", "TESTFLIGHT", "UNLIMITED"], id: \.self) { code in
                                Button(code) {
                                    promoCode = code
                                }
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
                .padding(.horizontal, 20)
                #endif
                
                Spacer(minLength: 20)
            }
            .navigationTitle("Promo Code")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func redeemCode() {
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        Task {
            let result = await promoManager.redeemPromoCode(promoCode)
            
            await MainActor.run {
                switch result {
                case .success(_):
                    self.showingSuccessAlert = true
                    // Clear the input after a delay so user sees what they entered
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.promoCode = ""
                    }
                case .failure(_):
                    // Error message is already shown via promoManager.redemptionMessage
                    break
                }
            }
        }
    }
}

struct PromoInfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

#Preview {
    PromoCodeView()
}
