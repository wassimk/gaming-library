require "test_helper"
require "gaming_library/notion_client"

module GamingLibrary
  class NotionClientTest < Minitest::Test
    def setup
      @client = NotionClient.new(api_key: "test_key", database_id: "test_db")
    end

    # --- games_map ---

    def test_games_map_builds_steam_id_to_data_hash
      pages = [
        {
          "id" => "page-1",
          "properties" => {
            "Steam ID" => { "number" => 123 },
            "Playtime (Minutes)" => { "number" => 60 },
            "Last Played Date" => { "date" => { "start" => "2024-01-15" } },
          },
        },
        {
          "id" => "page-2",
          "properties" => {
            "Steam ID" => { "number" => 456 },
            "Playtime (Minutes)" => { "number" => nil },
            "Last Played Date" => { "date" => nil },
          },
        },
      ]

      result = @client.games_map(pages)

      assert_equal "page-1", result[123][:page_id]
      assert_equal 60, result[123][:playtime]
      assert_equal "2024-01-15", result[123][:last_played_date]

      assert_equal "page-2", result[456][:page_id]
      assert_equal 0, result[456][:playtime]
      assert_nil result[456][:last_played_date]
    end

    def test_games_map_empty
      assert_equal({}, @client.games_map([]))
    end

    # --- build_update_properties ---

    def test_build_update_properties_with_full_details
      game = {
        name: "Test",
        playtime_forever: 120,
        last_played_date: Time.new(2024, 1, 15),
        icon_url: "http://example.com/icon.jpg",
        steam_id: 123,
      }
      details = {
        "publishers" => ["Valve Software"],
        "developers" => ["Valve"],
        "genres" => [{ "description" => "Action" }, { "description" => "FPS" }],
        "release_date" => { "date" => "Nov 16, 2004" },
        "capsule_imagev5" => "http://example.com/logo.jpg",
      }

      props = @client.send(:build_update_properties, game: game, details: details)

      assert_equal [{ name: "Valve Software" }], props[:Publishers][:multi_select]
      assert_equal [{ name: "Valve" }], props[:Developers][:multi_select]
      assert_equal [{ name: "Action" }, { name: "FPS" }], props[:Genres][:multi_select]
      assert_equal "2004-11-16", props[:"Release Date"][:date][:start]
      assert_equal 120, props[:"Playtime (Minutes)"][:number]
      assert_equal "2024-01-15", props[:"Last Played Date"][:date][:start]
      assert_equal "http://example.com/logo.jpg",
        props[:Icon][:files][0][:external][:url]
      assert_equal [{ name: "Steam" }], props[:Platforms][:multi_select]
      assert_equal({ name: "Digital" }, props[:Format][:select])
    end

    def test_build_update_properties_strips_commas_from_multi_select
      game = { name: "Test", playtime_forever: 0, last_played_date: nil, icon_url: nil, steam_id: 1 }
      details = {
        "publishers" => ["Company, Inc."],
        "developers" => nil,
        "genres" => nil,
        "release_date" => { "date" => nil },
        "capsule_imagev5" => nil,
      }

      props = @client.send(:build_update_properties, game: game, details: details)
      assert_equal [{ name: "Company Inc." }], props[:Publishers][:multi_select]
    end

    def test_build_update_properties_excludes_nil_fields
      game = { name: "Test", playtime_forever: 0, last_played_date: nil, icon_url: nil, steam_id: 1 }
      details = {
        "publishers" => nil,
        "developers" => nil,
        "genres" => nil,
        "release_date" => { "date" => nil },
        "capsule_imagev5" => nil,
      }

      props = @client.send(:build_update_properties, game: game, details: details)

      refute props.key?(:Publishers)
      refute props.key?(:Developers)
      refute props.key?(:Genres)
      refute props.key?(:"Release Date")
      refute props.key?(:Icon)
      refute props.key?(:"Last Played Date")
      assert props.key?(:"Playtime (Minutes)")
      assert_equal [{ name: "Steam" }], props[:Platforms][:multi_select]
      assert_equal({ name: "Digital" }, props[:Format][:select])
    end

    # --- update_game_playtime ---

    def test_update_game_playtime_builds_correct_properties
      game = {
        name: "Test",
        playtime_forever: 200,
        last_played_date: Time.new(2024, 6, 10),
        steam_id: 123,
      }

      props = build_playtime_properties(game)

      assert_equal 200, props[:"Playtime (Minutes)"][:number]
      assert_equal "2024-06-10", props[:"Last Played Date"][:date][:start]
      refute props.key?(:Publishers)
      refute props.key?(:Developers)
      refute props.key?(:Genres)
      refute props.key?(:"Release Date")
      refute props.key?(:Icon)
    end

    def test_update_game_playtime_excludes_nil_last_played
      game = {
        name: "Test",
        playtime_forever: 0,
        last_played_date: nil,
        steam_id: 456,
      }

      props = build_playtime_properties(game)

      assert_equal 0, props[:"Playtime (Minutes)"][:number]
      refute props.key?(:"Last Played Date")
    end

    # --- merge_platforms ---

    def test_merge_platforms_adds_new_platform
      result = @client.send(:merge_platforms, ["Steam"], "Nintendo Switch")
      assert_equal ["Steam", "Nintendo Switch"], result
    end

    def test_merge_platforms_deduplicates
      result = @client.send(:merge_platforms, ["Steam"], "Steam")
      assert_equal ["Steam"], result
    end

    def test_merge_platforms_switch2_removes_switch
      result = @client.send(:merge_platforms, ["Nintendo Switch", "Steam"], "Nintendo Switch 2")
      assert_equal ["Steam", "Nintendo Switch 2"], result
    end

    def test_merge_platforms_keeps_switch_when_no_switch2
      result = @client.send(:merge_platforms, ["Nintendo Switch", "Steam"], "PlayStation 5")
      assert_equal ["Nintendo Switch", "Steam", "PlayStation 5"], result
    end

    # --- games_map_by_name ---

    def test_games_map_by_name_builds_name_to_data_hash
      pages = [
        {
          "id" => "page-1",
          "properties" => {
            "Name" => { "title" => [{ "text" => { "content" => "Hades" } }] },
            "Platforms" => { "multi_select" => [{ "name" => "Steam" }, { "name" => "Nintendo Switch" }] },
            "Deku Deals ID" => { "rich_text" => [{ "text" => { "content" => "hades" } }] },
          },
        },
        {
          "id" => "page-2",
          "properties" => {
            "Name" => { "title" => [{ "text" => { "content" => "Celeste" } }] },
            "Platforms" => { "multi_select" => [{ "name" => "Steam" }] },
            "Deku Deals ID" => { "rich_text" => [] },
          },
        },
      ]

      result = @client.games_map_by_name(pages)

      assert_equal "page-1", result["hades"][:page_id]
      assert_equal ["Steam", "Nintendo Switch"], result["hades"][:platforms]
      assert_equal "hades", result["hades"][:deku_deals_id]

      assert_equal "page-2", result["celeste"][:page_id]
      assert_equal ["Steam"], result["celeste"][:platforms]
      assert_nil result["celeste"][:deku_deals_id]
    end

    def test_games_map_by_name_is_case_insensitive
      pages = [
        {
          "id" => "page-1",
          "properties" => {
            "Name" => { "title" => [{ "text" => { "content" => "HADES" } }] },
            "Platforms" => { "multi_select" => [] },
            "Deku Deals ID" => { "rich_text" => [] },
          },
        },
      ]

      result = @client.games_map_by_name(pages)

      assert result.key?("hades")
      refute result.key?("HADES")
    end

    def test_games_map_by_name_skips_pages_without_name
      pages = [
        {
          "id" => "page-1",
          "properties" => {
            "Name" => { "title" => [] },
            "Platforms" => { "multi_select" => [] },
            "Deku Deals ID" => { "rich_text" => [] },
          },
        },
      ]

      assert_equal({}, @client.games_map_by_name(pages))
    end

    def test_games_map_by_name_empty
      assert_equal({}, @client.games_map_by_name([]))
    end

    # --- parse_release_date ---

    def test_parse_release_date_standard_format
      date = @client.send(:parse_release_date, "Nov 16, 2004")
      assert_equal Date.new(2004, 11, 16), date
    end

    def test_parse_release_date_bad_date_returns_nil
      assert_nil @client.send(:parse_release_date, "Coming Soon")
    end

    def test_parse_release_date_nil_returns_nil
      assert_nil @client.send(:parse_release_date, nil)
    end

    private

    def build_playtime_properties(game)
      properties = {}
      properties[:"Playtime (Minutes)"] = { number: game[:playtime_forever] }
      if !game[:last_played_date].nil?
        properties[:"Last Played Date"] = {
          date: { start: game[:last_played_date].to_date.to_s },
        }
      end
      properties
    end
  end
end
