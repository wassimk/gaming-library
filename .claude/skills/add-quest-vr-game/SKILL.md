---
name: add-quest-vr-game
description: Add Meta Quest VR games to the Notion gaming library with cover art images
argument-hint: "game1, game2, ..."
user-invocable: true
disable-model-invocation: true
---

# Add VR Games to Notion Gaming Library

You are helping the user add Meta Quest VR games to their Notion gaming library. The user provides one or more game names as comma-separated arguments.

## Input

Parse `$ARGUMENTS` as a comma-separated list of game names. Trim whitespace from each name.

## Workflow

Repeat the following steps for **each game** in the list.

### Step 1: Check for duplicates

Run a Ruby one-liner to check if the game already exists in the Notion database:

```ruby
bundle exec ruby -e '
require "dotenv/load"
require_relative "lib/gaming_library/notion_client"

notion = GamingLibrary::NotionClient.new(
  api_key: ENV["NOTION_API_KEY"],
  database_id: ENV["NOTION_DATABASE_ID"],
)

results = notion.fetch_games_by_name("GAME_NAME")
results.each do |page|
  name = page.dig("properties", "Name", "title", 0, "text", "content")
  platforms = (page.dig("properties", "Platforms", "multi_select") || []).map { |p| p["name"] }.join(", ")
  puts "#{name} [#{platforms}] (#{page["id"]})"
end
puts "No matches found" if results.empty?
'
```

- If an exact or near-exact match exists with platform "Meta Quest", inform the user the game is already in the library and **skip** it.
- If a match exists on a different platform only, note this but continue — the user may want a separate Meta Quest entry.
- If no match is found, proceed to Step 2.

### Step 2: Find cover art

Search for a landscape-oriented cover art image URL for the game. Try these sources in order:

1. **Steam store page** — Use WebSearch to find the Steam store page, then WebFetch to extract the `header_image` or `capsule_imagev5` URL (these are landscape 460x215 or 616x353 images). Preferred source.
2. **Meta Quest store** — Search for the game on the Meta Quest store and extract the hero/banner image URL.
3. **IGDB** — Search IGDB for the game and find a cover or screenshot URL.
4. **SideQuest** — For sideloaded or lesser-known titles, check SideQuest CDN.

Prefer landscape images (wider than tall). Steam header images (`capsule_imagev5` or URLs containing `/header.jpg`) are ideal.

### Step 3: Confirm with user

Use `AskUserQuestion` to present:

- **Game name** as entered
- **Image URL** found (or note if none was found)
- **Image preview** — show the URL so the user can verify it

Ask whether to proceed with the insertion, skip this game, or use a different image URL.

### Step 4: Insert into Notion

Run a Ruby one-liner to insert the game:

```ruby
bundle exec ruby -e '
require "dotenv/load"
require_relative "lib/gaming_library/notion_client"

notion = GamingLibrary::NotionClient.new(
  api_key: ENV["NOTION_API_KEY"],
  database_id: ENV["NOTION_DATABASE_ID"],
)

game = {
  name: "GAME_NAME",
  slug: "",
  platform: "Meta Quest",
  format: "Digital",
  image_url: "IMAGE_URL",
}

code = notion.insert_deku_deals_game(game: game, details: nil)
puts "Insert response: #{code}"
'
```

Replace `GAME_NAME` and `IMAGE_URL` with the actual values. If no image was found and the user chose to proceed without one, set `image_url: nil`.

A response code of `200` indicates success.

### Step 5: Report results

After processing all games, present a summary table:

| Game | Status | Image |
|------|--------|-------|
| Beat Saber | Added | (steam header) |
| SUPERHOT VR | Skipped (duplicate) | — |
| Puzzling Places | Failed (error msg) | — |
