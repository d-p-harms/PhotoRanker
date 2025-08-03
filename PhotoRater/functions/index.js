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

    console.log(`Starting enhanced photo analysis with criteria: ${criteria} for ${photos.length} photos`);

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
          return await analyzeImageWithGemini(photoData, criteria, model, index);
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
        processingVersion: '3.0.0'
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

// ENHANCED IMAGE ANALYSIS WITH GEMINI
async function analyzeImageWithGemini(photoData, criteria, model, index) {
  const timeout = 30000; // 30 second timeout

  return Promise.race([
    performAnalysis(photoData, criteria, model, index),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Analysis timeout')), timeout)
    )
  ]);
}

async function performAnalysis(photoData, criteria, model, index) {
  try {
    console.log(`Processing photo ${index} with criteria: ${criteria}`);

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
    const prompt = buildEnhancedCriteriaPrompt(criteria);

    console.log(`Analyzing image with ${criteria} prompt (${prompt.length} chars)`);

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
        console.log(`Raw AI response for ${criteria} (${text.length} chars):`, text.substring(0, 200));

        const analysisResult = parseEnhancedAIResponse(text, criteria, `photo_${index}`, '');
        console.log(`Parsed ${criteria} analysis:`, {
          score: analysisResult.score,
          hasStrengths: analysisResult.strengths?.length > 0,
          hasImprovements: analysisResult.improvements?.length > 0
        });

        return analysisResult;
      } catch (error) {
        retries--;
        if (retries === 0) throw error;

        // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, (3 - retries) * 1000));
      }
    }
  } catch (error) {
    console.error(`Analysis failed for photo ${index}:`, error);

    if (error.message.includes('too small') || error.message.includes('too large')) {
      return createRejectedResponse(`photo_${index}`, '', error.message);
    }

    return createFallbackResponse(`photo_${index}`, '', criteria, error.message);
  }
}

