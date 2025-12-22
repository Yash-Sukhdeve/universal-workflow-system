import axios, { AxiosError } from 'axios'
import { z } from 'zod'
import toast from 'react-hot-toast'
import type { AuthResponse, User, Task, CreateTaskInput, Agent, Memory, MemoryContext, PaginatedResponse } from '@/types'

const API_BASE_URL = import.meta.env.VITE_API_URL || '/api'

// =============================================================================
// Zod Schemas for Runtime Validation
// =============================================================================

const UserSchema = z.object({
  id: z.string(),
  email: z.string().email(),
  role: z.enum(['admin', 'developer', 'viewer']),
  organization_id: z.string(),
})

const AuthResponseSchema = z.object({
  access_token: z.string(),
  token_type: z.string(),
  user: UserSchema,
})

const TaskSchema = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string(),
  status: z.enum(['pending', 'in_progress', 'completed', 'blocked']),
  priority: z.enum(['low', 'medium', 'high', 'critical']),
  assigned_to: z.string().optional().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
  project_id: z.string().optional().nullable(),
})

const AgentSchema = z.object({
  name: z.string(),
  status: z.enum(['active', 'inactive']),
  capabilities: z.array(z.string()),
  current_task: z.string().optional().nullable(),
  activated_at: z.string().optional().nullable(),
})

const MemorySchema = z.object({
  id: z.string(),
  content: z.string(),
  type: z.enum(['decision', 'discovery', 'learning', 'context']),
  relevance_score: z.number(),
  created_at: z.string(),
  metadata: z.record(z.string(), z.unknown()).optional().nullable(),
})

const PaginatedResponseSchema = <T extends z.ZodTypeAny>(itemSchema: T) =>
  z.object({
    items: z.array(itemSchema),
    total: z.number(),
    page: z.number(),
    per_page: z.number(),
  })

const MemoryContextSchema = z.object({
  recent_memories: z.array(MemorySchema),
  similar_tasks: z.array(TaskSchema),
  decisions: z.array(MemorySchema),
})

// =============================================================================
// Error Handling Utilities
// =============================================================================

interface ApiErrorDetails {
  message: string
  status?: number
  code?: string
}

/**
 * Extract meaningful error message from API error
 */
export function handleApiError(error: unknown): ApiErrorDetails {
  if (axios.isAxiosError(error)) {
    const axiosError = error as AxiosError<{ detail?: string; message?: string }>
    return {
      message: axiosError.response?.data?.detail
        || axiosError.response?.data?.message
        || axiosError.message
        || 'An error occurred',
      status: axiosError.response?.status,
      code: axiosError.code,
    }
  }
  if (error instanceof z.ZodError) {
    return {
      message: 'Invalid response from server',
      code: 'VALIDATION_ERROR',
    }
  }
  if (error instanceof Error) {
    return { message: error.message }
  }
  return { message: 'An unknown error occurred' }
}

/**
 * Wrapper for API calls with toast notifications
 */
async function apiCall<T>(
  operation: () => Promise<T>,
  options?: {
    successMessage?: string
    errorMessage?: string
    showSuccessToast?: boolean
    showErrorToast?: boolean
  }
): Promise<T> {
  const {
    successMessage,
    errorMessage,
    showSuccessToast = false,
    showErrorToast = true
  } = options || {}

  try {
    const result = await operation()
    if (showSuccessToast && successMessage) {
      toast.success(successMessage)
    }
    return result
  } catch (error) {
    const apiError = handleApiError(error)
    if (showErrorToast) {
      toast.error(errorMessage || apiError.message)
    }
    throw error
  }
}

// =============================================================================
// Axios Instance Configuration
// =============================================================================

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
  timeout: 30000, // 30 second timeout
})

// Add auth token and CSRF protection to requests
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }

  // CSRF Protection: Add token for state-changing methods
  if (['post', 'put', 'delete', 'patch'].includes(config.method?.toLowerCase() || '')) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    if (csrfToken) {
      config.headers['X-CSRF-Token'] = csrfToken
    }
    // Also add custom header that proves request came from our app
    config.headers['X-Requested-With'] = 'XMLHttpRequest'
  }

  return config
})

// Handle auth errors
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token')
      localStorage.removeItem('user')
      toast.error('Session expired. Please log in again.')
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

// =============================================================================
// Auth API
// =============================================================================

