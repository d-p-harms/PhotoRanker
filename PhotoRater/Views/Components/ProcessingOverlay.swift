//
//  ProcessingOverlay.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//
import SwiftUI

struct ProcessingOverlay: View {
    let message: String
    let progress: Double?
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(.headline)
            
            if let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(width: 200)
            }
        }
        .padding(30)
        .background(
            Color(.systemBackground)
                .opacity(0.95)
        )
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}
