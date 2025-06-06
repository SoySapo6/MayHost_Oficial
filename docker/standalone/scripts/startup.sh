#!/bin/bash

LOG_DIR="/var/www/html/storage/logs"

echo "Starting script..."

if [ ! -d "$LOG_DIR" ]; then
    echo "Creating log directory..."
    mkdir -p "$LOG_DIR"
fi

# Log helper
log_message() {
    echo "$1"
    if [ -d "$LOG_DIR" ]; then
        echo "$1" >> "$LOG_DIR/startup-script.log"
    fi
}

# Copiar archivos si falta la carpeta pública
if [ ! -d "/var/www/html/public" ]; then
    log_message "Warning: project folder is empty. Copying default files..."
    cp -nr /var/default/. /var/www/html
    chown -R laravel:laravel /var/www/html/
    chmod -R 755 /var/www/html/
fi

# Copiar .env si falta
cp -n /var/default/.env.example /var/www/html/.env

# Copiar configuración nginx si falta
if [ ! -f "/etc/nginx/conf.d/default.conf" ]; then
    log_message "Warning: Nginx configuration not found. Copying default configuration..."
    cp -n /var/default/docker/standalone/nginx/default.conf /etc/nginx/conf.d/default.conf
fi

# Instalar dependencias composer si falta vendor
if [ -f "/var/www/html/composer.json" ] && [ ! -d "/var/www/html/vendor" ]; then
    log_message "Composer dependencies not found. Running composer install..."
    cd /var/www/html || exit
    composer install --no-dev --optimize-autoloader
    cd - || exit
fi

cd /var/www/html || exit

# Generar APP_KEY si falta
if ! grep -q "^APP_KEY=base64:" .env; then
    log_message "APP_KEY not found. Generating new Laravel APP_KEY..."
    php artisan key:generate
fi

# Arreglar permisos y dueños de storage y bootstrap/cache — la dupla ganadora es usar el usuario que corre PHP-FPM, que en tu caso es **laravel** (por lo que veo en Dockerfile) y darle permisos 775
log_message "🔧 Ajustando permisos en storage y bootstrap/cache..."

chown -R laravel:laravel storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# Crear el archivo laravel.log si no existe
touch storage/logs/laravel.log
chmod 664 storage/logs/laravel.log
chown laravel:laravel storage/logs/laravel.log

# Limpiar caches de Laravel para que no haya config corrupta
log_message "Limpiando caches de Laravel..."
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache

# Migrar base de datos con seed
log_message "Ejecutando migraciones de base de datos..."
runuser -u laravel -- php artisan migrate --seed --force

cd - || exit

# Iniciar queue worker en background
log_message "Starting the queue worker service..."
runuser -u laravel -- php /var/www/html/artisan queue:work --sleep=3 --tries=3 &

# Iniciar Nginx
log_message "Starting Nginx..."
service nginx start

# Iniciar PHP-FPM en primer plano
log_message "Starting PHP-FPM..."
php-fpm -F
