#!/bin/bash
set -e

# Configuration script for TeamSpeak 3 Server
# Handles database configuration via Environment Variables

INI_FILE="/etc/teamspeak/ts3server.ini"
DB_INI_FILE="/var/lib/teamspeak/ts3db_mariadb.ini"

# Load environment variables if provided in a file
if [ -f /etc/default/teamspeak ]; then
    source /etc/default/teamspeak
fi

# Function to update INI value (only writes if value actually changed)
update_ini() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    if grep -q "^${key}=${value}$" "$file" 2>/dev/null; then
        # Value already matches, skip write
        return 0
    fi
    
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

echo "Configuring TeamSpeak Server..."

# Database Configuration
if [[ "${TS3_DB_TYPE}" == "mariadb" ]]; then
    echo "Configuring MariaDB/MySQL..."
    
    # Create MariaDB config file
    cat > "$DB_INI_FILE" << EOF
[config]
host=${TS3_DB_HOST:-localhost}
port=${TS3_DB_PORT:-3306}
username=${TS3_DB_USER:-teamspeak}
password=${TS3_DB_PASSWORD:-password}
database=${TS3_DB_NAME:-teamspeak}
socket=
EOF
    
    chown teamspeak:teamspeak "$DB_INI_FILE"
    chmod 600 "$DB_INI_FILE"
    
    # Update ts3server.ini to use MariaDB plugin
    update_ini "dbplugin" "ts3db_mariadb" "$INI_FILE"
    update_ini "dbpluginparameter" "$DB_INI_FILE" "$INI_FILE"
    update_ini "dbsqlpath" "/opt/teamspeak3-server/sql/" "$INI_FILE"
    
else
    echo "Using default SQLite database..."
    # Path must match dbpluginparameter in ts3server.ini
    SQLITE_DB="/var/lib/teamspeak/database/ts3server.sqlitedb"
    update_ini "dbplugin" "ts3db_sqlite3" "$INI_FILE"
    update_ini "dbpluginparameter" "$SQLITE_DB" "$INI_FILE"
    update_ini "dbsqlpath" "/opt/teamspeak3-server/sql/" "$INI_FILE"
    # NOTE: dbsqlcreatepath is intentionally NOT set. TS3's bundled libts3db_sqlite3.so
    # cannot execute setSQLfromFile on Fedora 43+ kernels. The schema is pre-seeded below.
    if ! sqlite3 "$SQLITE_DB" "SELECT count(*) FROM instance_properties;" > /dev/null 2>&1; then
        echo "Pre-initializing SQLite database with system sqlite3..."
        sqlite3 "$SQLITE_DB" < /opt/teamspeak3-server/sql/create_sqlite/create_tables.sql
        sqlite3 "$SQLITE_DB" < /opt/teamspeak3-server/sql/defaults.sql

        # The following settings are only applied on first boot.
        # After that, use a TS3 client or ServerQuery to change them at runtime.

        # TS3_SERVER_NAME — display name of the virtual server
        if [ -n "${TS3_SERVER_NAME:-}" ]; then
            sqlite3 "$SQLITE_DB" \
                "UPDATE server_properties SET value='${TS3_SERVER_NAME}' WHERE ident='virtualserver_name';"
            echo "Set server name to '${TS3_SERVER_NAME}'."
        fi

        # TS3_MAX_CLIENTS — maximum simultaneous clients (default: 32, max without license: 32)
        if [ -n "${TS3_MAX_CLIENTS:-}" ]; then
            sqlite3 "$SQLITE_DB" \
                "UPDATE server_properties SET value='${TS3_MAX_CLIENTS}' WHERE ident='virtualserver_maxclients';"
            echo "Set max clients to '${TS3_MAX_CLIENTS}'."
        fi

        # TS3_WELCOME_MESSAGE — message shown to clients on connect (supports [URL] BBCode)
        if [ -n "${TS3_WELCOME_MESSAGE:-}" ]; then
            sqlite3 "$SQLITE_DB" \
                "UPDATE server_properties SET value='${TS3_WELCOME_MESSAGE}' WHERE ident='virtualserver_welcomemessage';"
            echo "Set welcome message."
        fi

        # Derive the latest DB version from the highest available update_N.sql script
        # so ts3server skips all migration scripts on first start.
        LATEST_VERSION=$(ls /opt/teamspeak3-server/sql/update_[0-9]*.sql 2>/dev/null \
            | grep -oP 'update_\K[0-9]+(?=\.sql)' | sort -n | tail -1)
        if [ -n "$LATEST_VERSION" ]; then
            sqlite3 "$SQLITE_DB" \
                "INSERT INTO instance_properties (server_id, string_id, id, ident, value) \
                 VALUES (0, '', 0, 'serverinstance_database_version', '$LATEST_VERSION');"
            echo "Set database version to $LATEST_VERSION."
        fi
        chown teamspeak:teamspeak "$SQLITE_DB"
        echo "SQLite database initialized."
    fi
fi

echo "Configuration complete."
