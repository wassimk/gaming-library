require "dotenv/load"
require "awesome_print"
require "debug"
require_relative "gaming_library/steam_client"
require_relative "gaming_library/notion_client"

def steam_client
  @steam_client ||= GamingLibrary::SteamClient.new(
    api_key: ENV["STEAM_API_KEY"],
    user_id: ENV["STEAM_USER_ID"],
    excluded_game_ids: ENV["STEAM_EXCLUDED_GAME_IDS"].split(",").map(&:strip).map(&:to_i),
  )
end

def notion_client
  @notion_client ||= GamingLibrary::NotionClient.new(
    api_key: ENV["NOTION_API_KEY"],
    database_id: ENV["NOTION_DATABASE_ID"],
  )
end

def main
  notion_pages = notion_client.fetch_games
  notion_map = notion_client.games_map(notion_pages)

  puts "=" * 80
  puts "Steam games: #{steam_client.owned_games.count}"
  puts "Notion games: #{notion_map.count}"
  puts "=" * 80

  # Insert new games
  steam_client.owned_games.each do |game|
    next if notion_map.key?(game[:steam_id])
    next if steam_client.excluded?(game)

    code = notion_client.insert_game(game)
    if code == "200"
      puts "Added Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
    else
      puts "API error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
    end
  rescue StandardError => e
    puts "Program error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
    puts e.message
  end

  # Update existing games
  steam_client.owned_games.each do |game|
    next if steam_client.excluded?(game)

    page_id = notion_map[game[:steam_id]]
    if page_id.nil?
      puts "Game does not exist in Notion: #{game[:name]}"
      next
    end

    details = steam_client.game_details(game[:steam_id])
    if details.nil?
      puts "Game details API call for #{game[:name]} failed"
      next
    end

    notion_client.update_game(page_id: page_id, game: game, details: details)
    puts "Updated Notion for game: #{game[:name]} - #{game[:steam_id]}"
    sleep 1
  rescue StandardError => e
    puts "Program error updating Notion for game: #{game[:name]} - #{game[:steam_id]}"
    puts e.message
  end
end

main if __FILE__ == $PROGRAM_NAME
