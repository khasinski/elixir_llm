defmodule ElixirLLM.Provider do
  @moduledoc """
  Behaviour for LLM provider implementations.

  Providers must implement chat completion and streaming functionality.
  Optionally, they can implement embeddings and other features.
  """

  alias ElixirLLM.{Chat, Response, Chunk}

  @doc """
  Sends a chat completion request and returns the response.
  """
  @callback chat(chat :: Chat.t()) :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Sends a streaming chat completion request, yielding chunks to the callback.
  Returns the final accumulated response.
  """
  @callback stream(chat :: Chat.t(), callback :: (Chunk.t() -> any())) ::
              {:ok, Response.t()} | {:error, term()}

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
