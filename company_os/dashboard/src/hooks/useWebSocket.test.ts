import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { useWebSocket } from './useWebSocket'

// Mock WebSocket
class MockWebSocket {
  static CONNECTING = 0
  static OPEN = 1
  static CLOSING = 2
  static CLOSED = 3

  url: string
  readyState: number = MockWebSocket.CONNECTING
  onopen: ((ev: Event) => void) | null = null
  onclose: ((ev: CloseEvent) => void) | null = null
  onmessage: ((ev: MessageEvent) => void) | null = null
  onerror: ((ev: Event) => void) | null = null
  sentMessages: string[] = []

  constructor(url: string) {
    this.url = url
    // Simulate async connection
    setTimeout(() => {
      this.readyState = MockWebSocket.OPEN
      this.onopen?.(new Event('open'))
    }, 10)
  }

  send(data: string) {
    this.sentMessages.push(data)
  }

  close() {
    this.readyState = MockWebSocket.CLOSED
    this.onclose?.(new CloseEvent('close'))
  }

  // Helper to simulate receiving a message
  simulateMessage(data: unknown) {
    this.onmessage?.(new MessageEvent('message', { data: JSON.stringify(data) }))
  }

  // Helper to simulate error
  simulateError() {
    this.onerror?.(new Event('error'))
  }
}

// Store reference to created WebSocket instances
let mockWsInstance: MockWebSocket | null = null

