defmodule SocialScribeWeb.WebhookController do
  use SocialScribeWeb, :controller

  require Logger

  alias SocialScribe.Bots
  alias SocialScribe.Bots.RecallBot
  alias SocialScribe.Meetings
  alias SocialScribe.RecallApi
  alias SocialScribe.Repo
  alias SocialScribe.Workers.AIContentGenerationWorker

  def recall(conn, params) do
    Logger.info("Received Recall.ai webhook: #{inspect(params)}")

    event_type = params["event"]
    data = params["data"] || %{}
    bot_data = data["bot"] || %{}
    bot_id = bot_data["id"]
    recording_data = data["recording"] || %{}
    recording_id = recording_data["id"]
    transcript_data = data["transcript"] || %{}
    transcript_id = transcript_data["id"]

    case event_type do
      "recording.done" ->
        Logger.info("Recording completed for bot: #{bot_id}")
        handle_recording_done(bot_id, data)

      "transcript.done" ->
        Logger.info("Transcript completed for bot: #{bot_id}")
        handle_transcript_done(bot_id, transcript_id, recording_id)

      _ ->
        Logger.info("Unknown event type: #{event_type}")
    end

    conn
    |> put_status(200)
    |> json(%{success: true})
  end

  defp handle_recording_done(bot_id, data) do
    case Repo.get_by(RecallBot, recall_bot_id: bot_id) do
      nil ->
        Logger.warning("RecallBot not found for bot_id: #{bot_id}")

      recall_bot ->
        Logger.info("Recording done for RecallBot: #{recall_bot.id}")

        recording_id = get_in(data, ["recording", "id"])

        if recording_id do
          case create_async_transcript(recording_id) do
            {:ok, transcript_response} ->
              Logger.info("Async transcript job created: #{inspect(transcript_response)}")
              Bots.update_recall_bot(recall_bot, %{status: "transcript_job_created"})

            {:error, reason} ->
              Logger.error("Failed to create async transcript: #{inspect(reason)}")
              Bots.update_recall_bot(recall_bot, %{status: "transcript_job_failed"})
          end
        else
          Logger.warning("No recording ID found in webhook data")
        end
    end
  end

  defp create_async_transcript(recording_id) do
    api_key = Application.fetch_env!(:social_scribe, :recall_api_key)
    recall_region = Application.fetch_env!(:social_scribe, :recall_region)

    base_url = "https://#{recall_region}.recall.ai/api/v1"

    client = Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Token #{api_key}"},
         {"Content-Type", "application/json"},
         {"Accept", "application/json"}
       ]}
    ])

    body = %{
      provider: %{
        recallai_async: %{
          language_code: "en"
        }
      }
    }

    Tesla.post(client, "/recording/#{recording_id}/create_transcript/", body)
  end

  defp handle_transcript_done(bot_id, transcript_id, recording_id) do
    case Repo.get_by(RecallBot, recall_bot_id: bot_id) do
      nil ->
        Logger.warning("RecallBot not found for bot_id: #{bot_id}")

      recall_bot ->
        Logger.info("Transcript done for RecallBot: #{recall_bot.id}")

        case RecallApi.get_bot(bot_id) do
          {:ok, %{body: bot_info}} ->
            case RecallApi.get_transcript(transcript_id) do
              {:ok, %{body: transcript_response}} ->
                Logger.info("Transcript response: #{inspect(transcript_response)}")

                transcript_data = extract_transcript_data(transcript_response)

                # Fetch participant events using the recording ID from webhook
                participants = fetch_participants_from_recording(recording_id)

                # Add participants to bot_info so they can be saved
                bot_info_with_participants = Map.put(bot_info, :meeting_participants, participants)

                case Meetings.create_meeting_from_recall_data(recall_bot, bot_info_with_participants, transcript_data) do
                  {:ok, meeting} ->
                    Logger.info("Meeting created successfully: #{meeting.id}")
                    Bots.update_recall_bot(recall_bot, %{status: "meeting_created"})

                    enqueue_ai_content_generation(meeting.id)

                  {:error, reason} ->
                    Logger.error("Failed to create meeting: #{inspect(reason)}")
                end

              {:error, reason} ->
                Logger.error("Failed to retrieve transcript for bot #{bot_id}: #{inspect(reason)}")
            end

          {:error, reason} ->
            Logger.error("Failed to retrieve bot info for #{bot_id}: #{inspect(reason)}")
        end
    end
  end

  defp extract_transcript_data(transcript_response) do
    cond do
      is_nil(transcript_response) ->
        []

      is_list(transcript_response) ->
        transcript_response

      true ->
        utterances =
          Map.get(transcript_response, :utterances) ||
            Map.get(transcript_response, "utterances")

        cond do
          is_list(utterances) && utterances != [] ->
            utterances

          true ->
            download_url =
              transcript_response
              |> Map.get(:data, %{})
              |> Map.get(:download_url)

            download_url =
              download_url ||
                (transcript_response
                 |> Map.get("data", %{})
                 |> Map.get("download_url"))

            fetch_transcript_from_download(download_url)
        end
    end
  end

  defp fetch_transcript_from_download(nil) do
    Logger.warning("No transcript download URL found in transcript response")
    []
  end

  defp fetch_transcript_from_download(url) do
    case Tesla.get(Tesla.client([]), url) do
      {:ok, %{body: body}} ->
        cond do
          is_list(body) ->
            body

          is_binary(body) ->
            case Jason.decode(body) do
              {:ok, decoded} ->
                decoded

              {:error, decode_error} ->
                Logger.error("Failed to decode transcript JSON: #{inspect(decode_error)}")
                []
            end

          is_map(body) ->
            Map.get(body, :utterances) ||
              Map.get(body, "utterances") ||
              []

          true ->
            []
        end

      {:error, reason} ->
        Logger.error("Failed to fetch transcript download URL: #{inspect(reason)}")
        []
    end
  end

  defp fetch_participants_from_recording(recording_id) do
    case recording_id do
      nil ->
        Logger.info("No recording ID provided")
        []

      id ->
        case RecallApi.get_participant_events(id) do
          {:ok, %{body: participant_response}} ->
            Logger.info("Participant events response: #{inspect(participant_response)}")
            # Extract results array from the response
            results = Map.get(participant_response, :results, []) || Map.get(participant_response, "results", [])

            case results do
              [] ->
                Logger.info("No participant events found")
                []

              [first_result | _] ->
                # Get the participants_download_url from the first result
                participants_url =
                  first_result
                  |> Map.get(:data, %{})
                  |> Map.get(:participants_download_url)

                case participants_url do
                  nil ->
                    Logger.info("No participants download URL found")
                    []

                  url ->
                    # Fetch the actual participants JSON from the download URL
                    case Tesla.get(Tesla.client([]), url) do
                      {:ok, %{body: participants_data}} ->
                        Logger.info("Participants data: #{inspect(participants_data)}")

                        participants_payload =
                          cond do
                            is_map(participants_data) ->
                              participants_data

                            is_binary(participants_data) ->
                              case Jason.decode(participants_data) do
                                {:ok, decoded} -> decoded
                                {:error, decode_error} ->
                                  Logger.error(
                                    "Failed to decode participants JSON: #{inspect(decode_error)}"
                                  )

                                  %{}
                              end

                            true ->
                              %{}
                          end

                        participants_list =
                          cond do
                            is_list(participants_payload) ->
                              participants_payload

                            is_map(participants_payload) &&
                                Map.has_key?(participants_payload, :participants) ->
                              Map.get(participants_payload, :participants)

                            is_map(participants_payload) &&
                                Map.has_key?(participants_payload, "participants") ->
                              Map.get(participants_payload, "participants")

                            true ->
                              []
                          end

                        Enum.map(participants_list, fn p ->
                          %{
                            id: Map.get(p, :id) || Map.get(p, "id"),
                            name: Map.get(p, :name) || Map.get(p, "name") || "Unknown",
                            is_host: Map.get(p, :is_host) || Map.get(p, "is_host") || false
                          }
                        end)

                      {:error, reason} ->
                        Logger.error("Failed to fetch participants from download URL: #{inspect(reason)}")
                        []
                    end
                end
            end

          {:error, reason} ->
            Logger.error("Failed to fetch participant events: #{inspect(reason)}")
            []
        end
    end
  end

  defp enqueue_ai_content_generation(meeting_id) do
    case AIContentGenerationWorker.new(%{"meeting_id" => meeting_id}) |> Oban.insert() do
      {:ok, _job} ->
        Logger.info("AI content generation job enqueued for meeting #{meeting_id}")

      {:error, reason} ->
        Logger.error("Failed to enqueue AI content generation for meeting #{meeting_id}: #{inspect(reason)}")
    end
  end
end
