import logging
from dotenv import load_dotenv
from livekit import agents, rtc
from livekit.agents import AgentSession, Agent
from livekit.agents.voice import io
from livekit.plugins import openai, elevenlabs, silero
from openai.types.beta.realtime.session import  InputAudioTranscription, TurnDetection
import os
import json

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('agent_debug.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

load_dotenv()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
ELEVEN_API_KEY = os.getenv("ELEVEN_API_KEY")
voice_id = os.getenv("ELEVEN_VOICE_ID")
model = os.getenv("ELEVEN_MODEL")
LIVEKIT_URL = os.getenv("LIVEKIT_URL")
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET")

class CharacterDataPublisher(io.TextOutput):
    """Custom text output that publishes character-level timing data via data channel"""
    
    def __init__(self, room: rtc.Room, next_in_chain: io.TextOutput | None = None):
        super().__init__(label="character_publisher", next_in_chain=next_in_chain)
        self._room = room
        logger.info("CharacterDataPublisher initialized")
    
    async def capture_text(self, text: str) -> None:
        """Intercept text and send character-level data if it's a TimedString"""
        if isinstance(text, io.TimedString):
            logger.debug(f"TTS char='{text}' [{text.start_time:.3f}s -> {text.end_time:.3f}s]")
            
            try:
                # Send character data to frontend
                data = json.dumps({
                    'type': 'transcription',
                    'text': str(text),
                    'start_time': text.start_time,
                    'end_time': text.end_time,
                })
                await self._room.local_participant.publish_data(
                    data.encode('utf-8'),
                    topic="character_timing"
                )
                logger.debug(f"Published character: {text}")
            except Exception as e:
                logger.error(f"Failed to publish character data: {e}", exc_info=True)
        
        # Always forward to next in chain
        if self.next_in_chain:
            await self.next_in_chain.capture_text(text)
    
    def flush(self) -> None:
        """Forward flush to next in chain"""
        if self.next_in_chain:
            self.next_in_chain.flush()

class Assistant(Agent):
    def __init__(self) -> None:
        logger.info("Initializing Assistant agent")
        super().__init__(instructions="Talk like a normal Arab human, be conversational,  very talkative,  chatty outgoing, be an attention seeker and basically a motor mouth. Use the syrian dialect exclusively. ")

async def entrypoint(ctx: agents.JobContext):
    import time
    start_time = time.time()
    logger.info("Starting agent entrypoint")
    try:
        # Connect to room first so we have the room object
        logger.info("Connecting to LiveKit room...")
        t1 = time.time()
        await ctx.connect()
        logger.info(f"Connected to room in {time.time()-t1:.2f}s")
        
        # Initialize models BEFORE starting session (faster perceived startup)
        logger.info("Loading VAD model...")
        t1 = time.time()
        vad = silero.VAD.load(
            min_speech_duration=0.05,
            min_silence_duration=0.2,
        )
        logger.info(f"VAD loaded in {time.time()-t1:.2f}s")
        
        logger.info("Initializing STT...")
        t1 = time.time()
        stt = openai.STT(model="gpt-4o-transcribe",language='ar')
        logger.info(f"STT initialized in {time.time()-t1:.2f}s")
        
        logger.info("Initializing LLM...")
        t1 = time.time()
        llm = openai.LLM(model="gpt-5.1", temperature=0.7)
        logger.info(f"LLM initialized in {time.time()-t1:.2f}s")
        
        logger.info("Initializing TTS...")
        t1 = time.time()
        tts = elevenlabs.TTS(voice_id=voice_id, model=model, api_key=ELEVEN_API_KEY, language="ar")
        logger.info(f"TTS initialized in {time.time()-t1:.2f}s")
        
        logger.info("Creating agent session...")
        t1 = time.time()
        
        session = AgentSession(
            stt=stt, 
            llm=llm, 
            tts=tts, 
            vad=vad,
            use_tts_aligned_transcript=True,  # Enable character-level timing
        )
        logger.info(f"Agent session created in {time.time()-t1:.2f}s")
        
        # Wrap the existing transcription output with our character publisher
        logger.info("Injecting character data publisher...")
        existing_transcription = session.output.transcription
        char_publisher = CharacterDataPublisher(room=ctx.room, next_in_chain=existing_transcription)
        session.output.transcription = char_publisher
        logger.info("Character publisher injected")

        try:
            logger.info("Starting agent session...")
            t1 = time.time()
            await session.start(
                room=ctx.room,
                agent=Assistant(),
            )
            logger.info(f"Agent session started in {time.time()-t1:.2f}s")
            logger.info(f"TOTAL ENTRYPOINT TIME: {time.time()-start_time:.2f}s")
        except Exception as e:
            logger.error(f"Failed to start session: {str(e)}", exc_info=True)
            raise

    except Exception as e:
        logger.error(f"Critical error in entrypoint: {str(e)}", exc_info=True)
        raise

def prewarm(proc: agents.JobProcess):
    """Pre-load models before jobs arrive to reduce startup latency"""
    logger.info("Pre-warming process: loading VAD model...")
    # Load VAD model once at startup
    silero.VAD.load(
        min_speech_duration=0.05,
        min_silence_duration=0.2,
    )
    logger.info("Pre-warm complete - VAD model loaded")

if __name__ == "__main__":
    logger.info("Starting agent application")
    try:
        # Use AgentServer with optimized settings:
        # - port=0: Dynamic port allocation to avoid conflicts
        # - num_idle_processes=1: Keep 1 pre-warmed process ready (faster job acceptance)
        # - setup_fnc: Pre-load heavy models
        server = agents.AgentServer(
            port=0,
            num_idle_processes=1,  # Keep 1 process pre-warmed with models loaded
            setup_fnc=prewarm,      # Pre-load VAD model
        )
        server.rtc_session(entrypoint)
        agents.cli.run_app(server)
    except Exception as e:
        logger.error(f"Application failed to start: {str(e)}", exc_info=True)
        raise