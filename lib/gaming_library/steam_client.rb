require "net/http"
require "json"
require "uri"

module GamingLibrary
  class SteamClient
    def initialize(api_key:, user_id:, excluded_game_ids: [])
      @api_key = api_key
      @user_id = user_id
      @excluded_game_ids = excluded_game_ids
    end

    def owned_games
      @owned_games ||=
        fetch_owned_games.then { |response| parse_owned_games(response) }
    end

    def game_details(appid)
      response = fetch_game_details(appid)
      entry = response[appid.to_s]
      return nil if entry["success"] == false

      entry["data"]
    end

    def excluded?(game)
      @excluded_game_ids.include?(game[:steam_id])
    end

    private

    def fetch_owned_games
      uri = URI(
        "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/" \
        "?key=#{@api_key}&steamid=#{@user_id}&include_appinfo=true",
      )
      response = Net::HTTP.get(uri)
      JSON.parse(response)
    end

    def fetch_game_details(appid)
      uri = URI("https://store.steampowered.com/api/appdetails?appids=#{appid}")
      response = Net::HTTP.get(uri)
      JSON.parse(response)
    end

    def parse_owned_games(response)
      games = response["response"]["games"]
      games.map do |game|
        icon_url =
          "http://media.steampowered.com/steamcommunity/public/images/apps/" \
          "#{game["appid"]}/#{game["img_icon_url"]}.jpg"
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
  end
end
