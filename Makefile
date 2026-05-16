.PHONY: lint format test docs docker-up docker-down

lint:
	cd openmemory/api && ruff check .

format:
	cd openmemory/api && ruff format .

test:
	cd openmemory/api && python -m pytest tests/ $(ARGS)

docs:
	cd docs && mintlify dev

docker-up:
	cd openmemory && docker-compose up -d

docker-down:
	cd openmemory && docker-compose down
