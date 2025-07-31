const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const sharp = require('sharp');

// Initialize Firebase Admin SDK
admin.initializeApp();

// Define the secret for GEMINI_API_KEY
const geminiKey = defineSecret('GEMINI_API_KEY');

exports.analyzePhotos = onCall({
  secrets: [geminiKey],
  timeoutSeconds: 540,
  memory: '2GiB',
  region: 'us-central1',
}, async (request) => {
  try {
    const { photoUrls, criteria } = request.data;
    const maxBatchSize = 12;

    if (!photoUrls || !Array.isArray(photoUrls) || photoUrls.length === 0) {
      throw new HttpsError('invalid-argument', 'No photos provided');
    }

    if (photoUrls.length > maxBatchSize) {
      throw new HttpsError('invalid-argument', 
        `Maximum ${maxBatchSize} photos per batch. Please process in smaller groups.`);
    }

    if (!geminiKey.value()) {
      throw new HttpsError('internal', 'GEMINI_API_KEY not configured');
    }

    const genAI = new GoogleGenerativeAI(geminiKey.value());
    const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

    console.log(`Starting photo analysis with criteria: ${criteria} for ${photoUrls.length} photos`);

    const concurrencyLimit = 6;
    const batches = [];
    
    for (let i = 0; i < photoUrls.length; i += concurrencyLimit) {
      batches.push(photoUrls.slice(i, i + concurrencyLimit));
    }

    let allResults = [];

    for (const [batchIndex, batch] of batches.entries()) {
      console.log(`Processing batch ${batchIndex + 1}/${batches.length} (${batch.length} photos)`);
      
      const batchPromises = batch.map(async (photoUrl, index) => {
        try {
          await new Promise(resolve => setTimeout(resolve, index * 200));
          return await analyzeImageWithGemini(photoUrl, criteria, model);
        } catch (error) {
          console.error(`Error in batch ${batchIndex + 1}, photo ${index + 1}:`, error);
          return {
            fileName: `photo_${index}`,
            storageURL: photoUrl,
            score: 70,
            tags: [],
            bestQuality: "Photo uploaded successfully",
            suggestions: ["Analysis temporarily unavailable - please try again"]
          };
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
        totalPhotos: photoUrls.length,
        batchesProcessed: batches.length,
        averageScore: Math.round(allResults.reduce((sum, r) => sum + r.score, 0) / allResults.length)
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

async function analyzeImageWithGemini(photoUrl, criteria, model) {
  try {
    console.log(`Processing photo: ${photoUrl} with criteria: ${criteria}`);

    let filePath;
    if (photoUrl.includes('firebasestorage.googleapis.com')) {
      const matches = photoUrl.match(/o\/(.+?)\?/);
      if (matches && matches[1]) {
        filePath = decodeURIComponent(matches[1]);
      } else {
        throw new Error(`Could not parse file path from URL: ${photoUrl}`);
      }
    } else if (photoUrl.startsWith('gs://')) {
      filePath = photoUrl.replace(/^gs:\/\/[^\/]+\//, '');
    } else {
      filePath = photoUrl;
    }

    console.log(`Accessing file at path: ${filePath}`);
    const storage = admin.storage();
    const fileRef = storage.bucket().file(filePath);

    const [buffer] = await fileRef.download();
    console.log(`Downloaded photo, size: ${buffer.length} bytes`);

    const processedBuffer = await validateAndPrepareImage(buffer);
    console.log(`Processed image, new size: ${processedBuffer.length} bytes`);
    
    const result = await performGeminiAnalysis(processedBuffer, criteria, model);
    console.log(`Analysis complete for ${criteria}: Score ${result.score}`);
    
    // Return comprehensive result with all fields
    const analysisResult = {
      fileName: filePath.split('/').pop(),
      storageURL: photoUrl,
      score: result.score,
      tags: result.tags || [],
      bestQuality: result.bestQuality || result.strengths?.[0] || "Good photo quality",
      suggestions: result.suggestions || result.improvements || ["Keep up the great work!"],
      
      // Enhanced scoring data
      visualQuality: result.visualQuality || result.score,
      attractivenessScore: result.attractivenessScore || result.score,
      datingAppealScore: result.datingAppealScore || result.score,
      swipeWorthiness: result.swipeWorthiness || result.score,
      
      // Detailed feedback arrays
      strengths: result.strengths || [],
      improvements: result.improvements || result.suggestions || [],
      nextPhotoSuggestions: result.nextPhotoSuggestions || [],
      
      // Technical feedback
      technicalFeedback: result.technicalFeedback || {},
      
      // Dating insights
      datingInsights: result.datingInsights || {
        personalityProjected: result.personalityTraits || result.personalityProjected || [],
        demographicAppeal: result.demographicAppeal || result.targetDemographics || null,
        profileRole: result.profileRole || null
      },
      
      // Criteria-specific fields
      position: result.position,
      positionReason: result.positionReason,
      messageHooks: result.messageHooks,
      conversationElements: result.conversationElements,
      appealBreadth: result.appealBreadth,
      targetDemographics: result.targetDemographics,
      universalFactors: result.universalFactors,
      limitingFactors: result.limitingFactors,
      strategicAdvice: result.strategicAdvice,
      authenticityLevel: result.authenticityLevel,
      genuinenessFactors: result.genuinenessFactors,
      personalityTraits: result.personalityTraits,
      conversationAdvice: result.conversationAdvice,
      positioningAdvice: result.positioningAdvice
    };
    
    console.log(`Returning analysis result for ${criteria}:`, {
      score: analysisResult.score,
      hasStrengths: analysisResult.strengths.length > 0,
      hasImprovements: analysisResult.improvements.length > 0,
      hasTechnicalFeedback: Object.keys(analysisResult.technicalFeedback).length > 0
    });
    
    return analysisResult;
  } catch (error) {
    console.error(`Error processing photo ${photoUrl}:`, error);
    throw error;
  }
}

async function validateAndPrepareImage(buffer) {
  const metadata = await sharp(buffer).metadata();
  console.log(`Received image: ${metadata.width}x${metadata.height}, ${Math.round(buffer.length/1024)}KB`);
  
  const maxDimension = Math.max(metadata.width, metadata.height);
  
  if (maxDimension < 500) {
    throw new Error('Image too small for quality analysis (minimum 500px)');
  }
  
  if (buffer.length > 10 * 1024 * 1024) {
    throw new Error('Image too large (maximum 10MB)');
  }
  
  if (maxDimension > 2048) {
    console.log('Resizing oversized image to optimal size');
    return await sharp(buffer)
      .resize(1536, 1536, {
        fit: 'inside',
        withoutEnlargement: true
      })
      .jpeg({ quality: 92 })
      .toBuffer();
  }
  
  return buffer;
}

async function performGeminiAnalysis(imageBuffer, criteria, model) {
  const prompt = buildCriteriaSpecificPrompt(criteria);
  const base64Image = imageBuffer.toString('base64');
          
  try {
    console.log(`Analyzing image with ${criteria} prompt (${prompt.length} chars)`);
    
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
    
    const analysisResult = parseEnhancedAIResponse(text, criteria);
    console.log(`Parsed ${criteria} analysis:`, {
      score: analysisResult.score,
      hasStrengths: analysisResult.strengths?.length > 0,
      hasImprovements: analysisResult.improvements?.length > 0
    });
    
    return analysisResult;
  } catch (error) { 
    console.error('Gemini API error:', error);
    throw error;
  }         
}

function buildCriteriaSpecificPrompt(criteria) {
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

Focus on who this photo appeals to and provide strategic dating advice:

1. Rate this photo's broad vs niche appeal (broad = attracts many types, niche = attracts specific types strongly)
2. Identify specific demographic groups this appeals to most
3. Explain what makes it broadly appealing vs specialized
4. Give strategic advice for dating success

RETURN THIS EXACT JSON FORMAT:
{
  "score": (0-100),
  "appealBreadth": "broad",
  "targetDemographics": ["demographic 1", "demographic 2"],
  "universalFactors": ["broad appeal factor 1", "broad appeal factor 2"],
  "limitingFactors": ["limiting factor 1"],
  "strategicAdvice": "strategic advice for using this photo",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["social", "activity", "personality"],
  "strengths": ["strength 1", "strength 2"],
  "improvements": ["improvement 1", "improvement 2"],
  "nextPhotoSuggestions": ["suggestion 1", "suggestion 2"],
  "technicalFeedback": {
    "lighting": "lighting feedback",
    "composition": "composition feedback",
    "styling": "styling feedback"
  },
  "datingInsights": {
    "personalityProjected": ["trait1", "trait2"],
    "demographicAppeal": "primary demographic",
    "profileRole": "profile role"
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

function parseEnhancedAIResponse(responseText, criteria) {
  try {
    // Try to parse JSON from the response
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      console.log(`Successfully parsed JSON for ${criteria}:`, Object.keys(parsed));
      
      // Return the parsed object with all fields preserved
      return {
        score: Math.min(Math.max(parsed.score || 75, 0), 100),
        visualQuality: Math.min(Math.max(parsed.visualQuality || parsed.score || 75, 0), 100),
        attractivenessScore: Math.min(Math.max(parsed.attractivenessScore || parsed.score || 75, 0), 100),
        datingAppealScore: Math.min(Math.max(parsed.datingAppealScore || parsed.score || 75, 0), 100),
        swipeWorthiness: Math.min(Math.max(parsed.swipeWorthiness || parsed.score || 75, 0), 100),
        
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
        
        // Criteria-specific fields - preserve all that are actually used
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
        universalFactors: parsed.universalFactors,
        limitingFactors: parsed.limitingFactors,
        strategicAdvice: parsed.strategicAdvice,
        
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
  
  // Fallback parsing if JSON parsing fails
  console.log(`JSON parsing failed for ${criteria}, using fallback parsing`);
  
  let score = 75;
  const scoreMatch = responseText.match(/(?:score|rating):?\s*(\d+)/i);
  if (scoreMatch) {
    score = Math.min(Math.max(parseInt(scoreMatch[1], 10), 0), 100);
  }
  
  // Extract basic feedback
  let bestQuality = getCriteriaSpecificFallback(criteria, responseText);
  let suggestions = ["Consider the analysis feedback provided"];
  
  if (responseText.toLowerCase().includes('lighting')) {
    suggestions = ["Focus on improving lighting conditions"];
  } else if (responseText.toLowerCase().includes('background')) {
    suggestions = ["Consider a cleaner background"];
  }
  
  return {
    score: score,
    visualQuality: Math.max(score - 5, 0),
    attractivenessScore: score,
    datingAppealScore: Math.max(score - 3, 0),
    swipeWorthiness: Math.max(score - 2, 0),
    tags: [],
    bestQuality: bestQuality,
    suggestions: suggestions,
    strengths: [bestQuality],
    improvements: suggestions,
    nextPhotoSuggestions: ["Add more photos to complement this one"],
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
      return "Photo analyzed for profile positioning";
    case 'conversation_starters':
      return "Photo evaluated for conversation potential";
    case 'broad_appeal':
      return "Photo assessed for demographic appeal";
    case 'authenticity':
      return "Photo reviewed for authenticity";
    case 'balanced':
      return "Photo categorized for profile balance";
    default:
      return "Photo analysis completed";
  }
}

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
    version: '2.1.0',
    features: {
      enhancedAnalysis: true,
      detailedScoring: true,
      personalityInsights: true,
      technicalFeedback: true,
      profilePositioning: true,
      conversationOptimization: true,
      appealAnalysis: true,
      authenticityCheck: true
    }
  };
});

exports.initializeUser = onCall({
  region: 'us-central1',
}, async (request) => {
  const { auth } = request;
  
  if (!auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  const userId = auth.uid;
  const db = admin.firestore();
  
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      await db.collection('users').doc(userId).set({
        email: auth.token.email || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        credits: 3,
        totalAnalyses: 0,
        isUnlimited: false,
        preferences: {
          defaultCriteria: 'best',
          notifications: true
        }
      });
      
      console.log(`Initialized new user: ${userId} with 3 free credits`);
      return { success: true, credits: 3, isNewUser: true };
    } else {
      const userData = userDoc.data();
      console.log(`Existing user: ${userId}, credits: ${userData.credits}`);
      return { 
        success: true, 
        credits: userData.credits, 
        isUnlimited: userData.isUnlimited,
        isNewUser: false 
      };
    }
  } catch (error) {
    console.error('Error initializing user:', error);
    throw new HttpsError('internal', 'Failed to initialize user');
  }
});

exports.updateUserCredits = onCall({
  region: 'us-central1',
}, async (request) => {
  const { auth, data } = request;
  
  if (!auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  const { creditsToAdd, creditsToDeduct, purchaseDetails } = data;
  const userId = auth.uid;
  const db = admin.firestore();
  
  try {
    const userRef = db.collection('users').doc(userId);
    
    await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);
      
      if (!userDoc.exists) {
        throw new HttpsError('not-found', 'User not found');
      }
      
      const userData = userDoc.data();
      let newCredits = userData.credits || 0;
      
      if (creditsToAdd) {
        newCredits += creditsToAdd;
        console.log(`Adding ${creditsToAdd} credits to user ${userId}`);
      }
      
      if (creditsToDeduct) {
        if (userData.isUnlimited) {
          console.log(`User ${userId} has unlimited plan, not deducting credits`);
        } else {
          if (newCredits < creditsToDeduct) {
            throw new HttpsError('failed-precondition', 'Insufficient credits');
          }
          newCredits -= creditsToDeduct;
          console.log(`Deducting ${creditsToDeduct} credits from user ${userId}`);
        }
      }
      
      const updateData = {
        credits: newCredits,
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
exports.redeemPromoCode = onCall({
  region: 'us-central1',
}, async (request) => {
  const { auth, data } = request;
  const code = (data && data.code) ? String(data.code) : '';

  if (!auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const cleanCode = code.toUpperCase().trim();
  if (!cleanCode) {
    throw new HttpsError('invalid-argument', 'Invalid promo code');
  }

  const db = admin.firestore();
  const promoRef = db.collection('promoCodes').doc(cleanCode);
  const userRef = db.collection('users').doc(auth.uid);
  const userPromoRef = userRef.collection('redeemedPromoCodes').doc(cleanCode);

  let promoData;

  try {
    await db.runTransaction(async (transaction) => {
      const promoDoc = await transaction.get(promoRef);
      if (!promoDoc.exists) {
        throw new HttpsError('not-found', 'Promo code not found');
      }
      promoData = promoDoc.data();
      if (!promoData.isActive) {
        throw new HttpsError('failed-precondition', 'Promo code inactive');
      }
      if (promoData.expirationDate && promoData.expirationDate.toDate() < new Date()) {
        throw new HttpsError('deadline-exceeded', 'Promo code expired');
      }
      const currentUses = promoData.currentUses || 0;
      if (currentUses >= promoData.maxUses) {
        throw new HttpsError('resource-exhausted', 'Promo code usage limit reached');
      }

      const userPromoDoc = await transaction.get(userPromoRef);
      if (userPromoDoc.exists) {
        throw new HttpsError('already-exists', 'Promo code already redeemed');
      }

      const userDoc = await transaction.get(userRef);
      const userData = userDoc.data() || {};
      const currentCredits = userData.credits || 0;

      const updateData = {
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (promoData.isUnlimited) {
        updateData.isUnlimited = true;
        updateData.unlimitedUntil = promoData.expirationDate;
        updateData.credits = 999;
      } else {
        updateData.credits = currentCredits + promoData.credits;
      }

      transaction.set(userRef, updateData, { merge: true });
      transaction.set(userPromoRef, {
        redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
        creditsAdded: promoData.credits,
        isUnlimited: promoData.isUnlimited,
        description: promoData.description,
      });
      transaction.update(promoRef, {
        currentUses: currentUses + 1,
        lastUsed: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {
      success: true,
      credits: promoData.credits,
      description: promoData.description,
      isUnlimited: promoData.isUnlimited,
      expirationDate: promoData.expirationDate.toMillis() / 1000,
      maxUses: promoData.maxUses,
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('Error redeeming promo code:', error);
    throw new HttpsError('internal', 'Failed to redeem promo code');
  }
});
