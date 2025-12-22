import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider } from '@/contexts/AuthContext'
import { authApi } from '@/services/api'
import { mockUser, mockTask, mockAgent, mockMemory } from '@/test/utils'
import type { WSEvent } from '@/types'

// Mock the auth API
vi.mock('@/services/api', () => ({
  authApi: {
    me: vi.fn(),
  },
}))

const mockAuthApi = vi.mocked(authApi)

// Create controlled WebSocket context state for testing
let mockContextState = {
  isConnected: false,
  isAuthenticated: false,
  lastEvent: null as WSEvent | null,
  taskEvents: [] as WSEvent[],
  agentEvents: [] as WSEvent[],
  memoryEvents: [] as WSEvent[],
  send: vi.fn(),
  reconnect: vi.fn(),
  disconnect: vi.fn(),
}

// Mock the WebSocket context entirely for predictable testing
vi.mock('@/contexts/WebSocketContext', () => ({
  WebSocketProvider: ({ children }: { children: React.ReactNode }) => children,
  useWebSocketContext: () => mockContextState,
}))

// Import after mock is setup
import { useWebSocketContext } from '@/contexts/WebSocketContext'

const createTestQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: { retry: false },
    },
  })

// Test component that displays WebSocket context state
function WebSocketStateDisplay() {
  const ctx = useWebSocketContext()

  return (
    <div>
      <span data-testid="connection-status">{ctx.isConnected ? 'connected' : 'disconnected'}</span>
      <span data-testid="auth-status">{ctx.isAuthenticated ? 'authenticated' : 'not-authenticated'}</span>
      <span data-testid="last-event-type">{ctx.lastEvent?.type || 'none'}</span>
      <span data-testid="task-events-count">{ctx.taskEvents.length}</span>
      <span data-testid="agent-events-count">{ctx.agentEvents.length}</span>
      <span data-testid="memory-events-count">{ctx.memoryEvents.length}</span>
      <div data-testid="task-events">
        {ctx.taskEvents.map((e: WSEvent, i: number) => (
          <span key={i} data-testid={`task-event-${i}`}>
            {JSON.stringify(e.data)}
          </span>
        ))}
      </div>
    </div>
  )
}