// ENHANCED CRITERIA-SPECIFIC PROMPTS (From File 1)
function buildEnhancedCriteriaPrompt(criteria) {
  const baseInstructions = `You are an expert dating profile consultant. Analyze this photo comprehensively and return detailed JSON analysis.

ALWAYS return a complete JSON response with all requested fields, even if some fields are empty arrays or null.`;

  switch (criteria) {
    case 'profile_order':
      return `${baseInstructions}

ANALYZE FOR OPTIMAL PROFILE POSITION:

Evaluate this photo for:
1. Main photo suitability (clear face, good lighting, simple background)
2. Supporting photo value (adds variety, shows different aspects)
3. Position recommendation (1-6 or 'skip' if not suitable)

Consider:
- Face clarity and visibility
- Background complexity
- Photo quality and appeal
- How it complements other photos in a profile sequence

RETURN THIS EXACT JSON FORMAT:
{
  "score": (0-100, positioning value),
  "position": "1" | "2" | "3" | "4" | "5" | "6" | "skip",
  "positionReason": "detailed explanation of why this position is recommended",
  "faceClarity": (0-100),
  "backgroundComplexity": (0-100, lower is better),
  "positioningAdvice": "specific advice for optimal positioning",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["social", "activity", "personality", "professional", "casual"],
  "strengths": ["specific strength 1", "specific strength 2"],
  "improvements": ["specific improvement 1", "specific improvement 2"],
  "nextPhotoSuggestions": ["complementary photo type 1", "complementary photo type 2"],
  "technicalFeedback": {
    "lighting": "lighting assessment",
    "composition": "composition feedback",
    "styling": "styling advice"
  },
  "datingInsights": {
    "personalityProjected": ["trait1", "trait2"],
    "profileRole": "strategic positioning role"
  }
}`;

    case 'conversation_starters':
      return `${baseInstructions}

ANALYZE FOR CONVERSATION POTENTIAL:

Identify elements that give people something specific to message about:
- Unique backgrounds or locations
- Visible activities, hobbies, interests
- Pets, travel elements, unusual objects
- Anything that invites questions or comments

Rate conversation potential (0-100) and identify specific talking points.

RETURN THIS EXACT JSON FORMAT:
{
  "score": (0-100, conversation starter value),
  "conversationElements": ["element 1", "element 2", "element 3"],
  "messageHooks": ["what someone could ask about 1", "what someone could ask about 2"],
  "conversationAdvice": "how to leverage this photo for conversations",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["social", "activity", "personality", "travel", "hobby"],
  "strengths": ["conversation strength 1", "conversation strength 2"],
  "improvements": ["how to add more conversation elements"],
  "nextPhotoSuggestions": ["complementary photo idea 1", "complementary photo idea 2"],
  "technicalFeedback": {
    "lighting": "lighting assessment",
    "composition": "composition feedback",
    "styling": "styling advice"
  },
  "datingInsights": {
    "personalityProjected": ["trait1", "trait2"],
    "profileRole": "conversation starter role"
  }
}`;

    case 'broad_appeal':
      return `${baseInstructions}

ANALYZE DEMOGRAPHIC APPEAL:

Evaluate:
- Mass market appeal vs niche attraction
- Which demographics this appeals to most
- Trade-offs between broad appeal and attracting ideal matches

RETURN THIS EXACT JSON FORMAT:
{
  "score": (0-100, broad appeal rating),
  "appealBreadth": "broad" | "moderate" | "niche",
  "targetDemographics": ["demographic 1", "demographic 2"],
  "appealStrategy": "strategic advice for using this photo",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["broad_appeal", "niche", "professional", "casual"],
  "strengths": ["appeal strength 1", "appeal strength 2"],
  "improvements": ["how to broaden appeal", "how to target better"],
  "nextPhotoSuggestions": ["complementary photo idea 1", "complementary photo idea 2"],
  "technicalFeedback": {
    "lighting": "lighting assessment",
    "composition": "composition feedback",
    "styling": "styling advice"
  },
  "datingInsights": {
    "personalityProjected": ["trait1", "trait2"],
    "demographicAppeal": "who this attracts most",
    "profileRole": "how to use strategically"
  }
}`;

    case 'authenticity':
      return `${baseInstructions}

ANALYZE AUTHENTICITY AND NATURALNESS:

Focus on:
- How genuine vs posed the photo appears
- Natural expressions and body language
- Candid vs staged feeling
- Authentic personality showing through

RETURN THIS EXACT JSON FORMAT:
{
  "score": (0-100, authenticity rating),
  "authenticityLevel": "natural" | "somewhat_posed" | "clearly_posed",
  "genuinenessFactors": "what makes this feel genuine or not",
  "authenticityAdvice": "how to appear more authentic",
  "personalityTraits": ["authentic trait 1", "authentic trait 2"],
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["authentic", "natural", "genuine", "personality"],
  "strengths": ["authenticity strength 1", "authenticity strength 2"],
  "improvements": ["how to be more natural", "how to show genuine personality"],
  "nextPhotoSuggestions": ["complementary authentic photo idea 1", "complementary authentic photo idea 2"],
  "technicalFeedback": {
    "lighting": "lighting assessment",
    "composition": "composition feedback",
    "styling": "styling advice"
  },
  "datingInsights": {
    "personalityProjected": ["genuine trait 1", "genuine trait 2"],
    "profileRole": "how authentic photos should be used"
  }
}`;

    case 'balanced':
      return `${baseInstructions}

ANALYZE FOR PROFILE VARIETY:

Determine photo type and categorize for balanced profile creation:
- Social context (with others, social settings)
- Activity/hobby content (sports, interests, activities)
- Personality expression (character, emotions, traits)

RETURN THIS EXACT JSON FORMAT:
{
  "score": (0-100, overall quality),
  "isSocial": true | false,
  "isActivity": true | false,
  "isPersonality": true | false,
  "profileRole": "main photo" | "social proof" | "activity showcase" | "personality highlight",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["social", "activity", "personality"],
  "strengths": ["what works well", "balance strength"],
  "improvements": ["enhancement suggestion", "balance improvement"],
  "nextPhotoSuggestions": ["complementary photo type 1", "complementary photo type 2"],
  "technicalFeedback": {
    "lighting": "lighting assessment",
    "composition": "composition feedback",
    "styling": "styling advice"
  },
  "datingInsights": {
    "personalityProjected": ["trait1", "trait2"],
    "profileRole": "strategic role in balanced profile"
  }
}`;

    default: // 'best' and fallback
      return `${baseInstructions}

COMPREHENSIVE PHOTO ANALYSIS:

Analyze for overall dating profile excellence:
- Visual quality (technical aspects, composition, lighting)
- Attractiveness factors (appearance, styling, appeal)
- Dating potential (swipe-worthiness, conversation potential)
- Overall impression and impact

RETURN THIS EXACT JSON FORMAT:
{
  "score": (0-100, overall excellence),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["social", "activity", "personality", "professional", "casual"],
  "strengths": ["specific strength 1", "specific strength 2", "specific strength 3"],
  "improvements": ["actionable improvement 1", "actionable improvement 2"],
  "bestQuality": "what makes this photo excellent",
  "suggestions": ["enhancement suggestion 1", "enhancement suggestion 2"],
  "nextPhotoSuggestions": ["complementary photo type 1", "complementary photo type 2"],
  "technicalFeedback": {
    "lighting": "detailed lighting assessment",
    "composition": "composition analysis and improvements",
    "styling": "outfit, grooming, accessory feedback"
  },
  "datingInsights": {
    "personalityProjected": ["trait1", "trait2", "trait3"],
    "demographicAppeal": "who this photo appeals to most",
    "profileRole": "how this should be used strategically"
  }
}`;
  }
}

