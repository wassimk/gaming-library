require "test_helper"
require "stringio"
require "gaming_library/game_sync"

module GamingLibrary
  class GameSyncTest < Minitest::Test
    def setup
      @output = StringIO.new
    end

    def test_inserts_new_game
      games = [{ name: "New Game", steam_id: 42, playtime_forever: 5 }]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_equal 1, notion.inserted_games.length
      assert_equal "New Game", notion.inserted_games.first[:name]
      assert_includes @output.string, "Added Notion entry"
    end

    def test_skips_games_already_in_notion
      games = [{ name: "Existing", steam_id: 1, playtime_forever: 10 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.inserted_games
    end

    def test_skips_excluded_games_on_insert
      games = [{ name: "Excluded", steam_id: 99, playtime_forever: 0 }]

      steam = StubSteamClient.new(games: games, excluded_ids: [99])
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.inserted_games
    end

    def test_updates_existing_game
      games = [{ name: "Existing", steam_id: 1, playtime_forever: 10 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_equal 1, notion.updated_games.length
      assert_equal "page-1", notion.updated_games.first[:page_id]
      assert_includes @output.string, "Updated Notion for game: Existing"
    end

    def test_skips_excluded_games_on_update
      games = [{ name: "Excluded", steam_id: 99, playtime_forever: 0 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 99 } } },
      ]

      steam = StubSteamClient.new(games: games, excluded_ids: [99])
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.updated_games
    end

    def test_skips_update_when_details_nil
      games = [{ name: "Failed", steam_id: 1, playtime_forever: 0 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games, details: { 1 => nil })
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.updated_games
      assert_includes @output.string, "Game details API call for Failed failed"
    end

    def test_skips_update_when_game_not_in_notion
      games = [{ name: "Missing", steam_id: 999, playtime_forever: 0 }]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.updated_games
      assert_includes @output.string, "Game does not exist in Notion: Missing"
    end

    # --- Stub objects ---

    class StubSteamClient
      attr_reader :owned_games

      def initialize(games:, excluded_ids: [], details: {})
        @owned_games = games
        @excluded_ids = excluded_ids
        @details = details
      end

      def excluded_games
        @owned_games.select { |g| @excluded_ids.include?(g[:steam_id]) }
      end

      def excluded?(game)
        @excluded_ids.include?(game[:steam_id])
      end

      def game_details(appid)
        if @details.key?(appid)
          @details[appid]
        else
          { "publishers" => ["Test"], "developers" => ["Test"],
            "genres" => [{ "description" => "Action" }],
            "release_date" => { "date" => "Jan 1, 2020" },
            "capsule_imagev5" => "http://example.com/logo.jpg" }
        end
      end
    end

    class StubNotionClient
      attr_reader :inserted_games, :updated_games

      def initialize(pages:)
        @pages = pages
        @inserted_games = []
        @updated_games = []
      end

      def fetch_games = @pages

      def games_map(pages)
        pages.map { |p| [p["properties"]["Steam ID"]["number"], p["id"]] }.to_h
      end

      def insert_game(game)
        @inserted_games << game
        "200"
      end

      def update_game(page_id:, game:, details:)
        @updated_games << { page_id: page_id, game: game, details: details }
        {}
      end
    end
  end
end
