// User types
export interface User {
  id: string
  email: string
  name?: string
  role: 'owner' | 'admin' | 'developer' | 'viewer'
  org_id: string
}

export interface AuthResponse {
  access_token: string
  token_type: string
  refresh_token?: string
  expires_in?: number
}

// Task types
export interface Task {
  id: string
  title: string
  description: string
  status: 'pending' | 'in_progress' | 'completed' | 'blocked'
  priority: 'low' | 'medium' | 'high' | 'critical'
  assigned_to?: string | null
  created_at: string
  updated_at: string
  project_id?: string | null
}

export interface CreateTaskInput {
  title: string
  description: string
  priority: Task['priority']
  assigned_to?: string
  project_id?: string
}

// Agent types
export interface Agent {
  type: string
  name: string
  description: string
  capabilities: string[]
  icon: string
}

// Memory types
export interface Memory {
  id: string
  content: string
  type: 'decision' | 'discovery' | 'learning' | 'context'
  relevance_score: number
  created_at: string
  metadata?: Record<string, unknown> | null
}

export interface MemoryContext {
  recent_memories: Memory[]
  similar_tasks: Task[]
  decisions: Memory[]
}

// WebSocket event types - typed discriminated union for better type safety
interface TaskUpdatedEvent {
  type: 'task_updated'
  data: Task
  timestamp: string
}

interface AgentStatusEvent {
  type: 'agent_status'
  data: Agent
  timestamp: string
}

interface MemoryStoredEvent {
  type: 'memory_stored'
  data: Memory
  timestamp: string
}

interface CheckpointCreatedEvent {
  type: 'checkpoint_created'
  data: { id: string; message: string }
  timestamp: string
}

// Auth events for WebSocket (not exposed to UI - handled internally)
interface AuthSuccessEvent {
  type: 'auth_success'
  data: { user_id: string }
  timestamp: string
}

interface AuthErrorEvent {
  type: 'auth_error'
  data: { message: string }
  timestamp: string
}

export type WSEvent =
  | TaskUpdatedEvent
  | AgentStatusEvent
  | MemoryStoredEvent
  | CheckpointCreatedEvent
  | AuthSuccessEvent
  | AuthErrorEvent

// API response types
export interface ApiError {
  detail: string
}

export interface PaginatedResponse<T> {
  items: T[]
  total: number
  page: number
  per_page: number
}
