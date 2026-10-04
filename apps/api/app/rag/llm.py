"""
Chat LLM Model initialization module for TravelWise.

Supports:
- Google Gemini (ChatGoogleGenerativeAI via langchain-google-genai)
- OpenAI (ChatOpenAI via langchain-openai)

Instantiates LLMs dynamically using environment configuration.
Does not hardcode models or API keys into business logic.
Ensures API keys are never leaked into logs or error messages.
"""

import logging
from typing import Any, Optional, Union

from langchain_core.language_models.chat_models import BaseChatModel

from app.rag.config import (
    GEMINI_API_KEY,
    GEMINI_MODEL,
    LLM_PROVIDER,
    OPENAI_API_KEY,
    OPENAI_BASE_URL,
    OPENAI_MODEL,
)

logger = logging.getLogger(__name__)


def extract_response_text(content: Union[str, list, Any]) -> str:
    """Safely extracts text content from LLM response content.

    Handles both standard strings and structured block lists (common in Gemini).
    """
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and "text" in item:
                parts.append(item["text"])
            elif isinstance(item, str):
                parts.append(item)
            elif hasattr(item, "text"):
                parts.append(str(item.text))
        return "".join(parts)
    return str(content)


def get_chat_llm(
    provider: Optional[str] = None,
    model: Optional[str] = None,
    temperature: float = 0.7,
    **kwargs: Any,
) -> BaseChatModel:
    """Factory function returning a configured BaseChatModel instance.

    Args:
        provider: Optional override ("gemini" or "openai"). Defaults to LLM_PROVIDER.
        model: Optional model override; defaults to GEMINI_MODEL / OPENAI_MODEL from settings.
        temperature: Sampling temperature for the model (default: 0.7).
        **kwargs: Additional parameters passed to the underlying chat model.

    Returns:
        BaseChatModel: Configured LangChain Chat model instance.

    Raises:
        ValueError: If the required API key for the chosen provider is not configured.
    """
    selected_provider = (provider or LLM_PROVIDER or "gemini").lower()

    if selected_provider == "gemini":
        if not GEMINI_API_KEY:
            logger.error("Failed to initialize ChatGoogleGenerativeAI: GEMINI_API_KEY is missing or empty.")
            raise ValueError(
                "GEMINI_API_KEY is not configured. Please set GEMINI_API_KEY in your .env file."
            )
        from langchain_google_genai import ChatGoogleGenerativeAI

        selected_model = model or GEMINI_MODEL
        logger.info(
            "Initializing ChatGoogleGenerativeAI with model: %s (temperature: %s)",
            selected_model,
            temperature,
        )
        return ChatGoogleGenerativeAI(
            model=selected_model,
            google_api_key=GEMINI_API_KEY,
            temperature=temperature,
            **kwargs,
        )

    # Fallback to OpenAI
    if not OPENAI_API_KEY:
        logger.error("Failed to initialize ChatOpenAI: OPENAI_API_KEY is missing or empty.")
        raise ValueError(
            "OPENAI_API_KEY is not configured. Please set OPENAI_API_KEY in your .env file."
        )

    from langchain_openai import ChatOpenAI

    selected_model = model or OPENAI_MODEL
    selected_base_url = kwargs.pop("base_url", OPENAI_BASE_URL)

    llm_params: dict[str, Any] = {
        "model": selected_model,
        "api_key": OPENAI_API_KEY,
        "temperature": temperature,
        **kwargs,
    }
    if selected_base_url:
        llm_params["base_url"] = selected_base_url

    logger.info(
        "Initializing ChatOpenAI with model: %s (temperature: %s)",
        selected_model,
        temperature,
    )
    return ChatOpenAI(**llm_params)
