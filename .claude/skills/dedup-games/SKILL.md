---
name: dedup-games
description: Find and resolve duplicate games in the Notion gaming library
user-invocable: true
disable-model-invocation: true
---

# Dedup Games in Notion Gaming Library

You are helping the user find and merge duplicate game entries in their Notion gaming library. Duplicates typically arise from Deku Deals syncing edition variants as separate games (e.g., "Cyberpunk 2077" from Steam and "Cyberpunk 2077 Ultimate Edition" from Deku Deals).

## Workflow

### Step 1: Dump all games

Run the dump script to get the current game list:

```
bundle exec ruby lib/dump_games.rb > /tmp/games.json
```

Read the resulting `/tmp/games.json` file.

### Step 2: Analyze for duplicates

Scan the game list and identify potential duplicate groups. Look for:

- **Edition variants**: Same base name with edition suffixes like "Ultimate Edition", "Deluxe Edition", "GOTY Edition", "Digital Deluxe Edition", "Complete Edition", "Game of the Year Edition", "Definitive Edition", "Enhanced Edition", "Remastered", "HD", "Anniversary Edition", etc.
- **Substring matches**: One game name is a substring of another (e.g., "Hades" and "Hades II" are NOT duplicates, but "Dark Souls" and "Dark Souls: Remastered" could be)
- **Same Steam ID**: Multiple entries sharing the same Steam ID
- **Punctuation/encoding differences**: Curly vs straight apostrophes, special characters, etc. (e.g., "Demon's Souls" vs "Demon\u2019s Souls")

Be careful NOT to flag these as duplicates:
- Numbered sequels (e.g., "Hades" and "Hades II", "Portal" and "Portal 2")
- Different games with similar names (e.g., "DOOM" and "DOOM Eternal")
- DLC entries that are intentionally separate

### Step 3: Present findings

For each duplicate group, present a table showing:

| Field | Entry A | Entry B |
|-------|---------|---------|
| Name | ... | ... |
| Page ID | ... | ... |
| Steam ID | ... | ... |
| Deku Deals ID | ... | ... |
| Platforms | ... | ... |
| Playtime | ... | ... |

Recommend which entry to **keep** based on overall data richness. Some entries may have been manually curated by the user and contain significantly more data. Prefer to keep the entry that has:

1. More data overall (the "richer" entry — this is the strongest signal)
2. Has a Steam ID (enables automatic metadata sync)
3. Has playtime data
4. Has more platforms listed
5. Has a Deku Deals ID (useful for price tracking)

When in doubt, ask the user — they may have added data by hand and will know which entry is more complete.

If no duplicates are found, inform the user and stop.

### Step 4: Confirm with user

Use `AskUserQuestion` for each duplicate group to ask the user which entry to keep, or whether to skip that group. Present the recommendation clearly. Since some entries are hand-curated, always show what each entry has so the user can make an informed choice.

### Step 5: Merge and archive

For each confirmed duplicate group, execute a Ruby one-liner via `bundle exec ruby -e '...'` that:

1. Loads the environment and NotionClient
2. Merges platforms from all entries onto the keeper (union of all platforms)
3. Transfers the Deku Deals ID to the keeper if it doesn't already have one
4. Transfers the Steam ID to the keeper if it doesn't already have one
5. Archives all non-keeper entries using `archive_page`

**Important**: Only merge in attributes the keeper is missing — never overwrite existing data on the keeper, since it may have been manually curated.

Example Ruby one-liner pattern:

```ruby
bundle exec ruby -e '
require "dotenv/load"
require_relative "lib/gaming_library/notion_client"

notion = GamingLibrary::NotionClient.new(
  api_key: ENV["NOTION_API_KEY"],
  database_id: ENV["NOTION_DATABASE_ID"],
)

keeper_id = "KEEPER_PAGE_ID"
dupe_ids = ["DUPE_PAGE_ID_1"]
merged_platforms = ["Steam", "Nintendo Switch"]  # union of all platforms
deku_deals_id = "slug-value"  # from the dupe, if keeper lacks one (nil to skip)
steam_id = 12345  # from the dupe, if keeper lacks one (nil to skip)

properties = {
  Platforms: { multi_select: merged_platforms.map { |p| { name: p } } },
}
if deku_deals_id
  properties[:"Deku Deals ID"] = { rich_text: [{ text: { content: deku_deals_id } }] }
end
if steam_id
  properties[:"Steam ID"] = { number: steam_id }
end

notion.send(:patch, "/v1/pages/#{keeper_id}", { properties: properties })
dupe_ids.each { |id| notion.archive_page(id) }
puts "Merged and archived duplicates for keeper #{keeper_id}"
'
```

### Step 6: Re-sync metadata

After merging, re-sync the keeper's metadata by running:

```
bundle exec ruby lib/run.rb --full-sync --game "<partial_name>"
```

Use a partial name that avoids special characters (curly apostrophes, colons, etc.) to ensure the filter matches. For example, use `"Demon"` instead of `"Demon's Souls"`.

### Step 7: Verify

Run the dump script again and confirm the duplicates are resolved:

```
bundle exec ruby lib/dump_games.rb > /tmp/games.json
```

Report the final results to the user.
