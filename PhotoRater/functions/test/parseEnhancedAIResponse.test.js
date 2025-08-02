const test = require('node:test');
const assert = require('node:assert');
const { parseEnhancedAIResponse } = require('../index.js');

test('keeps zero scores instead of defaulting', () => {
  const responseText = JSON.stringify({
    score: 0,
    visualQuality: 0,
    attractivenessScore: 0,
    datingAppealScore: 0,
    swipeWorthiness: 0
  });
  const result = parseEnhancedAIResponse(responseText, 'best', 'photo_0', '');
  assert.strictEqual(result.score, 0);
  assert.strictEqual(result.visualQuality, 0);
  assert.strictEqual(result.attractivenessScore, 0);
  assert.strictEqual(result.datingAppealScore, 0);
  assert.strictEqual(result.swipeWorthiness, 0);
});
