import { useEffect, useState } from 'react'
import { Activity, CheckSquare, Users, Brain, TrendingUp, Clock, Wifi, WifiOff } from 'lucide-react'
import { tasksApi, agentsApi } from '@/services/api'
import { useWebSocketContext } from '@/contexts/WebSocketContext'
import type { Task, Agent, WSEvent } from '@/types'

interface DashboardStats {
  totalTasks: number
  completedTasks: number
  activeAgents: number
  recentMemories: number
}

function StatCard({ title, value, icon: Icon, trend }: { title: string; value: number | string; icon: typeof Activity; trend?: string }) {
  return (
    <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-gray-500">{title}</p>
          <p className="text-2xl font-bold text-gray-800 mt-1">{value}</p>
          {trend && <p className="text-xs text-green-500 mt-1">{trend}</p>}
        </div>
        <div className="w-12 h-12 bg-blue-100 text-blue-600 rounded-lg flex items-center justify-center">
          <Icon size={24} />
        </div>
      </div>
    </div>
  )
}

export function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats>({ totalTasks: 0, completedTasks: 0, activeAgents: 0, recentMemories: 0 })
  const [recentTasks, setRecentTasks] = useState<Task[]>([])
  const [agents, setAgents] = useState<Agent[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const { isConnected, taskEvents, agentEvents, memoryEvents } = useWebSocketContext()

  // Combine recent events for live feed
  const allEvents: WSEvent[] = [...taskEvents, ...agentEvents, ...memoryEvents]
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
    .slice(0, 10)

  useEffect(() => {
    let isMounted = true

    const loadDashboard = async () => {
      try {
        const [tasksRes, agentsList] = await Promise.all([
          tasksApi.list(1, 5),
          agentsApi.list(),
        ])

        // Prevent state updates if component unmounted
        if (!isMounted) return

        setRecentTasks(tasksRes.items || [])
        setAgents(agentsList || [])

        const completed = (tasksRes.items || []).filter((t: Task) => t.status === 'completed').length
        const active = (agentsList || []).filter((a: Agent) => a.status === 'active').length

        setStats({
          totalTasks: tasksRes.total || 0,
          completedTasks: completed,
          activeAgents: active,
          recentMemories: memoryEvents.length,
        })
      } catch (error) {
        if (!isMounted) return
        console.error('Failed to load dashboard:', error)
      } finally {
        if (isMounted) setIsLoading(false)
      }
    }

    loadDashboard()

    return () => {
      isMounted = false
    }
  }, [memoryEvents.length])

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Connection Status */}
      <div className="flex items-center justify-end">
        <div className={`flex items-center gap-2 px-3 py-1 rounded-full text-sm ${
          isConnected ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
        }`}>
          {isConnected ? <Wifi size={16} /> : <WifiOff size={16} />}
          {isConnected ? 'Live' : 'Offline'}
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard title="Total Tasks" value={stats.totalTasks} icon={CheckSquare} />
        <StatCard title="Completed" value={stats.completedTasks} icon={TrendingUp} trend="+12% this week" />
        <StatCard title="Active Agents" value={stats.activeAgents} icon={Users} />
        <StatCard title="Memory Items" value={stats.recentMemories} icon={Brain} />
      </div>

      {/* Recent Activity */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent Tasks */}
        <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
          <h3 className="text-lg font-semibold text-gray-800 mb-4 flex items-center gap-2">
            <Clock size={20} className="text-gray-400" />
            Recent Tasks
          </h3>
          <div className="space-y-3">
            {recentTasks.length > 0 ? (
              recentTasks.map((task) => (
                <div key={task.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div>
                    <p className="font-medium text-gray-800">{task.title}</p>
                    <p className="text-sm text-gray-500">{task.status}</p>
                  </div>
                  <span className={`px-2 py-1 text-xs rounded-full ${
                    task.priority === 'high' || task.priority === 'critical'
                      ? 'bg-red-100 text-red-700'
                      : task.priority === 'medium'
                      ? 'bg-yellow-100 text-yellow-700'
                      : 'bg-green-100 text-green-700'
                  }`}>
                    {task.priority}
                  </span>
                </div>
              ))
            ) : (
              <p className="text-gray-500 text-center py-4">No tasks yet</p>
            )}
          </div>
        </div>

        {/* Agent Status */}
        <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
          <h3 className="text-lg font-semibold text-gray-800 mb-4 flex items-center gap-2">
            <Activity size={20} className="text-gray-400" />
            Agent Status
          </h3>
          <div className="space-y-3">
            {agents.length > 0 ? (
              agents.map((agent) => (
                <div key={agent.name} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div className="flex items-center gap-3">
                    <div className={`w-3 h-3 rounded-full ${agent.status === 'active' ? 'bg-green-500' : 'bg-gray-300'}`}></div>
                    <div>
                      <p className="font-medium text-gray-800 capitalize">{agent.name}</p>
                      <p className="text-sm text-gray-500">{agent.current_task || 'Idle'}</p>
                    </div>
                  </div>
                  <span className={`px-2 py-1 text-xs rounded-full ${
                    agent.status === 'active' ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
                  }`}>
                    {agent.status}
                  </span>
                </div>
              ))
            ) : (
              <p className="text-gray-500 text-center py-4">No agents configured</p>
            )}
          </div>
        </div>
      </div>

      {/* Live Event Feed */}
      {allEvents.length > 0 && (
        <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
          <h3 className="text-lg font-semibold text-gray-800 mb-4 flex items-center gap-2">
            <Activity size={20} className="text-green-500" />
            Live Events
          </h3>
          <div className="space-y-2">
            {allEvents.map((event, idx) => (
              <div key={`${event.type}-${event.timestamp}-${idx}`} className="flex items-center gap-3 p-2 bg-gray-50 rounded text-sm">
                <div className={`w-2 h-2 rounded-full ${
                  event.type === 'task_updated' ? 'bg-blue-500' :
                  event.type === 'agent_status' ? 'bg-green-500' :
                  event.type === 'memory_stored' ? 'bg-purple-500' :
                  'bg-gray-500'
                }`} />
                <span className="text-gray-600 capitalize">{event.type.replace('_', ' ')}</span>
                <span className="text-gray-400 text-xs ml-auto">
                  {new Date(event.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
