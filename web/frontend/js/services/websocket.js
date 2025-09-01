/**
 * WebSocket Service
 * Handles real-time communication with backend
 */

export default class WebSocketService {
    constructor() {
        this.ws = null;
        this.reconnectInterval = 5000;
        this.shouldReconnect = true;
        
        // Callbacks
        this.onConnect = null;
        this.onDisconnect = null;
        this.onMessage = null;
    }
    
    /**
     * Connect to WebSocket server
     */
    connect() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const host = window.location.hostname;
        const port = 8000; // FastAPI port
        
        this.ws = new WebSocket(`${protocol}//${host}:${port}/ws`);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
            if (this.onConnect) {
                this.onConnect();
            }
        };
        
        this.ws.onclose = () => {
            console.log('WebSocket disconnected');
            if (this.onDisconnect) {
                this.onDisconnect();
            }
            
            // Auto-reconnect
            if (this.shouldReconnect) {
                setTimeout(() => {
                    console.log('Attempting to reconnect...');
                    this.connect();
                }, this.reconnectInterval);
            }
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
        
        this.ws.onmessage = (event) => {
            try {
                const message = JSON.parse(event.data);
                if (this.onMessage) {
                    this.onMessage(message);
                }
            } catch (error) {
                console.error('Failed to parse WebSocket message:', error);
            }
        };
        
        // Send periodic ping to keep connection alive
        setInterval(() => {
            if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                this.ws.send(JSON.stringify({ type: 'ping' }));
            }
        }, 30000);
        
        return this.ws;
    }
    
    /**
     * Send message to server
     */
    send(data) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(data));
        }
    }
    
    /**
     * Close connection
     */
    close() {
        this.shouldReconnect = false;
        if (this.ws) {
            this.ws.close();
        }
    }
}