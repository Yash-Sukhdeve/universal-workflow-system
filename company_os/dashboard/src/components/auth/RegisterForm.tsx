import { useState, useMemo } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'
import { UserPlus, AlertCircle, CheckCircle, XCircle } from 'lucide-react'

// SECURITY: Password validation requirements
const PASSWORD_REQUIREMENTS = {
  minLength: 12,
  requireUppercase: true,
  requireLowercase: true,
  requireNumber: true,
  requireSpecial: true,
} as const

interface PasswordValidation {
  isValid: boolean
  errors: string[]
  checks: {
    length: boolean
    uppercase: boolean
    lowercase: boolean
    number: boolean
    special: boolean
  }
}

// SECURITY: Validate password strength
function validatePassword(password: string): PasswordValidation {
  const checks = {
    length: password.length >= PASSWORD_REQUIREMENTS.minLength,
    uppercase: /[A-Z]/.test(password),
    lowercase: /[a-z]/.test(password),
    number: /[0-9]/.test(password),
    special: /[^A-Za-z0-9]/.test(password),
  }

  const errors: string[] = []
  if (!checks.length) errors.push(`At least ${PASSWORD_REQUIREMENTS.minLength} characters`)
  if (!checks.uppercase) errors.push('One uppercase letter')
  if (!checks.lowercase) errors.push('One lowercase letter')
  if (!checks.number) errors.push('One number')
  if (!checks.special) errors.push('One special character (!@#$%^&*)')

  return {
    isValid: Object.values(checks).every(Boolean),
    errors,
    checks,
  }
}

// SECURITY: Validate email format
function validateEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  return emailRegex.test(email)
}

export function RegisterForm() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [showPasswordRequirements, setShowPasswordRequirements] = useState(false)
  const { register } = useAuth()
  const navigate = useNavigate()

  // SECURITY: Real-time password validation
  const passwordValidation = useMemo(() => validatePassword(password), [password])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')

    // SECURITY: Validate email format
    if (!validateEmail(email)) {
      setError('Please enter a valid email address')
      return
    }

    // SECURITY: Validate password strength
    if (!passwordValidation.isValid) {
      setError('Password does not meet security requirements')
      return
    }

    if (password !== confirmPassword) {
      setError('Passwords do not match')
      return
    }

    setIsLoading(true)

    try {
      await register(email, password)
      navigate('/')
    } catch (err) {
      setError('Registration failed. Email may already be in use.')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-100">
      <div className="max-w-md w-full">
        <div className="bg-white rounded-lg shadow-lg p-8">
          <div className="text-center mb-8">
            <h1 className="text-2xl font-bold text-gray-800">Company OS</h1>
            <p className="text-gray-500 mt-2">Create your account</p>
          </div>

          {error && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg flex items-center gap-2 text-red-700">
              <AlertCircle size={18} />
              <span className="text-sm">{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
                Email
              </label>
              <input
                type="email"
                id="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                placeholder="you@example.com"
                required
              />
            </div>

            <div>
              <label htmlFor="password" className="block text-sm font-medium text-gray-700 mb-1">
                Password
              </label>
              <input
                type="password"
                id="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                onFocus={() => setShowPasswordRequirements(true)}
                onBlur={() => setShowPasswordRequirements(false)}
                className={`w-full px-3 py-2 border rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none ${
                  password && !passwordValidation.isValid ? 'border-red-300' : 'border-gray-300'
                }`}
                placeholder="At least 12 characters"
                required
                minLength={12}
                aria-describedby="password-requirements"
                aria-invalid={password.length > 0 && !passwordValidation.isValid}
              />
              {/* SECURITY: Password strength indicator */}
              {(showPasswordRequirements || password.length > 0) && (
                <div id="password-requirements" className="mt-2 p-3 bg-gray-50 rounded-lg text-sm">
                  <p className="font-medium text-gray-700 mb-2">Password requirements:</p>
                  <ul className="space-y-1">
                    <li className={`flex items-center gap-2 ${passwordValidation.checks.length ? 'text-green-600' : 'text-gray-500'}`}>
                      {passwordValidation.checks.length ? <CheckCircle size={14} /> : <XCircle size={14} />}
                      At least 12 characters
                    </li>
                    <li className={`flex items-center gap-2 ${passwordValidation.checks.uppercase ? 'text-green-600' : 'text-gray-500'}`}>
                      {passwordValidation.checks.uppercase ? <CheckCircle size={14} /> : <XCircle size={14} />}
                      One uppercase letter
                    </li>
                    <li className={`flex items-center gap-2 ${passwordValidation.checks.lowercase ? 'text-green-600' : 'text-gray-500'}`}>
                      {passwordValidation.checks.lowercase ? <CheckCircle size={14} /> : <XCircle size={14} />}
                      One lowercase letter
                    </li>
                    <li className={`flex items-center gap-2 ${passwordValidation.checks.number ? 'text-green-600' : 'text-gray-500'}`}>
                      {passwordValidation.checks.number ? <CheckCircle size={14} /> : <XCircle size={14} />}
                      One number
                    </li>
                    <li className={`flex items-center gap-2 ${passwordValidation.checks.special ? 'text-green-600' : 'text-gray-500'}`}>
                      {passwordValidation.checks.special ? <CheckCircle size={14} /> : <XCircle size={14} />}
                      One special character (!@#$%^&*)
                    </li>
                  </ul>
                </div>
              )}
            </div>

            <div>
              <label htmlFor="confirmPassword" className="block text-sm font-medium text-gray-700 mb-1">
                Confirm Password
              </label>
              <input
                type="password"
                id="confirmPassword"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                placeholder="Re-enter your password"
                required
              />
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="w-full px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium flex items-center justify-center gap-2"
            >
              {isLoading ? (
                <span>Creating account...</span>
              ) : (
                <>
                  <UserPlus size={18} />
                  <span>Create Account</span>
                </>
              )}
            </button>
          </form>

          <p className="mt-6 text-center text-sm text-gray-500">
            Already have an account?{' '}
            <Link to="/login" className="text-blue-600 hover:text-blue-700 font-medium">
              Sign in
            </Link>
          </p>
        </div>
      </div>
    </div>
  )
}
