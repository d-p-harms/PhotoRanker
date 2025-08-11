// PREMIUM CATEGORY-SPECIFIC ANALYSIS SYSTEM
// Delivers maximum value while optimizing AI workload for each category

function buildPremiumPrompt(criteria) {
  // Enhanced base framework for all analyses
  const premiumBase = `You are an elite dating profile consultant with expertise in psychology, marketing, and social dynamics. Provide detailed, professional-grade analysis worth a premium service.

CORE SCORING FRAMEWORK (0-100):
- overallScore: Primary effectiveness metric
- visualQuality: Technical excellence (lighting, composition, sharpness, color balance)
- attractivenessScore: Physical appeal, styling, grooming, and presentation
- datingAppealScore: Dating app performance potential and competitive advantage
- swipeWorthiness: Immediate thumb-stopping power and first impression impact`;

  // Category-specific premium prompts with rich detail
  switch (criteria) {
    case 'best':
      return `${premiumBase}

REQUIRED COMPREHENSIVE JSON RESPONSE:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100), 
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "marketPositioning": "elite|premium|competitive|developing|needs_work",
  "demographicAppeal": {
    "age_20s": (0-100),
    "age_30s": (0-100), 
    "age_40plus": (0-100),
    "breadth": "mass_market|broad|moderate|niche"
  },
  "psychologicalImpact": {
    "confidenceProjection": (0-100),
    "approachabilityFactor": (0-100),
    "trustworthiness": (0-100),
    "emotionalIntelligence": (0-100)
  },
  "strategicValue": {
    "profilePosition": "main|strong_support|moderate_support|filler|skip",
    "competitiveAdvantage": "high|moderate|low|none"
  },
  "technicalExcellence": {
    "lighting": "professional|good|acceptable|poor",
    "composition": "excellent|good|acceptable|needs_improvement", 
    "imageQuality": "crisp|good|acceptable|blurry"
  },
  "tags": [comprehensive descriptive tags],
  "strengths": [4-5 specific exceptional elements],
  "improvements": [3-4 actionable enhancement suggestions],
  "nextPhotoSuggestions": [3-4 strategic recommendations for additional photos],
  "marketAnalysis": "detailed competitive positioning assessment"
}

COMPREHENSIVE DATING SUCCESS ANALYSIS:
Conduct an elite-level evaluation of this photo's effectiveness across all critical dimensions. Analyze technical excellence, aesthetic appeal, psychological impact, market positioning, and strategic value. 

Examine facial expressions for authenticity, body language for confidence, styling for demographic appeal, and environmental factors for lifestyle projection. Assess competitive advantage in modern dating apps and provide strategic recommendations for profile optimization.

Consider: lighting quality, composition rules, color harmony, facial appeal, style choices, background appropriateness, personality projection, conversation potential, broad vs niche appeal, and strategic positioning within a complete profile.`;

    case 'social':
      return `${premiumBase}

REQUIRED SOCIAL ANALYSIS JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "socialDynamics": {
    "socialScore": (0-100),
    "leadershipIndicators": (0-100),
    "groupPosition": "center|prominent|integrated|peripheral",
    "socialProofLevel": "high|moderate|low|none"
  },
  "interpersonalSignals": {
    "charismaProjection": (0-100),
    "inclusivityFactor": (0-100),
    "socialConfidence": (0-100),
    "networkingAppeal": (0-100)
  },
  "groupAnalysis": {
    "groupSize": "intimate|small|medium|large",
    "groupDynamics": "natural|organized|professional|recreational",
    "diversityFactor": (0-100),
    "energyLevel": "high|moderate|relaxed|low"
  },
  "socialContext": {
    "settingType": "party|dinner|activity|professional|casual",
    "appropriateness": (0-100),
    "exclusivityLevel": "exclusive|selective|open|mass"
  },
  "tags": ["social" and other relevant descriptors],
  "strengths": [4-5 specific social advantages],
  "improvements": [3-4 social optimization suggestions],
  "socialStrategy": "strategic advice for social photo positioning",
  "conversationStarters": [3-4 social elements that invite discussion]
}

ELITE SOCIAL DYNAMICS ANALYSIS:
Conduct a sophisticated examination of social elements, group dynamics, and interpersonal positioning. Analyze your role within social settings, leadership indicators, charisma projection, and social proof factors.

Evaluate group composition, energy dynamics, social hierarchy positioning, and inclusivity signals. Assess how effectively this photo demonstrates social skills, popularity, and relationship-building ability.

Examine body language relative to others, facial expressions in group context, positioning within the frame, interaction quality, and overall social magnetism. Consider demographic appeal of the social setting and strategic value for dating profiles.`;

    case 'activity':
      return `${premiumBase}

REQUIRED ACTIVITY ANALYSIS JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "lifestyleProjection": {
    "activityScore": (0-100),
    "adventureAppeal": (0-100),
    "fitnessIndicators": (0-100),
    "skillDemonstration": (0-100)
  },
  "activityAnalysis": {
    "activityType": "adventure|fitness|creative|professional|recreational",
    "skillLevel": "expert|advanced|intermediate|beginner",
    "passionIntensity": (0-100),
    "accessibilityFactor": (0-100)
  },
  "lifestyleSignals": {
    "healthAppeal": (0-100),
    "activenessLevel": (0-100),
    "hobbyCultivation": (0-100),
    "balanceIndicator": (0-100)
  },
  "demographicAppeal": {
    "sharedInterestPotential": (0-100),
    "inspirationalFactor": (0-100),
    "intimidationRisk": (0-100)
  },
  "tags": ["activity" and other relevant descriptors],
  "strengths": [4-5 specific lifestyle advantages],
  "improvements": [3-4 activity optimization suggestions],
  "activityStrategy": "strategic advice for activity photo positioning",
  "conversationStarters": [3-4 activity elements that invite discussion]
}

COMPREHENSIVE LIFESTYLE & ACTIVITY ANALYSIS:
Perform an expert evaluation of lifestyle demonstration, activity engagement, and skill showcase elements. Analyze the activity type, skill level display, passion intensity, and accessibility for potential matches.

Examine fitness indicators, adventure appeal, creative expression, and hobby cultivation. Assess how effectively this photo demonstrates an active, interesting lifestyle that attracts compatible partners.

Consider activity authenticity vs posing, environmental appropriateness, gear/equipment quality, technique demonstration, and overall lifestyle positioning. Evaluate inspirational factor vs potential intimidation and strategic value for dating appeal.`;

    case 'personality':
      return `${premiumBase}

REQUIRED PERSONALITY ANALYSIS JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "personalityProjection": {
    "personalityScore": (0-100),
    "authenticityLevel": (0-100),
    "charismaFactor": (0-100),
    "approachabilityIndex": (0-100)
  },
  "characterTraits": {
    "confidence": (0-100),
    "warmth": (0-100),
    "intelligence": (0-100),
    "creativity": (0-100),
    "humor": (0-100)
  },
  "emotionalIntelligence": {
    "selfAwareness": (0-100),
    "emotionalExpression": (0-100),
    "empathySignals": (0-100),
    "socialAwareness": (0-100)
  },
  "authenticity": {
    "naturalness": "very_high|high|moderate|low",
    "genuineExpression": (0-100),
    "comfortLevel": (0-100),
    "spontaneityFactor": (0-100)
  },
  "tags": ["personality" and other relevant descriptors],
  "strengths": [4-5 specific personality advantages],
  "improvements": [3-4 personality optimization suggestions],
  "personalityStrategy": "strategic advice for personality photo positioning",
  "characterInsights": "deep psychological assessment of projected traits"
}

ADVANCED PERSONALITY & CHARACTER ANALYSIS:
Conduct a sophisticated psychological evaluation of personality projection, character traits, and authentic self-expression. Analyze emotional intelligence indicators, confidence levels, warmth signals, and approachability factors.

Examine facial micro-expressions, body language authenticity, comfort levels, and genuine emotion display. Assess creativity indicators, humor potential, intelligence signals, and overall character appeal.

Consider naturalness vs staging, spontaneous vs posed expressions, emotional accessibility, and trust-building elements. Evaluate strategic positioning for personality-driven attraction and authentic connection potential.`;

    case 'conversation_starters':
      return `${premiumBase}

REQUIRED CONVERSATION ANALYSIS JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "conversationPotential": {
    "discussionValue": (0-100),
    "questionGenerators": (0-100),
    "relatabilityFactor": (0-100),
    "intrigue": (0-100)
  },
  "visualElements": {
    "backgroundInterest": (0-100),
    "objectFascination": (0-100),
    "activityCuriosity": (0-100),
    "settingUniqueness": (0-100)
  },
  "messageHooks": [5-7 specific conversation starter elements],
  "openingLines": [4-5 natural message suggestions based on photo elements],
  "discussionTopics": [4-6 broader conversation themes this photo enables],
  "personalityReveals": [3-4 character traits revealed that invite questions],
  "tags": ["conversation" and other relevant descriptors],
  "strengths": [4-5 specific conversation advantages],
  "improvements": [3-4 conversation optimization suggestions],
  "conversationStrategy": "strategic advice for maximizing discussion potential"
}

EXPERT CONVERSATION CATALYST ANALYSIS:
Perform a detailed examination of conversation-generating elements, discussion triggers, and message opportunity creation. Identify unique backgrounds, interesting objects, visible activities, and personality reveals that naturally invite questions.

Analyze travel indicators, hobby displays, pets, unusual settings, creative elements, and lifestyle choices that create natural talking points. Assess relatability factors, intrigue elements, and question-generation potential.

Examine environmental storytelling, prop significance, activity context, and personality indicators that provide rich material for opening messages and sustained conversation development.`;

    case 'profile_order':
      return `${premiumBase}

REQUIRED POSITIONING ANALYSIS JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "strategicPositioning": {
    "position": "1|2|3|4|5|6|skip",
    "positionConfidence": (0-100),
    "mainPhotoSuitability": (0-100),
    "supportPhotoValue": (0-100)
  },
  "profileStrategy": {
    "narrativeContribution": "primary|strong|moderate|weak",
    "diversityValue": (0-100),
    "complementaryFactor": (0-100),
    "redundancyRisk": (0-100)
  },
  "technicalSuitability": {
    "faceClarity": (0-100),
    "backgroundSimplicity": (0-100),
    "immediateImpact": (0-100),
    "thumbnailEffectiveness": (0-100)
  },
  "competitiveAnalysis": {
    "marketAdvantage": "significant|moderate|neutral|disadvantage",
    "differentiationFactor": (0-100),
    "memorabilityIndex": (0-100)
  },
  "tags": ["positioning" and other relevant descriptors],
  "strengths": [4-5 specific positioning advantages],
  "improvements": [3-4 positioning optimization suggestions],
  "positionReason": "detailed strategic rationale for recommended position",
  "profileComposition": "advice for building complete profile around this photo"
}

STRATEGIC PROFILE POSITIONING ANALYSIS:
Conduct an expert evaluation of optimal placement within dating profile sequence. Analyze main photo suitability versus supporting photo value, considering face clarity, immediate impact, background complexity, and thumbnail effectiveness.

Examine narrative contribution to overall profile story, diversity value, and complementary potential with other photo types. Assess competitive advantage, differentiation factors, and memorability within target demographic.

Consider swipe-stopping power for position 1, storytelling value for positions 2-6, and strategic sequencing for maximum profile effectiveness. Evaluate technical factors and psychological impact across different positions.`;

    case 'broad_appeal':
      return `${premiumBase}

REQUIRED APPEAL ANALYSIS JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "demographicAppeal": {
    "age_18_25": (0-100),
    "age_26_35": (0-100),
    "age_36_45": (0-100),
    "age_46plus": (0-100),
    "overallBreadth": "mass_market|broad|moderate|niche"
  },
  "culturalAppeal": {
    "culturalAccessibility": (0-100),
    "socioeconomicBreadth": (0-100),
    "educationalLevels": (0-100),
    "lifestyleCompatibility": (0-100)
  },
  "psychographicAppeal": {
    "personalityTypes": [compatible personality types],
    "valueAlignment": (0-100),
    "lifestageCompatibility": (0-100),
    "interestOverlap": (0-100)
  },
  "marketPositioning": {
    "competitiveAdvantage": "premium|competitive|standard|developing",
    "uniquenessIndex": (0-100),
    "massAppealVsNiche": "mass_95|broad_80|moderate_60|niche_40|ultra_niche_20"
  },
  "tags": ["broad_appeal" and other relevant descriptors],
  "strengths": [4-5 specific appeal advantages],
  "improvements": [3-4 appeal optimization suggestions],
  "targetDemographics": [5-7 specific demographic groups this appeals to],
  "appealStrategy": "strategic advice for maximizing demographic reach"
}

COMPREHENSIVE DEMOGRAPHIC APPEAL ANALYSIS:
Perform an extensive evaluation of cross-demographic attraction potential and market positioning. Analyze appeal across age groups, cultural backgrounds, socioeconomic levels, and lifestyle preferences.

Examine styling choices, activity selections, environmental factors, and personality projection for broad accessibility versus niche targeting. Assess cultural inclusivity, professional appropriateness, and lifestyle relatability.

Consider mass market appeal versus specialized attraction, competitive positioning within target demographics, and strategic value for maximum reach versus authentic self-expression.`;

    case 'authenticity':
      return `${premiumBase}

REQUIRED AUTHENTICITY ANALYSIS JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "authenticityMetrics": {
    "authenticityLevel": "very_high|high|moderate|low|heavily_staged",
    "naturalness": (0-100),
    "spontaneityFactor": (0-100),
    "comfortIndex": (0-100)
  },
  "genuinenessIndicators": {
    "expressionAuthenticity": (0-100),
    "bodyLanguageNaturalness": (0-100),
    "emotionalGenuineness": (0-100),
    "unconsciousElements": (0-100)
  },
  "trustFactors": {
    "trustworthiness": (0-100),
    "relatability": (0-100),
    "approachability": (0-100),
    "emotionalSafety": (0-100)
  },
  "stagingAnalysis": {
    "posedElements": (0-100),
    "artificialFactors": (0-100),
    "overproductionRisk": (0-100),
    "manipulationConcerns": (0-100)
  },
  "tags": ["authentic" and other relevant descriptors],
  "strengths": [4-5 specific authenticity advantages],
  "improvements": [3-4 authenticity optimization suggestions],
  "genuinenessFactors": "detailed analysis of authentic elements",
  "authenticityStrategy": "strategic advice for maintaining authenticity while optimizing appeal"
}

ADVANCED AUTHENTICITY & NATURALNESS EVALUATION:
Conduct a sophisticated analysis of genuine versus staged elements, natural expression versus posed presentation, and authentic personality revelation versus manufactured appeal.

Examine micro-expressions, body language naturalness, comfort levels, and spontaneous elements. Analyze environmental authenticity, activity genuineness, and emotional accessibility.

Assess trust-building factors, relatability indicators, and emotional safety projection. Consider balance between authentic self-expression and strategic optimization for dating success.`;

    case 'balanced':
      return `${premiumBase}

REQUIRED COMPREHENSIVE CATEGORIZATION JSON:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "categorization": {
    "socialScore": (0-100),
    "activityScore": (0-100),
    "personalityScore": (0-100),
    "professionalScore": (0-100),
    "primaryCategory": "social|activity|personality|professional|general",
    "secondaryCategory": "social|activity|personality|professional|general",
    "categoryConfidence": (0-100),
    "categoryReasoning": "detailed explanation of categorization"
  },
  "balanceContribution": {
    "portfolioDiversity": "high|moderate|low",
    "narrativeValue": (0-100),
    "complementaryFactor": (0-100),
    "uniquenessContribution": (0-100)
  },
  "strategicValue": {
    "selectionPriority": "high|moderate|low",
    "profilePositioning": "primary|secondary|supporting|optional",
    "redundancyCheck": "unique|somewhat_unique|common|redundant"
  },
  "optimization": {
    "enhancementPotential": (0-100),
    "cropSuggestions": [specific cropping recommendations],
    "filterAdvice": "specific editing recommendations",
    "retakeValue": (0-100)
  },
  "tags": [comprehensive categorization tags],
  "strengths": [4-5 specific categorization advantages],
  "improvements": [3-4 categorization optimization suggestions],
  "selectionStrategy": "detailed advice for balanced portfolio construction"
}

EXPERT CATEGORIZATION & PORTFOLIO ANALYSIS:
Perform precise categorization analysis across all major photo types for optimal portfolio construction. Provide exact scoring for social, activity, personality, and professional elements with detailed reasoning.

Analyze portfolio contribution, narrative value, and strategic positioning within a complete dating profile. Assess uniqueness factors, complementary potential, and selection priority for balanced representation.

Examine technical optimization potential, cropping opportunities, and enhancement possibilities. Consider redundancy risks and strategic value for comprehensive profile development.`;

    default:
      // Fallback to 'best' for unknown criteria
      return buildPremiumPrompt('best');
  }
}

