defmodule ElixirLLM.CostTest do
  use ExUnit.Case, async: true

  alias ElixirLLM.Cost
  alias ElixirLLM.Response

  describe "calculate/1 with Response" do
    test "calculates cost from response struct" do
      response = %Response{
        content: "Hello",
        model: "gpt-4o",
        input_tokens: 100,
        output_tokens: 50
      }

      cost = Cost.calculate(response)

      assert is_float(cost.input)
      assert is_float(cost.output)
      assert is_float(cost.total)
      assert cost.currency == "USD"
      assert cost.total == cost.input + cost.output
    end

    test "handles nil tokens" do
      response = %Response{
        content: "Hello",
        model: "gpt-4o",
        input_tokens: nil,
        output_tokens: nil
      }

      cost = Cost.calculate(response)
      assert cost.total == 0.0
    end
  end

  describe "calculate/3 with model and tokens" do
    test "calculates cost for known model" do
      # gpt-4o: $2.50 input, $10 output per million tokens
      cost = Cost.calculate("gpt-4o", 1_000_000, 1_000_000)

      assert cost.input == 2.5
      assert cost.output == 10.0
      assert cost.total == 12.5
      assert cost.currency == "USD"
    end

    test "returns zero cost for unknown model" do
      cost = Cost.calculate("unknown-model", 1000, 1000)

      assert cost.input == 0.0
      assert cost.output == 0.0
      assert cost.total == 0.0
    end

    test "calculates fractional costs correctly" do
      # 100 tokens at gpt-4o rates
      cost = Cost.calculate("gpt-4o", 100, 100)

      assert cost.input > 0
      assert cost.output > 0
      # Should be very small but non-zero
      assert cost.total < 0.01
    end
  end

  describe "estimate/3" do
    test "estimates cost with default output multiplier" do
      # Default is 2x input tokens for output
      estimate = Cost.estimate("gpt-4o", 1000)

      assert estimate.total > 0
      assert estimate.currency == "USD"
    end

    test "estimates cost with custom output tokens" do
      estimate = Cost.estimate("gpt-4o", 1000, estimated_output_tokens: 500)

      # Should be different from default 2x
      default_estimate = Cost.estimate("gpt-4o", 1000)
      assert estimate.total != default_estimate.total
    end
  end

  describe "per_token_pricing/1" do
    test "returns per-token pricing for known model" do
      assert {:ok, pricing} = Cost.per_token_pricing("gpt-4o")

      assert pricing.input > 0
      assert pricing.output > 0
      # Per-token should be much smaller than per-million
      assert pricing.input < 0.001
      assert pricing.output < 0.001
    end

    test "returns error for unknown model" do
      assert {:error, :not_found} = Cost.per_token_pricing("unknown-model")
    end
  end

  describe "format/2" do
    test "formats cost as currency string" do
      cost = %{total: 0.0075, currency: "USD"}

      assert Cost.format(cost) == "$0.007500"
    end

    test "formats with custom precision" do
      cost = %{total: 0.0075, currency: "USD"}

      assert Cost.format(cost, precision: 4) == "$0.0075"
    end
  end

  describe "sum/1" do
    test "sums multiple costs" do
      costs = [
        %{input: 1.0, output: 2.0, total: 3.0, currency: "USD"},
        %{input: 0.5, output: 1.0, total: 1.5, currency: "USD"},
        %{input: 0.25, output: 0.5, total: 0.75, currency: "USD"}
      ]

      total = Cost.sum(costs)

      assert total.input == 1.75
      assert total.output == 3.5
      assert total.total == 5.25
    end

    test "returns zero for empty list" do
      total = Cost.sum([])

      assert total.input == 0.0
      assert total.output == 0.0
      assert total.total == 0.0
    end
  end

  describe "zero/0" do
    test "returns zero cost structure" do
      zero = Cost.zero()

      assert zero.input == 0.0
      assert zero.output == 0.0
      assert zero.total == 0.0
      assert zero.currency == "USD"
    end
  end
end
