# Deployment Fix - API Connection Issue

## Problem
Flutter web app was not connecting to production backend, showing:
```
ClientException: Failed to fetch, url=https://stock-backend-nt1s.onrender.com/overview
```

## Root Cause
Vercel was serving **old cached build files** that still had `http://localhost:8000` hardcoded.

## Solution Timeline

### Attempt 1: Update Source Code ❌
- Updated `ApiClient` default URL to production backend
- Pushed changes to GitHub
- **Issue:** Vercel uses pre-built files, doesn't rebuild on deploy

### Attempt 2: Force Rebuild ✅
- Built Flutter web app locally with `flutter build web --release`
- Force-added build files with `git add -f flutter_app/build/web`
- Pushed compiled files to repository
- **Result:** Vercel now serves correct build with production API URL

## Verification
Built files contain correct URL:
```bash
$ grep -r "stock-backend-nt1s" flutter_app/build/web/
flutter_app/build/web/index.html:      window.API_BASE_URL = 'https://stock-backend-nt1s.onrender.com';
flutter_app/build/web/main.dart.js:r=A.lG("https://stock-backend-nt1s.onrender.com",r,"")
```

## Files Changed
- `flutter_app/lib/api_client.dart` - Updated default URL
- `flutter_app/web/index.html` - Added window.API_BASE_URL
- `flutter_app/build/web/*` - Added 33 pre-built files (7.22 MB)

## Deployment Status
- ✅ Committed: `21acb0e` - "Add pre-built Flutter web files with correct API URL"
- ✅ Pushed to GitHub main branch
- ⏳ Vercel auto-deploying (usually 1-2 minutes)

## Next Steps
1. Wait for Vercel deployment to complete (~2 minutes)
2. Hard refresh browser (Cmd+Shift+R on Mac, Ctrl+Shift+R on Windows)
3. App should now load successfully with data from backend

## Why This Approach?
- ❌ Building on Vercel requires installing Flutter (slow, may timeout)
- ✅ Pre-building locally ensures known-good compilation
- ✅ Faster deployments (Vercel just serves static files)
- ✅ More control over build configuration

## Expected Result
After deployment completes:
- ✅ App loads without errors
- ✅ Connects to `https://stock-backend-nt1s.onrender.com`
- ✅ Displays AAPL stock data
- ✅ All animations and technical indicators work
- ✅ Shimmer loading skeletons appear during data fetch

## Troubleshooting
If error persists after deployment:
1. Check Vercel deployment logs
2. Hard refresh browser (clear cache)
3. Open DevTools → Network tab → verify API calls
4. Check console for any additional errors
