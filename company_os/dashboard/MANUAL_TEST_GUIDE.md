# Company OS Dashboard - Manual E2E Test Guide

This guide provides step-by-step instructions for manually testing the Company OS Dashboard when automated test execution is not available.

## Prerequisites

Ensure both servers are running:

```bash
# Terminal 1 - Backend API
cd /home/lab2208/Documents/universal-workflow-system/company_os
python -m uvicorn company_os.main:app --host 0.0.0.0 --port 8000

# Terminal 2 - Frontend
cd /home/lab2208/Documents/universal-workflow-system/company_os/dashboard
npm run dev
```

Verify servers:
- Backend: http://localhost:8000/health should return `{"status":"healthy","version":"0.1.0-mock"}`
- Frontend: http://localhost:5173 should load the application

## Running Automated Tests

To run the Playwright E2E tests (if browsers are installed):

```bash
cd /home/lab2208/Documents/universal-workflow-system/company_os/dashboard

# Install Playwright browsers (first time only)
npx playwright install chromium --with-deps

# Run all tests
npm run test:e2e

# Run specific test file
npx playwright test e2e/login.spec.ts

# Run tests with visible browser
npm run test:e2e:headed

# Run tests in interactive UI mode
npm run test:e2e:ui

# View HTML report after tests complete
npm run test:e2e:report
```

## Manual Testing Checklist

### Test 1: Login Flow

**Steps:**
1. Open browser to http://localhost:5173
2. Verify redirect to `/login` page
3. Check login form elements are visible:
   - Email input field
   - Password input field
   - Login button
4. Enter credentials:
   - Email: `test@example.com`
   - Password: `password123`
5. Click "Login" button
6. Verify redirect to dashboard (`/`)
7. Verify "Dashboard" heading is visible

**Expected Results:**
- ✅ Unauthenticated users redirected to login
- ✅ Valid credentials allow successful login
- ✅ User redirected to dashboard after login

**Issues Found:** _____________________________

---

### Test 2: Dashboard Page

**Steps:**
1. After logging in, verify you're on the Dashboard page
2. Check for stats cards with the following titles:
   - "Total Tasks"
   - "Completed"
   - "Active Agents"
   - "Memory Items"
3. Verify each card displays a number
4. Scroll down to find "Recent Tasks" section
5. Check "Agent Status" section is visible
6. Look for connection status indicator (top-right corner):
   - Should show "Live" with green background if connected
   - Or "Offline" with gray background if disconnected
7. If WebSocket is connected, check for "Live Events" section at bottom

**Expected Results:**
- ✅ Four stat cards visible with numeric values
- ✅ Recent Tasks section shows tasks or "No tasks yet"
- ✅ Agent Status section shows agents or "No agents configured"
- ✅ Connection status indicator visible
- ✅ Page is responsive on mobile (resize browser)

**Issues Found:** _____________________________

---

### Test 3: Tasks Page

**Steps:**
1. Click "Tasks" in the sidebar navigation
2. Verify URL changes to `/tasks`
3. Verify "Tasks" heading is visible
4. Look for search input field (if implemented)
5. Look for status filter dropdown (if implemented)
6. Click "New Task" button
7. Verify modal/dialog opens
8. Fill in task form:
   - Title: "E2E Test Task"
   - Description: "Testing the task creation"
9. Click Submit/Create button
10. Verify task appears in the list or success message shown
11. Check if task actions are available (Edit, Delete, Complete buttons)
12. Reload the page and verify tasks persist

**Expected Results:**
- ✅ Navigation to Tasks page works
- ✅ Task list is displayed
- ✅ New Task button opens creation modal
- ✅ Task can be created successfully
- ✅ Tasks persist after page reload

**Issues Found:** _____________________________

---

### Test 4: Agents Page

**Steps:**
1. Click "Agents" in the sidebar navigation
2. Verify URL changes to `/agents`
3. Verify "Agents" heading is visible
4. Check for agent cards/items displaying:
   - Agent names (researcher, architect, implementer, etc.)
   - Status indicators (active/inactive)
   - Status badges
5. Look for "Activate" or "Deactivate" buttons
6. Click an activation button
7. Verify status changes or confirmation shown
8. Check for agent capabilities or description
9. Verify page shows agent metrics/stats
10. Resize browser to mobile width and verify responsive design

**Expected Results:**
- ✅ Navigation to Agents page works
- ✅ Agent cards display with correct information
- ✅ Agent status indicators visible
- ✅ Activate/deactivate buttons functional
- ✅ Multiple agent types shown
- ✅ Responsive on mobile

**Issues Found:** _____________________________

---

### Test 5: Memory Page

