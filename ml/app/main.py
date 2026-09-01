"""FastAPI application for the FitSync ML service.

Node calls this service; it never calls Node. Every user field arrives in the
request body -- this process holds a read-only grant on four reference tables
and reads no user row at request time. See the design, section 3.
"""
import os

from dotenv import load_dotenv
from fastapi import FastAPI

from app.config import Settings


def create_app(settings: Settings) -> FastAPI:
    app = FastAPI(title="FitSync ML service")
    app.state.settings = settings

    @app.get("/health")
    def health():
        # Deliberately does not touch MySQL: this is what a load balancer polls,
        # and a health check that needs the database only reports the database.
        # The model slot is empty until a trained model exists -- see section 8.
        return {"status": "ok", "model": "absent", "mode": "rules"}

    return app


def build() -> FastAPI:
    """Entry point for `uvicorn app.main:build --factory`."""
    load_dotenv()
    return create_app(Settings.from_env(os.environ))
