import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { AuthProvider, useAuth } from './AuthContext'
import { authApi } from '@/services/api'
import { mockUser, mockAuthResponse } from '@/test/utils'

// Mock the API
vi.mock('@/services/api', () => ({
  authApi: {
    login: vi.fn(),
    register: vi.fn(),
    me: vi.fn(),
  },
}))

const mockAuthApi = vi.mocked(authApi)

describe('AuthContext', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    localStorage.clear()
  })

  describe('useAuth hook', () => {
    it('should throw error when used outside AuthProvider', () => {
      // Suppress console.error for this test
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})

      expect(() => {
        renderHook(() => useAuth())
      }).toThrow('useAuth must be used within an AuthProvider')

      consoleSpy.mockRestore()
    })
  })

  describe('AuthProvider', () => {
    it('should initialize with correct default values', async () => {
      mockAuthApi.me.mockRejectedValue(new Error('No token'))

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      // Initially or after initialization, these should be set
      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.user).toBeNull()
      expect(result.current.isAuthenticated).toBe(false)
    })

    it('should set isLoading to false after initialization', async () => {
      mockAuthApi.me.mockRejectedValue(new Error('No token'))

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })
    })

    it('should restore user from localStorage if token exists', async () => {
      const user = mockUser()
      localStorage.setItem('token', 'test-token')
      localStorage.setItem('user', JSON.stringify(user))
      mockAuthApi.me.mockResolvedValue(user)

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.user).toEqual(user)
      expect(result.current.isAuthenticated).toBe(true)
    })

    it('should clear localStorage if token is invalid', async () => {
      localStorage.setItem('token', 'invalid-token')
      localStorage.setItem('user', JSON.stringify(mockUser()))
      mockAuthApi.me.mockRejectedValue(new Error('Invalid token'))

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.user).toBeNull()
      expect(result.current.isAuthenticated).toBe(false)
      expect(localStorage.getItem('token')).toBeNull()
      expect(localStorage.getItem('user')).toBeNull()
    })

    it('should not have user if no token in localStorage', async () => {
      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.user).toBeNull()
      expect(result.current.isAuthenticated).toBe(false)
    })
  })

  describe('login', () => {
    it('should login successfully and store token', async () => {
      const authResponse = mockAuthResponse()
      mockAuthApi.login.mockResolvedValue(authResponse)

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      await act(async () => {
        await result.current.login('test@example.com', 'password123')
      })

      expect(mockAuthApi.login).toHaveBeenCalledWith('test@example.com', 'password123')
      expect(result.current.user).toEqual(authResponse.user)
      expect(result.current.isAuthenticated).toBe(true)
      expect(localStorage.getItem('token')).toBe(authResponse.access_token)
    })

    it('should throw error on login failure', async () => {
      const error = new Error('Invalid credentials')
      mockAuthApi.login.mockRejectedValue(error)

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      await expect(
        act(async () => {
          await result.current.login('test@example.com', 'wrongpassword')
        })
      ).rejects.toThrow('Invalid credentials')

      expect(result.current.user).toBeNull()
      expect(result.current.isAuthenticated).toBe(false)
    })
  })

  describe('register', () => {
    it('should register and auto-login', async () => {
      const user = mockUser()
      const authResponse = mockAuthResponse({ user })

      mockAuthApi.register.mockResolvedValue(user)
      mockAuthApi.login.mockResolvedValue(authResponse)

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      await act(async () => {
        await result.current.register('new@example.com', 'password123', 'org-1')
      })

      expect(mockAuthApi.register).toHaveBeenCalledWith(
        'new@example.com',
        'password123',
        'org-1'
      )
      expect(mockAuthApi.login).toHaveBeenCalledWith('new@example.com', 'password123')
      expect(result.current.user).toEqual(user)
      expect(result.current.isAuthenticated).toBe(true)
    })

    it('should throw error on registration failure', async () => {
      const error = new Error('Email already exists')
      mockAuthApi.register.mockRejectedValue(error)

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      await expect(
        act(async () => {
          await result.current.register('existing@example.com', 'password123')
        })
      ).rejects.toThrow('Email already exists')

      expect(result.current.user).toBeNull()
    })
  })

  describe('logout', () => {
    it('should clear user and localStorage on logout', async () => {
      const authResponse = mockAuthResponse()
      mockAuthApi.login.mockResolvedValue(authResponse)

      const { result } = renderHook(() => useAuth(), {
        wrapper: AuthProvider,
      })

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // Login first
      await act(async () => {
        await result.current.login('test@example.com', 'password123')
      })

      expect(result.current.isAuthenticated).toBe(true)

      // Then logout
      act(() => {
        result.current.logout()
      })

      expect(result.current.user).toBeNull()
      expect(result.current.isAuthenticated).toBe(false)
      expect(localStorage.getItem('token')).toBeNull()
      expect(localStorage.getItem('user')).toBeNull()
    })
  })
})
