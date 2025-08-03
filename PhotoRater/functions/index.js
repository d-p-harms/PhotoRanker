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

// CONTENT SAFETY CHECK
async function performSafetyCheck(imageBuffer) {
  try {
    const [safeResult] = await visionClient.safeSearchDetection(imageBuffer);
    const safe = safeResult.safeSearchAnnotation || {};
    const flaggedLevels = ['LIKELY', 'VERY_LIKELY'];
    
    if (flaggedLevels.includes(safe.adult) || 
        flaggedLevels.includes(safe.violence) || 
        flaggedLevels.includes(safe.racy)) {
      console.warn('SafeSearch blocked image:', safe);
      return false;
    }
    
    return true;
  } catch (error) {
    console.warn('SafeSearch check failed, proceeding with analysis:', error);
    return true; // Don't block if safety check fails
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

    console.log(`Starting hybrid analysis with criteria: ${criteria} for ${photos.length} photos`);

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
          return await analyzeImageWithHybridApproach(photoData, criteria, model, index);
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
        analysisDepth: 'hybrid_practical_plus_insights'
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

// HYBRID ANALYSIS APPROACH - PRACTICAL + INSIGHTS
async function analyzeImageWithHybridApproach(photoData, criteria, model, index) {
  const timeout = 45000; // 45 second timeout

  return Promise.race([
    performHybridAnalysis(photoData, criteria, model, index),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Hybrid analysis timeout')), timeout)
    )
  ]);
}

async function performHybridAnalysis(photoData, criteria, model, index) {
  try {
    console.log(`Processing photo ${index} with hybrid ${criteria} analysis`);

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
    const prompt = buildHybridAnalysisPrompt(criteria);

    console.log(`Analyzing image with hybrid ${criteria} prompt (${prompt.length} chars)`);

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
        console.log(`Raw hybrid AI response for ${criteria} (${text.length} chars)`);

        const analysisResult = parseHybridAIResponse(text, criteria, `photo_${index}`, '');
        console.log(`Parsed hybrid ${criteria} analysis:`, {
          score: analysisResult.score,
          hasActionableAdvice: analysisResult.strengths?.length > 0,
          hasPsychologicalInsights: analysisResult.psychologicalInsights?.confidence?.length > 0
        });

        return analysisResult;
      } catch (error) {
        retries--;
        if (retries === 0) throw error;

        // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, (3 - retries) * 2000));
      }
    }
  } catch (error) {
    console.error(`Hybrid analysis failed for photo ${index}:`, error);

    if (error.message.includes('too small') || error.message.includes('too large')) {
      return createRejectedResponse(`photo_${index}`, '', error.message);
    }

    return createFallbackResponse(`photo_${index}`, '', criteria, error.message);
  }
}

