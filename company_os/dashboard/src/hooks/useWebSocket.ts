import { useEffect, useRef, useState, useCallback } from 'react'
import type { WSEvent } from '@/types'

// Security: Constants for WebSocket configuration
const WEBSOCKET_CONFIG = {
  MAX_RECONNECT_ATTEMPTS: 5,
  RECONNECT_INTERVAL_MS: 3000,
  AUTH_TIMEOUT_MS: 5000,
} as const

interface UseWebSocketOptions {
  onMessage?: (event: WSEvent) => void
  onOpen?: () => void
  onClose?: () => void
  onError?: (error: Event) => void
  reconnect?: boolean
  reconnectInterval?: number
  maxReconnectAttempts?: number
}

export function useWebSocket(options: UseWebSocketOptions = {}) {
  const {
    onMessage,
    onOpen,
    onClose,
    onError,
    reconnect = true,
    reconnectInterval = WEBSOCKET_CONFIG.RECONNECT_INTERVAL_MS,
    maxReconnectAttempts = WEBSOCKET_CONFIG.MAX_RECONNECT_ATTEMPTS,
  } = options

  const [isConnected, setIsConnected] = useState(false)
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [lastEvent, setLastEvent] = useState<WSEvent | null>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const reconnectAttemptsRef = useRef(0)
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const authTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Store callbacks in refs to avoid dependency changes
  const onMessageRef = useRef(onMessage)
  const onOpenRef = useRef(onOpen)
  const onCloseRef = useRef(onClose)
  const onErrorRef = useRef(onError)

  // Update refs when callbacks change
  useEffect(() => {
    onMessageRef.current = onMessage
    onOpenRef.current = onOpen
    onCloseRef.current = onClose
    onErrorRef.current = onError
  }, [onMessage, onOpen, onClose, onError])

  const connect = useCallback(() => {
    const token = localStorage.getItem('token')
    if (!token) return

    // SECURITY FIX: Don't pass token in URL - send it after connection
    // This prevents token exposure in server logs, browser history, and referrer headers
    const wsUrl = `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/ws`

    try {
      wsRef.current = new WebSocket(wsUrl)

      wsRef.current.onopen = () => {
        setIsConnected(true)
        reconnectAttemptsRef.current = 0

        // SECURITY: Send authentication token as first message after connection
        // This is more secure than passing in URL query parameters
        if (wsRef.current?.readyState === WebSocket.OPEN) {
          wsRef.current.send(JSON.stringify({
            type: 'auth',
            token: token,
          }))

          // Set timeout for auth response
          authTimeoutRef.current = setTimeout(() => {
            if (!isAuthenticated && wsRef.current) {
              console.error('WebSocket authentication timeout')
              wsRef.current.close()
            }
          }, WEBSOCKET_CONFIG.AUTH_TIMEOUT_MS)
        }

        onOpenRef.current?.()
      }

      wsRef.current.onclose = () => {
        setIsConnected(false)
        setIsAuthenticated(false)

        if (authTimeoutRef.current) {
          clearTimeout(authTimeoutRef.current)
        }

        onCloseRef.current?.()

        // Attempt reconnection
        if (reconnect && reconnectAttemptsRef.current < maxReconnectAttempts) {
          reconnectAttemptsRef.current++
          reconnectTimeoutRef.current = setTimeout(connect, reconnectInterval)
        }
      }

      wsRef.current.onerror = (error) => {
        onErrorRef.current?.(error)
      }

      wsRef.current.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data) as WSEvent

          // Handle auth response
          if (data.type === 'auth_success') {
            setIsAuthenticated(true)
            if (authTimeoutRef.current) {
              clearTimeout(authTimeoutRef.current)
            }
            return
          }

          if (data.type === 'auth_error') {
            console.error('WebSocket authentication failed')
            wsRef.current?.close()
            return
          }

          setLastEvent(data)
          onMessageRef.current?.(data)
        } catch {
          console.error('Failed to parse WebSocket message:', event.data)
        }
      }
    } catch (error) {
      console.error('WebSocket connection error:', error)
    }
  }, [reconnect, reconnectInterval, maxReconnectAttempts, isAuthenticated])

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current)
    }
    if (authTimeoutRef.current) {
      clearTimeout(authTimeoutRef.current)
    }
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }
    setIsAuthenticated(false)
  }, [])

  const send = useCallback((data: unknown) => {
    if (wsRef.current?.readyState === WebSocket.OPEN && isAuthenticated) {
      wsRef.current.send(JSON.stringify(data))
    }
  }, [isAuthenticated])

  // SECURITY FIX: Remove connect/disconnect from dependency array to prevent memory leak
  // Use empty dependency array since we use refs for callbacks
  useEffect(() => {
    connect()
    return () => disconnect()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {
    isConnected,
    isAuthenticated,
    lastEvent,
    send,
    reconnect: connect,
    disconnect,
  }
}
