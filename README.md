# Gaming Library

Automatically sync your Steam game library to a Notion database. New purchases, playtime, genres, publishers, release dates, and cover art all stay up to date — no manual entry required.

The script runs on a schedule via GitHub Actions: a quick daily sync for playtime changes and new games, plus a monthly full refresh of all game metadata.

## Setup

### 1. Create a Notion Database

Set up a Notion database with properties for the fields you care about (e.g. Name, Playtime, Genres, Publishers, Release Date). The script will populate them automatically.

### 2. Configure Secrets

Fork this repo and add the following as [GitHub Actions secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions):

| Secret | Description |
|--------|-------------|
| `STEAM_API_KEY` | Your [Steam Web API key](https://steamcommunity.com/dev/apikey) |
| `STEAM_USER_ID` | Your 64-bit Steam ID |
| `STEAM_EXCLUDED_GAME_IDS` | Comma-separated Steam app IDs to skip (e.g. tools, betas) |
| `NOTION_API_KEY` | Your [Notion integration](https://www.notion.so/my-integrations) API key |
| `NOTION_DATABASE_ID` | The ID from your Notion database URL |

### 3. Enable the Workflows

Two GitHub Actions workflows handle everything. See [`.github/workflows/`](.github/workflows/):

- [**Daily Sync**](.github/workflows/daily-sync.yml) — Adds new games and updates playtime for recently played games.
- [**Monthly Sync**](.github/workflows/monthly-sync.yml) — Refreshes all game metadata (genres, publishers, release dates, cover art).

Both can be triggered manually from the **Actions** tab whenever you want.

## Running Locally

You can also run the script on your machine with a `.env` file containing the same variables listed above.

```shell
bundle install
bundle exec ruby lib/run.rb            # daily sync
bundle exec ruby lib/run.rb --full-sync # full metadata refresh
```

## Development

```shell
bundle exec rake test
```
