// PricingView.swift
// Create new file: PhotoRater/Views/PricingView.swift

import SwiftUI
import StoreKit

struct PricingView: View {
    @StateObject private var pricingManager = PricingManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedTier: PricingManager.PricingTier = .starter
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Text("🎯 Boost Your Dating Success")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("AI-powered photo analysis to maximize your matches")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Current credits display
                    if pricingManager.userCredits > 0 {
                        VStack {
                            Text("You have \(pricingManager.userCredits) credits remaining")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    } else {
                        VStack {
                            Text("⚡ You're out of credits!")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Pricing tiers
                    VStack(spacing: 16) {
                        PricingTierCard(tier: .starter, isSelected: selectedTier == .starter) {
                            selectedTier = .starter
                        }
                        
                        PricingTierCard(tier: .value, isSelected: selectedTier == .value, showBadge: true) {
                            selectedTier = .value
                        }
                    }
                    .padding(.horizontal)
                    
                    // Purchase button
                    Button(action: purchaseSelected) {
                        HStack {
                            if pricingManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            
                            Text(pricingManager.isLoading ? "Processing..." : "Get \(selectedTier.title)")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .disabled(pricingManager.isLoading)
                    .padding(.horizontal)
                    
                    // Value demonstration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What you get with every analysis:")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "brain.head.profile", text: "AI analysis of photo quality, attractiveness & dating appeal")
                            FeatureRow(icon: "chart.bar.fill", text: "Detailed scores: Visual Quality, Swipe Appeal & more")
                            FeatureRow(icon: "lightbulb.fill", text: "Technical feedback on lighting, composition & styling")
                            FeatureRow(icon: "person.2.fill", text: "Personality traits your photos project")
                            FeatureRow(icon: "target", text: "Specific improvement suggestions")
                            FeatureRow(icon: "camera.badge.plus", text: "Next photo recommendations for profile balance")
                        }
                    }
                    .padding(.horizontal)
                    
                    // Social proof
                    VStack(spacing: 8) {
                        HStack {
                            ForEach(0..<5) { _ in
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                            Text("4.8")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        Text("\"Helped me pick photos that actually got matches!\"")
                            .font(.caption)
                            .fontStyle(.italic)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
                    // Risk reduction
                    VStack(spacing: 4) {
                        Text("💯 Satisfaction Guaranteed")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Not happy? Full refund within 7 days")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Choose Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func purchaseSelected() {
        guard let productID = PricingManager.ProductID.allCases.first(where: { $0.tier.title == selectedTier.title }) else {
            print("Product ID not found for tier: \(selectedTier.title)")
            return
        }
        
        pricingManager.purchaseProduct(productID)
    }
}

struct PricingTierCard: View {
    let tier: PricingManager.PricingTier
    let isSelected: Bool
    let showBadge: Bool
    let action: () -> Void
    
    init(tier: PricingManager.PricingTier, isSelected: Bool, showBadge: Bool = false, action: @escaping () -> Void) {
        self.tier = tier
        self.isSelected = isSelected
        self.showBadge = showBadge
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tier.title)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            if showBadge {
                                Text("BEST VALUE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .cornerRadius(4)
                            }
                            
                            if let savings = tier.savings {
                                Text(savings)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(tier.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$\(tier.price, specifier: "%.2f")")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        Text("\(tier.credits) photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("$\(tier.costPerPhoto, specifier: "%.3f") each")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Value comparison
                if tier == .value {
                    HStack {
                        Text("vs $0.99 pack:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Save $2.00+ per photo!")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(
                Group {
                    if showBadge {
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else if isSelected {
                        Color.blue.opacity(0.1)
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        showBadge ? Color.green : (isSelected ? Color.blue : Color.clear),
                        lineWidth: showBadge ? 2 : (isSelected ? 2 : 0)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}
