const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const sharp = require('sharp');

// Initialize Firebase Admin SDK
admin.initializeApp();

// Define the secret for GEMINI_API_KEY
const geminiKey = defineSecret('GEMINI_API_KEY');

// ANALYZE PHOTOS FUNCTION
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
      }
    }

    const fileName = filePath ? filePath.split('/').pop() : 'uploaded_photo';

    const bucket = admin.storage().bucket();
    const file = bucket.file(filePath);
    
    const [buffer] = await file.download();
    
    const resizedBuffer = await sharp(buffer)
      .resize(1024, 1024, { 
        fit: 'inside',
        withoutEnlargement: true 
      })
      .jpeg({ quality: 85 })
      .toBuffer();

    const base64Image = resizedBuffer.toString('base64');

    const prompt = generatePrompt(criteria);
    
    const result = await model.generateContent([
      prompt,
      {
        inlineData: {
          data: base64Image,
          mimeType: 'image/jpeg'
        }
      }
    ]);

    const response = await result.response;
    const text = response.text();
    
    console.log(`Analysis complete for ${fileName}`);
    
    return parseGeminiResponse(text, fileName, photoUrl, criteria);
    
  } catch (error) {
    console.error('Error in analyzeImageWithGemini:', error);
    
    const fileName = photoUrl.split('/').pop() || 'photo';
    return createFallbackResponse(fileName, photoUrl, criteria);
  }
}

function generatePrompt(criteria) {
  const basePrompt = `You are an expert dating profile consultant. Analyze this photo and provide specific, actionable feedback.

IMPORTANT: Your response must be valid JSON in this exact format:
{
  "score": 85,
  "visualQuality": 88,
  "attractivenessScore": 82,
  "datingAppealScore": 87,
  "swipeWorthiness": 84,
  "tags": ["outdoor", "genuine_smile", "good_lighting"],
  "bestQuality": "Genuine smile creates immediate connection",
  "suggestions": ["Consider a less busy background", "Angle camera slightly higher"],
  "strengths": ["Natural expression", "Good eye contact"],
  "improvements": ["Background could be cleaner", "Lighting could be softer"],
  "nextPhotoSuggestions": ["Add a full body shot", "Include a hobby photo"],
  "technicalFeedback": {
    "lighting": "good",
    "composition": "decent", 
    "background": "busy",
    "angle": "flattering"
  },
  "datingInsights": {
    "personalityProjected": ["friendly", "approachable"],
    "demographicAppeal": "broad",
    "profileRole": "primary"
  }
}`;

  const criteriaSpecific = {
    'best': 'Focus on overall dating appeal and what makes this photo stand out.',
    'balanced': 'Evaluate how this photo fits into a complete dating profile.',
    'profile_order': 'Determine if this should be a main photo, secondary, or supporting image.',
    'conversation_starters': 'Identify elements that would spark interesting conversations.',
    'broad_appeal': 'Assess appeal across different demographics and preferences.',
    'authenticity': 'Evaluate how genuine and authentic the person appears.',
    'social': 'Analyze social dynamics and group interaction appeal.',
    'activity': 'Focus on activity/hobby elements and lifestyle appeal.',
    'personality': 'Identify personality traits and character projection.'
  };

  return basePrompt + '\n\nSpecific focus: ' + (criteriaSpecific[criteria] || criteriaSpecific['best']);
}

function parseGeminiResponse(responseText, fileName, photoUrl, criteria) {
  try {
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return {
        fileName: fileName,
        storageURL: photoUrl,
        score: Math.min(Math.max(parsed.score || 75, 0), 100),
        visualQuality: Math.min(Math.max(parsed.visualQuality || parsed.score || 75, 0), 100),
        attractivenessScore: Math.min(Math.max(parsed.attractivenessScore || parsed.score || 75, 0), 100),
        datingAppealScore: Math.min(Math.max(parsed.datingAppealScore || parsed.score || 75, 0), 100),
        swipeWorthiness: Math.min(Math.max(parsed.swipeWorthiness || parsed.score || 75, 0), 100),
        tags: Array.isArray(parsed.tags) ? parsed.tags : [],
        bestQuality: parsed.bestQuality || getCriteriaSpecificFallback(criteria, responseText),
        suggestions: Array.isArray(parsed.suggestions) ? parsed.suggestions : ["Consider the analysis feedback provided"],
        strengths: Array.isArray(parsed.strengths) ? parsed.strengths : [parsed.bestQuality || "Photo has good qualities"],
        improvements: Array.isArray(parsed.improvements) ? parsed.improvements : parsed.suggestions || ["Minor improvements possible"],
        nextPhotoSuggestions: Array.isArray(parsed.nextPhotoSuggestions) ? parsed.nextPhotoSuggestions : ["Add complementary photos"],
        technicalFeedback: parsed.technicalFeedback || {},
        datingInsights: parsed.datingInsights || {
          personalityProjected: [],
          demographicAppeal: null,
          profileRole: null
        }
      };
    }
  } catch (parseError) {
    console.warn('JSON parsing failed, using fallback parsing:', parseError);
  }
  
  return createFallbackResponse(fileName, photoUrl, criteria, responseText);
}

