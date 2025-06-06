#!/bin/bash

LOG_DIR="/var/www/html/storage/logs"
PROJECT_DIR="/var/www/html"
DEFAULT_DIR="/var/default"

echo "✨ Starting Laravel startup script..."

# Function to log messages
log_message() {
    echo "$1"
    [ -n "$LOG_DIR" ] && echo "$1" >> "$LOG_DIR/startup-script.log"
}

# Limpiar logs anteriores
[ -n "$LOG_DIR" ] && rm -f "$LOG_DIR/startup-script.log"
[ ! -d "$LOG_DIR" ] && LOG_DIR=""

# Copiar archivos si public no existe
if [ ! -d "$PROJECT_DIR/public" ]; then
    log_message "⚠️ Proyecto vacío. Copiando archivos iniciales..."
    cp -nr "$DEFAULT_DIR/." "$PROJECT_DIR/"
    chown -R laravel:laravel "$PROJECT_DIR/"
    chmod -R 755 "$PROJECT_DIR/"
fi

# Copiar .env si no existe
[ ! -f "$PROJECT_DIR/.env" ] && cp -n "$DEFAULT_DIR/.env.example" "$PROJECT_DIR/.env"

# Configurar NGINX si falta
if [ ! -f "/etc/nginx/conf.d/default.conf" ]; then
    log_message "🛠️ Copiando configuración de NGINX..."
    cp -n "$DEFAULT_DIR/docker/standalone/nginx/default.conf" /etc/nginx/conf.d/default.conf
fi

cd "$PROJECT_DIR" || exit

# Instalar dependencias si faltan
if [ ! -d "vendor" ]; then
    log_message "📦 Instalando dependencias con Composer..."
    composer install --no-dev --optimize-autoloader
fi

# Generar APP_KEY si no está
if ! grep -q "APP_KEY=base64" .env || grep -q "APP_KEY=$" .env; then
    log_message "🔐 Generando nueva APP_KEY..."
    php artisan key:generate
fi

# Limpiar y cachear configuración de Laravel
log_message "🧹 Limpiando y cacheando Laravel..."
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache

# Esperar a que la DB esté lista
log_message "⏳ Esperando que la base de datos esté disponible..."
for i in {1..5}; do
    if php artisan migrate:status > /dev/null 2>&1; then
        log_message "✅ Base de datos lista!"
        break
    fi
    log_message "🔁 Esperando DB ($i/5)..."
    sleep 5
done

# Ejecutar migraciones
log_message "🧬 Migrando la base de datos..."
php artisan migrate --seed --force

# Iniciar worker en background
log_message "⚙️ Iniciando worker de colas..."
runuser -u laravel -- php artisan queue:work --sleep=3 --tries=3 &

# Iniciar servicios web
log_message "🚀 Iniciando Nginx..."
service nginx start

log_message "🔥 Iniciando PHP-FPM..."
php-fpm -F
