#!/bin/bash
set -eu

main() {
  local env_file=".env"

  local app_key="base64:$(openssl rand -base64 32)"
  local mariadb_root_password="$(openssl rand -base64 16  | head -c 16)"
  local mariadb_password="$(openssl rand -base64 16  | head -c 16)"

  update_env_var "$env_file" APP_KEY "$app_key"
  update_env_var "$env_file" MARIADB_ROOT_PASSWORD "$mariadb_root_password"
  update_env_var "$env_file" MARIADB_PASSWORD "$mariadb_password"
}

update_env_var() {
  local env_file="$1"
  local name="$2"
  local value=$(echo "$3" | escape_special_chars)

  if grep -q "^$name=" "$env_file"; then
    sed -i "s/^$name=.*/$name=$value/" "$env_file"
  else
    echo "$name=$value" >> "$env_file"
  fi
}

escape_special_chars() {
    sed 's/[&/\]/\\&/g'
}

main "$@"
