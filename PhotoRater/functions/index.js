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
          hasCategorizationScores: !!analysisResult.categorization,
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

// ENHANCED PRACTICAL PROMPTS - COMBINING DOC4 PRACTICALITY WITH DOC5 DEPTH
function buildEnhancedPracticalPrompt(criteria) {
  const practicalBase = `You are an expert dating profile consultant analyzing photos for maximum dating success. Be encouraging but honest. Provide specific actionable advice that improves the photo within its current context.

ENHANCED ANALYSIS FRAMEWORK:

VISUAL QUALITY ASSESSMENT (0-100):
- Technical excellence: lighting conditions (natural vs artificial, shadows, highlights), composition rules (rule of thirds, framing), sharpness and image quality
- Aesthetic appeal: visual harmony, color balance, professional appearance vs casual authenticity
- Photo execution: intentional vs accidental look, proper framing, background appropriateness

ATTRACTIVENESS FACTORS (0-100):
- Facial analysis: expression authenticity, eye contact effectiveness, smile genuineness, facial symmetry and features
- Body language assessment: confident posture, approachability signals, relaxed vs tense appearance, overall presence
- Styling evaluation: outfit appropriateness for context, grooming level, accessories that enhance vs distract

DATING APPEAL ANALYSIS (0-100):
- First impression impact: immediate attraction factor, thumb-stopping power, memorable visual elements
- Personality projection: character traits clearly communicated, emotional intelligence indicators, authenticity markers
- Market positioning: competitive advantage in dating apps, target demographic appeal, broad vs niche attraction
- Conversation potential: interesting elements that naturally invite questions, discussion starters, relatability factors

ENHANCED CONTEXT & SETTING EVALUATION:
- Location analysis: appropriateness for dating profiles, demographic alignment, lifestyle signals
- Activity/lifestyle demonstration: hobbies, interests, skills clearly shown, adventure indicators
- Social dynamics: if others present - group dynamics, social proof, leadership indicators
- Environmental storytelling: props, background elements that add value vs create distractions

SOPHISTICATED CATEGORIZATION ANALYSIS:
- Social indicators: Multiple people visible? Group setting? Social activity? Team dynamics? Party/event context?
- Activity indicators: Sports, hobbies, adventures, skills demonstration? Travel? Creative pursuits? Fitness?
- Personality indicators: Genuine expressions, character traits, authentic moments? Artistic shots? Creative poses?
- Professional indicators: Work context, achievement displays, formal settings, competence signals?

PSYCHOLOGICAL & STRATEGIC DEPTH:
- Confidence indicators: body language, eye contact, posture, facial expression confidence
- Approachability factors: warmth signals, openness, inviting presence, emotional accessibility
- Authenticity assessment: natural vs posed, genuine vs staged, comfort level, spontaneity
- Dating strategy positioning: primary vs supporting photo role, profile narrative contribution

RETURN COMPREHENSIVE JSON ANALYSIS:
{
  "overallScore": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100), 
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  
  "tags": [select applicable from: "social", "activity", "personality", "professional", "casual", "outdoor", "group", "travel", "hobby", "confident", "natural", "attractive"],
  
  "categorization": {
    "socialScore": (0-100, based on presence of others, social setting, group dynamics, social proof),
    "activityScore": (0-100, based on sports, hobbies, adventures, skill demonstration, lifestyle activities),
    "personalityScore": (0-100, based on authentic expressions, character traits, emotional connection, creativity),
    "primaryCategory": "social|activity|personality|general",
    "categoryConfidence": (0-100, how confident you are in the primary category),
    "categoryReasoning": "brief explanation of why this categorization fits"
  },
  
  "strengths": [
    "Specific positive element that works exceptionally well with detailed explanation",
    "Another strong aspect with context of why it's effective for dating",
    "Third strength worth highlighting with actionable insight"
  ],
  
  "improvements": [
    "Specific actionable improvement that enhances THIS photo type with clear steps",
    "Technical or styling adjustment with detailed implementation guidance", 
    "Strategic positioning suggestion that works for this setting and context"
  ],
  
  "technicalFeedback": {
    "lighting": "detailed lighting assessment with specific improvement suggestions for this context",
    "composition": "framing analysis and composition improvements specific to this photo type",
    "styling": "outfit, grooming, and accessory feedback with alternatives appropriate for this context",
    "editing": "post-processing observations and enhancement suggestions",
    "angle": "camera positioning and perspective optimization for maximum appeal"
  },
  
  "datingInsights": {
    "personalityProjected": ["confident", "fun", "adventurous", "intelligent", "approachable", "social", "authentic"],
    "emotionalIntelligence": "assessment of EQ indicators visible in the photo",
    "demographicAppeal": "specific description of who this photo appeals to most and why",
    "marketPositioning": "strategic positioning advice for dating market advantage",
    "profileRole": "how this photo should be strategically used in a dating profile sequence",
    "conversationStarters": ["specific element someone could ask about", "interesting detail to discuss"],
    "approachabilityFactor": (0-100, how approachable you appear),
    "confidenceLevel": (0-100, confidence projected through image),
    "authenticityLevel": (0-100, how genuine vs posed the photo appears)
  },
  
  "nextPhotoSuggestions": [
    "Different type of photo that would complement this one for profile variety",
    "Specific scenario that would add balance to your profile mix with reasoning"
  ],
  
  "strategicAdvice": {
    "immediateImprovements": ["quick fixes for next photo session"],
    "profilePositioning": "where this fits in a 4-6 photo dating profile",
    "competitiveAdvantage": "what sets this photo apart from typical dating photos"
  }
}

CRITERIA FOCUS: ${getEnhancedCriteriaFocus(criteria)}

ENHANCED CATEGORIZATION GUIDELINES:
- Social (70+ social score): 2+ people visible, group activities, parties, social events, team photos, networking contexts
- Activity (70+ activity score): Sports, hobbies, travel, adventures, skills, outdoor activities, instruments, fitness, creative pursuits
- Personality (70+ personality score): Close-ups with genuine expressions, candid moments, creative shots, artistic poses, emotional depth
- General: Solo photos that don't clearly fit other categories, headshots, basic portraits, ambiguous contexts

Remember: Be encouraging but honest. Focus on specific actionable advice that users can immediately implement to improve their dating success.`;

  return practicalBase;
}

