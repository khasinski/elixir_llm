ExUnit.start()

# Configure ExVCR - uses default fixture/vcr_cassettes directory

# Match requests ignoring query parameters (so filtered keys still match)
ExVCR.Config.filter_url_params(true)

# Filter sensitive data from cassettes
# Bearer tokens in headers
ExVCR.Config.filter_sensitive_data("Bearer [^\"]+", "Bearer [FILTERED]")

# x-api-key header (Anthropic)
ExVCR.Config.filter_sensitive_data("x-api-key: [^\\r\\n]+", "x-api-key: [FILTERED]")

# Anthropic API key pattern
ExVCR.Config.filter_sensitive_data("sk-ant-[^\"]+", "[FILTERED_API_KEY]")

# OpenAI API key pattern
ExVCR.Config.filter_sensitive_data("sk-[A-Za-z0-9]+", "[FILTERED_API_KEY]")
