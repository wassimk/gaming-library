require "test_helper"
require "gaming_library/steam_client"

module GamingLibrary
  class SteamClientTest < Minitest::Test
    def test_owned_games_parses_response
      fake_response = {
        "response" => {
          "games" => [
            {
              "appid" => 123,
              "name" => "Test Game",
              "playtime_forever" => 60,
              "rtime_last_played" => 1_700_000_000,
              "img_icon_url" => "abc123",
            },
            {
              "appid" => 456,
              "name" => "Never Played",
              "playtime_forever" => 0,
              "rtime_last_played" => 0,
              "img_icon_url" => "def456",
            },
          ],
        },
      }

      client = build_client(owned_games_response: fake_response)
      games = client.owned_games

      assert_equal 2, games.length

      assert_equal "Test Game", games[0][:name]
      assert_equal 60, games[0][:playtime_forever]
      assert_equal 123, games[0][:steam_id]
      assert_instance_of Time, games[0][:last_played_date]
      assert_includes games[0][:icon_url], "abc123"

      assert_equal "Never Played", games[1][:name]
      assert_nil games[1][:last_played_date]
    end

    def test_owned_games_memoizes
      client = build_client(owned_games_response: { "response" => { "games" => [] } })

      first = client.owned_games
      second = client.owned_games
      assert_same first, second
    end

    def test_game_details_returns_data_on_success
      details_response = {
        "123" => {
          "success" => true,
          "data" => { "name" => "Test", "publishers" => ["Valve"] },
        },
      }

      client = build_client(game_details_response: details_response)
      details = client.game_details(123)

      assert_equal "Test", details["name"]
      assert_equal ["Valve"], details["publishers"]
    end

    def test_game_details_returns_nil_on_failure
      details_response = { "123" => { "success" => false } }

      client = build_client(game_details_response: details_response)
      assert_nil client.game_details(123)
    end

    def test_excluded_checks_against_ids
      client = build_client(excluded_game_ids: [999])

      assert client.excluded?({ steam_id: 999 })
      refute client.excluded?({ steam_id: 100 })
    end

    private

    def build_client(owned_games_response: nil, game_details_response: nil, excluded_game_ids: [])
      TestSteamClient.new(
        api_key: "test_key",
        user_id: "test_user",
        excluded_game_ids: excluded_game_ids,
        owned_games_response: owned_games_response,
        game_details_response: game_details_response,
      )
    end

    class TestSteamClient < SteamClient
      def initialize(owned_games_response: nil, game_details_response: nil, **kwargs)
        super(**kwargs)
        @fake_owned_games_response = owned_games_response
        @fake_game_details_response = game_details_response
      end

      private

      def fetch_owned_games
        @fake_owned_games_response
      end

      def fetch_game_details(_appid)
        @fake_game_details_response
      end
    end
  end
end
