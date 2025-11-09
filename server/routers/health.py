from __future__ import annotations

from fastapi import APIRouter


router = APIRouter(tags=["health"])


@router.get("/health", summary="Health check endpoint")
async def health() -> dict[str, str]:
    return {"status": "ok"}


