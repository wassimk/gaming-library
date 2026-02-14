module GamingLibrary
  class GameSync
    def initialize(steam_client:, notion_client:, full_sync: false, game_filter: nil, output: $stdout)
      @steam = steam_client
      @notion = notion_client
      @full_sync = full_sync
      @game_filter = game_filter
      @output = output
    end

    def call
      notion_pages = filtered_notion_pages
      @notion_map = @notion.games_map(notion_pages)

      log_summary
      insert_new_games
      update_existing_games
    end

    private

    def insert_new_games
      @output.puts "=" * 80
      @output.puts "Inserting new games into Notion"
      @output.puts "=" * 80

      games_to_sync.each do |game|
        next if @notion_map.key?(game[:steam_id])
        next if @steam.excluded?(game)

        details = @steam.game_details(game[:steam_id])
        if details && details["type"] == "demo"
          @output.puts "Skipping #{game[:name]} (demo)"
          next
        end

        code = @notion.insert_game(game)
        if code == "200"
          @output.puts "Added Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
          backfill_new_game(game, details)
        else
          @output.puts "API error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
        end
      rescue StandardError => e
        @output.puts "Program error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
        @output.puts e.message
      end
    end

    def backfill_new_game(game, details = nil)
      details ||= @steam.game_details(game[:steam_id])
      if details.nil?
        @output.puts "Game details API call for #{game[:name]} failed during backfill"
        return
      end

      notion_pages = @notion.fetch_games
      notion_map = @notion.games_map(notion_pages)
      notion_data = notion_map[game[:steam_id]]
      return if notion_data.nil?

      @notion.update_game(
        page_id: notion_data[:page_id],
        game: game,
        details: details,
        existing_platforms: notion_data[:platforms] || [],
      )
      @output.puts "Backfilled metadata for game: #{game[:name]}"
      sleep 1
    rescue StandardError => e
      @output.puts "Program error backfilling game: #{game[:name]}"
      @output.puts e.message
    end

    def update_existing_games
      @output.puts "=" * 80
      if @full_sync
        @output.puts "Full sync: updating all existing games in Notion"
      else
        @output.puts "Incremental sync: updating recently played games in Notion"
      end
      @output.puts "=" * 80

      games_to_sync.each do |game|
        next if @steam.excluded?(game)

        notion_data = @notion_map[game[:steam_id]]
        if notion_data.nil?
          @output.puts "Game does not exist in Notion: #{game[:name]}"
          next
        end

        if @full_sync
          full_update_game(notion_data, game)
        else
          incremental_update_game(notion_data, game)
        end
      rescue StandardError => e
        @output.puts "Program error updating Notion for game: #{game[:name]} - #{game[:steam_id]}"
        @output.puts e.message
      end
    end

    def full_update_game(notion_data, game)
      details = @steam.game_details(game[:steam_id])
      if details.nil?
        @output.puts "Game details API call for #{game[:name]} failed"
        return
      end

      if details["type"] == "demo"
        @output.puts "Skipping #{game[:name]} (demo)"
        return
      end

      @notion.update_game(
        page_id: notion_data[:page_id],
        game: game,
        details: details,
        existing_platforms: notion_data[:platforms] || [],
      )
      @output.puts "Updated Notion for game: #{game[:name]} - #{game[:steam_id]}"
      sleep 1
    end

    def incremental_update_game(notion_data, game)
      if game[:playtime_2weeks].nil? || game[:playtime_2weeks] == 0
        @output.puts "Skipping #{game[:name]} (no recent playtime)"
        return
      end

      if !playtime_changed?(notion_data, game)
        @output.puts "Skipping #{game[:name]} (no changes)"
        return
      end

      @notion.update_game_playtime(page_id: notion_data[:page_id], game: game)
      @output.puts "Updated playtime for game: #{game[:name]} - #{game[:steam_id]}"
    end

    def playtime_changed?(notion_data, game)
      return true if game[:playtime_forever] > (notion_data[:playtime] || 0)

      steam_date = game[:last_played_date]&.to_date&.to_s
      steam_date != nil && steam_date != notion_data[:last_played_date]
    end

    def filtered_notion_pages
      if @game_filter.nil?
        @notion.fetch_games
      elsif @game_filter.match?(/\A\d+\z/)
        @notion.fetch_games_by_steam_id(@game_filter.to_i)
      else
        @notion.fetch_games_by_name(@game_filter)
      end
    end

    def games_to_sync
      return @steam.owned_games if @game_filter.nil?

      matched = @steam.owned_games.select { |g| game_matches?(g) }
      if matched.empty?
        @output.puts "No Steam games matched filter: #{@game_filter}"
      end
      matched
    end

    def game_matches?(game)
      if @game_filter.match?(/\A\d+\z/)
        game[:steam_id] == @game_filter.to_i
      else
        game[:name].downcase.include?(@game_filter.downcase)
      end
    end

    def log_summary
      @output.puts "=" * 80
      @output.puts "Steam games: #{@steam.owned_games.count}"
      @output.puts "Notion games: #{@notion_map.count}"
      @output.puts "Sync mode: #{@full_sync ? "full" : "incremental"}"
      @output.puts "Game filter: #{@game_filter}" if @game_filter
      @output.puts "=" * 80
    end
  end
end
