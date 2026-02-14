require "dotenv/load"
require "json"
require_relative "gaming_library/notion_client"

notion = GamingLibrary::NotionClient.new(
  api_key: ENV["NOTION_API_KEY"],
  database_id: ENV["NOTION_DATABASE_ID"],
)

games = notion.fetch_all_games_summary
puts JSON.pretty_generate(games)
