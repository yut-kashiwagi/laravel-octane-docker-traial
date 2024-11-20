#!/bin/bash
set -eu

: "${LARAVEL_VERSION:=11.*}"

main() {
  if [ "$#" -lt 1 ]; then
    show_usage
    exit 1
  fi

  local target_path=$1

  mkdir "$target_path"
  cd "$target_path"

  create_laravel_project
  git init
  git add .
  git commit -m "Initial commit from Laravel"

  install_octane
  git add composer.json composer.lock
  git add config/octane.php .env.example
  git add package.json package-lock.json
  git commit -m "Install Octane"

  generate_dockerfile
  generate_dockerignore
  git add Dockerfile .dockerignore
  git commit -m "Add Dockerfile"
}

show_usage() {
  echo "Usage: $0 <target-path>"
}

create_laravel_project() {
  composer create-project laravel/laravel --no-scripts "." "$LARAVEL_VERSION"
}

install_octane() {
  composer require -W laravel/octane
  php artisan vendor:publish --tag octane-config
  npm install --save-dev chokidar

  cat <<'EOS' >> .env.example

OCTANE_SERVER=frankenphp
EOS
}

generate_dockerfile() {
  cat <<'EOS' > Dockerfile
FROM dunglas/frankenphp:1.3-php8.3 AS base

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN install-php-extensions \
    pcntl \
    pdo_mysql \
    zip

FROM base AS deps

WORKDIR /app

COPY composer.json composer.lock .

RUN set -eux; \
    composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

FROM base AS dev

WORKDIR /app

VOLUME /app/storage

ARG USER=laravel

RUN set -eux; \
    groupadd --gid 1001 laravel; \
    useradd --gid laravel --uid 1001 --create-home laravel; \
    setcap -r /usr/local/bin/frankenphp; \
    chown -R ${USER}:${USER} /data/caddy; \
    chown -R ${USER}:${USER} /config/caddy; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        nodejs \
        npm \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY --from=deps /app/vendor ./vendor

COPY --chown=laravel:laravel . .

RUN set -eux; \
    composer install; \
    php artisan storage:link; \
    php artisan octane:install -n --server=frankenphp; \
    npm install

USER ${USER}

CMD ["php", "artisan", "--watch", "octane:frankenphp"]
EOS
}

generate_dockerignore() {
  cat <<'EOS' > .dockerignore
Dockerfile
.dockerignore
.git
README.md
vendor
node_modules
EOS
}

main "$@"
