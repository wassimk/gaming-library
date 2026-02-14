# Gaming Library

A Ruby script that syncs your Steam game library to a Notion database. It runs automatically via GitHub Actions on a daily and monthly schedule.

## How It Works

The script pulls your owned games from the Steam API and syncs them to a Notion database. It has two sync modes:

- **Incremental (default)** — Inserts new games and updates playtime for recently played games. Skips the expensive `appdetails` API call since metadata rarely changes. Only writes to Notion when data has actually changed.
- **Full sync (`--full-sync`)** — Fetches full metadata from `appdetails` for every game: publishers, developers, genres, release date, and cover art.

New games are always backfilled with full metadata on insert, regardless of sync mode. Playtime only updates when the new value is higher than what's in Notion, preserving any manual adjustments.

### Notion Properties

The sync manages these Notion database properties:

| Property | Source | Updated |
|----------|--------|---------|
| Name | Steam | Insert |
| Steam ID | Steam | Insert |
| Playtime (Minutes) | Steam | Insert, incremental, full |
| Last Played Date | Steam | Insert, incremental, full |
| Platforms | Hardcoded ("Steam") | Insert, full |
| Format | Hardcoded ("Digital") | Insert, full |
| Publishers | Steam appdetails | Backfill, full |
| Developers | Steam appdetails | Backfill, full |
| Genres | Steam appdetails | Backfill, full |
| Release Date | Steam appdetails | Backfill, full |
| Icon | Steam appdetails | Backfill, full |

## Setup

### Environment Variables

The following environment variables are required. Set them as [GitHub Actions secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) for automated runs, or in a local `.env` file for development.

| Variable | Description |
|----------|-------------|
| `STEAM_API_KEY` | Your [Steam Web API key](https://steamcommunity.com/dev/apikey) |
| `STEAM_USER_ID` | Your 64-bit Steam ID |
| `STEAM_EXCLUDED_GAME_IDS` | Comma-separated Steam app IDs to skip (e.g. tools, betas) |
| `NOTION_API_KEY` | Your [Notion integration](https://www.notion.so/my-integrations) API key |
| `NOTION_DATABASE_ID` | The ID from your Notion database URL |

### GitHub Actions

The script is designed to run on a schedule via GitHub Actions. See the workflows in [`.github/workflows/`](.github/workflows/):

- [**Daily Sync**](.github/workflows/daily-sync.yml) — Runs every day at 4:15 AM CST. Incremental mode: inserts new games, updates recently played.
- [**Monthly Sync**](.github/workflows/monthly-sync.yml) — Runs on the 1st of each month at 4:15 AM CST. Full sync: refreshes all game metadata.

Both workflows support `workflow_dispatch`, so you can trigger either manually from the **Actions** tab.

### Running Locally

You can also run the script locally for development or one-off syncs:

```shell
# Install dependencies
bundle install

# Incremental sync
bundle exec ruby lib/run.rb

# Full sync
bundle exec ruby lib/run.rb --full-sync
```

### Testing

```shell
bundle exec rake test
```
