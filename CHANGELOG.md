# Changelog

All notable changes to ElixirLLM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- AWS Bedrock provider
- Parallel tool execution
- Audio input/output support
- Token counting utilities
- Cost estimation

---

## [0.3.0] - 2026-01-21

### Added

#### New Provider
- **OpenRouter** - Access 100+ models via unified API with `openrouter/` prefix

#### Testing Infrastructure
- **ExVCR integration** - HTTP recording for deterministic tests without API keys
- **VCR tests** - 10 cassette-based tests for OpenAI, Anthropic, and Gemini
- **API key filtering** - Automatic removal of sensitive data from cassettes

#### Gemini Models
- **Gemini 2.5 series** - `gemini-2.5-pro-preview-05-06`, `gemini-2.5-flash-preview-05-20`
- **Gemini 2.0 nano** - `gemini-2.0-flash-lite` for lowest latency

### Changed
- **Provider architecture** - Extracted shared logic into `ElixirLLM.Providers.Base`
- **Streaming implementation** - Refactored for Req 0.5.x compatibility using process dictionary pattern
- **Code deduplication** - Reduced provider code by ~40% through shared helpers

### Fixed
- **Streaming bug** - Fixed `{:fold, acc, fun}` format not supported in Req 0.5.x
- **Dialyzer warnings** - Added `:mix` to PLT for Mix.Task analysis

---

## [0.2.0] - 2026-01-20

### Added

#### New Providers
- **Google Gemini** - `gemini-2.0-flash`, `gemini-1.5-pro`, `gemini-1.5-flash` support
- **Mistral AI** - Direct API support for `mistral-large`, `codestral`, etc.
- **Groq** - Ultra-fast LPU inference with `llama-3.3-70b-versatile`, `llama4-scout`
- **Together AI** - 100+ open models via `together/` prefix

#### Resilience Features
- **Retry mechanism** - `ElixirLLM.Retry` with exponential backoff, configurable attempts, jitter
- **Rate limiting** - `ElixirLLM.RateLimiter` with token bucket algorithm per provider
- **Circuit breaker** - `ElixirLLM.CircuitBreaker` with closed/open/half-open states
- **Response caching** - `ElixirLLM.Cache` with TTL and LRU eviction

#### Error Handling
- **Structured errors** - 9 custom exception types for different failure modes
- **Error classification** - `retryable?/1` to identify transient vs permanent failures
- **Error conversion** - `from_response/2` to parse provider errors into structured types
- Error types: `APIError`, `RateLimitError`, `AuthenticationError`, `ValidationError`, `NetworkError`, `TimeoutError`, `ProviderError`, `ToolError`, `MaxDepthError`

### Changed
- **Provider detection** - Now supports 8 providers with automatic model-based routing
- **Test coverage** - Expanded from 24 to 60 tests

### Fixed
- **Code complexity** - Replaced nested `case` in `media_type_from_path/1` with efficient Map lookup
- **List operations** - Fixed inefficient `length(list) > 0` checks in all providers
- **Enum operations** - Used `Enum.map_join/3` instead of `Enum.map |> Enum.join`
- **Alias ordering** - All modules now have alphabetically sorted aliases

---

## [0.1.0] - 2026-01-20

### Added

#### Core Features
- **Unified Chat API** - Single interface for all LLM providers
- **Pipe-based configuration** - Idiomatic Elixir with `new() |> model() |> ask()`
- **Conversation continuity** - Multi-turn conversations with automatic context
- **Streaming support** - Real-time token streaming with callbacks

#### Providers
- **OpenAI** - GPT-4o, GPT-4-turbo, o1, o3-mini support
- **Anthropic** - Claude Sonnet 4, Claude Opus 4 support
- **Ollama** - Local models (Llama, Mistral, CodeLlama)
- **Auto-detection** - Provider automatically detected from model name

#### Tools
- **Tool behaviour** - `use ElixirLLM.Tool` with DSL for parameters
- **Inline tools** - `ElixirLLM.Tool.define/1` for quick definitions
- **Automatic execution loop** - No manual tool call handling required
- **Tool callbacks** - `on_tool_call` and `on_tool_result` hooks

#### Structured Output
- **Schema DSL** - `use ElixirLLM.Schema` with `field`, `embeds_one`, `embeds_many`
- **JSON Schema generation** - Automatic conversion for provider APIs
- **Type parsing** - Response automatically parsed into Elixir structs

#### Embeddings
- **Vector generation** - `ElixirLLM.embed/2` for text embeddings
- **Batch support** - Embed multiple texts in one call
- **Similarity functions** - `cosine_similarity/2`, `euclidean_distance/2`, `dot_product/2`
- **OpenAI text-embedding-3-small** - Default embedding model

#### Multi-Modal
- **Image support** - `ElixirLLM.image/1` for local files
- **Image URLs** - `ElixirLLM.image_url/1` for remote images
- **PDF documents** - `ElixirLLM.pdf/1` for document analysis (Claude)
- **Audio support** - `ElixirLLM.audio/1` for audio files

#### Phoenix/Ecto Integration
- **Mix generator** - `mix elixir_llm.gen.ecto` creates schemas and migrations
- **Chat persistence** - Automatic message saving with `use ElixirLLM.Ecto.Chat`
- **Message schema** - Token tracking, role enum, tool call references
- **Tool call schema** - Full tool execution history

#### Observability
- **Telemetry integration** - Events for chat, streaming, tools, embeddings
- **Request/response metadata** - Model, tokens, duration tracking

### Technical Details
- Minimal dependencies: Req, Jason, Telemetry, NimbleOptions
- Elixir 1.14+ compatibility
- Full documentation with examples

---

## [0.0.1] - 2026-01-20

### Added
- Initial project structure
- Basic README

---

[Unreleased]: https://github.com/khasinski/elixir_llm/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/khasinski/elixir_llm/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/khasinski/elixir_llm/releases/tag/v0.2.0
[0.1.0]: https://github.com/khasinski/elixir_llm/releases/tag/v0.1.0
[0.0.1]: https://github.com/khasinski/elixir_llm/releases/tag/v0.0.1
