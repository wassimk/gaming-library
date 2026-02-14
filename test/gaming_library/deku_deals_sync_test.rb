require "test_helper"
require "stringio"
require "gaming_library/deku_deals_sync"

module GamingLibrary
  class DekuDealsSyncTest < Minitest::Test
    def setup
      @output = StringIO.new
    end

    # --- Insert tests ---

    def test_inserts_new_game
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "Switch", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_equal 1, notion.inserted_deku_deals_games.length
      assert_equal "Hades", notion.inserted_deku_deals_games.first[:game][:name]
      assert_equal "Nintendo Switch", notion.inserted_deku_deals_games.first[:game][:platform]
      assert_includes @output.string, "Added Deku Deals game: Hades"
    end

    def test_merges_platform_for_existing_game
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "PS5", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Hades", page_id: "page-1", platforms: ["Steam"]),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_equal 1, notion.updated_deku_deals_games.length
      update = notion.updated_deku_deals_games.first
      assert_equal "page-1", update[:page_id]
      assert_equal ["Steam"], update[:existing_platforms]
      assert_equal "PlayStation 5", update[:game][:platform]
      assert_includes @output.string, "Merged platform PlayStation 5 for: Hades"
    end

    def test_skips_merge_when_platform_already_present
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "Switch", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Hades", page_id: "page-1", platforms: ["Nintendo Switch"]),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_empty notion.updated_deku_deals_games
      assert_empty notion.inserted_deku_deals_games
    end

    def test_matches_by_deku_deals_id
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "PS5", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      # Name doesn't match, but Deku Deals ID does
      notion = StubNotionClient.new(pages: [
        notion_page(name: "HADES (2020)", page_id: "page-1", platforms: ["Steam"], deku_deals_id: "hades"),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_equal 1, notion.updated_deku_deals_games.length
      assert_equal "page-1", notion.updated_deku_deals_games.first[:page_id]
    end

    def test_matches_by_name_case_insensitive
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "PS5", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "hades", page_id: "page-1", platforms: ["Steam"]),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_equal 1, notion.updated_deku_deals_games.length
    end

    def test_switch2_supersedes_switch_on_merge
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Zelda", slug: "zelda", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "zelda" => { name: "Zelda", platform: "Switch 2", format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Zelda", page_id: "page-1", platforms: ["Nintendo Switch"]),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_equal 1, notion.updated_deku_deals_games.length
      assert_equal ["Nintendo Switch"], notion.updated_deku_deals_games.first[:existing_platforms]
      assert_equal "Nintendo Switch 2", notion.updated_deku_deals_games.first[:game][:platform]
    end

    def test_skips_switch_when_switch2_already_present
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Zelda", slug: "zelda", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "zelda" => { name: "Zelda", platform: "Switch", format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Zelda", page_id: "page-1", platforms: ["Nintendo Switch 2"]),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_empty notion.updated_deku_deals_games
      assert_empty notion.inserted_deku_deals_games
    end

    def test_skips_merge_when_platform_is_empty
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Prison Boss VR", slug: "prison-boss-vr", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "prison-boss-vr" => { name: "Prison Boss VR", platform: nil, format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Prison Boss VR", page_id: "page-1", platforms: ["Steam"]),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_empty notion.updated_deku_deals_games
    end

    def test_skips_insert_when_platform_is_empty
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Unknown Game", slug: "unknown", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "unknown" => { name: "Unknown Game", platform: nil, format: nil, image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_empty notion.inserted_deku_deals_games
      assert_includes @output.string, "Skipping Unknown Game: no platform detected"
    end

    def test_merge_does_not_set_icon
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "PS5", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Hades", page_id: "page-1", platforms: ["Steam"]),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_equal false, notion.updated_deku_deals_games.first[:set_icon]
    end

    def test_full_sync_sets_icon
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "Switch", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Hades", page_id: "page-1", platforms: ["Nintendo Switch"], deku_deals_id: "hades"),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, full_sync: true, output: @output).call

      assert_equal true, notion.updated_deku_deals_games.first[:set_icon]
    end

    def test_maps_platform_names
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Game", slug: "game", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "game" => { name: "Game", platform: "Xbox X|S", format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_equal "Xbox Series X|S", notion.inserted_deku_deals_games.first[:game][:platform]
    end

    # --- Full sync tests ---

    def test_full_sync_updates_all_metadata
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "Switch", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [
        notion_page(name: "Hades", page_id: "page-1", platforms: ["Nintendo Switch"], deku_deals_id: "hades"),
      ])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, full_sync: true, output: @output).call

      # Platform already present, so no merge during insert_or_merge phase
      # But full sync should update metadata
      assert_includes @output.string, "Updated metadata for: Hades"
    end

    def test_full_sync_skips_games_not_in_notion
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "New Game", slug: "new-game", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "new-game" => { name: "New Game", platform: "PS5", format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, full_sync: true, output: @output).call

      # Game gets inserted (1 insert), but full sync update won't find it
      # since the name_map was built before insert
      assert_equal 1, notion.inserted_deku_deals_games.length
    end

    # --- Log summary tests ---

    def test_log_summary_shows_incremental_mode
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Game", slug: "game", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "game" => { name: "Game", platform: "Switch", format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_includes @output.string, "Sync mode: incremental"
    end

    def test_log_summary_shows_full_mode
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Game", slug: "game", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "game" => { name: "Game", platform: "Switch", format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, full_sync: true, output: @output).call

      assert_includes @output.string, "Sync mode: full"
    end

    def test_empty_collection_warns_and_returns_early
      deku = StubDekuDealsClient.new(collection: [], collection_details: {})
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_includes @output.string, "no games found in collection"
      refute_includes @output.string, "Syncing Deku Deals games"
    end

    # --- Game filter tests ---

    def test_game_filter_by_name
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
          { name: "Celeste", slug: "celeste", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "Switch", format: "Digital", image_url: "https://cdn.dekudeals.com/images/abc/w500.jpg" },
          "celeste" => { name: "Celeste", platform: "Switch", format: "Digital", image_url: "https://cdn.dekudeals.com/images/def/w500.jpg" },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, game_filter: "Hades", output: @output).call

      assert_equal 1, notion.inserted_deku_deals_games.length
      assert_equal "Hades", notion.inserted_deku_deals_games.first[:game][:name]
      assert_includes @output.string, "Game filter: Hades"
    end

    def test_game_filter_no_match
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Hades", slug: "hades", added_at: "2025-01-01T00:00:00+00:00", format: "digital" },
        ],
        collection_details: {
          "hades" => { name: "Hades", platform: "Switch", format: "Digital", image_url: nil },
        },
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, game_filter: "Nonexistent", output: @output).call

      assert_empty notion.inserted_deku_deals_games
      assert_includes @output.string, "No Deku Deals games matched filter: Nonexistent"
    end

    # --- Error handling ---

    def test_error_in_one_game_does_not_halt_sync
      deku = StubDekuDealsClient.new(
        collection: [
          { name: "Bad Game", slug: "bad-game", added_at: "2025-01-01T00:00:00+00:00" },
          { name: "Good Game", slug: "good-game", added_at: "2025-01-01T00:00:00+00:00" },
        ],
        collection_details: {
          "bad-game" => { name: "Bad Game", platform: "Switch", format: "Digital", image_url: nil },
          "good-game" => { name: "Good Game", platform: "Switch", format: "Digital", image_url: nil },
        },
        failing_slugs: ["bad-game"],
      )
      notion = StubNotionClient.new(pages: [])

      DekuDealsSync.new(deku_deals_client: deku, notion_client: notion, output: @output).call

      assert_includes @output.string, "Error syncing Deku Deals game: Bad Game"
      assert_equal 1, notion.inserted_deku_deals_games.length
      assert_equal "Good Game", notion.inserted_deku_deals_games.first[:game][:name]
    end

    private

    def notion_page(name:, page_id:, platforms: [], deku_deals_id: nil)
      deku_deals_rich_text = deku_deals_id ? [{ "text" => { "content" => deku_deals_id } }] : []
      {
        "id" => page_id,
        "properties" => {
          "Name" => { "title" => [{ "text" => { "content" => name } }] },
          "Steam ID" => { "number" => nil },
          "Playtime (Minutes)" => { "number" => 0 },
          "Last Played Date" => { "date" => nil },
          "Platforms" => { "multi_select" => platforms.map { |p| { "name" => p } } },
          "Deku Deals ID" => { "rich_text" => deku_deals_rich_text },
        },
      }
    end

    # --- Stub objects ---

    class StubDekuDealsClient
      def initialize(collection:, collection_details:, failing_slugs: [])
        @collection_data = collection
        @collection_details_data = collection_details
        @failing_slugs = failing_slugs
      end

      def collection
        @collection_data
      end

      def collection_details
        @collection_details_data
      end

      def game_details(slug)
        raise "Detail fetch failed" if @failing_slugs.include?(slug)

        {
          publishers: ["Test Publisher"],
          developers: ["Test Developer"],
          genres: ["Action"],
          release_date: "Jan 1, 2020",
          metacritic: 80,
          image_url: "https://cdn.dekudeals.com/images/test/w500.jpg",
        }
      end
    end

    class StubNotionClient
      attr_reader :inserted_deku_deals_games, :updated_deku_deals_games

      def initialize(pages:)
        @pages = pages
        @inserted_deku_deals_games = []
        @updated_deku_deals_games = []
      end

      def fetch_games
        @pages
      end

      def fetch_games_by_name(name)
        @pages.select { |p|
          page_name = p["properties"].dig("Name", "title", 0, "text", "content")
          page_name&.downcase&.include?(name.downcase)
        }
      end

      def games_map_by_name(pages)
        pages.map { |page|
          props = page["properties"]
          name = props.dig("Name", "title", 0, "text", "content")
          next unless name

          platforms = (props.dig("Platforms", "multi_select") || []).map { |p| p["name"] }
          deku_deals_id = props.dig("Deku Deals ID", "rich_text", 0, "text", "content")

          data = {
            page_id: page["id"],
            platforms: platforms,
            deku_deals_id: deku_deals_id,
          }
          [name.strip.downcase, data]
        }.compact.to_h
      end

      def insert_deku_deals_game(game:, details:)
        @inserted_deku_deals_games << { game: game, details: details }
        "200"
      end

      def update_deku_deals_game(page_id:, game:, details:, existing_platforms:, set_icon: false)
        @updated_deku_deals_games << {
          page_id: page_id,
          game: game,
          details: details,
          existing_platforms: existing_platforms,
          set_icon: set_icon,
        }
        {}
      end
    end
  end
end