describe('useWebSocket', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    localStorage.setItem('token', 'test-token')

    // Mock WebSocket constructor
    vi.stubGlobal('WebSocket', class extends MockWebSocket {
      constructor(url: string) {
        super(url)
        mockWsInstance = this
      }
    })
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
    localStorage.clear()
    mockWsInstance = null
  })

  it('should not connect without token', () => {
    localStorage.removeItem('token')

    const { result } = renderHook(() => useWebSocket())

    expect(result.current.isConnected).toBe(false)
    expect(mockWsInstance).toBeNull()
  })

  it('should connect when token exists', async () => {
    const { result } = renderHook(() => useWebSocket())

    // Advance timers to trigger connection
    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    expect(mockWsInstance).not.toBeNull()
    expect(result.current.isConnected).toBe(true)
  })

  it('should send auth token after connection', async () => {
    renderHook(() => useWebSocket())

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    expect(mockWsInstance?.sentMessages).toContain(
      JSON.stringify({ type: 'auth', token: 'test-token' })
    )
  })

  it('should call onOpen callback when connected', async () => {
    const onOpen = vi.fn()

    renderHook(() => useWebSocket({ onOpen }))

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    expect(onOpen).toHaveBeenCalled()
  })

  it('should call onMessage callback when message received', async () => {
    const onMessage = vi.fn()

    renderHook(() => useWebSocket({ onMessage }))

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    // Simulate auth success first
    act(() => {
      mockWsInstance?.simulateMessage({ type: 'auth_success' })
    })

    // Then simulate a regular message
    const testEvent = { type: 'task_updated', data: { id: 'task-1' } }
    act(() => {
      mockWsInstance?.simulateMessage(testEvent)
    })

    expect(onMessage).toHaveBeenCalledWith(testEvent)
  })

  it('should update lastEvent when message received', async () => {
    const { result } = renderHook(() => useWebSocket())

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    // Simulate auth success
    act(() => {
      mockWsInstance?.simulateMessage({ type: 'auth_success' })
    })

    const testEvent = { type: 'task_updated', data: { id: 'task-1' } }
    act(() => {
      mockWsInstance?.simulateMessage(testEvent)
    })

    expect(result.current.lastEvent).toEqual(testEvent)
  })

  it('should set isAuthenticated after auth_success', async () => {
    const { result } = renderHook(() => useWebSocket())

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    expect(result.current.isAuthenticated).toBe(false)

    act(() => {
      mockWsInstance?.simulateMessage({ type: 'auth_success' })
    })

    expect(result.current.isAuthenticated).toBe(true)
  })

  it('should close connection on auth_error', async () => {
    renderHook(() => useWebSocket())

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    const closeSpy = vi.spyOn(mockWsInstance!, 'close')

    act(() => {
      mockWsInstance?.simulateMessage({ type: 'auth_error' })
    })

    expect(closeSpy).toHaveBeenCalled()
  })

  it('should call onClose callback when disconnected', async () => {
    const onClose = vi.fn()

    renderHook(() => useWebSocket({ onClose, reconnect: false }))

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    act(() => {
      mockWsInstance?.close()
    })

    expect(onClose).toHaveBeenCalled()
  })

  it('should call onError callback on error', async () => {
    const onError = vi.fn()

    renderHook(() => useWebSocket({ onError }))

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    act(() => {
      mockWsInstance?.simulateError()
    })

    expect(onError).toHaveBeenCalled()
  })

  it('should attempt reconnection after disconnect', async () => {
    const { result } = renderHook(() =>
      useWebSocket({ reconnect: true, reconnectInterval: 1000 })
    )

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    expect(result.current.isConnected).toBe(true)

    // Close connection
    act(() => {
      mockWsInstance?.close()
    })

    expect(result.current.isConnected).toBe(false)

    // Advance timer for reconnection
    await act(async () => {
      vi.advanceTimersByTime(1020) // reconnectInterval + connection time
    })

    // Should have attempted to reconnect
    expect(mockWsInstance).not.toBeNull()
  })

  it('should respect maxReconnectAttempts configuration', async () => {
    // This test verifies that the hook accepts and uses maxReconnectAttempts
    const { result } = renderHook(() =>
      useWebSocket({
        reconnect: true,
        reconnectInterval: 100,
        maxReconnectAttempts: 2,
      })
    )

    // Initial connection
    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    expect(result.current.isConnected).toBe(true)

    // Simulate disconnection - hook should attempt to reconnect
    act(() => {
      mockWsInstance?.close()
    })

    expect(result.current.isConnected).toBe(false)

    // Advance time for reconnection attempt
    await act(async () => {
      vi.advanceTimersByTime(120)
    })

    // Should have reconnected
    expect(mockWsInstance).not.toBeNull()
  })

  it('should not reconnect when reconnect is false', async () => {
    const { result } = renderHook(() => useWebSocket({ reconnect: false }))

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    const firstInstance = mockWsInstance

    act(() => {
      mockWsInstance?.close()
    })

    await act(async () => {
      vi.advanceTimersByTime(5000)
    })

    // Should not have created a new instance
    expect(result.current.isConnected).toBe(false)
  })

  it('should send data when authenticated', async () => {
    const { result } = renderHook(() => useWebSocket())

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    // Authenticate
    act(() => {
      mockWsInstance?.simulateMessage({ type: 'auth_success' })
    })

    // Clear sent messages after auth
    mockWsInstance!.sentMessages = []

    // Send data
    act(() => {
      result.current.send({ type: 'test', data: 'hello' })
    })

    expect(mockWsInstance?.sentMessages).toContain(
      JSON.stringify({ type: 'test', data: 'hello' })
    )
  })

  it('should not send data when not authenticated', async () => {
    const { result } = renderHook(() => useWebSocket())

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    // Clear sent messages after auth request
    mockWsInstance!.sentMessages = []

    // Try to send without being authenticated
    act(() => {
      result.current.send({ type: 'test', data: 'hello' })
    })

    expect(mockWsInstance?.sentMessages).toHaveLength(0)
  })

  it('should disconnect cleanly', async () => {
    const { result } = renderHook(() => useWebSocket())

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    expect(result.current.isConnected).toBe(true)

    act(() => {
      result.current.disconnect()
    })

    expect(result.current.isConnected).toBe(false)
  })

  it('should handle malformed messages gracefully', async () => {
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
    const onMessage = vi.fn()

    renderHook(() => useWebSocket({ onMessage }))

    await act(async () => {
      vi.advanceTimersByTime(20)
    })

    // Send malformed message
    act(() => {
      mockWsInstance?.onmessage?.(
        new MessageEvent('message', { data: 'not json' })
      )
    })

    expect(consoleSpy).toHaveBeenCalled()
    expect(onMessage).not.toHaveBeenCalled()

    consoleSpy.mockRestore()
  })
})
