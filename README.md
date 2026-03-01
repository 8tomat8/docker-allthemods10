
# [All the Mods 10-6.0.1](https://www.curseforge.com/minecraft/modpacks/all-the-mods-10) on Curseforge
<!-- toc -->

- [Description](#description)
- [Requirements](#requirements)
- [Docker Compose](#docker-compose)
- [Options](#options)
  * [Adding Minecraft Operators](#adding-minecraft-operators)
- [Troubleshooting](#troubleshooting)
  * [Accept the EULA](#accept-the-eula)
  * [Permissions of Files](#permissions-of-files)
  * [Resetting](#resetting)
- [Source](#source-original-atm9-repo)

<!-- tocstop -->

## Description

This container is built to run on an [Unraid](https://unraid.net) server, outside of that your mileage will vary.


The docker on the first run will download the same version as tagged `All the Mods 10-6.0.1` and install it.  This can take a while as the Forge installer can take a bit to complete.  You can watch the logs and it will eventually finish.

After the first run, it will simply start the server.

Note: There are no modded Minecraft files shipped in the container, they are all downloaded at runtime.

## Requirements

* /data mounted to a persistent disk
* Port 25565/tcp mapped
* environment variable EULA set to "true"

As the end user, you are responsible for accepting the EULA from Mojang to run their server, by default in the container it is set to false.

## Docker Compose

This repository includes a full Compose setup in `docker-compose.yml` with:

* `atm10`: builds and runs the current image from this repo
* `backups`: scheduled backups via `itzg/mc-backup`
* `restarter`: scheduled restart announcements and graceful `stop` via RCON

### Quick start

1. Copy env template:

   `cp .env.example .env`

2. Update at minimum:

   * `EULA=true`
   * `RCON_PASSWORD=<strong-password>`
   * `CURSEFORGE_API_KEY=<api-key>`

3. Start stack:

   `docker compose up -d --build`

4. Verify services:

   `docker compose ps`

### Persistence and backups

* Server state persists on host with `${ATM10_DATA_DIR:-./data}:/data`
* Backups persist on host with `${ATM10_BACKUP_DIR:-./backups}:/backups`
* Default backup cadence is every 4 hours with 7-day + count-based pruning

Manual backup now:

`docker compose exec backups backup now`

### Automatic restart announcements

The `restarter` service uses `rcon-cli` to announce restart windows, run `save-all`, and send a graceful `stop`.
Because `atm10` uses `restart: unless-stopped`, the server starts automatically after stop.

Configure schedule in `.env`:

* `RESTART_INTERVAL_HOURS` (default `24`)
* `RESTART_WARNING_MINUTES` (default `10,5,1`)

The final countdown, grace period, and message prefix are intentionally fixed in the script for a simpler setup.

## Options

These environment variables can be set to override their defaults.

* JVM_OPTS "-Xms2048m -Xmx4096m"
* MOTD "ATM10"
* ALLOW_FLIGHT "true" or "false"
* MAX_PLAYERS "5"
* ONLINE_MODE "true" or "false"
* ENABLE_WHITELIST "true" or "false"
* WHITELIST_USERS "TestUserName1, TestUserName2"
* OP_USERS "TestUserName1, TestUserName2"
* REFRESH_REMOTE_UUIDS "true" or "false" (default: false)
* CURSEFORGE_API_KEY "<api key>" (required for automatic server file URL/hash resolution)
* ENABLE_RCON "true" or "false" (default: true)
* RCON_PORT "25575" (default)
* RCON_PASSWORD "<required for backup + restart announcer services>"
* ATM10_DATA_DIR "./data"
* ATM10_BACKUP_DIR "./backups"
* ATM10_PORT "25565"
* BACKUP_INITIAL_DELAY "2m"
* BACKUP_INTERVAL "4h"
* PRUNE_BACKUPS_DAYS "7"
* PRUNE_BACKUPS_COUNT "42"
* PAUSE_IF_NO_PLAYERS "true"
* RESTART_INTERVAL_HOURS "24"
* RESTART_WARNING_MINUTES "10,5,1"

### Adding Minecraft Operators

Set `OP_USERS` as a comma-separated list of usernames:

`OP_USERS=PlayerName1,PlayerName2`

The startup script keeps `ops.json` in sync. If you also set `REFRESH_REMOTE_UUIDS=true`, UUIDs are refreshed from the remote API.

### Integrity requirements

The startup script now enforces artifact integrity checks during initial install:

* `CURSEFORGE_API_KEY` is required; the script queries CurseForge API for official download URL and validates against the official file hash (`hashes` from API metadata).
* The server file is resolved from CurseForge by matching `SERVER_VERSION` (for example `ServerFiles-6.0.1.zip`).
* NeoForge installer SHA256 is fetched from the official NeoForge Maven `.sha256` and validated before execution.

When updating `SERVER_VERSION`, keep `CURSEFORGE_API_KEY` set so URL and hash checks stay fully automated.

### UUID lookup behavior

UUID lookups are no longer fetched remotely on every startup.

* Default (`REFRESH_REMOTE_UUIDS=false`): existing UUIDs in `whitelist.json` and `ops.json` are reused.
* Set `REFRESH_REMOTE_UUIDS=true` when you explicitly want to refresh UUIDs from the remote API.

## Troubleshooting

### Accept the EULA
Did you pass in the environment variable EULA set to `true`?

### Permissions of Files
This container is designed for [Unraid](https://unraid.net) so the user in the container runs on uid 99 and gid 100.  This may cause permission errors on the /data mount on other systems.

### Resetting
If the installation is incomplete for some reason.  Deleting the downloaded server file in /data will restart the install/upgrade process.

## Source (Original ATM9 repo)
Github: https://github.com/Goobaroo/docker-allthemods9

Docker: https://hub.docker.com/repository/docker/goobaroo/allthemods9

## Source (W3LFARe repo)
Github: https://github.com/W3LFARe/docker-allthemods10

Docker: https://registry.hub.docker.com/r/w3lfare/allthemods10 
