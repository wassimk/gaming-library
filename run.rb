require "dotenv/load"
require "awesome_print"
require "net/http"
require "json"
require "uri"
require "debug"
require "date"

def steam_games
  @steam_games ||=
    fetch_steam_owned_games.then { |response| parse_fetch_steam_games_response(response) }
end

def excluded_steam_games
  @excluded_steam_games ||=
    begin
      excluded_steam_games_ids = ENV["STEAM_EXCLUDE_GAME_IDS"].split(",").map(&:strip).map(&:to_i)

      steam_games
        .select { |game| excluded_steam_games_ids.include?(game[:steam_id]) }
        .sort_by { |game| game[:name] }
    end
end

def excluded_steam_game?(game)
  excluded_steam_games.map { |game| game[:steam_id] }.include?(game[:steam_id])
end

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

def parse_fetch_steam_games_response(response)
  games = response["response"]["games"]
  games.map do |game|
    icon_url =
      "http://media.steampowered.com/steamcommunity/public/images/apps/#{game["appid"]}/#{game["img_icon_url"]}.jpg"
    last_played_date =
      (game["rtime_last_played"].positive? ? Time.at(game["rtime_last_played"]) : nil)

    {
      name: game["name"],
      playtime_forever: game["playtime_forever"],
      last_played_date: last_played_date,
      icon_url: icon_url,
      steam_id: game["appid"],
    }
  end
end

def fetch_deku_games
  uri = URI("https://www.dekudeals.com/collection/#{ENV["DEKU_DEALS_COLLECTION_ID"]}.json")
  response = Net::HTTP.get(uri)

  JSON.parse(response)
end

def fetch_notion_games
  uri = URI("https://api.notion.com/v1/databases/#{ENV["NOTION_DATABASE_ID"]}/query")
  header = {
    Authorization: "Bearer #{ENV["NOTION_API_KEY"]}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28",
  }

  all_results = []
  has_more = true
  start_cursor = nil

  while has_more
    body = {}
    body[:start_cursor] = start_cursor if start_cursor
    body = body.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.path, header)
    request.body = body
    response = http.request(request)
    data = JSON.parse(response.body)

    all_results.concat(data["results"])
    has_more = data["has_more"]
    start_cursor = data["next_cursor"]
  end

  all_results
end

def insert_notion_database(steam_games, notion_games)
  uri = URI("https://api.notion.com/v1/pages")
  header = {
    Authorization: "Bearer #{ENV["NOTION_API_KEY"]}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28",
  }

  notion_games_map =
    notion_games.map { |page| [page["properties"]["Steam ID"]["number"], page["id"]] }.to_h

  puts "=" * 80
  puts "Inserting into Notion database"
  puts "Working with #{notion_games_map.count} Notion games"
  puts "Working with #{steam_games.count} Steam games"
  puts "=" * 80
  puts "Excluding #{excluded_steam_games.count} Steam games:"
  puts(excluded_steam_games.map { |game| "#{game[:name]} - #{game[:steam_id]}" })
  puts "=" * 80

  steam_games.each do |game|
    body = {
      properties: {
        Name: {
          title: [{ text: { content: game[:name] } }],
        },
        "Playtime (Minutes)": {
          number: game[:playtime_forever],
        },
        "Steam ID": {
          number: game[:steam_id],
        },
      },
    }

    next if notion_games_map.key?(game[:steam_id]) # game already exists in Notion
    # exclude this game
    next if excluded_steam_game?(game)

    uri = URI("https://api.notion.com/v1/pages")
    request = Net::HTTP::Post.new(uri.path, header)
    body[:parent] = { database_id: ENV["NOTION_DATABASE_ID"] }
    request.body = body.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response = http.request(request)
    if response.code == "200"
      puts "Added Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
    else
      puts "API error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
    end
  rescue StandardError => e
    puts "Program error adding Notion entry for game: #{game[:name]} - #{game[:steam_id]}"
    puts e.message
    binding.break
  end
end

def update_notion_database(steam_games, notion_games)
  header = {
    Authorization: "Bearer #{ENV["NOTION_API_KEY"]}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28",
  }

  notion_games_map =
    notion_games.map { |page| [page["properties"]["Steam ID"]["number"], page["id"]] }.to_h

  puts "=" * 80
  puts "Updating Notion database"
  puts "Working with #{notion_games_map.count} Notion games"
  puts "Working with #{steam_games.count} Steam games"
  puts "=" * 80

  steam_games.each do |game|
    game_details = fetch_steam_game_details(game[:steam_id])

    if game_details[game[:steam_id].to_s]["success"] == false
      puts "Game details API call for #{game[:name]} failed"
      next
    end

    details = game_details[game[:steam_id].to_s]["data"]
    publishers = details["publishers"]
    developers = details["developers"]
    genres = details["genres"].map { |genre| genre["description"] }
    release_date =
      begin
        Date.parse(details["release_date"]["date"].scan(/[,\w+\s]/).join)
      rescue StandardError # some steam_games have bad dates like Warhammer 40K: Space Marine II
        nil
      end
    last_played_date = game[:last_played_date]
    icon_url = game[:icon_url]
    logo_url = details["capsule_imagev5"]

    # ap "#{game[:name]} - #{game[:steam_id]}"
    # ap icon_url
    # ap logo_url
    # ap publishers&.join(", ")
    # ap developers&.join(", ")
    # ap genres&.join(", ")
    # ap release_date.to_s + " from " + details["release_date"]["date"]
    # ap last_played_date

    properties = {}
    if !publishers.nil?
      properties[:Publishers] = {
        multi_select: publishers.map { |publisher| { name: publisher.gsub(",", "") } },
      }
    end
    if !developers.nil?
      properties[:Developers] = {
        multi_select: developers.map { |developer| { name: developer.gsub(",", "") } },
      }
    end
    if !genres.nil?
      properties[:Genres] = { multi_select: genres.map { |genre| { name: genre.gsub(",", "") } } }
    end

    properties["Release Date".to_sym] = { date: { start: release_date.to_s } } if !release_date.nil?

    if !icon_url.nil?
      properties["Icon".to_sym] = {
        files: [
          # { name: "icon", type: "external", external: { url: icon_url } },
          { name: "logo", type: "external", external: { url: logo_url } },
        ],
      }
    end

    if !last_played_date.nil?
      properties["Last Played Date".to_sym] = { date: { start: last_played_date.to_date.to_s } }
    end

    properties["Playtime (Minutes)".to_sym] = { number: game[:playtime_forever] }

    body = { properties: properties }.to_json

    page_id = notion_games_map[game[:steam_id]]

    next if excluded_steam_game?(game)

    if page_id.nil?
      puts "Game does not exist in Notion: #{game[:name]}"
      next
    end

    uri = URI("https://api.notion.com/v1/pages/#{page_id}")
    request = Net::HTTP::Patch.new(uri.path, header)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request.body = body
    response = http.request(request)

    if response.code == "200"
      puts "Updated Notion for game: #{game[:name]} - #{game[:steam_id]}"
    else
      puts uri
      puts JSON.parse(request.body)
      puts "API error updating Notion for game: #{game[:name]} - #{game[:steam_id]}"
      puts response.body
      binding.break
    end
    sleep 1
  rescue StandardError => e
    puts "Program error updating Notion for game: #{game[:name]} - #{game[:steam_id]}"
    puts e.message
    binding.break
  end
end

def main
  notion_response = fetch_notion_games
  insert_notion_database(steam_games, notion_response)
  update_notion_database(steam_games, notion_response)
end

main if __FILE__ == $PROGRAM_NAME