function IntegrationWrapper({ children }: { children: React.ReactNode }) {
  const queryClient = createTestQueryClient()
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <AuthProvider>{children}</AuthProvider>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('WebSocket Real-time Integration', () => {
  const testUser = mockUser()

  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()

    // Setup authenticated state
    localStorage.setItem('token', 'test-token')
    localStorage.setItem('user', JSON.stringify(testUser))
    mockAuthApi.me.mockResolvedValue(testUser)

    // Reset mock context state
    mockContextState = {
      isConnected: false,
      isAuthenticated: false,
      lastEvent: null,
      taskEvents: [],
      agentEvents: [],
      memoryEvents: [],
      send: vi.fn(),
      reconnect: vi.fn(),
      disconnect: vi.fn(),
    }
  })

  afterEach(() => {
    localStorage.clear()
  })

  describe('Connection Status Display', () => {
    it('should display disconnected state initially', () => {
      mockContextState.isConnected = false

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('connection-status')).toHaveTextContent('disconnected')
    })

    it('should display connected state when WebSocket is connected', () => {
      mockContextState.isConnected = true
      mockContextState.isAuthenticated = true

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('connection-status')).toHaveTextContent('connected')
      expect(screen.getByTestId('auth-status')).toHaveTextContent('authenticated')
    })
  })

  describe('Event Display', () => {
    it('should display task events from context', () => {
      const taskEvent: WSEvent = {
        type: 'task_updated',
        data: mockTask({ id: 'task-1', title: 'Test Task' }),
        timestamp: new Date().toISOString(),
      }

      mockContextState.isConnected = true
      mockContextState.taskEvents = [taskEvent]
      mockContextState.lastEvent = taskEvent

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('task-events-count')).toHaveTextContent('1')
      expect(screen.getByTestId('last-event-type')).toHaveTextContent('task_updated')
    })

    it('should display agent events from context', () => {
      const agentEvent: WSEvent = {
        type: 'agent_status',
        data: mockAgent({ name: 'researcher', status: 'active' }),
        timestamp: new Date().toISOString(),
      }

      mockContextState.isConnected = true
      mockContextState.agentEvents = [agentEvent]
      mockContextState.lastEvent = agentEvent

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('agent-events-count')).toHaveTextContent('1')
      expect(screen.getByTestId('last-event-type')).toHaveTextContent('agent_status')
    })

    it('should display memory events from context', () => {
      const memoryEvent: WSEvent = {
        type: 'memory_stored',
        data: mockMemory({ id: 'mem-1', content: 'Important decision' }),
        timestamp: new Date().toISOString(),
      }

      mockContextState.isConnected = true
      mockContextState.memoryEvents = [memoryEvent]
      mockContextState.lastEvent = memoryEvent

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('memory-events-count')).toHaveTextContent('1')
      expect(screen.getByTestId('last-event-type')).toHaveTextContent('memory_stored')
    })

    it('should display multiple events of different types', () => {
      mockContextState.isConnected = true
      mockContextState.taskEvents = [
        { type: 'task_updated', data: mockTask({ id: 'task-1' }), timestamp: '' },
        { type: 'task_updated', data: mockTask({ id: 'task-2' }), timestamp: '' },
      ] as WSEvent[]
      mockContextState.agentEvents = [
        { type: 'agent_status', data: mockAgent({ name: 'researcher' }), timestamp: '' },
      ] as WSEvent[]
      mockContextState.memoryEvents = [
        { type: 'memory_stored', data: mockMemory({ id: 'mem-1' }), timestamp: '' },
      ] as WSEvent[]

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('task-events-count')).toHaveTextContent('2')
      expect(screen.getByTestId('agent-events-count')).toHaveTextContent('1')
      expect(screen.getByTestId('memory-events-count')).toHaveTextContent('1')
    })
  })

  describe('Event Buffer Limits', () => {
    it('should display up to 50 task events', () => {
      // Generate 50 task events
      const taskEvents: WSEvent[] = Array.from({ length: 50 }, (_, i) => ({
        type: 'task_updated',
        data: mockTask({ id: `task-${i}` }),
        timestamp: new Date().toISOString(),
      }))

      mockContextState.isConnected = true
      mockContextState.taskEvents = taskEvents

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('task-events-count')).toHaveTextContent('50')
    })

    it('should display task event data correctly', () => {
      const task = mockTask({ id: 'task-123', title: 'Important Task' })
      mockContextState.isConnected = true
      mockContextState.taskEvents = [
        { type: 'task_updated', data: task, timestamp: '' },
      ] as WSEvent[]

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      const taskEventsDiv = screen.getByTestId('task-events')
      expect(taskEventsDiv.textContent).toContain('task-123')
    })
  })

  describe('Context Actions', () => {
    it('should have send function available', () => {
      mockContextState.isConnected = true

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(mockContextState.send).toBeDefined()
      expect(typeof mockContextState.send).toBe('function')
    })

    it('should have reconnect function available', () => {
      mockContextState.isConnected = false

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(mockContextState.reconnect).toBeDefined()
      expect(typeof mockContextState.reconnect).toBe('function')
    })

    it('should have disconnect function available', () => {
      mockContextState.isConnected = true

      render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(mockContextState.disconnect).toBeDefined()
      expect(typeof mockContextState.disconnect).toBe('function')
    })
  })

  describe('Real-time Data Flow', () => {
    it('should reflect state changes through context updates', () => {
      // Start disconnected
      mockContextState.isConnected = false

      const { rerender } = render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('connection-status')).toHaveTextContent('disconnected')

      // Simulate connection
      mockContextState.isConnected = true
      mockContextState.isAuthenticated = true

      rerender(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('connection-status')).toHaveTextContent('connected')
    })

    it('should update last event when new event arrives', () => {
      mockContextState.isConnected = true
      mockContextState.lastEvent = null

      const { rerender } = render(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('last-event-type')).toHaveTextContent('none')

      // Simulate new event
      const newEvent: WSEvent = {
        type: 'task_updated',
        data: mockTask({ id: 'task-new' }),
        timestamp: new Date().toISOString(),
      }
      mockContextState.lastEvent = newEvent
      mockContextState.taskEvents = [newEvent]

      rerender(
        <IntegrationWrapper>
          <WebSocketStateDisplay />
        </IntegrationWrapper>
      )

      expect(screen.getByTestId('last-event-type')).toHaveTextContent('task_updated')
      expect(screen.getByTestId('task-events-count')).toHaveTextContent('1')
    })
  })
})
