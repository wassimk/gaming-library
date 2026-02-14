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

    def fetch_games_by_steam_id(steam_id)
      body = {
        filter: {
          property: "Steam ID",
          number: { equals: steam_id },
        },
      }
      data = post("/v1/databases/#{@database_id}/query", body)
      data["results"]
    end

    def fetch_games_by_name(name)
      body = {
        filter: {
          property: "Name",
          title: { contains: name },
        },
      }
      data = post("/v1/databases/#{@database_id}/query", body)
      data["results"]
    end

    def games_map(notion_pages)
      notion_pages.map { |page|
        props = page["properties"]
        steam_id = props["Steam ID"]["number"]
        data = {
          page_id: page["id"],
          playtime: props.dig("Playtime (Minutes)", "number") || 0,
          last_played_date: props.dig("Last Played Date", "date", "start"),
          platforms: (props.dig("Platforms", "multi_select") || []).map { |p| p["name"] },
        }
        [steam_id, data]
      }.to_h
    end

    def insert_game(game)
      body = {
        parent: { database_id: @database_id },
        properties: {
          Name: { title: [{ text: { content: game[:name] } }] },
          "Playtime (Minutes)": { number: game[:playtime_forever] },
          "Steam ID": { number: game[:steam_id] },
          Platforms: { multi_select: [{ name: "Steam" }] },
          Format: { select: { name: "Digital" } },
        },
      }

      response = post_raw("/v1/pages", body)
      response.code
    end

    def update_game(page_id:, game:, details:, existing_platforms: [])
      properties = build_update_properties(game: game, details: details, existing_platforms: existing_platforms)
      body = { properties: properties }

      patch("/v1/pages/#{page_id}", body)
    end

    def games_map_by_name(notion_pages)
      notion_pages.map { |page|
        props = page["properties"]
        name = props.dig("Name", "title", 0, "text", "content")
        next unless name

        platforms =
          (props.dig("Platforms", "multi_select") || []).map { |p| p["name"] }
        deku_deals_id =
          props.dig("Deku Deals ID", "rich_text", 0, "text", "content")

        data = {
          page_id: page["id"],
          platforms: platforms,
          deku_deals_id: deku_deals_id,
        }
        [name.strip.downcase, data]
      }.compact.to_h
    end

    def insert_deku_deals_game(game:, details:)
      properties = {
        Name: { title: [{ text: { content: game[:name] } }] },
        "Deku Deals ID": {
          rich_text: [{ text: { content: game[:slug] } }],
        },
        Platforms: { multi_select: [{ name: game[:platform] }] },
        Format: { select: { name: (game[:format] || "Digital").capitalize } },
      }

      if details
        if details[:publishers]
          properties[:Publishers] = {
            multi_select:
              details[:publishers].map { |p| { name: p.gsub(",", "") } },
          }
        end

        if details[:developers]
          properties[:Developers] = {
            multi_select:
              details[:developers].map { |d| { name: d.gsub(",", "") } },
          }
        end

        if details[:genres]
          properties[:Genres] = {
            multi_select:
              details[:genres].map { |g| { name: g.gsub(",", "") } },
          }
        end

        release_date = parse_release_date(details[:release_date])
        if release_date
          properties[:"Release Date"] = { date: { start: release_date.to_s } }
        end

        image_url = game[:image_url] || details[:image_url]
        if image_url
          properties[:Icon] = {
            files: [
              { name: "logo", type: "external", external: { url: image_url } },
            ],
          }
        end
      elsif game[:image_url]
        properties[:Icon] = {
          files: [
            {
              name: "logo",
              type: "external",
              external: { url: game[:image_url] },
            },
          ],
        }
      end

      body = { parent: { database_id: @database_id }, properties: properties }
      response = post_raw("/v1/pages", body)
      response.code
    end

    def update_deku_deals_game(page_id:, game:, details:, existing_platforms:, set_icon: false)
      properties = {}

      merged_platforms = merge_platforms(existing_platforms, game[:platform])
      properties[:Platforms] = {
        multi_select: merged_platforms.map { |p| { name: p } },
      }

      properties[:"Deku Deals ID"] = {
        rich_text: [{ text: { content: game[:slug] } }],
      }

      if details
        if details[:publishers]
          properties[:Publishers] = {
            multi_select:
              details[:publishers].map { |p| { name: p.gsub(",", "") } },
          }
        end

        if details[:developers]
          properties[:Developers] = {
            multi_select:
              details[:developers].map { |d| { name: d.gsub(",", "") } },
          }
        end

        if details[:genres]
          properties[:Genres] = {
            multi_select:
              details[:genres].map { |g| { name: g.gsub(",", "") } },
          }
        end

        release_date = parse_release_date(details[:release_date])
        if release_date
          properties[:"Release Date"] = { date: { start: release_date.to_s } }
        end

        if set_icon
          image_url = game[:image_url] || details[:image_url]
          if image_url
            properties[:Icon] = {
              files: [
                { name: "logo", type: "external", external: { url: image_url } },
              ],
            }
          end
        end
      end

      body = { properties: properties }
      patch("/v1/pages/#{page_id}", body)
    end

    def update_game_playtime(page_id:, game:)
      properties = {}
      properties[:"Playtime (Minutes)"] = { number: game[:playtime_forever] }
      if !game[:last_played_date].nil?
        properties[:"Last Played Date"] = {
          date: { start: game[:last_played_date].to_date.to_s },
        }
      end
      body = { properties: properties }
      patch("/v1/pages/#{page_id}", body)
    end

    def archive_page(page_id)
      patch("/v1/pages/#{page_id}", { archived: true })
    end

    def fetch_all_games_summary
      fetch_games.map { |page|
        props = page["properties"]
        {
          page_id: page["id"],
          name: props.dig("Name", "title", 0, "text", "content"),
          steam_id: props.dig("Steam ID", "number"),
          deku_deals_id: props.dig("Deku Deals ID", "rich_text", 0, "text", "content"),
          platforms: (props.dig("Platforms", "multi_select") || []).map { |p| p["name"] },
          playtime: props.dig("Playtime (Minutes)", "number") || 0,
        }
      }
    end

    private

    PLATFORM_UPGRADES = {
      "Nintendo Switch 2" => "Nintendo Switch",
    }.freeze

    def merge_platforms(existing, new_platform)
      platforms = existing.dup
      platforms << new_platform if new_platform && !new_platform.strip.empty?
      platforms.uniq!

      PLATFORM_UPGRADES.each do |upgrade, superseded|
        if platforms.include?(upgrade)
          platforms.delete(superseded)
        end
      end

      platforms
    end

    def build_update_properties(game:, details:, existing_platforms: [])
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
      merged_platforms = merge_platforms(existing_platforms, "Steam")
      properties[:Platforms] = {
        multi_select: merged_platforms.map { |p| { name: p } },
      }
      properties[:Format] = { select: { name: "Digital" } }

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
