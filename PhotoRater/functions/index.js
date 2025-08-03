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

    console.log(`Starting sophisticated photo analysis with criteria: ${criteria} for ${photos.length} photos`);

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
          return await analyzeImageWithAdvancedGemini(photoData, criteria, model, index);
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
        processingVersion: '3.1.0',
        analysisDepth: 'professional'
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

// ADVANCED IMAGE ANALYSIS WITH SOPHISTICATED GEMINI PROMPTS
async function analyzeImageWithAdvancedGemini(photoData, criteria, model, index) {
  const timeout = 45000; // 45 second timeout for detailed analysis

  return Promise.race([
    performAdvancedAnalysis(photoData, criteria, model, index),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Advanced analysis timeout')), timeout)
    )
  ]);
}

async function performAdvancedAnalysis(photoData, criteria, model, index) {
  try {
    console.log(`Processing photo ${index} with sophisticated ${criteria} analysis`);

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
    const prompt = buildSophisticatedAnalysisPrompt(criteria);

    console.log(`Analyzing image with sophisticated ${criteria} prompt (${prompt.length} chars)`);

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
        console.log(`Raw sophisticated AI response for ${criteria} (${text.length} chars)`);

        const analysisResult = parseAdvancedAIResponse(text, criteria, `photo_${index}`, '');
        console.log(`Parsed sophisticated ${criteria} analysis:`, {
          score: analysisResult.score,
          detailedScores: analysisResult.detailedScores,
          hasStrengths: analysisResult.strengths?.length > 0,
          hasPersonalityInsights: analysisResult.datingInsights?.personalityProjected?.length > 0
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
    console.error(`Advanced analysis failed for photo ${index}:`, error);

    if (error.message.includes('too small') || error.message.includes('too large')) {
      return createRejectedResponse(`photo_${index}`, '', error.message);
    }

    return createFallbackResponse(`photo_${index}`, '', criteria, error.message);
  }
}

// SOPHISTICATED ANALYSIS PROMPTS - PROFESSIONAL DATING CONSULTANT LEVEL
function buildSophisticatedAnalysisPrompt(criteria) {
  const sophisticatedBase = `You are a world-class dating profile consultant and image analyst with expertise in psychology, fashion, photography, and social dynamics. Provide an incredibly detailed, nuanced analysis that goes beyond surface-level observations.

ANALYSIS FRAMEWORK:
1. Technical Excellence: Lighting, composition, angles, image quality
2. Aesthetic Appeal: Attractiveness factors, styling, visual harmony
3. Psychological Impact: Personality projection, emotional response, trustworthiness
4. Dating Strategy: Market positioning, demographic appeal, conversation potential
5. Social Dynamics: Confidence indicators, approachability, social proof

RETURN VALID JSON WITH COMPREHENSIVE DATA - NO TEXT OUTSIDE JSON.`;

  switch (criteria) {
    case 'best':
      return `${sophisticatedBase}

COMPREHENSIVE EXCELLENCE ANALYSIS:

Analyze this photo across ALL dimensions of dating profile success:

TECHNICAL ASSESSMENT:
- Lighting quality and direction (natural vs artificial, shadows, highlights)
- Composition and framing (rule of thirds, background, focus)
- Image quality (sharpness, resolution, editing quality)
- Angle and perspective (most flattering angles, camera height)

ATTRACTIVENESS EVALUATION:
- Facial features and expression analysis
- Body language and posture assessment
- Styling and fashion choices
- Overall visual appeal and aesthetic harmony

DATING MARKET ANALYSIS:
- Mass market appeal vs niche attractiveness
- Target demographic analysis
- Competitive advantage in dating apps
- First impression impact

PSYCHOLOGICAL PROFILING:
- Personality traits projected through image
- Emotional intelligence indicators
- Confidence and authenticity levels
- Approachability and warmth factors

STRATEGIC POSITIONING:
- Primary vs secondary photo suitability
- Profile role and positioning strategy
- Conversation starter potential
- Long-term relationship vs casual appeal

{
  "score": (0-100, overall excellence rating),
  "detailedScores": {
    "technicalQuality": (0-100),
    "visualAppeal": (0-100),
    "attractiveness": (0-100),
    "personalityProjection": (0-100),
    "datingMarketValue": (0-100),
    "conversationPotential": (0-100),
    "authenticityLevel": (0-100),
    "approachabilityFactor": (0-100)
  },
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["multiple", "relevant", "descriptive", "tags"],
  "strengths": [
    "specific technical strength with details",
    "attractiveness factor with explanation",
    "personality trait clearly visible",
    "strategic advantage for dating",
    "unique appeal factor"
  ],
  "improvements": [
    "specific technical improvement with steps",
    "styling enhancement with details",
    "angle or pose adjustment suggestion",
    "background or setting improvement",
    "overall strategy enhancement"
  ],
  "bestQuality": "the single most compelling aspect of this photo",
  "suggestions": [
    "immediate actionable improvement",
    "medium-term strategy suggestion",
    "long-term profile development advice"
  ],
  "nextPhotoSuggestions": [
    "specific complementary photo type needed",
    "activity or setting recommendation",
    "style or mood variation suggested"
  ],
  "technicalFeedback": {
    "lighting": "detailed lighting analysis and improvement suggestions",
    "composition": "composition strengths/weaknesses and specific improvements",
    "styling": "outfit, grooming, and accessory feedback with alternatives",
    "editing": "post-processing observations and suggestions",
    "equipment": "camera angle, distance, and technical recommendations"
  },
  "datingInsights": {
    "personalityProjected": [
      "confident", "approachable", "intelligent", "creative", "adventurous"
    ],
    "emotionalIntelligence": "assessment of EQ indicators in photo",
    "demographicAppeal": "primary target demographic analysis",
    "marketPositioning": "dating market positioning strategy",
    "relationshipType": "casual vs serious relationship appeal",
    "conversationStarters": [
      "specific element someone could ask about",
      "interesting background detail to discuss",
      "hobby or interest visible in photo"
    ],
    "psychologicalImpact": "deeper analysis of psychological response this photo evokes",
    "profileRole": "strategic role this photo should play in dating profile"
  },
  "competitiveAnalysis": {
    "uniqueSellingPoints": ["what sets this photo apart from typical dating photos"],
    "marketAdvantages": ["strengths in competitive dating environment"],
    "differentiationFactors": ["elements that make you memorable"]
  },
  "improvementStrategy": {
    "immediateChanges": ["quick fixes for next photo session"],
    "mediumTermGoals": ["style or presentation improvements to work on"],
    "longTermStrategy": ["overall dating profile and personal brand development"]
  }
}`;

    case 'profile_order':
      return `${sophisticatedBase}

STRATEGIC PROFILE POSITIONING ANALYSIS:

Analyze optimal positioning in dating profile sequence (photos 1-6):

MAIN PHOTO CRITERIA (Position 1):
- Face visibility and clarity (70%+ of frame)
- Immediate attractiveness and appeal
- Simple, non-distracting background
- Confident, approachable expression
- High technical quality

SUPPORTING PHOTO ANALYSIS (Positions 2-6):
- Complementary value to main photo
- Variety and personality demonstration
- Social proof and lifestyle indicators
- Activity and interest showcases
- Full-body and different angle options

SEQUENCING STRATEGY:
- Profile flow and narrative development
- Psychological impact progression
- Conversation starter distribution
- Appeal to different user preferences

{
  "score": (0-100, positioning effectiveness),
  "position": "1" | "2" | "3" | "4" | "5" | "6" | "skip",
  "positionReason": "detailed strategic explanation for recommended position",
  "mainPhotoSuitability": (0-100),
  "supportingPhotoValue": (0-100),
  "faceClarity": (0-100),
  "backgroundComplexity": (0-100, lower is better),
  "immediateImpact": (0-100),
  "complementaryValue": (0-100),
  "positioningAdvice": "specific strategic positioning guidance",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["main_photo", "supporting", "social_proof", "activity", "personality"],
  "strengths": [
    "positioning strength with explanation",
    "profile sequence advantage",
    "unique positioning value"
  ],
  "improvements": [
    "positioning strategy enhancement",
    "profile flow improvement",
    "sequencing optimization"
  ],
  "nextPhotoSuggestions": [
    "specific photo type needed to complement this one",
    "gap in profile narrative to fill",
    "variety enhancement recommendation"
  ],
  "technicalFeedback": {
    "lighting": "lighting assessment for profile positioning",
    "composition": "composition effectiveness for chosen position",
    "styling": "styling appropriateness for position"
  },
  "datingInsights": {
    "personalityProjected": ["traits shown in this positioning context"],
    "profileRole": "specific strategic role in profile sequence",
    "narrativeContribution": "how this photo advances your dating story"
  },
  "positioningStrategy": {
    "primaryAppeal": "main attraction factor for this position",
    "targetTiming": "when in profile viewing this photo impacts most",
    "psychologicalImpact": "mental impression created at this position",
    "competitiveAdvantage": "positioning advantage over typical profiles"
  }
}`;

    case 'conversation_starters':
      return `${sophisticatedBase}

CONVERSATION CATALYST ANALYSIS:

Evaluate conversation-generating potential and message hooks:

CONVERSATION ELEMENTS IDENTIFICATION:
- Unique background locations and settings
- Visible activities, hobbies, and interests
- Travel destinations and cultural elements
- Pets, objects, and personal items
- Professional or creative indicators
- Unusual or intriguing details

MESSAGE HOOK ANALYSIS:
- Easy conversation openers
- Question-generating elements
- Shared interest potential
- Story-telling opportunities
- Compliment-worthy aspects

ENGAGEMENT STRATEGY:
- Immediate conversation starters
- Deeper conversation development
- Personality reveal opportunities
- Connection building elements

{
  "score": (0-100, conversation generation potential),
  "conversationElements": [
    "specific visible element with conversation potential",
    "background detail that invites questions",
    "activity or hobby clearly shown",
    "travel or location indicator",
    "interesting object or accessory"
  ],
  "messageHooks": [
    "natural conversation opener someone could use",
    "question this photo naturally invites",
    "compliment opportunity this photo provides",
    "shared experience connection point",
    "story or experience inquiry hook"
  ],
  "conversationAdvice": "strategic guidance for leveraging this photo in conversations",
  "engagementPotential": (0-100),
  "questionGenerationScore": (0-100),
  "relatabilityFactor": (0-100),
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["conversation", "engaging", "interesting", "relatable", "discussion"],
  "strengths": [
    "specific conversation strength with example",
    "engagement factor that works well",
    "relatable element that connects"
  ],
  "improvements": [
    "how to add more conversation elements",
    "enhancement for better engagement",
    "strategy for increased relatability"
  ],
  "nextPhotoSuggestions": [
    "complementary photo type for conversation variety",
    "activity photo to add discussion points",
    "setting that creates different conversation opportunities"
  ],
  "technicalFeedback": {
    "lighting": "lighting impact on conversation element visibility",
    "composition": "composition effectiveness for highlighting interesting elements",
    "styling": "styling choices that add conversation value"
  },
  "datingInsights": {
    "personalityProjected": ["traits revealed through conversation elements"],
    "profileRole": "conversation starter specialist role",
    "connectionFactors": ["elements that help build rapport"]
  },
  "conversationStrategy": {
    "immediateOpeners": ["first message possibilities this photo creates"],
    "conversationDevelopment": ["how conversations could naturally evolve"],
    "personalityReveal": ["aspects of personality this photo helps reveal"],
    "connectionBuilding": ["how this photo facilitates deeper connection"]
  }
}`;

    case 'broad_appeal':
      return `${sophisticatedBase}

DEMOGRAPHIC APPEAL ANALYSIS:

Evaluate appeal across different demographics and market segments:

MASS MARKET ANALYSIS:
- Universal attractiveness factors
- Cross-demographic appeal elements
- Cultural and social accessibility
- Age range appeal assessment
- Geographic and lifestyle compatibility

NICHE VS BROAD APPEAL:
- Specific demographic targeting
- Unique attraction factors
- Trade-offs between broad and targeted appeal
- Market positioning implications

TARGET DEMOGRAPHIC EVALUATION:
- Primary demographic attraction
- Secondary market appeal
- Lifestyle and value alignment
- Professional and social compatibility

{
  "score": (0-100, broad demographic appeal),
  "appealBreadth": "broad" | "moderate" | "niche",
  "massMarketScore": (0-100),
  "nicheAppealScore": (0-100),
  "universalFactors": (0-100),
  "targetDemographics": [
    "primary demographic with details",
    "secondary demographic appeal",
    "tertiary market segment"
  ],
  "appealStrategy": "strategic advice for optimizing demographic appeal",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["broad_appeal", "universal", "accessible", "mainstream", "diverse"],
  "strengths": [
    "universal appeal factor with explanation",
    "cross-demographic strength",
    "mass market advantage"
  ],
  "improvements": [
    "how to broaden appeal without losing authenticity",
    "demographic expansion strategy",
    "market positioning enhancement"
  ],
  "nextPhotoSuggestions": [
    "photo type to appeal to different demographics",
    "setting or activity for broader appeal",
    "style variation for market expansion"
  ],
  "technicalFeedback": {
    "lighting": "lighting choices impact on broad appeal",
    "composition": "composition effectiveness across demographics",
    "styling": "styling choices for maximum appeal breadth"
  },
  "datingInsights": {
    "personalityProjected": ["universally appealing personality traits"],
    "demographicAppeal": "detailed breakdown of who this attracts most",
    "profileRole": "strategic positioning for broad market appeal"
  },
  "marketAnalysis": {
    "competitiveAdvantages": ["advantages in broad dating market"],
    "appealOptimization": ["strategies for maintaining broad appeal"],
    "demographicBalance": ["how to balance broad vs targeted appeal"],
    "marketPositioning": ["optimal positioning strategy for maximum reach"]
  }
}`;

    case 'authenticity':
      return `${sophisticatedBase}

AUTHENTICITY AND NATURALNESS ANALYSIS:

Evaluate genuine personality expression and natural appeal:

AUTHENTICITY INDICATORS:
- Natural vs posed expression analysis
- Genuine emotion and body language
- Spontaneous vs staged appearance
- Personality authenticity assessment
- Comfortable vs forced presentation

NATURALNESS EVALUATION:
- Candid moment capture quality
- Relaxed and comfortable appearance
- Genuine smile and expression
- Natural posture and positioning
- Unforced styling and presentation

PERSONALITY REVELATION:
- True character showing through
- Authentic interest and passion display
- Natural confidence indicators
- Genuine warmth and approachability
- Real lifestyle representation

{
  "score": (0-100, overall authenticity rating),
  "authenticityLevel": "completely_natural" | "mostly_natural" | "somewhat_posed" | "clearly_staged",
  "naturalness": (0-100),
  "genuineness": (0-100),
  "spontaneityLevel": (0-100),
  "comfortLevel": (0-100),
  "genuinenessFactors": "detailed analysis of what makes this feel genuine or not",
  "authenticityAdvice": "specific guidance for appearing more authentic",
  "personalityTraits": [
    "authentic personality trait clearly visible",
    "genuine character aspect shown",
    "natural behavioral indicator",
    "honest self-expression element"
  ],
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["authentic", "natural", "genuine", "real", "unposed"],
  "strengths": [
    "specific authenticity strength with evidence",
    "natural appeal factor",
    "genuine personality trait visible"
  ],
  "improvements": [
    "how to enhance natural expression",
    "authenticity improvement strategy",
    "natural confidence building approach"
  ],
  "nextPhotoSuggestions": [
    "setting for more natural expression",
    "activity that reveals authentic personality",
    "context for genuine self-expression"
  ],
  "technicalFeedback": {
    "lighting": "lighting contribution to natural appearance",
    "composition": "composition impact on authenticity perception",
    "styling": "styling authenticity and natural fit"
  },
  "datingInsights": {
    "personalityProjected": ["authentic personality traits clearly visible"],
    "profileRole": "authenticity anchor for dating profile",
    "connectionPotential": "how authenticity facilitates genuine connections"
  },
  "authenticityAnalysis": {
    "genuineElements": ["specific elements that feel completely authentic"],
    "naturalAdvantages": ["benefits of authentic presentation"],
    "trustworthiness": ["factors that build trust through authenticity"],
    "realPersonality": ["aspects of real personality successfully conveyed"]
  }
}`;

    case 'balanced':
      return `${sophisticatedBase}

PROFILE BALANCE AND VARIETY ANALYSIS:

Analyze photo categorization for balanced profile creation:

PHOTO TYPE CLASSIFICATION:
- Social context and proof indicators
- Activity and hobby demonstration
- Personality and character expression
- Professional and lifestyle elements
- Physical and aesthetic components

BALANCE CONTRIBUTION:
- Profile variety enhancement
- Narrative development support
- Multi-dimensional personality show
- Different context representation
- Comprehensive self-presentation

STRATEGIC ROLE ASSESSMENT:
- Primary profile function
- Supporting narrative element
- Variety and diversity contribution
- Target audience expansion
- Complete picture development

{
  "score": (0-100, overall contribution to balanced profile),
  "profileBalanceScore": (0-100),
  "varietyContribution": (0-100),
  "narrativeDevelopment": (0-100),
  "isSocial": true | false,
  "isActivity": true | false,
  "isPersonality": true | false,
  "isProfessional": true | false,
  "isLifestyle": true | false,
  "profileRole": "primary_attraction" | "social_proof" | "activity_showcase" | "personality_highlight" | "lifestyle_indicator" | "professional_display",
  "balanceAnalysis": "detailed analysis of how this photo contributes to profile balance",
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["balanced", "variety", "comprehensive", "multi-dimensional"],
  "strengths": [
    "specific balance contribution strength",
    "variety enhancement factor",
    "narrative development advantage"
  ],
  "improvements": [
    "balance optimization suggestion",
    "variety enhancement opportunity",
    "profile completion recommendation"
  ],
  "nextPhotoSuggestions": [
    "complementary photo type for better balance",
    "missing profile element to address",
    "variety enhancement opportunity"
  ],
  "technicalFeedback": {
    "lighting": "lighting appropriateness for photo type",
    "composition": "composition effectiveness for intended role",
    "styling": "styling fit for profile category"
  },
  "datingInsights": {
    "personalityProjected": ["traits shown in this context"],
    "profileRole": "specific strategic role in balanced profile presentation",
    "narrativeContribution": "how this photo advances complete self-presentation"
  },
  "balanceStrategy": {
    "profileCompleteness": ["what this photo adds to complete picture"],
    "varietyOptimization": ["how to use this for maximum profile variety"],
    "narrativeCoherence": ["how this fits into overall dating narrative"],
    "targetAudienceExpansion": ["demographics this photo helps reach"]
  }
}`;

    default:
      return `${sophisticatedBase}

COMPREHENSIVE PROFESSIONAL DATING ANALYSIS:

Conduct the most thorough analysis possible across all dimensions:

{
  "score": (0-100, overall excellence),
  "detailedScores": {
    "technicalQuality": (0-100),
    "visualAppeal": (0-100),
    "attractiveness": (0-100),
    "personalityProjection": (0-100),
    "datingMarketValue": (0-100),
    "conversationPotential": (0-100),
    "authenticityLevel": (0-100),
    "approachabilityFactor": (0-100)
  },
  "visualQuality": (0-100),
  "attractivenessScore": (0-100),
  "datingAppealScore": (0-100),
  "swipeWorthiness": (0-100),
  "tags": ["comprehensive", "professional", "detailed", "strategic"],
  "strengths": ["strength 1", "strength 2", "strength 3"],
  "improvements": ["improvement 1", "improvement 2"],
  "bestQuality": "the most compelling aspect",
  "suggestions": ["suggestion 1", "suggestion 2"],
  "nextPhotoSuggestions": ["complementary photo 1", "complementary photo 2"],
  "technicalFeedback": {
    "lighting": "detailed analysis",
    "composition": "comprehensive feedback",
    "styling": "complete assessment"
  },
  "datingInsights": {
    "personalityProjected": ["trait1", "trait2", "trait3"],
    "demographicAppeal": "target demographic",
    "profileRole": "strategic role"
  }
}`;
  }
}

// ADVANCED AI RESPONSE PARSING
function parseAdvancedAIResponse(responseText, criteria, fileName, photoUrl) {
  try {
    // More sophisticated JSON extraction
    let jsonMatch = responseText.match(/\{[\s\S]*\}/);
    
    // Try multiple JSON extraction methods
    if (!jsonMatch) {
      const lines = responseText.split('\n');
      const jsonLines = lines.filter(line => line.trim().startsWith('{') || line.includes('"score"'));
      if (jsonLines.length > 0) {
        jsonMatch = [jsonLines.join('\n')];
      }
    }
    
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      console.log(`Successfully parsed sophisticated JSON for ${criteria}:`, Object.keys(parsed));
      
      // Enhanced response structure with all sophisticated features
      return {
        fileName: fileName,
        storageURL: photoUrl,
        score: Math.min(Math.max(parsed.score ?? 75, 0), 100),
        
        // Detailed scoring system
        detailedScores: parsed.detailedScores || {
          technicalQuality: parsed.technicalQuality ?? parsed.visualQuality ?? parsed.score ?? 75,
          visualAppeal: parsed.visualAppeal ?? parsed.attractivenessScore ?? parsed.score ?? 75,
          attractiveness: parsed.attractiveness ?? parsed.attractivenessScore ?? parsed.score ?? 75,
          personalityProjection: parsed.personalityProjection ?? parsed.score ?? 75,
          datingMarketValue: parsed.datingMarketValue ?? parsed.datingAppealScore ?? parsed.score ?? 75,
          conversationPotential: parsed.conversationPotential ?? parsed.engagementPotential ?? parsed.score ?? 75,
          authenticityLevel: parsed.authenticityLevel ?? parsed.naturalness ?? parsed.score ?? 75,
          approachabilityFactor: parsed.approachabilityFactor ?? parsed.score ?? 75
        },
        
        // Standard scores
        visualQuality: Math.min(Math.max(parsed.visualQuality ?? parsed.score ?? 75, 0), 100),
        attractivenessScore: Math.min(Math.max(parsed.attractivenessScore ?? parsed.score ?? 75, 0), 100),
        datingAppealScore: Math.min(Math.max(parsed.datingAppealScore ?? parsed.score ?? 75, 0), 100),
        swipeWorthiness: Math.min(Math.max(parsed.swipeWorthiness ?? parsed.score ?? 75, 0), 100),
        
        // Enhanced content fields
        tags: Array.isArray(parsed.tags) ? parsed.tags : [],
        bestQuality: parsed.bestQuality || (Array.isArray(parsed.strengths) && parsed.strengths.length > 0 ? parsed.strengths[0] : "High quality photo"),
        suggestions: Array.isArray(parsed.suggestions) ? parsed.suggestions : (Array.isArray(parsed.improvements) ? parsed.improvements : ["Excellent photo quality"]),
        
        // Comprehensive feedback arrays
        strengths: Array.isArray(parsed.strengths) ? parsed.strengths : [],
        improvements: Array.isArray(parsed.improvements) ? parsed.improvements : [],
        nextPhotoSuggestions: Array.isArray(parsed.nextPhotoSuggestions) ? parsed.nextPhotoSuggestions : [],
        
        // Enhanced technical feedback
        technicalFeedback: parsed.technicalFeedback || {},
        
        // Sophisticated dating insights
        datingInsights: {
          personalityProjected: parsed.datingInsights?.personalityProjected || parsed.personalityTraits || [],
          emotionalIntelligence: parsed.datingInsights?.emotionalIntelligence,
          demographicAppeal: parsed.datingInsights?.demographicAppeal || parsed.demographicAppeal,
          marketPositioning: parsed.datingInsights?.marketPositioning,
          relationshipType: parsed.datingInsights?.relationshipType,
          conversationStarters: parsed.datingInsights?.conversationStarters || parsed.conversationElements || [],
          psychologicalImpact: parsed.datingInsights?.psychologicalImpact,
          profileRole: parsed.datingInsights?.profileRole || parsed.profileRole
        },
        
        // Advanced analysis fields
        competitiveAnalysis: parsed.competitiveAnalysis,
        improvementStrategy: parsed.improvementStrategy,
        positioningStrategy: parsed.positioningStrategy,
        conversationStrategy: parsed.conversationStrategy,
        marketAnalysis: parsed.marketAnalysis,
        authenticityAnalysis: parsed.authenticityAnalysis,
        balanceStrategy: parsed.balanceStrategy,
        
        // Criteria-specific fields (preserved from original)
        position: parsed.position,
        positionReason: parsed.positionReason,
        faceClarity: parsed.faceClarity,
        backgroundComplexity: parsed.backgroundComplexity,
        positioningAdvice: parsed.positioningAdvice,
        mainPhotoSuitability: parsed.mainPhotoSuitability,
        supportingPhotoValue: parsed.supportingPhotoValue,
        immediateImpact: parsed.immediateImpact,
        complementaryValue: parsed.complementaryValue,
        
        conversationElements: parsed.conversationElements,
        messageHooks: parsed.messageHooks,
        conversationAdvice: parsed.conversationAdvice,
        engagementPotential: parsed.engagementPotential,
        questionGenerationScore: parsed.questionGenerationScore,
        relatabilityFactor: parsed.relatabilityFactor,
        
        appealBreadth: parsed.appealBreadth,
        targetDemographics: parsed.targetDemographics,
        appealStrategy: parsed.appealStrategy,
        massMarketScore: parsed.massMarketScore,
        nicheAppealScore: parsed.nicheAppealScore,
        universalFactors: parsed.universalFactors,
        
        authenticityLevel: parsed.authenticityLevel,
        genuinenessFactors: parsed.genuinenessFactors,
        authenticityAdvice: parsed.authenticityAdvice,
        naturalness: parsed.naturalness,
        genuineness: parsed.genuineness,
        spontaneityLevel: parsed.spontaneityLevel,
        comfortLevel: parsed.comfortLevel,
        personalityTraits: parsed.personalityTraits,
        
        isSocial: parsed.isSocial,
        isActivity: parsed.isActivity,
        isPersonality: parsed.isPersonality,
        isProfessional: parsed.isProfessional,
        isLifestyle: parsed.isLifestyle,
        profileBalanceScore: parsed.profileBalanceScore,
        varietyContribution: parsed.varietyContribution,
        narrativeDevelopment: parsed.narrativeDevelopment,
        balanceAnalysis: parsed.balanceAnalysis
      };
    }
  } catch (error) {
    console.error(`Error parsing sophisticated JSON for ${criteria}:`, error);
    console.log('Response text sample:', responseText.substring(0, 1000));
  }
  
  // Enhanced fallback parsing with more sophistication
  console.log(`JSON parsing failed for ${criteria}, using sophisticated fallback parsing`);
  return createSophisticatedFallbackResponse(fileName, photoUrl, criteria, responseText);
}

// SOPHISTICATED FALLBACK RESPONSES
function createSophisticatedFallbackResponse(fileName, photoUrl, criteria, responseText = '') {
  let score = 75;
  
  // Enhanced score detection
  const scoreMatches = responseText.match(/(?:score|rating|quality):?\s*(\d+)/gi);
  if (scoreMatches && scoreMatches.length > 0) {
    const scores = scoreMatches.map(match => {
      const num = match.match(/(\d+)/);
      return num ? parseInt(num[1], 10) : 75;
    });
    score = Math.round(scores.reduce((a, b) => a + b, 0) / scores.length);
  }
  
  // Sophisticated quality assessment from text
  let bestQuality = getSophisticatedFallback(criteria, responseText);
  let suggestions = ["Professional analysis recommends technical improvements"];
  let strengths = [bestQuality];
  let improvements = suggestions;
  
  // Enhanced content analysis
  if (responseText.toLowerCase().includes('excellent') || responseText.toLowerCase().includes('outstanding')) {
    score = Math.max(score, 85);
    bestQuality = "Exceptional photo quality with professional appeal";
  } else if (responseText.toLowerCase().includes('great') || responseText.toLowerCase().includes('strong')) {
    score = Math.max(score, 80);
    bestQuality = "Strong visual appeal with good technical execution";
  }
  
  // Sophisticated technical feedback extraction
  const technicalFeedback = extractTechnicalFeedback(responseText);
  const datingInsights = extractDatingInsights(responseText, criteria);
  const tags = extractSophisticatedTags(responseText, criteria);
  
  return {
    fileName: fileName,
    storageURL: photoUrl,
    score: Math.min(Math.max(score, 0), 100),
    
    detailedScores: {
      technicalQuality: Math.max(score - 5, 0),
      visualAppeal: score,
      attractiveness: Math.max(score - 3, 0),
      personalityProjection: Math.max(score - 7, 0),
      datingMarketValue: Math.max(score - 2, 0),
      conversationPotential: Math.max(score - 10, 0),
      authenticityLevel: Math.max(score - 5, 0),
      approachabilityFactor: Math.max(score - 4, 0)
    },
    
    visualQuality: Math.max(score - 5, 0),
    attractivenessScore: score,
    datingAppealScore: Math.max(score - 3, 0),
    swipeWorthiness: Math.max(score - 2, 0),
    
    tags: tags,
    bestQuality: bestQuality,
    suggestions: suggestions,
    strengths: strengths,
    improvements: improvements,
    nextPhotoSuggestions: ["Add complementary photos for complete profile presentation"],
    
    technicalFeedback: technicalFeedback,
    datingInsights: datingInsights,
    
    // Initialize all possible fields to prevent errors
    competitiveAnalysis: null,
    improvementStrategy: null,
    positioningStrategy: null,
    conversationStrategy: null,
    marketAnalysis: null,
    authenticityAnalysis: null,
    balanceStrategy: null
  };
}

// Helper functions for sophisticated fallback parsing
function extractTechnicalFeedback(responseText) {
  return {
    lighting: responseText.toLowerCase().includes('lighting') ? "Lighting analysis available" : "Consider lighting optimization",
    composition: responseText.toLowerCase().includes('composition') ? "Composition feedback provided" : "Focus on composition improvement",
    styling: responseText.toLowerCase().includes('style') || responseText.toLowerCase().includes('outfit') ? "Styling guidance included" : "Enhance styling choices"
  };
}

function extractDatingInsights(responseText, criteria) {
  const personalityTraits = [];
  if (responseText.toLowerCase().includes('confident')) personalityTraits.push('confident');
  if (responseText.toLowerCase().includes('friendly')) personalityTraits.push('friendly');
  if (responseText.toLowerCase().includes('approachable')) personalityTraits.push('approachable');
  if (responseText.toLowerCase().includes('authentic')) personalityTraits.push('authentic');
  
  return {
    personalityProjected: personalityTraits,
    emotionalIntelligence: null,
    demographicAppeal: "Analysis in progress",
    marketPositioning: null,
    relationshipType: null,
    conversationStarters: [],
    psychologicalImpact: null,
    profileRole: getSophisticatedProfileRole(criteria)
  };
}

function extractSophisticatedTags(responseText, criteria) {
  const tags = [];
  const text = responseText.toLowerCase();
  
  if (text.includes('professional')) tags.push('professional');
  if (text.includes('casual')) tags.push('casual');
  if (text.includes('social')) tags.push('social');
  if (text.includes('activity')) tags.push('activity');
  if (text.includes('personality')) tags.push('personality');
  if (text.includes('attractive')) tags.push('attractive');
  if (text.includes('natural')) tags.push('natural');
  if (text.includes('confident')) tags.push('confident');
  
  return tags.length > 0 ? tags : ['analyzed', 'processed'];
}

function getSophisticatedFallback(criteria, responseText) {
  const qualityIndicators = {
    'profile_order': "Photo analyzed for strategic profile positioning",
    'conversation_starters': "Photo evaluated for conversation engagement potential",
    'broad_appeal': "Photo assessed for demographic market appeal",
    'authenticity': "Photo reviewed for authentic personality expression",
    'balanced': "Photo categorized for balanced profile creation",
    'best': "Comprehensive professional analysis completed"
  };
  
  return qualityIndicators[criteria] || "Professional photo analysis completed";
}

function getSophisticatedProfileRole(criteria) {
  const roles = {
    'profile_order': 'Strategic positioning specialist',
    'conversation_starters': 'Conversation catalyst',
    'broad_appeal': 'Mass market appeal driver',
    'authenticity': 'Authentic personality showcase',
    'balanced': 'Profile balance contributor',
    'best': 'Primary attraction element'
  };
  
  return roles[criteria] || 'Dating profile enhancement';
}

function createFallbackResponse(fileName, photoUrl, criteria, errorMessage) {
  return {
    fileName: fileName,
    storageURL: photoUrl,
    score: 70,
    detailedScores: {
      technicalQuality: 65,
      visualAppeal: 70,
      attractiveness: 70,
      personalityProjection: 65,
      datingMarketValue: 68,
      conversationPotential: 60,
      authenticityLevel: 67,
      approachabilityFactor: 68
    },
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
    technicalFeedback: {},
    datingInsights: {
      personalityProjected: [],
      profileRole: "Processing"
    }
  };
}

function createRejectedResponse(fileName, photoUrl, reason) {
  return {
    fileName: fileName,
    storageURL: photoUrl,
    score: 0,
    detailedScores: {
      technicalQuality: 0,
      visualAppeal: 0,
      attractiveness: 0,
      personalityProjection: 0,
      datingMarketValue: 0,
      conversationPotential: 0,
      authenticityLevel: 0,
      approachabilityFactor: 0
    },
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
    version: '3.1.0',
    features: {
      sophisticatedAnalysis: true,
      professionalConsultation: true,
      detailedScoring: true,
      psychologicalInsights: true,
      marketPositioning: true,
      competitiveAnalysis: true,
      strategicGuidance: true,
      personalityAssessment: true,
      technicalExpertise: true,
      datingMarketAnalysis: true,
      conversationOptimization: true,
      authenticityEvaluation: true,
      profileBalancing: true,
      enhancedImageProcessing: true,
      contentSafety: true,
      base64Processing: true,
      promoCodeSupport: true
    },
    analysisDepth: 'world_class_consultant_level'
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
          analysisDepth: 'professional',
          notifications: true
        },
        metadata: {
          signupPeriod: inLaunchPeriod ? 'launch' : 'standard',
          version: '3.1.0',
          analysisLevel: 'sophisticated'
        }
      });
      
      console.log(`Initialized new user: ${uid} with ${startingCredits} free credits`);
      return { 
        success: true, 
        newUser: true, 
        freeCredits: startingCredits,
        isLaunchPeriod: inLaunchPeriod,
        analysisLevel: 'sophisticated'
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
        analysisLevel: 'sophisticated'
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
      description: 'Unlimited Access - Professional Consultant Level',
      isUnlimited: true,
      expirationDate: new Date(new Date().setFullYear(new Date().getFullYear() + 2)),
      maxUses: 10,
    },
    'LAUNCH50': {
      credits: 50,
      description: 'Launch Special - 50 Professional Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 100,
    },
    'BETA20': {
      credits: 20,
      description: 'Beta Tester - 20 Sophisticated Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 50,
    },
    'FRIEND10': {
      credits: 10,
      description: 'Friend Referral - 10 Expert Analyses',
      isUnlimited: false,
      expirationDate: new Date('2025-12-31'),
      maxUses: 500,
    },
    'PREMIUM100': {
      credits: 100,
      description: 'Premium Package - 100 World-Class Analyses',
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
        analysisLevel: 'sophisticated'
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
        'metadata.analysisLevel': 'sophisticated'
      };

      transaction.set(userRef, updateData, { merge: true });
    });

    console.log(`User ${uid} redeemed sophisticated promo code ${code} for ${details.credits} credits`);
    
    return { 
      success: true, 
      promo: { 
        credits: details.credits, 
        isUnlimited: details.isUnlimited,
        description: details.description,
        analysisLevel: 'sophisticated'
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
        console.log(`Adding ${creditsToAdd} sophisticated analysis credits to user ${uid}`);
      }
      
      if (creditsToDeduct) {
        if (userData.isUnlimited) {
          console.log(`User ${uid} has unlimited sophisticated analysis plan, not deducting credits`);
        } else {
          if (newCredits < creditsToDeduct) {
            throw new HttpsError('failed-precondition', 'Insufficient credits for sophisticated analysis');
          }
          newCredits -= creditsToDeduct;
          console.log(`Deducting ${creditsToDeduct} sophisticated analysis credits from user ${uid}`);
        }
      }
      
      const updateData = {
        freeCredits: Math.max(newCredits, 0),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        'metadata.lastAnalysisLevel': 'sophisticated'
      };
      
      if (creditsToDeduct) {
        updateData.totalAnalyses = (userData.totalAnalyses || 0) + creditsToDeduct;
        updateData.sophisticatedAnalyses = (userData.sophisticatedAnalyses || 0) + creditsToDeduct;
      }
      
      if (purchaseDetails) {
        updateData.lastPurchase = {
          ...purchaseDetails,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          analysisLevel: 'sophisticated'
        };
      }
      
      transaction.update(userRef, updateData);
    });
    
    return { success: true, analysisLevel: 'sophisticated' };
  } catch (error) {
    console.error('Error updating user credits:', error);
    throw error;
  }
});
