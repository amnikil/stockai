class ClaudeService
  CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"

  # Prompt that tells Claude exactly what analysis to perform
  ANALYSIS_PROMPT = <<~PROMPT
    You are a professional stock market analyst with 15 years of experience.
    Analyze this stock chart image and provide a comprehensive investment analysis.

    Structure your response with these exact sections:

    ## 1. Stock Identification
    - Company name and ticker symbol (if visible)
    - Exchange (NSE/BSE/NYSE etc.)
    - Current price visible on chart

    ## 2. Technical Analysis
    - Price trend: Bullish / Bearish / Sideways
    - Key support levels (price points where stock bounced up)
    - Key resistance levels (price points where stock got stuck)
    - Moving averages visible (50 DMA, 200 DMA)
    - Volume trend (increasing/decreasing)
    - Any technical patterns (Head & Shoulders, Triangle, Flag etc.)

    ## 3. Indicators (if visible)
    - RSI reading and what it means
    - MACD signal
    - Any other indicators

    ## 4. Fundamental Checklist
    List the key fundamentals an investor MUST verify before investing:
    - P/E ratio (check if reasonable for sector)
    - Revenue growth (last 4 quarters)
    - Profit margins
    - Debt-to-equity ratio
    - Promoter holding percentage
    - Institutional holding
    - Free cash flow

    ## 5. Risk Assessment
    Risk Level: HIGH / MEDIUM / LOW
    Explain why in 2-3 sentences.

    ## 6. Investment Recommendation
    Decision: ✅ BUY / ⚠️ HOLD / ❌ SELL / 🔍 NEEDS MORE RESEARCH

    Short-term outlook (1-3 months):
    Long-term outlook (1-3 years):

    Reasoning: (3-4 sentences explaining your recommendation)

    ## 7. Important Disclaimer
    This is AI-generated technical analysis for educational purposes only.
    Always consult a SEBI-registered financial advisor before investing.
  PROMPT

  def self.analyze_stock(image_base64, media_type)
    response = HTTParty.post(
      CLAUDE_API_URL,
      headers: {
        'x-api-key'         => ENV.fetch('ANTHROPIC_API_KEY'),
        'anthropic-version' => '2023-06-01',
        'Content-Type'      => 'application/json'
      },
      body: {
        model:      'claude-opus-4-5',
        max_tokens: 2048,
        messages: [{
          role:    'user',
          content: [
            {
              type:   'image',
              source: {
                type:       'base64',
                media_type: media_type,
                data:       image_base64
              }
            },
            { type: 'text', text: ANALYSIS_PROMPT }
          ]
        }]
      }.to_json,
      timeout: 60
    )

    case response.code
    when 200
      data = JSON.parse(response.body)
      { success: true, analysis: data['content'][0]['text'] }
    when 401
      { success: false, error: 'Invalid Anthropic API key. Check your ANTHROPIC_API_KEY secret.' }
    when 429
      { success: false, error: 'AI rate limit reached. Wait 1 minute and try again.' }
    else
      { success: false, error: "AI API error #{response.code}: #{response.body}" }
    end
  rescue Net::ReadTimeout
    { success: false, error: 'AI analysis timed out. Try with a smaller image.' }
  rescue => e
    { success: false, error: "Unexpected error: #{e.message}" }
  end
end