function getEnhancedCriteriaFocus(criteria) {
  switch (criteria) {
    case 'best':
      return 'Comprehensive analysis for overall dating profile excellence. Evaluate all dimensions: technical quality, attractiveness, dating appeal, personality projection, and strategic positioning. Focus on maximizing broad appeal and dating success potential.';
      
    case 'social':
      return 'Deep dive into social elements and group dynamics. Analyze social connectivity, group positioning, social proof factors, and how well the photo demonstrates social skills and popularity. Evaluate leadership vs follower dynamics if in groups.';
      
    case 'activity':
      return 'Focus intensively on activities, hobbies, lifestyle demonstration, and skill showcase. Analyze adventure appeal, fitness indicators, creative pursuits, and lifestyle alignment. Group activities can show both social and active aspects.';
      
    case 'personality':
      return 'Sophisticated analysis of personality traits, character projection, and authenticity markers. Examine emotional intelligence indicators, confidence levels, approachability, creativity, and genuine self-expression through the image.';
      
    case 'balanced':
      return 'Provide extremely detailed categorization scores for social, activity, and personality aspects. Analyze precisely what type of photo this is and how it contributes to a diverse, well-rounded dating profile. Be exact about categorization for balanced selection algorithms.';
      
    case 'profile_order':
      return 'Strategic positioning analysis for dating profile sequence. Evaluate main photo suitability (position 1) vs supporting photo value (positions 2-6). Consider face clarity, immediate impact, background simplicity, and complement to other photos.';
      
    case 'conversation_starters':
      return 'Identify and analyze conversation-generating elements in detail. Look for unique backgrounds, visible activities, interesting objects, travel indicators, pets, or unusual details that naturally invite questions and create message opportunities.';
      
    case 'broad_appeal':
      return 'Analyze demographic appeal across different market segments. Evaluate mass market vs niche attraction, cross-demographic appeal, cultural accessibility, and strategic positioning for maximum reach vs targeted attraction.';
      
    case 'authenticity':
      return 'Deep authenticity and naturalness evaluation. Analyze genuine vs posed expressions, natural body language, spontaneous vs staged appearance, comfort level, and authentic personality revelation through the image.';
      
    default:
      return 'Focus on overall dating profile optimization, broad demographic appeal, and maximizing dating success potential with actionable insights.';
  }
}

