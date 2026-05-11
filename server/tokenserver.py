from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from livekit import api
from datetime import timedelta
import os
from dotenv import load_dotenv
import logging
import uuid

from admin_api import router as admin_router


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

# Mount admin routes.
app.include_router(admin_router)


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
    identity: str = None,
    room: str = None,
):
    """Generate a token for connecting to LiveKit room for TTS"""
    session_id = uuid.uuid4().hex[:12]

    # Generate default values if none provided
    if identity is None:
        identity = f"realtime-{session_id}"
    if room is None:
        room = f"realtime-{session_id}"
    
    if not LIVEKIT_API_KEY or not LIVEKIT_API_SECRET:
        raise HTTPException(
            status_code=500, 
            detail="LiveKit credentials not configured. Check .env file."
        )
    
    try:
        # Create access token
        token = api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        
        # Set token properties
        token.ttl = timedelta(hours=2)
        token.name = identity
        token.identity = identity
        
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
        
        # Generate JWT
        jwt_token = token.to_jwt()
        
        logger.info(f"Generated token for {identity} in room {room}")
        
        return {
            "accessToken": jwt_token,
            "url": LIVEKIT_URL,
            "room": room,
            "identity": identity
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
