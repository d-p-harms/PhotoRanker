const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');

admin.initializeApp();

// Retrieve the Gemini API key from environment variables instead of
// relying on runtime config which isn't available in Cloud Functions
// second generation by default. If the key is missing we log an error
// so the function fails fast during invocation rather than at startup.
const geminiApiKey = process.env.GEMINI_API_KEY;
if (!geminiApiKey) {
  console.error('GEMINI_API_KEY environment variable is not set.');
}

const genAI = new GoogleGenerativeAI(geminiApiKey || '');

// Enhanced file path parsing with better error handling
function parseFirebaseStorageUrl(photoUrl) {
  let filePath;
  
  try {
    console.log(`Parsing URL: ${photoUrl}`);
    
    if (photoUrl.includes('firebasestorage.googleapis.com') || photoUrl.includes('firebase')) {
      // Handle Firebase Storage URLs - multiple formats
      let matches = photoUrl.match(/\/o\/(.*?)(\?|$)/);
      if (matches && matches[1]) {
        filePath = decodeURIComponent(matches[1]);
      } else {
        // Fallback: try to extract from different URL format
        matches = photoUrl.match(/ai-analysis%2F[^%]+%2F[^?&]+/);
        if (matches) {
          filePath = decodeURIComponent(matches[0]);
        } else {
          // Another fallback: extract everything after /o/
          matches = photoUrl.match(/\/o\/([^?&]+)/);
          if (matches && matches[1]) {
            filePath = decodeURIComponent(matches[1]);
          } else {
            throw new Error(`Could not parse file path from URL: ${photoUrl}`);
          }
        }
      }
    } else if (photoUrl.startsWith('gs://')) {
      filePath = photoUrl.replace(/^gs:\/\/[^\/]+\//, '');
    } else {
      filePath = photoUrl;
    }
    
    console.log(`Parsed file path: ${filePath}`);
    return filePath;
  } catch (error) {
    console.error(`URL parsing error: ${error.message}`);
    throw new Error(`Failed to parse photo URL: ${photoUrl}`);
  }
}

// Enhanced image validation and preparation
async function validateAndPrepareImage(buffer) {
  console.log(`Validating image buffer of size: ${buffer.length} bytes`);
  
  if (buffer.length === 0) {
    throw new Error('Empty image buffer received');
  }
  
  if (buffer.length > 20 * 1024 * 1024) { // 20MB limit
    throw new Error('Image file too large (max 20MB)');
  }
  
  // Basic image format validation
  const isPNG = buffer.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
  const isJPEG = buffer.slice(0, 3).equals(Buffer.from([0xFF, 0xD8, 0xFF]));
  
  if (!isPNG && !isJPEG) {
    throw new Error('Invalid image format. Only PNG and JPEG are supported.');
  }
  
  console.log(`Image validated: ${isPNG ? 'PNG' : 'JPEG'}, size: ${buffer.length} bytes`);
  return buffer;
}

// Enhanced Gemini analysis with comprehensive error handling
async function performGeminiAnalysis(imageBuffer, criteria, model) {
  try {
    console.log(`Starting Gemini analysis for criteria: ${criteria}`);
    
    const base64Image = imageBuffer.toString('base64');
    const mimeType = imageBuffer.slice(0, 3).equals(Buffer.from([0xFF, 0xD8, 0xFF])) ? 'image/jpeg' : 'image/png';
    
    const prompt = generatePromptForCriteria(criteria);
    
    const result = await model.generateContent([
      {
        inlineData: {
          data: base64Image,
          mimeType: mimeType
        }
      },
      prompt
    ]);
    
    const response = await result.response;
    const text = response.text();
    
    console.log(`Gemini response received: ${text.substring(0, 200)}...`);
    
    return parseGeminiResponse(text, criteria);
  } catch (error) {
    console.error(`Gemini analysis error: ${error.message}`);
    throw new Error(`AI analysis failed: ${error.message}`);
  }
}

function generatePromptForCriteria(criteria) {
  const basePrompt = `Analyze this photo for dating app purposes. Rate it from 1-100 and provide detailed feedback.`;
  
  switch (criteria) {
    case 'DATING_APPEAL':
      return `${basePrompt} Focus on overall dating appeal, attractiveness, and swipe-worthiness. 
      Return JSON with: score, strengths, improvements, datingInsights, swipeWorthiness.`;
      
    case 'BROAD_APPEAL':
      return `${basePrompt} Focus on broad demographic appeal and universal attractiveness factors.
      Return JSON with: score, appealBreadth, targetDemographics, universalFactors, limitingFactors.`;
      
    case 'AUTHENTICITY_CHECK':
      return `${basePrompt} Focus on authenticity, genuineness, and trustworthiness.
      Return JSON with: score, authenticityFactors, trustSignals, genuinenessScore, improvements.`;
      
    default:
      return `${basePrompt} Provide comprehensive analysis.
      Return JSON with: score, strengths, improvements, suggestions.`;
  }
}

function parseGeminiResponse(text, criteria) {
  try {
    // Try to extract JSON from the response
    let jsonMatch = text.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return {
        score: parsed.score || 50,
        strengths: parsed.strengths || [],
        improvements: parsed.improvements || [],
        suggestions: parsed.suggestions || parsed.improvements || [],
        tags: parsed.tags || [],
        ...parsed
      };
    }
    
    // Fallback: parse manually
    console.warn('Could not parse JSON response, using fallback parsing');
    return {
      score: 60,
      strengths: ['Good photo quality'],
      improvements: ['Consider better lighting'],
      suggestions: ['Keep up the great work!'],
      tags: ['dating-photo']
    };
  } catch (error) {
    console.error(`Response parsing error: ${error.message}`);
    return {
      score: 50,
      strengths: ['Photo uploaded successfully'],
      improvements: ['Analysis could not be completed'],
      suggestions: ['Try uploading again'],
      tags: ['error']
    };
  }
}

