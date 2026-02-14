require "dotenv/load"
require "awesome_print"
require "debug"
require_relative "gaming_library/steam_client"
require_relative "gaming_library/notion_client"
require_relative "gaming_library/game_sync"

def main
  full_sync = ARGV.include?("--full-sync")

  steam_client = GamingLibrary::SteamClient.new(
    api_key: ENV["STEAM_API_KEY"],
    user_id: ENV["STEAM_USER_ID"],
    excluded_game_ids: ENV["STEAM_EXCLUDED_GAME_IDS"].split(",").map(&:strip).map(&:to_i),
  )

  notion_client = GamingLibrary::NotionClient.new(
    api_key: ENV["NOTION_API_KEY"],
    database_id: ENV["NOTION_DATABASE_ID"],
  )

  GamingLibrary::GameSync.new(
    steam_client: steam_client,
    notion_client: notion_client,
    full_sync: full_sync,
  ).call
end

main if __FILE__ == $PROGRAM_NAME
