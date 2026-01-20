defmodule ElixirLLM.Content do
  @moduledoc """
  Handles multi-modal content (images, audio, PDFs, etc.) for LLM messages.

  ## Example

      # Image from file
      content = ElixirLLM.Content.image("photo.jpg")

      # Image from URL
      content = ElixirLLM.Content.image_url("https://example.com/image.png")

      # Image from base64
      content = ElixirLLM.Content.image_base64(base64_data, "image/png")

      # Audio file
      content = ElixirLLM.Content.audio("recording.mp3")

      # PDF document
      content = ElixirLLM.Content.pdf("document.pdf")

      # Use with ask
      {:ok, response, chat} = ElixirLLM.ask(chat, "What's in this image?", with: content)
  """

  @type content_type :: :image | :audio | :video | :pdf | :file
  @type source_type :: :file | :url | :base64

  @type t :: %__MODULE__{
          type: content_type(),
          source: source_type(),
          data: binary() | String.t(),
          media_type: String.t() | nil,
          filename: String.t() | nil
        }

  defstruct [:type, :source, :data, :media_type, :filename]

  @image_extensions ~w(.jpg .jpeg .png .gif .webp .bmp)
  @audio_extensions ~w(.mp3 .wav .ogg .m4a .flac .webm)
  @video_extensions ~w(.mp4 .avi .mov .webm .mkv)

  @doc """
  Creates an image content from a file path.
  """
  @spec image(String.t()) :: t()
  def image(path) when is_binary(path) do
    %__MODULE__{
      type: :image,
      source: :file,
      data: path,
      media_type: media_type_from_path(path),
      filename: Path.basename(path)
    }
  end

  @doc """
  Creates an image content from a URL.
  """
  @spec image_url(String.t()) :: t()
  def image_url(url) when is_binary(url) do
    %__MODULE__{
      type: :image,
      source: :url,
      data: url,
      media_type: media_type_from_path(url)
    }
  end

  @doc """
  Creates an image content from base64 encoded data.
  """
  @spec image_base64(String.t(), String.t()) :: t()
  def image_base64(data, media_type \\ "image/png") do
    %__MODULE__{
      type: :image,
      source: :base64,
      data: data,
      media_type: media_type
    }
  end

  @doc """
  Creates an audio content from a file path.
  """
  @spec audio(String.t()) :: t()
  def audio(path) when is_binary(path) do
    %__MODULE__{
      type: :audio,
      source: :file,
      data: path,
      media_type: media_type_from_path(path),
      filename: Path.basename(path)
    }
  end

  @doc """
  Creates a PDF content from a file path.
  """
  @spec pdf(String.t()) :: t()
  def pdf(path) when is_binary(path) do
    %__MODULE__{
      type: :pdf,
      source: :file,
      data: path,
      media_type: "application/pdf",
      filename: Path.basename(path)
    }
  end

  @doc """
  Creates content from a file path, auto-detecting the type.
  """
  @spec from_file(String.t()) :: t()
  def from_file(path) when is_binary(path) do
    ext = Path.extname(path) |> String.downcase()

    cond do
      ext in @image_extensions -> image(path)
      ext in @audio_extensions -> audio(path)
      ext in @video_extensions -> video(path)
      ext == ".pdf" -> pdf(path)
      true -> file(path)
    end
  end

  @doc """
  Creates a video content from a file path.
  """
  @spec video(String.t()) :: t()
  def video(path) when is_binary(path) do
    %__MODULE__{
      type: :video,
      source: :file,
      data: path,
      media_type: media_type_from_path(path),
      filename: Path.basename(path)
    }
  end

  @doc """
  Creates a generic file content.
  """
  @spec file(String.t()) :: t()
  def file(path) when is_binary(path) do
    %__MODULE__{
      type: :file,
      source: :file,
      data: path,
      media_type: media_type_from_path(path),
      filename: Path.basename(path)
    }
  end

  @doc """
  Converts content to provider-specific format for OpenAI.
  """
  @spec to_openai(t()) :: map()
  def to_openai(%__MODULE__{type: :image, source: :url, data: url}) do
    %{type: "image_url", image_url: %{url: url}}
  end

  def to_openai(%__MODULE__{type: :image, source: :base64, data: data, media_type: media_type}) do
    %{type: "image_url", image_url: %{url: "data:#{media_type};base64,#{data}"}}
  end

  def to_openai(%__MODULE__{type: :image, source: :file, data: path, media_type: media_type}) do
    base64 = path |> File.read!() |> Base.encode64()
    %{type: "image_url", image_url: %{url: "data:#{media_type};base64,#{base64}"}}
  end

  def to_openai(%__MODULE__{type: :audio, source: :file, data: path}) do
    base64 = path |> File.read!() |> Base.encode64()
    media_type = media_type_from_path(path)
    %{type: "input_audio", input_audio: %{data: base64, format: audio_format(media_type)}}
  end

  @doc """
  Converts content to provider-specific format for Anthropic.
  """
  @spec to_anthropic(t()) :: map()
  def to_anthropic(%__MODULE__{type: :image, source: :url, data: url}) do
    %{type: "image", source: %{type: "url", url: url}}
  end

  def to_anthropic(%__MODULE__{type: :image, source: :base64, data: data, media_type: media_type}) do
    %{type: "image", source: %{type: "base64", media_type: media_type, data: data}}
  end

  def to_anthropic(%__MODULE__{type: :image, source: :file, data: path, media_type: media_type}) do
    base64 = path |> File.read!() |> Base.encode64()
    %{type: "image", source: %{type: "base64", media_type: media_type, data: base64}}
  end

  def to_anthropic(%__MODULE__{type: :pdf, source: :file, data: path}) do
    base64 = path |> File.read!() |> Base.encode64()

    %{
      type: "document",
      source: %{type: "base64", media_type: "application/pdf", data: base64}
    }
  end

  # Private helpers

  defp media_type_from_path(path) do
    ext = Path.extname(path) |> String.downcase()

    case ext do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".bmp" -> "image/bmp"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".ogg" -> "audio/ogg"
      ".m4a" -> "audio/mp4"
      ".flac" -> "audio/flac"
      ".webm" -> "video/webm"
      ".mp4" -> "video/mp4"
      ".avi" -> "video/x-msvideo"
      ".mov" -> "video/quicktime"
      ".pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end

  defp audio_format("audio/mpeg"), do: "mp3"
  defp audio_format("audio/wav"), do: "wav"
  defp audio_format("audio/ogg"), do: "ogg"
  defp audio_format(_), do: "mp3"
end