// PREMIUM ANALYSIS CONFIGURATION
function getPremiumAnalysisConfig(criteria) {
  const configs = {
    'best': {
      complexity: 'comprehensive',
      expectedTokens: 2200,
      timeout: 45000,
      analysisDepth: 'maximum',
      priority: 'thoroughness'
    },
    'social': {
      complexity: 'specialized_deep',
      expectedTokens: 1800,
      timeout: 35000,
      analysisDepth: 'expert',
      priority: 'social_accuracy'
    },
    'activity': {
      complexity: 'specialized_deep',
      expectedTokens: 1800,
      timeout: 35000,
      analysisDepth: 'expert',
      priority: 'lifestyle_accuracy'
    },
    'personality': {
      complexity: 'specialized_deep',
      expectedTokens: 1900,
      timeout: 38000,
      analysisDepth: 'expert',
      priority: 'psychological_accuracy'
    },
    'conversation_starters': {
      complexity: 'specialized_medium',
      expectedTokens: 1600,
      timeout: 30000,
      analysisDepth: 'focused_expert',
      priority: 'conversation_value'
    },
    'profile_order': {
      complexity: 'strategic',
      expectedTokens: 1700,
      timeout: 32000,
      analysisDepth: 'strategic_expert',
      priority: 'positioning_accuracy'
    },
    'broad_appeal': {
      complexity: 'comprehensive',
      expectedTokens: 2000,
      timeout: 40000,
      analysisDepth: 'market_expert',
      priority: 'demographic_accuracy'
    },
    'authenticity': {
      complexity: 'specialized_deep',
      expectedTokens: 1800,
      timeout: 35000,
      analysisDepth: 'psychological_expert',
      priority: 'authenticity_accuracy'
    },
    'balanced': {
      complexity: 'comprehensive',
      expectedTokens: 2100,
      timeout: 42000,
      analysisDepth: 'portfolio_expert',
      priority: 'categorization_accuracy'
    }
  };

  return configs[criteria] || configs['best'];
}

