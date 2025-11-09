from __future__ import annotations

import logging
import ssl
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.middleware.cors import CORSMiddleware

from server.routers import create_api_router


# Match previous behaviour for environments with custom certificates
ssl._create_default_https_context = ssl._create_unverified_context  # type: ignore[attr-defined]


LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / "api_logs.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, mode="a"),
        logging.StreamHandler(),
    ],
    force=True,
)
logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    app = FastAPI(title="HackUMass Slide Processor")

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request, exc: RequestValidationError
    ) -> Any:
        logger.error("Validation error: %s %s %s", request.method, request.url, exc.errors())
        return await request_validation_exception_handler(request, exc)

    @app.get("/")
    async def healthcheck() -> dict[str, str]:
        return {
            "message": "HackUMass OCR slide server is running",
            "process_slide": "/process_slide",
        }

    app.include_router(create_api_router())

    return app


app = create_app()


