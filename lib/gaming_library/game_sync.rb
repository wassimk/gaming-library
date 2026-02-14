module GamingLibrary
  class GameSync
    def initialize(steam_client:, notion_client:, output: $stdout)
      @steam = steam_client
      @notion = notion_client
      @output = output
    end

    def call
      notion_pages = @notion.fetch_games
      notion_map = @notion.games_map(notion_pages)

      log_summary(notion_map)
      insert_new_games(notion_map)
      update_existing_games(notion_map)
    end

    private

    def insert_new_games(notion_map)
      @output.puts "=" * 80
      @output.puts "Inserting new games into Notion"
      @output.puts "=" * 80

      @steam.owned_games.each do |game|
        next if notion_map.key?(game[:steam_id])
        next if @steam.excluded?(game)

        code = @notion.insert_game(game)
        if code == "200"
          @output.puts "Added Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
        else
          @output.puts "API error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
        end
      rescue StandardError => e
        @output.puts "Program error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
        @output.puts e.message
      end
    end

    def update_existing_games(notion_map)
      @output.puts "=" * 80
      @output.puts "Updating existing games in Notion"
      @output.puts "=" * 80

      @steam.owned_games.each do |game|
        next if @steam.excluded?(game)

        page_id = notion_map[game[:steam_id]]
        if page_id.nil?
          @output.puts "Game does not exist in Notion: #{game[:name]}"
          next
        end

        details = @steam.game_details(game[:steam_id])
        if details.nil?
          @output.puts "Game details API call for #{game[:name]} failed"
          next
        end

        @notion.update_game(page_id: page_id, game: game, details: details)
        @output.puts "Updated Notion for game: #{game[:name]} - #{game[:steam_id]}"
        sleep 1
      rescue StandardError => e
        @output.puts "Program error updating Notion for game: #{game[:name]} - #{game[:steam_id]}"
        @output.puts e.message
      end
    end

    def log_summary(notion_map)
      @output.puts "=" * 80
      @output.puts "Steam games: #{@steam.owned_games.count}"
      @output.puts "Notion games: #{notion_map.count}"
      @output.puts "=" * 80
    end
  end
end