**Steps:**
1. Click "Memory" in the sidebar navigation
2. Verify URL changes to `/memory`
3. Verify "Memory" heading is visible
4. Look for search input field (if implemented)
5. Check for memory item cards/list
6. Verify each item shows:
   - Content or key/value pairs
   - Metadata (timestamp, type, etc.)
7. Look for filter or sort controls
8. Check for action buttons (View, Edit, Delete)
9. Verify page handles empty state gracefully
10. Reload page and verify memory items persist

**Expected Results:**
- ✅ Navigation to Memory page works
- ✅ Memory items displayed or empty state shown
- ✅ Item details and metadata visible
- ✅ Search functionality works (if present)
- ✅ State persists after reload
- ✅ Responsive design

**Issues Found:** _____________________________

---

### Test 6: Navigation Testing

**Steps:**
1. From Dashboard, click "Tasks" in sidebar
   - Verify URL: `/tasks`
   - Verify "Tasks" is highlighted in sidebar
2. Click "Agents" in sidebar
   - Verify URL: `/agents`
   - Verify "Agents" is highlighted in sidebar
3. Click "Memory" in sidebar
   - Verify URL: `/memory`
   - Verify "Memory" is highlighted in sidebar
4. Click "Dashboard" in sidebar
   - Verify URL: `/`
   - Verify "Dashboard" is highlighted
5. Use browser back button
   - Verify navigation back through pages works
6. Use browser forward button
   - Verify navigation forward works
7. Manually type `/tasks` in address bar
   - Verify direct URL navigation works
8. Navigate to `/invalid-route-123`
   - Verify 404 handling or redirect
9. Test keyboard navigation:
   - Press Tab repeatedly
   - Use Enter to activate links
10. Resize to mobile width (375px)
    - Check if hamburger menu appears
    - Test mobile navigation

**Expected Results:**
- ✅ All navigation links work
- ✅ Active page is highlighted in sidebar
- ✅ Browser back/forward buttons work
- ✅ Direct URL navigation works
- ✅ Authentication persists across pages
- ✅ 404 routes handled gracefully
- ✅ Keyboard navigation functional
- ✅ Mobile navigation works

**Issues Found:** _____________________________

---

### Test 7: Logout Flow

**Steps:**
1. From any page, locate "Logout" button in sidebar (bottom)
2. Click "Logout" button
3. Verify redirect to `/login` page
4. Try to navigate to `/` directly
5. Verify redirect back to `/login` (authentication check)
6. Try to navigate to `/tasks` directly
7. Verify redirect back to `/login`

**Expected Results:**
- ✅ Logout button visible in sidebar
- ✅ Clicking logout redirects to login page
- ✅ Authentication is cleared
- ✅ Protected routes redirect to login

**Issues Found:** _____________________________

---

## Test Summary

Date: _______________
Tester: _______________

| Test Suite | Pass | Fail | Notes |
|------------|------|------|-------|
| Login Flow | ☐ | ☐ | |
| Dashboard Page | ☐ | ☐ | |
| Tasks Page | ☐ | ☐ | |
| Agents Page | ☐ | ☐ | |
| Memory Page | ☐ | ☐ | |
| Navigation | ☐ | ☐ | |
| Logout Flow | ☐ | ☐ | |

**Total Tests:** 7
**Passed:** _______
**Failed:** _______
**Pass Rate:** _______%

## Common Issues to Check

- [ ] CORS errors in browser console
- [ ] API connection failures (check Network tab)
- [ ] WebSocket connection issues
- [ ] Authentication token persistence
- [ ] Mobile responsive layout issues
- [ ] Console errors or warnings
- [ ] Missing error handling
- [ ] Loading states not showing
- [ ] Empty states not handled

## Browser Compatibility

Test in multiple browsers:
- [ ] Chrome/Chromium (primary)
- [ ] Firefox
- [ ] Safari
- [ ] Edge

## Performance Checks

- [ ] Page loads in < 2 seconds
- [ ] No memory leaks (check DevTools Memory)
- [ ] Smooth navigation transitions
- [ ] API responses in < 500ms
- [ ] WebSocket maintains connection

## Accessibility Checks

- [ ] Keyboard navigation works
- [ ] Focus indicators visible
- [ ] Color contrast sufficient
- [ ] Screen reader compatible (use NVDA/JAWS)
- [ ] ARIA labels present

## Next Steps After Testing

1. Document all issues found in detail
2. Create GitHub issues for bugs
3. Prioritize fixes based on severity
4. Re-test after fixes are implemented
5. Run automated Playwright tests for regression testing

## Automated Test Execution Log

If you ran the automated tests, paste results here:

```
[Paste npx playwright test output here]
```

## Additional Notes

_____________________________________________
_____________________________________________
_____________________________________________
_____________________________________________
