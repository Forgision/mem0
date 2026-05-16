import pytest
from unittest.mock import Mock, patch
from app.utils.categorization import get_categories_for_memory, _parse_categories_from_text


class TestTextFallbackParser:
    """Test the fallback text parser for non-structured providers."""

    def test_parse_comma_separated_categories(self):
        result = _parse_categories_from_text("work, personal, ideas")
        assert result == ["work", "personal", "ideas"]

    def test_parse_with_spaces(self):
        result = _parse_categories_from_text("  work  ,  personal  ,  ideas  ")
        assert result == ["work", "personal", "ideas"]

    def test_parse_empty_string(self):
        result = _parse_categories_from_text("")
        assert result == []

    def test_parse_invalid_input(self):
        result = _parse_categories_from_text("not valid comma separated")
        assert result == ["not valid comma separated"]


class TestCategorizationWithMemoryClient:
    """Test categorization using Memory client LLM."""

    @patch("app.utils.categorization.get_memory_client")
    def test_memory_client_not_initialized_raises_error(self, mock_get_client):
        mock_get_client.return_value = None
        # The @retry decorator wraps RuntimeError in RetryError
        with pytest.raises(Exception):  # Will be RetryError from tenacity
            get_categories_for_memory("test memory")

    @patch("app.utils.categorization.get_memory_client")
    def test_openai_provider_structured_output(self, mock_get_client):
        # Setup mock Memory client
        mock_llm = Mock()
        mock_llm.generate_response.return_value = '{"categories": ["work", "personal"]}'
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "openai"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("buy groceries")

        assert result == ["work", "personal"]
        mock_llm.generate_response.assert_called_once()

    @patch("app.utils.categorization.get_memory_client")
    def test_gemini_provider_structured_output(self, mock_get_client):
        mock_llm = Mock()
        mock_llm.generate_response.return_value = '{"categories": ["ideas"]}'
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "gemini"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("new project idea")

        assert result == ["ideas"]

    @patch("app.utils.categorization.get_memory_client")
    def test_ollama_provider_text_fallback(self, mock_get_client):
        mock_llm = Mock()
        mock_llm.generate_response.return_value = "work, personal, tasks"
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "ollama"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("daily tasks")

        assert result == ["work", "personal", "tasks"]

    @patch("app.utils.categorization.get_memory_client")
    def test_invalid_json_returns_empty_list(self, mock_get_client):
        mock_llm = Mock()
        mock_llm.generate_response.return_value = "invalid json{{{"
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "openai"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("test memory")

        assert result == []
