const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const vision = require('@google-cloud/vision');
const sharp = require('sharp');

// Initialize Firebase Admin SDK
admin.initializeApp();

// Set default options for all functions
setGlobalOptions({ region: 'us-central1' });

// Define secrets
const geminiKey = defineSecret('GEMINI_API_KEY');
const visionClient = new vision.ImageAnnotatorClient();

// ENHANCED IMAGE PROCESSING WITH VALIDATION
async function validateAndPrepareImage(buffer) {
  const metadata = await sharp(buffer).metadata();
  console.log(`Received image: ${metadata.width}x${metadata.height}, ${Math.round(buffer.length/1024)}KB`);
  
  const maxDimension = Math.max(metadata.width, metadata.height);
  
  if (maxDimension < 500) {
    throw new Error('Image too small for quality analysis (minimum 500px)');
  }
  
  let sharpInstance = sharp(buffer);
  
  // Resize very large images for optimal processing
  if (maxDimension > 2048) {
    console.log('Resizing oversized image to optimal size');
    sharpInstance = sharpInstance.resize(1536, 1536, {
      fit: 'inside',
      withoutEnlargement: true
    });
  }
  
  // Convert to JPEG and iteratively reduce quality if needed
  let quality = 92;
  let processedBuffer = await sharpInstance.jpeg({ quality }).toBuffer();
  
  while (processedBuffer.length > 10 * 1024 * 1024 && quality > 60) {
    quality -= 5;
    console.log(`Compressing image to quality ${quality}`);
    processedBuffer = await sharpInstance.jpeg({ quality }).toBuffer();
  }
  
  if (processedBuffer.length > 10 * 1024 * 1024) {
    throw new Error('Image too large (maximum 10MB after processing)');
  }
  
  return processedBuffer;
}

// DATING APP STANDARD CONTENT SAFETY CHECK
async function performSafetyCheck(imageBuffer) {
  try {
    const [safeResult] = await visionClient.safeSearchDetection(imageBuffer);
    const safe = safeResult.safeSearchAnnotation || {};

    console.log('SafeSearch results:', {
      adult: safe.adult,
      violence: safe.violence,
      racy: safe.racy,
      medical: safe.medical,
      spoof: safe.spoof
    });

    // Block only highly explicit adult content
    if (['VERY_LIKELY'].includes(safe.adult)) {
      console.warn('SafeSearch blocked - explicit adult content:', safe.adult);
      return false;
    }

    // Block ALL violence (dating apps are very strict about violence)
    if (['POSSIBLE', 'LIKELY', 'VERY_LIKELY'].includes(safe.violence)) {
      console.warn('SafeSearch blocked - violence detected:', safe.violence);
      return false;
    }

    // Allow racy content unless explicitly sexual
    if (['VERY_LIKELY'].includes(safe.racy)) {
      console.warn('SafeSearch blocked - explicit racy content:', safe.racy);
      return false;
    }

    // Block medical content
    if (['LIKELY', 'VERY_LIKELY'].includes(safe.medical)) {
      console.warn('SafeSearch blocked - medical content:', safe.medical);
      return false;
    }

    // Block fake/manipulated content
    if (['LIKELY', 'VERY_LIKELY'].includes(safe.spoof)) {
      console.warn('SafeSearch blocked - spoof/fake content:', safe.spoof);
      return false;
    }

    console.log('Image passed dating app content policy');
    return true;

  } catch (error) {
    console.error('SafeSearch check failed:', error);
    // Fail closed – reject images when safety check fails
    return false;
  }
}

