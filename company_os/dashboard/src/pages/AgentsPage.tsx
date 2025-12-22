import { useEffect, useState, useRef, useCallback } from 'react'
import { Bot, Power, PowerOff, Zap, Settings, Radio } from 'lucide-react'
import { agentsApi } from '@/services/api'
import { useWebSocketContext } from '@/contexts/WebSocketContext'
import type { Agent } from '@/types'

const agentColors: Record<string, string> = {
  researcher: 'bg-purple-100 text-purple-700 border-purple-200',
  architect: 'bg-blue-100 text-blue-700 border-blue-200',
  implementer: 'bg-green-100 text-green-700 border-green-200',
  experimenter: 'bg-orange-100 text-orange-700 border-orange-200',
  optimizer: 'bg-cyan-100 text-cyan-700 border-cyan-200',
  deployer: 'bg-red-100 text-red-700 border-red-200',
  documenter: 'bg-yellow-100 text-yellow-700 border-yellow-200',
}

export function AgentsPage() {
  const [agents, setAgents] = useState<Agent[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [activatingAgent, setActivatingAgent] = useState<string | null>(null)
  const { agentEvents, isConnected } = useWebSocketContext()
  const isMountedRef = useRef(true)

  const loadAgents = useCallback(async () => {
    try {
      const agentsList = await agentsApi.list()
      if (isMountedRef.current) {
        setAgents(agentsList || [])
      }
    } catch (error) {
      if (isMountedRef.current) {
        console.error('Failed to load agents:', error)
      }
    } finally {
      if (isMountedRef.current) {
        setIsLoading(false)
      }
    }
  }, [])

  useEffect(() => {
    isMountedRef.current = true
    loadAgents()
    return () => {
      isMountedRef.current = false
    }
  }, [loadAgents])

  // Refresh agents when we receive WebSocket agent status updates
  useEffect(() => {
    if (agentEvents.length > 0 && isMountedRef.current) {
      loadAgents()
    }
  }, [agentEvents.length, loadAgents])

  const handleActivate = async (agentName: string) => {
    setActivatingAgent(agentName)
    try {
      await agentsApi.activate(agentName)
      await loadAgents()
    } catch (error) {
      console.error('Failed to activate agent:', error)
    } finally {
      setActivatingAgent(null)
    }
  }

  const handleDeactivate = async (agentName: string) => {
    setActivatingAgent(agentName)
    try {
      await agentsApi.deactivate(agentName)
      await loadAgents()
    } catch (error) {
      console.error('Failed to deactivate agent:', error)
    } finally {
      setActivatingAgent(null)
    }
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Agents</h1>
          <p className="text-gray-500 mt-1">Manage workflow agents and their capabilities</p>
        </div>
        {isConnected && (
          <span className="flex items-center gap-1 text-xs text-green-600 bg-green-100 px-2 py-1 rounded-full">
            <Radio size={12} className="animate-pulse" />
            Live Updates
          </span>
        )}
      </div>

      {/* Agent Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {agents.length > 0 ? (
          agents.map((agent) => (
            <AgentCard
              key={agent.name}
              agent={agent}
              colorClass={agentColors[agent.name] || 'bg-gray-100 text-gray-700 border-gray-200'}
              onActivate={() => handleActivate(agent.name)}
              onDeactivate={() => handleDeactivate(agent.name)}
              isLoading={activatingAgent === agent.name}
            />
          ))
        ) : (
          <div className="col-span-full text-center py-12 text-gray-500">
            <Bot size={48} className="mx-auto mb-4 opacity-50" />
            <p>No agents configured</p>
            <p className="text-sm mt-1">Configure agents in the UWS registry</p>
          </div>
        )}
      </div>
    </div>
  )
}

interface AgentCardProps {
  agent: Agent
  colorClass: string
  onActivate: () => void
  onDeactivate: () => void
  isLoading: boolean
}

function AgentCard({ agent, colorClass, onActivate, onDeactivate, isLoading }: AgentCardProps) {
  const isActive = agent.status === 'active'

  return (
    <div className={`card border-2 ${isActive ? 'border-blue-300 bg-blue-50/30' : 'border-gray-200'}`}>
      <div className="flex items-start justify-between mb-4">
        <div className={`p-3 rounded-lg ${colorClass}`}>
          <Bot size={24} />
        </div>
        <span className={`px-2 py-1 text-xs rounded-full ${
          isActive ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
        }`}>
          {isActive ? 'Active' : 'Inactive'}
        </span>
      </div>

      <h3 className="text-lg font-semibold text-gray-800 capitalize mb-1">{agent.name}</h3>

      {agent.current_task && (
        <p className="text-sm text-gray-600 mb-3 flex items-center gap-1">
          <Zap size={14} className="text-blue-500" />
          {agent.current_task}
        </p>
      )}

      {agent.capabilities && agent.capabilities.length > 0 && (
        <div className="mb-4">
          <p className="text-xs text-gray-500 mb-2">Capabilities:</p>
          <div className="flex flex-wrap gap-1">
            {agent.capabilities.slice(0, 4).map((cap) => (
              <span key={cap} className="px-2 py-0.5 text-xs bg-gray-100 text-gray-600 rounded">
                {cap}
              </span>
            ))}
            {agent.capabilities.length > 4 && (
              <span className="px-2 py-0.5 text-xs bg-gray-100 text-gray-600 rounded">
                +{agent.capabilities.length - 4}
              </span>
            )}
          </div>
        </div>
      )}

      <div className="flex gap-2 mt-auto pt-4 border-t border-gray-100">
        {isActive ? (
          <button
            onClick={onDeactivate}
            disabled={isLoading}
            className="flex-1 px-4 py-2 bg-gray-200 text-gray-800 rounded-lg hover:bg-gray-300 transition-colors font-medium flex items-center justify-center gap-2 text-sm"
          >
            <PowerOff size={16} />
            {isLoading ? 'Deactivating...' : 'Deactivate'}
          </button>
        ) : (
          <button
            onClick={onActivate}
            disabled={isLoading}
            className="flex-1 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium flex items-center justify-center gap-2 text-sm"
          >
            <Power size={16} />
            {isLoading ? 'Activating...' : 'Activate'}
          </button>
        )}
        <button className="p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg">
          <Settings size={18} />
        </button>
      </div>
    </div>
  )
}
