// API helper
async function api(endpoint, options = {}) {
    const token = localStorage.getItem('token');
    const headers = { ...options.headers };

    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }

    if (options.body && !(options.body instanceof FormData)) {
        headers['Content-Type'] = 'application/json';
    }

    const response = await fetch(`/api${endpoint}`, { ...options, headers });

    if (response.status === 401) {
        localStorage.removeItem('token');
        location.reload();
        throw new Error('Unauthorized');
    }

    return response;
}

function app() {
    return {
        // Auth state
        token: localStorage.getItem('token'),
        loginForm: { username: '', password: '' },

        // UI state
        tab: 'clients',
        loading: false,
        toast: { show: false, message: '', type: 'success' },
        showAddModal: false,
        confirmRevoke: null,
        createdConfig: null,
        createdClientName: '',
        newClientName: '',
        restoreFile: null,

        // Data
        clients: [],
        logs: '',
        autoRefresh: false,
        refreshInterval: null,

        init() {
            if (this.token) {
                this.fetchClients();
            }
        },

        showToast(message, type = 'success') {
            this.toast = { show: true, message, type };
            setTimeout(() => { this.toast.show = false; }, 3000);
        },

        // Auth
        async login() {
            this.loading = true;
            try {
                const res = await fetch('/api/auth/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(this.loginForm),
                });
                if (!res.ok) {
                    const data = await res.json();
                    this.showToast(data.detail || 'Login failed', 'error');
                    return;
                }
                const data = await res.json();
                this.token = data.token;
                localStorage.setItem('token', data.token);
                this.fetchClients();
            } catch (e) {
                this.showToast('Connection error', 'error');
            } finally {
                this.loading = false;
            }
        },

        logout() {
            this.token = null;
            localStorage.removeItem('token');
            this.clients = [];
            this.logs = '';
        },

        // Clients
        async fetchClients() {
            try {
                const res = await api('/clients');
                if (res.ok) {
                    this.clients = await res.json();
                }
            } catch (e) {
                this.showToast('Failed to fetch clients', 'error');
            }
        },

        async addClient() {
            if (!this.newClientName) return;
            this.loading = true;
            try {
                const res = await api('/clients', {
                    method: 'POST',
                    body: JSON.stringify({ name: this.newClientName }),
                });
                const data = await res.json();
                if (!res.ok) {
                    this.showToast(data.detail || 'Failed to create client', 'error');
                    return;
                }
                this.createdConfig = data.config;
                this.createdClientName = data.name;
                this.showAddModal = false;
                this.newClientName = '';
                this.fetchClients();
                this.showToast(`Client "${data.name}" created`);
            } catch (e) {
                this.showToast('Failed to create client', 'error');
            } finally {
                this.loading = false;
            }
        },

        downloadCreatedConfig() {
            const blob = new Blob([this.createdConfig], { type: 'application/x-openvpn-profile' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `${this.createdClientName}.ovpn`;
            a.click();
            URL.revokeObjectURL(url);
        },

        async downloadConfig(name) {
            try {
                const res = await api(`/clients/${encodeURIComponent(name)}/config`);
                if (!res.ok) {
                    this.showToast('Failed to download config', 'error');
                    return;
                }
                const blob = await res.blob();
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `${name}.ovpn`;
                a.click();
                URL.revokeObjectURL(url);
            } catch (e) {
                this.showToast('Failed to download config', 'error');
            }
        },

        async revokeClient(name) {
            this.loading = true;
            try {
                const res = await api(`/clients/${encodeURIComponent(name)}`, {
                    method: 'DELETE',
                });
                if (res.ok) {
                    this.showToast(`Client "${name}" revoked`);
                    this.fetchClients();
                } else {
                    const data = await res.json();
                    this.showToast(data.detail || 'Failed to revoke', 'error');
                }
            } catch (e) {
                this.showToast('Failed to revoke client', 'error');
            } finally {
                this.loading = false;
            }
        },

        // Backup
        async downloadBackup() {
            this.loading = true;
            try {
                const res = await api('/backup');
                if (!res.ok) {
                    this.showToast('Failed to download backup', 'error');
                    return;
                }
                const blob = await res.blob();
                const disposition = res.headers.get('Content-Disposition') || '';
                const match = disposition.match(/filename="?(.+?)"?$/);
                const filename = match ? match[1] : 'openvpn-backup.zip';
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = filename;
                a.click();
                URL.revokeObjectURL(url);
                this.showToast('Backup downloaded');
            } catch (e) {
                this.showToast('Failed to download backup', 'error');
            } finally {
                this.loading = false;
            }
        },

        async restoreBackup() {
            if (!this.restoreFile) return;
            this.loading = true;
            try {
                const formData = new FormData();
                formData.append('file', this.restoreFile);
                const res = await api('/backup/restore', {
                    method: 'POST',
                    body: formData,
                });
                if (res.ok) {
                    this.showToast('Backup restored successfully. OpenVPN restarted.');
                    this.restoreFile = null;
                    this.fetchClients();
                } else {
                    const data = await res.json();
                    this.showToast(data.detail || 'Failed to restore', 'error');
                }
            } catch (e) {
                this.showToast('Failed to restore backup', 'error');
            } finally {
                this.loading = false;
            }
        },

        // Logs
        async fetchLogs() {
            try {
                const res = await api('/logs?lines=200');
                if (res.ok) {
                    const data = await res.json();
                    this.logs = data.logs;
                }
            } catch (e) {
                this.showToast('Failed to fetch logs', 'error');
            }
        },

        toggleAutoRefresh() {
            if (this.autoRefresh) {
                this.refreshInterval = setInterval(() => this.fetchLogs(), 5000);
            } else {
                clearInterval(this.refreshInterval);
                this.refreshInterval = null;
            }
        },

        destroy() {
            if (this.refreshInterval) {
                clearInterval(this.refreshInterval);
            }
        },
    };
}