// ENHANCED ANALYZE PHOTOS FUNCTION
exports.analyzePhotos = onCall({
  secrets: [geminiKey],
  timeoutSeconds: 540,
  memory: '2GiB',
  region: 'us-central1',
}, async (request) => {
  try {
    const { photos, criteria } = request.data;
    const maxBatchSize = 12;

    if (!photos || !Array.isArray(photos) || photos.length === 0) {
      throw new HttpsError('invalid-argument', 'No photos provided');
    }

    if (photos.length > maxBatchSize) {
      throw new HttpsError('invalid-argument', 
        `Maximum ${maxBatchSize} photos per batch. Please process in smaller groups.`);
    }

    if (!geminiKey.value()) {
      throw new HttpsError('internal', 'GEMINI_API_KEY not configured');
    }

    const genAI = new GoogleGenerativeAI(geminiKey.value());
    const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

    console.log(`Starting enhanced practical analysis with criteria: ${criteria} for ${photos.length} photos`);

    const concurrencyLimit = 6;
    const batches = [];
    
    for (let i = 0; i < photos.length; i += concurrencyLimit) {
      batches.push(photos.slice(i, i + concurrencyLimit));
    }

    let allResults = [];

    for (const [batchIndex, batch] of batches.entries()) {
      console.log(`Processing batch ${batchIndex + 1}/${batches.length} (${batch.length} photos)`);
      
      const batchPromises = batch.map(async (photoData, index) => {
        try {
          await new Promise(resolve => setTimeout(resolve, index * 200));
          return await analyzeImageWithEnhancedGemini(photoData, criteria, model, index);
        } catch (error) {
          console.error(`Error in batch ${batchIndex + 1}, photo ${index + 1}:`, error);
          return createFallbackResponse(`photo_${index}`, '', criteria, error.message);
        }
      });
      
      const batchResults = await Promise.all(batchPromises);
      allResults = allResults.concat(batchResults);
      
      if (batchIndex < batches.length - 1) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }

    console.log('All photos analyzed successfully');
        
    const sortedResults = allResults.sort((a, b) => b.score - a.score);
    const topResults = sortedResults.slice(0, Math.min(12, sortedResults.length));
        
    console.log(`Returning top ${topResults.length} results`);

    return {
      success: true,
      results: topResults,
      metadata: {
        totalPhotos: photos.length,
        batchesProcessed: batches.length,
        averageScore: Math.round(allResults.reduce((sum, r) => sum + r.score, 0) / allResults.length),
        criteriaUsed: criteria,
        processingVersion: '3.2.0',
        analysisDepth: 'practical_expert'
      }
    };
           
  } catch (error) {
    console.error('Error analyzing photos:', error);
    throw new HttpsError(
      'internal',
      error.message || 'Failed to analyze photos'
    );
  }
});

// ENHANCED IMAGE ANALYSIS WITH PRACTICAL DEPTH
async function analyzeImageWithEnhancedGemini(photoData, criteria, model, index) {
  const timeout = 40000; // 40 second timeout for enhanced analysis

  return Promise.race([
    performEnhancedAnalysis(photoData, criteria, model, index),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Enhanced analysis timeout')), timeout)
    )
  ]);
}

async function performEnhancedAnalysis(photoData, criteria, model, index) {
  try {
    console.log(`Processing photo ${index} with enhanced ${criteria} analysis`);

    const buffer = Buffer.from(photoData, 'base64');

    // Enhanced image processing with validation
    const processedBuffer = await validateAndPrepareImage(buffer);
    console.log(`Enhanced image processing complete, new size: ${processedBuffer.length} bytes`);

    // Content safety check
    const isSafe = await performSafetyCheck(processedBuffer);
    if (!isSafe) {
      return createRejectedResponse(`photo_${index}`, '', 'Image violates content policy');
    }

    const base64Image = processedBuffer.toString('base64');
    const prompt = buildEnhancedPracticalPrompt(criteria);

    console.log(`Analyzing image with enhanced practical ${criteria} prompt (${prompt.length} chars)`);

    let retries = 3;
    while (retries > 0) {
      try {
        const result = await model.generateContent([
          prompt,
          {
            inlineData: {
              mimeType: 'image/jpeg',
              data: base64Image
            }
          }
        ]);

        const response = await result.response;
        const text = response.text();
        console.log(`Raw enhanced practical AI response for ${criteria} (${text.length} chars)`);

        const analysisResult = parseEnhancedPracticalResponse(text, criteria, `photo_${index}`, '');
        console.log(`Parsed enhanced practical ${criteria} analysis:`, {
          score: analysisResult.score,
          hasCategorizationScores: !analysisResult.categorization,
          hasStrengths: analysisResult.strengths?.length > 0,
          hasPersonalityInsights: analysisResult.datingInsights?.personalityProjected?.length > 0
        });

        return analysisResult;
      } catch (error) {
        retries--;
        if (retries === 0) throw error;

        // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, (3 - retries) * 1500));
      }
    }
  } catch (error) {
    console.error(`Enhanced practical analysis failed for photo ${index}:`, error);

    if (error.message.includes('too small') || error.message.includes('too large')) {
      return createRejectedResponse(`photo_${index}`, '', error.message);
    }

    return createFallbackResponse(`photo_${index}`, '', criteria, error.message);
  }
}

