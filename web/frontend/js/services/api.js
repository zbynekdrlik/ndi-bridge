/**
 * API Service
 * Handles all HTTP requests to FastAPI backend
 */

export default class ApiService {
    constructor() {
        this.baseUrl = '/api/intercom';
    }
    
    /**
     * Make API request
     */
    async request(method, endpoint, data = null) {
        const options = {
            method,
            headers: {
                'Content-Type': 'application/json'
            }
        };
        
        if (data) {
            options.body = JSON.stringify(data);
        }
        
        const response = await fetch(this.baseUrl + endpoint, options);
        
        if (!response.ok) {
            throw new Error(`API Error: ${response.statusText}`);
        }
        
        return await response.json();
    }
    
    /**
     * Get current state
     */
    async getState() {
        return await this.request('GET', '/state');
    }
    
    /**
     * Toggle mic mute (PRIMARY CONTROL)
     */
    async toggleMicMute() {
        return await this.request('POST', '/mic/toggle');
    }
    
    /**
     * Set mic mute state
     */
    async setMicMute(muted) {
        return await this.request('POST', '/mic/mute', { muted });
    }
    
    /**
     * Set speaker mute state
     */
    async setSpeakerMute(muted) {
        return await this.request('POST', '/speaker/mute', { muted });
    }
    
    /**
     * Set speaker volume
     */
    async setSpeakerVolume(volume) {
        return await this.request('POST', '/speaker/volume', { volume });
    }
    
    /**
     * Set mic volume
     */
    async setMicVolume(volume) {
        return await this.request('POST', '/mic/volume', { volume });
    }
    
    /**
     * Save current settings as default
     */
    async saveDefaults() {
        return await this.request('POST', '/save-defaults');
    }
    
    /**
     * Load default settings
     */
    async loadDefaults() {
        return await this.request('POST', '/load-defaults');
    }
    
    /**
     * Get audio devices
     */
    async getDevices() {
        return await this.request('GET', '/devices');
    }
}