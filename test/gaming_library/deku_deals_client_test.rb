require "test_helper"
require "gaming_library/deku_deals_client"

module GamingLibrary
  class DekuDealsClientTest < Minitest::Test
    def setup
      @client = TestDekuDealsClient.new(collection_id: "test123")
    end

    # --- collection JSON parsing ---

    def test_collection_parses_items
      @client.collection_json_response = {
        "items" => [
          {
            "name" => "1000xRESIST",
            "link" => "https://www.dekudeals.com/items/1000xresist",
            "added_at" => "2025-03-30T00:31:47+00:00",
            "format" => "digital",
          },
          {
            "name" => "Hades",
            "link" => "https://www.dekudeals.com/items/hades",
            "added_at" => "2024-01-15T10:00:00+00:00",
          },
        ],
      }

      result = @client.collection

      assert_equal 2, result.length
      assert_equal "1000xRESIST", result[0][:name]
      assert_equal "1000xresist", result[0][:slug]
      assert_equal "2025-03-30T00:31:47+00:00", result[0][:added_at]
      assert_equal "digital", result[0][:format]

      assert_equal "Hades", result[1][:name]
      assert_equal "hades", result[1][:slug]
      assert_nil result[1][:format]
    end

    def test_collection_handles_empty_items
      @client.collection_json_response = { "items" => [] }

      assert_equal [], @client.collection
    end

    # --- collection HTML parsing ---

    def test_collection_details_parses_cards
      @client.collection_html_response = <<~HTML
        <html><body>
          <div class="col d-block">
            <div class="d-flex flex-column img-frame">
              <img class="w-100 h-100" src="https://cdn.dekudeals.com/images/abc123/w500.jpg" alt="">
            </div>
            <a class="main-link" href="/items/boneraiser-minions">
              <h6>Boneraiser Minions</h6>
            </a>
            <div class="shared-details watch-details">
              <div class="body">
                <div class="detail">
                  <small class="text-muted">Format</small><br>Digital
                </div>
                <div class="detail">
                  <small class="text-muted">Platform</small><br>Steam
                </div>
              </div>
            </div>
          </div>
          <div class="col d-block">
            <div class="d-flex flex-column img-frame">
              <img class="w-100 h-100" src="https://cdn.dekudeals.com/images/def456/w500.jpg" alt="">
            </div>
            <a class="main-link" href="/items/the-order-1886">
              <h6>The Order: 1886</h6>
            </a>
            <div class="shared-details watch-details">
              <div class="body">
                <div class="detail">
                  <small class="text-muted">Platform</small><br>PS4
                </div>
              </div>
            </div>
          </div>
        </body></html>
      HTML

      result = @client.collection_details

      assert_equal 2, result.size

      bone = result["boneraiser-minions"]
      assert_equal "Boneraiser Minions", bone[:name]
      assert_equal "Steam", bone[:platform]
      assert_equal "Digital", bone[:format]
      assert_equal "https://cdn.dekudeals.com/images/abc123/w500.jpg", bone[:image_url]

      order = result["the-order-1886"]
      assert_equal "The Order: 1886", order[:name]
      assert_equal "PS4", order[:platform]
      assert_nil order[:format]
    end

    def test_collection_details_skips_cards_without_link
      @client.collection_html_response = <<~HTML
        <html><body>
          <div class="col d-block">
            <div>No link here</div>
          </div>
        </body></html>
      HTML

      assert_equal({}, @client.collection_details)
    end

    # --- game detail page parsing ---

    def test_game_details_parses_full_page
      @client.game_details_html = <<~HTML
        <html><body>
          <h1>1000xRESIST</h1>
          <img class="shadow-img-large" src="https://cdn.dekudeals.com/images/abc123/w500.jpg">
          <ul>
            <li class="list-group-item">
              <strong>Genre:</strong>
              <a href="/games?filter[genre]=Adventure">Adventure</a>
            </li>
            <li class="list-group-item">
              <strong>Developer:</strong>
              <a href="/games?filter[developer]=sunset+visitor">sunset visitor</a>
            </li>
            <li class="list-group-item">
              <strong>Publisher:</strong>
              <a href="/games?filter[publisher]=Fellow+Traveller">Fellow Traveller</a>
            </li>
            <li class="list-group-item">
              <strong>Release date:</strong>
              <ul>
                <li><strong>Steam, Switch</strong><br>May  9, 2024</li>
                <li><strong>PS5, Xbox X|S</strong><br>November  4, 2025</li>
              </ul>
            </li>
            <li class="list-group-item">
              <strong>Metacritic:</strong>
              <a class="metacritic" href="https://www.metacritic.com/game/1000xresist/">
                <span class="text-white p-1 rounded bg-success">87</span>
                <span class="p-1 text-success">8.2</span>
              </a>
            </li>
          </ul>
        </body></html>
      HTML

      result = @client.game_details("1000xresist")

      assert_equal ["Adventure"], result[:genres]
      assert_equal ["sunset visitor"], result[:developers]
      assert_equal ["Fellow Traveller"], result[:publishers]
      assert_equal "May  9, 2024", result[:release_date]
      assert_equal 87, result[:metacritic]
      assert_equal "https://cdn.dekudeals.com/images/abc123/w500.jpg", result[:image_url]
    end

    def test_game_details_parses_multiple_genres
      @client.game_details_html = <<~HTML
        <html><body>
          <ul>
            <li class="list-group-item">
              <strong>Genre:</strong>
              <a href="/games?filter[genre]=Action">Action</a>,
              <a href="/games?filter[genre]=Shooter">Shooter</a>
            </li>
            <li class="list-group-item">
              <strong>Release date:</strong> January 13, 2015
            </li>
          </ul>
        </body></html>
      HTML

      result = @client.game_details("the-order-1886")

      assert_equal ["Action", "Shooter"], result[:genres]
      assert_equal "January 13, 2015", result[:release_date]
    end

    def test_game_details_handles_missing_fields
      @client.game_details_html = <<~HTML
        <html><body>
          <h1>Minimal Game</h1>
        </body></html>
      HTML

      result = @client.game_details("minimal-game")

      assert_nil result[:genres]
      assert_nil result[:publishers]
      assert_nil result[:developers]
      assert_nil result[:release_date]
      assert_nil result[:metacritic]
      assert_nil result[:image_url]
    end

    def test_game_details_simple_release_date
      @client.game_details_html = <<~HTML
        <html><body>
          <ul>
            <li class="list-group-item">
              <strong>Release date:</strong> January 13, 2015
            </li>
          </ul>
        </body></html>
      HTML

      result = @client.game_details("test")

      assert_equal "January 13, 2015", result[:release_date]
    end

    def test_game_details_returns_nil_on_fetch_error
      client = ErrorDekuDealsClient.new(collection_id: "test123")
      assert_nil client.game_details("broken-game")
    end

    def test_game_details_uses_small_image_as_fallback
      @client.game_details_html = <<~HTML
        <html><body>
          <img class="shadow-img-small" src="https://cdn.dekudeals.com/images/small123/w500.jpg">
        </body></html>
      HTML

      result = @client.game_details("test")

      assert_equal "https://cdn.dekudeals.com/images/small123/w500.jpg", result[:image_url]
    end

    # --- Test subclass ---

    class TestDekuDealsClient < DekuDealsClient
      attr_writer :collection_json_response,
                  :collection_html_response,
                  :game_details_html

      private

      def fetch_collection_json
        @collection_json_response
      end

      def fetch_collection_html
        @collection_html_response
      end

      def fetch_game_details(_slug)
        @game_details_html
      end
    end

    class ErrorDekuDealsClient < DekuDealsClient
      private

      def fetch_game_details(_slug)
        raise StandardError, "connection refused"
      end
    end
  end
end