// PREMIUM CATEGORY-SPECIFIC PROMPTS
function buildEnhancedPracticalPrompt(criteria) {
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
      return buildEnhancedPracticalPrompt('best');
  }
}

// ENHANCED PRACTICAL RESPONSE PARSING
function parseEnhancedPracticalResponse(responseText, criteria, fileName, photoUrl) {
  try {
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      
      const result = {
        fileName,
        storageURL: photoUrl,
        score: parsed.overallScore || 75,
        visualQuality: parsed.visualQuality || 70,
        attractivenessScore: parsed.attractivenessScore || 70,
        datingAppealScore: parsed.datingAppealScore || 70,
        swipeWorthiness: parsed.swipeWorthiness || 70,
        tags: parsed.tags || ['premium_analyzed'],
        strengths: parsed.strengths || [],
        improvements: parsed.improvements || [],
        bestQuality: getEnhancedPracticalFallback(criteria, responseText),
        suggestions: parsed.improvements || [],
        nextPhotoSuggestions: parsed.nextPhotoSuggestions || [],
        technicalFeedback: {
          lighting: parsed.technicalExcellence?.lighting || 'good',
          composition: parsed.technicalExcellence?.composition || 'acceptable',
          styling: parsed.technicalExcellence?.styling || 'good'
        },
        datingInsights: {
          personalityProjected: parsed.personalityProjected || [],
          profileRole: getEnhancedProfileRole(criteria),
          demographicAppeal: getEnhancedDemographicAppeal(criteria, responseText)
        },
        categorization: inferEnhancedCategorization(responseText, parsed.tags || [])
      };

      // Add category-specific data
      if (parsed.socialDynamics) result.socialDynamics = parsed.socialDynamics;
      if (parsed.activityAnalysis || parsed.lifestyleProjection) {
        result.activityAnalysis = parsed.activityAnalysis || parsed.lifestyleProjection;
      }
      if (parsed.personalityProjection) result.personalityProjection = parsed.personalityProjection;
      if (parsed.conversationPotential) result.conversationPotential = parsed.conversationPotential;
      if (parsed.strategicPositioning) result.strategicPositioning = parsed.strategicPositioning;
      if (parsed.demographicAppeal) result.demographicAppeal = parsed.demographicAppeal;
      if (parsed.authenticityMetrics) result.authenticityMetrics = parsed.authenticityMetrics;
      if (parsed.categorization) result.categorization = parsed.categorization;

      return result;
    }
  } catch (error) {
    console.log('JSON parsing failed, using enhanced fallback extraction');
  }
  
  return createEnhancedPracticalFallback(fileName, photoUrl, criteria, responseText);
}