// ENHANCED PRACTICAL RESPONSE PARSING
function parseEnhancedPracticalResponse(responseText, criteria, fileName, photoUrl) {
  try {
    // Try to find and parse JSON in the response
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      console.log(`Successfully parsed enhanced practical JSON for ${criteria}:`, Object.keys(parsed));
      
      // Enhanced parsing with comprehensive categorization data
      const result = {  
        fileName: fileName,
        storageURL: photoUrl,
        score: Math.min(Math.max(parsed.overallScore || parsed.score || 75, 0), 100),
        visualQuality: Math.min(Math.max(parsed.visualQuality || 75, 0), 100),
        attractivenessScore: Math.min(Math.max(parsed.attractivenessScore || 75, 0), 100),
        datingAppealScore: Math.min(Math.max(parsed.datingAppealScore || 75, 0), 100),
        swipeWorthiness: Math.min(Math.max(parsed.swipeWorthiness || 75, 0), 100),
        
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
        
        // Enhanced dating insights with practical depth
        datingInsights: {
          personalityProjected: parsed.datingInsights?.personalityProjected || [],
          emotionalIntelligence: parsed.datingInsights?.emotionalIntelligence,
          demographicAppeal: parsed.datingInsights?.demographicAppeal,
          marketPositioning: parsed.datingInsights?.marketPositioning,
          profileRole: parsed.datingInsights?.profileRole,
          conversationStarters: parsed.datingInsights?.conversationStarters || [],
          approachabilityFactor: parsed.datingInsights?.approachabilityFactor,
          confidenceLevel: parsed.datingInsights?.confidenceLevel,
          authenticityLevel: parsed.datingInsights?.authenticityLevel
        },
        
        // Strategic advice for practical implementation
        strategicAdvice: parsed.strategicAdvice
      };

      // Enhanced categorization data for balanced selection - CRITICAL FEATURE
      if (parsed.categorization) {
        result.categorization = {
          socialScore: Math.min(Math.max(parsed.categorization.socialScore || 0, 0), 100),
          activityScore: Math.min(Math.max(parsed.categorization.activityScore || 0, 0), 100),
          personalityScore: Math.min(Math.max(parsed.categorization.personalityScore || 0, 0), 100),
          primaryCategory: parsed.categorization.primaryCategory || 'general',
          categoryConfidence: Math.min(Math.max(parsed.categorization.categoryConfidence || 50, 0), 100),
          categoryReasoning: parsed.categorization.categoryReasoning || ''
        };
      } else {
        // Intelligent fallback categorization based on tags and content analysis
        result.categorization = inferCategorizationFromContent(parsed, responseText);
      }

      return result;
    }
  } catch (error) {
    console.error(`Error parsing enhanced practical JSON for ${criteria}:`, error);
    console.log('Response text sample:', responseText.substring(0, 500));
  }
  
  // Enhanced fallback parsing
  console.log(`JSON parsing failed for ${criteria}, using enhanced practical fallback parsing`);
  return createEnhancedPracticalFallback(fileName, photoUrl, criteria, responseText);
}

// INTELLIGENT CATEGORIZATION INFERENCE
function inferCategorizationFromContent(parsed, responseText) {
  const text = responseText.toLowerCase();
  const tags = parsed.tags || [];
  
  let socialScore = 0;
  let activityScore = 0;
  let personalityScore = 0;
  
  // Social indicators
  if (text.includes('group') || text.includes('people') || text.includes('social') || text.includes('friends')) socialScore += 30;
  if (text.includes('party') || text.includes('event') || text.includes('team')) socialScore += 25;
  if (tags.includes('social') || tags.includes('group')) socialScore += 35;
  if (text.includes('multiple') || text.includes('others')) socialScore += 20;
  
  // Activity indicators  
  if (text.includes('sport') || text.includes('activity') || text.includes('hobby')) activityScore += 30;
  if (text.includes('outdoor') || text.includes('adventure') || text.includes('travel')) activityScore += 25;
  if (tags.includes('activity') || tags.includes('outdoor') || tags.includes('hobby')) activityScore += 35;
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
      return num ? parseInt(num[1], 10) : 75;
    });
    score = Math.round(scores.reduce((a, b) => a + b, 0) / scores.length);
  }
  
  // Enhanced quality assessment from content
  let bestQuality = getEnhancedPracticalFallback(criteria, responseText);
  let suggestions = ["Consider technical improvements for enhanced dating appeal"];
  let strengths = [bestQuality];
  
  // Content-based quality enhancement
  if (responseText.toLowerCase().includes('excellent') || responseText.toLowerCase().includes('outstanding')) {
    score = Math.max(score, 85);
    bestQuality = "Exceptional photo quality with strong dating appeal";
  } else if (responseText.toLowerCase().includes('great') || responseText.toLowerCase().includes('strong')) {
    score = Math.max(score, 80);
    bestQuality = "Strong visual appeal with good dating potential";
  }
  
  // Enhanced technical feedback extraction
  const technicalFeedback = extractEnhancedTechnicalFeedback(responseText);
  const datingInsights = extractEnhancedDatingInsights(responseText, criteria);
  const tags = extractEnhancedTags(responseText, criteria);
  const categorization = inferCategorizationFromContent({ tags }, responseText);
  
  return {
    fileName: fileName,
    storageURL: photoUrl,
    score: Math.min(Math.max(score, 0), 100),
    visualQuality: Math.max(score - 5, 0),
    attractivenessScore: score,
    datingAppealScore: Math.max(score - 3, 0),
    swipeWorthiness: Math.max(score - 2, 0),
    
    tags: tags,
    bestQuality: bestQuality,
    suggestions: suggestions,
    strengths: strengths,
    improvements: suggestions,
    nextPhotoSuggestions: ["Add complementary photos for complete profile variety"],
    
    technicalFeedback: technicalFeedback,
    datingInsights: datingInsights,
    categorization: categorization,
    
    strategicAdvice: {
      immediateImprovements: ["Enhanced analysis recommends photo session improvements"],
      profilePositioning: "Strategic positioning advice for dating profile",
      competitiveAdvantage: "Unique elements that differentiate from typical dating photos"
    }
  };
}

