import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { WebSocketProvider, useWebSocketContext } from './WebSocketContext'
import type { WSEvent } from '@/types'

// Mock the useWebSocket hook
vi.mock('@/hooks/useWebSocket', () => ({
  useWebSocket: vi.fn(() => ({
    isConnected: false,
    lastEvent: null,
  })),
}))

import { useWebSocket } from '@/hooks/useWebSocket'
const mockUseWebSocket = vi.mocked(useWebSocket)

describe('WebSocketContext', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockUseWebSocket.mockReturnValue({
      isConnected: false,
      isAuthenticated: false,
      lastEvent: null,
      send: vi.fn(),
      reconnect: vi.fn(),
      disconnect: vi.fn(),
    })
  })

  describe('useWebSocketContext', () => {
    it('should throw error when used outside WebSocketProvider', () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})

      expect(() => {
        renderHook(() => useWebSocketContext())
      }).toThrow('useWebSocketContext must be used within a WebSocketProvider')

      consoleSpy.mockRestore()
    })
  })

  describe('WebSocketProvider', () => {
    it('should provide initial state', () => {
      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      expect(result.current.isConnected).toBe(false)
      expect(result.current.lastEvent).toBeNull()
      expect(result.current.taskEvents).toEqual([])
      expect(result.current.agentEvents).toEqual([])
      expect(result.current.memoryEvents).toEqual([])
    })

    it('should reflect connected state from useWebSocket', () => {
      mockUseWebSocket.mockReturnValue({
        isConnected: true,
        isAuthenticated: true,
        lastEvent: null,
        send: vi.fn(),
        reconnect: vi.fn(),
        disconnect: vi.fn(),
      })

      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      expect(result.current.isConnected).toBe(true)
    })

    it('should pass lastEvent from useWebSocket', () => {
      const testEvent: WSEvent = { type: 'task_updated', data: { id: 'task-1' } }
      mockUseWebSocket.mockReturnValue({
        isConnected: true,
        isAuthenticated: true,
        lastEvent: testEvent,
        send: vi.fn(),
        reconnect: vi.fn(),
        disconnect: vi.fn(),
      })

      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      expect(result.current.lastEvent).toEqual(testEvent)
    })

    it('should categorize task_updated events', () => {
      let messageHandler: ((event: WSEvent) => void) | undefined

      mockUseWebSocket.mockImplementation((options) => {
        messageHandler = options?.onMessage
        return {
          isConnected: true,
          isAuthenticated: true,
          lastEvent: null,
          send: vi.fn(),
          reconnect: vi.fn(),
          disconnect: vi.fn(),
        }
      })

      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      const taskEvent: WSEvent = { type: 'task_updated', data: { id: 'task-1' } }

      act(() => {
        messageHandler?.(taskEvent)
      })

      expect(result.current.taskEvents).toHaveLength(1)
      expect(result.current.taskEvents[0]).toEqual(taskEvent)
      expect(result.current.agentEvents).toHaveLength(0)
      expect(result.current.memoryEvents).toHaveLength(0)
    })

    it('should categorize agent_status events', () => {
      let messageHandler: ((event: WSEvent) => void) | undefined

      mockUseWebSocket.mockImplementation((options) => {
        messageHandler = options?.onMessage
        return {
          isConnected: true,
          isAuthenticated: true,
          lastEvent: null,
          send: vi.fn(),
          reconnect: vi.fn(),
          disconnect: vi.fn(),
        }
      })

      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      const agentEvent: WSEvent = { type: 'agent_status', data: { name: 'researcher', status: 'active' } }

      act(() => {
        messageHandler?.(agentEvent)
      })

      expect(result.current.agentEvents).toHaveLength(1)
      expect(result.current.agentEvents[0]).toEqual(agentEvent)
      expect(result.current.taskEvents).toHaveLength(0)
      expect(result.current.memoryEvents).toHaveLength(0)
    })

    it('should categorize memory_stored events', () => {
      let messageHandler: ((event: WSEvent) => void) | undefined

      mockUseWebSocket.mockImplementation((options) => {
        messageHandler = options?.onMessage
        return {
          isConnected: true,
          isAuthenticated: true,
          lastEvent: null,
          send: vi.fn(),
          reconnect: vi.fn(),
          disconnect: vi.fn(),
        }
      })

      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      const memoryEvent: WSEvent = { type: 'memory_stored', data: { id: 'mem-1' } }

      act(() => {
        messageHandler?.(memoryEvent)
      })

      expect(result.current.memoryEvents).toHaveLength(1)
      expect(result.current.memoryEvents[0]).toEqual(memoryEvent)
      expect(result.current.taskEvents).toHaveLength(0)
      expect(result.current.agentEvents).toHaveLength(0)
    })

    it('should limit stored events to 50', () => {
      let messageHandler: ((event: WSEvent) => void) | undefined

      mockUseWebSocket.mockImplementation((options) => {
        messageHandler = options?.onMessage
        return {
          isConnected: true,
          isAuthenticated: true,
          lastEvent: null,
          send: vi.fn(),
          reconnect: vi.fn(),
          disconnect: vi.fn(),
        }
      })

      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      // Add 60 events
      act(() => {
        for (let i = 0; i < 60; i++) {
          messageHandler?.({ type: 'task_updated', data: { id: `task-${i}` } })
        }
      })

      expect(result.current.taskEvents).toHaveLength(50)
      // Most recent should be first
      expect(result.current.taskEvents[0].data.id).toBe('task-59')
    })

    it('should ignore unknown event types', () => {
      let messageHandler: ((event: WSEvent) => void) | undefined

      mockUseWebSocket.mockImplementation((options) => {
        messageHandler = options?.onMessage
        return {
          isConnected: true,
          isAuthenticated: true,
          lastEvent: null,
          send: vi.fn(),
          reconnect: vi.fn(),
          disconnect: vi.fn(),
        }
      })

      const { result } = renderHook(() => useWebSocketContext(), {
        wrapper: WebSocketProvider,
      })

      const unknownEvent = { type: 'unknown_type', data: {} } as WSEvent

      act(() => {
        messageHandler?.(unknownEvent)
      })

      expect(result.current.taskEvents).toHaveLength(0)
      expect(result.current.agentEvents).toHaveLength(0)
      expect(result.current.memoryEvents).toHaveLength(0)
    })
  })
})
