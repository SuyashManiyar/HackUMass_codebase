from fastapi import APIRouter

from .health import router as health_router
from .slides import router as slides_router

__all__ = ["create_api_router"]


def create_api_router() -> APIRouter:
    router = APIRouter()
    router.include_router(health_router)
    router.include_router(slides_router)
    return router


