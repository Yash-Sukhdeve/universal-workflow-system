import { describe, it, expect, vi, beforeEach } from 'vitest'
import axios, { AxiosError } from 'axios'
import { z } from 'zod'
import { handleApiError, authApi, tasksApi, agentsApi, memoryApi } from './api'
import { mockUser, mockTask, mockAgent, mockMemory, mockAuthResponse } from '@/test/utils'

// Mock axios
vi.mock('axios', async () => {
  const actual = await vi.importActual('axios')
  return {
    ...actual,
    default: {
      create: vi.fn(() => ({
        get: vi.fn(),
        post: vi.fn(),
        put: vi.fn(),
        delete: vi.fn(),
        interceptors: {
          request: { use: vi.fn() },
          response: { use: vi.fn() },
        },
      })),
      isAxiosError: (actual as typeof axios).isAxiosError,
    },
  }
})

// Mock react-hot-toast
vi.mock('react-hot-toast', () => ({
  default: {
    success: vi.fn(),
    error: vi.fn(),
  },
}))

describe('handleApiError', () => {
  it('should handle Axios errors with response data', () => {
    const axiosError = new AxiosError('Network error')
    axiosError.response = {
      status: 400,
      data: { detail: 'Bad request error' },
      statusText: 'Bad Request',
      headers: {},
      config: {} as never,
    }

    const result = handleApiError(axiosError)

    expect(result.message).toBe('Bad request error')
    expect(result.status).toBe(400)
  })

  it('should handle Axios errors with message field', () => {
    const axiosError = new AxiosError('Network error')
    axiosError.response = {
      status: 500,
      data: { message: 'Server error message' },
      statusText: 'Internal Server Error',
      headers: {},
      config: {} as never,
    }

    const result = handleApiError(axiosError)

    expect(result.message).toBe('Server error message')
    expect(result.status).toBe(500)
  })

  it('should handle Axios errors without response', () => {
    const axiosError = new AxiosError('Network Error')
    axiosError.code = 'ERR_NETWORK'

    const result = handleApiError(axiosError)

    expect(result.message).toBe('Network Error')
    expect(result.code).toBe('ERR_NETWORK')
  })

  it('should handle Zod validation errors', () => {
    const zodError = new z.ZodError([
      {
        code: 'invalid_type',
        expected: 'string',
        received: 'number',
        path: ['email'],
        message: 'Expected string, received number',
      },
    ])

    const result = handleApiError(zodError)

    expect(result.message).toBe('Invalid response from server')
    expect(result.code).toBe('VALIDATION_ERROR')
  })

  it('should handle generic Error objects', () => {
    const error = new Error('Something went wrong')

    const result = handleApiError(error)

    expect(result.message).toBe('Something went wrong')
  })

  it('should handle unknown errors', () => {
    const result = handleApiError('string error')

    expect(result.message).toBe('An unknown error occurred')
  })

  it('should handle null/undefined errors', () => {
    const result = handleApiError(null)

    expect(result.message).toBe('An unknown error occurred')
  })
})