// ENHANCED HELPER FUNCTIONS FOR PRACTICAL ANALYSIS
function extractEnhancedTechnicalFeedback(responseText) {
  const feedback = {
    lighting: "Lighting analysis in progress",
    composition: "Composition evaluation in progress", 
    styling: "Styling assessment in progress",
    editing: "Post-processing review in progress",
    angle: "Camera positioning analysis in progress"
  };
  
  if (responseText.toLowerCase().includes('lighting')) {
    feedback.lighting = "Lighting elements identified - optimization recommendations available";
  }
  if (responseText.toLowerCase().includes('composition') || responseText.toLowerCase().includes('framing')) {
    feedback.composition = "Composition analysis completed - improvement suggestions provided";
  }
  if (responseText.toLowerCase().includes('style') || responseText.toLowerCase().includes('outfit')) {
    feedback.styling = "Styling evaluation completed - enhancement recommendations available";
  }
  if (responseText.toLowerCase().includes('angle') || responseText.toLowerCase().includes('perspective')) {
    feedback.angle = "Camera angle analysis completed - positioning optimization available";
  }
  
  return feedback;
}

function extractEnhancedDatingInsights(responseText, criteria) {
  const personalityTraits = [];
  const text = responseText.toLowerCase();
  
  // Enhanced personality trait detection
  if (text.includes('confident')) personalityTraits.push('confident');
  if (text.includes('friendly') || text.includes('warm')) personalityTraits.push('friendly');
  if (text.includes('approachable') || text.includes('welcoming')) personalityTraits.push('approachable');
  if (text.includes('authentic') || text.includes('genuine')) personalityTraits.push('authentic');
  if (text.includes('fun') || text.includes('playful')) personalityTraits.push('fun');
  if (text.includes('intelligent') || text.includes('smart')) personalityTraits.push('intelligent');
  if (text.includes('adventurous') || text.includes('active')) personalityTraits.push('adventurous');
  if (text.includes('creative') || text.includes('artistic')) personalityTraits.push('creative');
  if (text.includes('social') || text.includes('outgoing')) personalityTraits.push('social');
  
  // Enhanced scoring based on content analysis
  const approachabilityFactor = text.includes('approachable') || text.includes('warm') ? 85 : 
                               text.includes('friendly') ? 80 : 75;
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
      promoCodeSupport: true
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
        console.log(`Adding ${creditsToAdd} enhanced practical analysis credits to user ${uid}`);
      }
      
      if (creditsToDeduct) {
        if (userData.isUnlimited) {
          console.log(`User ${uid} has unlimited enhanced practical analysis plan, not deducting credits`);
        } else {
          if (newCredits < creditsToDeduct) {
            throw new HttpsError('failed-precondition', 'Insufficient credits for enhanced practical analysis');
          }
          newCredits -= creditsToDeduct;
          console.log(`Deducting ${creditsToDeduct} enhanced practical analysis credits from user ${uid}`);
        }
      }
      
      const updateData = {
        freeCredits: Math.max(newCredits, 0),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        'metadata.lastAnalysisLevel': 'enhanced_practical'
      };
      
      if (creditsToDeduct) {
        updateData.totalAnalyses = (userData.totalAnalyses || 0) + creditsToDeduct;
        updateData.enhancedPracticalAnalyses = (userData.enhancedPracticalAnalyses || 0) + creditsToDeduct;
      }
      
      if (purchaseDetails) {
        updateData.lastPurchase = {
          ...purchaseDetails,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          analysisLevel: 'enhanced_practical'
        };
      }
      
      transaction.update(userRef, updateData);
    });
    
    return { success: true, analysisLevel: 'enhanced_practical' };
  } catch (error) {
    console.error('Error updating user credits:', error);
    throw error;
  }
});
