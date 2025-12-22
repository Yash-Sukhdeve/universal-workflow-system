import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { BrowserRouter, MemoryRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider, useAuth } from '@/contexts/AuthContext'
import { LoginForm } from '@/components/auth/LoginForm'
import { RegisterForm } from '@/components/auth/RegisterForm'
import { authApi } from '@/services/api'
import { mockAuthResponse, mockUser } from '@/test/utils'

// Mock the API
vi.mock('@/services/api', () => ({
  authApi: {
    login: vi.fn(),
    register: vi.fn(),
    me: vi.fn(),
  },
}))

const mockAuthApi = vi.mocked(authApi)

// Create a fresh QueryClient for each test
const createTestQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
    },
  })

// Wrapper component for integration tests
function IntegrationWrapper({ children, initialEntries = ['/login'] }: { children: React.ReactNode; initialEntries?: string[] }) {
  const queryClient = createTestQueryClient()
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={initialEntries}>
        <AuthProvider>{children}</AuthProvider>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

// Test component to display auth state
function AuthStateDisplay() {
  const { user, isAuthenticated, isLoading } = useAuth()
  return (
    <div>
      <span data-testid="is-loading">{isLoading ? 'loading' : 'ready'}</span>
      <span data-testid="is-authenticated">{isAuthenticated ? 'authenticated' : 'not-authenticated'}</span>
      <span data-testid="user-email">{user?.email || 'no-user'}</span>
    </div>
  )
}

describe('Auth Flow Integration', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()
  })

  afterEach(() => {
    localStorage.clear()
  })

  describe('Login Flow', () => {
    it('should complete full login flow: form → API → context → localStorage', async () => {
      const user = userEvent.setup()
      const authResponse = mockAuthResponse()
      mockAuthApi.login.mockResolvedValue(authResponse)
      mockAuthApi.me.mockRejectedValue(new Error('No token'))

      render(
        <IntegrationWrapper>
          <Routes>
            <Route path="/login" element={<LoginForm />} />
            <Route path="/" element={<AuthStateDisplay />} />
          </Routes>
        </IntegrationWrapper>
      )

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByLabelText(/email/i)).toBeInTheDocument()
      })

      // Fill in login form
      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'password123')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      // Verify API was called with correct credentials
      await waitFor(() => {
        expect(mockAuthApi.login).toHaveBeenCalledWith('test@example.com', 'password123')
      })

      // Verify localStorage was updated
      await waitFor(() => {
        expect(localStorage.getItem('token')).toBe(authResponse.access_token)
      })
    })

    it('should persist auth state across context updates', async () => {
      const authResponse = mockAuthResponse()
      const testUser = authResponse.user

      // Pre-set localStorage to simulate existing session
      localStorage.setItem('token', authResponse.access_token)
      localStorage.setItem('user', JSON.stringify(testUser))
      mockAuthApi.me.mockResolvedValue(testUser)

      render(
        <IntegrationWrapper initialEntries={['/']}>
          <AuthStateDisplay />
        </IntegrationWrapper>
      )

      // Wait for auth context to restore from localStorage
      await waitFor(() => {
        expect(screen.getByTestId('is-loading')).toHaveTextContent('ready')
      })

      expect(screen.getByTestId('is-authenticated')).toHaveTextContent('authenticated')
      expect(screen.getByTestId('user-email')).toHaveTextContent(testUser.email)
    })

    it('should handle login errors and display error message', async () => {
      const user = userEvent.setup()
      mockAuthApi.login.mockRejectedValue(new Error('Invalid credentials'))
      mockAuthApi.me.mockRejectedValue(new Error('No token'))

      render(
        <IntegrationWrapper>
          <LoginForm />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByLabelText(/email/i)).toBeInTheDocument()
      })

      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'wrongpassword')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      // Verify error is displayed
      await waitFor(() => {
        expect(screen.getByText(/invalid email or password/i)).toBeInTheDocument()
      })

      // Verify localStorage was NOT updated
      expect(localStorage.getItem('token')).toBeNull()
    })

    it('should clear auth state on logout', async () => {
      const authResponse = mockAuthResponse()
      const testUser = authResponse.user

      localStorage.setItem('token', authResponse.access_token)
      localStorage.setItem('user', JSON.stringify(testUser))
      mockAuthApi.me.mockResolvedValue(testUser)

      // Component that triggers logout
      function LogoutButton() {
        const { logout, isAuthenticated } = useAuth()
        return (
          <div>
            <span data-testid="auth-state">{isAuthenticated ? 'logged-in' : 'logged-out'}</span>
            <button onClick={logout}>Logout</button>
          </div>
        )
      }

      const user = userEvent.setup()

      render(
        <IntegrationWrapper initialEntries={['/']}>
          <LogoutButton />
        </IntegrationWrapper>
      )

      // Wait for initial authenticated state
      await waitFor(() => {
        expect(screen.getByTestId('auth-state')).toHaveTextContent('logged-in')
      })

      // Click logout
      await user.click(screen.getByRole('button', { name: /logout/i }))

      // Verify state is cleared
      await waitFor(() => {
        expect(screen.getByTestId('auth-state')).toHaveTextContent('logged-out')
      })

      expect(localStorage.getItem('token')).toBeNull()
      expect(localStorage.getItem('user')).toBeNull()
    })
  })

  describe('Registration Flow', () => {
    it('should complete full registration flow: form → API → auto-login', async () => {
      const user = userEvent.setup()
      const newUser = mockUser({ email: 'new@example.com' })
      const authResponse = mockAuthResponse({ user: newUser })

      mockAuthApi.register.mockResolvedValue(newUser)
      mockAuthApi.login.mockResolvedValue(authResponse)
      mockAuthApi.me.mockRejectedValue(new Error('No token'))

      render(
        <IntegrationWrapper initialEntries={['/register']}>
          <Routes>
            <Route path="/register" element={<RegisterForm />} />
            <Route path="/" element={<AuthStateDisplay />} />
          </Routes>
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByLabelText(/email/i)).toBeInTheDocument()
      })

      // Password must meet requirements: 12+ chars, uppercase, lowercase, number, special
      const strongPassword = 'SecurePass123!'
      await user.type(screen.getByLabelText(/email/i), 'new@example.com')
      await user.type(screen.getByLabelText(/^password$/i), strongPassword)
      await user.type(screen.getByLabelText(/confirm password/i), strongPassword)
      await user.click(screen.getByRole('button', { name: /create account/i }))

      // Verify registration API was called
      await waitFor(() => {
        expect(mockAuthApi.register).toHaveBeenCalledWith('new@example.com', strongPassword, undefined)
      })

      // Verify auto-login was triggered
      await waitFor(() => {
        expect(mockAuthApi.login).toHaveBeenCalledWith('new@example.com', strongPassword)
      })
    })

    it('should handle registration errors', async () => {
      const user = userEvent.setup()
      mockAuthApi.register.mockRejectedValue(new Error('Email already exists'))
      mockAuthApi.me.mockRejectedValue(new Error('No token'))

      render(
        <IntegrationWrapper initialEntries={['/register']}>
          <RegisterForm />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByLabelText(/email/i)).toBeInTheDocument()
      })

      const strongPassword = 'SecurePass123!'
      await user.type(screen.getByLabelText(/email/i), 'existing@example.com')
      await user.type(screen.getByLabelText(/^password$/i), strongPassword)
      await user.type(screen.getByLabelText(/confirm password/i), strongPassword)
      await user.click(screen.getByRole('button', { name: /create account/i }))

      // Verify error is displayed
      await waitFor(() => {
        expect(screen.getByText(/email already exists|registration failed/i)).toBeInTheDocument()
      })
    })
  })

  describe('Session Persistence', () => {
    it('should validate token on app load', async () => {
      const testUser = mockUser()
      localStorage.setItem('token', 'valid-token')
      localStorage.setItem('user', JSON.stringify(testUser))
      mockAuthApi.me.mockResolvedValue(testUser)

      render(
        <IntegrationWrapper initialEntries={['/']}>
          <AuthStateDisplay />
        </IntegrationWrapper>
      )

      // Should call me() to validate token
      await waitFor(() => {
        expect(mockAuthApi.me).toHaveBeenCalled()
      })

      expect(screen.getByTestId('is-authenticated')).toHaveTextContent('authenticated')
    })

    it('should clear invalid token on validation failure', async () => {
      localStorage.setItem('token', 'invalid-token')
      localStorage.setItem('user', JSON.stringify(mockUser()))
      mockAuthApi.me.mockRejectedValue(new Error('Invalid token'))

      render(
        <IntegrationWrapper initialEntries={['/']}>
          <AuthStateDisplay />
        </IntegrationWrapper>
      )

      await waitFor(() => {
        expect(screen.getByTestId('is-loading')).toHaveTextContent('ready')
      })

      expect(screen.getByTestId('is-authenticated')).toHaveTextContent('not-authenticated')
      expect(localStorage.getItem('token')).toBeNull()
    })
  })
})
