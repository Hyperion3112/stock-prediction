# 🚀 Local Development Guide - AI Stock Prediction App

## ✅ Application is Now Running!

Your AI Stock Prediction application is now running locally with both backend and frontend servers.

---

## 🌐 Access Your Application

### **Frontend (Flutter Web App)**
👉 **Open in your browser:** http://localhost:3000

### **Backend API (FastAPI)**
👉 **API Base:** http://127.0.0.1:8000
👉 **API Health Check:** http://127.0.0.1:8000/health
👉 **API Documentation:** http://127.0.0.1:8000/docs

---

## 📊 Available Features

### ✅ Working Features:
1. **Stock Overview** - Real-time stock data and metrics
2. **Linear Forecasting** - Price predictions using linear regression
3. **Technical Indicators** - SMA-20, SMA-50, EMA-12, EMA-26
4. **News Sentiment Analysis** - Analyze market sentiment from news
5. **Interactive Charts** - Beautiful, responsive visualizations
6. **Multiple Time Ranges** - 1M, 3M, 6M, 1Y, 2Y, 5Y
7. **Different Intervals** - 1d, 1wk, 1mo, 1h, 30m

### ⚠️ Note:
- **LSTM Forecasting** is not available in local mode (requires TensorFlow)
- The app will automatically fall back to linear regression for forecasts

---

## 🎯 Quick Test

Try these commands to test the API:

```bash
# Health check
curl http://127.0.0.1:8000/health

# Get stock overview for AAPL
curl "http://127.0.0.1:8000/overview?ticker=AAPL&preset=6M"

# Get forecast for AAPL
curl "http://127.0.0.1:8000/forecast?ticker=AAPL&days=30"

# Get sentiment analysis
curl "http://127.0.0.1:8000/sentiment?ticker=AAPL"

# List available models
curl http://127.0.0.1:8000/models
```

---

## 🛑 Stopping the Application

To stop both servers:

```bash
# Kill servers on ports 8000 and 3000
lsof -ti:8000,3000 | xargs kill -9
```

Or press `Ctrl+C` in the terminals where the servers are running.

---

## 🔄 Restarting the Application

### Start Backend:
```bash
cd "/Users/shaunak/Projects/Stock Prediction"
python3 -m uvicorn app:app --host 127.0.0.1 --port 8000 --reload
```

### Start Frontend:
```bash
cd "/Users/shaunak/Projects/Stock Prediction/flutter_app/build/web"
python3 -m http.server 3000
```

---

## 📝 Development Tips

### Backend Development:
- The backend runs with `--reload` flag, so it auto-restarts on code changes
- Check logs in the terminal for any errors
- API documentation available at: http://127.0.0.1:8000/docs

### Frontend Development:
- The frontend is serving pre-built files from `flutter_app/build/web`
- To rebuild the Flutter app after changes:
  ```bash
  cd flutter_app
  flutter build web
  ```
- API URL is configured to point to `http://127.0.0.1:8000`

### Testing Different Tickers:
Try these popular stocks:
- **AAPL** - Apple Inc.
- **NVDA** - NVIDIA Corporation
- **TSLA** - Tesla, Inc.
- **MSFT** - Microsoft Corporation
- **GOOGL** - Alphabet Inc.
- **AMZN** - Amazon.com Inc.

---

## 🐛 Troubleshooting

### "Port already in use" error:
```bash
# Find and kill the process using the port
lsof -ti:8000 | xargs kill -9  # For backend
lsof -ti:3000 | xargs kill -9  # For frontend
```

### Backend not responding:
1. Check if the backend is running: `lsof -ti:8000`
2. Check backend logs in the terminal
3. Verify dependencies are installed: `pip3 list | grep -E "fastapi|uvicorn|pandas"`

### Frontend showing errors:
1. Check browser console for errors (F12)
2. Verify API URL is set to `http://127.0.0.1:8000`
3. Check if backend is accessible: `curl http://127.0.0.1:8000/health`

### No data showing:
- Ensure you have internet connection (app fetches real-time data from Yahoo Finance)
- Try a different ticker symbol
- Check if the time range is valid for the interval

---

## 📦 Installed Dependencies

The following packages were installed for local development:
- ✅ fastapi (0.103.2)
- ✅ uvicorn (ASGI server)
- ✅ pandas (data processing)
- ✅ numpy (2.3.2)
- ✅ yfinance (stock data)
- ✅ scikit-learn (machine learning)
- ✅ joblib (model persistence)
- ✅ vaderSentiment (sentiment analysis)

---

## 🎨 UI Features

The app includes:
- 🌈 Dynamic gradient backgrounds
- 🔮 Glass morphism design
- 📈 Interactive charts with tooltips
- ⚡ Smooth animations and transitions
- 📱 Responsive layout
- 🌙 Dark theme optimized for extended use
- 💫 Loading skeletons for better UX

---

## 🚀 Production vs Local

| Feature | Production | Local |
|---------|-----------|-------|
| Backend URL | Render.com | localhost:8000 |
| Frontend URL | Vercel | localhost:3000 |
| LSTM Models | ✅ Available | ❌ Not available |
| Linear Forecast | ✅ Available | ✅ Available |
| Real-time Data | ✅ Available | ✅ Available |
| Auto-scaling | ✅ Yes | ❌ No |
| HTTPS | ✅ Yes | ❌ HTTP only |

---

## ✅ What's Next?

1. **Test the app** - Open http://localhost:3000 in your browser
2. **Try different stocks** - Enter various ticker symbols
3. **Explore features** - Toggle technical indicators, change time ranges
4. **Monitor performance** - Check backend logs for any issues
5. **Make changes** - Edit code and see changes automatically (backend auto-reloads)

---

## 📞 Need Help?

- Check the API docs: http://127.0.0.1:8000/docs
- Review `FIXES_APPLIED.md` for detailed technical information
- Check browser console (F12) for frontend errors
- Review backend logs in the terminal for API errors

---

**Happy Trading! 📈💰**
