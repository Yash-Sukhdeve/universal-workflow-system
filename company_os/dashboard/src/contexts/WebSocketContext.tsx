import { createContext, useContext, useCallback, useState, type ReactNode } from 'react'
import { useWebSocket } from '@/hooks/useWebSocket'
import type { WSEvent } from '@/types'

interface WebSocketContextType {
  isConnected: boolean
  lastEvent: WSEvent | null
  taskEvents: WSEvent[]
  agentEvents: WSEvent[]
  memoryEvents: WSEvent[]
}

const WebSocketContext = createContext<WebSocketContextType | null>(null)

export function WebSocketProvider({ children }: { children: ReactNode }) {
  const [taskEvents, setTaskEvents] = useState<WSEvent[]>([])
  const [agentEvents, setAgentEvents] = useState<WSEvent[]>([])
  const [memoryEvents, setMemoryEvents] = useState<WSEvent[]>([])

  const handleMessage = useCallback((event: WSEvent) => {
    switch (event.type) {
      case 'task_updated':
        setTaskEvents((prev) => [event, ...prev].slice(0, 50))
        break
      case 'agent_status':
        setAgentEvents((prev) => [event, ...prev].slice(0, 50))
        break
      case 'memory_stored':
        setMemoryEvents((prev) => [event, ...prev].slice(0, 50))
        break
      default:
        break
    }
  }, [])

  const { isConnected, lastEvent } = useWebSocket({
    onMessage: handleMessage,
  })

  return (
    <WebSocketContext.Provider
      value={{
        isConnected,
        lastEvent,
        taskEvents,
        agentEvents,
        memoryEvents,
      }}
    >
      {children}
    </WebSocketContext.Provider>
  )
}

export function useWebSocketContext() {
  const context = useContext(WebSocketContext)
  if (!context) {
    throw new Error('useWebSocketContext must be used within a WebSocketProvider')
  }
  return context
}
