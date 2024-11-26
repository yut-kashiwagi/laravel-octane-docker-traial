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
  git add config/octane.php .env.example public/frankenphp-worker.php
  git add package.json package-lock.json
  git commit -m "Install Octane"

  install_larastan
  git add composer.json composer.lock phpstan.neon phpstan-baseline.neon
  git commit -m "Install Larastan"

  install_php_codesniffer
  git add composer.json composer.lock phpcs.xml
  git commit -m "Install PHP_CodeSniffer"
  vendor/bin/phpcbf --standard=phpcs.xml || true
  git add -u
  git commit -m "Format code with PHP_CodeSniffer"

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
  cp vendor/laravel/octane/src/Commands/stubs/frankenphp-worker.php public/frankenphp-worker.php

  cat <<'EOS' >> .env.example

OCTANE_SERVER=frankenphp
EOS
}

install_larastan() {
  composer require --dev "larastan/larastan:^3.0"
  touch phpstan-baseline.neon
  cat <<'EOS' > phpstan.neon
includes:
  - vendor/larastan/larastan/extension.neon
  - vendor/nesbot/carbon/extension.neon
  - phpstan-baseline.neon
parameters:
  level: max
  paths:
    - .
  excludePaths:
    - bootstrap/cache
    - node_modules
    - public
    - storage
    - vendor
EOS
  ./vendor/bin/phpstan analyse --generate-baseline --allow-empty-baseline
}

install_php_codesniffer() {
  composer require --dev "squizlabs/php_codesniffer:^3.7.2"
  cat <<'EOS' > phpcs.xml
<?xml version="1.0"?>
<ruleset xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="PHP_CodeSniffer" xsi:noNamespaceSchemaLocation="phpcs.xsd">
    <file>.</file>

    <exclude-pattern>/bootstrap/cache/</exclude-pattern>
    <exclude-pattern>/node_modules/</exclude-pattern>
    <exclude-pattern>/public/</exclude-pattern>
    <exclude-pattern>/storage/</exclude-pattern>
    <exclude-pattern>/vendor/</exclude-pattern>

    <arg name="extensions" value="php"/>
    <arg name="basepath" value="."/>
    <arg value="n"/>
    <arg name="colors"/>
    <arg value="p"/>

    <rule ref="PSR12" />

    <rule ref="PSR1.Methods.CamelCapsMethodName">
        <exclude-pattern>/tests/*</exclude-pattern>
    </rule>
</ruleset>
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