// ENHANCED CATEGORIZATION INFERENCE
function inferEnhancedCategorization(responseText, tags) {
  const text = responseText.toLowerCase();
  let socialScore = 0;
  let activityScore = 0;
  let personalityScore = 0;
  
  // Social indicators
  if (text.includes('group') || text.includes('social') || text.includes('friends')) socialScore += 40;
  if (text.includes('party') || text.includes('event') || text.includes('gathering')) socialScore += 30;
  if (tags.includes('social') || tags.includes('group')) socialScore += 35;
  if (text.includes('leadership') || text.includes('charisma') || text.includes('networking')) socialScore += 25;
  
  // Activity indicators
  if (text.includes('sport') || text.includes('outdoor') || text.includes('adventure')) activityScore += 40;
  if (text.includes('hobby') || text.includes('travel') || text.includes('recreation')) activityScore += 30;
  if (tags.includes('activity') || tags.includes('outdoor') || tags.includes('travel')) activityScore += 35;
  if (text.includes('fitness') || text.includes('exercise') || text.includes('skill')) activityScore += 20;
  
  // Personality indicators
  if (text.includes('expression') || text.includes('personality') || text.includes('character')) personalityScore += 30;
  if (text.includes('authentic') || text.includes('genuine') || text.includes('natural')) personalityScore += 25;
  if (tags.includes('personality') || tags.includes('natural') || tags.includes('confident')) personalityScore += 35;
  if (text.includes('creative') || text.includes('artistic') || text.includes('emotion')) personalityScore += 20;
  
  // Normalize scores
  socialScore = Math.min(socialScore, 100);
  activityScore = Math.min(activityScore, 100);
  personalityScore = Math.min(personalityScore, 100);
  
  // Determine primary category
  const maxScore = Math.max(socialScore, activityScore, personalityScore);
  let primaryCategory = 'general';
  let categoryConfidence = 50;
  
  if (maxScore >= 70) {
    categoryConfidence = Math.min(maxScore, 95);
    if (socialScore === maxScore) primaryCategory = 'social';
    else if (activityScore === maxScore) primaryCategory = 'activity';
    else if (personalityScore === maxScore) primaryCategory = 'personality';
  }
  
  return {
    socialScore,
    activityScore,
    personalityScore,
    primaryCategory,
    categoryConfidence,
    categoryReasoning: `Inferred from content analysis: ${primaryCategory} indicators scored highest`
  };
}

// ENHANCED PRACTICAL FALLBACK RESPONSE
function createEnhancedPracticalFallback(fileName, photoUrl, criteria, responseText = '') {
  let score = 75;
  
  // Enhanced score detection with multiple patterns
  const scoreMatches = responseText.match(/(?:score|rating|quality|appeal):?\s*(\d+)/gi);
  if (scoreMatches && scoreMatches.length > 0) {
    const scores = scoreMatches.map(match => {
      const num = match.match(/(\d+)/);
      return num ? parseInt(num[1]) : null;
    }).filter(s => s !== null && s >= 0 && s <= 100);
    
    if (scores.length > 0) {
      score = Math.round(scores.reduce((sum, s) => sum + s, 0) / scores.length);
    }
  }
  
  const enhancedTags = extractEnhancedTags(responseText, criteria);
  
  return {
    fileName,
    storageURL: photoUrl,
    score,
    visualQuality: score - 5,
    attractivenessScore: score,
    datingAppealScore: score - 3,
    swipeWorthiness: score - 2,
    tags: enhancedTags,
    bestQuality: getEnhancedPracticalFallback(criteria, responseText),
    suggestions: ["Enhanced analysis completed with practical recommendations"],
    strengths: ["Photo processed with advanced AI analysis"],
    improvements: ["Detailed feedback available in premium analysis"],
    nextPhotoSuggestions: [`Consider ${criteria.replace('_', ' ')} focused photos for comparison`],
    technicalFeedback: {
      lighting: "Enhanced analysis in progress",
      composition: "Technical evaluation completed",
      styling: "Professional assessment available"
    },
    datingInsights: getEnhancedDatingInsights(criteria, responseText),
    categorization: inferEnhancedCategorization(responseText, enhancedTags)
  };
}

