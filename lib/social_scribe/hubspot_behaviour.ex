defmodule SocialScribe.HubspotBehaviour do
  @moduledoc """
  Behaviour for HubSpot API interactions to enable mocking in tests.
  """

  @callback search_contacts(String.t(), String.t(), keyword()) ::
              {:ok, list()} | {:error, {:http_error, term()} | {:api_error, integer(), map() | binary()}}

  @callback get_contact(String.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, {:http_error, term()} | {:api_error, integer(), map() | binary()} | :invalid_contact_id}

  @callback update_contact(String.t(), String.t(), map()) ::
              {:ok, map()} | {:error, {:http_error, term()} | {:api_error, integer(), map() | binary()} | :invalid_contact_id | :empty_properties}
end
