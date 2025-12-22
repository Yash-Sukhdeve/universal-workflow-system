/**
 * UWS Dashboard - Real-Time Multi-Agent Monitoring
 * Supports WebSocket for live updates with polling fallback
 */

const API_BASE = '/api';
const WS_RECONNECT_DELAY = 3000;
const POLL_INTERVAL = 5000;

// State
let state = {
    inbox: [],
    board: [],
    sessions: [],
    system: {
        active_agent: 'None',
        active_session_count: 0,
        status: 'Unknown',
        websocket_available: false
    }
};

// WebSocket connection
let ws = null;
let wsReconnectTimer = null;
let pollingTimer = null;

// Agent configuration (colors and icons)
const AGENT_CONFIG = {
    researcher: { icon: '🔬', color: '#3498db', name: 'Researcher' },
    architect: { icon: '🏗️', color: '#9b59b6', name: 'Architect' },
    implementer: { icon: '💻', color: '#2ecc71', name: 'Implementer' },
    experimenter: { icon: '🧪', color: '#e67e22', name: 'Experimenter' },
    optimizer: { icon: '⚡', color: '#e74c3c', name: 'Optimizer' },
    deployer: { icon: '🚀', color: '#1abc9c', name: 'Deployer' },
    documenter: { icon: '📝', color: '#f1c40f', name: 'Documenter' }
};

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    // Initial data fetch
    await fetchData();

    // Try to connect WebSocket
    await initWebSocket();

    // Fallback to polling if WebSocket unavailable
    if (!state.system.websocket_available) {
        startPolling();
    }
});

// WebSocket Management
async function initWebSocket() {
    try {
        const res = await fetch(`${API_BASE}/ws-info`);
        const info = await res.json();

        if (info.websocket_available && info.ws_url) {
            connectWebSocket(info.ws_url);
        }
    } catch (e) {
        console.log('WebSocket info unavailable, using polling');
        startPolling();
    }
}

function connectWebSocket(wsUrl) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        return;
    }

    console.log('Connecting to WebSocket:', wsUrl);

    try {
        ws = new WebSocket(wsUrl);

        ws.onopen = () => {
            console.log('WebSocket connected');
            updateConnectionStatus(true);
            stopPolling();
        };

        ws.onmessage = (event) => {
            try {
                const message = JSON.parse(event.data);
                handleWebSocketMessage(message);
            } catch (e) {
                console.error('Failed to parse WebSocket message', e);
            }
        };

        ws.onclose = () => {
            console.log('WebSocket disconnected');
            updateConnectionStatus(false);
            scheduleReconnect(wsUrl);
        };

        ws.onerror = (error) => {
            console.error('WebSocket error', error);
            updateConnectionStatus(false);
        };
    } catch (e) {
        console.error('Failed to create WebSocket', e);
        startPolling();
    }
}

function scheduleReconnect(wsUrl) {
    if (wsReconnectTimer) {
        clearTimeout(wsReconnectTimer);
    }

    wsReconnectTimer = setTimeout(() => {
        connectWebSocket(wsUrl);
    }, WS_RECONNECT_DELAY);

    // Start polling while reconnecting
    startPolling();
}

function handleWebSocketMessage(message) {
    const { event, data } = message;

    switch (event) {
        case 'initial_state':
            state.sessions = data.sessions || [];
            renderAgents();
            break;

        case 'sessions_update':
            state.sessions = data.sessions || [];
            renderAgents();
            break;

        case 'agent_started':
            // Add new session
            const newSession = {
                id: data.session_id,
                agent: data.agent,
                task: data.task,
                status: 'active',
                progress: 0,
                ...AGENT_CONFIG[data.agent]
            };
            state.sessions.push(newSession);
            renderAgents();
            showNotification(`${AGENT_CONFIG[data.agent]?.icon || '🤖'} ${data.agent} started: ${data.task}`);
            break;

        case 'agent_progress':
            // Update session progress
            const session = state.sessions.find(s => s.id === data.session_id);
            if (session) {
                session.progress = data.progress;
                renderAgents();
            }
            break;

        case 'agent_completed':
            // Remove completed session
            state.sessions = state.sessions.filter(s => s.id !== data.session_id);
            renderAgents();
            showNotification(`✅ Agent completed: ${data.result}`);
            break;

        case 'pong':
            // Heartbeat response
            break;

        default:
            console.log('Unknown WebSocket event:', event);
    }
}