export const authApi = {
  login: async (email: string, password: string): Promise<AuthResponse> => {
    return apiCall(async () => {
      const formData = new URLSearchParams()
      formData.append('username', email)
      formData.append('password', password)
      const { data } = await api.post('/auth/login', formData, {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      })
      return AuthResponseSchema.parse(data)
    }, { showErrorToast: false }) // Handle login errors in component
  },

  register: async (email: string, password: string, organizationId?: string): Promise<User> => {
    return apiCall(async () => {
      const { data } = await api.post('/auth/register', {
        email,
        password,
        organization_id: organizationId,
      })
      return UserSchema.parse(data)
    }, { showErrorToast: false }) // Handle register errors in component
  },

  me: async (): Promise<User> => {
    const { data } = await api.get('/auth/me')
    return UserSchema.parse(data)
  },
}

// =============================================================================
// Tasks API
// =============================================================================

export const tasksApi = {
  list: async (page = 1, perPage = 20): Promise<PaginatedResponse<Task>> => {
    const { data } = await api.get('/tasks', { params: { page, per_page: perPage } })
    return PaginatedResponseSchema(TaskSchema).parse(data)
  },

  get: async (id: string): Promise<Task> => {
    const { data } = await api.get(`/tasks/${id}`)
    return TaskSchema.parse(data)
  },

  create: async (task: CreateTaskInput): Promise<Task> => {
    return apiCall(async () => {
      const { data } = await api.post('/tasks', task)
      return TaskSchema.parse(data)
    }, {
      successMessage: 'Task created successfully',
      showSuccessToast: true,
    })
  },

  update: async (id: string, updates: Partial<Task>): Promise<Task> => {
    return apiCall(async () => {
      const { data } = await api.put(`/tasks/${id}`, updates)
      return TaskSchema.parse(data)
    }, {
      successMessage: 'Task updated successfully',
      showSuccessToast: true,
    })
  },

  delete: async (id: string): Promise<void> => {
    return apiCall(async () => {
      await api.delete(`/tasks/${id}`)
    }, {
      successMessage: 'Task deleted successfully',
      showSuccessToast: true,
    })
  },

  assign: async (id: string, userId: string): Promise<Task> => {
    return apiCall(async () => {
      const { data } = await api.post(`/tasks/${id}/assign`, { user_id: userId })
      return TaskSchema.parse(data)
    }, {
      successMessage: 'Task assigned successfully',
      showSuccessToast: true,
    })
  },

  complete: async (id: string): Promise<Task> => {
    return apiCall(async () => {
      const { data } = await api.post(`/tasks/${id}/complete`)
      return TaskSchema.parse(data)
    }, {
      successMessage: 'Task completed!',
      showSuccessToast: true,
    })
  },
}

// =============================================================================
// Agents API
// =============================================================================

export const agentsApi = {
  list: async (): Promise<Agent[]> => {
    const { data } = await api.get('/agents')
    return z.array(AgentSchema).parse(data)
  },

  activate: async (name: string, task?: string): Promise<Agent> => {
    return apiCall(async () => {
      const { data } = await api.post(`/agents/${name}/activate`, { task })
      return AgentSchema.parse(data)
    }, {
      successMessage: `Agent ${name} activated`,
      showSuccessToast: true,
    })
  },

  deactivate: async (name: string): Promise<Agent> => {
    return apiCall(async () => {
      const { data } = await api.post(`/agents/${name}/deactivate`)
      return AgentSchema.parse(data)
    }, {
      successMessage: `Agent ${name} deactivated`,
      showSuccessToast: true,
    })
  },

  status: async (): Promise<{ active_agent: Agent | null; available_agents: string[] }> => {
    const { data } = await api.get('/agents/status')
    return z.object({
      active_agent: AgentSchema.nullable(),
      available_agents: z.array(z.string()),
    }).parse(data)
  },
}

// =============================================================================
// Memory API
// =============================================================================

export const memoryApi = {
  store: async (content: string, type: Memory['type'], metadata?: Record<string, unknown>): Promise<Memory> => {
    return apiCall(async () => {
      const { data } = await api.post('/memory/store', { content, type, metadata })
      return MemorySchema.parse(data)
    }, {
      successMessage: 'Memory stored',
      showSuccessToast: true,
    })
  },

  search: async (query: string, limit = 10): Promise<Memory[]> => {
    const { data } = await api.get('/memory/search', { params: { query, limit } })
    return z.array(MemorySchema).parse(data)
  },

  context: async (taskId?: string): Promise<MemoryContext> => {
    const { data } = await api.get('/memory/context', { params: { task_id: taskId } })
    return MemoryContextSchema.parse(data)
  },

  similarTasks: async (description: string): Promise<Task[]> => {
    const { data } = await api.get('/memory/similar-tasks', { params: { description } })
    return z.array(TaskSchema).parse(data)
  },
}

export default api
