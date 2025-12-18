import { useEffect, useState, useRef, useCallback } from 'react'
import { Plus, Search, MoreVertical, CheckCircle, Circle, Clock, AlertTriangle, RefreshCw } from 'lucide-react'
import { tasksApi } from '@/services/api'
import { useWebSocketContext } from '@/contexts/WebSocketContext'
import type { Task, CreateTaskInput } from '@/types'

const statusIcons: Record<Task['status'], typeof Circle> = {
  pending: Circle,
  in_progress: Clock,
  completed: CheckCircle,
  blocked: AlertTriangle,
}

const statusColors: Record<Task['status'], string> = {
  pending: 'text-gray-400',
  in_progress: 'text-blue-500',
  completed: 'text-green-500',
  blocked: 'text-red-500',
}

export function TasksPage() {
  const [tasks, setTasks] = useState<Task[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<Task['status'] | 'all'>('all')
  const [showCreateModal, setShowCreateModal] = useState(false)
  const { taskEvents, isConnected } = useWebSocketContext()
  const isMountedRef = useRef(true)

  const loadTasks = useCallback(async () => {
    try {
      const response = await tasksApi.list(1, 50)
      if (isMountedRef.current) {
        setTasks(response.items || [])
      }
    } catch (error) {
      if (isMountedRef.current) {
        console.error('Failed to load tasks:', error)
      }
    } finally {
      if (isMountedRef.current) {
        setIsLoading(false)
      }
    }
  }, [])

  useEffect(() => {
    isMountedRef.current = true
    loadTasks()
    return () => {
      isMountedRef.current = false
    }
  }, [loadTasks])

  // Refresh tasks when we receive WebSocket task updates
  useEffect(() => {
    if (taskEvents.length > 0 && isMountedRef.current) {
      loadTasks()
    }
  }, [taskEvents.length, loadTasks])

  const filteredTasks = tasks.filter((task) => {
    const matchesSearch = task.title.toLowerCase().includes(searchQuery.toLowerCase())
    const matchesStatus = statusFilter === 'all' || task.status === statusFilter
    return matchesSearch && matchesStatus
  })

  const handleCreateTask = async (input: CreateTaskInput) => {
    try {
      const newTask = await tasksApi.create(input)
      setTasks([newTask, ...tasks])
      setShowCreateModal(false)
    } catch (error) {
      console.error('Failed to create task:', error)
    }
  }

  const handleCompleteTask = async (taskId: string) => {
    try {
      const updated = await tasksApi.complete(taskId)
      setTasks(tasks.map((t) => (t.id === taskId ? updated : t)))
    } catch (error) {
      console.error('Failed to complete task:', error)
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
        <div className="flex items-center gap-4 flex-1">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={20} />
            <input
              type="text"
              placeholder="Search tasks..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="input pl-10"
            />
          </div>
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as Task['status'] | 'all')}
            className="input w-auto"
          >
            <option value="all">All Status</option>
            <option value="pending">Pending</option>
            <option value="in_progress">In Progress</option>
            <option value="completed">Completed</option>
            <option value="blocked">Blocked</option>
          </select>
        </div>
        <div className="flex items-center gap-2">
          {isConnected && (
            <span className="flex items-center gap-1 text-xs text-green-600 bg-green-100 px-2 py-1 rounded-full">
              <RefreshCw size={12} className="animate-spin" />
              Live
            </span>
          )}
          <button onClick={() => setShowCreateModal(true)} className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium flex items-center gap-2">
            <Plus size={18} />
            <span>New Task</span>
          </button>
        </div>
      </div>

      {/* Tasks List */}
      <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-gray-200">
                <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Status</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Title</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Priority</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Assigned</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Updated</th>
                <th className="py-3 px-4"></th>
              </tr>
            </thead>
            <tbody>
              {filteredTasks.length > 0 ? (
                filteredTasks.map((task) => {
                  const StatusIcon = statusIcons[task.status]
                  return (
                    <tr key={task.id} className="border-b border-gray-100 hover:bg-gray-50">
                      <td className="py-3 px-4">
                        <button
                          onClick={() => task.status !== 'completed' && handleCompleteTask(task.id)}
                          className={`${statusColors[task.status]} hover:opacity-70`}
                          disabled={task.status === 'completed'}
                        >
                          <StatusIcon size={20} />
                        </button>
                      </td>
                      <td className="py-3 px-4">
                        <p className="font-medium text-gray-800">{task.title}</p>
                        <p className="text-sm text-gray-500 truncate max-w-xs">{task.description}</p>
                      </td>
                      <td className="py-3 px-4">
                        <span className={`px-2 py-1 text-xs rounded-full ${
                          task.priority === 'critical' ? 'bg-red-100 text-red-700' :
                          task.priority === 'high' ? 'bg-orange-100 text-orange-700' :
                          task.priority === 'medium' ? 'bg-yellow-100 text-yellow-700' :
                          'bg-green-100 text-green-700'
                        }`}>
                          {task.priority}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-sm text-gray-500">
                        {task.assigned_to || '-'}
                      </td>
                      <td className="py-3 px-4 text-sm text-gray-500">
                        {new Date(task.updated_at).toLocaleDateString()}
                      </td>
                      <td className="py-3 px-4">
                        <button className="text-gray-400 hover:text-gray-600">
                          <MoreVertical size={18} />
                        </button>
                      </td>
                    </tr>
                  )
                })
              ) : (
                <tr>
                  <td colSpan={6} className="py-8 text-center text-gray-500">
                    No tasks found
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Create Task Modal */}
      {showCreateModal && (
        <CreateTaskModal
          onClose={() => setShowCreateModal(false)}
          onCreate={handleCreateTask}
        />
      )}
    </div>
  )
}

function CreateTaskModal({ onClose, onCreate }: { onClose: () => void; onCreate: (input: CreateTaskInput) => void }) {
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [priority, setPriority] = useState<Task['priority']>('medium')

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onCreate({ title, description, priority })
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-md p-6">
        <h2 className="text-xl font-bold text-gray-800 mb-4">Create New Task</h2>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Title</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none min-h-[100px]"
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Priority</label>
            <select value={priority} onChange={(e) => setPriority(e.target.value as Task['priority'])} className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none">
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="critical">Critical</option>
            </select>
          </div>
          <div className="flex gap-3 pt-4">
            <button type="button" onClick={onClose} className="px-4 py-2 bg-gray-200 text-gray-800 rounded-lg hover:bg-gray-300 transition-colors font-medium flex-1">Cancel</button>
            <button type="submit" className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium flex-1">Create Task</button>
          </div>
        </form>
      </div>
    </div>
  )
}
