import { ReactElement, ReactNode } from 'react'
import { render, RenderOptions } from '@testing-library/react'
import { BrowserRouter } from 'react-router-dom'
import { AuthProvider } from '@/contexts/AuthContext'
import { WebSocketProvider } from '@/contexts/WebSocketContext'

interface WrapperProps {
  children: ReactNode
}

// All providers wrapper for testing
function AllProviders({ children }: WrapperProps) {
  return (
    <BrowserRouter>
      <AuthProvider>
        <WebSocketProvider>
          {children}
        </WebSocketProvider>
      </AuthProvider>
    </BrowserRouter>
  )
}

// Router-only wrapper
function RouterWrapper({ children }: WrapperProps) {
  return <BrowserRouter>{children}</BrowserRouter>
}

// Custom render with all providers
const customRender = (
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>
) => render(ui, { wrapper: AllProviders, ...options })

// Custom render with router only
const renderWithRouter = (
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>
) => render(ui, { wrapper: RouterWrapper, ...options })

// Re-export everything
export * from '@testing-library/react'
export { customRender as render, renderWithRouter }

// Mock data factories
export const mockUser = (overrides = {}) => ({
  id: 'user-1',
  email: 'test@example.com',
  role: 'developer' as const,
  organization_id: 'org-1',
  ...overrides,
})

export const mockTask = (overrides = {}) => ({
  id: 'task-1',
  title: 'Test Task',
  description: 'Test description',
  status: 'pending' as const,
  priority: 'medium' as const,
  assigned_to: null,
  created_at: '2024-01-01T00:00:00Z',
  updated_at: '2024-01-01T00:00:00Z',
  project_id: null,
  ...overrides,
})

export const mockAgent = (overrides = {}) => ({
  name: 'researcher',
  status: 'inactive' as const,
  capabilities: ['literature_review', 'experimental_design'],
  current_task: null,
  activated_at: null,
  ...overrides,
})

export const mockMemory = (overrides = {}) => ({
  id: 'mem-1',
  content: 'Test memory content',
  type: 'context' as const,
  relevance_score: 0.85,
  created_at: '2024-01-01T00:00:00Z',
  metadata: null,
  ...overrides,
})

export const mockAuthResponse = (overrides = {}) => ({
  access_token: 'mock-token-123',
  token_type: 'bearer',
  user: mockUser(),
  ...overrides,
})
