
// PromoCodeView.swift
// Final production version for promo code redemption UI

import SwiftUI
import FirebaseAuth

struct PromoCodeView: View {
    @StateObject private var promoManager = PromoCodeManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var promoCode = ""
    @State private var showingKeyboard = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Header Section
                    headerSection
                    
                    // Input Section
                    inputSection
                    
                    // Feedback Section
                    if let message = promoManager.redemptionMessage {
                        feedbackSection(message: message)
                    }
                    
                    // Info Section
                    infoSection
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .navigationTitle("Promo Code")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    hideKeyboard()
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onTapGesture {
                hideKeyboard()
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green.opacity(0.2), Color.blue.opacity(0.2)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "gift.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                    .scaleEffect(promoManager.isValidating ? 0.9 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatCount(promoManager.isValidating ? .max : 0), value: promoManager.isValidating)
            }
            
            VStack(spacing: 8) {
                Text("Redeem Promo Code")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Enter your promo code to unlock exclusive benefits")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 20) {
            // Input Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Promo Code")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                TextField("Enter promo code", text: $promoCode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .font(.title3)
                    .fontWeight(.medium)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(promoCode.isEmpty ? Color.gray.opacity(0.3) : Color.blue, lineWidth: 2)
                    )
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        showingKeyboard = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        showingKeyboard = false
                    }
            }
            
            // Redeem Button
            Button(action: redeemCode) {
                HStack(spacing: 12) {
                    if promoManager.isValidating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        
                        Text("Validating...")
                            .font(.headline)
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "gift.fill")
                            .font(.title3)
                        
                        Text("Redeem Code")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(buttonColor)
                )
                .scaleEffect(promoManager.isValidating ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: promoManager.isValidating)
            }
            .disabled(promoCode.isEmpty || promoManager.isValidating)
        }
    }
    
    private func feedbackSection(message: String) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: promoManager.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(promoManager.isSuccess ? .green : .red)
                
                Text(message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(promoManager.isSuccess ? .green : .red)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill((promoManager.isSuccess ? Color.green : Color.red).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke((promoManager.isSuccess ? Color.green : Color.red).opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Success Action Button
            if promoManager.isSuccess {
                Button("Continue") {
                    presentationMode.wrappedValue.dismiss()
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green)
                )
            }
        }
        .transition(.slide)
        .animation(.easeInOut, value: promoManager.redemptionMessage)
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                
                Text("About Promo Codes")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(spacing: 16) {
                InfoRow(
                    icon: "shield.fill",
                    iconColor: .blue,
                    title: "Secure Codes",
                    description: "12-character alphanumeric codes for security"
                )
                
                InfoRow(
                    icon: "clock.fill",
                    iconColor: .orange,
                    title: "Limited Availability",
                    description: "Exclusive codes with usage limits"
                )
                
                InfoRow(
                    icon: "checkmark.seal.fill",
                    iconColor: .purple,
                    title: "One-Time Use",
                    description: "Each code can only be used once per account"
                )
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Computed Properties
    
    private var buttonColor: Color {
        if promoCode.isEmpty {
            return Color.gray
        } else if promoManager.isValidating {
            return Color.blue.opacity(0.8)
        } else {
            return Color.green
        }
    }
    
    // MARK: - Actions
    
    private func redeemCode() {
        guard !promoCode.isEmpty && !promoManager.isValidating else { return }
        
        hideKeyboard()
        
        Task {
            let result = await promoManager.redeemPromoCode(promoCode)
            
            await MainActor.run {
                switch result {
                case .success(_):
                    // Success message is handled by the manager
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.promoCode = ""
                    }
                    
                case .failure(let error):
                    print("❌ Promo code redemption failed: \(error)")
                    // Error message is handled by the manager
                }
            }
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

struct PromoCodeView_Previews: PreviewProvider {
    static var previews: some View {
        PromoCodeView()
    }
}
