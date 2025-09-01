/**
 * NDI Bridge Intercom Control App
 * Vue 3 application with Vuetify
 */

import ApiService from './services/api.js';
import WebSocketService from './services/websocket.js';

export default {
    name: 'IntercomApp',
    data() {
        return {
            // Connection state
            connected: false,
            ws: null,
            
            // Intercom state
            state: {
                mic_muted: false,
                speaker_muted: false,
                mic_volume: 75,
                speaker_volume: 75,
                devices: {
                    input: null,
                    output: null
                }
            },
            
            // Audio levels for VU meters
            audioLevels: {
                mic: 0,
                speaker: 0
            },
            
            // Loading states
            loading: {
                mic: false,
                speaker: false,
                save: false,
                load: false
            },
            
            // Snackbar for notifications
            snackbar: {
                show: false,
                text: '',
                color: 'success'
            }
        }
    },
    
    mounted() {
        // Initialize API service
        this.api = new ApiService();
        
        // Load initial state
        this.loadState();
        
        // Connect WebSocket for real-time updates
        this.connectWebSocket();
    },
    
    beforeUnmount() {
        // Clean up WebSocket
        if (this.ws) {
            this.ws.close();
        }
    },
    
    methods: {
        /**
         * PRIMARY CONTROL: Toggle microphone mute
         */
        async toggleMicMute() {
            this.loading.mic = true;
            try {
                const response = await this.api.toggleMicMute();
                this.state.mic_muted = response.muted;
                this.showNotification(
                    response.muted ? 'Microphone muted' : 'Microphone unmuted',
                    response.muted ? 'warning' : 'success'
                );
            } catch (error) {
                this.showNotification('Failed to toggle microphone', 'error');
            } finally {
                this.loading.mic = false;
            }
        },
        
        /**
         * Toggle speaker mute
         */
        async toggleSpeakerMute() {
            this.loading.speaker = true;
            try {
                const muted = !this.state.speaker_muted;
                await this.api.setSpeakerMute(muted);
                this.state.speaker_muted = muted;
                this.showNotification(
                    muted ? 'Speaker muted' : 'Speaker unmuted',
                    muted ? 'warning' : 'success'
                );
            } catch (error) {
                this.showNotification('Failed to toggle speaker', 'error');
            } finally {
                this.loading.speaker = false;
            }
        },
        
        /**
         * Update speaker volume
         */
        async updateSpeakerVolume() {
            try {
                await this.api.setSpeakerVolume(this.state.speaker_volume);
            } catch (error) {
                this.showNotification('Failed to set volume', 'error');
            }
        },
        
        /**
         * Update microphone volume
         */
        async updateMicVolume() {
            try {
                await this.api.setMicVolume(this.state.mic_volume);
            } catch (error) {
                this.showNotification('Failed to set microphone gain', 'error');
            }
        },
        
        /**
         * Save current settings as default
         */
        async saveAsDefault() {
            this.loading.save = true;
            try {
                await this.api.saveDefaults();
                this.showNotification('Settings saved as default', 'success');
            } catch (error) {
                this.showNotification('Failed to save settings', 'error');
            } finally {
                this.loading.save = false;
            }
        },
        
        /**
         * Load default settings
         */
        async loadDefaults() {
            this.loading.load = true;
            try {
                await this.api.loadDefaults();
                this.showNotification('Default settings loaded', 'success');
                // State will be updated via WebSocket
            } catch (error) {
                this.showNotification('No default settings found', 'warning');
            } finally {
                this.loading.load = false;
            }
        },
        
        /**
         * Load initial state from API
         */
        async loadState() {
            try {
                const state = await this.api.getState();
                this.state = state;
            } catch (error) {
                this.showNotification('Failed to load state', 'error');
            }
        },
        
        /**
         * Connect WebSocket for real-time updates
         */
        connectWebSocket() {
            const wsService = new WebSocketService();
            
            wsService.onConnect = () => {
                this.connected = true;
                this.showNotification('Connected to server', 'success');
            };
            
            wsService.onDisconnect = () => {
                this.connected = false;
                this.showNotification('Disconnected from server', 'error');
            };
            
            wsService.onMessage = (message) => {
                // Handle different message types
                switch (message.type) {
                    case 'audio_levels':
                        this.audioLevels = message.data;
                        break;
                    
                    case 'mic_mute':
                        this.state.mic_muted = message.data.muted;
                        break;
                    
                    case 'speaker_mute':
                        this.state.speaker_muted = message.data.muted;
                        break;
                    
                    case 'mic_volume':
                        this.state.mic_volume = message.data.volume;
                        break;
                    
                    case 'speaker_volume':
                        this.state.speaker_volume = message.data.volume;
                        break;
                    
                    case 'full_state':
                        this.state = message.data;
                        break;
                }
            };
            
            this.ws = wsService.connect();
        },
        
        /**
         * Get color for audio level meter
         */
        audioLevelColor(level) {
            if (level < 70) return 'success';
            if (level < 90) return 'warning';
            return 'error';
        },
        
        /**
         * Show notification snackbar
         */
        showNotification(text, color = 'success') {
            this.snackbar.text = text;
            this.snackbar.color = color;
            this.snackbar.show = true;
        }
    }
}