#!/usr/bin/env python3
"""Quick test script to verify sentiment generation works locally."""

import sys
from app import fetch_news_with_sentiment

if __name__ == "__main__":
    ticker = sys.argv[1] if len(sys.argv) > 1 else "AAPL"
    print(f"\nTesting sentiment for {ticker}...")
    
    df = fetch_news_with_sentiment(ticker, limit=5)
    
    if df.empty:
        print("❌ No sentiment data returned")
    else:
        print(f"✅ Found {len(df)} news items:\n")
        for idx, row in df.iterrows():
            print(f"  {idx+1}. [{row['Sentiment']}] {row['Headline']}")
            print(f"     Score: {row['Score']:.3f} | Publisher: {row['Publisher']}")
            print(f"     {row['Summary'][:80]}...")
            print()
