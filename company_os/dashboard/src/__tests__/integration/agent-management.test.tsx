import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider } from '@/contexts/AuthContext'
import { AgentsPage } from '@/pages/AgentsPage'
import { agentsApi, authApi } from '@/services/api'
import { mockAgent, mockUser } from '@/test/utils'
import type { Agent, WSEvent } from '@/types'

// Mock the APIs
vi.mock('@/services/api', () => ({
  agentsApi: {
    list: vi.fn(),
    activate: vi.fn(),
    deactivate: vi.fn(),
    status: vi.fn(),
  },
  authApi: {
    me: vi.fn(),
  },
}))

// Mock WebSocket context
const mockWebSocketState = {
  isConnected: true,
  isAuthenticated: true,
  taskEvents: [] as WSEvent[],
  agentEvents: [] as WSEvent[],
  memoryEvents: [] as WSEvent[],
  lastEvent: null as WSEvent | null,
}

vi.mock('@/contexts/WebSocketContext', () => ({
  WebSocketProvider: ({ children }: { children: React.ReactNode }) => children,
  useWebSocketContext: () => mockWebSocketState,
}))

const mockAgentsApi = vi.mocked(agentsApi)
const mockAuthApi = vi.mocked(authApi)

const createTestQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: { retry: false },
      mutations: { retry: false },
    },
  })

