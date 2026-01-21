#!/bin/bash
set -euo pipefail

# Get script filename for logging
self_filename=$(basename "${BASH_SOURCE[0]}")

# pgBackRestディレクトリ準備
echo "[$self_filename] Initializing pgBackRest directories..."
mkdir -p /var/lib/pgbackrest/{lock,spool}
chown -R postgres:postgres /var/lib/pgbackrest
chmod 700 /var/lib/pgbackrest /var/lib/pgbackrest/*

# 必要な環境変数が設定されていない場合は上書き
echo "[$self_filename] Setting environment variables..."
export ENV_PGBACKREST_STANZA="${ENV_PGBACKREST_STANZA:-${POSTGRES_DB:-postgres}}"   # 優先順位：PGBACKREST_STANZA > POSTGRES_DB > "postgres"
export ENV_PGDATA="${PGDATA:-/var/lib/postgresql/data}"
export ENV_POSTGRES_USER="${POSTGRES_USER:-postgres}" 
export ENV_PGBACKREST_CONFIG_FILE_PATH=${ENV_PGBACKREST_CONFIG_FILE_PATH:-/etc/pgbackrest/conf/pgbackrest.conf}

# ユーザーのpgbackrest.confが存在しない場合、デフォルトテンプレートから生成
PGBACKREST_TEMPLATE_CONFIG="/etc/pgbackrest/conf/pgbackrest.conf.template"

if [ ! -f "$ENV_PGBACKREST_CONFIG_FILE_PATH" ]; then
  echo "[$self_filename] pgBackRest config file not found, generating from template..."
  mkdir -p "$(dirname "$ENV_PGBACKREST_CONFIG_FILE_PATH")"

  # envsubstで変数を置き換え
  envsubst '${ENV_PGBACKREST_STANZA} ${ENV_PGDATA} ${ENV_POSTGRES_USER}' \
    < "$PGBACKREST_TEMPLATE_CONFIG" \
    > "$ENV_PGBACKREST_CONFIG_FILE_PATH"
  
  echo "[$self_filename] pgBackRest config file created: $ENV_PGBACKREST_CONFIG_FILE_PATH"
fi

echo "[$self_filename] Setting permission to pgBackRest config file"
chown postgres:postgres "$ENV_PGBACKREST_CONFIG_FILE_PATH"
chmod 640 "$ENV_PGBACKREST_CONFIG_FILE_PATH"

# pgbackrestの初回セットアップをバックグラウンドで起動
echo "[$self_filename] Starting pgBackRest setup script..."
#/setup.sh "$ENV_PGBACKREST_CONFIG_FILE_PATH" "$ENV_PGBACKREST_STANZA" &
su -s /bin/bash postgres -c "/setup.sh '${ENV_PGBACKREST_CONFIG_FILE_PATH}' '${ENV_PGBACKREST_STANZA}'" &

# PostgreSQLをフォアグラウンドで起動（これがコンテナのメイン）
echo "[$self_filename] Starting PostgreSQL..."
ARCHIVE_COMMAND="pgbackrest --config=${ENV_PGBACKREST_CONFIG_FILE_PATH} --stanza=${ENV_PGBACKREST_STANZA} --pg1-path=${ENV_PGDATA} archive-push %p"
# ちなみに $@ にはDockerfileに書いているCMD(postgres)やユーザー指定のCMDが入るよ
exec /usr/local/bin/docker-entrypoint.sh "$@" \
  -c archive_mode=on \
  -c archive_command="${ARCHIVE_COMMAND}" \
  2>&1 | sed 's/^/[postgres] /'