.PHONY: all setup migrate watch

watch: setup
	@docker compose watch

setup: laravel-app .env migrate

laravel-app:
	@./create-laravel-app.sh laravel-app

.env: .env.example
	@cp .env.example .env
	@./generate-secret.sh

migrate: .migrated

.migrated:
	@docker compose run -T --rm --entrypoint /bin/bash app php artisan migrate --seed
	@touch .migrated
