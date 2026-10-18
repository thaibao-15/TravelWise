---
name: TravelWise API Rules
description: "Use when changing the FastAPI backend, Python services, SQLModel models, API routes, RAG pipeline, LLM integration, database code, or backend tests."
applyTo: "apps/api/**/*.py"
---

# TravelWise API Rules

## Architecture

- Keep `app/api/routes/` focused on request parsing, authorization checks, dependency injection and service orchestration.
- Put business logic in `app/services/`.
- Keep RAG retrieval, prompts, embeddings and LLM chain code in `app/rag/`.
- Define request and response contracts with Pydantic schemas in `app/schemas/`.
- Use the existing `get_session` dependency and SQLModel patterns for database access.
- Protect user-owned resources with the existing ownership and `ADMIN` authorization patterns.

## Python and FastAPI

- Add complete type annotations to functions, public methods and important variables.
- Validate request bodies and query parameters at the API boundary.
- Use `async def` and non-blocking clients for genuinely asynchronous I/O. Do not put long blocking operations in the event loop.
- Surface errors through repository-standard HTTP errors and logging. Do not silently continue after failed database, LLM or external-service operations.
- Keep configuration in `app.core.config.settings` and environment variables.

## RAG and itinerary generation

- Keep these responsibilities separate:
  - `RAGChain`: retrieval and conversational answers.
  - `TripPlanningContextExtractionService`: extraction, merging and persistence of planning context.
  - `ItineraryGenerationService`: candidate search, LLM itinerary generation and sanitization.
  - `ItineraryPersistenceService`: final validation and atomic database persistence.
- Never allow the itinerary LLM to invent places or `place_id` values. It may select only from candidates returned by `PlaceSearchService`.
- Validate generated itineraries for duration, continuous day/order indexes, valid and non-overlapping times, non-negative costs/durations/distances, excluded places and unresolved must-visit requirements.
- Parse LLM JSON defensively. Use at most a controlled repair attempt and return an explicit failure status if parsing still fails.
- Treat RAG chat output and a persisted itinerary as separate flows. Only itinerary generation endpoints create itinerary records.
- Preserve transaction atomicity. Roll back all itinerary changes on persistence failure and do not overwrite `CONFIRMED` trips without explicit authorization.
- In voice mode, return natural text without Markdown, emoji or repeated fixed greetings.

## Database changes

- When changing models or database structure, create or update the appropriate Alembic migration.
- Do not rely on model changes alone to update an existing database.
- Preserve ownership, transaction and cascade-delete behavior when changing trip or itinerary persistence.

## Validation

From `apps\api` run the smallest relevant checks, for example:

```powershell
uv run python -m unittest discover tests -v
uv run ruff check app tests
uv run ruff format --check app tests
uv run python -c "from app.services.<module> import <symbol>; print('OK')"
```
