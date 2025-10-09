# 🚀 Local Deployment Guide

Complete guide to run your AI Stock Prediction application locally.

---

## 📋 Prerequisites

Before you begin, make sure you have:

- ✅ **Python 3.9+** installed
- ✅ **Flutter 3.3+** with web support enabled
- ✅ **Git** (for cloning/updating)

Check your versions:
```bash
python3 --version
flutter --version
```

---

## 🎯 Quick Start (Easiest Method)

### **Step 1: Navigate to project directory**
```bash
cd "/Users/shaunak/Projects/Stock Prediction"
```

### **Step 2: Run the startup script**
```bash
./start_local.sh
```

That's it! 🎉 The script will:
- ✅ Create/activate Python virtual environment
- ✅ Install backend dependencies
- ✅ Start FastAPI backend on port 8000
- ✅ Build Flutter web app
- ✅ Start frontend server on port 3000

### **Step 3: Access the application**

Open your browser and go to:
- **Frontend:** http://localhost:3000
- **Backend API Docs:** http://localhost:8000/docs
- **Health Check:** http://localhost:8000/health

### **Stop the servers**
Press `Ctrl+C` in the terminal where the script is running.

---

## 🔧 Manual Setup (Step-by-Step)

If you prefer to run things manually or need more control:

### **Backend Setup**

1. **Navigate to project directory:**
   ```bash
   cd "/Users/shaunak/Projects/Stock Prediction"
   ```

2. **Create and activate virtual environment:**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Start the FastAPI backend:**
   ```bash
   uvicorn app:app --reload --port 8000
   ```

   ✅ Backend is now running at http://localhost:8000

### **Frontend Setup**

Open a **new terminal** and:

1. **Navigate to Flutter app directory:**
   ```bash
   cd "/Users/shaunak/Projects/Stock Prediction/flutter_app"
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Build the web app:**
   ```bash
   flutter build web
   ```

4. **Serve the built app:**
   ```bash
   python3 -m http.server 3000 --directory build/web
   ```

   ✅ Frontend is now running at http://localhost:3000

---

## 🔄 Development Mode (Hot Reload)

For active development with live reload:

### **Terminal 1 - Backend with hot reload:**
```bash
cd "/Users/shaunak/Projects/Stock Prediction"
source .venv/bin/activate
uvicorn app:app --reload --port 8000
```

### **Terminal 2 - Frontend with hot reload:**
```bash
cd "/Users/shaunak/Projects/Stock Prediction/flutter_app"
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

This will open Chrome with hot reload enabled - changes to Flutter code will update immediately!

---

## 🧪 Testing the Application

### **1. Test Backend API:**
```bash
# Health check
curl http://localhost:8000/health

# Get stock overview
curl "http://localhost:8000/overview?ticker=AAPL&preset=6M"

# Get forecast
curl "http://localhost:8000/forecast?ticker=AAPL&days=30"

# Get sentiment
curl "http://localhost:8000/sentiment?ticker=AAPL"
```

### **2. Test Frontend:**
- Open http://localhost:3000
- Enter a stock ticker (e.g., AAPL, TSLA, MSFT)
- Select time range (1M, 3M, 6M, etc.)
- Click "Refresh insights"
- Hover over the help icon (?) to see the new popup design!

---

## 🎨 Available Features

### ✅ Working Features:
- 📊 **Stock Overview** - Real-time stock data and metrics
- 📈 **Linear Forecasting** - Price predictions using linear regression
- 📉 **LSTM Forecasting** - Advanced neural network predictions (if models exist)
- 📊 **Technical Indicators** - SMA-20, SMA-50, EMA-12, EMA-26
- 📰 **News Sentiment Analysis** - Analyze market sentiment from news
- 📱 **Interactive Charts** - Beautiful, responsive visualizations
- ⏰ **Multiple Time Ranges** - 1M, 3M, 6M, 1Y, 2Y, 5Y
- 🕐 **Different Intervals** - 1d, 1wk, 1mo, 1h, 30m, 15m, 5m, 1m

---

## 🛠️ Troubleshooting

### **Port Already in Use**

If you get "Address already in use" error:

**For Backend (port 8000):**
```bash
lsof -ti:8000 | xargs kill -9
```

**For Frontend (port 3000):**
```bash
lsof -ti:3000 | xargs kill -9
```

### **Module Not Found**

If Python modules are missing:
```bash
source .venv/bin/activate
pip install -r requirements.txt
```

### **Flutter Build Errors**

Clean and rebuild:
```bash
cd flutter_app
flutter clean
flutter pub get
flutter build web
```

### **CORS Issues**

Make sure the backend is running on port 8000 and the frontend is configured to point to it. The FastAPI backend has CORS enabled for all origins.

---

## 📝 Environment Variables

### **Backend (Optional):**
```bash
export HOST=0.0.0.0
export PORT=8000
```

### **Frontend (Build Time):**
```bash
flutter build web --dart-define=API_BASE_URL=http://localhost:8000
```

---

## 🔄 Updating After Git Pull

After pulling new changes:

1. **Update backend dependencies:**
   ```bash
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Rebuild frontend:**
   ```bash
   cd flutter_app
   flutter pub get
   flutter build web
   ```

3. **Restart servers:**
   ```bash
   ./start_local.sh
   ```

---

## 🌟 Tips

- 💡 Use the **Quick Start** method for regular use
- 🔥 Use **Development Mode** when actively coding
- 🧪 Always test the API endpoints before using the frontend
- 📱 The app is fully responsive - try it on different screen sizes!
- 🎨 Hover over the help icon (?) to see usage instructions

---

## 🆘 Need Help?

- Check the logs in the terminal where servers are running
- Visit http://localhost:8000/docs for interactive API documentation
- Ensure both backend and frontend are running before accessing the app

---

**Happy Forecasting! 📈🚀**