// PREMIUM RESPONSE PARSING WITH RICH DATA EXTRACTION
function parsePremiumResponse(responseText, criteria, fileName, photoUrl) {
  try {
    // Advanced JSON extraction with multiple patterns
    const patterns = [
      /\{[\s\S]*\}/,  // Standard JSON block
      /```json\s*(\{[\s\S]*?\})\s*```/,  // Markdown JSON block
      /```(\{[\s\S]*?\})```/  // Generic code block
    ];

    for (const pattern of patterns) {
      const match = responseText.match(pattern);
      if (match) {
        const jsonStr = match[1] || match[0];
        try {
          const parsed = JSON.parse(jsonStr);
          return buildPremiumResult(parsed, criteria, fileName, photoUrl, responseText);
        } catch (e) {
          continue;
        }
      }
    }
  } catch (error) {
    console.log('Advanced JSON parsing failed, using intelligent extraction');
  }

  // Intelligent fallback extraction
  return extractPremiumData(responseText, criteria, fileName, photoUrl);
}

function buildPremiumResult(data, criteria, fileName, photoUrl, fullText) {
  // Build comprehensive result with all premium features
  const result = {
    fileName,
    storageURL: photoUrl,
    score: data.overallScore || 75,
    visualQuality: data.visualQuality || 70,
    attractivenessScore: data.attractivenessScore || 70,
    datingAppealScore: data.datingAppealScore || 70,
    swipeWorthiness: data.swipeWorthiness || 70,
    tags: data.tags || ['premium_analyzed'],
    strengths: data.strengths || [],
    improvements: data.improvements || [],
    technicalFeedback: extractTechnicalFeedback(data, fullText),
    strategicAdvice: extractStrategicAdvice(data, fullText, criteria)
  };

  // Add comprehensive category-specific data
  switch (criteria) {
    case 'best':
      Object.assign(result, {
        marketPositioning: data.marketPositioning,
        demographicAppeal: data.demographicAppeal,
        psychologicalImpact: data.psychologicalImpact,
        strategicValue: data.strategicValue,
        technicalExcellence: data.technicalExcellence,
        marketAnalysis: data.marketAnalysis
      });
      break;
      
    case 'social':
      Object.assign(result, {
        socialDynamics: data.socialDynamics,
        interpersonalSignals: data.interpersonalSignals,
        groupAnalysis: data.groupAnalysis,
        socialContext: data.socialContext,
        socialStrategy: data.socialStrategy,
        conversationStarters: data.conversationStarters
      });
      break;
      
    case 'activity':
      Object.assign(result, {
        lifestyleProjection: data.lifestyleProjection,
        activityAnalysis: data.activityAnalysis,
        lifestyleSignals: data.lifestyleSignals,
        demographicAppeal: data.demographicAppeal,
        activityStrategy: data.activityStrategy,
        conversationStarters: data.conversationStarters
      });
      break;
      
    case 'personality':
      Object.assign(result, {
        personalityProjection: data.personalityProjection,
        characterTraits: data.characterTraits,
        emotionalIntelligence: data.emotionalIntelligence,
        authenticity: data.authenticity,
        personalityStrategy: data.personalityStrategy,
        characterInsights: data.characterInsights
      });
      break;
      
    case 'conversation_starters':
      Object.assign(result, {
        conversationPotential: data.conversationPotential,
        visualElements: data.visualElements,
        messageHooks: data.messageHooks,
        openingLines: data.openingLines,
        discussionTopics: data.discussionTopics,
        personalityReveals: data.personalityReveals,
        conversationStrategy: data.conversationStrategy
      });
      break;
      
    case 'profile_order':
      Object.assign(result, {
        strategicPositioning: data.strategicPositioning,
        profileStrategy: data.profileStrategy,
        technicalSuitability: data.technicalSuitability,
        competitiveAnalysis: data.competitiveAnalysis,
        positionReason: data.positionReason,
        profileComposition: data.profileComposition
      });
      break;
      
    case 'broad_appeal':
      Object.assign(result, {
        demographicAppeal: data.demographicAppeal,
        culturalAppeal: data.culturalAppeal,
        psychographicAppeal: data.psychographicAppeal,
        marketPositioning: data.marketPositioning,
        targetDemographics: data.targetDemographics,
        appealStrategy: data.appealStrategy
      });
      break;
      
    case 'authenticity':
      Object.assign(result, {
        authenticityMetrics: data.authenticityMetrics,
        genuinenessIndicators: data.genuinenessIndicators,
        trustFactors: data.trustFactors,
        stagingAnalysis: data.stagingAnalysis,
        genuinenessFactors: data.genuinenessFactors,
        authenticityStrategy: data.authenticityStrategy
      });
      break;
      
    case 'balanced':
      Object.assign(result, {
        categorization: data.categorization,
        balanceContribution: data.balanceContribution,
        strategicValue: data.strategicValue,
        optimization: data.optimization,
        selectionStrategy: data.selectionStrategy
      });
      break;
  }

  return result;
}