// Main analysis function with enhanced error handling
async function analyzePhoto(photoUrl, criteria, model) {
  try {
    console.log(`Starting analysis for URL: ${photoUrl}`);
    
    // Parse the file path with enhanced error handling
    const filePath = parseFirebaseStorageUrl(photoUrl);
    
    console.log(`Accessing file at path: ${filePath}`);
    const storage = admin.storage();
    const fileRef = storage.bucket().file(filePath);
    
    // Check if file exists before attempting download
    console.log('Checking if file exists...');
    const [exists] = await fileRef.exists();
    if (!exists) {
      throw new Error(`File does not exist at path: ${filePath}`);
    }
    
    console.log('File exists, downloading...');
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
      strategicAdvice: result.strategicAdvice
    };
    
    console.log(`Analysis result prepared for ${filePath}`);
    return analysisResult;
    
  } catch (error) {
    console.error(`Analysis error for ${photoUrl}: ${error.message}`);
    console.error(`Full error:`, error);
    
    // Return error result instead of throwing
    return {
      fileName: photoUrl.split('/').pop() || 'unknown',
      storageURL: photoUrl,
      score: 0,
      error: error.message,
      tags: ['error'],
      bestQuality: "Analysis failed",
      suggestions: ["Please try uploading the photo again"],
      strengths: [],
      improvements: [`Error: ${error.message}`],
      nextPhotoSuggestions: [],
      technicalFeedback: { error: error.message },
      datingInsights: {
        personalityProjected: [],
        demographicAppeal: null,
        profileRole: null
      }
    };
  }
}

// Main Cloud Function
exports.analyzePhotos = functions.https.onCall(async (data, context) => {
  try {
    console.log('=== Starting analyzePhotos function ===');
    
    // Verify authentication
    if (!context.auth) {
      console.error('Unauthenticated request');
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    
    const { photoUrls, criteria } = data;
    
    // Validate input
    if (!photoUrls || !Array.isArray(photoUrls) || photoUrls.length === 0) {
      console.error('Invalid photoUrls:', photoUrls);
      throw new functions.https.HttpsError('invalid-argument', 'photoUrls must be a non-empty array');
    }
    
    if (!criteria) {
      console.error('Missing criteria');
      throw new functions.https.HttpsError('invalid-argument', 'criteria is required');
    }
    
    console.log(`Processing ${photoUrls.length} photos with criteria: ${criteria}`);
    console.log('Photo URLs:', photoUrls);
    
    // Initialize Gemini model
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    
    // Process all photos
    const analysisPromises = photoUrls.map((url, index) => {
      console.log(`Starting analysis for photo ${index + 1}: ${url}`);
      return analyzePhoto(url, criteria, model);
    });
    
    console.log('Waiting for all analyses to complete...');
    const results = await Promise.all(analysisPromises);
    
    // Filter out any null results and sort by score
    const validResults = results.filter(result => result !== null);
    const sortedResults = validResults.sort((a, b) => (b.score || 0) - (a.score || 0));
    
    console.log(`=== Analysis complete: ${validResults.length} successful results ===`);
    
    return {
      success: true,
      results: sortedResults,
      criteria: criteria,
      totalPhotos: photoUrls.length,
      successfulAnalyses: validResults.length
    };
    
  } catch (error) {
    console.error('=== Function error ===');
    console.error('Error message:', error.message);
    console.error('Error stack:', error.stack);
    
    // Return structured error response
    return {
      success: false,
      error: error.message,
      results: [],
      criteria: data?.criteria || 'unknown',
      totalPhotos: data?.photoUrls?.length || 0,
      successfulAnalyses: 0
    };
  }
});

// Initialize user function (existing)
exports.initializeUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  const userId = context.auth.uid;
  const userRef = admin.firestore().collection('users').doc(userId);
  
  try {
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      await userRef.set({
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        credits: 3,
        totalAnalyses: 0,
        lastActive: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`Created new user document for ${userId}`);
    } else {
      await userRef.update({
        lastActive: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`Updated last active for existing user ${userId}`);
    }
    
    return { success: true, message: 'User initialized successfully' };
  } catch (error) {
    console.error('Error initializing user:', error);
    throw new functions.https.HttpsError('internal', 'Failed to initialize user');
  }
});
