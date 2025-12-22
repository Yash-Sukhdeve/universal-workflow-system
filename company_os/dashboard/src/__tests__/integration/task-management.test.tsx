import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider } from '@/contexts/AuthContext'
import { WebSocketProvider } from '@/contexts/WebSocketContext'
import { TasksPage } from '@/pages/TasksPage'
import { tasksApi, authApi } from '@/services/api'
import { mockTask, mockUser, mockAuthResponse } from '@/test/utils'
import type { Task, PaginatedResponse, WSEvent } from '@/types'

// Mock the APIs
vi.mock('@/services/api', () => ({
  tasksApi: {
    list: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    complete: vi.fn(),
  },
  authApi: {
    me: vi.fn(),
    login: vi.fn(),
  },
}))

// Mock WebSocket hook to control events
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

const mockTasksApi = vi.mocked(tasksApi)
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
      <MemoryRouter initialEntries={['/tasks']}>
        <AuthProvider>{children}</AuthProvider>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('Task Management Integration', () => {
  const testUser = mockUser()

  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()

    // Setup authenticated state
    localStorage.setItem('token', 'test-token')
    localStorage.setItem('user', JSON.stringify(testUser))
    mockAuthApi.me.mockResolvedValue(testUser)

    // Reset WebSocket state
    mockWebSocketState.taskEvents = []
    mockWebSocketState.isConnected = true
  })

  afterEach(() => {
    localStorage.clear()
  })

  describe('Task List Display', () => {
    it('should load and display tasks from API', async () => {
      const tasks = [
        mockTask({ id: 'task-1', title: 'First Task', status: 'pending' }),
        mockTask({ id: 'task-2', title: 'Second Task', status: 'in_progress' }),
        mockTask({ id: 'task-3', title: 'Third Task', status: 'completed' }),
      ]

      mockTasksApi.list.mockResolvedValue({
        items: tasks,
        total: 3,
        page: 1,
        per_page: 50,
      })

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      // Wait for tasks to load
      await waitFor(() => {
        expect(screen.getByText('First Task')).toBeInTheDocument()
      })

      expect(screen.getByText('Second Task')).toBeInTheDocument()
      expect(screen.getByText('Third Task')).toBeInTheDocument()
      expect(mockTasksApi.list).toHaveBeenCalledWith(1, 50)
    })

    it('should display empty state when no tasks', async () => {
      mockTasksApi.list.mockResolvedValue({
        items: [],
        total: 0,
        page: 1,
        per_page: 50,
      })

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText(/no tasks found/i)).toBeInTheDocument()
      })
    })

    it('should filter tasks by search query', async () => {
      const tasks = [
        mockTask({ id: 'task-1', title: 'Build feature' }),
        mockTask({ id: 'task-2', title: 'Fix bug' }),
        mockTask({ id: 'task-3', title: 'Build another feature' }),
      ]

      mockTasksApi.list.mockResolvedValue({
        items: tasks,
        total: 3,
        page: 1,
        per_page: 50,
      })

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('Build feature')).toBeInTheDocument()
      })

      // Search for "Build"
      await user.type(screen.getByPlaceholderText(/search tasks/i), 'Build')

      // Should only show tasks with "Build" in title
      expect(screen.getByText('Build feature')).toBeInTheDocument()
      expect(screen.getByText('Build another feature')).toBeInTheDocument()
      expect(screen.queryByText('Fix bug')).not.toBeInTheDocument()
    })

    it('should filter tasks by status', async () => {
      const tasks = [
        mockTask({ id: 'task-1', title: 'Pending Task', status: 'pending' }),
        mockTask({ id: 'task-2', title: 'In Progress Task', status: 'in_progress' }),
        mockTask({ id: 'task-3', title: 'Completed Task', status: 'completed' }),
      ]

      mockTasksApi.list.mockResolvedValue({
        items: tasks,
        total: 3,
        page: 1,
        per_page: 50,
      })

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('Pending Task')).toBeInTheDocument()
      })

      // Filter by "completed" status
      await user.selectOptions(screen.getByRole('combobox'), 'completed')

      // Should only show completed tasks
      expect(screen.getByText('Completed Task')).toBeInTheDocument()
      expect(screen.queryByText('Pending Task')).not.toBeInTheDocument()
      expect(screen.queryByText('In Progress Task')).not.toBeInTheDocument()
    })
  })

  describe('Task Creation', () => {
    it('should create a new task through the modal', async () => {
      const existingTasks = [mockTask({ id: 'task-1', title: 'Existing Task' })]
      const newTask = mockTask({ id: 'task-new', title: 'New Task', description: 'Task description', priority: 'high' })

      mockTasksApi.list
        .mockResolvedValueOnce({
          items: existingTasks,
          total: 1,
          page: 1,
          per_page: 50,
        })
        .mockResolvedValue({
          items: [...existingTasks, newTask],
          total: 2,
          page: 1,
          per_page: 50,
        })
      mockTasksApi.create.mockResolvedValue(newTask)

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByText('Existing Task')).toBeInTheDocument()
      })

      // Open create modal
      await user.click(screen.getByRole('button', { name: /new task/i }))

      // Wait for modal to appear
      await waitFor(() => {
        expect(screen.getByRole('heading', { name: /create new task/i })).toBeInTheDocument()
      })

      // Fill in the form - find modal inputs by their position in the DOM
      // The modal has: Title (input type=text), Description (textarea), Priority (select)
      const modal = screen.getByRole('heading', { name: /create new task/i }).closest('.fixed')!
      const titleInput = modal.querySelector('input[type="text"]')!
      const descriptionTextarea = modal.querySelector('textarea')!

      await user.type(titleInput, 'New Task')
      await user.type(descriptionTextarea, 'Task description')

      // Select priority - the select inside the modal
      const prioritySelect = within(modal).getByRole('combobox')
      await user.selectOptions(prioritySelect, 'high')

      // Submit
      await user.click(screen.getByRole('button', { name: /create task/i }))

      // Verify API was called with correct data
      await waitFor(() => {
        expect(mockTasksApi.create).toHaveBeenCalledWith({
          title: 'New Task',
          description: 'Task description',
          priority: 'high',
        })
      })

      // Modal should close after successful creation
      await waitFor(() => {
        expect(screen.queryByRole('heading', { name: /create new task/i })).not.toBeInTheDocument()
      })
    })

    it('should close modal after successful creation', async () => {
      const newTask = mockTask({ id: 'task-new', title: 'New Task' })

      mockTasksApi.list.mockResolvedValue({ items: [], total: 0, page: 1, per_page: 50 })
      mockTasksApi.create.mockResolvedValue(newTask)

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /new task/i })).toBeInTheDocument()
      })

      // Open modal
      await user.click(screen.getByRole('button', { name: /new task/i }))

      await waitFor(() => {
        expect(screen.getByRole('heading', { name: /create new task/i })).toBeInTheDocument()
      })

      // Fill and submit - find elements within modal
      const modal = screen.getByRole('heading', { name: /create new task/i }).closest('.fixed')!
      const titleInput = modal.querySelector('input[type="text"]')!
      const descriptionTextarea = modal.querySelector('textarea')!

      await user.type(titleInput, 'New Task')
      await user.type(descriptionTextarea, 'Description')
      await user.click(screen.getByRole('button', { name: /create task/i }))

      // Modal should close
      await waitFor(() => {
        expect(screen.queryByRole('heading', { name: /create new task/i })).not.toBeInTheDocument()
      })
    })

    it('should cancel task creation', async () => {
      mockTasksApi.list.mockResolvedValue({ items: [], total: 0, page: 1, per_page: 50 })

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /new task/i })).toBeInTheDocument()
      })

      // Open modal
      await user.click(screen.getByRole('button', { name: /new task/i }))

      // Cancel
      await user.click(screen.getByRole('button', { name: /cancel/i }))

      // Modal should close without API call
      await waitFor(() => {
        expect(screen.queryByRole('heading', { name: /create new task/i })).not.toBeInTheDocument()
      })
      expect(mockTasksApi.create).not.toHaveBeenCalled()
    })
  })

  describe('Task Completion', () => {
    it('should complete a task when clicking status icon', async () => {
      const task = mockTask({ id: 'task-1', title: 'Task to Complete', status: 'pending' })
      const completedTask = { ...task, status: 'completed' as const }

      mockTasksApi.list.mockResolvedValue({
        items: [task],
        total: 1,
        page: 1,
        per_page: 50,
      })
      mockTasksApi.complete.mockResolvedValue(completedTask)

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('Task to Complete')).toBeInTheDocument()
      })

      // Find and click the status button (first button in the row)
      const row = screen.getByText('Task to Complete').closest('tr')!
      const statusButton = within(row).getAllByRole('button')[0]
      await user.click(statusButton)

      // Verify API was called
      await waitFor(() => {
        expect(mockTasksApi.complete).toHaveBeenCalledWith('task-1')
      })
    })

    it('should not allow completing an already completed task', async () => {
      const completedTask = mockTask({ id: 'task-1', title: 'Completed Task', status: 'completed' })

      mockTasksApi.list.mockResolvedValue({
        items: [completedTask],
        total: 1,
        page: 1,
        per_page: 50,
      })

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText('Completed Task')).toBeInTheDocument()
      })

      // Find status button - should be disabled
      const row = screen.getByText('Completed Task').closest('tr')!
      const statusButton = within(row).getAllByRole('button')[0]
      expect(statusButton).toBeDisabled()
    })
  })

  describe('Real-time Updates', () => {
    it('should show connection status indicator', async () => {
      mockWebSocketState.isConnected = true
      mockTasksApi.list.mockResolvedValue({ items: [], total: 0, page: 1, per_page: 50 })

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByText(/live/i)).toBeInTheDocument()
      })
    })

    it('should reload tasks when WebSocket events are received', async () => {
      const initialTasks = [mockTask({ id: 'task-1', title: 'Initial Task' })]
      const updatedTasks = [
        mockTask({ id: 'task-1', title: 'Initial Task' }),
        mockTask({ id: 'task-2', title: 'New Task from WebSocket' }),
      ]

      mockTasksApi.list
        .mockResolvedValueOnce({ items: initialTasks, total: 1, page: 1, per_page: 50 })
        .mockResolvedValueOnce({ items: updatedTasks, total: 2, page: 1, per_page: 50 })

      const { rerender } = render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByText('Initial Task')).toBeInTheDocument()
      })

      // Simulate WebSocket event by updating the mock state
      mockWebSocketState.taskEvents = [{ type: 'task_updated', data: { id: 'task-2' } }] as WSEvent[]

      // Trigger re-render to pick up new events
      rerender(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      // Tasks should be reloaded
      await waitFor(() => {
        expect(mockTasksApi.list).toHaveBeenCalledTimes(2)
      })
    })
  })

  describe('Error Handling', () => {
    it('should handle API errors gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
      mockTasksApi.list.mockRejectedValue(new Error('API Error'))

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      // Should not crash and should eventually show empty state
      await waitFor(() => {
        expect(screen.getByText(/no tasks found/i)).toBeInTheDocument()
      })

      consoleSpy.mockRestore()
    })

    it('should handle task creation errors', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
      mockTasksApi.list.mockResolvedValue({ items: [], total: 0, page: 1, per_page: 50 })
      mockTasksApi.create.mockRejectedValue(new Error('Failed to create task'))

      const user = userEvent.setup()

      render(
        <IntegrationWrapper>
          <TasksPage />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /new task/i })).toBeInTheDocument()
      })

      // Open modal and submit
      await user.click(screen.getByRole('button', { name: /new task/i }))

      await waitFor(() => {
        expect(screen.getByRole('heading', { name: /create new task/i })).toBeInTheDocument()
      })

      // Fill and submit - find elements within modal
      const modal = screen.getByRole('heading', { name: /create new task/i }).closest('.fixed')!
      const titleInput = modal.querySelector('input[type="text"]')!
      const descriptionTextarea = modal.querySelector('textarea')!

      await user.type(titleInput, 'New Task')
      await user.type(descriptionTextarea, 'Description')
      await user.click(screen.getByRole('button', { name: /create task/i }))

      // Verify API was called
      await waitFor(() => {
        expect(mockTasksApi.create).toHaveBeenCalled()
      })

      // Error is caught, modal may close or stay open depending on implementation
      // The important thing is that the app doesn't crash

      consoleSpy.mockRestore()
    })
  })
})
