defmodule SocialScribe.Hubspot do
  @moduledoc """
  Minimal HubSpot API client for SocialScribe.
  """

  @behaviour SocialScribe.HubspotBehaviour

  require Logger

  @default_properties ["firstname", "lastname", "email"]
  @contact_detail_properties [
    "firstname",
    "lastname",
    "email",
    "phone",
    "mobilephone",
    "company",
    "jobtitle",
    "website",
    "city",
    "state",
    "country",
    "lifecyclestage"
  ]
  @default_limit 10

  @spec search_contacts(String.t(), String.t(), keyword()) ::
          {:ok, list()} | {:error, {:http_error, term()} | {:api_error, integer(), map() | binary()}}
  def search_contacts(token, query, opts \\ [])
  def search_contacts(_token, query, _opts) when query in [nil, ""], do: {:ok, []}

  def search_contacts(token, query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    properties = Keyword.get(opts, :properties, @default_properties)

    body = %{
      query: query,
      limit: limit,
      properties: properties
    }

    case Tesla.post(client(token), "/crm/v3/objects/contacts/search", body) do
      {:ok, %Tesla.Env{status: 200, body: %{"results" => results}}} ->
        {:ok, results}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.warning("HubSpot contact search failed", status: status, body: body)
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("HubSpot contact search HTTP error", reason: inspect(reason))
        {:error, {:http_error, reason}}
    end
  end

  @spec get_contact(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, {:http_error, term()} | {:api_error, integer(), map() | binary()} | :invalid_contact_id}
  def get_contact(token, contact_id, opts \\ [])
  def get_contact(_token, contact_id, _opts) when contact_id in [nil, ""], do: {:error, :invalid_contact_id}

  def get_contact(token, contact_id, opts) do
    properties = Keyword.get(opts, :properties, @contact_detail_properties)

    query_params = Enum.map(properties, fn property -> {"properties", property} end)

    case Tesla.get(client(token), "/crm/v3/objects/contacts/#{contact_id}", query: query_params) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.warning("HubSpot contact fetch failed", status: status, body: body)
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("HubSpot contact fetch HTTP error", reason: inspect(reason))
        {:error, {:http_error, reason}}
    end
  end

  @spec update_contact(String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, {:http_error, term()} | {:api_error, integer(), map() | binary()} | :invalid_contact_id | :empty_properties}
  def update_contact(_token, contact_id, _properties) when contact_id in [nil, ""], do: {:error, :invalid_contact_id}
  def update_contact(_token, _contact_id, properties) when properties == %{}, do: {:error, :empty_properties}

  def update_contact(token, contact_id, properties) when is_map(properties) do
    body = %{
      properties: properties
    }

    case Tesla.patch(client(token), "/crm/v3/objects/contacts/#{contact_id}", body) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.warning("HubSpot contact update failed", status: status, body: body)
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("HubSpot contact update HTTP error", reason: inspect(reason))
        {:error, {:http_error, reason}}
    end
  end

  defp client(token) do
    headers = [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url()},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, headers}
    ])
  end

  defp base_url do
    Application.get_env(:ueberauth_hubspot, :base_api_url, "https://api.hubapi.com")
  end
end