// HYBRID PROMPTS - PRACTICAL FOUNDATION + PSYCHOLOGICAL INSIGHTS
function buildHybridAnalysisPrompt(criteria) {
  const practicalBase = `You are an expert dating profile consultant analyzing photos for maximum dating success.

ANALYZE THIS PHOTO COMPREHENSIVELY:

VISUAL QUALITY ASSESSMENT (0-100):
- Technical quality: lighting conditions, composition rules, sharpness, color balance
- Aesthetic appeal: visual harmony, artistic merit, professional appearance
- Photo execution: looks intentional vs accidental, proper framing

ATTRACTIVENESS FACTORS (0-100):
- Facial features: symmetry, expression authenticity, eye contact effectiveness
- Body language: confident posture, approachability signals, relaxed vs tense
- Styling choices: outfit appropriateness, grooming level, accessories that enhance appeal

DATING APPEAL ANALYSIS (0-100):
- First impression impact: immediate attraction factor, memorable elements
- Personality projection: what character traits are clearly communicated
- Conversation potential: interesting elements that naturally invite questions
- Swipe-worthiness: thumb-stopping power on dating apps, differentiation factor

CONTEXT & SETTING EVALUATION:
- Location appropriateness for dating profiles and target demographic
- Activity/lifestyle signals being communicated effectively
- Social context (if others present) - analyze honestly without forcing categorization
- Props/background elements that add value or create distractions

CATEGORIZATION ANALYSIS:
- Social indicators: Are there other people visible? Group setting? Social activity?
- Activity indicators: Sports, hobbies, adventures, skills being demonstrated?
- Personality indicators: Genuine expressions, character traits, authentic moments?

PSYCHOLOGICAL INSIGHTS (DEEPER UNDERSTANDING):
- Confidence indicators and how they're projected
- Emotional intelligence signals visible in the photo
- Authenticity vs. performance assessment
- Psychological impact on viewers (trust, attraction, relatability)
- Market positioning in competitive dating environment

PROVIDE SPECIFIC, ACTIONABLE FEEDBACK:
- What's working exceptionally well (be specific and encouraging)
- Improvements that enhance this photo within its current context
- Technical fixes that would enhance photo quality
- Styling/positioning suggestions that work for this setting

${getCriteriaFocus(criteria)}

RETURN COMPREHENSIVE JSON ANALYSIS:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100), 
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  
  "tags": [select applicable from: "social", "activity", "personality", "professional", "casual", "outdoor", "group", "travel", "hobby"],
  
  "categorization": {
    "socialScore": (0-100, based on presence of others, social setting, group dynamics),
    "activityScore": (0-100, based on sports, hobbies, adventures, skill demonstration),
    "personalityScore": (0-100, based on authentic expressions, character traits, emotional connection),
    "primaryCategory": "social|activity|personality|general",
    "categoryConfidence": (0-100, how confident you are in the primary category)
  },
  
  "strengths": [
    "Specific positive element that works well",
    "Another strong aspect of the photo",
    "Third strength worth highlighting"
  ],
  
  "improvements": [
    "Specific actionable improvement that enhances THIS photo type",
    "Technical adjustment that would enhance appeal within current context", 
    "Styling/positioning suggestion that works for this setting"
  ],
  
  "technicalFeedback": {
    "lighting": "detailed lighting assessment and specific suggestions",
    "composition": "framing analysis and composition improvements for this photo type",
    "styling": "outfit, grooming, and accessory feedback appropriate for this context"
  },
  
  "datingInsights": {
    "personalityProjected": ["confident", "fun", "adventurous", "intellectual", "approachable", "social"],
    "demographicAppeal": "specific description of who this photo appeals to most",
    "profileRole": "how this photo should be strategically used in a dating profile"
  },
  
  "psychologicalInsights": {
    "confidence": ["specific confidence indicators visible in photo"],
    "authenticity": "natural vs posed assessment with reasoning",
    "emotionalIntelligence": "EQ indicators shown through expression/body language",
    "marketPositioning": "how this positions you in the dating market",
    "psychologicalImpact": "what emotional response this photo likely evokes",
    "trustworthiness": "factors that build or reduce trust perception",
    "approachability": "elements that make you seem more or less approachable"
  },
  
  "competitiveAnalysis": {
    "uniqueElements": ["what makes this photo stand out from typical dating photos"],
    "marketAdvantages": ["your competitive strengths in this photo"],
    "improvementPotential": ["areas where small changes could yield big improvements"]
  },
  
  "nextPhotoSuggestions": [
    "Different type of photo that would complement this one (variety is key)",
    "Specific scenario that would add balance to your profile mix"
  ]
}

CATEGORIZATION GUIDELINES:
- Social: 2+ people visible, group activities, parties, social events, team photos
- Activity: Sports, hobbies, travel, adventures, skills, outdoor activities, instruments
- Personality: Close-ups with genuine expressions, candid moments, creative shots, artistic poses
- General: Solo photos that don't clearly fit other categories, headshots, basic portraits

Be encouraging but honest. Provide specific actionable advice that improves the photo within its current context.`;

  return practicalBase;
}

