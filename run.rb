#!/usr/bin/env ruby

require "dotenv/load"
require "awesome_print"
require "net/http"
require "json"
require "uri"
require "debug"

# Method to query the Steam API
def fetch_steam_owned_games
  uri =
    URI(
      "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=#{ENV["STEAM_API_KEY"]}&steamid=#{ENV["STEAM_USER_ID"]}&include_appinfo=true",
    )
  response = Net::HTTP.get(uri)
  JSON.parse(response)
end

def fetch_steam_game_details(appid)
  uri = URI("https://store.steampowered.com/api/appdetails?appids=#{appid}")
  response = Net::HTTP.get(uri)
  JSON.parse(response)
end

def parse_steam_games(response)
  games = response["response"]["games"]
  games.map do |game|
    icon =
      "http://media.steampowered.com/steamcommunity/public/images/apps/#{game["appid"]}/#{game["img_icon_url"]}.jpg"
    {
      name: game["name"],
      playtime_forever: game["playtime_forever"],
      icon: icon,
      steam_id: game["appid"],
    }
  end
end

def fetch_notion_games # rubocop:disable Metrics/MethodLength
  uri = URI("https://api.notion.com/v1/databases/#{ENV["NOTION_DATABASE_ID"]}/query")
  header = {
    Authorization: "Bearer #{ENV["NOTION_API_KEY"]}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28",
  }
  body = {}.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.path, header)
  request.body = body
  response = http.request(request)
  JSON.parse(response.body)
end

def upsert_notion_database(games, notion_games) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  uri = URI("https://api.notion.com/v1/pages")
  header = {
    Authorization: "Bearer #{ENV["NOTION_API_KEY"]}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28",
  }

  notion_games_map =
    notion_games["results"]
      .map { |page| [page["properties"]["Steam ID"]["number"], page["id"]] }
      .to_h

  games.each do |game|
    body = {
      properties: {
        Name: {
          title: [{ text: { content: game[:name] } }],
        },
        Playtime: {
          number: game[:playtime_forever],
        },
        "Steam ID": {
          number: game[:steam_id],
        },
      },
    }

    uri = nil

    request =
      if notion_games_map.key?(game[:steam_id])
        page_id = notion_games_map[game[:steam_id]]
        uri = URI("https://api.notion.com/v1/pages/#{page_id}")
        Net::HTTP::Patch.new(uri.path, header)
      else
        puts "Game does not exist in Notion: #{game[:name]}"
        uri = URI("https://api.notion.com/v1/pages")
        body[:parent] = { database_id: ENV["NOTION_DATABASE_ID"] }
        Net::HTTP::Post.new(uri.path, header)
      end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request.body = body.to_json

    response = http.request(request)
    if response.code == "200"
      puts "Upserted Notion for game: #{game[:name]}"
    else
      puts "API error upserting Notion for game: #{game[:name]}"
      binding.break
      exit
    end
  rescue StandardError => e
    puts "Program error upserting Notion for game: #{game[:name]}"
    puts e.message
    exit
  end
end

def update_notion_database(games, notion_games)
  header = {
    Authorization: "Bearer #{ENV["NOTION_API_KEY"]}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28",
  }

  notion_games_map =
    notion_games["results"]
      .map { |page| [page["properties"]["Steam ID"]["number"], page["id"]] }
      .to_h

  games.each do |game|
    game_details = fetch_steam_game_details(game[:steam_id])
    details = game_details[game[:steam_id].to_s]["data"]
    publishers = details["publishers"]&.join(", ").to_s
    developers = details["developers"]&.join(", ").to_s
    genres = details["genres"].map { |genre| genre["description"] }&.join(", ").to_s

    body = {
      properties: {
        Publishers: {
          rich_text: [{ type: "text", text: { content: publishers, link: nil } }],
        },
        Developers: {
          rich_text: [{ type: "text", text: { content: developers, link: nil } }],
        },
        Genres: {
          rich_text: [{ type: "text", text: { content: genres, link: nil } }],
        },
      },
    }.to_json

    page_id = notion_games_map[game[:steam_id]]
    uri = URI("https://api.notion.com/v1/pages/#{page_id}")

    next unless notion_games_map.key?(game[:steam_id])

    request = Net::HTTP::Patch.new(uri.path, header)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request.body = body
    response = http.request(request)
    if response.code == "200"
      puts "Updated Notion for game: #{game[:name]}"
    else
      puts uri
      puts JSON.parse(request.body)
      puts "API error updating Notion for game: #{game[:name]}"
      exit
    end
    sleep 1
  rescue StandardError => e
    puts "Program error updating Notion for game: #{game[:name]}"
    puts e.message
    exit
  end
end

def main
  steam_games = fetch_steam_owned_games
  games = parse_steam_games(steam_games)
  notion_response = fetch_notion_games
  upsert_notion_database(games, notion_response)
  # update_notion_database(games, notion_response)
end

main if __FILE__ == $PROGRAM_NAME