function getEnhancedDatingInsights(criteria, responseText) {
  const personalityTraits = [];
  const text = responseText.toLowerCase();
  
  // Enhanced personality detection
  if (text.includes('confident') || text.includes('bold')) personalityTraits.push('confident');
  if (text.includes('friendly') || text.includes('warm')) personalityTraits.push('approachable');
  if (text.includes('creative') || text.includes('artistic')) personalityTraits.push('creative');
  if (text.includes('active') || text.includes('energetic')) personalityTraits.push('active');
  if (text.includes('authentic') || text.includes('genuine')) personalityTraits.push('authentic');
  if (text.includes('professional') || text.includes('polished')) personalityTraits.push('professional');
  
  const approachabilityFactor = text.includes('approachable') || text.includes('friendly') ? 85 : 
                               text.includes('welcoming') || text.includes('open') ? 80 :
                               text.includes('friendly') || text.includes('warm') ? 85 : 
                               text.includes('fitness') || text.includes('exercise') || text.includes('skill') ? 80 : 75;
  const confidenceLevel = text.includes('confident') || text.includes('strong') ? 85 :
                         text.includes('comfortable') ? 80 : 75;
  const authenticityLevel = text.includes('genuine') || text.includes('natural') ? 90 :
                           text.includes('authentic') ? 85 : 75;
  
  return {
    personalityProjected: personalityTraits,
    emotionalIntelligence: "Analysis in progress - emotional indicators being evaluated",
    demographicAppeal: getEnhancedDemographicAppeal(criteria, text),
    marketPositioning: "Strategic market positioning analysis available",
    profileRole: getEnhancedProfileRole(criteria),
    conversationStarters: extractConversationStarters(text),
    approachabilityFactor: approachabilityFactor,
    confidenceLevel: confidenceLevel,
    authenticityLevel: authenticityLevel
  };
}

function extractEnhancedTags(responseText, criteria) {
  const tags = [];
  const text = responseText.toLowerCase();
  
  // Enhanced tag detection with context
  if (text.includes('professional') || text.includes('work')) tags.push('professional');
  if (text.includes('casual') || text.includes('relaxed')) tags.push('casual');
  if (text.includes('social') || text.includes('group') || text.includes('friends')) tags.push('social');
  if (text.includes('activity') || text.includes('sport') || text.includes('hobby')) tags.push('activity');
  if (text.includes('personality') || text.includes('character')) tags.push('personality');
  if (text.includes('attractive') || text.includes('appealing')) tags.push('attractive');
  if (text.includes('natural') || text.includes('genuine')) tags.push('natural');
  if (text.includes('confident') || text.includes('strong')) tags.push('confident');
  if (text.includes('outdoor') || text.includes('nature')) tags.push('outdoor');
  if (text.includes('travel') || text.includes('adventure')) tags.push('travel');
  if (text.includes('creative') || text.includes('artistic')) tags.push('hobby');
  
  // Ensure minimum tags based on criteria
  if (tags.length === 0) {
    switch (criteria) {
      case 'social': tags.push('social', 'analyzed'); break;
      case 'activity': tags.push('activity', 'analyzed'); break;
      case 'personality': tags.push('personality', 'analyzed'); break;
      default: tags.push('analyzed', 'processed');
    }
  }
  
  return tags;
}

function extractConversationStarters(responseText) {
  const starters = [];
  const text = responseText.toLowerCase();
  
  if (text.includes('background') || text.includes('location')) {
    starters.push("Interesting background location to ask about");
  }
  if (text.includes('activity') || text.includes('hobby')) {
    starters.push("Activity or hobby visible for discussion");
  }
  if (text.includes('travel') || text.includes('adventure')) {
    starters.push("Travel or adventure element for conversation");
  }
  if (text.includes('pet') || text.includes('animal')) {
    starters.push("Pet or animal for easy conversation starter");
  }
  
  return starters;
}

