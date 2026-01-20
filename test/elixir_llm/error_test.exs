defmodule ElixirLLM.ErrorTest do
  use ExUnit.Case

  alias ElixirLLM.Error
  alias ElixirLLM.Error.Helpers

  describe "Helpers.retryable?/1" do
    test "returns true for rate limit errors" do
      error = %Error.RateLimitError{message: "Rate limited", provider: :openai, retry_after: 60}
      assert Helpers.retryable?(error)
    end

    test "returns true for network errors" do
      error = %Error.NetworkError{message: "Connection failed", provider: :openai, reason: :econnrefused}
      assert Helpers.retryable?(error)
    end

    test "returns true for timeout errors" do
      error = %Error.TimeoutError{message: "Timeout", provider: :openai}
      assert Helpers.retryable?(error)
    end

    test "returns true for 5xx API errors" do
      error = %Error.APIError{message: "Server error", provider: :openai, status: 503, body: %{}}
      assert Helpers.retryable?(error)
    end

    test "returns true for 429 API errors" do
      error = %Error.APIError{message: "Too many requests", provider: :openai, status: 429, body: %{}}
      assert Helpers.retryable?(error)
    end

    test "returns false for authentication errors" do
      error = %Error.AuthenticationError{message: "Invalid API key", provider: :openai}
      refute Helpers.retryable?(error)
    end

    test "returns false for validation errors" do
      error = %Error.ValidationError{message: "Invalid params", provider: :openai, details: %{}}
      refute Helpers.retryable?(error)
    end

    test "returns false for 400 API errors" do
      error = %Error.APIError{message: "Bad request", provider: :openai, status: 400, body: %{}}
      refute Helpers.retryable?(error)
    end
  end

  describe "Helpers.from_response/2" do
    test "creates AuthenticationError for 401" do
      response = %{status: 401, message: "Invalid API key", body: %{}}
      error = Helpers.from_response(response, :openai)
      assert %Error.AuthenticationError{} = error
      assert error.provider == :openai
    end

    test "creates RateLimitError for 429" do
      response = %{status: 429, message: "Rate limit exceeded", body: %{}}
      error = Helpers.from_response(response, :anthropic)
      assert %Error.RateLimitError{} = error
      assert error.provider == :anthropic
    end

    test "creates ValidationError for 400" do
      response = %{status: 400, message: "Invalid parameters", body: %{"details" => "bad"}}
      error = Helpers.from_response(response, :openai)
      assert %Error.ValidationError{} = error
    end

    test "creates ProviderError for 5xx" do
      response = %{status: 502, message: "Bad gateway", body: %{}}
      error = Helpers.from_response(response, :gemini)
      assert %Error.ProviderError{} = error
      assert error.status == 502
    end

    test "extracts retry_after from body" do
      response = %{
        status: 429,
        message: "Rate limited",
        body: %{"error" => %{"retry_after" => 30}}
      }
      error = Helpers.from_response(response, :openai)
      assert error.retry_after == 30
    end
  end

  describe "exception messages" do
    test "APIError message includes provider and status" do
      error = %Error.APIError{message: "Error", provider: :openai, status: 400, body: %{}}
      msg = Exception.message(error)
      assert msg =~ "[openai]"
      assert msg =~ "(400)"
    end

    test "RateLimitError message includes retry_after" do
      error = %Error.RateLimitError{message: "Limited", provider: :anthropic, retry_after: 60}
      msg = Exception.message(error)
      assert msg =~ "retry after 60s"
    end

    test "ToolError message includes tool name" do
      error = %Error.ToolError{message: "Failed", tool_name: "calculator", arguments: %{}, reason: :bad}
      msg = Exception.message(error)
      assert msg =~ "[Tool:calculator]"
    end
  end
end
