#!/bin/bash

echo "🚀 Starting AI Stock Prediction App Locally..."
echo ""

# Kill any existing processes on ports 8000 and 3000
echo "🧹 Cleaning up ports..."
lsof -ti:8000 | xargs kill -9 2>/dev/null
lsof -ti:3000 | xargs kill -9 2>/dev/null
sleep 1

# Start Backend (FastAPI)
echo "📊 Starting Backend API on port 8000..."
cd "/Users/shaunak/Projects/Stock Prediction"

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

source .venv/bin/activate

# Install dependencies without tensorflow first
echo "Installing dependencies..."
pip install -q yfinance fastapi "uvicorn[standard]" pandas numpy scikit-learn joblib pytest vaderSentiment

# Try to install tensorflow (optional)
pip install -q tensorflow-macos tensorflow-metal 2>/dev/null || \
pip install -q tensorflow 2>/dev/null || \
echo "⚠️  TensorFlow not available (will use linear forecasting only)"

# Start backend in background
uvicorn app:app --reload --port 8000 &
BACKEND_PID=$!
echo "✅ Backend running (PID: $BACKEND_PID)"

# Wait for backend to start
sleep 4

# Start Frontend (Flutter Web)
echo ""
echo "🎨 Starting Frontend on port 3000..."
cd flutter_app
flutter pub get
flutter build web

# Start web server for Flutter
python3 -m http.server 3000 --directory build/web &
FRONTEND_PID=$!
echo "✅ Frontend running (PID: $FRONTEND_PID)"

echo ""
echo "════════════════════════════════════════════════════════"
echo "�� Application Started Successfully!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "🌐 Frontend: http://localhost:3000"
echo "📡 Backend API: http://localhost:8000"
echo "📚 API Docs: http://localhost:8000/docs"
echo ""
echo "Press Ctrl+C to stop both servers"
echo "════════════════════════════════════════════════════════"

# Wait for user interrupt
trap "kill $BACKEND_PID $FRONTEND_PID; echo ''; echo '👋 Servers stopped'; exit" INT
wait
