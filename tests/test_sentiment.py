import importlib

import pytest

from app import SENTIMENT_ANALYZER, _analyze_headline_sentiment


def test_analyze_headline_sentiment_with_vader():
    if SENTIMENT_ANALYZER is None:
        pytest.skip("VADER analyzer not available in environment")

    label, score = _analyze_headline_sentiment(
        "Company reports record profit and strong growth",
        "The quarterly results beat analyst expectations with bullish guidance.",
    )
    assert label == "Positive"
    assert score > 0


def test_analyze_headline_sentiment_keyword_fallback(monkeypatch):
    module = importlib.import_module("app")
    monkeypatch.setattr(module, "SENTIMENT_ANALYZER", None, raising=False)

    label, score = module._analyze_headline_sentiment(  # pylint: disable=protected-access
        "Company faces lawsuit after massive loss",
        "Investors worry about the debt and ongoing decline in revenue.",
    )
    assert label == "Negative"
    assert score <= -0.05
