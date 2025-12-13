defmodule SocialScribe.HubspotOAuth do
  @moduledoc """
  Lightweight client for HubSpot OAuth token management.
  """

  alias SocialScribe.Accounts.UserCredential

  require Logger

  @token_path "/oauth/v1/token"

  @spec refresh_access_token(UserCredential.t()) :: {:ok, map()} | {:error, {:http_error, term()} | {:api_error, integer(), map() | binary()} | :missing_refresh_token}
  def refresh_access_token(%UserCredential{refresh_token: nil}) do
    Logger.warning("Attempted to refresh HubSpot token without refresh token")
    {:error, :missing_refresh_token}
  end

  def refresh_access_token(%UserCredential{refresh_token: refresh_token}) do
    config = Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)
    client_id = Keyword.fetch!(config, :client_id)
    client_secret = Keyword.fetch!(config, :client_secret)

    body = %{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => client_id,
      "client_secret" => client_secret
    }

    case Tesla.post(client(), @token_path, body, opts: [form_urlencoded: true]) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.warning("HubSpot token refresh failed", status: status, body: body)
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("HubSpot token refresh HTTP error", reason: inspect(reason))
        {:error, {:http_error, reason}}
    end
  end

  defp client do
    base_url = Application.get_env(:ueberauth_hubspot, :base_api_url, "https://api.hubapi.com")

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1,
       decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ])
  end
end
