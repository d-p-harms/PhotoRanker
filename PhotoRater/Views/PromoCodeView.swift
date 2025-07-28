// PromoCodeView.swift
// Fixed version that resolves all compilation errors

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
                    .scaleEffect(promoManager.isValidating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: promoManager.isValidating)
            }
            
            VStack(spacing: 8) {
                Text("Redeem Promo Code")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter your promo code to unlock additional credits and features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 20) {
            // Text Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Promo Code")
                    .font(.headline)
                    .fontWeight(.medium)
                
                TextField("Enter code here", text: $promoCode)
                    .textFieldStyle(CustomTextFieldStyle())
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .textCase(.uppercase)
                    .disabled(promoManager.isValidating)
                    .onSubmit {
                        if !promoCode.isEmpty && !promoManager.isValidating {
                            redeemCode()
                        }
                    }
                
                Text("Promo codes are case-insensitive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Redeem Button
            Button(action: redeemCode) {
                HStack(spacing: 12) {
                    if promoManager.isValidating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                    }
                    
                    Text(promoManager.isValidating ? "Validating Code..." : "Redeem Code")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
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
                
                Text("How to Get Promo Codes")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(spacing: 16) {
                InfoRow(
                    icon: "heart.fill",
                    iconColor: .red,
                    title: "Leave a Review",
                    description: "Rate us on the App Store for exclusive codes"
                )
                
                InfoRow(
                    icon: "envelope.fill",
                    iconColor: .blue,
                    title: "Newsletter",
                    description: "Subscribe for special promotions and updates"
                )
                
                InfoRow(
                    icon: "person.3.fill",
                    iconColor: .green,
                    title: "Refer Friends",
                    description: "Share the app and earn bonus credits"
                )
                
                InfoRow(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "Special Events",
                    description: "Follow our social media for limited-time codes"
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
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

// MARK: - Supporting Views

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.title3)
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
    }
}

struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
    }
}

#Preview {
    PromoCodeView()
}
