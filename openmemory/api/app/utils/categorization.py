import logging
from typing import List

from app.utils.memory import get_memory_client
from app.utils.prompts import MEMORY_CATEGORIZATION_PROMPT
from pydantic import BaseModel
from tenacity import retry, stop_after_attempt, wait_exponential


class MemoryCategories(BaseModel):
    categories: List[str]


def _parse_categories_from_text(text: str) -> List[str]:
    """Parse categories from plain text response (fallback for non-structured providers)."""
    try:
        # Try to extract comma-separated values
        categories = [cat.strip().lower() for cat in text.split(",")]
        return [cat for cat in categories if cat]
    except Exception:
        logging.warning(f"[WARN] Failed to parse categories from text: {text}")
        return []


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=15))
def get_categories_for_memory(memory: str) -> List[str]:
    try:
        memory_client = get_memory_client()
        if not memory_client:
            raise RuntimeError("Memory client not initialized")

        llm = memory_client.llm
        provider = memory_client.config.llm.provider

        messages = [{"role": "system", "content": MEMORY_CATEGORIZATION_PROMPT}, {"role": "user", "content": memory}]

        # Structured output providers (OpenAI, Gemini)
        if provider in ("openai", "openai_structured", "gemini"):
            response = llm.generate_response(messages=messages, response_format={"type": "json_object"})
            try:
                parsed = MemoryCategories.model_validate_json(response)
                return [cat.strip().lower() for cat in parsed.categories]
            except Exception as e:
                logging.error(f"[ERROR] Failed to parse structured output: {e}")
                return []

        # Fallback: text parsing for ollama, anthropic, groq, etc.
        else:
            response = llm.generate_response(messages=messages)
            return _parse_categories_from_text(response)

    except Exception as e:
        logging.error(f"[ERROR] Failed to get categories: {e}")
        raise
