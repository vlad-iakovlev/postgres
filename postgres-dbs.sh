#!/bin/bash

function parse_db_url {
  local db_url=$1
  local creds
  protocol=$(echo "$db_url" | awk -F:// '{print $1}')
  creds=$(echo "$db_url" | awk -F[/:@] '{print $4, $5}')
  username=$(echo "$creds" | cut -d' ' -f1)
  password=$(echo "$creds" | cut -d' ' -f2)
  dbname=$(echo "$db_url" | awk -F[/] '{print $4}' | cut -d'?' -f1)
}

function handle_db_url {
  local db_url=$1
  local protocol
  local username
  local password
  local dbname

  parse_db_url "$db_url"

  if [ "$protocol" != "postgresql" ]; then
    return 0
  fi

  if ! psql -c "CREATE ROLE $username;"; then
    echo "Failed to create role \"$username\""
  fi

  if ! psql -c "ALTER ROLE $username WITH LOGIN PASSWORD '$password';"; then
    echo "Failed to set password for \"$username\""
  fi

  if ! psql -c "CREATE DATABASE $dbname WITH OWNER $PGUSER;"; then
    echo "Failed to create database \"$dbname\""
  fi

  if ! psql -c "GRANT ALL PRIVILEGES ON DATABASE $dbname TO $username;"; then
    echo "Failed to grant privileges for \"$username\" to access \"$dbname\""
  fi
}

function handle_container {
  local container_id=$1
  local envs
  local db_url

  if ! envs=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container_id"); then
    echo "Failed to inspect container $container_id"
    return 0
  fi

  handle_db_url "$(echo "$envs" | grep "^DATABASE_URL=" | cut -d'=' -f2)"
  handle_db_url "$(echo "$envs" | grep "^SHADOW_DATABASE_URL=" | cut -d'=' -f2)"
}

# Wait for PostgreSQL to start
while ! pg_isready -h "$PGHOST" -U "$PGUSER" >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL to start..."
  sleep 1
done

# Handle all currently running containers
for container_id in $(docker ps -q); do
  handle_container "$container_id"
done

# Handle containers started in the future
docker events --filter 'type=container' --filter 'event=start' |
  while read -r timestamp type action container_id rest; do
    handle_container "$container_id"
  done
