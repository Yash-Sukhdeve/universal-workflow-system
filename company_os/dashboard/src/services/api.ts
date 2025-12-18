import axios from 'axios'
import type { AuthResponse, User, Task, CreateTaskInput, Agent, Memory, MemoryContext, PaginatedResponse } from '@/types'

const API_BASE_URL = import.meta.env.VITE_API_URL || '/api'

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Add auth token to requests
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
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
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

// Auth API
export const authApi = {
  login: async (email: string, password: string): Promise<AuthResponse> => {
    const formData = new URLSearchParams()
    formData.append('username', email)
    formData.append('password', password)
    const { data } = await api.post('/auth/login', formData, {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    })
    return data
  },

  register: async (email: string, password: string, organizationId?: string): Promise<User> => {
    const { data } = await api.post('/auth/register', {
      email,
      password,
      organization_id: organizationId,
    })
    return data
  },

  me: async (): Promise<User> => {
    const { data } = await api.get('/auth/me')
    return data
  },
}

// Tasks API
export const tasksApi = {
  list: async (page = 1, perPage = 20): Promise<PaginatedResponse<Task>> => {
    const { data } = await api.get('/tasks', { params: { page, per_page: perPage } })
    return data
  },

  get: async (id: string): Promise<Task> => {
    const { data } = await api.get(`/tasks/${id}`)
    return data
  },

  create: async (task: CreateTaskInput): Promise<Task> => {
    const { data } = await api.post('/tasks', task)
    return data
  },

  update: async (id: string, updates: Partial<Task>): Promise<Task> => {
    const { data } = await api.put(`/tasks/${id}`, updates)
    return data
  },

  delete: async (id: string): Promise<void> => {
    await api.delete(`/tasks/${id}`)
  },

  assign: async (id: string, userId: string): Promise<Task> => {
    const { data } = await api.post(`/tasks/${id}/assign`, { user_id: userId })
    return data
  },

  complete: async (id: string): Promise<Task> => {
    const { data } = await api.post(`/tasks/${id}/complete`)
    return data
  },
}

// Agents API
export const agentsApi = {
  list: async (): Promise<Agent[]> => {
    const { data } = await api.get('/agents')
    return data
  },

  activate: async (name: string, task?: string): Promise<Agent> => {
    const { data } = await api.post(`/agents/${name}/activate`, { task })
    return data
  },

  deactivate: async (name: string): Promise<Agent> => {
    const { data } = await api.post(`/agents/${name}/deactivate`)
    return data
  },

  status: async (): Promise<{ active_agent: Agent | null; available_agents: string[] }> => {
    const { data } = await api.get('/agents/status')
    return data
  },
}

// Memory API
export const memoryApi = {
  store: async (content: string, type: Memory['type'], metadata?: Record<string, unknown>): Promise<Memory> => {
    const { data } = await api.post('/memory/store', { content, type, metadata })
    return data
  },

  search: async (query: string, limit = 10): Promise<Memory[]> => {
    const { data } = await api.get('/memory/search', { params: { query, limit } })
    return data
  },

  context: async (taskId?: string): Promise<MemoryContext> => {
    const { data } = await api.get('/memory/context', { params: { task_id: taskId } })
    return data
  },

  similarTasks: async (description: string): Promise<Task[]> => {
    const { data } = await api.get('/memory/similar-tasks', { params: { description } })
    return data
  },
}

export default api
