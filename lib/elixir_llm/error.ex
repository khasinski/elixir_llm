defmodule ElixirLLM.Error do
  @moduledoc """
  Custom exception types for ElixirLLM.

  Provides structured error handling with classification of errors into
  retryable and non-retryable categories.

  ## Error Types

    * `ElixirLLM.Error.APIError` - Errors from LLM provider APIs
    * `ElixirLLM.Error.RateLimitError` - Rate limiting errors (retryable)
    * `ElixirLLM.Error.AuthenticationError` - Invalid API credentials
    * `ElixirLLM.Error.ValidationError` - Invalid request parameters
    * `ElixirLLM.Error.NetworkError` - Network/connection failures (retryable)
    * `ElixirLLM.Error.TimeoutError` - Request timeouts (retryable)
    * `ElixirLLM.Error.ProviderError` - Provider-specific errors
    * `ElixirLLM.Error.ToolError` - Tool execution failures

  ## Example

      case ElixirLLM.chat("Hello") do
        {:ok, response} ->
          response.content

        {:error, %ElixirLLM.Error.RateLimitError{retry_after: seconds}} ->
          Process.sleep(seconds * 1000)
          # Retry...

        {:error, %ElixirLLM.Error.AuthenticationError{}} ->
          Logger.error("Invalid API key")
      end
  """

  @type error_type ::
          :api_error
          | :rate_limit
          | :authentication
          | :validation
          | :network
          | :timeout
          | :provider
          | :tool
end

# Define exception modules outside the parent module to avoid compilation order issues

defmodule ElixirLLM.Error.APIError do
  @moduledoc """
  General API error from an LLM provider.
  """
  defexception [:message, :provider, :status, :body]

  @type t :: %__MODULE__{
          message: String.t(),
          provider: atom(),
          status: integer() | nil,
          body: term()
        }

  @impl true
  def message(%{message: message, provider: provider, status: status}) do
    status_str = if status, do: " (#{status})", else: ""
    "[#{provider}]#{status_str} #{message}"
  end
end

defmodule ElixirLLM.Error.RateLimitError do
  @moduledoc """
  Rate limit exceeded. This error is retryable after waiting.
  """
  defexception [:message, :provider, :retry_after]

  @type t :: %__MODULE__{
          message: String.t(),
          provider: atom(),
          retry_after: integer() | nil
        }

  @impl true
  def message(%{message: message, provider: provider, retry_after: retry_after}) do
    retry_str = if retry_after, do: " (retry after #{retry_after}s)", else: ""
    "[#{provider}] Rate limit exceeded#{retry_str}: #{message}"
  end
end

defmodule ElixirLLM.Error.AuthenticationError do
  @moduledoc """
  Authentication failed. Check your API key.
  """
  defexception [:message, :provider]

  @type t :: %__MODULE__{
          message: String.t(),
          provider: atom()
        }

  @impl true
  def message(%{message: message, provider: provider}) do
    "[#{provider}] Authentication failed: #{message}"
  end
end

defmodule ElixirLLM.Error.ValidationError do
  @moduledoc """
  Request validation failed. Check your parameters.
  """
  defexception [:message, :provider, :details]

  @type t :: %__MODULE__{
          message: String.t(),
          provider: atom(),
          details: term()
        }

  @impl true
  def message(%{message: message, provider: provider}) do
    "[#{provider}] Validation error: #{message}"
  end
end

defmodule ElixirLLM.Error.NetworkError do
  @moduledoc """
  Network connection error. This error is retryable.
  """
  defexception [:message, :provider, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          provider: atom(),
          reason: term()
        }

  @impl true
  def message(%{message: message, provider: provider}) do
    "[#{provider}] Network error: #{message}"
  end
end

defmodule ElixirLLM.Error.TimeoutError do
  @moduledoc """
  Request timed out. This error is retryable.
  """
  defexception [:message, :provider]

  @type t :: %__MODULE__{
          message: String.t(),
          provider: atom()
        }

  @impl true
  def message(%{message: message, provider: provider}) do
    "[#{provider}] Timeout: #{message}"
  end
end

defmodule ElixirLLM.Error.ProviderError do
  @moduledoc """
  Provider-side error (5xx). This error may be retryable.
  """
  defexception [:message, :provider, :status, :body]

  @type t :: %__MODULE__{
          message: String.t(),
          provider: atom(),
          status: integer(),
          body: term()
        }

  @impl true
  def message(%{message: message, provider: provider, status: status}) do
    "[#{provider}] Provider error (#{status}): #{message}"
  end
end

defmodule ElixirLLM.Error.ToolError do
  @moduledoc """
  Tool execution failed.
  """
  defexception [:message, :tool_name, :arguments, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          tool_name: String.t(),
          arguments: map(),
          reason: term()
        }

  @impl true
  def message(%{message: message, tool_name: tool_name}) do
    "[Tool:#{tool_name}] #{message}"
  end
end

defmodule ElixirLLM.Error.MaxDepthError do
  @moduledoc """
  Maximum tool call depth exceeded.
  """
  defexception [:message, :depth]

  @type t :: %__MODULE__{
          message: String.t(),
          depth: integer()
        }

  @impl true
  def message(%{depth: depth}) do
    "Maximum tool call depth (#{depth}) exceeded"
  end
end

