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

upd:
	sudo docker compose -f openmemory/docker-compose.yml -f openmemory/docker-compose-dev.yml down && \
	sudo docker rmi mem0/openmemory-mcp mem0/openmemory-ui:latest 2>/dev/null; \
	sudo docker compose -f openmemory/docker-compose.yml -f openmemory/docker-compose-dev.yml build --no-cache openmemory-mcp openmemory-ui && \
	sudo docker compose -f openmemory/docker-compose.yml -f openmemory/docker-compose-dev.yml up -d
