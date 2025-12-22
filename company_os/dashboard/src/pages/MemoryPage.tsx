import { useEffect, useState, useRef, useCallback } from 'react'
import { Search, Brain, Lightbulb, GitBranch, BookOpen, Plus } from 'lucide-react'
import { memoryApi } from '@/services/api'
import type { Memory, MemoryContext } from '@/types'

const typeIcons: Record<Memory['type'], typeof Brain> = {
  decision: GitBranch,
  discovery: Lightbulb,
  learning: BookOpen,
  context: Brain,
}

const typeColors: Record<Memory['type'], string> = {
  decision: 'bg-purple-100 text-purple-700',
  discovery: 'bg-yellow-100 text-yellow-700',
  learning: 'bg-blue-100 text-blue-700',
  context: 'bg-green-100 text-green-700',
}

export function MemoryPage() {
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<Memory[]>([])
  const [context, setContext] = useState<MemoryContext | null>(null)
  const [isSearching, setIsSearching] = useState(false)
  const [isLoadingContext, setIsLoadingContext] = useState(true)
  const [showStoreModal, setShowStoreModal] = useState(false)
  const isMountedRef = useRef(true)

  const loadContext = useCallback(async () => {
    try {
      const ctx = await memoryApi.context()
      if (isMountedRef.current) {
        setContext(ctx)
      }
    } catch (error) {
      if (isMountedRef.current) {
        console.error('Failed to load context:', error)
      }
    } finally {
      if (isMountedRef.current) {
        setIsLoadingContext(false)
      }
    }
  }, [])

  useEffect(() => {
    isMountedRef.current = true
    loadContext()
    return () => {
      isMountedRef.current = false
    }
  }, [loadContext])

  const handleSearch = async () => {
    if (!searchQuery.trim()) return
    setIsSearching(true)
    try {
      const results = await memoryApi.search(searchQuery)
      setSearchResults(results)
    } catch (error) {
      console.error('Search failed:', error)
    } finally {
      setIsSearching(false)
    }
  }

  const handleStore = async (content: string, type: Memory['type']) => {
    try {
      await memoryApi.store(content, type)
      setShowStoreModal(false)
      await loadContext()
    } catch (error) {
      console.error('Failed to store memory:', error)
    }
  }

  if (isLoadingContext) {
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
          <h1 className="text-2xl font-bold text-gray-800">Memory & Context</h1>
          <p className="text-gray-500 mt-1">Search and manage semantic memory</p>
        </div>
        <button onClick={() => setShowStoreModal(true)} className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium flex items-center gap-2">
          <Plus size={18} />
          <span>Store Memory</span>
        </button>
      </div>

      {/* Search */}
      <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
        <div className="flex gap-3">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={20} />
            <input
              type="text"
              placeholder="Search memories..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
              className="input pl-10"
            />
          </div>
          <button onClick={handleSearch} disabled={isSearching} className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium">
            {isSearching ? 'Searching...' : 'Search'}
          </button>
        </div>

        {/* Search Results */}
        {searchResults.length > 0 && (
          <div className="mt-4 space-y-3">
            <h3 className="text-sm font-medium text-gray-700">Search Results ({searchResults.length})</h3>
            {searchResults.map((memory) => (
              <MemoryCard key={memory.id} memory={memory} />
            ))}
          </div>
        )}
      </div>

      {/* Context Sections */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent Memories */}
        <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
          <h3 className="text-lg font-semibold text-gray-800 mb-4 flex items-center gap-2">
            <Brain size={20} className="text-gray-400" />
            Recent Memories
          </h3>
          <div className="space-y-3">
            {context?.recent_memories && context.recent_memories.length > 0 ? (
              context.recent_memories.map((memory) => (
                <MemoryCard key={memory.id} memory={memory} compact />
              ))
            ) : (
              <p className="text-gray-500 text-center py-4">No recent memories</p>
            )}
          </div>
        </div>

        {/* Decisions */}
        <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
          <h3 className="text-lg font-semibold text-gray-800 mb-4 flex items-center gap-2">
            <GitBranch size={20} className="text-gray-400" />
            Recent Decisions
          </h3>
          <div className="space-y-3">
            {context?.decisions && context.decisions.length > 0 ? (
              context.decisions.map((memory) => (
                <MemoryCard key={memory.id} memory={memory} compact />
              ))
            ) : (
              <p className="text-gray-500 text-center py-4">No decisions recorded</p>
            )}
          </div>
        </div>
      </div>

      {/* Store Modal */}
      {showStoreModal && (
        <StoreMemoryModal onClose={() => setShowStoreModal(false)} onStore={handleStore} />
      )}
    </div>
  )
}

function MemoryCard({ memory, compact = false }: { memory: Memory; compact?: boolean }) {
  const Icon = typeIcons[memory.type]

  return (
    <div className={`p-3 bg-gray-50 rounded-lg ${compact ? '' : 'border border-gray-200'}`}>
      <div className="flex items-start gap-3">
        <div className={`p-2 rounded-lg ${typeColors[memory.type]}`}>
          <Icon size={16} />
        </div>
        <div className="flex-1 min-w-0">
          <p className={`text-gray-800 ${compact ? 'text-sm line-clamp-2' : ''}`}>{memory.content}</p>
          <div className="flex items-center gap-3 mt-2 text-xs text-gray-500">
            <span className="capitalize">{memory.type}</span>
            <span>Relevance: {(memory.relevance_score * 100).toFixed(0)}%</span>
            <span>{new Date(memory.created_at).toLocaleDateString()}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

function StoreMemoryModal({ onClose, onStore }: { onClose: () => void; onStore: (content: string, type: Memory['type']) => void }) {
  const [content, setContent] = useState('')
  const [type, setType] = useState<Memory['type']>('context')

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onStore(content, type)
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-md p-6">
        <h2 className="text-xl font-bold text-gray-800 mb-4">Store Memory</h2>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Content</label>
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none min-h-[120px]"
              placeholder="Enter memory content..."
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Type</label>
            <select value={type} onChange={(e) => setType(e.target.value as Memory['type'])} className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none">
              <option value="context">Context</option>
              <option value="decision">Decision</option>
              <option value="discovery">Discovery</option>
              <option value="learning">Learning</option>
            </select>
          </div>
          <div className="flex gap-3 pt-4">
            <button type="button" onClick={onClose} className="px-4 py-2 bg-gray-200 text-gray-800 rounded-lg hover:bg-gray-300 transition-colors font-medium flex-1">Cancel</button>
            <button type="submit" className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium flex-1">Store</button>
          </div>
        </form>
      </div>
    </div>
  )
}