// Polling Fallback
function startPolling() {
    if (pollingTimer) return;

    pollingTimer = setInterval(fetchData, POLL_INTERVAL);
    console.log('Polling started');
}

function stopPolling() {
    if (pollingTimer) {
        clearInterval(pollingTimer);
        pollingTimer = null;
        console.log('Polling stopped');
    }
}

// Data Fetching
async function fetchData() {
    try {
        const res = await fetch(`${API_BASE}/data`);
        const data = await res.json();

        state.inbox = data.inbox || [];
        state.board = data.board || [];
        state.sessions = data.sessions || [];
        state.system = data.system || state.system;

        render();
    } catch (e) {
        console.error('Failed to fetch data', e);
    }
}

// UI Updates
function updateConnectionStatus(connected) {
    const indicator = document.getElementById('connection-status');
    if (indicator) {
        indicator.className = connected ? 'status-dot connected' : 'status-dot disconnected';
        indicator.title = connected ? 'Real-time connected' : 'Polling mode';
    }
}

function showNotification(message) {
    // Simple notification - could be enhanced with a toast library
    console.log('Notification:', message);

    const container = document.getElementById('notifications');
    if (container) {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        container.appendChild(notification);

        setTimeout(() => {
            notification.remove();
        }, 5000);
    }
}

// View Management
function switchView(viewName) {
    document.querySelectorAll('.view').forEach(el => el.classList.add('hidden'));
    document.getElementById(`view-${viewName}`).classList.remove('hidden');

    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    const navItem = document.querySelector(`a[href="#${viewName}"]`);
    if (navItem) navItem.classList.add('active');
}

// Render Functions
function render() {
    renderInbox();
    renderBoard();
    renderAgents();
    renderSystemInfo();
}

function renderInbox() {
    const inboxList = document.getElementById('inbox-list');
    if (!inboxList) return;

    if (state.inbox.length === 0) {
        inboxList.innerHTML = `
            <div class="empty-state">
                <span class="empty-icon">📭</span>
                <p>No pending reviews</p>
            </div>
        `;
    } else {
        inboxList.innerHTML = state.inbox.map(cr => `
            <div class="card">
                <div class="card-header">
                    <span>${cr.id}</span>
                    <span>${cr.date}</span>
                </div>
                <div class="card-title">${cr.ticket !== "None" ? cr.ticket + ': ' : ''} Code Submission</div>
                <div class="card-meta">
                    Agent: <span style="color: var(--accent)">${cr.agent}</span>
                </div>
                <div class="actions">
                    <button class="btn btn-approve" onclick="approveCR('${cr.id}')">Approve</button>
                    <button class="btn btn-reject" onclick="rejectCR('${cr.id}')">Reject</button>
                </div>
            </div>
        `).join('');
    }

    const countEl = document.getElementById('inbox-count');
    if (countEl) countEl.innerText = state.inbox.length;
}

function renderBoard() {
    renderBoardColumn('col-todo', 'To Do');
    renderBoardColumn('col-inprogress', 'In Progress');
    renderBoardColumn('col-review', 'Review');
    renderBoardColumn('col-done', 'Done');
}

function renderBoardColumn(colId, status) {
    const col = document.querySelector(`#${colId} .column-content`);
    if (!col) return;

    const items = state.board.filter(t => t.status === status);
    col.innerHTML = items.map(t => `
        <div class="ticket-card">
            <div class="ticket-id">${t.id}</div>
            <div class="ticket-title">${t.title}</div>
        </div>
    `).join('');
}