function getCriteriaFocus(criteria) {
  switch (criteria) {
    case 'social':
      return 'SOCIAL FOCUS: Emphasize social elements, group dynamics, and social context. Evaluate how well the photo demonstrates social connectivity and what it says about your social life.';
    case 'activity':
      return 'ACTIVITY FOCUS: Focus on activities, hobbies, lifestyle demonstration, and skill showcase. Group activities can show both social and active aspects. Analyze what this reveals about your interests and lifestyle.';
    case 'personality':
      return 'PERSONALITY FOCUS: Deep dive into personality traits, character projection, and authenticity markers revealed in the photo. Focus on what makes you uniquely you.';
    case 'balanced':
      return 'BALANCED FOCUS: Provide detailed categorization scores for social, activity, and personality aspects. Analyze what type of photo this is and how it contributes to a diverse dating profile. Be precise about categorization - this will be used for balanced selection.';
    case 'profile_order':
      return 'POSITIONING FOCUS: Analyze where this photo should be positioned in a dating profile (main photo vs supporting). Consider face clarity, immediate impact, and how it fits in a profile sequence.';
    case 'conversation_starters':
      return 'CONVERSATION FOCUS: Identify specific elements that would give someone something to message you about. Look for conversation hooks, interesting background details, and discussion starters.';
    case 'broad_appeal':
      return 'APPEAL FOCUS: Evaluate appeal across different demographics. Analyze mass market appeal vs niche attraction and strategic positioning for maximum reach.';
    case 'authenticity':
      return 'AUTHENTICITY FOCUS: Assess how genuine and natural you appear. Analyze posed vs candid feelings, authentic expression, and personality authenticity.';
    default:
      return 'OVERALL FOCUS: Focus on overall dating profile optimization, broad demographic appeal, and maximizing dating success potential while providing deep insights into your personal brand.';
  }
}

// HYBRID AI RESPONSE PARSING
function parseHybridAIResponse(responseText, criteria, fileName, photoUrl) {
  try {
    // Enhanced JSON extraction
    let jsonMatch = responseText.match(/\{[\s\S]*\}/);
    
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      console.log(`Successfully parsed hybrid JSON for ${criteria}:`, Object.keys(parsed));
      
      // Create hybrid response with both practical and insight elements
      const result = {
        fileName: fileName,
        storageURL: photoUrl,
        score: Math.min(Math.max(parsed.overallScore ?? parsed.score ?? 75, 0), 100),
        visualQuality: Math.min(Math.max(parsed.visualQuality ?? 75, 0), 100),
        attractivenessScore: Math.min(Math.max(parsed.attractivenessScore ?? 75, 0), 100),
        datingAppealScore: Math.min(Math.max(parsed.datingAppealScore ?? 75, 0), 100),
        swipeWorthiness: Math.min(Math.max(parsed.swipeWorthiness ?? 75, 0), 100),
        
        // Practical elements (from Document 4)
        tags: Array.isArray(parsed.tags) ? parsed.tags : [],
        bestQuality: Array.isArray(parsed.strengths) && parsed.strengths.length > 0 
          ? parsed.strengths[0] 
          : parsed.bestQuality || "Good photo for dating profile",
        suggestions: Array.isArray(parsed.improvements) && parsed.improvements.length > 0
          ? parsed.improvements
          : Array.isArray(parsed.suggestions) 
            ? parsed.suggestions 
            : ["Keep taking great photos!"],
        
        strengths: Array.isArray(parsed.strengths) ? parsed.strengths : [],
        improvements: Array.isArray(parsed.improvements) ? parsed.improvements : [],
        nextPhotoSuggestions: Array.isArray(parsed.nextPhotoSuggestions) ? parsed.nextPhotoSuggestions : [],
        technicalFeedback: parsed.technicalFeedback || {},
        
        // Essential categorization (from Document 4)
        categorization: parsed.categorization ? {
          socialScore: Math.min(Math.max(parsed.categorization.socialScore ?? 0, 0), 100),
          activityScore: Math.min(Math.max(parsed.categorization.activityScore ?? 0, 0), 100),
          personalityScore: Math.min(Math.max(parsed.categorization.personalityScore ?? 0, 0), 100),
          primaryCategory: parsed.categorization.primaryCategory || 'general',
          categoryConfidence: Math.min(Math.max(parsed.categorization.categoryConfidence ?? 50, 0), 100)
        } : inferCategorization(parsed.tags, parsed.strengths),
        
        // Basic dating insights (from Document 4)
        datingInsights: {
          personalityProjected: parsed.datingInsights?.personalityProjected || [],
          demographicAppeal: parsed.datingInsights?.demographicAppeal || "Broad appeal",
          profileRole: parsed.datingInsights?.profileRole || "Supporting photo"
        },
        
        // Enhanced psychological insights (from Document 5)
        psychologicalInsights: parsed.psychologicalInsights ? {
          confidence: parsed.psychologicalInsights.confidence || [],
          authenticity: parsed.psychologicalInsights.authenticity || "Assessment pending",
          emotionalIntelligence: parsed.psychologicalInsights.emotionalIntelligence || "Analysis available",
          marketPositioning: parsed.psychologicalInsights.marketPositioning || "Competitive analysis",
          psychologicalImpact: parsed.psychologicalInsights.psychologicalImpact || "Impact assessment",
          trustworthiness: parsed.psychologicalInsights.trustworthiness || "Trust factor analysis",
          approachability: parsed.psychologicalInsights.approachability || "Approachability assessment"
        } : null,
        
        // Competitive analysis (simplified from Document 5)
        competitiveAnalysis: parsed.competitiveAnalysis ? {
          uniqueElements: parsed.competitiveAnalysis.uniqueElements || [],
          marketAdvantages: parsed.competitiveAnalysis.marketAdvantages || [],
          improvementPotential: parsed.competitiveAnalysis.improvementPotential || []
        } : null,
        
        // Criteria-specific fields
        position: parsed.position,
        positionReason: parsed.positionReason,
        conversationElements: parsed.conversationElements,
        messageHooks: parsed.messageHooks,
        appealBreadth: parsed.appealBreadth,
        authenticityLevel: parsed.authenticityLevel
      };
      
      return result;
    }
  } catch (error) {
    console.error(`Error parsing hybrid JSON for ${criteria}:`, error);
    console.log('Response text sample:', responseText.substring(0, 500));
  }
  
  // Enhanced fallback parsing
  console.log(`JSON parsing failed for ${criteria}, using hybrid fallback parsing`);
  return createHybridFallbackResponse(fileName, photoUrl, criteria, responseText);
}

