#!/bin/bash
set -euo pipefail

# Explicitly receive required parameters
PGBACKREST_CONFIG_FILE_PATH="$1"
PGBACKREST_STANZA="$2"
CRON_SCHEDULE=${ENV_PGBACKREST_CRON_SCHEDULE:-"0 0 * * *"}
BACKUP_ON_STARTUP=${ENV_PGBACKREST_FULLBACKUP_ON_STARTUP:-true}

# pgBackRestフルバックアップ日時記録ファイル
FULL_TIMESTAMP_FILE="$PGDATA/full_backup_timestamp.txt"

# ログのプレフィックスを設定
LOG_PREFIX="setup.sh"

# どうにかしてコンテナ終了を試みる関数
terminate_container() {
  local reason="$1"
  echo "[$LOG_PREFIX] ERROR: $reason"
  echo "[$LOG_PREFIX] Forcefully terminating container..."
  
  # 方法1: PostgreSQLプロセスを直接終了
  echo "[$LOG_PREFIX] Killing PostgreSQL processes..."
  pkill -TERM postgres 2>/dev/null || true
  pkill -TERM postmaster 2>/dev/null || true

  # 方法2: PID 1にシグナル送信（複数試す）
  echo "[$LOG_PREFIX] Sending signals to PID 1..."
  kill -TERM 1 2>/dev/null || true
  sleep 1
  kill -HUP 1 2>/dev/null || true
  sleep 1
  kill -INT 1 2>/dev/null || true
  sleep 2
  kill -KILL 1 2>/dev/null || true
  
  # 方法3: 強制終了（最後の手段）
  echo "[$LOG_PREFIX] Forcing exit..."
  exit 1
}

# PostgreSQL起動完了を待機
echo "[$LOG_PREFIX] Waiting for PostgreSQL to start..."
until pg_isready -h /var/run/postgresql -p 5432 -U postgres; do
  sleep 2
done
echo "[$LOG_PREFIX] PostgreSQL is ready"

# lock-path/spool-pathを強制的に設定
LOCK_PATH="/var/lib/pgbackrest/lock"
SPOOL_PATH="/var/lib/pgbackrest/spool"

# ディレクトリ準備
echo "[$LOG_PREFIX] Creating directories: $LOCK_PATH, $SPOOL_PATH"
mkdir -p "$LOCK_PATH" "$SPOOL_PATH"
chown -R postgres:postgres "$LOCK_PATH" "$SPOOL_PATH"
chmod 700 "$LOCK_PATH" "$SPOOL_PATH"

# stanza作成 → 失敗したらコンテナ終了
echo "[$LOG_PREFIX] Creating pgBackRest stanza: $PGBACKREST_STANZA"
if ! pgbackrest --config="$ENV_PGBACKREST_CONFIG_FILE_PATH" --stanza="$ENV_PGBACKREST_STANZA" stanza-create; then
  echo "[$LOG_PREFIX] ERROR: pgBackRest stanza creation failed"
  #kill -TERM 1   # PID 1（PostgreSQL）にSIGTERM → graceful shutdown → コンテナ終了
  terminate_container "Invalid stanza: Creation failed"
fi

# 構成チェック → 失敗したらコンテナ終了
echo "[$LOG_PREFIX] Verifying configuration for stanza: $PGBACKREST_STANZA"
if ! pgbackrest --config="$ENV_PGBACKREST_CONFIG_FILE_PATH" --stanza="$ENV_PGBACKREST_STANZA" check; then
  echo "[$LOG_PREFIX] ERROR: pgBackRest configuration check failed"
  terminate_container "Invalid configuration: Check failed"
fi

# フルバックアップ実行日時記録用ファイルを用意
touch "$FULL_TIMESTAMP_FILE"
chown postgres:postgres "$FULL_TIMESTAMP_FILE"
chmod 640 "$FULL_TIMESTAMP_FILE"

# 初回フルバックアップ
SETUP_FLAG="$PGDATA/pgbackrest-setup-done"
if [ "${BACKUP_ON_STARTUP}" = "true" ] && [ ! -f "$SETUP_FLAG" ]; then
  echo "[$LOG_PREFIX] Starting initial full backup"
  
  if pgbackrest --config="$ENV_PGBACKREST_CONFIG_FILE_PATH" --stanza="$ENV_PGBACKREST_STANZA" backup --type=full; then
    # 成功したらタイムスタンプを更新
    date +%s > "$FULL_TIMESTAMP_FILE"
    echo "[$LOG_PREFIX] Initial full backup succeeded → Timestamp recorded in $FULL_TIMESTAMP_FILE"
    
    # フラグ作成（重複実行防止）
    touch "$SETUP_FLAG"
  else
    echo "[$LOG_PREFIX] ERROR: Initial full backup failed"
    terminate_container "Initial full backup failed"
  fi
else
  echo "[$LOG_PREFIX] Skipping initial full backup"
fi

# cronジョブ生成
echo "[$LOG_PREFIX] Generating backup cron job with schedule: $CRON_SCHEDULE"

# 専用の一時ディレクトリ
CRON_TMP_DIR="/tmp/cronjobs"
mkdir -p "$CRON_TMP_DIR"
chown postgres:postgres "$CRON_TMP_DIR"
chmod 700 "$CRON_TMP_DIR"

# 古いファイルを削除（再起動時の残骸をクリア）
rm -f "$CRON_TMP_DIR"/pgbackrest-crontab*

# 新しいcronジョブファイル（固定名でOK）
TMP_CRON="$CRON_TMP_DIR/pgbackrest-crontab"
cat > "$TMP_CRON" << EOF
$CRON_SCHEDULE /etc/cronjobs/pgbackrest-cronjob.sh
EOF

# cron構文検証 → 失敗したらコンテナ終了
echo "[$LOG_PREFIX] Validating cron syntax..."
if ! supercronic -test "$TMP_CRON"; then
  echo "[$LOG_PREFIX] ERROR: Invalid cron syntax"
  rm -f "$TMP_CRON"
  terminate_container "Cron job registration failed"
fi

# Start supercronic with formatted output
cat <<EOF
[$LOG_PREFIX] Starting supercronic...
[$LOG_PREFIX] Backup schedule: $CRON_SCHEDULE
----------------------------------------
EOF

# supercronicを起動し、ログフォーマットをjqで整える
exec supercronic -json "$TMP_CRON" 2>&1 | jq -r '"[supercronic] \(.level): \(.msg)"'