function renderAgents() {
    const agentsList = document.getElementById('agents-list');
    if (!agentsList) return;

    const sessionCount = state.sessions.length;

    // Update header count
    const countEl = document.getElementById('agent-count');
    if (countEl) countEl.innerText = sessionCount;

    if (sessionCount === 0) {
        agentsList.innerHTML = `
            <div class="empty-state">
                <span class="empty-icon">🤖</span>
                <p>No active agents</p>
                <p class="empty-hint">Activate an agent with: ./scripts/activate_agent.sh &lt;agent&gt;</p>
            </div>
        `;
    } else {
        agentsList.innerHTML = state.sessions.map(session => {
            const config = AGENT_CONFIG[session.agent] || { icon: '🤖', color: '#888', name: session.agent };
            const progress = session.progress || 0;
            const elapsed = session.elapsed_minutes || 0;
            const status = session.status || 'active';

            const statusClass = status === 'active' ? 'status-active' :
                               status === 'completing' ? 'status-completing' : 'status-idle';
            const statusIcon = status === 'active' ? '🟢' :
                              status === 'completing' ? '🟡' : '⚪';

            return `
                <div class="agent-card" style="--agent-color: ${config.color}">
                    <div class="agent-header">
                        <span class="agent-icon">${config.icon}</span>
                        <span class="agent-name">${config.name.toUpperCase()}</span>
                        <span class="agent-status ${statusClass}">${statusIcon} ${status}</span>
                    </div>
                    <div class="agent-task">
                        <label>Task:</label>
                        <span>${session.task || 'No task assigned'}</span>
                    </div>
                    <div class="agent-progress">
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${progress}%; background: ${config.color}"></div>
                        </div>
                        <span class="progress-text">${progress}%</span>
                    </div>
                    <div class="agent-footer">
                        <span class="elapsed-time">⏱ ${formatElapsed(elapsed)}</span>
                        <span class="session-id">${session.id}</span>
                    </div>
                </div>
            `;
        }).join('');
    }

    // Also update legacy single-agent display
    const activeAgentEl = document.getElementById('active-agent');
    const agentNameEl = document.getElementById('agent-name');
    const agentWorkspaceEl = document.getElementById('agent-workspace');

    if (activeAgentEl) activeAgentEl.innerText = state.system.active_agent || 'None';
    if (agentNameEl) agentNameEl.innerText = (state.system.active_agent || 'NONE').toUpperCase();
    if (agentWorkspaceEl) agentWorkspaceEl.innerText = state.system.active_agent ? `workspace/${state.system.active_agent}` : 'N/A';
}

function renderSystemInfo() {
    const statusEl = document.getElementById('system-status');
    if (statusEl) {
        statusEl.innerText = state.system.status || 'Unknown';
        statusEl.className = state.system.status === 'Healthy' ? 'status-healthy' : 'status-warning';
    }
}

function formatElapsed(minutes) {
    if (minutes < 1) return 'Just started';
    if (minutes < 60) return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    return `${hours}h ${mins}m`;
}

// Actions
async function approveCR(id) {
    if (!confirm(`Approve ${id}? This will merge code.`)) return;
    try {
        const res = await fetch(`${API_BASE}/approve`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id })
        });
        const result = await res.json();
        if (result.success) {
            showNotification('✅ Approved successfully!');
            fetchData();
        } else {
            alert('Error: ' + result.error);
        }
    } catch (e) {
        alert('Network error');
    }
}

async function rejectCR(id) {
    if (!confirm(`Reject ${id}?`)) return;
    try {
        await fetch(`${API_BASE}/reject`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id })
        });
        showNotification('❌ Rejected');
        fetchData();
    } catch (e) {
        alert('Network error');
    }
}

// Manual refresh
function refreshData() {
    fetchData();
    showNotification('🔄 Refreshed');
}

// Expose for HTML onclick handlers
window.switchView = switchView;
window.approveCR = approveCR;
window.rejectCR = rejectCR;
window.refreshData = refreshData;