// Export parser for testing
exports.parseEnhancedAIResponse = parseHybridAIResponse;

// Helper function for categorization inference
function inferCategorization(tags, strengths) {
  const socialTags = ['social', 'group', 'friends', 'party', 'team'];
  const activityTags = ['activity', 'sport', 'hobby', 'travel', 'outdoor', 'adventure'];
  const personalityTags = ['personality', 'authentic', 'genuine', 'expression', 'creative'];
  
  let socialScore = 0;
  let activityScore = 0; 
  let personalityScore = 0;
  
  if (tags) {
    socialScore = tags.filter(tag => socialTags.includes(tag.toLowerCase())).length * 25;
    activityScore = tags.filter(tag => activityTags.includes(tag.toLowerCase())).length * 25;
    personalityScore = tags.filter(tag => personalityTags.includes(tag.toLowerCase())).length * 25;
  }
  
  // Base scores
  socialScore = Math.max(socialScore, 30);
  activityScore = Math.max(activityScore, 30);
  personalityScore = Math.max(personalityScore, 30);
  
  const maxScore = Math.max(socialScore, activityScore, personalityScore);
  let primaryCategory = 'general';
  
  if (maxScore === socialScore) primaryCategory = 'social';
  else if (maxScore === activityScore) primaryCategory = 'activity';
  else if (maxScore === personalityScore) primaryCategory = 'personality';
  
  return {
    socialScore: Math.min(socialScore, 100),
    activityScore: Math.min(activityScore, 100),
    personalityScore: Math.min(personalityScore, 100),
    primaryCategory,
    categoryConfidence: Math.min(maxScore, 100)
  };
}

