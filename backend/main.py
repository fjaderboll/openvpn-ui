import os

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from backend.auth import router as auth_router
from backend.api import router as api_router

app = FastAPI(title="OpenVPN UI", version="1.0.0")

app.include_router(auth_router, prefix="/api/auth", tags=["auth"])
app.include_router(api_router, prefix="/api", tags=["api"])

# Serve frontend static files — must be last so /api routes take priority
frontend_dir = os.environ.get("FRONTEND_DIR", "/app/frontend")
if os.path.isdir(frontend_dir):
    app.mount("/", StaticFiles(directory=frontend_dir, html=True), name="frontend")
