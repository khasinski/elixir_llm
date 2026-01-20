# Changelog

All notable changes to ElixirLLM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Google Gemini provider
- AWS Bedrock provider
- OpenRouter provider
- Parallel tool execution
- Audio input/output support
- Token counting utilities
- Cost estimation

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

[Unreleased]: https://github.com/khasinski/elixir_llm/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/khasinski/elixir_llm/releases/tag/v0.1.0
[0.0.1]: https://github.com/khasinski/elixir_llm/releases/tag/v0.0.1
