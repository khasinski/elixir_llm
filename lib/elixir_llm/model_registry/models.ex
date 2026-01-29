defmodule ElixirLLM.ModelRegistry.Models do
  @moduledoc """
  Built-in model definitions with capabilities and pricing.

  Pricing is in USD per million tokens as of January 2025.
  """

  alias ElixirLLM.ModelRegistry

  @models [
    # ===========================================================================
    # OpenAI Models
    # ===========================================================================
    %ModelRegistry{
      id: "gpt-4o",
      provider: :openai,
      display_name: "GPT-4o",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 128_000,
      max_output_tokens: 16_384,
      input_price_per_million: 2.50,
      output_price_per_million: 10.00,
      aliases: ["gpt-4o-2024-11-20"]
    },
    %ModelRegistry{
      id: "gpt-4o-mini",
      provider: :openai,
      display_name: "GPT-4o Mini",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 128_000,
      max_output_tokens: 16_384,
      input_price_per_million: 0.15,
      output_price_per_million: 0.60,
      aliases: ["gpt-4o-mini-2024-07-18"]
    },
    %ModelRegistry{
      id: "gpt-4.5-preview",
      provider: :openai,
      display_name: "GPT-4.5 Preview",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 128_000,
      max_output_tokens: 16_384,
      input_price_per_million: 75.00,
      output_price_per_million: 150.00
    },
    %ModelRegistry{
      id: "o1",
      provider: :openai,
      display_name: "o1",
      capabilities: [:chat, :streaming, :tools, :vision, :extended_thinking],
      context_window: 200_000,
      max_output_tokens: 100_000,
      input_price_per_million: 15.00,
      output_price_per_million: 60.00
    },
    %ModelRegistry{
      id: "o1-mini",
      provider: :openai,
      display_name: "o1 Mini",
      capabilities: [:chat, :streaming, :tools, :extended_thinking],
      context_window: 128_000,
      max_output_tokens: 65_536,
      input_price_per_million: 3.00,
      output_price_per_million: 12.00
    },
    %ModelRegistry{
      id: "o3-mini",
      provider: :openai,
      display_name: "o3 Mini",
      capabilities: [:chat, :streaming, :tools, :extended_thinking],
      context_window: 128_000,
      max_output_tokens: 65_536,
      input_price_per_million: 1.10,
      output_price_per_million: 4.40
    },
    %ModelRegistry{
      id: "gpt-image-1.5",
      provider: :openai,
      display_name: "GPT Image 1.5",
      capabilities: [:image_gen],
      context_window: 32_000,
      max_output_tokens: nil,
      input_price_per_million: 0.0,
      output_price_per_million: 0.0,
      metadata: %{
        image_price_low: 0.02,
        image_price_medium: 0.07,
        image_price_high: 0.19
      }
    },
    %ModelRegistry{
      id: "gpt-image-1",
      provider: :openai,
      display_name: "GPT Image 1",
      capabilities: [:image_gen],
      context_window: 32_000,
      max_output_tokens: nil,
      input_price_per_million: 0.0,
      output_price_per_million: 0.0,
      metadata: %{
        image_price_low: 0.011,
        image_price_medium: 0.042,
        image_price_high: 0.167
      }
    },
    %ModelRegistry{
      id: "whisper-1",
      provider: :openai,
      display_name: "Whisper",
      capabilities: [:audio],
      context_window: 0,
      max_output_tokens: nil,
      input_price_per_million: 0.0,
      output_price_per_million: 0.0,
      metadata: %{price_per_minute: 0.006}
    },
    %ModelRegistry{
      id: "text-embedding-3-small",
      provider: :openai,
      display_name: "Text Embedding 3 Small",
      capabilities: [:embeddings],
      context_window: 8191,
      max_output_tokens: nil,
      input_price_per_million: 0.02,
      output_price_per_million: 0.0
    },
    %ModelRegistry{
      id: "text-embedding-3-large",
      provider: :openai,
      display_name: "Text Embedding 3 Large",
      capabilities: [:embeddings],
      context_window: 8191,
      max_output_tokens: nil,
      input_price_per_million: 0.13,
      output_price_per_million: 0.0
    },

    # ===========================================================================
    # Anthropic Models
    # ===========================================================================
    %ModelRegistry{
      id: "claude-sonnet-4-20250514",
      provider: :anthropic,
      display_name: "Claude Sonnet 4",
      capabilities: [:chat, :streaming, :tools, :vision, :pdf, :extended_thinking],
      context_window: 200_000,
      max_output_tokens: 64_000,
      input_price_per_million: 3.00,
      output_price_per_million: 15.00,
      aliases: ["claude-4-sonnet", "claude-sonnet-4"]
    },
    %ModelRegistry{
      id: "claude-opus-4-20250514",
      provider: :anthropic,
      display_name: "Claude Opus 4",
      capabilities: [:chat, :streaming, :tools, :vision, :pdf, :extended_thinking],
      context_window: 200_000,
      max_output_tokens: 32_000,
      input_price_per_million: 15.00,
      output_price_per_million: 75.00,
      aliases: ["claude-4-opus", "claude-opus-4"]
    },
    %ModelRegistry{
      id: "claude-3-5-sonnet-20241022",
      provider: :anthropic,
      display_name: "Claude 3.5 Sonnet",
      capabilities: [:chat, :streaming, :tools, :vision, :pdf],
      context_window: 200_000,
      max_output_tokens: 8192,
      input_price_per_million: 3.00,
      output_price_per_million: 15.00,
      aliases: ["claude-3-5-sonnet", "claude-3.5-sonnet"]
    },
    %ModelRegistry{
      id: "claude-3-5-haiku-20241022",
      provider: :anthropic,
      display_name: "Claude 3.5 Haiku",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 200_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.80,
      output_price_per_million: 4.00,
      aliases: ["claude-3-5-haiku", "claude-3.5-haiku", "claude-3-5-haiku-latest"]
    },
    %ModelRegistry{
      id: "claude-3-opus-20240229",
      provider: :anthropic,
      display_name: "Claude 3 Opus",
      capabilities: [:chat, :streaming, :tools, :vision, :pdf],
      context_window: 200_000,
      max_output_tokens: 4096,
      input_price_per_million: 15.00,
      output_price_per_million: 75.00,
      aliases: ["claude-3-opus"]
    },

    # ===========================================================================
    # Google Gemini Models
    # ===========================================================================
    %ModelRegistry{
      id: "gemini-2.0-flash",
      provider: :gemini,
      display_name: "Gemini 2.0 Flash",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 1_000_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.10,
      output_price_per_million: 0.40,
      aliases: ["gemini-2.0-flash-001"]
    },
    %ModelRegistry{
      id: "gemini-2.0-flash-lite",
      provider: :gemini,
      display_name: "Gemini 2.0 Flash Lite",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 1_000_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.075,
      output_price_per_million: 0.30,
      aliases: ["gemini-2.0-flash-lite-001"]
    },
    %ModelRegistry{
      id: "gemini-2.5-flash",
      provider: :gemini,
      display_name: "Gemini 2.5 Flash",
      capabilities: [:chat, :streaming, :tools, :vision, :extended_thinking],
      context_window: 1_000_000,
      max_output_tokens: 65_536,
      input_price_per_million: 0.15,
      output_price_per_million: 0.60,
      aliases: ["gemini-2.5-flash-preview-05-20"]
    },
    %ModelRegistry{
      id: "gemini-2.0-flash-exp-image-generation",
      provider: :gemini,
      display_name: "Gemini 2.0 Flash (Image Gen)",
      capabilities: [:chat, :streaming, :image_gen],
      context_window: 32_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.0,
      output_price_per_million: 0.0,
      aliases: ["gemini-image", "nano-banana"],
      metadata: %{image_generation: true}
    },
    %ModelRegistry{
      id: "gemini-1.5-pro",
      provider: :gemini,
      display_name: "Gemini 1.5 Pro",
      capabilities: [:chat, :streaming, :tools, :vision, :audio],
      context_window: 2_000_000,
      max_output_tokens: 8192,
      input_price_per_million: 1.25,
      output_price_per_million: 5.00,
      aliases: ["gemini-1.5-pro-002"]
    },
    %ModelRegistry{
      id: "gemini-1.5-flash",
      provider: :gemini,
      display_name: "Gemini 1.5 Flash",
      capabilities: [:chat, :streaming, :tools, :vision, :audio],
      context_window: 1_000_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.075,
      output_price_per_million: 0.30,
      aliases: ["gemini-1.5-flash-002"]
    },

    # ===========================================================================
    # xAI/Grok Models
    # ===========================================================================
    %ModelRegistry{
      id: "grok-3",
      provider: :xai,
      display_name: "Grok 3",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 131_072,
      max_output_tokens: 16_384,
      input_price_per_million: 3.00,
      output_price_per_million: 15.00,
      aliases: ["xai/grok-3"]
    },
    %ModelRegistry{
      id: "grok-3-mini",
      provider: :xai,
      display_name: "Grok 3 Mini",
      capabilities: [:chat, :streaming, :tools, :extended_thinking],
      context_window: 131_072,
      max_output_tokens: 16_384,
      input_price_per_million: 0.30,
      output_price_per_million: 0.50,
      aliases: ["xai/grok-3-mini"]
    },
    %ModelRegistry{
      id: "grok-2",
      provider: :xai,
      display_name: "Grok 2",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 131_072,
      max_output_tokens: 16_384,
      input_price_per_million: 2.00,
      output_price_per_million: 10.00,
      aliases: ["xai/grok-2", "grok-2-1212"]
    },

    # ===========================================================================
    # DeepSeek Models
    # ===========================================================================
    %ModelRegistry{
      id: "deepseek-chat",
      provider: :deepseek,
      display_name: "DeepSeek Chat",
      capabilities: [:chat, :streaming, :tools],
      context_window: 64_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.14,
      output_price_per_million: 0.28,
      aliases: ["deepseek/deepseek-chat", "deepseek-v3"]
    },
    %ModelRegistry{
      id: "deepseek-reasoner",
      provider: :deepseek,
      display_name: "DeepSeek Reasoner",
      capabilities: [:chat, :streaming, :tools, :extended_thinking],
      context_window: 64_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.55,
      output_price_per_million: 2.19,
      aliases: ["deepseek/deepseek-reasoner", "deepseek-r1"]
    },
    %ModelRegistry{
      id: "deepseek-coder",
      provider: :deepseek,
      display_name: "DeepSeek Coder",
      capabilities: [:chat, :streaming, :tools],
      context_window: 64_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.14,
      output_price_per_million: 0.28,
      aliases: ["deepseek/deepseek-coder"]
    },

    # ===========================================================================
    # Mistral Models
    # ===========================================================================
    %ModelRegistry{
      id: "mistral-large-latest",
      provider: :mistral,
      display_name: "Mistral Large",
      capabilities: [:chat, :streaming, :tools, :vision],
      context_window: 128_000,
      max_output_tokens: 8192,
      input_price_per_million: 2.00,
      output_price_per_million: 6.00,
      aliases: ["mistral-large-2411"]
    },
    %ModelRegistry{
      id: "mistral-small-latest",
      provider: :mistral,
      display_name: "Mistral Small",
      capabilities: [:chat, :streaming, :tools],
      context_window: 32_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.10,
      output_price_per_million: 0.30,
      aliases: ["mistral-small-2501"]
    },
    %ModelRegistry{
      id: "codestral-latest",
      provider: :mistral,
      display_name: "Codestral",
      capabilities: [:chat, :streaming, :tools],
      context_window: 256_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.30,
      output_price_per_million: 0.90,
      aliases: ["codestral-2501"]
    },

    # ===========================================================================
    # Groq Models
    # ===========================================================================
    %ModelRegistry{
      id: "groq/llama-3.3-70b-versatile",
      provider: :groq,
      display_name: "Llama 3.3 70B (Groq)",
      capabilities: [:chat, :streaming, :tools],
      context_window: 128_000,
      max_output_tokens: 32_768,
      input_price_per_million: 0.59,
      output_price_per_million: 0.79
    },
    %ModelRegistry{
      id: "groq/llama-3.1-8b-instant",
      provider: :groq,
      display_name: "Llama 3.1 8B (Groq)",
      capabilities: [:chat, :streaming, :tools],
      context_window: 128_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.05,
      output_price_per_million: 0.08
    },
    %ModelRegistry{
      id: "groq/mixtral-8x7b-32768",
      provider: :groq,
      display_name: "Mixtral 8x7B (Groq)",
      capabilities: [:chat, :streaming, :tools],
      context_window: 32_768,
      max_output_tokens: 8192,
      input_price_per_million: 0.24,
      output_price_per_million: 0.24
    },

    # ===========================================================================
    # Together AI Models
    # ===========================================================================
    %ModelRegistry{
      id: "together/meta-llama/Llama-3.3-70B-Instruct-Turbo",
      provider: :together,
      display_name: "Llama 3.3 70B (Together)",
      capabilities: [:chat, :streaming, :tools],
      context_window: 128_000,
      max_output_tokens: 8192,
      input_price_per_million: 0.88,
      output_price_per_million: 0.88
    },
    %ModelRegistry{
      id: "together/Qwen/Qwen2.5-72B-Instruct-Turbo",
      provider: :together,
      display_name: "Qwen 2.5 72B (Together)",
      capabilities: [:chat, :streaming, :tools],
      context_window: 32_768,
      max_output_tokens: 8192,
      input_price_per_million: 0.60,
      output_price_per_million: 0.60
    },

    # ===========================================================================
    # AWS Bedrock Models (using Bedrock model IDs)
    # ===========================================================================
    %ModelRegistry{
      id: "bedrock/claude-sonnet-4",
      provider: :bedrock,
      display_name: "Claude Sonnet 4 (Bedrock)",
      capabilities: [:chat, :streaming, :tools, :vision, :pdf, :extended_thinking],
      context_window: 200_000,
      max_output_tokens: 64_000,
      input_price_per_million: 3.00,
      output_price_per_million: 15.00,
      metadata: %{bedrock_model_id: "anthropic.claude-sonnet-4-20250514-v1:0"}
    },
    %ModelRegistry{
      id: "bedrock/claude-3-5-sonnet",
      provider: :bedrock,
      display_name: "Claude 3.5 Sonnet (Bedrock)",
      capabilities: [:chat, :streaming, :tools, :vision, :pdf],
      context_window: 200_000,
      max_output_tokens: 8192,
      input_price_per_million: 3.00,
      output_price_per_million: 15.00,
      metadata: %{bedrock_model_id: "anthropic.claude-3-5-sonnet-20241022-v2:0"}
    },
    %ModelRegistry{
      id: "bedrock/llama3-70b",
      provider: :bedrock,
      display_name: "Llama 3 70B (Bedrock)",
      capabilities: [:chat, :streaming],
      context_window: 8192,
      max_output_tokens: 2048,
      input_price_per_million: 2.65,
      output_price_per_million: 3.50,
      metadata: %{bedrock_model_id: "meta.llama3-70b-instruct-v1:0"}
    }
  ]

  @doc """
  Returns all built-in model definitions.
  """
  @spec all() :: [ModelRegistry.t()]
  def all, do: @models
end
