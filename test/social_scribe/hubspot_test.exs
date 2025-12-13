defmodule SocialScribe.HubspotTest do
  use ExUnit.Case, async: true

  import Mox

  alias SocialScribe.Hubspot

  setup :verify_on_exit!

  setup do
    Tesla.Mock.mock_global(fn env -> env end)
    :ok
  end

  describe "search_contacts/3" do
    test "returns empty list when query is nil" do
      assert {:ok, []} = Hubspot.search_contacts("token", nil)
    end

    test "returns empty list when query is empty string" do
      assert {:ok, []} = Hubspot.search_contacts("token", "")
    end

    test "returns list of contacts on successful search" do
      # Mock Tesla HTTP client
      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.hubapi.com/crm/v3/objects/contacts/search"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "results" => [
                %{
                  "id" => "123",
                  "properties" => %{
                    "firstname" => "John",
                    "lastname" => "Doe",
                    "email" => "john@example.com"
                  }
                },
                %{
                  "id" => "456",
                  "properties" => %{
                    "firstname" => "Jane",
                    "lastname" => "Smith",
                    "email" => "jane@example.com"
                  }
                }
              ]
            }
          }
      end)

      assert {:ok, results} = Hubspot.search_contacts("test_token", "john")
      assert length(results) == 2
      assert hd(results)["id"] == "123"
      assert hd(results)["properties"]["firstname"] == "John"
    end

    test "returns error on API failure" do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 401,
            body: %{"message" => "Unauthorized"}
          }
      end)

      assert {:error, {:api_error, 401, _body}} = Hubspot.search_contacts("invalid_token", "john")
    end

    test "returns error on HTTP failure" do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          {:error, :timeout}
      end)

      assert {:error, {:http_error, :timeout}} = Hubspot.search_contacts("token", "john")
    end

    test "respects custom limit parameter" do
      Tesla.Mock.mock(fn
        %{method: :post, body: body} when is_binary(body) ->
          decoded = Jason.decode!(body)
          assert decoded["limit"] == 5

          %Tesla.Env{
            status: 200,
            body: %{"results" => []}
          }
      end)

      Hubspot.search_contacts("token", "test", limit: 5)
    end

    test "respects custom properties parameter" do
      Tesla.Mock.mock(fn
        %{method: :post, body: body} when is_binary(body) ->
          decoded = Jason.decode!(body)
          assert decoded["properties"] == ["email", "phone"]

          %Tesla.Env{
            status: 200,
            body: %{"results" => []}
          }
      end)

      Hubspot.search_contacts("token", "test", properties: ["email", "phone"])
    end
  end

  describe "get_contact/3" do
    test "returns error when contact_id is nil" do
      assert {:error, :invalid_contact_id} = Hubspot.get_contact("token", nil)
    end

    test "returns error when contact_id is empty string" do
      assert {:error, :invalid_contact_id} = Hubspot.get_contact("token", "")
    end

    test "returns contact details on success" do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://api.hubapi.com/crm/v3/objects/contacts/123"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "id" => "123",
              "properties" => %{
                "firstname" => "John",
                "lastname" => "Doe",
                "email" => "john@example.com",
                "phone" => "555-1234"
              }
            }
          }
      end)

      assert {:ok, contact} = Hubspot.get_contact("token", "123")
      assert contact["id"] == "123"
      assert contact["properties"]["firstname"] == "John"
    end

    test "returns error on API failure" do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 404,
            body: %{"message" => "Contact not found"}
          }
      end)

      assert {:error, {:api_error, 404, _body}} = Hubspot.get_contact("token", "999")
    end

    test "returns error on HTTP failure" do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          {:error, :econnrefused}
      end)

      assert {:error, {:http_error, :econnrefused}} = Hubspot.get_contact("token", "123")
    end
  end

  describe "update_contact/3" do
    test "returns error when contact_id is nil" do
      assert {:error, :invalid_contact_id} = Hubspot.update_contact("token", nil, %{"firstname" => "John"})
    end

    test "returns error when contact_id is empty string" do
      assert {:error, :invalid_contact_id} = Hubspot.update_contact("token", "", %{"firstname" => "John"})
    end

    test "returns error when properties is empty map" do
      assert {:error, :empty_properties} = Hubspot.update_contact("token", "123", %{})
    end

    test "successfully updates contact" do
      Tesla.Mock.mock(fn
        %{method: :patch, url: "https://api.hubapi.com/crm/v3/objects/contacts/123", body: body} when is_binary(body) ->
          decoded = Jason.decode!(body)
          assert decoded["properties"]["firstname"] == "John"
          assert decoded["properties"]["lastname"] == "Updated"

          %Tesla.Env{
            status: 200,
            body: %{
              "id" => "123",
              "properties" => %{
                "firstname" => "John",
                "lastname" => "Updated"
              }
            }
          }
      end)

      properties = %{"firstname" => "John", "lastname" => "Updated"}
      assert {:ok, result} = Hubspot.update_contact("token", "123", properties)
      assert result["id"] == "123"
      assert result["properties"]["lastname"] == "Updated"
    end

    test "returns error on API failure" do
      Tesla.Mock.mock(fn
        %{method: :patch} ->
          %Tesla.Env{
            status: 400,
            body: %{"message" => "Invalid properties"}
          }
      end)

      assert {:error, {:api_error, 400, _body}} =
        Hubspot.update_contact("token", "123", %{"invalid_field" => "value"})
    end

    test "returns error on HTTP failure" do
      Tesla.Mock.mock(fn
        %{method: :patch} ->
          {:error, :network_error}
      end)

      assert {:error, {:http_error, :network_error}} =
        Hubspot.update_contact("token", "123", %{"firstname" => "John"})
    end

    test "sends correct authorization header" do
      Tesla.Mock.mock(fn
        %{headers: headers} = _env ->
          assert {"Authorization", "Bearer test_token_123"} in headers

          %Tesla.Env{
            status: 200,
            body: %{"id" => "123", "properties" => %{}}
          }
      end)

      Hubspot.update_contact("test_token_123", "123", %{"firstname" => "Test"})
    end
  end
end
