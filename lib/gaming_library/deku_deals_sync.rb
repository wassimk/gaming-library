module GamingLibrary
  class DekuDealsSync
    PLATFORM_MAP = {
      "Steam" => "Steam",
      "PS5" => "PlayStation 5",
      "PS4" => "PlayStation 4",
      "Switch" => "Nintendo Switch",
      "Switch 2" => "Nintendo Switch 2",
      "Xbox X|S" => "Xbox Series X|S",
    }.freeze

    # When the upgrade is present, the superseded platform is redundant
    PLATFORM_UPGRADES = {
      "Nintendo Switch 2" => "Nintendo Switch",
    }.freeze

    def initialize(deku_deals_client:, notion_client:, full_sync: false, output: $stdout)
      @deku_deals = deku_deals_client
      @notion = notion_client
      @full_sync = full_sync
      @output = output
    end

    def call
      notion_pages = @notion.fetch_games
      @name_map = @notion.games_map_by_name(notion_pages)
      @deku_id_map = build_deku_id_map

      game_list = build_game_list
      log_summary(game_list)
      insert_or_merge_games(game_list)
      update_all_metadata(game_list) if @full_sync
    end

    private

    def build_deku_id_map
      @name_map
        .each_with_object({}) do |(_, data), map|
          map[data[:deku_deals_id]] = data if data[:deku_deals_id]
        end
    end

    def build_game_list
      json_items = @deku_deals.collection
      html_details = @deku_deals.collection_details

      json_by_slug = json_items.each_with_object({}) do |item, map|
        map[item[:slug]] ||= item
      end

      html_details.map do |slug, html_data|
        json_data = json_by_slug[slug]
        platform = platform_name(html_data[:platform])

        {
          name: html_data[:name],
          slug: slug,
          platform: platform,
          format: html_data[:format] || json_data&.dig(:format),
          image_url: html_data[:image_url],
          added_at: json_data&.dig(:added_at),
        }
      end
    end

    def insert_or_merge_games(game_list)
      @output.puts "=" * 80
      @output.puts "Syncing Deku Deals games to Notion"
      @output.puts "=" * 80

      game_list.each do |game|
        existing = find_existing(game)

        if existing
          merge_platform(existing, game)
        else
          insert_game(game)
        end
      rescue StandardError => e
        @output.puts "Error syncing Deku Deals game: #{game[:name]}"
        @output.puts e.message
      end
    end

    def find_existing(game)
      @deku_id_map[game[:slug]] || @name_map[game[:name]&.strip&.downcase]
    end

    def merge_platform(existing, game)
      return if existing[:platforms].include?(game[:platform])
      return if platform_superseded?(existing[:platforms], game[:platform])

      details = @deku_deals.game_details(game[:slug])

      @notion.update_deku_deals_game(
        page_id: existing[:page_id],
        game: game,
        details: details,
        existing_platforms: existing[:platforms],
      )
      @output.puts "Merged platform #{game[:platform]} for: #{game[:name]}"
      sleep 1
    end

    def insert_game(game)
      details = @deku_deals.game_details(game[:slug])

      code = @notion.insert_deku_deals_game(game: game, details: details)
      if code == "200"
        @output.puts "Added Deku Deals game: #{game[:name]} (#{game[:platform]})"
      else
        @output.puts "API error adding Deku Deals game: #{game[:name]}"
      end
      sleep 1
    end

    def update_all_metadata(game_list)
      @output.puts "=" * 80
      @output.puts "Full sync: updating all Deku Deals game metadata"
      @output.puts "=" * 80

      game_list.each do |game|
        existing = find_existing(game)
        next unless existing

        details = @deku_deals.game_details(game[:slug])

        @notion.update_deku_deals_game(
          page_id: existing[:page_id],
          game: game,
          details: details,
          existing_platforms: existing[:platforms],
        )
        @output.puts "Updated metadata for: #{game[:name]}"
        sleep 1
      rescue StandardError => e
        @output.puts "Error updating Deku Deals game: #{game[:name]}"
        @output.puts e.message
      end
    end

    def platform_superseded?(existing_platforms, new_platform)
      PLATFORM_UPGRADES.any? { |upgrade, superseded|
        new_platform == superseded && existing_platforms.include?(upgrade)
      }
    end

    def platform_name(raw)
      PLATFORM_MAP[raw] || raw
    end

    def log_summary(game_list)
      @output.puts "=" * 80
      @output.puts "Deku Deals games: #{game_list.count}"
      @output.puts "Notion games: #{@name_map.count}"
      @output.puts "Sync mode: #{@full_sync ? "full" : "incremental"}"
      @output.puts "=" * 80
    end
  end
end
