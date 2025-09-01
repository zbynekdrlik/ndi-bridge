#!/bin/bash
# Web interface setup module - provides browser-based terminal access

setup_web_interface() {
    log "Setting up web interface with wetty..."
    
    # Copy systemd service files BEFORE chroot
    mkdir -p /mnt/usb/etc/systemd/system
    for service in wetty.service nginx-tmpfs-dirs.service; do
        if [ -f files/systemd/system/$service ]; then
            cp files/systemd/system/$service /mnt/usb/etc/systemd/system/
            log "  Copied $service"
        else
            warn "  $service not found in files/systemd/system/"
        fi
    done
    
    # Copy new FastAPI/Vue web interface BEFORE chroot
    WEB_DIR="$(dirname "$0")/../web"
    if [ -d "$WEB_DIR/backend" ] && [ -d "$WEB_DIR/frontend" ]; then
        log "Copying FastAPI/Vue intercom interface..."
        
        # Create directory structure
        mkdir -p /mnt/usb/opt/ndi-bridge-web/backend
        mkdir -p /mnt/usb/opt/ndi-bridge-web/frontend
        
        # Copy backend files
        cp -r "$WEB_DIR/backend"/* /mnt/usb/opt/ndi-bridge-web/backend/
        
        # Copy frontend files  
        cp -r "$WEB_DIR/frontend"/* /mnt/usb/opt/ndi-bridge-web/frontend/
        
        # Copy systemd service if available
        if [ -f "$WEB_DIR/ndi-bridge-intercom-web.service" ]; then
            cp "$WEB_DIR/ndi-bridge-intercom-web.service" /mnt/usb/etc/systemd/system/
        fi
        
        log "  FastAPI/Vue interface copied"
    fi
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFWEB'

# Install wetty dependencies and nginx for web interface
apt-get update -qq 2>&1 | grep -v "^Get:\|^Hit:\|^Reading" || true
apt-get install -y -qq nginx nodejs npm apache2-utils python3-pip 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building\|^Unpacking\|^Setting up\|Processing triggers\|database" || true
npm install -g wetty@2.0.2 2>&1 | grep -v "^npm notice\|^npm WARN" || true

# Install FastAPI dependencies for new intercom interface
if [ -f /opt/ndi-bridge-web/backend/requirements.txt ]; then
    echo "Installing FastAPI dependencies..."
    pip3 install -r /opt/ndi-bridge-web/backend/requirements.txt --break-system-packages 2>&1 | grep -v "Requirement already satisfied" || true
    
    # Enable the new intercom web service
    if [ -f /etc/systemd/system/ndi-bridge-intercom-web.service ]; then
        systemctl enable ndi-bridge-intercom-web.service || true
    fi
fi

# Disable default nginx site
rm -f /etc/nginx/sites-enabled/default

# Create nginx configuration for NDI Bridge
cat > /etc/nginx/sites-available/ndi-bridge << 'EOFNGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    # Root directory for intercom frontend (no auth for intercom)
    root /opt/ndi-bridge-web/frontend;
    index index.html;
    
    # Serve intercom interface at root
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Intercom API endpoints
    location /api/intercom/ {
        proxy_pass http://127.0.0.1:8000/api/intercom/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # WebSocket support for real-time updates
    location /ws {
        proxy_pass http://127.0.0.1:8000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Terminal interface (with authentication)
    location /terminal/ {
        auth_basic "NDI Bridge Terminal";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://127.0.0.1:7681/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # FastAPI documentation
    location /docs {
        proxy_pass http://127.0.0.1:8000/docs;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /openapi.json {
        proxy_pass http://127.0.0.1:8000/openapi.json;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOFNGINX

# Enable the site
ln -s /etc/nginx/sites-available/ndi-bridge /etc/nginx/sites-enabled/

# Create password file for nginx (user: admin, password: newlevel)
# Using htpasswd to generate the password file
htpasswd -b -c /etc/nginx/.htpasswd admin newlevel
chmod 644 /etc/nginx/.htpasswd

# Note: Web interface files are already copied before chroot in setup_web_interface()
# The intercom frontend is served directly from /opt/ndi-bridge-web/frontend/

# Create tmux session wrapper for shared persistent sessions
cat > /usr/local/bin/ndi-bridge-tmux-session << 'EOFTMUX'
#!/bin/bash
# Persistent tmux session - shared across all connections

SESSION="ndi-bridge"

# Check if tmux session exists
if ! tmux has-session -t $SESSION 2>/dev/null; then
    # Create new session only if it doesn't exist
    tmux new-session -d -s $SESSION
    
    # Start with welcome loop
    tmux send-keys -t $SESSION "/usr/local/bin/ndi-bridge-welcome-loop" C-m
fi

# Attach to the existing session (multiple connections share the same view)
exec tmux attach-session -t $SESSION
EOFTMUX

chmod +x /usr/local/bin/ndi-bridge-tmux-session

# wetty.service was copied before chroot

# Create nginx writable directories for read-only filesystem
mkdir -p /var/lib/nginx/body
mkdir -p /var/lib/nginx/proxy
mkdir -p /var/lib/nginx/fastcgi
mkdir -p /var/lib/nginx/uwsgi
mkdir -p /var/lib/nginx/scgi
mkdir -p /var/log/nginx
chown -R www-data:www-data /var/lib/nginx
chown -R www-data:www-data /var/log/nginx

# nginx-tmpfs-dirs.service was copied before chroot

# Enable services
systemctl daemon-reload
systemctl enable nginx-tmpfs-dirs
systemctl enable nginx
systemctl enable wetty
systemctl start nginx-tmpfs-dirs
systemctl start nginx
systemctl start wetty

# Create helper script for web interface management
cat > /usr/local/bin/ndi-bridge-web << 'EOFWEBHELPER'
#!/bin/bash
# NDI Bridge Web Interface Management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper functions
# Use log function from 01-functions.sh, don't redefine it

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "This script must be run as root"
fi

case "$1" in
    status)
        echo -e "${CYAN}Web Interface Status:${NC}"
        echo ""
        
        # Check nginx
        if systemctl is-active --quiet nginx; then
            echo -e "  Nginx:     ${GREEN}Running${NC} (port 80)"
        else
            echo -e "  Nginx:     ${RED}Stopped${NC}"
        fi
        
        # Check wetty
        if systemctl is-active --quiet wetty; then
            echo -e "  Terminal:  ${GREEN}Running${NC} (port 7681)"
        else
            echo -e "  Terminal:  ${RED}Stopped${NC}"
        fi
        
        # Show URLs
        IP=$(ip -4 addr show br0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        HOSTNAME=$(hostname)
        echo ""
        echo -e "${CYAN}Access URLs:${NC}"
        echo "  Intercom: http://${HOSTNAME}.local/ (no auth)"
        echo "  Terminal: http://${HOSTNAME}.local/terminal/ (auth required)"
        if [ -n "$IP" ]; then
            echo "  Intercom: http://${IP}/ (no auth)"
            echo "  Terminal: http://${IP}/terminal/ (auth required)"
        fi
        echo ""
        echo -e "${CYAN}Terminal Credentials:${NC}"
        echo "  Username: admin"
        echo "  Password: newlevel"
        ;;
        
    restart)
        log "Restarting web interface services..."
        systemctl restart nginx
        systemctl restart wetty
        log "Web interface restarted"
        ;;
        
    stop)
        log "Stopping web interface services..."
        systemctl stop nginx
        systemctl stop wetty
        log "Web interface stopped"
        ;;
        
    start)
        log "Starting web interface services..."
        systemctl start nginx
        systemctl start wetty
        log "Web interface started"
        ;;
        
    password)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 password <new-password>"
            exit 1
        fi
        
        NEW_PASS="$2"
        log "Changing web interface password..."
        
        # Generate new htpasswd entry
        HASH=$(openssl passwd -apr1 "$NEW_PASS")
        echo "admin:$HASH" > /etc/nginx/.htpasswd
        chmod 600 /etc/nginx/.htpasswd
        
        # Reload nginx
        systemctl reload nginx
        
        log "Password changed successfully"
        ;;
        
    *)
        echo "Usage: $0 {status|restart|stop|start|password <new-password>}"
        echo ""
        echo "Commands:"
        echo "  status   - Show web interface status"
        echo "  restart  - Restart web services"
        echo "  stop     - Stop web services"
        echo "  start    - Start web services"
        echo "  password - Change web interface password"
        exit 1
        ;;
esac
EOFWEBHELPER

chmod +x /usr/local/bin/ndi-bridge-web

# Add web interface info to the welcome script
sed -i '/Web Interface (future)/c\
echo -e "${CYAN}Web Interface:${NC}"\
echo "  - http://${FULL_HOSTNAME}.local/"\
echo "  - http://${NEW_NAME}.local/"\
echo "  Username: admin, Password: newlevel"' /usr/local/bin/ndi-bridge-set-name

EOFWEB
}