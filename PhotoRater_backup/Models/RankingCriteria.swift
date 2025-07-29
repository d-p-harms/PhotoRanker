import Foundation

enum RankingCriteria: String, CaseIterable {
    case best
    case balanced
    case profileOrder = "profile_order"
    case conversationStarters = "conversation_starters"
    case broadAppeal = "broad_appeal"
    case authenticity = "authenticity"
    
    var title: String {
        switch self {
        case .best: return "Best Overall"
        case .balanced: return "Balanced Set"
        case .profileOrder: return "Profile Order"
        case .conversationStarters: return "Conversation Starters"
        case .broadAppeal: return "Broad Appeal"
        case .authenticity: return "Authenticity Check"
        }
    }
    
    var icon: String {
        switch self {
        case .best: return "trophy"
        case .balanced: return "camera"
        case .profileOrder: return "list.number"
        case .conversationStarters: return "message.circle"
        case .broadAppeal: return "person.3"
        case .authenticity: return "checkmark.seal"
        }
    }
    
    var description: String {
        switch self {
        case .best:
            return "Selects your highest quality photos based on overall appeal for dating profiles."
            
        case .balanced:
            return "Creates a diverse selection with social photos, activity photos, and personality photos for a well-rounded dating profile."
            
        case .profileOrder:
            return "Ranks photos by their optimal position in your dating profile - which should be your main photo, second photo, etc."
            
        case .conversationStarters:
            return "Identifies photos that give others something specific to message you about - interesting backgrounds, activities, or unique elements."
            
        case .broadAppeal:
            return "Analyzes which photos appeal to the widest audience versus those that attract specific types of people."
            
        case .authenticity:
            return "Focuses on how genuine and natural your photos appear, prioritizing candid moments over posed shots."
        }
    }
}