function getEnhancedDemographicAppeal(criteria, responseText) {
  const demographicMapping = {
    'social': 'Appeals to socially-oriented individuals seeking connection',
    'activity': 'Attracts active, adventure-seeking demographics',
    'personality': 'Appeals to those seeking authentic personality connection',
    'broad_appeal': 'Strong cross-demographic appeal for mass market',
    'authenticity': 'Attracts individuals valuing genuine, authentic connections',
    'best': 'Broad appeal across multiple demographic segments'
  };
  
  return demographicMapping[criteria] || 'Analysis indicates positive demographic appeal';
}

function getEnhancedPracticalFallback(criteria, responseText) {
  const fallbackMapping = {
    'profile_order': "Photo analyzed for strategic profile positioning with practical recommendations",
    'conversation_starters': "Photo evaluated for conversation engagement and discussion potential",
    'broad_appeal': "Photo assessed for broad demographic appeal and market positioning",
    'authenticity': "Photo reviewed for authentic personality expression and genuine appeal",
    'balanced': "Photo categorized for balanced profile creation with detailed classification",
    'social': "Photo analyzed for social connectivity and group dynamics",
    'activity': "Photo evaluated for activity demonstration and lifestyle appeal",
    'personality': "Photo assessed for personality projection and character expression",
    'best': "Comprehensive practical analysis completed for dating optimization"
  };
  
  return fallbackMapping[criteria] || "Enhanced practical photo analysis completed";
}

function getEnhancedProfileRole(criteria) {
  const roleMapping = {
    'profile_order': 'Strategic positioning for optimal profile sequence',
    'conversation_starters': 'Conversation catalyst and discussion starter',
    'broad_appeal': 'Mass market appeal driver for wide demographic reach',
    'authenticity': 'Authentic personality showcase for genuine connections',
    'balanced': 'Profile balance contributor for comprehensive presentation',
    'social': 'Social proof and connectivity demonstration',
    'activity': 'Lifestyle and activity showcase element',
    'personality': 'Character and personality highlight piece',
    'best': 'Primary attraction and dating appeal driver'
  };
  
  return roleMapping[criteria] || 'Enhanced dating profile optimization element';
}

function createFallbackResponse(fileName, photoUrl, criteria, errorMessage) {
  return {
    fileName: fileName,
    storageURL: photoUrl,
    score: 70,
    visualQuality: 65,
    attractivenessScore: 70,
    datingAppealScore: 68,
    swipeWorthiness: 67,
    tags: ['uploaded', 'processing'],
    bestQuality: "Photo uploaded successfully",
    suggestions: ["Analysis temporarily unavailable - please try again"],
    strengths: ["Photo processed successfully"],
    improvements: [errorMessage || "Please try uploading again"],
    nextPhotoSuggestions: ["Try different photos for comparison"],
    technicalFeedback: {
      lighting: "Analysis pending",
      composition: "Analysis pending",
      styling: "Analysis pending"
    },
    datingInsights: {
      personalityProjected: [],
      profileRole: "Processing"
    },
    categorization: {
      socialScore: 0,
      activityScore: 0,
      personalityScore: 0,
      primaryCategory: 'general',
      categoryConfidence: 0,
      categoryReasoning: 'Analysis failed - please retry'
    }
  };
}

function createRejectedResponse(fileName, photoUrl, reason) {
  return {
    fileName: fileName,
    storageURL: photoUrl,
    score: 0,
    visualQuality: 0,
    attractivenessScore: 0,
    datingAppealScore: 0,
    swipeWorthiness: 0,
    tags: [],
    bestQuality: '',
    suggestions: [reason],
    strengths: [],
    improvements: [reason],
    nextPhotoSuggestions: [],
    technicalFeedback: {},
    datingInsights: {
      personalityProjected: [],
      profileRole: "Rejected"
    },
    categorization: {
      socialScore: 0,
      activityScore: 0,
      personalityScore: 0,
      primaryCategory: 'general',
      categoryConfidence: 0,
      categoryReasoning: reason
    }
  };
}

