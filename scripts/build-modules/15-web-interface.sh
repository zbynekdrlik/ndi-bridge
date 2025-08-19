#!/bin/bash
# Web interface setup module - provides browser-based terminal access

setup_web_interface() {
    log "Setting up web interface with ttyd..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFWEB'

# Install ttyd and nginx for web interface
apt-get update
apt-get install -y ttyd nginx

# Disable default nginx site
rm -f /etc/nginx/sites-enabled/default

# Create nginx configuration for NDI Bridge
cat > /etc/nginx/sites-available/ndi-bridge << 'EOFNGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    # Basic authentication
    auth_basic "NDI Bridge Login";
    auth_basic_user_file /etc/nginx/.htpasswd;
    
    # Root directory for static files
    root /var/www/ndi-bridge;
    index index.html;
    
    # Main location - serve static files
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Terminal proxy to ttyd
    location /terminal/ {
        proxy_pass http://127.0.0.1:7681/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
    
    # API endpoints for future use
    location /api/ {
        return 503;
    }
}
EOFNGINX

# Enable the site
ln -s /etc/nginx/sites-available/ndi-bridge /etc/nginx/sites-enabled/

# Create password file for nginx (user: admin, password: newlevel)
# Password hash for 'newlevel': generated with htpasswd
echo 'admin:$apr1$7qPdJqOr$mKl9kUEO9kVCZ.l5TqF8M/' > /etc/nginx/.htpasswd
chmod 600 /etc/nginx/.htpasswd

# Create web root directory
mkdir -p /var/www/ndi-bridge

# Create landing page
cat > /var/www/ndi-bridge/index.html << 'EOFHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NDI Bridge Control Panel</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 10px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 40px;
            max-width: 500px;
            width: 100%;
        }
        
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        
        .info-box {
            background: #f7f7f7;
            border-left: 4px solid #667eea;
            padding: 15px;
            margin-bottom: 25px;
            border-radius: 4px;
        }
        
        .info-box p {
            margin: 5px 0;
            color: #555;
            font-size: 14px;
        }
        
        .info-box strong {
            color: #333;
        }
        
        .btn-container {
            display: flex;
            gap: 10px;
            margin-top: 30px;
        }
        
        .btn {
            flex: 1;
            padding: 12px 24px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 5px;
            font-size: 16px;
            cursor: pointer;
            transition: background 0.3s;
            text-decoration: none;
            text-align: center;
            display: inline-block;
        }
        
        .btn:hover {
            background: #5a67d8;
        }
        
        .btn-secondary {
            background: #48bb78;
        }
        
        .btn-secondary:hover {
            background: #38a169;
        }
        
        .status {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-top: 20px;
            padding: 10px;
            background: #f0fdf4;
            border-radius: 5px;
        }
        
        .status-dot {
            width: 10px;
            height: 10px;
            background: #48bb78;
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0% {
                box-shadow: 0 0 0 0 rgba(72, 187, 120, 0.7);
            }
            70% {
                box-shadow: 0 0 0 10px rgba(72, 187, 120, 0);
            }
            100% {
                box-shadow: 0 0 0 0 rgba(72, 187, 120, 0);
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>NDI Bridge Control Panel</h1>
        <p class="subtitle">Web-based management interface</p>
        
        <div class="info-box">
            <p><strong>Device:</strong> <span id="hostname">Loading...</span></p>
            <p><strong>IP Address:</strong> <span id="ipaddr">Loading...</span></p>
            <p><strong>NDI Name:</strong> <span id="ndiname">Loading...</span></p>
        </div>
        
        <div class="btn-container">
            <a href="/terminal/" class="btn">Open Terminal</a>
            <button class="btn btn-secondary" onclick="refreshInfo()">Refresh</button>
        </div>
        
        <div class="status">
            <div class="status-dot"></div>
            <span>System Online</span>
        </div>
    </div>
    
    <script>
        function refreshInfo() {
            // Get hostname from window location
            document.getElementById('hostname').textContent = window.location.hostname;
            document.getElementById('ipaddr').textContent = window.location.host;
            
            // For NDI name, we'll need to fetch from config
            // For now, extract from hostname
            const hostname = window.location.hostname;
            let ndiName = hostname;
            if (hostname.includes('ndi-bridge-')) {
                ndiName = hostname.replace('ndi-bridge-', '').replace('.local', '');
            } else if (hostname.match(/^\d+\.\d+\.\d+\.\d+$/)) {
                // IP address, use default
                ndiName = 'ndi-bridge';
            }
            document.getElementById('ndiname').textContent = ndiName;
        }
        
        // Load info on page load
        window.addEventListener('load', refreshInfo);
    </script>
</body>
</html>
EOFHTML

# Create ttyd systemd service
cat > /etc/systemd/system/ttyd.service << 'EOFTTYD'
[Unit]
Description=ttyd - Web Terminal
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ttyd -p 7681 -i lo -t fontSize=16 -t 'theme={"background": "#1e1e1e"}' /usr/local/bin/ndi-bridge-welcome-loop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFTTYD

# Enable services
systemctl daemon-reload
systemctl enable nginx
systemctl enable ttyd
systemctl start nginx
systemctl start ttyd

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
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

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
        
        # Check ttyd
        if systemctl is-active --quiet ttyd; then
            echo -e "  Terminal:  ${GREEN}Running${NC} (port 7681)"
        else
            echo -e "  Terminal:  ${RED}Stopped${NC}"
        fi
        
        # Show URLs
        IP=$(ip -4 addr show br0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        HOSTNAME=$(hostname)
        echo ""
        echo -e "${CYAN}Access URLs:${NC}"
        echo "  http://${HOSTNAME}.local/"
        if [ -n "$IP" ]; then
            echo "  http://${IP}/"
        fi
        echo ""
        echo -e "${CYAN}Credentials:${NC}"
        echo "  Username: admin"
        echo "  Password: newlevel"
        ;;
        
    restart)
        log "Restarting web interface services..."
        systemctl restart nginx
        systemctl restart ttyd
        log "Web interface restarted"
        ;;
        
    stop)
        log "Stopping web interface services..."
        systemctl stop nginx
        systemctl stop ttyd
        log "Web interface stopped"
        ;;
        
    start)
        log "Starting web interface services..."
        systemctl start nginx
        systemctl start ttyd
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