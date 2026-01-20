# ElixirLLM

[![Hex.pm](https://img.shields.io/hexpm/v/elixir_llm.svg)](https://hex.pm/packages/elixir_llm)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/elixir_llm)
[![CI](https://github.com/khasinski/elixir_llm/actions/workflows/ci.yml/badge.svg)](https://github.com/khasinski/elixir_llm/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**One beautiful API for all LLMs.** Chat with GPT-4, Claude, Llama, and more—using idiomatic Elixir.

No more juggling different APIs. No more provider lock-in. Just clean, pipe-friendly code that works everywhere.

```elixir
{:ok, response} = ElixirLLM.chat("What is Elixir?")
```

Inspired by the wonderful [RubyLLM](https://rubyllm.com).

---

## Demo

```elixir
iex> ElixirLLM.new()
...> |> ElixirLLM.model("gpt-4o")
...> |> ElixirLLM.tool(MyApp.Tools.Weather)
...> |> ElixirLLM.ask("What's the weather in Tokyo?")

# Tool called: get_weather(%{city: "Tokyo"})
# Tool result: %{temperature: 18, conditions: "partly cloudy"}

{:ok,
 %ElixirLLM.Response{
   content: "It's currently 18°C and partly cloudy in Tokyo.",
   model: "gpt-4o",
   input_tokens: 52,
   output_tokens: 14
 },
 %ElixirLLM.Chat{...}}
```

---

## Why ElixirLLM?

Every AI provider has their own API. Different formats. Different conventions. Different headaches.

**ElixirLLM gives you one consistent interface for all of them:**

| Feature | What it means |
|---------|---------------|
| **Unified API** | Same code works with GPT-4, Claude, Llama, and more |
| **Pipe-friendly** | Idiomatic Elixir with chainable configuration |
| **Tools that just work** | Define once, automatic execution loop handles the rest |
| **Streaming built-in** | Real-time responses with callbacks or Streams |
| **Phoenix/Ecto ready** | First-class persistence with `mix elixir_llm.gen.ecto` |
| **Minimal deps** | Just Req, Jason, and Telemetry—no bloat |

---

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:elixir_llm, "~> 0.1.0"}
  ]
end
```

Then configure your API keys:

```elixir
# config/runtime.exs
config :elixir_llm,
  openai: [api_key: System.get_env("OPENAI_API_KEY")],
  anthropic: [api_key: System.get_env("ANTHROPIC_API_KEY")]
```

---

## Quick Start

### Simple Chat

```elixir
# One-liner
{:ok, response} = ElixirLLM.chat("Explain pattern matching in Elixir")

# With options
{:ok, response} = ElixirLLM.chat("Hello!", model: "claude-sonnet-4-20250514")
```

### Pipe-Based Configuration

```elixir
{:ok, response, chat} =
  ElixirLLM.new()
  |> ElixirLLM.model("gpt-4o")
  |> ElixirLLM.temperature(0.7)
  |> ElixirLLM.instructions("You are a helpful Elixir expert")
  |> ElixirLLM.ask("What's the difference between Task and GenServer?")

# Continue the conversation
{:ok, response, chat} = ElixirLLM.ask(chat, "Show me an example")
```

### Streaming

```elixir
# With callback - tokens appear in real-time
{:ok, response, _chat} =
  ElixirLLM.new()
  |> ElixirLLM.model("gpt-4o")
  |> ElixirLLM.ask("Write a haiku about Elixir", stream: fn chunk ->
    IO.write(chunk.content || "")
  end)

# As Elixir Stream - composable and lazy
ElixirLLM.new()
|> ElixirLLM.stream("Tell me a story")
|> Stream.each(&IO.write(&1.content || ""))
|> Stream.run()
```

---

## Tools

Let AI call your Elixir code. ElixirLLM handles the entire tool execution loop automatically—no manual back-and-forth required.

### Define a Tool

```elixir
defmodule MyApp.Tools.Weather do
  use ElixirLLM.Tool,
    name: "get_weather",
    description: "Gets current weather for a location"

  param :city, :string, required: true, description: "City name"
  param :units, :string, required: false, description: "celsius or fahrenheit"

  @impl true
  def execute(%{city: city, units: units}) do
    # Your implementation here
    {:ok, %{temperature: 22, conditions: "sunny", city: city}}
  end
end
```

### Use Tools

```elixir
{:ok, response, _chat} =
  ElixirLLM.new()
  |> ElixirLLM.tool(MyApp.Tools.Weather)
  |> ElixirLLM.ask("What's the weather in Berlin?")

# The model calls your tool, gets the result, and responds naturally:
# => "The current weather in Berlin is sunny with a temperature of 22°C."
```

### Inline Tools

For quick one-offs:

```elixir
calculator = ElixirLLM.Tool.define(
  name: "calculator",
  description: "Performs math calculations",
  parameters: %{
    a: [type: :integer, required: true, description: "First number"],
    b: [type: :integer, required: true, description: "Second number"],
    operation: [type: :string, required: true, description: "add, subtract, multiply, divide"]
  },
  execute: fn %{a: a, b: b, operation: op} ->
    result = case op do
      "add" -> a + b
      "subtract" -> a - b
      "multiply" -> a * b
      "divide" -> a / b
    end
    {:ok, "Result: #{result}"}
  end
)

{:ok, response, _} =
  ElixirLLM.new()
  |> ElixirLLM.tool(calculator)
  |> ElixirLLM.ask("What's 42 * 17?")
# => "42 multiplied by 17 is 714."
```

---

## Structured Output

Get typed, validated responses with the Schema DSL:

```elixir
defmodule MyApp.Schemas.Person do
  use ElixirLLM.Schema

  field :name, :string, description: "Full name"
  field :age, :integer, description: "Age in years"
  field :email, :string, required: false

  embeds_one :address do
    field :city, :string
    field :country, :string
  end

  embeds_many :skills, of: :string
end

{:ok, %MyApp.Schemas.Person{} = person, _chat} =
  ElixirLLM.new()
  |> ElixirLLM.schema(MyApp.Schemas.Person)
  |> ElixirLLM.ask("Generate a profile for a senior Elixir developer")

person.name         # => "Alice Chen"
person.age          # => 34
person.address.city # => "San Francisco"
person.skills       # => ["Elixir", "Phoenix", "PostgreSQL"]
```

---

## Multi-Modal (Images, Audio, PDFs)

```elixir
# Analyze an image
{:ok, response, _} =
  ElixirLLM.new()
  |> ElixirLLM.model("gpt-4o")
  |> ElixirLLM.ask("What's in this image?", with: ElixirLLM.image("photo.jpg"))

# From URL
{:ok, response, _} =
  ElixirLLM.new()
  |> ElixirLLM.ask("Describe this", with: ElixirLLM.image_url("https://example.com/photo.jpg"))

# PDF document (Claude)
{:ok, response, _} =
  ElixirLLM.new()
  |> ElixirLLM.model("claude-sonnet-4-20250514")
  |> ElixirLLM.ask("Summarize this contract", with: ElixirLLM.pdf("contract.pdf"))
```

---

## Embeddings

Generate vector representations for semantic search, similarity, and RAG:

```elixir
# Single text
{:ok, embedding} = ElixirLLM.embed("Elixir is a functional language")
embedding.vector  # => [-0.019, -0.025, 0.018, ...]

# Batch processing
{:ok, embeddings} = ElixirLLM.embed(["Hello", "World", "Elixir"])

# Semantic similarity
alias ElixirLLM.Embedding

{:ok, e1} = ElixirLLM.embed("The cat sat on the mat")
{:ok, e2} = ElixirLLM.embed("A feline rested on a rug")
{:ok, e3} = ElixirLLM.embed("The stock market crashed")

Embedding.cosine_similarity(e1, e2)  # => 0.635 (similar!)
Embedding.cosine_similarity(e1, e3)  # => 0.064 (different)
```

---

## Phoenix/Ecto Integration

Persist conversations to your database with one command:

```bash
mix elixir_llm.gen.ecto
mix ecto.migrate
```

This generates:
- `MyApp.LLM.Chat` — Conversation schema
- `MyApp.LLM.Message` — Message schema with token tracking
- `MyApp.LLM.ToolCall` — Tool call history
- Migration for all tables

### Using Persisted Chats

```elixir
# Create a chat
{:ok, chat} = MyApp.LLM.Chat.create(%{model_id: "gpt-4o"})

# Ask questions - automatically persisted
{:ok, response, chat} = MyApp.LLM.Chat.ask(chat, "Hello!", repo: MyApp.Repo)

# Later, load and continue the conversation
chat = MyApp.Repo.get(MyApp.LLM.Chat, id) |> MyApp.Repo.preload(:messages)
{:ok, response, chat} = MyApp.LLM.Chat.ask(chat, "What did we discuss?", repo: MyApp.Repo)
```

### LiveView Streaming

Real-time AI responses in your Phoenix app:

```elixir
def handle_event("send_message", %{"message" => msg}, socket) do
  chat = socket.assigns.chat
  parent = self()

  Task.start(fn ->
    MyApp.LLM.Chat.ask(chat, msg,
      repo: MyApp.Repo,
      stream: fn chunk ->
        send(parent, {:chunk, chunk})
      end
    )
  end)

  {:noreply, assign(socket, loading: true)}
end

def handle_info({:chunk, chunk}, socket) do
  new_response = socket.assigns.response <> (chunk.content || "")
  {:noreply, assign(socket, response: new_response)}
end
```

---

## Configuration

```elixir
# config/config.exs
config :elixir_llm,
  default_model: "gpt-4o"

# config/runtime.exs (recommended for secrets)
config :elixir_llm,
  openai: [
    api_key: System.get_env("OPENAI_API_KEY")
    # base_url: "https://api.openai.com/v1"  # optional, for proxies
  ],

  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY")
  ],

  ollama: [
    base_url: "http://localhost:11434"
  ]

# For Ecto integration
config :elixir_llm, :ecto,
  repo: MyApp.Repo,
  chat_schema: MyApp.LLM.Chat,
  message_schema: MyApp.LLM.Message
```

---

## Providers

ElixirLLM auto-detects the provider from the model name:

| Provider | Example Models | Features |
|----------|----------------|----------|
| **OpenAI** | `gpt-4o`, `gpt-4-turbo`, `o1`, `o3-mini` | Chat, Vision, Tools, Streaming, Embeddings |
| **Anthropic** | `claude-sonnet-4-20250514`, `claude-opus-4-20250514` | Chat, Vision, PDFs, Tools, Streaming |
| **Ollama** | `llama3.2`, `mistral`, `codellama` | Chat, Tools, Streaming, 100% Local |

```elixir
# Provider is auto-detected from model name
ElixirLLM.new() |> ElixirLLM.model("gpt-4o")                   # => OpenAI
ElixirLLM.new() |> ElixirLLM.model("claude-sonnet-4-20250514") # => Anthropic
ElixirLLM.new() |> ElixirLLM.model("llama3.2")                 # => Ollama
```

---

## Telemetry

ElixirLLM emits telemetry events for observability, metrics, and debugging:

```elixir
# Attach a handler
:telemetry.attach("llm-logger", [:elixir_llm, :chat, :stop], fn _event, measurements, metadata, _config ->
  Logger.info("#{metadata.model} responded in #{div(measurements.duration, 1_000_000)}ms")
end, nil)
```

### Events

| Event | When |
|-------|------|
| `[:elixir_llm, :chat, :start \| :stop]` | Chat request lifecycle |
| `[:elixir_llm, :stream, :start \| :stop]` | Streaming request lifecycle |
| `[:elixir_llm, :tool, :call]` | Tool is being called |
| `[:elixir_llm, :tool, :result]` | Tool returned a result |
| `[:elixir_llm, :embed, :start \| :stop]` | Embedding request lifecycle |

---

## Comparison

| Feature | ElixirLLM | LangChain | ExLLM |
|---------|-----------|-----------|-------|
| **Unified API** | Pipe-based | Chain-based | Mixed |
| **Tool DSL** | `use ElixirLLM.Tool` | Functions | Basic |
| **Auto tool loop** | Yes | Manual | Manual |
| **Schema DSL** | Yes | No | Basic |
| **Ecto integration** | First-class | No | No |
| **Streaming** | Callback + Stream | Callbacks | Basic |
| **Telemetry** | Built-in | No | No |
| **Multi-modal** | Images, PDFs, Audio | Limited | No |

---

## Contributing

We welcome contributions! Here's how to get started:

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/elixir_llm.git`
3. **Install** dependencies: `mix deps.get`
4. **Run** tests: `mix test`
5. **Create** a branch: `git checkout -b my-feature`
6. **Make** your changes
7. **Run** the formatter: `mix format`
8. **Submit** a pull request

### Development Setup

```bash
# Clone and setup
git clone https://github.com/khasinski/elixir_llm.git
cd elixir_llm
mix deps.get

# Run tests (requires API keys in environment)
export OPENAI_API_KEY=your_key
export ANTHROPIC_API_KEY=your_key
mix test

# Generate docs
mix docs
```

### Guidelines

- Follow existing code style
- Add tests for new features
- Update documentation
- Keep commits focused and atomic
- Write descriptive commit messages

---

## Roadmap

- [ ] Google Gemini provider
- [ ] AWS Bedrock provider
- [ ] OpenRouter provider
- [ ] Function calling with multiple parallel tools
- [ ] Vision streaming
- [ ] Audio input/output (Whisper, TTS)
- [ ] Token counting utilities
- [ ] Cost estimation

See the [CHANGELOG](CHANGELOG.md) for release history.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Acknowledgements

Inspired by the beautiful API design of [RubyLLM](https://rubyllm.com) by [@crmne](https://github.com/crmne).

Built with love for the Elixir community.

---

<p align="center">
  <strong>Ready to build something amazing?</strong><br>
  <code>mix hex.info elixir_llm</code>
</p>