// UTILITY FUNCTIONS FOR PREMIUM DATA EXTRACTION
function extractTechnicalFeedback(data, fullText) {
  return {
    lighting: data.technicalExcellence?.lighting || extractPattern(fullText, /lighting[:\s]*([\w\s]+)/i) || 'good',
    composition: data.technicalExcellence?.composition || extractPattern(fullText, /composition[:\s]*([\w\s]+)/i) || 'acceptable',
    imageQuality: data.technicalExcellence?.imageQuality || extractPattern(fullText, /image quality[:\s]*([\w\s]+)/i) || 'good',
    enhancement: data.optimization || 'Technical analysis available in detailed report'
  };
}

function extractStrategicAdvice(data, fullText, criteria) {
  const strategies = {
    best: data.marketAnalysis,
    social: data.socialStrategy,
    activity: data.activityStrategy,
    personality: data.personalityStrategy,
    conversation_starters: data.conversationStrategy,
    profile_order: data.positionReason,
    broad_appeal: data.appealStrategy,
    authenticity: data.authenticityStrategy,
    balanced: data.selectionStrategy
  };
  
  return strategies[criteria] || extractPattern(fullText, /strategy[:\s]*([\w\s,.!?]+)/i) || 'Strategic recommendations available';
}

function extractPattern(text, pattern) {
  const match = text.match(pattern);
  return match ? match[1].trim().substring(0, 100) : null;
}
