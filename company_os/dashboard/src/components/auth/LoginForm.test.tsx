import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { BrowserRouter } from 'react-router-dom'
import { LoginForm } from './LoginForm'
import { useAuth } from '@/contexts/AuthContext'

// Mock useAuth hook
vi.mock('@/contexts/AuthContext', () => ({
  useAuth: vi.fn(),
}))

// Mock useNavigate
const mockNavigate = vi.fn()
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom')
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  }
})

const mockUseAuth = vi.mocked(useAuth)

const renderLoginForm = () => {
  return render(
    <BrowserRouter>
      <LoginForm />
    </BrowserRouter>
  )
}

describe('LoginForm', () => {
  const mockLogin = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    mockUseAuth.mockReturnValue({
      user: null,
      isLoading: false,
      isAuthenticated: false,
      login: mockLogin,
      register: vi.fn(),
      logout: vi.fn(),
    })
  })

  describe('rendering', () => {
    it('should render the login form', () => {
      renderLoginForm()

      expect(screen.getByRole('heading', { name: /company os/i })).toBeInTheDocument()
      expect(screen.getByText(/sign in to your account/i)).toBeInTheDocument()
      expect(screen.getByLabelText(/email/i)).toBeInTheDocument()
      expect(screen.getByLabelText(/password/i)).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument()
    })

    it('should render register link', () => {
      renderLoginForm()

      expect(screen.getByText(/don't have an account/i)).toBeInTheDocument()
      expect(screen.getByRole('link', { name: /register/i })).toHaveAttribute('href', '/register')
    })

    it('should have required fields', () => {
      renderLoginForm()

      expect(screen.getByLabelText(/email/i)).toBeRequired()
      expect(screen.getByLabelText(/password/i)).toBeRequired()
    })
  })

  describe('form interaction', () => {
    it('should update email input value', async () => {
      const user = userEvent.setup()
      renderLoginForm()

      const emailInput = screen.getByLabelText(/email/i)
      await user.type(emailInput, 'test@example.com')

      expect(emailInput).toHaveValue('test@example.com')
    })

    it('should update password input value', async () => {
      const user = userEvent.setup()
      renderLoginForm()

      const passwordInput = screen.getByLabelText(/password/i)
      await user.type(passwordInput, 'password123')

      expect(passwordInput).toHaveValue('password123')
    })

    it('should call login with email and password on submit', async () => {
      const user = userEvent.setup()
      mockLogin.mockResolvedValue(undefined)
      renderLoginForm()

      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'password123')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      expect(mockLogin).toHaveBeenCalledWith('test@example.com', 'password123')
    })
  })

  describe('form submission', () => {
    it('should navigate to home on successful login', async () => {
      const user = userEvent.setup()
      mockLogin.mockResolvedValue(undefined)
      renderLoginForm()

      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'password123')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/')
      })
    })

    it('should show loading state while submitting', async () => {
      const user = userEvent.setup()
      // Make login take some time
      mockLogin.mockImplementation(() => new Promise((resolve) => setTimeout(resolve, 100)))
      renderLoginForm()

      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'password123')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      expect(screen.getByText(/signing in/i)).toBeInTheDocument()
    })

    it('should disable submit button while loading', async () => {
      const user = userEvent.setup()
      mockLogin.mockImplementation(() => new Promise((resolve) => setTimeout(resolve, 100)))
      renderLoginForm()

      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'password123')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      expect(screen.getByRole('button')).toBeDisabled()
    })
  })

  describe('error handling', () => {
    it('should display error message on login failure', async () => {
      const user = userEvent.setup()
      mockLogin.mockRejectedValue(new Error('Invalid credentials'))
      renderLoginForm()

      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'wrongpassword')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      await waitFor(() => {
        expect(screen.getByText(/invalid email or password/i)).toBeInTheDocument()
      })
    })

    it('should clear error on new submission', async () => {
      const user = userEvent.setup()
      mockLogin.mockRejectedValueOnce(new Error('Invalid credentials'))
      mockLogin.mockResolvedValueOnce(undefined)
      renderLoginForm()

      // First attempt - fails
      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'wrongpassword')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      await waitFor(() => {
        expect(screen.getByText(/invalid email or password/i)).toBeInTheDocument()
      })

      // Second attempt - should clear error first
      await user.clear(screen.getByLabelText(/password/i))
      await user.type(screen.getByLabelText(/password/i), 'correctpassword')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      await waitFor(() => {
        expect(screen.queryByText(/invalid email or password/i)).not.toBeInTheDocument()
      })
    })

    it('should not navigate on login failure', async () => {
      const user = userEvent.setup()
      mockLogin.mockRejectedValue(new Error('Invalid credentials'))
      renderLoginForm()

      await user.type(screen.getByLabelText(/email/i), 'test@example.com')
      await user.type(screen.getByLabelText(/password/i), 'wrongpassword')
      await user.click(screen.getByRole('button', { name: /sign in/i }))

      await waitFor(() => {
        expect(screen.getByText(/invalid email or password/i)).toBeInTheDocument()
      })

      expect(mockNavigate).not.toHaveBeenCalled()
    })
  })

  describe('accessibility', () => {
    it('should have proper form labels', () => {
      renderLoginForm()

      const emailInput = screen.getByLabelText(/email/i)
      const passwordInput = screen.getByLabelText(/password/i)

      expect(emailInput).toHaveAttribute('id', 'email')
      expect(passwordInput).toHaveAttribute('id', 'password')
    })

    it('should have proper input types', () => {
      renderLoginForm()

      expect(screen.getByLabelText(/email/i)).toHaveAttribute('type', 'email')
      expect(screen.getByLabelText(/password/i)).toHaveAttribute('type', 'password')
    })

    it('should have placeholder text', () => {
      renderLoginForm()

      expect(screen.getByPlaceholderText(/you@example.com/i)).toBeInTheDocument()
      expect(screen.getByPlaceholderText(/enter your password/i)).toBeInTheDocument()
    })
  })
})
