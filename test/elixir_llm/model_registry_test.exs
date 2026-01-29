defmodule ElixirLLM.ModelRegistryTest do
  use ExUnit.Case, async: true

  alias ElixirLLM.ModelRegistry

  describe "get/1" do
    test "returns model info for known OpenAI models" do
      assert {:ok, model} = ModelRegistry.get("gpt-4o")
      assert model.id == "gpt-4o"
      assert model.provider == :openai
      assert :chat in model.capabilities
    end

    test "returns model info for known Anthropic models" do
      assert {:ok, model} = ModelRegistry.get("claude-sonnet-4-20250514")
      assert model.id == "claude-sonnet-4-20250514"
      assert model.provider == :anthropic
      assert :extended_thinking in model.capabilities
    end

    test "returns model info for known Gemini models" do
      assert {:ok, model} = ModelRegistry.get("gemini-2.0-flash")
      assert model.id == "gemini-2.0-flash"
      assert model.provider == :gemini
    end

    test "returns error for unknown models" do
      assert {:error, :not_found} = ModelRegistry.get("unknown-model-xyz")
    end
  end

  describe "list/1" do
    test "returns all models when no filters" do
      models = ModelRegistry.list()
      assert models != []
      assert Enum.all?(models, &is_struct(&1, ModelRegistry))
    end

    test "filters by provider" do
      openai_models = ModelRegistry.list(provider: :openai)
      assert openai_models != []
      assert Enum.all?(openai_models, &(&1.provider == :openai))
    end

    test "filters by capability" do
      vision_models = ModelRegistry.list(capability: :vision)
      assert vision_models != []
      assert Enum.all?(vision_models, &(:vision in &1.capabilities))
    end

    test "filters by multiple criteria" do
      models = ModelRegistry.list(provider: :anthropic, capability: :tools)
      assert models != []
      assert Enum.all?(models, fn m ->
        m.provider == :anthropic and :tools in m.capabilities
      end)
    end
  end

  describe "supports?/2" do
    test "returns true for supported capabilities" do
      assert ModelRegistry.supports?("gpt-4o", :chat)
      assert ModelRegistry.supports?("gpt-4o", :vision)
      assert ModelRegistry.supports?("gpt-4o", :tools)
    end

    test "returns false for unsupported capabilities" do
      refute ModelRegistry.supports?("gpt-4o", :extended_thinking)
    end

    test "returns false for unknown models" do
      refute ModelRegistry.supports?("unknown-model", :chat)
    end
  end

  describe "price_for/3" do
    test "calculates price for known models" do
      # gpt-4o: $2.50 input, $10 output per million
      assert {:ok, price} = ModelRegistry.price_for("gpt-4o", 1_000_000, 1_000_000)
      assert price == 2.5 + 10.0
    end

    test "returns error for unknown models" do
      assert {:error, :not_found} = ModelRegistry.price_for("unknown", 100, 100)
    end
  end

  describe "register/1" do
    test "registers a custom model" do
      custom = %ModelRegistry{
        id: "test-custom-model",
        provider: :custom,
        display_name: "Test Custom",
        capabilities: [:chat],
        context_window: 4096,
        input_price_per_million: 1.0,
        output_price_per_million: 2.0
      }

      assert :ok = ModelRegistry.register(custom)
      assert {:ok, retrieved} = ModelRegistry.get("test-custom-model")
      assert retrieved.display_name == "Test Custom"
    end
  end

  describe "get/1 returns context window in struct" do
    test "returns context window for known models" do
      assert {:ok, model} = ModelRegistry.get("gpt-4o")
      assert model.context_window == 128_000
    end
  end
end