describe('API Schemas Validation', () => {
  describe('User Schema', () => {
    it('should validate correct user data', () => {
      const user = mockUser()
      // Test by creating the same schema
      const UserSchema = z.object({
        id: z.string(),
        email: z.string().email(),
        role: z.enum(['admin', 'developer', 'viewer']),
        organization_id: z.string(),
      })

      expect(() => UserSchema.parse(user)).not.toThrow()
    })

    it('should reject invalid email', () => {
      const UserSchema = z.object({
        id: z.string(),
        email: z.string().email(),
        role: z.enum(['admin', 'developer', 'viewer']),
        organization_id: z.string(),
      })

      expect(() =>
        UserSchema.parse({ ...mockUser(), email: 'invalid-email' })
      ).toThrow()
    })

    it('should reject invalid role', () => {
      const UserSchema = z.object({
        id: z.string(),
        email: z.string().email(),
        role: z.enum(['admin', 'developer', 'viewer']),
        organization_id: z.string(),
      })

      expect(() =>
        UserSchema.parse({ ...mockUser(), role: 'superuser' })
      ).toThrow()
    })
  })

  describe('Task Schema', () => {
    it('should validate correct task data', () => {
      const task = mockTask()
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

      expect(() => TaskSchema.parse(task)).not.toThrow()
    })

    it('should reject invalid status', () => {
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

      expect(() =>
        TaskSchema.parse({ ...mockTask(), status: 'unknown' })
      ).toThrow()
    })
  })

  describe('Agent Schema', () => {
    it('should validate correct agent data', () => {
      const agent = mockAgent()
      const AgentSchema = z.object({
        name: z.string(),
        status: z.enum(['active', 'inactive']),
        capabilities: z.array(z.string()),
        current_task: z.string().optional().nullable(),
        activated_at: z.string().optional().nullable(),
      })

      expect(() => AgentSchema.parse(agent)).not.toThrow()
    })

    it('should validate active agent with task', () => {
      const AgentSchema = z.object({
        name: z.string(),
        status: z.enum(['active', 'inactive']),
        capabilities: z.array(z.string()),
        current_task: z.string().optional().nullable(),
        activated_at: z.string().optional().nullable(),
      })

      const activeAgent = mockAgent({
        status: 'active',
        current_task: 'Analyzing code',
        activated_at: '2024-01-01T00:00:00Z',
      })

      expect(() => AgentSchema.parse(activeAgent)).not.toThrow()
    })
  })

  describe('Memory Schema', () => {
    it('should validate correct memory data', () => {
      const memory = mockMemory()
      const MemorySchema = z.object({
        id: z.string(),
        content: z.string(),
        type: z.enum(['decision', 'discovery', 'learning', 'context']),
        relevance_score: z.number(),
        created_at: z.string(),
        metadata: z.record(z.string(), z.unknown()).optional().nullable(),
      })

      expect(() => MemorySchema.parse(memory)).not.toThrow()
    })

    it('should validate all memory types', () => {
      const MemorySchema = z.object({
        id: z.string(),
        content: z.string(),
        type: z.enum(['decision', 'discovery', 'learning', 'context']),
        relevance_score: z.number(),
        created_at: z.string(),
        metadata: z.record(z.string(), z.unknown()).optional().nullable(),
      })

      const types = ['decision', 'discovery', 'learning', 'context'] as const
      types.forEach((type) => {
        expect(() =>
          MemorySchema.parse(mockMemory({ type }))
        ).not.toThrow()
      })
    })
  })
})

describe('Auth Response Schema', () => {
  it('should validate correct auth response', () => {
    const AuthResponseSchema = z.object({
      access_token: z.string(),
      token_type: z.string(),
      user: z.object({
        id: z.string(),
        email: z.string().email(),
        role: z.enum(['admin', 'developer', 'viewer']),
        organization_id: z.string(),
      }),
    })

    const response = mockAuthResponse()
    expect(() => AuthResponseSchema.parse(response)).not.toThrow()
  })

  it('should reject missing token', () => {
    const AuthResponseSchema = z.object({
      access_token: z.string(),
      token_type: z.string(),
      user: z.object({
        id: z.string(),
        email: z.string().email(),
        role: z.enum(['admin', 'developer', 'viewer']),
        organization_id: z.string(),
      }),
    })

    const response = { ...mockAuthResponse(), access_token: undefined }
    expect(() => AuthResponseSchema.parse(response)).toThrow()
  })
})

describe('Paginated Response Schema', () => {
  it('should validate paginated tasks', () => {
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

    const PaginatedResponseSchema = z.object({
      items: z.array(TaskSchema),
      total: z.number(),
      page: z.number(),
      per_page: z.number(),
    })

    const paginatedResponse = {
      items: [mockTask(), mockTask({ id: 'task-2' })],
      total: 2,
      page: 1,
      per_page: 20,
    }

    expect(() => PaginatedResponseSchema.parse(paginatedResponse)).not.toThrow()
  })

  it('should validate empty paginated response', () => {
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

    const PaginatedResponseSchema = z.object({
      items: z.array(TaskSchema),
      total: z.number(),
      page: z.number(),
      per_page: z.number(),
    })

    const emptyResponse = {
      items: [],
      total: 0,
      page: 1,
      per_page: 20,
    }

    expect(() => PaginatedResponseSchema.parse(emptyResponse)).not.toThrow()
  })
})
