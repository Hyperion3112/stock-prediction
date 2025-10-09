#!/bin/bash

# AI Stock Insights - Quick Deployment Script for Vercel
# This script deploys your optimized Flutter app to Vercel

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 AI Stock Insights - Quick Vercel Deployment${NC}"
echo "=================================================="

# Check if we're in the right directory
if [ ! -d "flutter_app" ]; then
    echo -e "${RED}Error: flutter_app directory not found!${NC}"
    echo "Please run this script from the 'Stock Prediction' directory"
    exit 1
fi

# Check Flutter installation
echo -e "\n${BLUE}[1/6]${NC} Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed${NC}"
    echo "Please install Flutter from: https://docs.flutter.dev/get-started/install"
    exit 1
fi
echo -e "${GREEN}✓ Flutter found${NC}"

# Check Vercel CLI
echo -e "\n${BLUE}[2/6]${NC} Checking Vercel CLI..."
if ! command -v vercel &> /dev/null; then
    echo -e "${YELLOW}Vercel CLI not found. Installing...${NC}"
    npm install -g vercel
fi
echo -e "${GREEN}✓ Vercel CLI ready${NC}"

# Navigate to Flutter app
cd flutter_app

# Clean previous builds
echo -e "\n${BLUE}[3/6]${NC} Cleaning previous builds..."
flutter clean
rm -rf build/web
echo -e "${GREEN}✓ Clean complete${NC}"

# Install dependencies
echo -e "\n${BLUE}[4/6]${NC} Installing dependencies..."
flutter pub get
echo -e "${GREEN}✓ Dependencies installed${NC}"

# Build Flutter web app with optimizations
echo -e "\n${BLUE}[5/6]${NC} Building optimized Flutter web app..."
flutter build web \
    --web-renderer html \
    --dart-define=FLUTTER_WEB_USE_SKIA=false \
    --dart-define=API_BASE_URL=https://stock-backend-nt1s.onrender.com \
    --release \
    --no-tree-shake-icons \
    --base-href=/

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Flutter build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Build successful${NC}"

# Deploy to Vercel
echo -e "\n${BLUE}[6/6]${NC} Deploying to Vercel..."
echo -e "${YELLOW}Note: If this is your first deployment, you'll be asked to login and configure the project${NC}"

vercel --prod

if [ $? -eq 0 ]; then
    echo -e "\n=================================================="
    echo -e "${GREEN}🎉 Deployment successful!${NC}"
    echo -e "=================================================="
    echo -e "\n${GREEN}Your optimized app is now live with:${NC}"
    echo -e "  ✓ Enhanced timeout handling (60s → 180s)"
    echo -e "  ✓ Automatic retry logic with exponential backoff"
    echo -e "  ✓ Circuit breaker pattern for reliability"
    echo -e "  ✓ Smart caching (5-minute TTL)"
    echo -e "  ✓ Contextual error messages"
    echo -e "  ✓ Fallback strategies (LSTM → Linear)"
    echo -e "\n${BLUE}💡 Test your deployment:${NC}"
    echo -e "  1. Try searching for 'AAPL'"
    echo -e "  2. Check timeout messages are user-friendly"
    echo -e "  3. Verify retry attempts in browser console"
    echo -e "  4. Test during backend cold start"
else