#!/bin/bash
set -x

NEOFORGE_VERSION=21.1.219
SERVER_VERSION=6.0.1
SERVER_ZIP="Server-Files-$SERVER_VERSION.zip"
SERVER_ZIP_URL="https://mediafilez.forgecdn.net/files/7679/065/ServerFiles-$SERVER_VERSION.zip"
NEOFORGE_INSTALLER="neoforge-${NEOFORGE_VERSION}-installer.jar"
NEOFORGE_SHA256_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/$NEOFORGE_VERSION/neoforge-$NEOFORGE_VERSION-installer.jar.sha256"
REFRESH_REMOTE_UUIDS=${REFRESH_REMOTE_UUIDS:-false}
CURSEFORGE_API_URL="https://api.curseforge.com/v1"
CURSEFORGE_MOD_ID=925200
ENABLE_RCON=${ENABLE_RCON:-true}
RCON_PORT=${RCON_PORT:-25575}
RCON_PASSWORD=${RCON_PASSWORD:-}

extract_file_id_from_url() {
    local url="$1"
    if [[ "$url" =~ /files/([0-9]+)/([0-9]+)/ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

download_server_zip_with_curseforge_api() {
    local file_id
    local files_index
    local metadata
    local download_url
    local expected_sha1
    local actual_sha1
    local actual_sha256

    files_index=$(curl -fsS --retry 2 --max-time 20 \
        -H "x-api-key: $CURSEFORGE_API_KEY" \
        "$CURSEFORGE_API_URL/mods/$CURSEFORGE_MOD_ID/files?pageSize=50") || return 1

    local escaped_v
    escaped_v=$(printf '%s' "$SERVER_VERSION" | sed 's/\./\\\\./g')

    file_id=$(jq -r --arg v "$escaped_v" \
        '.data[] | select(.displayName | test("(Server[-_ ]?Files[-_]|[-_])" + $v + "(\\.zip)?$"; "i")) | .id' <<<"$files_index" | head -n 1)

    if [[ -z "$file_id" ]] || [[ "$file_id" == "null" ]]; then
        if file_id=$(extract_file_id_from_url "$SERVER_ZIP_URL"); then
            echo "CurseForge API version match not found; trying fallback file ID $file_id from SERVER_ZIP_URL"
        else
            echo "Could not resolve CurseForge file ID for SERVER_VERSION=$SERVER_VERSION."
            return 1
        fi
    fi

    metadata=$(curl -fsS --retry 2 --max-time 20 \
        -H "x-api-key: $CURSEFORGE_API_KEY" \
        "$CURSEFORGE_API_URL/mods/$CURSEFORGE_MOD_ID/files/$file_id") || return 1

    download_url=$(jq -r '.data.downloadUrl // empty' <<<"$metadata")
    if [[ -z "$download_url" ]]; then
        download_url=$(curl -fsS --retry 2 --max-time 20 \
            -H "x-api-key: $CURSEFORGE_API_KEY" \
            "$CURSEFORGE_API_URL/mods/$CURSEFORGE_MOD_ID/files/$file_id/download-url" |
            jq -r '.data // empty') || return 1
    fi

    if [[ -z "$download_url" ]]; then
        echo "CurseForge returned no download URL for mod=$CURSEFORGE_MOD_ID file=$file_id."
        return 1
    fi

    expected_sha1=$(jq -r '.data.hashes[]? | select(.algo==1) | .value' <<<"$metadata" | head -n 1)

    curl -fL --retry 2 --max-time 300 -o "$SERVER_ZIP" "$download_url" || return 1

    if [[ -n "$expected_sha1" ]] && [[ "$expected_sha1" != "null" ]]; then
        actual_sha1=$(sha1sum "$SERVER_ZIP" | awk '{print $1}')
        if [[ "${actual_sha1,,}" != "${expected_sha1,,}" ]]; then
            echo "CurseForge SHA1 validation failed for $SERVER_ZIP."
            return 1
        fi
    fi

    actual_sha256=$(sha256sum "$SERVER_ZIP" | awk '{print $1}')
    echo "Downloaded and validated $SERVER_ZIP via CurseForge API."
    echo "Computed SHA256: $actual_sha256"
    return 0
}

normalize_bool() {
    case "${1,,}" in
    true | 1 | yes | on) echo "true" ;;
    *) echo "false" ;;
    esac
}

strip_wrapping_quotes() {
    local value="$1"
    if [[ ${#value} -ge 2 ]]; then
        if [[ "$value" == "\""*"\"" ]] || [[ "$value" == "'"*"'" ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi
    printf '%s' "$value"
}

set_server_property() {
    local key="$1"
    local value="$2"
    local file="${3:-/data/server.properties}"
    local tmp_file

    if [[ ! -f "$file" ]]; then
        printf '%s=%s\n' "$key" "$value" >"$file"
        return 0
    fi

    tmp_file=$(mktemp)
    awk -F= -v key="$key" -v value="$value" '
        BEGIN { found = 0 }
        $1 == key {
            print key "=" value
            found = 1
            next
        }
        { print }
        END {
            if (!found) {
                print key "=" value
            }
        }
    ' "$file" >"$tmp_file"
    mv "$tmp_file" "$file"
}

fetch_remote_uuid() {
    local username="$1"
    curl -fsS --max-time 10 --retry 2 "https://playerdb.co/api/player/minecraft/$username" | jq -r '.data.player.id'
}

cd /data

EULA="$(strip_wrapping_quotes "${EULA:-false}")"
JVM_OPTS="$(strip_wrapping_quotes "${JVM_OPTS:-}")"
MOTD="$(strip_wrapping_quotes "${MOTD:-}")"
ALLOW_FLIGHT="$(strip_wrapping_quotes "${ALLOW_FLIGHT:-}")"
MAX_PLAYERS="$(strip_wrapping_quotes "${MAX_PLAYERS:-}")"
ONLINE_MODE="$(strip_wrapping_quotes "${ONLINE_MODE:-}")"
ENABLE_WHITELIST="$(strip_wrapping_quotes "${ENABLE_WHITELIST:-}")"
WHITELIST_USERS="$(strip_wrapping_quotes "${WHITELIST_USERS:-}")"
OP_USERS="$(strip_wrapping_quotes "${OP_USERS:-}")"
REFRESH_REMOTE_UUIDS="$(strip_wrapping_quotes "${REFRESH_REMOTE_UUIDS:-false}")"
CURSEFORGE_API_KEY="$(strip_wrapping_quotes "${CURSEFORGE_API_KEY:-}")"
ENABLE_RCON="$(strip_wrapping_quotes "${ENABLE_RCON:-true}")"
RCON_PORT="$(strip_wrapping_quotes "${RCON_PORT:-25575}")"
RCON_PASSWORD="$(strip_wrapping_quotes "${RCON_PASSWORD:-}")"

if ! [[ "$RCON_PORT" =~ ^[0-9]+$ ]] || ((RCON_PORT < 1 || RCON_PORT > 65535)); then
    echo "RCON_PORT must be a number between 1 and 65535."
    exit 13
fi

if ! [[ "$EULA" = "false" ]]; then
    echo "eula=true" >eula.txt
else
    echo "You must accept the EULA to install."
    exit 99
fi

if ! [[ -f "$SERVER_ZIP" ]]; then
    rm -fr config defaultconfigs kubejs mods packmenu Server-Files-* neoforge*

    if [[ -z "${CURSEFORGE_API_KEY:-}" ]]; then
        echo "CURSEFORGE_API_KEY is required for artifact resolution and validation."
        exit 10
    fi

    download_server_zip_with_curseforge_api || exit 9

    unzip -u -o "$SERVER_ZIP" -d /data
    DIR_TEST="ServerFiles-$SERVER_VERSION"
    if [[ $(find . -type d -maxdepth 1 | wc -l) -gt 1 ]]; then
        cd "${DIR_TEST}"
        find . -type d -exec chmod 755 {} +
        find . -type f -exec chmod 644 {} +
        mv -f * /data
        cd /data
        rm -fr "$DIR_TEST"
    fi

    curl -fLo "$NEOFORGE_INSTALLER" "https://maven.neoforged.net/releases/net/neoforged/neoforge/$NEOFORGE_VERSION/neoforge-$NEOFORGE_VERSION-installer.jar" || exit 11
    curl -fsSL "$NEOFORGE_SHA256_URL" -o "$NEOFORGE_INSTALLER.sha256" || exit 11
    echo "$(cat "$NEOFORGE_INSTALLER.sha256")  $NEOFORGE_INSTALLER" | sha256sum -c - || exit 11
    java -jar "$NEOFORGE_INSTALLER" --installServer
fi

if [[ -n "$JVM_OPTS" ]]; then
    sed -i '/-Xm[s,x]/d' user_jvm_args.txt
    for j in ${JVM_OPTS}; do sed -i '$a\'$j'' user_jvm_args.txt; done
fi
if [[ -n "$MOTD" ]]; then
    set_server_property "motd" "$MOTD"
fi
if [[ -n "$ENABLE_WHITELIST" ]]; then
    set_server_property "white-list" "$ENABLE_WHITELIST"
fi
if [[ -n "$ALLOW_FLIGHT" ]]; then
    set_server_property "allow-flight" "$ALLOW_FLIGHT"
fi
if [[ -n "$MAX_PLAYERS" ]]; then
    set_server_property "max-players" "$MAX_PLAYERS"
fi
if [[ -n "$ONLINE_MODE" ]]; then
    set_server_property "online-mode" "$ONLINE_MODE"
fi
if [[ "$(normalize_bool "$ENABLE_RCON")" == "true" ]]; then
    if [[ -z "$RCON_PASSWORD" ]]; then
        echo "RCON_PASSWORD is required when ENABLE_RCON=true."
        exit 12
    fi

    set_server_property "enable-rcon" "true"
    set_server_property "rcon.port" "$RCON_PORT"
    set_server_property "rcon.password" "$RCON_PASSWORD"
else
    set_server_property "enable-rcon" "false"
fi

# Initialize whitelist.json if not present
if [[ ! -f whitelist.json ]]; then
    echo "[]" >whitelist.json
fi

IFS=',' read -ra USERS <<<"$WHITELIST_USERS"
for raw_username in "${USERS[@]}"; do
    username=$(echo "$raw_username" | xargs)
    refresh_enabled=$(normalize_bool "$REFRESH_REMOTE_UUIDS")

    if [[ -z "$username" ]] || ! [[ "$username" =~ ^[a-zA-Z0-9_]{3,16}$ ]]; then
        echo "Whitelist: Invalid or empty username: '$username'. Skipping..."
        continue
    fi

    UUID=$(jq -r --arg username "$username" 'first(.[] | select(.name == $username) | .uuid) // empty' whitelist.json)
    if [[ "$refresh_enabled" == "true" ]]; then
        remote_uuid=$(fetch_remote_uuid "$username")
        if [[ -n "$remote_uuid" ]] && [[ "$remote_uuid" != "null" ]]; then
            UUID="$remote_uuid"
        fi
    fi

    if [[ -n "$UUID" ]] && [[ "$UUID" != "null" ]]; then
        if jq -e --arg username "$username" '.[] | select(.name == $username)' whitelist.json >/dev/null; then
            if jq -e --arg username "$username" --arg uuid "$UUID" '.[] | select(.name == $username and .uuid == $uuid)' whitelist.json >/dev/null; then
                echo "Whitelist: $username ($UUID) is already whitelisted. Skipping..."
            else
                echo "Whitelist: Updating UUID for $username to $UUID."
                jq --arg username "$username" --arg uuid "$UUID" 'map(if .name == $username then .uuid = $uuid else . end)' whitelist.json >tmp.json && mv tmp.json whitelist.json
            fi
        else
            echo "Whitelist: Adding $username ($UUID) to whitelist."
            jq ". += [{\"uuid\": \"$UUID\", \"name\": \"$username\"}]" whitelist.json >tmp.json && mv tmp.json whitelist.json
        fi
    else
        echo "Whitelist: No UUID available for $username. Set REFRESH_REMOTE_UUIDS=true to fetch from remote API."
    fi
done

# Initialize ops.json if not present
if [[ ! -f ops.json ]]; then
    echo "[]" >ops.json
fi

IFS=',' read -ra OPS <<<"$OP_USERS"
for raw_username in "${OPS[@]}"; do
    username=$(echo "$raw_username" | xargs)
    refresh_enabled=$(normalize_bool "$REFRESH_REMOTE_UUIDS")

    if [[ -z "$username" ]] || ! [[ "$username" =~ ^[a-zA-Z0-9_]{3,16}$ ]]; then
        echo "Ops: Invalid or empty username: '$username'. Skipping..."
        continue
    fi

    UUID=$(jq -r --arg username "$username" 'first(.[] | select(.name == $username) | .uuid) // empty' ops.json)
    if [[ "$refresh_enabled" == "true" ]]; then
        remote_uuid=$(fetch_remote_uuid "$username")
        if [[ -n "$remote_uuid" ]] && [[ "$remote_uuid" != "null" ]]; then
            UUID="$remote_uuid"
        fi
    fi

    if [[ -n "$UUID" ]] && [[ "$UUID" != "null" ]]; then
        if jq -e --arg username "$username" '.[] | select(.name == $username)' ops.json >/dev/null; then
            if jq -e --arg username "$username" --arg uuid "$UUID" '.[] | select(.name == $username and .uuid == $uuid)' ops.json >/dev/null; then
                echo "Ops: $username ($UUID) is already an operator. Skipping..."
            else
                echo "Ops: Updating UUID for operator $username to $UUID."
                jq --arg username "$username" --arg uuid "$UUID" 'map(if .name == $username then .uuid = $uuid else . end)' ops.json >tmp.json && mv tmp.json ops.json
            fi
        else
            echo "Ops: Adding $username ($UUID) as operator."
            jq ". += [{\"uuid\": \"$UUID\", \"name\": \"$username\", \"level\": 4, \"bypassesPlayerLimit\": false}]" ops.json >tmp.json && mv tmp.json ops.json
        fi
    else
        echo "Ops: No UUID available for $username. Set REFRESH_REMOTE_UUIDS=true to fetch from remote API."
    fi
done

sed -i 's/server-port.*/server-port=25565/g' server.properties
chmod 755 run.sh

./run.sh