// ENHANCED RESPONSE PARSING (From File 1)
function parseEnhancedAIResponse(responseText, criteria, fileName, photoUrl) {
  try {
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      console.log(`Successfully parsed JSON for ${criteria}:`, Object.keys(parsed));
      
      return {
        fileName: fileName,
        storageURL: photoUrl,
        score: Math.min(Math.max(parsed.score ?? 75, 0), 100),
        visualQuality: Math.min(Math.max(parsed.visualQuality ?? parsed.score ?? 75, 0), 100),
        attractivenessScore: Math.min(Math.max(parsed.attractivenessScore ?? parsed.score ?? 75, 0), 100),
        datingAppealScore: Math.min(Math.max(parsed.datingAppealScore ?? parsed.score ?? 75, 0), 100),
        swipeWorthiness: Math.min(Math.max(parsed.swipeWorthiness ?? parsed.score ?? 75, 0), 100),
        
        // Basic fields
        tags: Array.isArray(parsed.tags) ? parsed.tags : [],
        bestQuality: parsed.bestQuality || (Array.isArray(parsed.strengths) && parsed.strengths.length > 0 ? parsed.strengths[0] : "Good photo quality"),
        suggestions: Array.isArray(parsed.suggestions) ? parsed.suggestions : (Array.isArray(parsed.improvements) ? parsed.improvements : ["Keep up the great work!"]),
        
        // Enhanced feedback
        strengths: Array.isArray(parsed.strengths) ? parsed.strengths : [],
        improvements: Array.isArray(parsed.improvements) ? parsed.improvements : (Array.isArray(parsed.suggestions) ? parsed.suggestions : []),
        nextPhotoSuggestions: Array.isArray(parsed.nextPhotoSuggestions) ? parsed.nextPhotoSuggestions : [],
        
        // Technical feedback
        technicalFeedback: parsed.technicalFeedback || {},
        
        // Dating insights
        datingInsights: parsed.datingInsights || {
          personalityProjected: parsed.personalityProjected || parsed.personalityTraits || [],
          demographicAppeal: parsed.demographicAppeal,
          profileRole: parsed.profileRole
        },
        
        // Criteria-specific fields
        position: parsed.position,
        positionReason: parsed.positionReason,
        faceClarity: parsed.faceClarity,
        backgroundComplexity: parsed.backgroundComplexity,
        positioningAdvice: parsed.positioningAdvice,
        
        conversationElements: parsed.conversationElements,
        messageHooks: parsed.messageHooks,
        conversationAdvice: parsed.conversationAdvice,
        
        appealBreadth: parsed.appealBreadth,
        targetDemographics: parsed.targetDemographics,
        appealStrategy: parsed.appealStrategy,
        
        authenticityLevel: parsed.authenticityLevel,
        genuinenessFactors: parsed.genuinenessFactors,
        authenticityAdvice: parsed.authenticityAdvice,
        personalityTraits: parsed.personalityTraits,
        
        isSocial: parsed.isSocial,
        isActivity: parsed.isActivity,
        isPersonality: parsed.isPersonality
      };
    }
  } catch (error) {
    console.error(`Error parsing JSON for ${criteria}:`, error);
    console.log('Response text sample:', responseText.substring(0, 500));
  }
  
  // Enhanced fallback parsing
  console.log(`JSON parsing failed for ${criteria}, using enhanced fallback parsing`);
  return createEnhancedFallbackResponse(fileName, photoUrl, criteria, responseText);
}

// Export for testing
exports.parseEnhancedAIResponse = parseEnhancedAIResponse;

