#!/bin/bash

# Log directory
LOG_DIR="/var/www/html/storage/logs"

echo "Starting script..."

echo "Clearing log file..."
# clean all logs in log directory
if [ -n "$LOG_DIR" ]; then
    rm -f "$LOG_DIR/startup-script.log"
fi

# Check if log directory exists
if [ ! -d "$LOG_DIR" ]; then
    echo "Warning: Log directory does not exist (maybe first install ?). Logging disabled until restart."
    LOG_DIR=""
fi

# Function to log messages
log_message() {
    if [ -n "$LOG_DIR" ]; then
        echo "$1" >> "$LOG_DIR/startup-script.log"
    fi
    echo "$1"
}

# Check if public folder exists. If not, copy project.
if [ ! -d "/var/www/html/public" ]; then
    log_message "Warning: project folder is empty. Copying default files..."
    cp -nr /var/default/. /var/www/html
    chown -R laravel:laravel /var/www/html/
    chmod -R 755 /var/www/html/
fi

# Copy .env file if not exists
cp -n /var/default/.env.example /var/www/html/.env

# Check and copy default Nginx configuration if not exists
if [ ! -f "/etc/nginx/conf.d/default.conf" ]; then
    log_message "Warning: Nginx configuration not found. Copying default configuration..."
    cp -n /var/default/docker/standalone/nginx/default.conf /etc/nginx/conf.d/default.conf
fi

# Install dependencies if needed
if [ -f "/var/www/html/composer.json" ] && [ ! -d "/var/www/html/vendor" ]; then
    log_message "Warning: Composer dependencies not found. Running composer install..."
    cd /var/www/html || exit
    composer install --no-dev --optimize-autoloader
    cd - || exit
fi

# ⚙️ Generate APP_KEY if not exists
cd /var/www/html || exit
if ! grep -q "APP_KEY=base64" .env; then
    log_message "APP_KEY not found. Generating new Laravel APP_KEY..."
    php artisan key:generate
fi
cd - || exit

# Start the queue worker service
log_message "Starting the queue worker service..."
runuser -u laravel -- php /var/www/html/artisan queue:work --sleep=3 --tries=3 &

# Run database migrations
log_message "Migrate Database to current state..."
runuser -u laravel -- php artisan migrate --seed --force

# Start Nginx
log_message "Starting Nginx..."
service nginx start

# Start PHP-FPM
log_message "Starting PHP-FPM..."
php-fpm -F
