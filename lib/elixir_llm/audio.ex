defmodule ElixirLLM.Audio do
  @moduledoc """
  Audio transcription and translation capabilities for ElixirLLM.

  Uses OpenAI's Whisper model for speech-to-text.

  ## Examples

      # Basic transcription
      {:ok, transcript} = ElixirLLM.Audio.transcribe("recording.mp3")
      transcript.text  # => "Hello, world..."

      # With language hint
      {:ok, transcript} = ElixirLLM.Audio.transcribe("spanish.mp3",
        language: "es"
      )

      # With timestamps
      {:ok, transcript} = ElixirLLM.Audio.transcribe("meeting.mp3",
        response_format: "verbose_json",
        timestamp_granularities: ["word", "segment"]
      )
      transcript.words     # => [%{word: "Hello", start: 0.0, end_time: 0.5}, ...]
      transcript.segments  # => [%{text: "Hello world", start: 0.0, end_time: 1.2}, ...]

      # Translate to English
      {:ok, transcript} = ElixirLLM.Audio.translate("french.mp3")

  ## Supported Formats

  Audio files must be in one of these formats:
    * MP3 (.mp3)
    * MP4 (.mp4, .m4a)
    * MPEG (.mpeg)
    * MPGA (.mpga)
    * WAV (.wav)
    * WEBM (.webm)
    * FLAC (.flac)

  Maximum file size is 25MB.
  """

  alias ElixirLLM.{Config, Telemetry}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  defmodule Transcript do
    @moduledoc """
    Represents an audio transcription result.
    """

    @type word :: %{word: String.t(), start: float(), end_time: float()}
    @type segment :: %{text: String.t(), start: float(), end_time: float()}

    @type t :: %__MODULE__{
            text: String.t(),
            language: String.t() | nil,
            duration: float() | nil,
            words: [word()] | nil,
            segments: [segment()] | nil
          }

    defstruct [:text, :language, :duration, :words, :segments]
  end

  @doc """
  Transcribes audio to text using Whisper.

  ## Options

    * `:model` - Model to use (default: "whisper-1")
    * `:language` - Language code (e.g., "en", "es", "fr") for better accuracy
    * `:prompt` - Optional text to guide the model's style
    * `:response_format` - "json", "text", "srt", "verbose_json", "vtt" (default: "json")
    * `:temperature` - Sampling temperature 0-1 (default: 0)
    * `:timestamp_granularities` - ["word"] and/or ["segment"] for timestamps

  ## Examples

      {:ok, transcript} = ElixirLLM.Audio.transcribe("meeting.mp3")
      {:ok, transcript} = ElixirLLM.Audio.transcribe("call.wav", language: "en")
  """
  @spec transcribe(String.t(), keyword()) :: {:ok, Transcript.t()} | {:error, term()}
  def transcribe(file_path, opts \\ []) do
    model = Keyword.get(opts, :model, "whisper-1")
    metadata = %{model: model, operation: :transcribe}

    Telemetry.span(:audio_transcribe, metadata, fn ->
      transcribe_openai(file_path, model, opts)
    end)
  end

  @doc """
  Translates audio to English text.

  Takes audio in any supported language and transcribes it to English.

  ## Options

  Same as `transcribe/2`.

  ## Examples

      {:ok, transcript} = ElixirLLM.Audio.translate("french_meeting.mp3")
      # transcript.text is in English regardless of input language
  """
  @spec translate(String.t(), keyword()) :: {:ok, Transcript.t()} | {:error, term()}
  def translate(file_path, opts \\ []) do
    model = Keyword.get(opts, :model, "whisper-1")
    metadata = %{model: model, operation: :translate}

    Telemetry.span(:audio_translate, metadata, fn ->
      translate_openai(file_path, model, opts)
    end)
  end

  # ===========================================================================
  # OpenAI Implementation
  # ===========================================================================

  defp transcribe_openai(file_path, model, opts) do
    make_audio_request("/audio/transcriptions", file_path, model, opts)
  end

  defp translate_openai(file_path, model, opts) do
    make_audio_request("/audio/translations", file_path, model, opts)
  end

  defp make_audio_request(endpoint, file_path, model, opts) do
    base_url = Config.base_url(:openai) || "https://api.openai.com/v1"
    api_key = Config.api_key(:openai)
    timeout = Base.get_timeout(:openai)

    # Read the file
    case File.read(file_path) do
      {:ok, file_content} ->
        form_data = build_form_data(file_path, file_content, model, opts)

        case Req.post(
               base_url <> endpoint,
               form_multipart: form_data,
               headers: Base.bearer_headers(api_key),
               receive_timeout: timeout
             ) do
          {:ok, %{status: 200, body: response}} ->
            {:ok, parse_transcript(response)}

          {:ok, %{status: status, body: body}} ->
            {:error, Base.parse_error(status, body, :openai)}

          {:error, reason} ->
            {:error, ErrorHelpers.from_transport_error(reason, :openai)}
        end

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  defp build_form_data(file_path, file_content, model, opts) do
    filename = Path.basename(file_path)
    content_type = mime_type(file_path)

    form = [
      {:file, file_content, [filename: filename, content_type: content_type]},
      {:model, model}
    ]

    form
    |> maybe_add_form(:language, Keyword.get(opts, :language))
    |> maybe_add_form(:prompt, Keyword.get(opts, :prompt))
    |> maybe_add_form(:response_format, Keyword.get(opts, :response_format))
    |> maybe_add_form(:temperature, Keyword.get(opts, :temperature))
    |> maybe_add_timestamp_granularities(Keyword.get(opts, :timestamp_granularities))
  end

  defp maybe_add_form(form, _key, nil), do: form
  defp maybe_add_form(form, key, value), do: form ++ [{key, to_string(value)}]

  defp maybe_add_timestamp_granularities(form, nil), do: form

  defp maybe_add_timestamp_granularities(form, granularities) when is_list(granularities) do
    Enum.reduce(granularities, form, fn g, acc ->
      acc ++ [{:"timestamp_granularities[]", g}]
    end)
  end

  defp parse_transcript(response) when is_binary(response) do
    # Plain text response
    %Transcript{text: response}
  end

  defp parse_transcript(response) when is_map(response) do
    %Transcript{
      text: response["text"],
      language: response["language"],
      duration: response["duration"],
      words: parse_words(response["words"]),
      segments: parse_segments(response["segments"])
    }
  end

  defp parse_words(nil), do: nil

  defp parse_words(words) when is_list(words) do
    Enum.map(words, fn w ->
      %{
        word: w["word"],
        start: w["start"],
        end_time: w["end"]
      }
    end)
  end

  defp parse_segments(nil), do: nil

  defp parse_segments(segments) when is_list(segments) do
    Enum.map(segments, fn s ->
      %{
        text: s["text"],
        start: s["start"],
        end_time: s["end"]
      }
    end)
  end

  @mime_types %{
    ".mp3" => "audio/mpeg",
    ".mp4" => "audio/mp4",
    ".m4a" => "audio/mp4",
    ".mpeg" => "audio/mpeg",
    ".mpga" => "audio/mpeg",
    ".wav" => "audio/wav",
    ".webm" => "audio/webm",
    ".flac" => "audio/flac"
  }

  defp mime_type(path) do
    ext = path |> Path.extname() |> String.downcase()
    Map.get(@mime_types, ext, "application/octet-stream")
  end
end
