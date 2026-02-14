require "test_helper"
require "gaming_library/notion_client"

module GamingLibrary
  class NotionClientTest < Minitest::Test
    def setup
      @client = NotionClient.new(api_key: "test_key", database_id: "test_db")
    end

    # --- games_map ---

    def test_games_map_builds_steam_id_to_page_id_hash
      pages = [
        { "id" => "page-1", "properties" => { "Steam ID" => { "number" => 123 } } },
        { "id" => "page-2", "properties" => { "Steam ID" => { "number" => 456 } } },
      ]

      result = @client.games_map(pages)
      assert_equal({ 123 => "page-1", 456 => "page-2" }, result)
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
  end
end
