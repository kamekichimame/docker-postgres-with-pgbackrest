#!/bin/bash
set -euo pipefail

# Explicitly receive required parameters
PGBACKREST_CONFIG_FILE_PATH="$1"
PGBACKREST_STANZA="$2"
CRON_SCHEDULE=${ENV_PGBACKREST_CRON_SCHEDULE:-"0 0 * * *"}

# 自分のファイル名(setup.sh)を取得
self_filename=$(basename "${BASH_SOURCE[0]}");

terminate_container() {
  local reason="$1"
  echo "[$self_filename] ERROR: $reason"
  echo "[$self_filename] Forcefully terminating container..."
  
  # 方法1: PostgreSQLプロセスを直接終了
  echo "[$self_filename] Killing PostgreSQL processes..."
  pkill -TERM postgres 2>/dev/null || true
  pkill -TERM postmaster 2>/dev/null || true
  
  # 方法2: PID 1にシグナル送信（複数試す）
  echo "[$self_filename] Sending signals to PID 1..."
  kill -TERM 1 2>/dev/null || true
  sleep 1
  kill -HUP 1 2>/dev/null || true
  sleep 1
  kill -INT 1 2>/dev/null || true
  sleep 2
  kill -KILL 1 2>/dev/null || true
  
  # 方法3: 強制終了（最後の手段）
  echo "[$self_filename] Forcing exit..."
  exit 1
}

# PostgreSQL起動完了を待機
echo "[$self_filename] Waiting for PostgreSQL to start..."
until pg_isready -h /var/run/postgresql -p 5432 -U postgres; do
  sleep 2
done
echo "[$self_filename] PostgreSQL is ready"

# lock-path/spool-pathを強制的に設定
LOCK_PATH="/var/lib/pgbackrest/lock"
SPOOL_PATH="/var/lib/pgbackrest/spool"

# ディレクトリ準備
echo "[$self_filename] Creating directories: $LOCK_PATH, $SPOOL_PATH"
mkdir -p "$LOCK_PATH" "$SPOOL_PATH"
chown -R postgres:postgres "$LOCK_PATH" "$SPOOL_PATH"
chmod 700 "$LOCK_PATH" "$SPOOL_PATH"

# stanza作成 → 失敗したらコンテナ終了
echo "[$self_filename] Creating pgBackRest stanza: $PGBACKREST_STANZA"
if ! pgbackrest --config="$ENV_PGBACKREST_CONFIG_FILE_PATH" --stanza="$ENV_PGBACKREST_STANZA" stanza-create; then
  echo "[$self_filename] ERROR: pgBackRest stanza creation failed"
  #kill -TERM 1   # PID 1（PostgreSQL）にSIGTERM → graceful shutdown → コンテナ終了
  terminate_container "Invalid stanza creation failed"
  #exit 1
fi

# 構成チェック → 失敗したらコンテナ終了
echo "[$self_filename] Verifying configuration for stanza: $PGBACKREST_STANZA"
if ! pgbackrest --config="$ENV_PGBACKREST_CONFIG_FILE_PATH" --stanza="$ENV_PGBACKREST_STANZA" check; then
  echo "[$self_filename] ERROR: pgBackRest configuration check failed"
  kill -TERM 1
  exit 1
fi

# cronジョブ生成 → 失敗したらコンテナ終了
echo "[$self_filename] Generating backup cron job with schedule: $CRON_SCHEDULE"
# 一時ファイルにジョブを書く
# TMP_CRON=$(mktemp)
# CRON_FILE="/var/spool/cron/crontabs/postgres"
# cat > "$CRON_FILE" << EOF
# $CRON_SCHEDULE pgbackrest --config="$PGBACKREST_FINAL_CONFIG_FILE_PATH" --stanza="$PGBACKREST_STANZA" \
#   --lock-path="$LOCK_PATH" --spool-path="$SPOOL_PATH" backup 2>&1 | sed "s/^/[pgbackrest-cron] /"'
# EOF
# cat > /etc/crontabs/postgres << EOF
# $CRON_SCHEDULE pgbackrest --config="$PGBACKREST_FINAL_CONFIG_FILE_PATH" --stanza="$PGBACKREST_STANZA" \
#   --lock-path="$LOCK_PATH" --spool-path="$SPOOL_PATH" \
#   backup >> /var/log/pgbackrest/cron.log 2>&1
# EOF

# postgresユーザーとしてcrontabに登録
# if ! crontab -u postgres "$TMP_CRON"; then
#   echo "[cron] ERROR: crontab登録失敗"
#   kill -TERM 1
#   exit 1
# fi

# 一時ファイル削除
#rm -f "$TMP_CRON"

# chown postgres:postgres "$CRON_FILE"
# chmod 600 "$CRON_FILE"

# cronジョブ内容を直接変数に格納
CRON_JOB="$CRON_SCHEDULE pgbackrest --config=$ENV_PGBACKREST_CONFIG_FILE_PATH --stanza=$ENV_PGBACKREST_STANZA \
  --lock-path=$LOCK_PATH backup 2>&1 | sed \"s/^/[pgbackrest-cron] /\""

# cron構文検証 → 失敗したらコンテナ終了
# if ! crontab -u postgres "$CRON_FILE"; then
#   echo "[cron] ERROR: cron構文エラー"
#   kill -TERM 1
#   exit 1
# fi
# if ! echo "$CRON_JOB" | crontab -u postgres -; then
#   echo "[cron] ERROR: cron構文エラー - cronジョブの登録に失敗しました"
#   kill -TERM 1
#   exit 1
# fi
# crontabファイルを作成
CRONTAB_FILE="/tmp/pgbackrest-crontab"
echo "$CRON_JOB" > "$CRONTAB_FILE"

# cron構文検証
echo "[$self_filename] Validating cron syntax..."
if ! supercronic -test "$CRONTAB_FILE"; then
  echo "[$self_filename] ERROR: Invalid cron syntax"
  rm -f "$CRONTAB_FILE"
  kill -TERM 1
  exit 1
fi

# Start supercronic with formatted output
cat <<EOF
[$self_filename] Starting supercronic...
[$self_filename] Backup schedule: $CRON_SCHEDULE
[$self_filename] Configuration file: $PGBACKREST_CONFIG_FILE_PATH
[$self_filename] Cron job: $CRON_JOB
----------------------------------------
EOF

# supercronicを起動し、ログフォーマットをjqとsedで整える
exec supercronic -json "$CRONTAB_FILE" 2>&1 | jq 'del(.job.command)' | sed 's/^/[supercronic] /'