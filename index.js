// Firebase Cloud Functions for Photo Ranker App
// index.js

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const fetch = require('node-fetch');

admin.initializeApp();

// Initialize Gemini API
const genAI = new GoogleGenerativeAI(functions.config().gemini.api_key);

/**
 * Cloud Function to analyze photos using Gemini AI
 * 
 * This function receives photo URLs and ranking criteria,
 * then calls Gemini API to analyze them
 */
exports.analyzePhotos = functions.https.onCall(async (data, context) => {
  // Ensure user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication required'
    );
  }

  const { photoUrls, criteria } = data;
  
  if (!photoUrls || !Array.isArray(photoUrls) || photoUrls.length === 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Valid photo URLs array required'
    );
  }
  
  if (!criteria) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Ranking criteria required'
    );
  }
  
  try {
    // Process each photo
    const results = await Promise.all(
      photoUrls.map(url => analyzePhotoWithGemini(url, criteria))
    );
    
    // Save results to Firestore
    const sessionId = await saveResultsToFirestore(context.auth.uid, results, criteria);
    
    // Return results to client with session ID
    return {
      sessionId,
      results
    };
  } catch (error) {
    console.error('Error analyzing photos:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Analyze a single photo using Gemini API
 */
async function analyzePhotoWithGemini(photoUrl, criteria) {
  try {
    // Fetch the image and convert to base64
    const response = await fetch(photoUrl);
    const imageBuffer = await response.buffer();
    const base64Image = imageBuffer.toString('base64');
    
    // Set up the Gemini model
    const model = genAI.getGenerativeModel({ model: "gemini-pro-vision" });
    
    // Prepare prompt based on criteria
    const prompt = generatePromptForCriteria(criteria);
    
    // Create content parts with the image
    const imagePart = {
      inlineData: {
        data: base64Image,
        mimeType: "image/jpeg"
      }
    };
    
    // Call Gemini API
    const result = await model.generateContent([prompt, imagePart]);
    const aiResponse = await result.response;
    const responseText = await aiResponse.text();
    
    // Parse the response
    return parseGeminiResponse(responseText, photoUrl);
  } catch (error) {
    console.error(`Error analyzing image ${photoUrl}:`, error);
    throw error;
  }
}

/**
 * Generate appropriate prompt for Gemini based on selected criteria
 */
function generatePromptForCriteria(criteria) {
  switch (criteria) {
    case 'best':
      return "Analyze this photo for use in a dating profile. Rate it on a scale of 0-100 based on overall quality, composition, lighting, and how well it represents someone in a positive light. Provide the score and a brief explanation of strengths or weaknesses. Format your response as JSON with 'score' and 'feedback' fields.";
    
    case 'social':
      return "Analyze this photo for social context in a dating profile. Rate it on a scale of 0-100 based on how well it shows the person in social settings, with friends, or at social events. Determine if it's a social photo (true/false). Format your response as JSON with 'score', 'isSocial', and 'feedback' fields.";
    
    case 'activity':
      return "Analyze this photo for activities or hobbies in a dating profile. Rate it on a scale of 0-100 based on how well it shows the person engaged in activities, sports, or hobbies. Determine if it's an activity photo (true/false). Format your response as JSON with 'score', 'isActivity', and 'feedback' fields.";
    
    case 'personality':
      return "Analyze this photo for personality expression in a dating profile. Rate it on a scale of 0-100 based on how well it conveys personality traits, emotions, or character. Determine if it's a personality photo (true/false). Format your response as JSON with 'score', 'isPersonality', and 'feedback' fields.";
    
    case 'balanced':
      return "Analyze this photo for a balanced dating profile. Rate it on a scale of 0-100 based on overall quality. Also determine if it shows social context (with others), activities/hobbies, or personality expression. Format your response as JSON with 'score', 'isSocial', 'isActivity', 'isPersonality', and 'feedback' fields.";
    
    default:
      return "Analyze this photo for use in a dating profile. Rate it on a scale of 0-100 based on overall quality, composition, lighting, and appeal. Format your response as JSON with 'score' and 'feedback' fields.";
  }
}

/**
 * Parse Gemini's response text into a structured format
 */
function parseGeminiResponse(responseText, photoUrl) {
  try {
    // Try to parse JSON from the response
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const jsonResponse = JSON.parse(jsonMatch[0]);
      return {
        photoUrl,
        ...jsonResponse,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      };
    }
    
    // If JSON parsing fails, extract score manually
    const scoreMatch = responseText.match(/score:?\s*(\d+)/i);
    const score = scoreMatch ? parseInt(scoreMatch[1], 10) : 70; // Default to 70 if no score found
    
    // Look for boolean values
    const isSocial = /social:?\s*true/i.test(responseText);
    const isActivity = /activity:?\s*true/i.test(responseText);
    const isPersonality = /personality:?\s*true/i.test(responseText);
    
    // Extract feedback
    const feedbackMatch = responseText.match(/feedback:?\s*"([^"]*)"/i);
    const feedback = feedbackMatch ? feedbackMatch[1] : responseText.substring(0, 100);
    
    return {
      photoUrl,
      score,
      isSocial,
      isActivity,
      isPersonality,
      feedback,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    };
  } catch (error) {
    console.error('Error parsing Gemini response:', error);
    // Return a default response
    return {
      photoUrl,
      score: 70,
      feedback: "Unable to analyze this photo properly",
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    };
  }
}