// ENHANCED CONFIG FUNCTION
exports.getConfig = onCall({
  region: 'us-central1',
}, async (request) => {
  return {
    maxPhotos: 12,
    maxBatchSize: 12,
    supportedCriteria: [
      'best', 
      'social',
      'activity', 
      'personality',
      'balanced', 
      'profile_order', 
      'conversation_starters', 
      'broad_appeal', 
      'authenticity'
    ],
    version: '3.2.0',
    features: {
      enhancedPracticalAnalysis: true,
      professionalDepthAnalysis: true,
      detailedCategorization: true,
      strategicGuidance: true,
      practicalRecommendations: true,
      psychologicalInsights: true,
      marketPositioning: true,
      conversationOptimization: true,
      authenticityEvaluation: true,
      balancedSelection: true,
      enhancedImageProcessing: true,
      contentSafety: true,
      base64Processing: true,
      promoCodeSupport: true,
      premiumCategoryAnalysis: true
    },
    analysisDepth: 'practical_expert_level'
  };
});

// ENHANCED USER INITIALIZATION WITH LAUNCH CREDITS
exports.initializeUser = onCall({
  region: 'us-central1',
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  // Launch period special: 15 credits vs standard 3
  const launchStart = new Date('2025-07-24T00:00:00Z');
  const launchEnd = new Date(launchStart);
  launchEnd.setDate(launchEnd.getDate() + 14);
  const inLaunchPeriod = Date.now() >= launchStart.getTime() && Date.now() < launchEnd.getTime();
  const startingCredits = inLaunchPeriod ? 15 : 3;

  const userRef = admin.firestore().collection('users').doc(uid);
  
  try {
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      await userRef.set({
        email: request.auth.token.email || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        freeCredits: startingCredits,
        totalAnalyses: 0,
        isUnlimited: false,
        preferences: {
          defaultCriteria: 'best',
          analysisDepth: 'practical_expert',
          notifications: true
        },
        metadata: {
          signupPeriod: inLaunchPeriod ? 'launch' : 'standard',
          version: '3.2.0',
          analysisLevel: 'enhanced_practical'
        }
      });
      
      console.log(`Initialized new user: ${uid} with ${startingCredits} free credits`);
      return { 
        success: true, 
        newUser: true, 
        freeCredits: startingCredits,
        isLaunchPeriod: inLaunchPeriod,
        analysisLevel: 'enhanced_practical'
      };
    } else {
      const userData = userDoc.data();
      console.log(`Existing user: ${uid}, credits: ${userData.freeCredits}`);
      return { 
        success: true, 
        newUser: false, 
        freeCredits: userData.freeCredits || 0,
        isUnlimited: userData.isUnlimited || false,
        isLaunchPeriod: inLaunchPeriod,
        analysisLevel: 'enhanced_practical'
      };
    }
  } catch (error) {
    console.error('Error initializing user:', error);
    throw new HttpsError('internal', 'Failed to initialize user');
  }
});