// ENHANCED FALLBACK RESPONSES
function createEnhancedFallbackResponse(fileName, photoUrl, criteria, responseText = '') {
  let score = 75;
  
  const scoreMatch = responseText.match(/(?:score|rating):?\s*(\d+)/i);
  if (scoreMatch) {
    score = Math.min(Math.max(parseInt(scoreMatch[1], 10), 0), 100);
  }
  
  let bestQuality = getCriteriaSpecificFallback(criteria, responseText);
  if (responseText.toLowerCase().includes('great lighting')) {
    bestQuality = "Excellent lighting creates an appealing look";
  } else if (responseText.toLowerCase().includes('natural')) {
    bestQuality = "Natural and authentic appearance is very attractive";
  } else if (responseText.toLowerCase().includes('confident')) {
    bestQuality = "Projects confidence which is highly appealing";
  }
  
  let suggestions = ["Consider enhancing lighting for better appeal"];
  if (responseText.toLowerCase().includes('background')) {
    suggestions = ["Try a less distracting background"];
  } else if (responseText.toLowerCase().includes('angle')) {
    suggestions = ["Experiment with different camera angles"];
  }
  
  const tags = [];
  if (responseText.toLowerCase().includes('social')) tags.push('social');
  if (responseText.toLowerCase().includes('activity')) tags.push('activity');
  if (responseText.toLowerCase().includes('personality')) tags.push('personality');
  
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
    nextPhotoSuggestions: ["Add complementary photos to showcase different aspects"],
    technicalFeedback: {},
    datingInsights: {
      personalityProjected: [],
      demographicAppeal: null,
      profileRole: null
    }
  };
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
    tags: [],
    bestQuality: "Photo uploaded successfully",
    suggestions: ["Analysis temporarily unavailable - please try again"],
    strengths: ["Photo processed successfully"],
    improvements: [errorMessage || "Please try uploading again"],
    nextPhotoSuggestions: ["Try different photos for comparison"],
    technicalFeedback: {},
    datingInsights: {
      personalityProjected: [],
      demographicAppeal: null,
      profileRole: null
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
      demographicAppeal: null,
      profileRole: null
    }
  };
}

function getCriteriaSpecificFallback(criteria, responseText) {
  switch (criteria) {
    case 'profile_order':
      return "Photo analyzed for optimal profile positioning";
    case 'conversation_starters':
      return "Photo evaluated for conversation potential";
    case 'broad_appeal':
      return "Photo assessed for demographic appeal";
    case 'authenticity':
      return "Photo reviewed for authenticity and naturalness";
    case 'balanced':
      return "Photo categorized for balanced profile creation";
    default:
      return "Comprehensive photo analysis completed";
  }
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
    version: '3.0.0',
    features: {
      enhancedAnalysis: true,
      detailedScoring: true,
      personalityInsights: true,
      technicalFeedback: true,
      profilePositioning: true,
      conversationOptimization: true,
      appealAnalysis: true,
      authenticityCheck: true,
      enhancedImageProcessing: true,
      contentSafety: true,
      base64Processing: true,
      promoCodeSupport: true
    }
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
          notifications: true
        },
        metadata: {
          signupPeriod: inLaunchPeriod ? 'launch' : 'standard',
          version: '3.0.0'
        }
      });
      
      console.log(`Initialized new user: ${uid} with ${startingCredits} free credits`);
      return { 
        success: true, 
        newUser: true, 
        freeCredits: startingCredits,
        isLaunchPeriod: inLaunchPeriod
      };
    } else {
      const userData = userDoc.data();
      console.log(`Existing user: ${uid}, credits: ${userData.freeCredits}`);
      return { 
        success: true, 
        newUser: false, 
        freeCredits: userData.freeCredits || 0,
        isUnlimited: userData.isUnlimited || false,
        isLaunchPeriod: inLaunchPeriod
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
      description: 'Unlimited Access - Premium',
      isUnlimited: true,
      expirationDate: new Date(new Date().setFullYear(new Date().getFullYear() + 2)),
      maxUses: 10,
    },
    'LAUNCH50': {
      credits: 50,
      description: 'Launch Special - 50 Credits',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 100,
    },
    'BETA20': {
      credits: 20,
      description: 'Beta Tester Bonus',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 50,
    },
    'FRIEND10': {
      credits: 10,
      description: 'Friend Referral',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 500,
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
      };

      transaction.set(userRef, updateData, { merge: true });
    });

    console.log(`User ${uid} redeemed promo code ${code} for ${details.credits} credits`);
    
    return { 
      success: true, 
      promo: { 
        credits: details.credits, 
        isUnlimited: details.isUnlimited,
        description: details.description
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
        console.log(`Adding ${creditsToAdd} credits to user ${uid}`);
      }
      
      if (creditsToDeduct) {
        if (userData.isUnlimited) {
          console.log(`User ${uid} has unlimited plan, not deducting credits`);
        } else {
          if (newCredits < creditsToDeduct) {
            throw new HttpsError('failed-precondition', 'Insufficient credits');
          }
          newCredits -= creditsToDeduct;
          console.log(`Deducting ${creditsToDeduct} credits from user ${uid}`);
        }
      }
      
      const updateData = {
        freeCredits: Math.max(newCredits, 0),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      };
      
      if (creditsToDeduct) {
        updateData.totalAnalyses = (userData.totalAnalyses || 0) + creditsToDeduct;
      }
      
      if (purchaseDetails) {
        updateData.lastPurchase = {
          ...purchaseDetails,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        };
      }
      
      transaction.update(userRef, updateData);
    });
    
    return { success: true };
  } catch (error) {
    console.error('Error updating user credits:', error);
    throw error;
  }
});