function IntegrationWrapper({ children }: { children: React.ReactNode }) {
  const queryClient = createTestQueryClient()
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={['/agents']}>
        <AuthProvider>{children}</AuthProvider>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('Agent Management Integration', () => {
  const testUser = mockUser()

  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()

    // Setup authenticated state
    localStorage.setItem('token', 'test-token')
    localStorage.setItem('user', JSON.stringify(testUser))
    mockAuthApi.me.mockResolvedValue(testUser)

    // Reset WebSocket state
    mockWebSocketState.agentEvents = []
    mockWebSocketState.isConnected = true
  })

  afterEach(() => {
    localStorage.clear()
  })

  describe('Agent List Display', () => {
    it('should load and display agents from API', async () => {
      const agents = [
        mockAgent({ name: 'researcher', status: 'inactive', capabilities: ['research', 'analysis'] }),
        mockAgent({ name: 'architect', status: 'active', capabilities: ['design', 'planning'] }),
        mockAgent({ name: 'implementer', status: 'inactive', capabilities: ['coding', 'testing'] }),
      ]

      mockAgentsApi.list.mockResolvedValue(agents)

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      // Wait for agents to load
      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      expect(screen.getByText('architect')).toBeInTheDocument()
      expect(screen.getByText('implementer')).toBeInTheDocument()
      expect(mockAgentsApi.list).toHaveBeenCalled()
    })

    it('should display empty state when no agents', async () => {
      mockAgentsApi.list.mockResolvedValue([])

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText(/no agents configured/i)).toBeInTheDocument()
      })
    })

    it('should show agent status badges correctly', async () => {
      const agents = [
        mockAgent({ name: 'researcher', status: 'inactive' }),
        mockAgent({ name: 'architect', status: 'active' }),
      ]

      mockAgentsApi.list.mockResolvedValue(agents)

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      // Check status badges
      const inactiveBadges = screen.getAllByText('Inactive')
      const activeBadges = screen.getAllByText('Active')

      expect(inactiveBadges.length).toBeGreaterThanOrEqual(1)
      expect(activeBadges.length).toBeGreaterThanOrEqual(1)
    })

    it('should display agent capabilities', async () => {
      const agent = mockAgent({
        name: 'researcher',
        status: 'active',
        capabilities: ['research', 'analysis', 'data_collection', 'literature_review'],
      })

      mockAgentsApi.list.mockResolvedValue([agent])

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      // Check capabilities are displayed
      expect(screen.getByText('research')).toBeInTheDocument()
      expect(screen.getByText('analysis')).toBeInTheDocument()
    })

    it('should truncate many capabilities with +N indicator', async () => {
      const agent = mockAgent({
        name: 'researcher',
        status: 'active',
        capabilities: ['cap1', 'cap2', 'cap3', 'cap4', 'cap5', 'cap6'],
      })

      mockAgentsApi.list.mockResolvedValue([agent])

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      // Should show +2 for remaining capabilities
      expect(screen.getByText('+2')).toBeInTheDocument()
    })
  })

  describe('Agent Activation', () => {
    it('should activate an inactive agent', async () => {
      const inactiveAgent = mockAgent({ name: 'researcher', status: 'inactive' })
      const activatedAgent = { ...inactiveAgent, status: 'active' as const }

      mockAgentsApi.list
        .mockResolvedValueOnce([inactiveAgent])
        .mockResolvedValueOnce([activatedAgent])
      mockAgentsApi.activate.mockResolvedValue(activatedAgent)

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      // Find and click the Activate button
      const activateButton = screen.getByRole('button', { name: /activate/i })
      await user.click(activateButton)

      // Verify API was called
      await waitFor(() => {
        expect(mockAgentsApi.activate).toHaveBeenCalledWith('researcher')
      })

      // Verify list was refreshed
      expect(mockAgentsApi.list).toHaveBeenCalledTimes(2)
    })

    it('should show loading state during activation', async () => {
      const inactiveAgent = mockAgent({ name: 'researcher', status: 'inactive' })

      mockAgentsApi.list.mockResolvedValue([inactiveAgent])
      mockAgentsApi.activate.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({ ...inactiveAgent, status: 'active' }), 100))
      )

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /activate/i })).toBeInTheDocument()
      })

      await user.click(screen.getByRole('button', { name: /activate/i }))

      // Should show loading text
      expect(screen.getByText(/activating/i)).toBeInTheDocument()
    })
  })

  describe('Agent Deactivation', () => {
    it('should deactivate an active agent', async () => {
      const activeAgent = mockAgent({ name: 'researcher', status: 'active' })
      const deactivatedAgent = { ...activeAgent, status: 'inactive' as const }

      mockAgentsApi.list
        .mockResolvedValueOnce([activeAgent])
        .mockResolvedValueOnce([deactivatedAgent])
      mockAgentsApi.deactivate.mockResolvedValue(deactivatedAgent)

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      // Find and click the Deactivate button
      const deactivateButton = screen.getByRole('button', { name: /deactivate/i })
      await user.click(deactivateButton)

      // Verify API was called
      await waitFor(() => {
        expect(mockAgentsApi.deactivate).toHaveBeenCalledWith('researcher')
      })
    })

    it('should show loading state during deactivation', async () => {
      const activeAgent = mockAgent({ name: 'researcher', status: 'active' })

      mockAgentsApi.list.mockResolvedValue([activeAgent])
      mockAgentsApi.deactivate.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({ ...activeAgent, status: 'inactive' }), 100))
      )

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /deactivate/i })).toBeInTheDocument()
      })

      await user.click(screen.getByRole('button', { name: /deactivate/i }))

      // Should show loading text
      expect(screen.getByText(/deactivating/i)).toBeInTheDocument()
    })
  })

  describe('Real-time Updates', () => {
    it('should show live updates indicator when connected', async () => {
      mockWebSocketState.isConnected = true
      mockAgentsApi.list.mockResolvedValue([])

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText(/live updates/i)).toBeInTheDocument()
      })
    })

    it('should receive WebSocket events in context', async () => {
      const agents = [mockAgent({ name: 'researcher', status: 'inactive' })]

      mockAgentsApi.list.mockResolvedValue(agents)

      const { rerender } = render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      // Verify initial API call
      expect(mockAgentsApi.list).toHaveBeenCalled()

      // Simulate WebSocket event arriving
      mockWebSocketState.agentEvents = [
        { type: 'agent_status', data: { name: 'researcher', status: 'active' } },
      ] as WSEvent[]

      // Trigger re-render to pick up new event state
      rerender(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      // Component should still render (WebSocket events received by context)
      expect(screen.getByText('researcher')).toBeInTheDocument()
    })
  })

  describe('Current Task Display', () => {
    it('should show current task when agent is working', async () => {
      const agent = mockAgent({
        name: 'researcher',
        status: 'active',
        current_task: 'Analyzing codebase architecture',
      })

      mockAgentsApi.list.mockResolvedValue([agent])

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      expect(screen.getByText('Analyzing codebase architecture')).toBeInTheDocument()
    })

    it('should not show task section when no current task', async () => {
      const agent = mockAgent({
        name: 'researcher',
        status: 'inactive',
        current_task: null,
      })

      mockAgentsApi.list.mockResolvedValue([agent])

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('researcher')).toBeInTheDocument()
      })

      // No task should be displayed
      const card = screen.getByText('researcher').closest('.card')
      expect(within(card!).queryByRole('article')).not.toBeInTheDocument()
    })
  })

  describe('Error Handling', () => {
    it('should handle API errors gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
      mockAgentsApi.list.mockRejectedValue(new Error('API Error'))

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      // Should show empty state
      await waitFor(() => {
        expect(screen.getByText(/no agents configured/i)).toBeInTheDocument()
      })

      consoleSpy.mockRestore()
    })

    it('should handle activation errors', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
      const agent = mockAgent({ name: 'researcher', status: 'inactive' })

      mockAgentsApi.list.mockResolvedValue([agent])
      mockAgentsApi.activate.mockRejectedValue(new Error('Activation failed'))

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /activate/i })).toBeInTheDocument()
      })

      await user.click(screen.getByRole('button', { name: /activate/i }))

      // Should log error
      await waitFor(() => {
        expect(consoleSpy).toHaveBeenCalled()
      })

      consoleSpy.mockRestore()
    })

    it('should handle deactivation errors', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
      const agent = mockAgent({ name: 'researcher', status: 'active' })

      mockAgentsApi.list.mockResolvedValue([agent])
      mockAgentsApi.deactivate.mockRejectedValue(new Error('Deactivation failed'))

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /deactivate/i })).toBeInTheDocument()
      })

      await user.click(screen.getByRole('button', { name: /deactivate/i }))

      // Should log error
      await waitFor(() => {
        expect(consoleSpy).toHaveBeenCalled()
      })

      consoleSpy.mockRestore()
    })
  })

  describe('Multiple Agents Interaction', () => {
    it('should only allow one agent to be activated at a time', async () => {
      const agents = [
        mockAgent({ name: 'researcher', status: 'inactive' }),
        mockAgent({ name: 'architect', status: 'inactive' }),
      ]

      mockAgentsApi.list.mockResolvedValue(agents)
      mockAgentsApi.activate.mockImplementation(
        (name) => new Promise((resolve) => setTimeout(() => resolve(mockAgent({ name, status: 'active' })), 100))
      )

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <AgentsPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getAllByRole('button', { name: /activate/i })).toHaveLength(2)
      })

      // Click first activate button
      const activateButtons = screen.getAllByRole('button', { name: /activate/i })
      await user.click(activateButtons[0])

      // First button should show loading
      expect(screen.getByText(/activating/i)).toBeInTheDocument()
    })
  })
})