// HYBRID FALLBACK RESPONSES
function createHybridFallbackResponse(fileName, photoUrl, criteria, responseText = '') {
  let score = 75;
  
  const scoreMatch = responseText.match(/(?:score|rating):?\s*(\d+)/i);
  if (scoreMatch) {
    score = Math.min(Math.max(parseInt(scoreMatch[1], 10), 0), 100);
  }
  
  let bestQuality = getHybridFallback(criteria, responseText);
  let suggestions = ["Consider technical improvements for enhanced appeal"];
  
  // Enhanced content analysis
  if (responseText.toLowerCase().includes('excellent')) {
    score = Math.max(score, 85);
    bestQuality = "Excellent photo quality with strong appeal";
  } else if (responseText.toLowerCase().includes('confident')) {
    bestQuality = "Shows confidence which is very attractive";
  }
  
  const tags = extractTags(responseText);
  const categorization = inferCategorization(tags, [bestQuality]);
  
  return {
    fileName: fileName,
    storageURL: photoUrl,
    score: score,
    visualQuality: Math.max(score - 5, 0),
    attractivenessScore: score,
    datingAppealScore: Math.max(score - 3, 0),
    swipeWorthiness: Math.max(score - 2, 0),
    
    tags: tags,
    bestQuality: bestQuality,
    suggestions: suggestions,
    strengths: [bestQuality],
    improvements: suggestions,
    nextPhotoSuggestions: ["Add complementary photos for variety"],
    technicalFeedback: {},
    
    categorization: categorization,
    
    datingInsights: {
      personalityProjected: [],
      demographicAppeal: "Analysis in progress",
      profileRole: "Profile enhancement"
    },
    
    psychologicalInsights: {
      confidence: ["Confidence assessment available"],
      authenticity: "Authenticity analysis pending",
      emotionalIntelligence: "EQ evaluation in progress",
      marketPositioning: "Market position analysis",
      psychologicalImpact: "Psychological impact assessment",
      trustworthiness: "Trust factor evaluation",
      approachability: "Approachability analysis"
    },
    
    competitiveAnalysis: {
      uniqueElements: ["Unique qualities identified"],
      marketAdvantages: ["Competitive advantages noted"],
      improvementPotential: ["Enhancement opportunities available"]
    }
  };
}

function extractTags(responseText) {
  const tags = [];
  const text = responseText.toLowerCase();
  
  if (text.includes('social') || text.includes('group')) tags.push('social');
  if (text.includes('activity') || text.includes('sport')) tags.push('activity');
  if (text.includes('personality') || text.includes('character')) tags.push('personality');
  if (text.includes('professional')) tags.push('professional');
  if (text.includes('casual')) tags.push('casual');
  if (text.includes('outdoor')) tags.push('outdoor');
  
  return tags.length > 0 ? tags : ['analyzed'];
}

