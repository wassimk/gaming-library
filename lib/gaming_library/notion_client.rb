require "net/http"
require "json"
require "uri"
require "date"

module GamingLibrary
  class NotionClient
    BASE_URL = "https://api.notion.com"

    def initialize(api_key:, database_id:)
      @api_key = api_key
      @database_id = database_id
    end

    def fetch_games
      all_results = []
      has_more = true
      start_cursor = nil

      while has_more
        body = {}
        body[:start_cursor] = start_cursor if start_cursor

        data = post("/v1/databases/#{@database_id}/query", body)
        all_results.concat(data["results"])
        has_more = data["has_more"]
        start_cursor = data["next_cursor"]
      end

      all_results
    end

    def games_map(notion_pages)
      notion_pages.map { |page|
        [page["properties"]["Steam ID"]["number"], page["id"]]
      }.to_h
    end

    def insert_game(game)
      body = {
        parent: { database_id: @database_id },
        properties: {
          Name: { title: [{ text: { content: game[:name] } }] },
          "Playtime (Minutes)": { number: game[:playtime_forever] },
          "Steam ID": { number: game[:steam_id] },
        },
      }

      response = post_raw("/v1/pages", body)
      response.code
    end

    def update_game(page_id:, game:, details:)
      properties = build_update_properties(game: game, details: details)
      body = { properties: properties }

      patch("/v1/pages/#{page_id}", body)
    end

    private

    def build_update_properties(game:, details:)
      properties = {}

      publishers = details["publishers"]
      developers = details["developers"]
      genres = details["genres"]&.map { |g| g["description"] }

      release_date = parse_release_date(details.dig("release_date", "date"))
      logo_url = details["capsule_imagev5"]

      if !publishers.nil?
        properties[:Publishers] = {
          multi_select: publishers.map { |p| { name: p.gsub(",", "") } },
        }
      end

      if !developers.nil?
        properties[:Developers] = {
          multi_select: developers.map { |d| { name: d.gsub(",", "") } },
        }
      end

      if !genres.nil?
        properties[:Genres] = {
          multi_select: genres.map { |g| { name: g.gsub(",", "") } },
        }
      end

      if !release_date.nil?
        properties[:"Release Date"] = { date: { start: release_date.to_s } }
      end

      if logo_url
        properties[:Icon] = {
          files: [{ name: "logo", type: "external", external: { url: logo_url } }],
        }
      end

      if !game[:last_played_date].nil?
        properties[:"Last Played Date"] = {
          date: { start: game[:last_played_date].to_date.to_s },
        }
      end

      properties[:"Playtime (Minutes)"] = { number: game[:playtime_forever] }

      properties
    end

    def parse_release_date(date_string)
      return nil if date_string.nil?

      Date.parse(date_string.scan(/[,\w+\s]/).join)
    rescue StandardError
      nil
    end

    def headers
      {
        "Authorization" => "Bearer #{@api_key}",
        "Content-Type" => "application/json",
        "Notion-Version" => "2022-06-28",
      }
    end

    def post(path, body)
      response = post_raw(path, body)
      JSON.parse(response.body)
    end

    def post_raw(path, body)
      uri = URI("#{BASE_URL}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri.path, headers)
      request.body = body.to_json
      http.request(request)
    end

    def patch(path, body)
      uri = URI("#{BASE_URL}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Patch.new(uri.path, headers)
      request.body = body.to_json
      response = http.request(request)
      JSON.parse(response.body)
    end
  end
end
