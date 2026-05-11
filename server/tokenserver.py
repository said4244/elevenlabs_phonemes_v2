import json

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from livekit import api
from datetime import timedelta
import os
from dotenv import load_dotenv
import logging
import uuid

from admin_api import router as admin_router
from session_api import (
    get_authenticated_user,
    router as session_router,
    _sb_get,
    _validate_session_ownership,
)


load_dotenv()


logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

app = FastAPI(title="Arabic TTS Token Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your domains
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["*"],
)

# Mount admin and session routes.
app.include_router(admin_router)
app.include_router(session_router)


LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET")
LIVEKIT_URL = os.getenv("LIVEKIT_URL", "wss://cloud.livekit.io")


if not all([LIVEKIT_API_KEY, LIVEKIT_API_SECRET]):
    logger.error("Missing LiveKit credentials in .env file")
else:
    logger.info("LiveKit credentials loaded successfully")
    logger.info(f"LiveKit URL: {LIVEKIT_URL}")

@app.get("/token")
async def create_token(
    session_id: str | None = None,
    prompt_id: str | None = None,
    user: dict = Depends(get_authenticated_user),
):
    """Generate a LiveKit token for the authenticated user.

    When session_id is provided, the room name is fixed to huda-session-<session_id>
    and session ownership is validated against session_evidence.
    Falls back to a random room if no session_id is supplied (dev/testing only).
    """
    user_id: str = user["id"]

    if session_id:
        # Validate the session belongs to this user
        try:
            await _validate_session_ownership(session_id, user_id)
        except HTTPException:
            raise
        room = f"huda-session-{session_id}"
        identity = f"user:{user_id}"
    else:
        # Development fallback – anonymous session
        fallback_id = uuid.uuid4().hex[:12]
        room = f"realtime-{fallback_id}"
        identity = f"anon-{fallback_id}"

    if not LIVEKIT_API_KEY or not LIVEKIT_API_SECRET:
        raise HTTPException(
            status_code=500,
            detail="LiveKit credentials not configured. Check .env file."
        )

    try:
        # Build metadata for the agent to read
        metadata_payload: dict = {"user_id": user_id}
        if session_id:
            metadata_payload["session_id"] = session_id
        if prompt_id:
            metadata_payload["prompt_id"] = prompt_id

        # Create access token
        token = api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        token.ttl = timedelta(hours=2)
        token.name = identity
        token.identity = identity
        token.metadata = json.dumps(metadata_payload)

        # Grant permissions
        token.with_grants(
            api.VideoGrants(
                room_join=True,
                room=room,
                can_publish=True,
                can_subscribe=True,
                can_publish_data=True,
            )
        )

        jwt_token = token.to_jwt()
        logger.info(f"Generated token for {identity} in room {room}")

        return {
            "accessToken": jwt_token,
            "url": LIVEKIT_URL,
            "room": room,
            "identity": identity,
            "session_id": session_id,
            "prompt_id": prompt_id,
        }

    except Exception as e:
        logger.error(f"Failed to generate token: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "Arabic TTS Token Server"}


@app.get("/debug")
async def debug_info():
    """Debug endpoint to check server status"""
    return {
        "status": "running",
        "default_room": "tts-reading-room",
        "livekit_url": LIVEKIT_URL,
        "credentials_loaded": bool(LIVEKIT_API_KEY and LIVEKIT_API_SECRET),
    }


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8080))
    logger.info(f"Starting token server on port {port}")
    uvicorn.run(app, host="0.0.0.0", port=port)
