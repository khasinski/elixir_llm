defmodule ElixirLLM.Provider do
  @moduledoc """
  Behaviour for LLM provider implementations.

  Providers must implement chat completion and streaming functionality.
  Optionally, they can implement embeddings and other features.

  ## Error Types

  Provider implementations should return structured exceptions on error:

    * `ElixirLLM.Error.AuthenticationError` - Invalid API key (401/403)
    * `ElixirLLM.Error.RateLimitError` - Rate limit exceeded (429)
    * `ElixirLLM.Error.ValidationError` - Invalid parameters (400/422)
    * `ElixirLLM.Error.ProviderError` - Server error (5xx)
    * `ElixirLLM.Error.NetworkError` - Connection failed
    * `ElixirLLM.Error.TimeoutError` - Request timed out
    * `ElixirLLM.Error.APIError` - Other API errors

  Use `ElixirLLM.Providers.Base.parse_error/3` and
  `ElixirLLM.Error.Helpers.from_transport_error/2` to create these.
  """

  alias ElixirLLM.{Chat, Chunk, Response}

  @type error :: Exception.t()

  @doc """
  Sends a chat completion request and returns the response.

  Returns `{:ok, response}` on success or `{:error, exception}` on failure.
  """
  @callback chat(chat :: Chat.t()) :: {:ok, Response.t()} | {:error, error()}

  @doc """
  Sends a streaming chat completion request, yielding chunks to the callback.
  Returns the final accumulated response.

  The callback is called with each chunk as it arrives. The final response
  contains the accumulated content from all chunks.
  """
  @callback stream(chat :: Chat.t(), callback :: (Chunk.t() -> any())) ::
              {:ok, Response.t()} | {:error, error()}

  @doc """
  Converts tools from ElixirLLM format to provider-specific format.
  """
  @callback format_tools(tools :: [module() | map()]) :: list()

  @doc """
  Parses a response from the provider's format to ElixirLLM format.
  """
  @callback parse_response(response :: map()) :: Response.t()

  @doc """
  Parses a streaming chunk from the provider's format.
  """
  @callback parse_chunk(chunk :: map()) :: Chunk.t() | nil

  @optional_callbacks [format_tools: 1, parse_response: 1, parse_chunk: 1]
end
