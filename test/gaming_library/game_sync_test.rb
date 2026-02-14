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
      notion_pages = [notion_page(steam_id: 1, page_id: "page-1", playtime: 10)]

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

    def test_skips_demo_games_on_insert
      games = [{ name: "Stellar Blade\u2122 Demo", steam_id: 100, playtime_forever: 0, playtime_2weeks: 0 }]

      steam = StubSteamClient.new(games: games, details: {
        100 => { "type" => "demo", "publishers" => ["Test"] },
      })
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.inserted_games
      assert_includes @output.string, "Skipping Stellar Blade\u2122 Demo (demo)"
    end

    # --- Full sync update tests ---

    def test_full_sync_updates_existing_game_with_details
      games = [{ name: "Existing", steam_id: 1, playtime_forever: 10, playtime_2weeks: 0 }]
      notion_pages = [notion_page(steam_id: 1, page_id: "page-1", playtime: 10)]

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
        notion_page(steam_id: 1, page_id: "page-1", playtime: 100),
        notion_page(steam_id: 2, page_id: "page-2", playtime: 50),
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_equal 2, notion.updated_games.length
    end

    def test_full_sync_skips_demo_games
      games = [{ name: "Stellar Blade\u2122 Demo", steam_id: 100, playtime_forever: 5, playtime_2weeks: 0 }]
      notion_pages = [notion_page(steam_id: 100, page_id: "page-1", playtime: 5)]

      steam = StubSteamClient.new(games: games, details: {
        100 => { "type" => "demo", "publishers" => ["Test"], "developers" => ["Test"] },
      })
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_empty notion.updated_games
      assert_includes @output.string, "Skipping Stellar Blade\u2122 Demo (demo)"
    end

    def test_full_sync_skips_excluded_games_on_update
      games = [{ name: "Excluded", steam_id: 99, playtime_forever: 0, playtime_2weeks: 0 }]
      notion_pages = [notion_page(steam_id: 99, page_id: "page-1", playtime: 0)]

      steam = StubSteamClient.new(games: games, excluded_ids: [99])
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, full_sync: true, output: @output).call

      assert_empty notion.updated_games
    end

    def test_full_sync_skips_update_when_details_nil
      games = [{ name: "Failed", steam_id: 1, playtime_forever: 0, playtime_2weeks: 0 }]
      notion_pages = [notion_page(steam_id: 1, page_id: "page-1", playtime: 0)]

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
      notion_pages = [notion_page(steam_id: 1, page_id: "page-1", playtime: 50)]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.updated_games
      assert_empty notion.playtime_updated_games
      assert_includes @output.string, "Skipping Not Played (no recent playtime)"
    end

    def test_incremental_updates_games_with_higher_playtime
      games = [
        { name: "Playing Now", steam_id: 1, playtime_forever: 100, playtime_2weeks: 25,
          last_played_date: Time.new(2024, 1, 15) },
      ]
      notion_pages = [notion_page(steam_id: 1, page_id: "page-1", playtime: 75)]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.updated_games
      assert_equal 1, notion.playtime_updated_games.length
      assert_equal "page-1", notion.playtime_updated_games.first[:page_id]
      assert_includes @output.string, "Updated playtime for game: Playing Now"
    end

    def test_incremental_skips_when_playtime_unchanged
      games = [
        { name: "Same Playtime", steam_id: 1, playtime_forever: 100, playtime_2weeks: 5,
          last_played_date: Time.new(2024, 1, 15) },
      ]
      notion_pages = [
        notion_page(steam_id: 1, page_id: "page-1", playtime: 100, last_played_date: "2024-01-15"),
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.playtime_updated_games
      assert_includes @output.string, "Skipping Same Playtime (no changes)"
    end

    def test_incremental_skips_when_notion_playtime_is_higher
      games = [
        { name: "Manual Override", steam_id: 1, playtime_forever: 50, playtime_2weeks: 10,
          last_played_date: Time.new(2024, 1, 15) },
      ]
      notion_pages = [
        notion_page(steam_id: 1, page_id: "page-1", playtime: 200, last_played_date: "2024-01-15"),
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_empty notion.playtime_updated_games
      assert_includes @output.string, "Skipping Manual Override (no changes)"
    end

    def test_incremental_updates_when_last_played_date_changed
      games = [
        { name: "New Date", steam_id: 1, playtime_forever: 100, playtime_2weeks: 5,
          last_played_date: Time.new(2024, 2, 20) },
      ]
      notion_pages = [
        notion_page(steam_id: 1, page_id: "page-1", playtime: 100, last_played_date: "2024-01-15"),
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: notion_pages)

      GameSync.new(steam_client: steam, notion_client: notion, output: @output).call

      assert_equal 1, notion.playtime_updated_games.length
      assert_includes @output.string, "Updated playtime for game: New Date"
    end

    def test_incremental_only_updates_recently_played_games
      games = [
        { name: "Active", steam_id: 1, playtime_forever: 100, playtime_2weeks: 20 },
        { name: "Idle", steam_id: 2, playtime_forever: 50, playtime_2weeks: 0 },
        { name: "Also Active", steam_id: 3, playtime_forever: 200, playtime_2weeks: 5 },
      ]
      notion_pages = [
        notion_page(steam_id: 1, page_id: "page-1", playtime: 80),
        notion_page(steam_id: 2, page_id: "page-2", playtime: 50),
        notion_page(steam_id: 3, page_id: "page-3", playtime: 195),
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

    # --- Game filter tests ---

    def test_game_filter_by_name
      games = [
        { name: "Hades", steam_id: 1145360, playtime_forever: 100, playtime_2weeks: 0 },
        { name: "Celeste", steam_id: 504230, playtime_forever: 50, playtime_2weeks: 0 },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, game_filter: "Hades", output: @output).call

      assert_equal 1, notion.inserted_games.length
      assert_equal "Hades", notion.inserted_games.first[:name]
      assert_includes @output.string, "Game filter: Hades"
    end

    def test_game_filter_by_steam_id
      games = [
        { name: "Hades", steam_id: 1145360, playtime_forever: 100, playtime_2weeks: 0 },
        { name: "Celeste", steam_id: 504230, playtime_forever: 50, playtime_2weeks: 0 },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, game_filter: "1145360", output: @output).call

      assert_equal 1, notion.inserted_games.length
      assert_equal "Hades", notion.inserted_games.first[:name]
    end

    def test_game_filter_no_match
      games = [
        { name: "Hades", steam_id: 1145360, playtime_forever: 100, playtime_2weeks: 0 },
      ]

      steam = StubSteamClient.new(games: games)
      notion = StubNotionClient.new(pages: [])

      GameSync.new(steam_client: steam, notion_client: notion, game_filter: "Nonexistent", output: @output).call

      assert_empty notion.inserted_games
      assert_includes @output.string, "No Steam games matched filter: Nonexistent"
    end

    private

    def notion_page(steam_id:, page_id:, playtime: 0, last_played_date: nil, platforms: ["Steam"])
      date_value = last_played_date ? { "start" => last_played_date } : nil
      {
        "id" => page_id,
        "properties" => {
          "Steam ID" => { "number" => steam_id },
          "Playtime (Minutes)" => { "number" => playtime },
          "Last Played Date" => { "date" => date_value },
          "Platforms" => { "multi_select" => platforms.map { |p| { "name" => p } } },
        },
      }
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

      def fetch_games_by_steam_id(steam_id)
        @pages.select { |p| p["properties"]["Steam ID"]["number"] == steam_id }
      end

      def fetch_games_by_name(name)
        @pages.select { |p|
          page_name = p["properties"].dig("Name", "title", 0, "text", "content")
          page_name&.downcase&.include?(name.downcase)
        }
      end

      def games_map(pages)
        pages.map { |p|
          props = p["properties"]
          steam_id = props["Steam ID"]["number"]
          data = {
            page_id: p["id"],
            playtime: props.dig("Playtime (Minutes)", "number") || 0,
            last_played_date: props.dig("Last Played Date", "date", "start"),
            platforms: (props.dig("Platforms", "multi_select") || []).map { |pl| pl["name"] },
          }
          [steam_id, data]
        }.to_h
      end

      def insert_game(game)
        @inserted_games << game
        if @backfill_after_insert
          @pages << {
            "id" => "new-page-#{game[:steam_id]}",
            "properties" => {
              "Steam ID" => { "number" => game[:steam_id] },
              "Playtime (Minutes)" => { "number" => 0 },
              "Last Played Date" => { "date" => nil },
            },
          }
        end
        "200"
      end

      def update_game(page_id:, game:, details:, existing_platforms: [])
        @updated_games << { page_id: page_id, game: game, details: details, existing_platforms: existing_platforms }
        {}
      end

      def update_game_playtime(page_id:, game:)
        @playtime_updated_games << { page_id: page_id, game: game }
        {}
      end
    end
  end
end
