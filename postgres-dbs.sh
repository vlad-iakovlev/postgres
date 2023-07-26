#!/bin/bash
set -e

function handle_container {
  local container_id=$1
  {
    local envs=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container_id")
    local db_url=$(echo "$envs" | grep DATABASE_URL | cut -d'=' -f2)

    local protocol=$(echo $db_url | awk -F:// '{print $1}')

    if [ "$protocol" != "postgresql" ]; then
      return
    fi

    local creds=$(echo $db_url | awk -F[/:@] '{print $4, $5}')
    local username=$(echo $creds | cut -d' ' -f1)
    local password=$(echo $creds | cut -d' ' -f2)
    local dbname=$(echo $db_url | awk -F[/] '{print $4}' | cut -d'?' -f1)

    psql -c "CREATE ROLE $username WITH LOGIN PASSWORD '$password';"
    psql -c "CREATE DATABASE $dbname WITH OWNER $PGUSER;"
    psql -c "GRANT ALL PRIVILEGES ON DATABASE $dbname TO $username;"
  } || {
    echo "An error occurred while handling container $container_id"
  }
}

# Wait for PostgreSQL to start
while ! pg_isready -h $PGHOST -U $PGUSER >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL to start..."
  sleep 1
done

# Handle all currently running containers
for container_id in $(docker ps -q); do
  handle_container $container_id
done

# Handle containers started in the future
docker events --filter 'type=container' --filter 'event=start' | while read -r timestamp type action container_id rest; do
  handle_container $container_id
done
