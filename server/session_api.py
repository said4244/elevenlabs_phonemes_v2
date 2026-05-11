"""
session_api.py – FastAPI router for session lifecycle management.

Auth model:
  - All endpoints require Authorization: Bearer <Supabase access token>.
  - Backend validates the token via Supabase /auth/v1/user (never trusts client-side user_id).
  - Backend uses SERVICE_ROLE_KEY to read/write Supabase tables.

Tables used (NO new tables created):
  - public.user_profile         – read learner data
  - public.user_cached_prompts  – write generated system prompts
  - public.session_evidence     – write session lifecycle events
  - public.level_prompt_templates – read level-specific tutor notes
"""

import logging
import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from prompt_builder import build_first_session_prompt

load_dotenv()

logger = logging.getLogger(__name__)

SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

_bearer = HTTPBearer()

# ---------------------------------------------------------------------------
# Auth helper – shared with tokenserver.py
# ---------------------------------------------------------------------------


async def get_authenticated_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> dict:
    """Validate a Supabase JWT and return {"id": user_id, "email": email}.

    Raises HTTP 401 if the token is invalid or expired.
    """
    token = credentials.credentials
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            f"{SUPABASE_URL}/auth/v1/user",
            headers={
                "Authorization": f"Bearer {token}",
                "apikey": SUPABASE_SERVICE_ROLE_KEY,
            },
        )

    if resp.status_code != 200:
        logger.warning("Token validation failed: %s %s", resp.status_code, resp.text[:200])
        raise HTTPException(status_code=401, detail="Invalid or expired token.")

    data = resp.json()
    user_id: str = data.get("id", "")
    email: str = data.get("email", "")

    if not user_id:
        raise HTTPException(status_code=401, detail="Cannot determine user id from token.")

    return {"id": user_id, "email": email}


# ---------------------------------------------------------------------------
# Supabase REST helpers (service-role, bypasses RLS)
# ---------------------------------------------------------------------------


def _service_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


async def _sb_get(path: str, params: dict | None = None) -> Any:
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            f"{SUPABASE_URL}{path}",
            headers=_service_headers(),
            params=params,
        )
    resp.raise_for_status()
    return resp.json()


async def _sb_post(path: str, body: dict) -> Any:
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(
            f"{SUPABASE_URL}{path}",
            headers=_service_headers(),
            json=body,
        )
    if resp.status_code not in (200, 201):
        logger.error("Supabase POST %s → %s: %s", path, resp.status_code, resp.text[:400])
        resp.raise_for_status()
    return resp.json()


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------


def _now_utc() -> str:
    return datetime.now(tz=timezone.utc).isoformat()


def _utc_plus_hours(hours: int = 2) -> str:
    return (datetime.now(tz=timezone.utc) + timedelta(hours=hours)).isoformat()


async def _insert_session_evidence(
    *,
    session_id: str,
    user_id: str,
    evidence_type: str,
    dialect_code: str = "",
    transcript_excerpt: str = "",
) -> None:
    """Insert one row into public.session_evidence."""
    row = {
        "session_id": session_id,
        "user_id": user_id,
        "concept_id": "session_lifecycle",
        "dialect_code": dialect_code or "",
        "evidence_type": evidence_type,
        "confidence": 1.0,
        "transcript_excerpt": transcript_excerpt,
        "created_at": _now_utc(),
    }
    try:
        await _sb_post("/rest/v1/session_evidence", row)
    except Exception as exc:
        # Non-fatal – log and continue
        logger.warning("session_evidence insert failed (%s): %s", evidence_type, exc)


async def _validate_session_ownership(session_id: str, user_id: str) -> None:
    """Assert at least one session_evidence row exists for (session_id, user_id)."""
    rows = await _sb_get(
        "/rest/v1/session_evidence",
        params={
            "select": "session_id",
            "session_id": f"eq.{session_id}",
            "user_id": f"eq.{user_id}",
            "limit": "1",
        },
    )
    if not rows:
        raise HTTPException(
            status_code=403,
            detail="Session not found or not owned by this user.",
        )


# ---------------------------------------------------------------------------
# Pydantic request/response models
# ---------------------------------------------------------------------------


class PrepareSessionRequest(BaseModel):
    target_dialect_code: str | None = None
    translation_language_code: str | None = None


class SessionEndedRequest(BaseModel):
    reason: str = "user_ended"
    metadata: dict | None = None


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

router = APIRouter(prefix="/session", tags=["session"])


