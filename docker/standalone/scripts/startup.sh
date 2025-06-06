#!/bin/bash

# Log directory
LOG_DIR="/var/www/html/storage/logs"

echo "Starting script..."

echo "Clearing log file..."
if [ -n "$LOG_DIR" ]; then
    rm -f "$LOG_DIR/startup-script.log"
fi

if [ ! -d "$LOG_DIR" ]; then
    echo "Warning: Log directory does not exist (maybe first install ?). Logging disabled until restart."
    LOG_DIR=""
fi

log_message() {
    if [ -n "$LOG_DIR" ]; then
        echo "$1" >> "$LOG_DIR/startup-script.log"
    fi
    echo "$1"
}

# Copy project files if public folder is missing
if [ ! -d "/var/www/html/public" ]; then
    log_message "Warning: project folder is empty. Copying default files..."
    cp -nr /var/default/. /var/www/html
    chown -R laravel:laravel /var/www/html/
    chmod -R 755 /var/www/html/
fi

# Copy .env if not exists
cp -n /var/default/.env.example /var/www/html/.env

# Copy Nginx config if missing
if [ ! -f "/etc/nginx/conf.d/default.conf" ]; then
    log_message "Warning: Nginx configuration not found. Copying default configuration..."
    cp -n /var/default/docker/standalone/nginx/default.conf /etc/nginx/conf.d/default.conf
fi

# Install composer dependencies if vendor missing
if [ -f "/var/www/html/composer.json" ] && [ ! -d "/var/www/html/vendor" ]; then
    log_message "Composer dependencies not found. Running composer install..."
    cd /var/www/html || exit
    composer install --no-dev --optimize-autoloader
    cd - || exit
fi

cd /var/www/html || exit

# Generate APP_KEY if missing
if ! grep -q "^APP_KEY=base64:" .env; then
    log_message "APP_KEY not found. Generating new Laravel APP_KEY..."
    php artisan key:generate
fi

# Fix permissions en storage y bootstrap/cache para evitar errores 500
log_message "🔧 Ajustando permisos en storage y bootstrap/cache..."
chown -R laravel:laravel storage bootstrap/cache
chmod -R 775 storage bootstrap/cache
chown -R laravel:laravel /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 storage bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache
chmod -R 777 storage bootstrap/cache
chmod 777 -R /var/www/html/storage
chmod 777 -R /var/www/html/bootstrap/cache
mkdir -p storage/logs
touch storage/logs/laravel.log
chmod -R 775 storage bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

# Limpiar caches para evitar config corrupta
log_message "Limpiando caches de Laravel..."
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache

# Ejecutar migraciones con seed forzado (si hay)
log_message "Ejecutando migraciones de base de datos..."
runuser -u laravel -- php artisan migrate --seed --force

cd - || exit

# Start queue worker
log_message "Starting the queue worker service..."
runuser -u laravel -- php /var/www/html/artisan queue:work --sleep=3 --tries=3 &

# Start Nginx
log_message "Starting Nginx..."
service nginx start

# Start PHP-FPM
log_message "Starting PHP-FPM..."
php-fpm -F
