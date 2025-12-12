const API_BASE = '/api';

// State
let state = {
    inbox: [],
    board: [],
    system: {}
};

// Init
document.addEventListener('DOMContentLoaded', () => {
    fetchData();
    setInterval(fetchData, 5000); // Auto-refresh every 5s
});

// Switch Views
function switchView(viewName) {
    document.querySelectorAll('.view').forEach(el => el.classList.add('hidden'));
    document.getElementById(`view-${viewName}`).classList.remove('hidden');

    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    document.querySelector(`a[href="#${viewName}"]`).classList.add('active');
}

// Fetch Data
async function fetchData() {
    try {
        const res = await fetch(`${API_BASE}/data`);
        state = await res.json();
        render();
    } catch (e) {
        console.error("Failed to fetch data", e);
    }
}

// Render
function render() {
    // 1. Inbox
    const inboxList = document.getElementById('inbox-list');
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

    if (state.inbox.length === 0) {
        inboxList.innerHTML = '<div style="color: var(--text-secondary); grid-column: 1/-1; text-align: center; padding: 40px;">No pending reviews. good job!</div>';
    }

    document.getElementById('inbox-count').innerText = state.inbox.length;

    // 2. Board
    renderBoardColumn('col-todo', 'To Do');
    renderBoardColumn('col-inprogress', 'In Progress');
    renderBoardColumn('col-review', 'Review');
    renderBoardColumn('col-done', 'Done');

    // 3. System
    document.getElementById('active-agent').innerText = state.system.active_agent;
    document.getElementById('agent-name').innerText = state.system.active_agent.toUpperCase();
    document.getElementById('agent-workspace').innerText = `workspace/${state.system.active_agent}`;
}

function renderBoardColumn(colId, status) {
    const col = document.querySelector(`#${colId} .column-content`);
    const items = state.board.filter(t => t.status === status);
    col.innerHTML = items.map(t => `
        <div class="ticket-card">
            <div class="ticket-id">${t.id}</div>
            <div class="ticket-title">${t.title}</div>
        </div>
    `).join('');
}

// Actions
async function approveCR(id) {
    if (!confirm(`Approve ${id}? This will merge code.`)) return;
    try {
        const res = await fetch(`${API_BASE}/approve`, {
            method: 'POST',
            body: JSON.stringify({ id })
        });
        const result = await res.json();
        if (result.success) {
            alert('Approved successfully!');
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
        const res = await fetch(`${API_BASE}/reject`, {
            method: 'POST',
            body: JSON.stringify({ id })
        });
        fetchData();
    } catch (e) {
        alert('Network error');
    }
}