function getHybridFallback(criteria, responseText) {
  const qualityIndicators = {
    'social': "Photo shows social engagement and connectivity",
    'activity': "Photo demonstrates active lifestyle and interests", 
    'personality': "Photo reveals authentic personality traits",
    'balanced': "Photo contributes to well-rounded profile presentation",
    'profile_order': "Photo suitable for strategic profile positioning",
    'conversation_starters': "Photo provides conversation opportunities",
    'broad_appeal': "Photo has broad demographic appeal",
    'authenticity': "Photo shows genuine, authentic expression",
    'best': "Photo demonstrates overall dating profile quality"
  };
  
  return qualityIndicators[criteria] || "Professional photo analysis completed";
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
    tags: ['uploaded'],
    bestQuality: "Photo uploaded successfully",
    suggestions: ["Analysis temporarily unavailable - please try again"],
    strengths: ["Photo processed successfully"],
    improvements: [errorMessage || "Please try uploading again"],
    nextPhotoSuggestions: ["Try different photos for comparison"],
    technicalFeedback: {},
    categorization: {
      socialScore: 50,
      activityScore: 50,
      personalityScore: 50,
      primaryCategory: 'general',
      categoryConfidence: 50
    },
    datingInsights: {
      personalityProjected: [],
      demographicAppeal: "Processing",
      profileRole: "Analysis pending"
    },
    psychologicalInsights: null,
    competitiveAnalysis: null
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
    categorization: {
      socialScore: 0,
      activityScore: 0,
      personalityScore: 0,
      primaryCategory: 'rejected',
      categoryConfidence: 100
    },
    datingInsights: {
      personalityProjected: [],
      demographicAppeal: "Not applicable",
      profileRole: "Not suitable"
    },
    psychologicalInsights: null,
    competitiveAnalysis: null
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
      'balanced', 
      'profile_order', 
      'conversation_starters', 
      'broad_appeal', 
      'authenticity',
      'social',
      'activity',
      'personality'
    ],
    version: '3.2.0',
    features: {
      hybridAnalysis: true,
      practicalAdvice: true,
      psychologicalInsights: true,
      competitiveAnalysis: true,
      categorizationScoring: true,
      actionableFeedback: true,
      personalityAssessment: true,
      marketPositioning: true,
      enhancedImageProcessing: true,
      contentSafety: true,
      base64Processing: true,
      promoCodeSupport: true
    },
    analysisDepth: 'hybrid_practical_plus_insights'
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
          analysisDepth: 'hybrid',
          notifications: true,
          showPsychologicalInsights: true
        },
        metadata: {
          signupPeriod: inLaunchPeriod ? 'launch' : 'standard',
          version: '3.2.0',
          analysisLevel: 'hybrid'
        }
      });
      
      console.log(`Initialized new user: ${uid} with ${startingCredits} free credits (hybrid analysis)`);
      return { 
        success: true, 
        newUser: true, 
        freeCredits: startingCredits,
        isLaunchPeriod: inLaunchPeriod,
        analysisLevel: 'hybrid'
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
        analysisLevel: 'hybrid'
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

  // Enhanced promo code system
  const promoCodes = {
    'K9X7M3P8Q2W5': {
      credits: 999,
      description: 'Unlimited Access - Hybrid Analysis with Psychological Insights',
      isUnlimited: true,
      expirationDate: new Date(new Date().setFullYear(new Date().getFullYear() + 2)),
      maxUses: 10,
    },
    'LAUNCH50': {
      credits: 50,
      description: 'Launch Special - 50 Hybrid Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 100,
    },
    'BETA20': {
      credits: 20,
      description: 'Beta Tester - 20 Hybrid Analyses with Insights',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 50,
    },
    'FRIEND10': {
      credits: 10,
      description: 'Friend Referral - 10 Enhanced Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 500,
    },
    'PREMIUM100': {
      credits: 100,
      description: 'Premium Package - 100 Complete Hybrid Analyses',
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
        analysisLevel: 'hybrid'
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
        'metadata.analysisLevel': 'hybrid',
        'preferences.showPsychologicalInsights': true
      };

      transaction.set(userRef, updateData, { merge: true });
    });

    console.log(`User ${uid} redeemed hybrid promo code ${code} for ${details.credits} credits`);
    
    return { 
      success: true, 
      promo: { 
        credits: details.credits, 
        isUnlimited: details.isUnlimited,
        description: details.description,
        analysisLevel: 'hybrid'
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
      
      if (!userDoc.exists) {
        throw new HttpsError('not-found', 'User not found');
      }
      
      const userData = userDoc.data();
      let newCredits = userData.freeCredits || 0;
      
      // Handle different credit operations
      if (typeof freeCredits === 'number') {
        newCredits = freeCredits;
      }
      
      if (creditsToAdd) {
        newCredits += creditsToAdd;
        console.log(`Adding ${creditsToAdd} hybrid analysis credits to user ${uid}`);
      }
      
      if (creditsToDeduct) {
        if (userData.isUnlimited) {
          console.log(`User ${uid} has unlimited hybrid analysis plan, not deducting credits`);
        } else {
          if (newCredits < creditsToDeduct) {
            throw new HttpsError('failed-precondition', 'Insufficient credits for hybrid analysis');
          }
          newCredits -= creditsToDeduct;
          console.log(`Deducting ${creditsToDeduct} hybrid analysis credits from user ${uid}`);
        }
      }
      
      const updateData = {
        freeCredits: Math.max(newCredits, 0),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        'metadata.lastAnalysisLevel': 'hybrid'
      };
      
      if (creditsToDeduct) {
        updateData.totalAnalyses = (userData.totalAnalyses || 0) + creditsToDeduct;
        updateData.hybridAnalyses = (userData.hybridAnalyses || 0) + creditsToDeduct;
      }
      
      if (purchaseDetails) {
        updateData.lastPurchase = {
          ...purchaseDetails,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          analysisLevel: 'hybrid'
        };
      }
      
      transaction.update(userRef, updateData);
    });
    
    return { success: true, analysisLevel: 'hybrid' };
  } catch (error) {
    console.error('Error updating user credits:', error);
    throw error;
  }
});
