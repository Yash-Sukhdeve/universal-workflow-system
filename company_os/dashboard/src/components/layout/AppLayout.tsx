import { Outlet, useLocation } from 'react-router-dom'
import { Sidebar } from './Sidebar'
import { Header } from './Header'
import { useAuth } from '@/contexts/AuthContext'

const pageTitles: Record<string, string> = {
  '/': 'Dashboard',
  '/tasks': 'Tasks',
  '/agents': 'Agents',
  '/memory': 'Memory',
  '/settings': 'Settings',
}

export function AppLayout() {
  const location = useLocation()
  const { user, logout } = useAuth()
  const title = pageTitles[location.pathname] || 'Company OS'

  return (
    <div className="flex h-screen bg-gray-100">
      <Sidebar onLogout={logout} />

      <div className="flex-1 flex flex-col overflow-hidden">
        <Header title={title} user={user || undefined} />

        <main className="flex-1 overflow-auto p-6">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
