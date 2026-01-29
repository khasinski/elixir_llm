defmodule ElixirLLM.Image do
  @moduledoc """
  Image generation capabilities for ElixirLLM.

  Supports OpenAI GPT Image models (gpt-image-1.5, gpt-image-1) and
  Gemini native image generation (nano banana).

  ## Examples

      # Generate with OpenAI (default)
      {:ok, image} = ElixirLLM.Image.generate("A sunset over mountains")
      image.url  # => "https://..."

      # Generate with specific model
      {:ok, image} = ElixirLLM.Image.generate("A futuristic city",
        model: "gpt-image-1.5",
        size: "1024x1024",
        quality: "hd"
      )

      # Generate with Gemini (nano banana)
      {:ok, image} = ElixirLLM.Image.generate("A cat in space",
        model: "gemini-2.0-flash-exp-image-generation"
      )
      image.base64  # => "iVBORw0KGgo..."

      # Get base64 instead of URL (OpenAI)
      {:ok, image} = ElixirLLM.Image.generate("A robot",
        response_format: "b64_json"
      )

  ## Supported Models

    * `gpt-image-1.5` - Latest OpenAI image model (recommended)
    * `gpt-image-1` - Original GPT image model
    * `gpt-image-1-mini` - Cost-effective option
    * `gemini-2.0-flash-exp-image-generation` - Gemini native (nano banana)
  """

  alias ElixirLLM.{Config, Telemetry}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  @type t :: %__MODULE__{
          url: String.t() | nil,
          base64: String.t() | nil,
          revised_prompt: String.t() | nil,
          model: String.t(),
          size: String.t() | nil
        }

  defstruct [:url, :base64, :revised_prompt, :model, :size]

  @doc """
  Generates an image from a text prompt.

  ## Options

    * `:model` - Model to use (default: "gpt-image-1.5")
    * `:size` - Image size, e.g. "1024x1024", "1536x1024" (default: "1024x1024")
    * `:quality` - Quality level: "standard", "low", "medium", "high" (default: "standard")
    * `:response_format` - "url" or "b64_json" (default: "url")
    * `:n` - Number of images to generate (default: 1)
    * `:background` - Background style: "transparent", "opaque", "auto" (GPT Image only)

  ## Returns

    * `{:ok, image}` - Single image when n=1
    * `{:ok, [images]}` - List of images when n>1
    * `{:error, reason}` - On failure
  """
  @spec generate(String.t(), keyword()) :: {:ok, t() | [t()]} | {:error, term()}
  def generate(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, "gpt-image-1.5")
    provider = provider_for_model(model)

    metadata = %{model: model, provider: provider}

    Telemetry.span(:image_generate, metadata, fn ->
      case provider do
        :openai -> generate_openai(prompt, model, opts)
        :gemini -> generate_gemini(prompt, model, opts)
      end
    end)
  end

  @doc """
  Generates an image and saves it to a file.

  **Note:** This function automatically sets `response_format: "b64_json"` to retrieve
  the image data for saving, regardless of any `:response_format` option passed.

  ## Options

  Same as `generate/2`, plus:

    * `:path` - Path to save the image (required)

  ## Examples

      {:ok, image} = ElixirLLM.Image.generate_and_save("A sunset",
        path: "/tmp/sunset.png"
      )
  """
  @spec generate_and_save(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def generate_and_save(prompt, opts) do
    path = Keyword.fetch!(opts, :path)

    # Force b64_json for saving
    opts = Keyword.put(opts, :response_format, "b64_json")

    with {:ok, image} <- generate(prompt, opts),
         image <- if(is_list(image), do: hd(image), else: image),
         :ok <- save_image(image, path) do
      {:ok, image}
    end
  end

  # Provider detection
  defp provider_for_model("gpt-image-" <> _), do: :openai
  defp provider_for_model("dall-e-" <> _), do: :openai
  defp provider_for_model("gemini-" <> _), do: :gemini
  defp provider_for_model(_), do: :openai

  # ===========================================================================
  # OpenAI Implementation
  # ===========================================================================

  defp generate_openai(prompt, model, opts) do
    base_url = Config.base_url(:openai) || "https://api.openai.com/v1"
    api_key = Config.api_key(:openai)
    timeout = Base.get_timeout(:openai)

    body = %{
      model: model,
      prompt: prompt,
      size: Keyword.get(opts, :size, "1024x1024"),
      quality: Keyword.get(opts, :quality, "standard"),
      response_format: Keyword.get(opts, :response_format, "url"),
      n: Keyword.get(opts, :n, 1)
    }

    # Add optional background parameter for GPT Image models
    body =
      case Keyword.get(opts, :background) do
        nil -> body
        bg -> Map.put(body, :background, bg)
      end

    case Req.post(
           base_url <> "/images/generations",
           json: body,
           headers: Base.bearer_headers(api_key),
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: response}} ->
        images = parse_openai_images(response, model)

        if length(images) == 1 do
          {:ok, hd(images)}
        else
          {:ok, images}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, Base.parse_error(status, body, :openai)}

      {:error, reason} ->
        {:error, ErrorHelpers.from_transport_error(reason, :openai)}
    end
  end

  defp parse_openai_images(response, model) do
    Enum.map(response["data"] || [], fn item ->
      %__MODULE__{
        url: item["url"],
        base64: item["b64_json"],
        revised_prompt: item["revised_prompt"],
        model: model,
        size: nil
      }
    end)
  end

  # ===========================================================================
  # Gemini Implementation (Nano Banana)
  # ===========================================================================

  defp generate_gemini(prompt, model, opts) do
    base_url = Config.base_url(:gemini) || "https://generativelanguage.googleapis.com/v1beta"
    api_key = Config.api_key(:gemini)
    timeout = Base.get_timeout(:gemini)

    body = %{
      contents: [
        %{
          parts: [%{text: prompt}]
        }
      ],
      generationConfig: %{
        responseModalities: ["IMAGE", "TEXT"],
        responseMimeType: Keyword.get(opts, :mime_type, "image/png")
      }
    }

    path = "/models/#{model}:generateContent"

    case Req.post(
           base_url <> path,
           json: body,
           params: [key: api_key],
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, parse_gemini_image(response, model)}

      {:ok, %{status: status, body: body}} ->
        {:error, Base.parse_error(status, body, :gemini)}

      {:error, reason} ->
        {:error, ErrorHelpers.from_transport_error(reason, :gemini)}
    end
  end

  defp parse_gemini_image(response, model) do
    candidate = List.first(response["candidates"] || [])
    parts = get_in(candidate, ["content", "parts"]) || []

    # Find the image part
    image_part = Enum.find(parts, &(&1["inlineData"] != nil))

    %__MODULE__{
      base64: get_in(image_part, ["inlineData", "data"]),
      model: model
    }
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp save_image(%__MODULE__{base64: base64}, path) when is_binary(base64) do
    case :base64.decode(base64) do
      binary when is_binary(binary) ->
        File.write(path, binary)
    end
  rescue
    _ -> {:error, :invalid_base64}
  end

  defp save_image(%__MODULE__{url: url}, path) when is_binary(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: binary}} ->
        File.write(path, binary)

      {:ok, %{status: status}} ->
        {:error, {:download_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_image(_, _), do: {:error, :no_image_data}
end
