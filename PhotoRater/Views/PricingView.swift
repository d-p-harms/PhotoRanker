// PricingView.swift
// Updated to work with StoreKit 2 APIs and new pricing

import SwiftUI
import StoreKit

struct PricingView: View {
    @StateObject private var pricingManager = PricingManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedProductID: PricingManager.ProductID = .starter
    
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
                    
                    // Current credits display with 2-week promo info
                    if pricingManager.userCredits > 0 {
                        VStack(spacing: 8) {
                            Text("You have \(pricingManager.userCredits) credits remaining")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            
                            // Show launch promo status
                            if isLaunchPeriod {
                                Text("🎉 Launch Special Active: New users get 15 free analyses!")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(6)
                                
                                Text("Ends August 24, 2025")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("⚡ You're out of credits!")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            
                            if isLaunchPeriod {
                                Text("🎉 New users get 15 free analyses during our launch special!")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    // Pricing tiers using actual StoreKit products
                    VStack(spacing: 16) {
                        ForEach(pricingManager.products, id: \.id) { product in
                            if let productID = PricingManager.ProductID(rawValue: product.id) {
                                ProductCard(
                                    product: product,
                                    productID: productID,
                                    isSelected: selectedProductID == productID,
                                    showBadge: productID == .value
                                ) {
                                    selectedProductID = productID
                                }
                            }
                        }
                        
                        // Show loading state if products haven't loaded yet
                        if pricingManager.products.isEmpty {
                            VStack {
                                ProgressView()
                                    .padding()
                                Text("Loading pricing options...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 100)
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
                            
                            Text(pricingManager.isLoading ? "Processing..." : "Get \(selectedProductID.tier.title)")
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
                    .disabled(pricingManager.isLoading || pricingManager.products.isEmpty)
                    .padding(.horizontal)
                    
                    // Restore purchases button
                    Button("Restore Purchases") {
                        Task {
                            await pricingManager.restorePurchases()
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    
                    // Value demonstration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What you get with every analysis:")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "brain.head.profile", text: "AI analysis of photo quality, attractiveness & dating appeal")
                            FeatureRow(icon: "chart.bar.fill", text: "Detailed quality breakdown with visual indicators")
                            FeatureRow(icon: "lightbulb.fill", text: "Technical feedback on lighting, composition & styling")
                            FeatureRow(icon: "person.2.fill", text: "Personality traits your photos project")
                            FeatureRow(icon: "target", text: "Specific improvement suggestions")
                            FeatureRow(icon: "camera.badge.plus", text: "Next photo recommendations for profile balance")
                        }
                    }
                    .padding(.horizontal)
                    
                    // Launch special callout
                    if isLaunchPeriod {
                        VStack(spacing: 8) {
                            Text("🚀 Launch Special")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            
                            Text("New users get 15 FREE analyses!")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Perfect for testing all our AI analysis features")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Ends August 24, 2025")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green, lineWidth: 2)
                        )
                        .padding(.horizontal)
                    }
                    
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
                            .italic()
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
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
    
    private var isLaunchPeriod: Bool {
        let launchDate = Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 10))!
        let promotionEnd = Calendar.current.date(byAdding: .day, value: 14, to: launchDate)!
        return Date() >= launchDate && Date() < promotionEnd
    }
    
    private func purchaseSelected() {
        Task {
            await pricingManager.purchaseProduct(selectedProductID)
        }
    }
}

struct ProductCard: View {
    let product: Product
    let productID: PricingManager.ProductID
    let isSelected: Bool
    let showBadge: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(productID.tier.title)
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
                            
                            if let savings = productID.tier.savings {
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
                        
                        Text(productID.tier.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        Text("\(productID.tier.credits) photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let costPerPhoto = product.price / Decimal(productID.tier.credits)
                        Text("$\(NSDecimalNumber(decimal: costPerPhoto).doubleValue, specifier: "%.3f") each")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Value comparison for best value pack
                if productID == .value {
                    HStack {
                        Text("vs Starter pack:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Save $0.008 per photo!")
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
