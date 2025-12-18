import { User, Bell, Shield } from 'lucide-react'
import { useAuth } from '@/contexts/AuthContext'

export function SettingsPage() {
  const { user } = useAuth()

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h1 className="text-2xl font-bold text-gray-800">Settings</h1>
        <p className="text-gray-500 mt-1">Manage your account and preferences</p>
      </div>

      {/* Profile Section */}
      <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
        <div className="flex items-center gap-3 mb-4">
          <User size={20} className="text-gray-400" />
          <h2 className="text-lg font-semibold text-gray-800">Profile</h2>
        </div>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
            <input
              type="email"
              value={user?.email || ''}
              disabled
              className="input bg-gray-50"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Role</label>
            <input
              type="text"
              value={user?.role || ''}
              disabled
              className="input bg-gray-50 capitalize"
            />
          </div>
        </div>
      </div>

      {/* Notifications */}
      <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
        <div className="flex items-center gap-3 mb-4">
          <Bell size={20} className="text-gray-400" />
          <h2 className="text-lg font-semibold text-gray-800">Notifications</h2>
        </div>
        <div className="space-y-3">
          <label className="flex items-center justify-between p-3 bg-gray-50 rounded-lg cursor-pointer">
            <div>
              <p className="font-medium text-gray-800">Task Updates</p>
              <p className="text-sm text-gray-500">Get notified when tasks are updated</p>
            </div>
            <input type="checkbox" defaultChecked className="w-5 h-5 text-blue-600 rounded" />
          </label>
          <label className="flex items-center justify-between p-3 bg-gray-50 rounded-lg cursor-pointer">
            <div>
              <p className="font-medium text-gray-800">Agent Activity</p>
              <p className="text-sm text-gray-500">Get notified when agents change status</p>
            </div>
            <input type="checkbox" defaultChecked className="w-5 h-5 text-blue-600 rounded" />
          </label>
        </div>
      </div>

      {/* Security */}
      <div className="bg-white rounded-lg shadow-md border border-gray-200 p-4">
        <div className="flex items-center gap-3 mb-4">
          <Shield size={20} className="text-gray-400" />
          <h2 className="text-lg font-semibold text-gray-800">Security</h2>
        </div>
        <button className="px-4 py-2 bg-gray-200 text-gray-800 rounded-lg hover:bg-gray-300 transition-colors font-medium">Change Password</button>
      </div>
    </div>
  )
}
