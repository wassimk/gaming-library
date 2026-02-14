require "net/http"
require "json"
require "uri"
require "nokogiri"

module GamingLibrary
  class DekuDealsClient
    BASE_URL = "https://www.dekudeals.com"

    def initialize(collection_id:)
      @collection_id = collection_id
    end

    def collection
      @collection ||=
        fetch_collection_json.then { |response| parse_collection_json(response) }
    end

    def collection_details
      @collection_details ||=
        fetch_collection_html.then { |html| parse_collection_html(html) }
    end

    def game_details(slug)
      html = fetch_game_details(slug)
      parse_game_details(html)
    end

    private

    def fetch_collection_json
      uri = URI("#{BASE_URL}/collection/#{@collection_id}.json")
      response = Net::HTTP.get(uri)
      JSON.parse(response)
    end

    def fetch_collection_html
      uri = URI("#{BASE_URL}/collection/#{@collection_id}?per_page=500&page_size=all")
      Net::HTTP.get(uri)
    end

    def fetch_game_details(slug)
      uri = URI("#{BASE_URL}/items/#{slug}")
      Net::HTTP.get(uri)
    end

    def parse_collection_json(response)
      items = response["items"] || []
      items.map do |item|
        slug = URI.parse(item["link"]).path.split("/").last
        {
          name: item["name"],
          slug: slug,
          added_at: item["added_at"],
          format: item["format"],
        }
      end
    end

    def parse_collection_html(html)
      doc = Nokogiri::HTML(html)
      result = {}

      doc.css(".col.d-block").each do |card|
        link = card.at_css("a.main-link")
        next unless link

        slug = link["href"]&.split("/")&.last
        next unless slug

        name = card.at_css("h6")&.text&.strip
        image_url = card.at_css("img[src*='cdn.dekudeals.com']")&.[]("src")

        platform = nil
        format = nil
        card.css(".detail").each do |detail|
          label = detail.at_css("small")&.text&.strip
          value = detail.text.sub(label.to_s, "").strip
          case label
          when "Platform"
            platform = value
          when "Format"
            format = value
          end
        end

        result[slug] = {
          name: name,
          platform: platform,
          format: format,
          image_url: image_url,
        }
      end

      result
    end

    def parse_game_details(html)
      doc = Nokogiri::HTML(html)

      genres = doc.css('a[href*="filter[genre]"]').map { |a| a.text.strip }
      publishers = doc.css('a[href*="filter[publisher]"]').map { |a| a.text.strip }
      developers = doc.css('a[href*="filter[developer]"]').map { |a| a.text.strip }

      release_date = parse_release_date(doc)
      metacritic = parse_metacritic(doc)

      cover_img =
        doc.at_css('img.shadow-img-large[src*="cdn.dekudeals.com"]') ||
        doc.at_css('img.shadow-img-small[src*="cdn.dekudeals.com"]')
      image_url = cover_img&.[]("src")

      {
        genres: genres.empty? ? nil : genres,
        publishers: publishers.empty? ? nil : publishers,
        developers: developers.empty? ? nil : developers,
        release_date: release_date,
        metacritic: metacritic,
        image_url: image_url,
      }
    end

    def parse_release_date(doc)
      release_li = doc.css("li.list-group-item").find { |li|
        strong = li.at_css("strong")
        strong&.text&.include?("Release date")
      }
      return nil unless release_li

      nested_items = release_li.css("ul li")
      if nested_items.any?
        nested_items.first.children.select(&:text?).map(&:text).join.strip
      else
        release_li.children.select(&:text?).map(&:text).join.strip
      end
    end

    def parse_metacritic(doc)
      metacritic_link = doc.at_css("a.metacritic")
      return nil unless metacritic_link

      score_span = metacritic_link.at_css("span")
      score_span&.text&.strip&.to_i
    end
  end
end
