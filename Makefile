.PHONY: lint format test docs docker-up docker-down upd updc log

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

## Dev only: rebuild + restart all openmemory containers
upd:
	sudo docker compose -f openmemory/docker-compose-dev.yml down && \
	sudo docker rmi mem0/openmemory-mcp mem0/openmemory-ui:latest 2>/dev/null; \
	sudo docker compose -f openmemory/docker-compose-dev.yml build && \
	sudo docker compose -f openmemory/docker-compose-dev.yml up -d

## Dev only: force clean rebuild (no cache)
updc:
	sudo docker compose -f openmemory/docker-compose-dev.yml down && \
	sudo docker rmi mem0/openmemory-mcp mem0/openmemory-ui:latest 2>/dev/null; \
	sudo docker compose -f openmemory/docker-compose-dev.yml build --no-cache && \
	sudo docker compose -f openmemory/docker-compose-dev.yml up -d

## Dev only: tail logs for all openmemory containers
log:
	sudo docker compose -f openmemory/docker-compose-dev.yml logs -f