/**
 * Save analysis results to Firestore for the user
 */
async function saveResultsToFirestore(userId, results, criteria) {
  const batch = admin.firestore().batch();
  
  // Create a new analysis session
  const sessionRef = admin.firestore().collection('users').doc(userId)
    .collection('analysisSessions').doc();
  
  batch.set(sessionRef, {
    criteria,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    photoCount: results.length
  });
  
  // Add each photo result
  results.forEach((result, index) => {
    const photoResultRef = sessionRef.collection('photoResults').doc();
    batch.set(photoResultRef, {
      ...result,
      rank: index + 1
    });
  });
  
  // Commit the batch
  await batch.commit();
  
  return sessionRef.id;
}

/**
 * Cloud Function to retrieve a user's analysis history
 */
exports.getAnalysisHistory = functions.https.onCall(async (data, context) => {
  // Ensure user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication required'
    );
  }
  
  const userId = context.auth.uid;
  const limit = data.limit || 10; // Default to 10 sessions
  
  try {
    const sessionsSnapshot = await admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('analysisSessions')
      .orderBy('timestamp', 'desc')
      .limit(limit)
      .get();
    
    const sessions = [];
    
    for (const doc of sessionsSnapshot.docs) {
      const sessionData = doc.data();
      
      // Get top 3 photos for the session preview
      const topPhotosSnapshot = await doc.ref
        .collection('photoResults')
        .orderBy('score', 'desc')
        .limit(3)
        .get();
      
      const topPhotos = topPhotosSnapshot.docs.map(photoDoc => photoDoc.data());
      
      sessions.push({
        id: doc.id,
        ...sessionData,
        topPhotos,
      });
    }
    
    return { sessions };
  } catch (error) {
    console.error('Error getting analysis history:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Cloud Function to retrieve a specific analysis session
 */
exports.getAnalysisSession = functions.https.onCall(async (data, context) => {
  // Ensure user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication required'
    );
  }
  
  const userId = context.auth.uid;
  const { sessionId } = data;
  
  if (!sessionId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Session ID required'
    );
  }
  
  try {
    // Get session data
    const sessionRef = admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('analysisSessions')
      .doc(sessionId);
    
    const sessionSnapshot = await sessionRef.get();
    
    if (!sessionSnapshot.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'Session not found'
      );
    }
    
    const sessionData = sessionSnapshot.data();
    
    // Get all photos for the session
    const photosSnapshot = await sessionRef
      .collection('photoResults')
      .orderBy('score', 'desc')
      .get();
    
    const photos = photosSnapshot.docs.map(doc => doc.data());
    
    return {
      session: {
        id: sessionSnapshot.id,
        ...sessionData,
        photos,
      }
    };
  } catch (error) {
    console.error('Error getting analysis session:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// Cloud Function to clean up old photos
exports.cleanupOldPhotos = functions.pubsub.schedule('every 24 hours').onRun(async (context) => {
  const storage = admin.storage();
  const bucket = storage.bucket();
  
  // Delete files older than 7 days
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 7);
  
  try {
    const [files] = await bucket.getFiles({ prefix: 'photos/' });
    
    for (const file of files) {
      const [metadata] = await file.getMetadata();
      const created = new Date(metadata.timeCreated);
      
      if (created < cutoff) {
        await file.delete();
        console.log(`Deleted old file: ${file.name}`);
      }
    }
    
    return null;
  } catch (error) {
    console.error('Error cleaning up old photos:', error);
    return null;
  }
});

/**
 * Cloud Function to initialize the app for a new user
 */
exports.initializeUserApp = functions.auth.user().onCreate(async (user) => {
  try {
    // Create user document in Firestore
    await admin.firestore().collection('users').doc(user.uid).set({
      email: user.email,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      totalSessions: 0,
      preferences: {
        defaultCriteria: 'best',
        darkMode: false,
        notificationsEnabled: true
      }
    });
    
    console.log(`Initialized app for user: ${user.uid}`);
    return null;
  } catch (error) {
    console.error('Error initializing user app:', error);
    return null;
  }
});

/**
 * Cloud Function to update user preferences
 */
exports.updateUserPreferences = functions.https.onCall(async (data, context) => {
  // Ensure user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication required'
    );
  }
  
  const userId = context.auth.uid;
  const { preferences } = data;
  
  if (!preferences || typeof preferences !== 'object') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Valid preferences object required'
    );
  }
  
  try {
    await admin.firestore()
      .collection('users')
      .doc(userId)
      .update({
        'preferences': preferences
      });
    
    return { success: true };
  } catch (error) {
    console.error('Error updating user preferences:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});
