#!/bin/bash
# Build script for deployment

echo "Installing dependencies..."
pip install --upgrade pip
pip install --no-cache-dir -r requirements.txt

echo "Build complete!"

