defmodule SocialScribe.AIContentGenerator do
  @moduledoc "Generates content using Groq-hosted large language models."

  @behaviour SocialScribe.AIContentGeneratorApi

  alias SocialScribe.Meetings
  alias SocialScribe.Automations

  require Logger

  @default_groq_model "llama-3.3-70b-versatile"
  @groq_api_base_url "https://api.groq.com/openai/v1"
  @default_system_prompt "You write concise, professional follow-up emails summarizing meetings and listing action items."
  @field_update_system_prompt "You are an expert CRM assistant who suggests accurate HubSpot contact field updates based on meeting transcripts."

  @impl SocialScribe.AIContentGeneratorApi
  def generate_follow_up_email(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        Based on the following meeting transcript, please draft a concise and professional follow-up email.
        The email should summarize the key discussion points and clearly list any action items assigned, including who is responsible if mentioned.
        Keep the tone friendly and action-oriented.

        #{meeting_prompt}
        """

        call_groq(prompt)
    end
  end

  defp contact_identity_summary(properties) do
    fullname =
      [Map.get(properties, "firstname", ""), Map.get(properties, "lastname", "")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    email = Map.get(properties, "email")

    summary_parts =
      [
        fullname != "" && "Name: #{fullname}" || nil,
        email && "Email: #{email}" || nil
      ]
      |> Enum.reject(&is_nil/1)

    case summary_parts do
      [] -> "(No unique identifiers available)"
      parts -> Enum.join(parts, " | ")
    end
  end

  defp format_prompt_property_value(nil), do: "(empty)"
  defp format_prompt_property_value(""), do: "(empty)"
  defp format_prompt_property_value(value) when is_binary(value), do: String.trim(value)
  defp format_prompt_property_value(value), do: to_string(value)

  @impl SocialScribe.AIContentGeneratorApi
  def generate_automation(automation, meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        #{Automations.generate_prompt_for_automation(automation)}

        #{meeting_prompt}
        """

        call_groq(prompt)
    end
  end

  @impl true
  def suggest_contact_field_updates(%Meetings.Meeting{} = meeting, contact) when is_map(contact) do
    contact_properties = Map.get(contact, "properties", %{})
    identity_summary = contact_identity_summary(contact_properties)

    with {:ok, meeting_prompt} <- Meetings.generate_prompt_for_meeting(meeting) do
      case contact_reference_status(meeting_prompt, contact_properties) do
        :not_referenced ->
          {:ok, []}

        _ ->
          with {:ok, response_text} <-
                 call_groq(
                   build_field_update_prompt(
                     meeting_prompt,
                     normalized_contact_properties(contact_properties),
                     identity_summary
                   ),
                   system_prompt: @field_update_system_prompt
                 ),
               {:ok, updates} <- parse_field_update_response(response_text) do
            filtered = filter_updates(updates, contact_properties, meeting_prompt)
            {:ok, filtered}
          else
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  defp call_groq(prompt_text, opts \\ []) do
    api_key = Application.fetch_env!(:social_scribe, :groq_api_key)
    model = Application.get_env(:social_scribe, :groq_model) || @default_groq_model
    system_prompt = Keyword.get(opts, :system_prompt, @default_system_prompt)

    payload = %{
      model: model,
      messages: [
        %{
          role: "system",
          content: system_prompt
        },
        %{role: "user", content: prompt_text}
      ],
      temperature: 0.5
    }

    Logger.info(
      "Groq request starting: prompt_chars=#{String.length(prompt_text)} model=#{model}"
    )

    case Tesla.post(client(api_key), "chat/completions", payload) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info(
          "Groq response received: status=200 choices=#{length(body["choices"] || [])}"
        )

        text_path = ["choices", Access.at(0), "message", "content"]

        case get_in(body, text_path) do
          nil -> {:error, {:parsing_error, "No text content found in Groq response", body}}
          text_content -> {:ok, text_content}
        end

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("Groq API responded with status #{status}: #{inspect(error_body)}")
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        Logger.error("Groq API HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp build_field_update_prompt(meeting_prompt, contact_properties, identity) do
    property_lines =
      contact_properties
      |> Enum.map(fn {field, value} ->
        "#{field}: #{format_prompt_property_value(value)}"
      end)
      |> Enum.sort()

    contact_overview =
      case property_lines do
        [] -> "(No existing HubSpot values available.)"
        lines -> Enum.join(lines, "\n")
      end

    """
    You are an expert CRM assistant. Extract contact information mentioned in this meeting transcript and suggest CRM field updates.
    Only propose changes that clearly apply to the contact described below. If the transcript references a different person, you must skip the update.

    Contact identity (use for matching transcript references):
    #{identity}

    Return a JSON array. Each element must be an object with keys:
    - "field": the HubSpot contact property name (snake_case string)
    - "new_value": the suggested value as a string (set to null if the field should be cleared)
    - "reason": concise explanation of why this change is recommended (string)
    - "confidence": number between 0 and 1 indicating confidence in this suggestion

    Only include fields that should change. Avoid duplicates. Do not include free-form explanation outside the JSON.

    Current HubSpot contact values:
    #{contact_overview}

    ---
    Meeting context and transcript:
    #{meeting_prompt}
    """
  end

  defp filter_updates(updates, _contact_properties, meeting_prompt) do
    prompt_downcase = String.downcase(meeting_prompt || "")
    prompt_digits = digits_only(meeting_prompt)

    updates
    |> Enum.filter(fn update ->
      field = Map.get(update, "field")
      new_value = Map.get(update, "new_value")

      case field do
        field when field in ["firstname", "lastname"] ->
          value_in_prompt?(new_value, prompt_downcase)

        field when field in ["phone", "mobilephone"] ->
          phone_in_prompt?(new_value, prompt_downcase, prompt_digits)

        _ ->
          true
      end
    end)
  end

  defp contact_reference_status(meeting_prompt, contact_properties) do
    identifiers = contact_identifiers(contact_properties)

    cond do
      identifiers == [] -> :unknown
      identifiers_in_prompt?(meeting_prompt, identifiers) -> :referenced
      true -> :not_referenced
    end
  end

  defp contact_identifiers(properties) do
    [
      Map.get(properties, "firstname"),
      Map.get(properties, "lastname"),
      Map.get(properties, "email")
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp identifiers_in_prompt?(meeting_prompt, identifiers) do
    normalized_prompt = String.downcase(meeting_prompt || "")

    Enum.any?(identifiers, fn identifier ->
      downcased = String.downcase(identifier)
      downcased != "" && String.contains?(normalized_prompt, downcased)
    end)
  end

  defp value_in_prompt?(value, prompt_downcase) when is_binary(value) do
    trimmed = String.trim(value)

    trimmed != "" && String.contains?(prompt_downcase, String.downcase(trimmed))
  end

  defp value_in_prompt?(_value, _prompt_downcase), do: false

  defp phone_in_prompt?(value, prompt_downcase, prompt_digits) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> false
      value_in_prompt?(trimmed, prompt_downcase) -> true
      true ->
        digits = digits_only(trimmed)
        digits != "" && String.contains?(prompt_digits, digits)
    end
  end

  defp phone_in_prompt?(_value, _prompt_downcase, _prompt_digits), do: false

  defp digits_only(nil), do: ""
  defp digits_only(value) when is_binary(value), do: String.replace(value, ~r/\D/, "")
  defp digits_only(value), do: value |> to_string() |> digits_only()

  defp normalized_contact_properties(properties) do
    properties
    |> Enum.map(fn
      {key, value} when is_binary(value) -> {key, String.trim(value)}
      other -> other
    end)
    |> Enum.into(%{})
  end

  defp parse_field_update_response(response_text) do
    response_text
    |> clean_model_response()
    |> Jason.decode()
    |> case do
      {:ok, %{"updates" => updates}} when is_list(updates) ->
        normalize_field_updates(updates)

      {:ok, updates} when is_list(updates) ->
        normalize_field_updates(updates)

      {:ok, other} ->
        {:error, {:unexpected_response_shape, other}}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  defp clean_model_response(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      String.starts_with?(trimmed, "```json") ->
        trimmed
        |> String.trim_leading("```json")
        |> String.trim()
        |> String.replace_suffix("```", "")
        |> String.trim()

      String.starts_with?(trimmed, "```") ->
        trimmed
        |> String.trim_leading("```")
        |> String.trim()
        |> String.replace_suffix("```", "")
        |> String.trim()

      true ->
        trimmed
    end
  end

  defp normalize_field_updates(updates) do
    normalized =
      updates
      |> Enum.map(&normalize_field_update/1)
      |> Enum.reject(&is_nil/1)

    {:ok, normalized}
  end

  defp normalize_field_update(update) when is_map(update) do
    field = Map.get(update, "field") || Map.get(update, :field)
    new_value =
      Map.get(update, "new_value") ||
        Map.get(update, :new_value) ||
        Map.get(update, "value") ||
        Map.get(update, :value)

    reason = Map.get(update, "reason") || Map.get(update, :reason)
    confidence = Map.get(update, "confidence") || Map.get(update, :confidence)

    cond do
      is_nil(field) -> nil
      String.trim(to_string(field)) == "" -> nil
      true ->
        %{
          "field" => to_string(field),
          "new_value" => format_new_value(new_value),
          "reason" => maybe_to_string(reason),
          "confidence" => normalize_confidence(confidence)
        }
    end
  end

  defp normalize_field_update(_), do: nil

  defp format_new_value(nil), do: nil
  defp format_new_value(value) when is_binary(value), do: String.trim(value)
  defp format_new_value(value), do: to_string(value)

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value) when is_binary(value), do: String.trim(value)
  defp maybe_to_string(value), do: to_string(value)

  defp normalize_confidence(nil), do: nil

  defp normalize_confidence(value) when is_number(value) do
    value
    |> max(0.0)
    |> min(1.0)
  end

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> normalize_confidence(parsed)
      :error -> nil
    end
  end

  defp normalize_confidence(_), do: nil

  defp client(api_key) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @groq_api_base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"authorization", "Bearer #{api_key}"},
         {"content-type", "application/json"}
       ]}
    ])
  end
end
