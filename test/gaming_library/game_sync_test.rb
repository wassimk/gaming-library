require "test_helper"
require "stringio"
require "gaming_library/game_sync"

module GamingLibrary
  class GameSyncTest < Minitest::Test
    def setup
      @output = StringIO.new
    end

    # --- Insert tests ---

    def test_inserts_new_game
      games = [{ name: "New Game", steam_id: 42, playtime_forever: 5, playtime_2weeks: 0 }]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_equal 1, notion.inserted_games.length
      assert_equal "New Game", notion.inserted_games.first[:name]
      assert_includes @output.string, "Added Notion entry"
    end

    def test_inserts_new_game_and_backfills_metadata
      games = [{ name: "New Game", steam_id: 42, playtime_forever: 5, playtime_2weeks: 0 }]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [], backfill_after_insert: true)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_equal 1, notion.inserted_games.length
      assert_equal 1, notion.updated_games.length
      assert_includes @output.string, "Backfilled metadata for game: New Game"
    end

    def test_skips_games_already_in_notion
      games = [{ name: "Existing", steam_id: 1, playtime_forever: 10, playtime_2weeks: 0 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.inserted_games
    end

    def test_skips_excluded_games_on_insert
      games = [{ name: "Excluded", steam_id: 99, playtime_forever: 0, playtime_2weeks: 0 }]

      steam = StubSteamClient.new(games: games, excluded_ids: [99])
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.inserted_games
    end

    # --- Full sync update tests ---

    def test_full_sync_updates_existing_game_with_details
      games = [{ name: "Existing", steam_id: 1, playtime_forever: 10, playtime_2weeks: 0 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_equal 1, notion.updated_games.length
      assert_equal "page-1", notion.updated_games.first[:page_id]
      assert_includes @output.string, "Updated Notion for game: Existing"
    end

    def test_full_sync_updates_all_games_regardless_of_playtime
      games = [
        { name: "Played Recently", steam_id: 1, playtime_forever: 100, playtime_2weeks: 30 },
        { name: "Not Played Recently", steam_id: 2, playtime_forever: 50, playtime_2weeks: 0 },
      ]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
        { "id" => "page-2", "properties" => { "Steam ID" => { "number" => 2 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_equal 2, notion.updated_games.length
    end

    def test_full_sync_skips_excluded_games_on_update
      games = [{ name: "Excluded", steam_id: 99, playtime_forever: 0, playtime_2weeks: 0 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 99 } } },
      ]

      steam = StubSteamClient.new(games: games, excluded_ids: [99])
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_empty notion.updated_games
    end

    def test_full_sync_skips_update_when_details_nil
      games = [{ name: "Failed", steam_id: 1, playtime_forever: 0, playtime_2weeks: 0 }]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games, details: { 1 => nil })
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_empty notion.updated_games
      assert_includes @output.string, "Game details API call for Failed failed"
    end

    # --- Incremental sync update tests ---

    def test_incremental_skips_games_with_no_recent_playtime
      games = [
        { name: "Not Played", steam_id: 1, playtime_forever: 50, playtime_2weeks: 0 },
      ]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.updated_games
      assert_empty notion.playtime_updated_games
      assert_includes @output.string, "Skipping Not Played (no recent playtime)"
    end

    def test_incremental_updates_games_with_recent_playtime
      games = [
        { name: "Playing Now", steam_id: 1, playtime_forever: 100, playtime_2weeks: 25,
          last_played_date: Time.new(2024, 1, 15) },
      ]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.updated_games
      assert_equal 1, notion.playtime_updated_games.length
      assert_equal "page-1", notion.playtime_updated_games.first[:page_id]
      assert_includes @output.string, "Updated playtime for game: Playing Now"
    end

    def test_incremental_only_updates_recently_played_games
      games = [
        { name: "Active", steam_id: 1, playtime_forever: 100, playtime_2weeks: 20 },
        { name: "Idle", steam_id: 2, playtime_forever: 50, playtime_2weeks: 0 },
        { name: "Also Active", steam_id: 3, playtime_forever: 200, playtime_2weeks: 5 },
      ]
      notion_pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 1 } } },
        { "id" => "page-2", "properties" => { "Steam ID" => { "number" => 2 } } },
        { "id" => "page-3", "properties" => { "Steam ID" => { "number" => 3 } } },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_equal 2, notion.playtime_updated_games.length
      assert_equal ["page-1", "page-3"], notion.playtime_updated_games.map { |g| g[:page_id] }
    end

    def test_incremental_skips_update_when_game_not_in_notion
      games = [{ name: "Missing", steam_id: 999, playtime_forever: 0, playtime_2weeks: 10 }]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.playtime_updated_games
      assert_includes @output.string, "Game does not exist in Notion: Missing"
    end

    def test_log_summary_shows_incremental_mode
      games = []
      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_includes @output.string, "Sync mode: incremental"
    end

    def test_log_summary_shows_full_mode
      games = []
      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_includes @output.string, "Sync mode: full"
    end

    # --- Stub objects ---

    class StubSteamClient
      attr_reader :owned_games

      def initialize(games:, excluded_ids: [], details: {})
        @owned_games = games
        @excluded_ids = excluded_ids
        @details = details
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
      attr_reader :inserted_games, :updated_games, :playtime_updated_games

      def initialize(pages:, backfill_after_insert: false)
        @pages = pages
        @backfill_after_insert = backfill_after_insert
        @inserted_games = []
        @updated_games = []
        @playtime_updated_games = []
      end

      def fetch_games
        @pages
      end

      def games_map(pages)
        pages.map { |p| [p["properties"]["Steam ID"]["number"], p["id"]] }.to_h
      end

      def insert_game(game)
        @inserted_games << game
        if @backfill_after_insert
          @pages << {
            "id" => "new-page-#{game[:steam_id]}",
            "properties" => { "Steam ID" => { "number" => game[:steam_id] } },
          }
        end
        "200"
      end

      def update_game(page_id:, game:, details:)
        @updated_games << { page_id: page_id, game: game, details: details }
        {}
      end

      def update_game_playtime(page_id:, game:)
        @playtime_updated_games << { page_id: page_id, game: game }
        {}
      end
    end
  end
end