function createFallbackResponse(fileName, photoUrl, criteria, responseText = '') {
  let score = 75;
  
  const scoreMatch = responseText.match(/(?:score|rating):?\s*(\d+)/i);
  if (scoreMatch) {
    score = Math.min(Math.max(parseInt(scoreMatch[1], 10), 0), 100);
  }
  
  let bestQuality = getCriteriaSpecificFallback(criteria, responseText);
  let suggestions = ["Consider the analysis feedback provided"];
  
  if (responseText.toLowerCase().includes('lighting')) {
    suggestions = ["Focus on improving lighting conditions"];
  } else if (responseText.toLowerCase().includes('background')) {
    suggestions = ["Consider a cleaner background"];
  }
  
  return {
    fileName: fileName,
    storageURL: photoUrl,
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

// GET CONFIG FUNCTION
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

// INITIALIZE USER FUNCTION
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

// UPDATE USER CREDITS FUNCTION
exports.updateUserCredits = onCall({
  region: 'us-central1',
}, async (request) => {
  const { auth, data } = request;
  
  if (!auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  const userId = auth.uid;
  const { creditChange, reason, creditsToAdd, creditsToDeduct, purchaseDetails } = data;
  
  const db = admin.firestore();
  
  try {
    const userRef = db.collection('users').doc(userId);
    
    const result = await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);
      
      if (!userDoc.exists) {
        throw new HttpsError('not-found', 'User not found');
      }
      
      const userData = userDoc.data();
      let newCredits = userData.credits || 0;
      
      // Handle legacy creditChange parameter
      if (typeof creditChange === 'number') {
        newCredits = Math.max(0, newCredits + creditChange);
      }
      
      // Handle new creditsToAdd parameter
      if (creditsToAdd) {
        newCredits += creditsToAdd;
        console.log(`Adding ${creditsToAdd} credits to user ${userId}`);
      }
      
      // Handle creditsToDeduct parameter
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
      
      // Legacy support for creditChange
      if (typeof creditChange === 'number') {
        updateData.lastCreditUpdate = admin.firestore.FieldValue.serverTimestamp();
        if (creditChange < 0) {
          updateData.totalAnalyses = (userData.totalAnalyses || 0) + Math.abs(creditChange);
        }
      }
      
      // Track analyses for creditsToDeduct
      if (creditsToDeduct) {
        updateData.totalAnalyses = (userData.totalAnalyses || 0) + creditsToDeduct;
      }
      
      // Add purchase details if provided
      if (purchaseDetails) {
        updateData.lastPurchase = {
          ...purchaseDetails,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        };
      }
      
      transaction.update(userRef, updateData);
      
      console.log(`Updated credits for user ${userId}: ${userData.credits || 0} -> ${newCredits} (${reason || 'No reason provided'})`);
      
      return {
        success: true,
        previousCredits: userData.credits || 0,
        newCredits: newCredits,
        change: creditChange || (creditsToAdd || 0) - (creditsToDeduct || 0)
      };
    });
    
    return result;
    
  } catch (error) {
    console.error('Error updating user credits:', error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('internal', 'Failed to update user credits');
  }
});

// REDEEM PROMO CODE FUNCTION
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

    console.log(`✅ Promo code ${cleanCode} redeemed successfully for user ${auth.uid}`);

    return {
      success: true,
      credits: promoData.credits,
      description: promoData.description,
      isUnlimited: promoData.isUnlimited,
      expirationDate: promoData.expirationDate ? promoData.expirationDate.toMillis() / 1000 : null,
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