@router.post("/prepare")
async def prepare_session(
    req: PrepareSessionRequest,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    """
    Prepare a new learning session.

    1. Validates the Supabase JWT.
    2. Loads the user's profile from public.user_profile.
    3. Generates a personalized system prompt (rule-based, no OpenAI).
    4. Stores the prompt in public.user_cached_prompts.
    5. Inserts a session_evidence row with evidence_type='session_prepared'.
    6. Returns session_id, prompt_id, room_name, and prompt_preview.
    """
    user_id: str = user["id"]

    # ── 1. Load profile ───────────────────────────────────────────────────
    rows = await _sb_get(
        "/rest/v1/user_profile",
        params={"select": "*", "user_id": f"eq.{user_id}", "limit": "1"},
    )
    if not rows:
        raise HTTPException(
            status_code=400,
            detail="User profile not found. Please complete onboarding first.",
        )

    profile: dict = rows[0]

    if profile.get("is_new_user", True):
        raise HTTPException(
            status_code=400,
            detail="Onboarding is not yet complete for this user.",
        )

    # Resolve dialect/lang (request overrides profile)
    target_dialect: str = req.target_dialect_code or profile.get("target_dialect_code") or "msa"
    translation_lang: str = req.translation_language_code or profile.get("translation_language_code") or "en"
    current_level: int = int(profile.get("current_level") or 1)

    # ── 2. Load level template (optional) ────────────────────────────────
    level_template: dict | None = None
    try:
        tmpl_rows = await _sb_get(
            "/rest/v1/level_prompt_templates",
            params={"select": "*", "level": f"eq.{current_level}", "limit": "1"},
        )
        if tmpl_rows:
            level_template = tmpl_rows[0]
    except Exception as exc:
        logger.info("level_prompt_templates not available or empty: %s", exc)

    # ── 3. Build system prompt ───────────────────────────────────────────
    session_id: str = str(uuid.uuid4())
    room_name: str = f"huda-session-{session_id}"

    prompt_text: str = build_first_session_prompt(profile, level_template)

    # ── 4. Store prompt in user_cached_prompts ───────────────────────────
    prompt_row = {
        "user_id": user_id,
        "target_dialect_code": target_dialect,
        "translation_language_code": translation_lang,
        "current_level": current_level,
        "algorithm_version": "1.0",
        "prompt_version": "1",
        "prompt_status": "active",
        "prompt_role": "system",
        "prompt_text": prompt_text,
        "generated_by": "rule_based_session_prepare_v1",
        "prompt_metadata": {
            "session_id": session_id,
            "room_name": room_name,
            "source": "session_prepare_v1",
        },
        "profile_snapshot": profile,
        "plan_snapshot": {},
        "valid_from": _now_utc(),
        "valid_until": _utc_plus_hours(2),
    }

    prompt_id: str = ""
    try:
        result = await _sb_post("/rest/v1/user_cached_prompts", prompt_row)
        if isinstance(result, list) and result:
            prompt_id = str(result[0].get("prompt_id") or result[0].get("id") or "")
        elif isinstance(result, dict):
            prompt_id = str(result.get("prompt_id") or result.get("id") or "")
    except Exception as exc:
        logger.error("Failed to store prompt in user_cached_prompts: %s", exc)

    if not prompt_id:
        # Fallback: use a UUID so the rest of the flow works even if DB write failed
        prompt_id = str(uuid.uuid4())
        logger.warning("Using fallback prompt_id (DB write may have failed): %s", prompt_id)

    # ── 5. Insert session_evidence for 'session_prepared' ────────────────
    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="session_prepared",
        dialect_code=target_dialect,
        transcript_excerpt=(
            f"Session prepared for level {current_level} user. "
            f"dialect={target_dialect}, prompt_id={prompt_id}"
        ),
    )

    logger.info("Session prepared: session_id=%s user_id=%s level=%s", session_id, user_id, current_level)

    return {
        "session_id": session_id,
        "prompt_id": prompt_id,
        "user_id": user_id,
        "room_name": room_name,
        "target_dialect_code": target_dialect,
        "translation_language_code": translation_lang,
        "current_level": current_level,
        "prompt_preview": prompt_text[:300],
    }


@router.post("/{session_id}/started")
async def session_started(
    session_id: str,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    """Mark a session as started (LiveKit connected)."""
    user_id: str = user["id"]
    await _validate_session_ownership(session_id, user_id)

    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="session_started",
        transcript_excerpt="LiveKit session started by user.",
    )

    logger.info("Session started: session_id=%s user_id=%s", session_id, user_id)
    return {"status": "ok", "session_id": session_id}


@router.post("/{session_id}/ended")
async def session_ended(
    session_id: str,
    req: SessionEndedRequest,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    """Mark a session as ended and record the reason."""
    user_id: str = user["id"]
    await _validate_session_ownership(session_id, user_id)

    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="session_ended",
        transcript_excerpt=f"Session ended. Reason: {req.reason}",
    )

    logger.info(
        "Session ended: session_id=%s user_id=%s reason=%s",
        session_id,
        user_id,
        req.reason,
    )
    return {"status": "ok", "session_id": session_id, "reason": req.reason}


@router.get("/{session_id}")
async def get_session_events(
    session_id: str,
    user: dict = Depends(get_authenticated_user),
) -> list:
    """Return all session_evidence rows for this session (current user only)."""
    user_id: str = user["id"]

    rows = await _sb_get(
        "/rest/v1/session_evidence",
        params={
            "select": "*",
            "session_id": f"eq.{session_id}",
            "user_id": f"eq.{user_id}",
            "order": "created_at.asc",
        },
    )
    return rows