# Now add the helper functions back to the main module
defmodule ElixirLLM.Error.Helpers do
  @moduledoc """
  Helper functions for error handling.
  """

  alias ElixirLLM.Error

  @doc """
  Returns true if the error is retryable.
  """
  @spec retryable?(Exception.t()) :: boolean()
  def retryable?(%Error.RateLimitError{}), do: true
  def retryable?(%Error.NetworkError{}), do: true
  def retryable?(%Error.TimeoutError{}), do: true
  def retryable?(%Error.ProviderError{}), do: true
  def retryable?(%Error.APIError{status: status}) when status in 500..599, do: true
  def retryable?(%Error.APIError{status: 429}), do: true
  def retryable?(_), do: false

  @doc """
  Creates a structured error from an HTTP status code and message.

  Can be called in two forms:
    * `from_response(status, message, opts)` - with status, message, and options
    * `from_response(response_map, provider)` - with a response map containing :status, :message, :body

  ## Options
    * `:provider` - The provider atom (e.g., :openai)
    * `:body` - The raw response body
    * `:retry_after` - Seconds to wait before retrying (for rate limits)
  """
  @spec from_response(map(), atom()) :: Exception.t()
  @spec from_response(integer(), String.t(), keyword()) :: Exception.t()
  def from_response(%{status: status, message: message} = response, provider) when is_atom(provider) do
    from_response(status, message, provider: provider, body: Map.get(response, :body))
  end

  def from_response(status, message, opts \\ [])

  def from_response(401, message, opts) do
    %Error.AuthenticationError{
      message: message,
      provider: Keyword.get(opts, :provider)
    }
  end

  def from_response(403, message, opts) do
    %Error.AuthenticationError{
      message: message,
      provider: Keyword.get(opts, :provider)
    }
  end

  def from_response(429, message, opts) do
    retry_after = Keyword.get(opts, :retry_after) || extract_retry_after(Keyword.get(opts, :body))

    %Error.RateLimitError{
      message: message,
      provider: Keyword.get(opts, :provider),
      retry_after: retry_after
    }
  end

  def from_response(400, message, opts) do
    %Error.ValidationError{
      message: message,
      provider: Keyword.get(opts, :provider),
      details: Keyword.get(opts, :body)
    }
  end

  def from_response(422, message, opts) do
    %Error.ValidationError{
      message: message,
      provider: Keyword.get(opts, :provider),
      details: Keyword.get(opts, :body)
    }
  end

  def from_response(status, message, opts) when status in 500..599 do
    %Error.ProviderError{
      message: message,
      provider: Keyword.get(opts, :provider),
      status: status,
      body: Keyword.get(opts, :body)
    }
  end

  def from_response(status, message, opts) do
    %Error.APIError{
      message: message,
      provider: Keyword.get(opts, :provider),
      status: status,
      body: Keyword.get(opts, :body)
    }
  end

  @doc """
  Converts a raw error (map or exception) into a structured error.

  This is the legacy format for backwards compatibility.
  """
  @spec from_raw_error(map() | term(), atom()) :: Exception.t()
  def from_raw_error(%{status: 401, message: message}, provider) do
    %Error.AuthenticationError{
      message: message,
      provider: provider
    }
  end

  def from_raw_error(%{status: 403, message: message}, provider) do
    %Error.AuthenticationError{
      message: message,
      provider: provider
    }
  end

  def from_raw_error(%{status: 429, message: message, body: body}, provider) do
    retry_after = extract_retry_after(body)

    %Error.RateLimitError{
      message: message,
      provider: provider,
      retry_after: retry_after
    }
  end

  def from_raw_error(%{status: 400, message: message, body: body}, provider) do
    %Error.ValidationError{
      message: message,
      provider: provider,
      details: body
    }
  end

  def from_raw_error(%{status: 422, message: message, body: body}, provider) do
    %Error.ValidationError{
      message: message,
      provider: provider,
      details: body
    }
  end

  def from_raw_error(%{status: status, message: message, body: body}, provider)
      when status in 500..599 do
    %Error.ProviderError{
      message: message,
      provider: provider,
      status: status,
      body: body
    }
  end

  def from_raw_error(%{status: status, message: message, body: body}, provider) do
    %Error.APIError{
      message: message,
      provider: provider,
      status: status,
      body: body
    }
  end

  @doc """
  Creates a network/transport error from a Req error.
  """
  @spec from_transport_error(term(), atom()) :: Exception.t()
  def from_transport_error(%Req.TransportError{reason: :timeout}, provider) do
    %Error.TimeoutError{
      message: "Request timed out",
      provider: provider
    }
  end

  def from_transport_error(%Req.TransportError{reason: reason}, provider) do
    %Error.NetworkError{
      message: "Network error: #{inspect(reason)}",
      provider: provider,
      reason: reason
    }
  end

  def from_transport_error(error, provider) when is_atom(error) do
    case error do
      :timeout ->
        %Error.TimeoutError{message: "Request timed out", provider: provider}

      _ ->
        %Error.NetworkError{
          message: "Connection error: #{error}",
          provider: provider,
          reason: error
        }
    end
  end

  def from_transport_error(error, provider) do
    %Error.NetworkError{
      message: inspect(error),
      provider: provider,
      reason: error
    }
  end

  defp extract_retry_after(%{"error" => %{"retry_after" => seconds}}) when is_number(seconds) do
    seconds
  end

  defp extract_retry_after(%{"retry_after" => seconds}) when is_number(seconds) do
    seconds
  end

  defp extract_retry_after(_), do: nil
end