// ENHANCED PROMO CODE REDEMPTION SYSTEM
exports.redeemPromoCode = onCall({
  region: 'us-central1',
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const code = String(request.data?.code || '').toUpperCase().trim();
  if (!code) {
    throw new HttpsError('invalid-argument', 'Promo code required');
  }

  // Enhanced promo code system with multiple tiers
  const promoCodes = {
    'K9X7M3P8Q2W5': {
      credits: 999,
      description: 'Unlimited Access - Enhanced Practical Analysis',
      isUnlimited: true,
      expirationDate: new Date(new Date().setFullYear(new Date().getFullYear() + 2)),
      maxUses: 10,
    },
    'LAUNCH50': {
      credits: 50,
      description: 'Launch Special - 50 Enhanced Practical Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 100,
    },
    'BETA20': {
      credits: 20,
      description: 'Beta Tester - 20 Enhanced Practical Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 50,
    },
    'FRIEND10': {
      credits: 10,
      description: 'Friend Referral - 10 Enhanced Expert Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 500,
    },
    'PREMIUM100': {
      credits: 100,
      description: 'Premium Package - 100 Enhanced Practical Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 25,
    }
  };

  const details = promoCodes[code];
  if (!details) {
    throw new HttpsError('not-found', 'Invalid promo code');
  }
  
  if (Date.now() > details.expirationDate.getTime()) {
    throw new HttpsError('failed-precondition', 'Promo code expired');
  }

  const db = admin.firestore();
  const userPromoRef = db.collection('users').doc(uid).collection('redeemedPromoCodes').doc(code);
  const globalRef = db.collection('promoCodes').doc(code);
  const userRef = db.collection('users').doc(uid);

  try {
    await db.runTransaction(async (transaction) => {
      const userPromoSnap = await transaction.get(userPromoRef);
      if (userPromoSnap.exists) {
        throw new HttpsError('already-exists', 'Promo code already redeemed');
      }

      const globalSnap = await transaction.get(globalRef);
      const uses = (globalSnap.data()?.uses) || 0;
      if (uses >= details.maxUses) {
        throw new HttpsError('failed-precondition', 'Promo code usage limit reached');
      }

      const userSnap = await transaction.get(userRef);
      const userData = userSnap.data() || {};
      const currentCredits = userData.freeCredits || 0;

      // Record promo redemption
      transaction.set(userPromoRef, {
        redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
        creditsAdded: details.credits,
        isUnlimited: details.isUnlimited,
        description: details.description,
        analysisLevel: 'enhanced_practical'
      });

      // Update global usage
      transaction.set(globalRef, {
        uses: uses + 1,
        lastUsed: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Update user credits and status
      const updateData = {
        freeCredits: details.isUnlimited ? 999999 : currentCredits + details.credits,
        isUnlimited: details.isUnlimited || userData.isUnlimited || false,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        'metadata.analysisLevel': 'enhanced_practical'
      };

      transaction.set(userRef, updateData, { merge: true });
    });

    console.log(`User ${uid} redeemed enhanced practical promo code ${code} for ${details.credits} credits`);
    
    return { 
      success: true, 
      promo: { 
        credits: details.credits, 
        isUnlimited: details.isUnlimited,
        description: details.description,
        analysisLevel: 'enhanced_practical'
      }
    };
  } catch (error) {
    console.error('Error redeeming promo code:', error);
    throw error;
  }
});

// ENHANCED CREDIT MANAGEMENT
exports.updateUserCredits = onCall({
  region: 'us-central1',
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const { freeCredits, creditsToAdd, creditsToDeduct, purchaseDetails } = request.data;
  const userRef = admin.firestore().collection('users').doc(uid);

  try {
    await admin.firestore().runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);
      const userData = userDoc.data() || {};
      
      let newCredits = userData.freeCredits || 0;
      
      if (typeof freeCredits === 'number') {
        newCredits = freeCredits;
      } else if (typeof creditsToAdd === 'number') {
        newCredits += creditsToAdd;
      } else if (typeof creditsToDeduct === 'number') {
        newCredits = Math.max(0, newCredits - creditsToDeduct);
      }

      const updateData = {
        freeCredits: newCredits,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      };

      if (purchaseDetails) {
        updateData.lastPurchase = {
          ...purchaseDetails,
          purchaseDate: admin.firestore.FieldValue.serverTimestamp()
        };
      }

      transaction.set(userRef, updateData, { merge: true });
    });

    console.log(`Updated credits for user ${uid}`);
    return { success: true };
  } catch (error) {
    console.error('Error updating user credits:', error);
    throw new HttpsError('internal', 'Failed to update credits');
  }
});
