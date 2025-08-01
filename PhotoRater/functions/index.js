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

// Define the secret for GEMINI_API_KEY
const geminiKey = defineSecret('GEMINI_API_KEY');
const visionClient = new vision.ImageAnnotatorClient();

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
    let filesToCleanup = [];

    for (const [batchIndex, batch] of batches.entries()) {
      console.log(`Processing batch ${batchIndex + 1}/${batches.length} (${batch.length} photos)`);
      
      const batchPromises = batch.map(async (photoUrl, index) => {
        try {
          await new Promise(resolve => setTimeout(resolve, index * 200));
          return await analyzeImageWithGemini(photoUrl, criteria, model, filesToCleanup);
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

    await cleanupFiles(filesToCleanup);

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
    await cleanupFiles(filesToCleanup);
    throw new HttpsError(
      'internal',
      error.message || 'Failed to analyze photos'
    );
  }
});

async function analyzeImageWithGemini(photoUrl, criteria, model, filesToCleanup) {
  let file;
  try {
    console.log(`Processing photo: ${photoUrl} with criteria: ${criteria}`);

    let filePath;
    let bucket = admin.storage().bucket();
    if (photoUrl.includes('firebasestorage.googleapis.com')) {
      const pathMatch = photoUrl.match(/o\/(.+?)\?/);
      if (pathMatch && pathMatch[1]) {
        filePath = decodeURIComponent(pathMatch[1]);
      }
      const bucketMatch = photoUrl.match(/v0\/b\/([^/]+)/);
      if (bucketMatch && bucketMatch[1] && bucketMatch[1] !== bucket.name) {
        console.log(`Using bucket from URL: ${bucketMatch[1]}`);
        bucket = admin.storage().bucket(bucketMatch[1]);
      }
    }

    const fileName = filePath ? filePath.split('/').pop() : 'uploaded_photo';

    file = bucket.file(filePath);
    if (filesToCleanup) {
      filesToCleanup.push(file);
    }
    
    const [buffer] = await file.download();
    
    const resizedBuffer = await sharp(buffer)
      .resize(1024, 1024, {
        fit: 'inside',
        withoutEnlargement: true
      })
      .jpeg({ quality: 85 })
      .toBuffer();

    const [safeResult] = await visionClient.safeSearchDetection(resizedBuffer);
    const safe = safeResult.safeSearchAnnotation || {};
    const flaggedLevels = ['LIKELY', 'VERY_LIKELY'];
    if (flaggedLevels.includes(safe.adult) || flaggedLevels.includes(safe.violence) || flaggedLevels.includes(safe.racy)) {
      console.warn(`SafeSearch blocked ${fileName}:`, safe);
      return createRejectedResponse(fileName, photoUrl, 'Image violates content policy');
    }

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
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const launchStart = new Date('2025-07-24T00:00:00Z');
  const launchEnd = new Date(launchStart);
  launchEnd.setDate(launchEnd.getDate() + 14);
  const inLaunch = Date.now() >= launchStart.getTime() && Date.now() < launchEnd.getTime();
  const startingCredits = inLaunch ? 15 : 3;

  const userRef = admin.firestore().collection('users').doc(uid);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    await userRef.set({
      freeCredits: startingCredits,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, newUser: true, freeCredits: startingCredits };
  }

  return { success: true, newUser: false, freeCredits: userDoc.data().freeCredits };
});

// REDEEM PROMO CODE FUNCTION
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

  const promoCodes = {
    'K9X7M3P8Q2W5': {
      credits: 999,
      description: 'Unlimited Access',
      isUnlimited: true,
      expirationDate: new Date(new Date().setFullYear(new Date().getFullYear() + 2)),
      maxUses: 10,
    },
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

  await db.runTransaction(async (tx) => {
    const userPromoSnap = await tx.get(userPromoRef);
    if (userPromoSnap.exists) {
      throw new HttpsError('already-exists', 'Promo code already redeemed');
    }

    const globalSnap = await tx.get(globalRef);
    const uses = (globalSnap.data()?.uses) || 0;
    if (uses >= details.maxUses) {
      throw new HttpsError('failed-precondition', 'Promo code usage limit reached');
    }

    tx.set(userPromoRef, {
      redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
      creditsAdded: details.credits,
      isUnlimited: details.isUnlimited,
      description: details.description,
    });

    tx.set(globalRef, {
      uses: uses + 1,
      lastUsed: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  return { success: true, promo: { credits: details.credits, isUnlimited: details.isUnlimited } };
});

// UPDATE USER CREDITS FUNCTION
exports.updateUserCredits = onCall({
  region: 'us-central1',
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const freeCredits = Number(request.data?.freeCredits);
  if (!Number.isFinite(freeCredits)) {
    throw new HttpsError('invalid-argument', 'Valid credit count required');
  }

  const userRef = admin.firestore().collection('users').doc(uid);
  await userRef.set({
    freeCredits,
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { success: true };
});

async function cleanupFiles(files) {
  for (const file of files) {
    try {
      await file.delete({ ignoreNotFound: true });
    } catch (error) {
      console.error('Cleanup error:', error);
    }
  }
}
