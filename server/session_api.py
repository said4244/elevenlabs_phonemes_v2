"""
session_api.py – FastAPI router for session lifecycle management.

Auth model:
  - All endpoints require Authorization: Bearer <Supabase access token>.
  - Backend validates via Supabase /auth/v1/user (never trusts client-side user_id).
  - Backend uses SERVICE_ROLE_KEY to read/write Supabase tables.

Tables used:
  - public.user_profile
  - public.user_cached_prompts
  - public.session_evidence
  - public.level_prompt_templates
  - public.conversation_analysis
  - public.user_learning_plans
  - public.user_learning_plan_items
  - public.user_item_state
  - public.vocab_all
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
# Auth helper
# ---------------------------------------------------------------------------


async def get_authenticated_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> dict:
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
# Supabase REST helpers (service-role)
# ---------------------------------------------------------------------------


def _service_headers(prefer: str = "return=representation") -> dict[str, str]:
    return {
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "application/json",
        "Prefer": prefer,
    }


async def _sb_get(path: str, params: dict | None = None) -> Any:
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            f"{SUPABASE_URL}{path}", headers=_service_headers(), params=params
        )
    resp.raise_for_status()
    return resp.json()


async def _sb_post(path: str, body: Any, prefer: str = "return=representation") -> Any:
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            f"{SUPABASE_URL}{path}", headers=_service_headers(prefer), json=body
        )
    if resp.status_code not in (200, 201):
        logger.error("Supabase POST %s -> %s: %s", path, resp.status_code, resp.text[:400])
        resp.raise_for_status()
    return resp.json()


async def _sb_patch(path: str, body: dict, params: dict | None = None) -> Any:
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.patch(
            f"{SUPABASE_URL}{path}",
            headers=_service_headers("return=minimal"),
            json=body,
            params=params,
        )
    if resp.status_code not in (200, 201, 204):
        logger.warning("PATCH %s -> %s: %s", path, resp.status_code, resp.text[:200])
    return resp.json() if resp.content else {}


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
    concept_id: str = "session_lifecycle",
    dialect_code: str = "",
    transcript_excerpt: str = "",
) -> None:
    row = {
        "session_id": session_id,
        "user_id": user_id,
        "concept_id": concept_id,
        "dialect_code": dialect_code or "",
        "evidence_type": evidence_type,
        "confidence": 1.0,
        "transcript_excerpt": transcript_excerpt,
        "created_at": _now_utc(),
    }
    try:
        await _sb_post("/rest/v1/session_evidence", row, prefer="return=minimal")
    except Exception as exc:
        logger.warning("session_evidence insert failed (%s): %s", evidence_type, exc)


async def _validate_session_ownership(session_id: str, user_id: str) -> None:
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
# Pydantic models
# ---------------------------------------------------------------------------


class PrepareSessionRequest(BaseModel):
    target_dialect_code: str | None = None
    translation_language_code: str | None = None


class SessionEndedRequest(BaseModel):
    reason: str = "user_ended"
    metadata: dict | None = None


class TranscriptMessage(BaseModel):
    role: str
    text: str
    timestamp: str | None = None
    language: str | None = None
    metadata: dict | None = None


class SaveTranscriptRequest(BaseModel):
    prompt_id: str | None = None
    plan_id: str | None = None
    messages: list[TranscriptMessage] = []
    metadata: dict | None = None


class CompleteSessionRequest(BaseModel):
    prompt_id: str | None = None
    plan_id: str | None = None
    messages: list[TranscriptMessage] = []
    end_reason: str = "user_ended"


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

router = APIRouter(prefix="/session", tags=["session"])


# == POST /session/prepare ==================================================

@router.post("/prepare")
async def prepare_session(
    req: PrepareSessionRequest,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    from workflows.item_chooser import choose_items
    from workflows.prompt_builder_ai import build_prompt_ai
    from workflows.progress_updater import initialize_user_item_state_if_needed

    user_id: str = user["id"]

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

    target_dialect: str = (
        req.target_dialect_code or profile.get("target_dialect_code") or "msa"
    )
    translation_lang: str = (
        req.translation_language_code
        or profile.get("translation_language_code")
        or "en"
    )
    current_level: int = int(profile.get("current_level") or 1)

    level_template: dict | None = None
    try:
        tmpl_rows = await _sb_get(
            "/rest/v1/level_prompt_templates",
            params={"select": "*", "level": f"eq.{current_level}", "limit": "1"},
        )
        if tmpl_rows:
            level_template = tmpl_rows[0]
    except Exception as exc:
        logger.info("level_prompt_templates unavailable: %s", exc)

    session_id: str = str(uuid.uuid4())
    room_name: str = f"huda-session-{session_id}"

    try:
        seeded = await initialize_user_item_state_if_needed(
            user_id, current_level, target_dialect
        )
        if seeded:
            logger.info("Seeded %d starter items for user=%s", seeded, user_id)
    except Exception as exc:
        logger.warning("initialize_user_item_state_if_needed failed: %s", exc)

    plan_id: str = ""
    selected_items: list[dict] = []
    try:
        chooser_result = await choose_items(
            user_id=user_id,
            profile=profile,
            current_level=current_level,
            target_dialect_code=target_dialect,
            session_id=session_id,
        )
        plan_id = chooser_result.get("plan_id", "")
        selected_items = chooser_result.get("items", [])
    except Exception as exc:
        logger.warning("Item chooser failed (continuing without plan): %s", exc)
        plan_id = str(uuid.uuid4())

    recent_analysis: dict | None = None
    try:
        ca_rows = await _sb_get(
            "/rest/v1/conversation_analysis",
            params={
                "select": "analysis,level_score",
                "user_id": f"eq.{user_id}",
                "order": "created_at.desc",
                "limit": "1",
            },
        )
        if ca_rows and ca_rows[0].get("analysis"):
            recent_analysis = ca_rows[0]["analysis"]
    except Exception as exc:
        logger.info("No recent analysis available: %s", exc)

    try:
        prompt_result = await build_prompt_ai(
            profile=profile,
            level_template=level_template,
            selected_items=selected_items,
            recent_analysis=recent_analysis,
        )
    except Exception as exc:
        logger.error("build_prompt_ai failed, using rule-based fallback: %s", exc)
        prompt_result = {
            "prompt_text": build_first_session_prompt(profile, level_template),
            "prompt_summary": "(fallback)",
            "generated_by": "rule_engine",
            "prompt_version": "v1_rule_based",
            "fallback_used": True,
        }

    prompt_row = {
        "user_id": user_id,
        "plan_id": plan_id or None,
        "target_dialect_code": target_dialect,
        "translation_language_code": translation_lang,
        "current_level": current_level,
        "algorithm_version": "2.0",
        "prompt_version": prompt_result.get("prompt_version", "v1_rule_based"),
        "prompt_status": "active",
        "prompt_role": "system",
        "prompt_text": prompt_result["prompt_text"],
        "generated_by": prompt_result.get("generated_by", "rule_engine"),
        "prompt_metadata": {
            "session_id": session_id,
            "room_name": room_name,
            "source": "ai_prompt_builder_v1",
            "fallback_used": prompt_result.get("fallback_used", False),
        },
        "profile_snapshot": profile,
        "plan_snapshot": {"items": selected_items, "plan_id": plan_id},
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
        logger.error("Failed to store prompt: %s", exc)

    if not prompt_id:
        prompt_id = str(uuid.uuid4())
        logger.warning("Using fallback prompt_id: %s", prompt_id)

    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="session_prepared",
        dialect_code=target_dialect,
        transcript_excerpt=(
            f"Session prepared for level {current_level} user. "
            f"dialect={target_dialect}, prompt_id={prompt_id}, "
            f"plan_id={plan_id}, items={len(selected_items)}"
        ),
    )
    if plan_id:
        await _insert_session_evidence(
            session_id=session_id,
            user_id=user_id,
            evidence_type="learning_plan_created",
            concept_id="item_chooser",
            transcript_excerpt=f"Learning plan created: plan_id={plan_id}, items={len(selected_items)}",
        )
    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="prompt_prepared",
        concept_id="prompt_builder",
        transcript_excerpt=(
            f"Prompt stored: prompt_id={prompt_id}, "
            f"generated_by={prompt_result.get('generated_by','unknown')}"
        ),
    )

    logger.info(
        "Session prepared: session_id=%s user_id=%s level=%s plan_id=%s items=%d",
        session_id, user_id, current_level, plan_id, len(selected_items),
    )

    return {
        "session_id": session_id,
        "prompt_id": prompt_id,
        "plan_id": plan_id,
        "user_id": user_id,
        "room_name": room_name,
        "target_dialect_code": target_dialect,
        "translation_language_code": translation_lang,
        "current_level": current_level,
        "selected_items": selected_items,
        "prompt_preview": prompt_result["prompt_text"][:300],
    }


# == POST /session/{session_id}/started =====================================

@router.post("/{session_id}/started")
async def session_started(
    session_id: str,
    user: dict = Depends(get_authenticated_user),
) -> dict:
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


# == POST /session/{session_id}/ended =======================================

@router.post("/{session_id}/ended")
async def session_ended(
    session_id: str,
    req: SessionEndedRequest,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    user_id: str = user["id"]
    await _validate_session_ownership(session_id, user_id)
    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="session_ended",
        transcript_excerpt=f"Session ended. Reason: {req.reason}",
    )
    logger.info(
        "Session ended: session_id=%s user_id=%s reason=%s", session_id, user_id, req.reason
    )
    return {"status": "ok", "session_id": session_id, "reason": req.reason}


# == GET /session/{session_id} ==============================================

@router.get("/{session_id}")
async def get_session_events(
    session_id: str,
    user: dict = Depends(get_authenticated_user),
) -> list:
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


# == POST /session/{session_id}/transcript ==================================

@router.post("/{session_id}/transcript")
async def save_transcript(
    session_id: str,
    req: SaveTranscriptRequest,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    user_id: str = user["id"]
    await _validate_session_ownership(session_id, user_id)

    prompt_id = req.prompt_id
    if not prompt_id:
        try:
            p_rows = await _sb_get(
                "/rest/v1/user_cached_prompts",
                params={
                    "select": "prompt_id,prompt_metadata",
                    "user_id": f"eq.{user_id}",
                    "prompt_status": "eq.active",
                    "order": "created_at.desc",
                    "limit": "10",
                },
            )
            for p in p_rows:
                meta = p.get("prompt_metadata") or {}
                if isinstance(meta, dict) and meta.get("session_id") == session_id:
                    prompt_id = str(p["prompt_id"])
                    break
        except Exception as exc:
            logger.info("Could not resolve prompt_id for session %s: %s", session_id, exc)

    transcript_json = {
        "session_id": session_id,
        "messages": [m.model_dump(exclude_none=True) for m in req.messages],
        "metadata": req.metadata or {},
    }

    ca_id: str = ""
    if prompt_id:
        existing = await _sb_get(
            "/rest/v1/conversation_analysis",
            params={
                "select": "analysis_id",
                "user_id": f"eq.{user_id}",
                "prompt_id": f"eq.{prompt_id}",
                "limit": "1",
            },
        )
        if existing:
            ca_id = str(existing[0]["analysis_id"])
            await _sb_patch(
                "/rest/v1/conversation_analysis",
                {"transcript": transcript_json},
                params={"analysis_id": f"eq.{ca_id}"},
            )

    if not ca_id:
        row = {
            "user_id": user_id,
            "plan_id": req.plan_id or None,
            "prompt_id": prompt_id or None,
            "transcript": transcript_json,
            "analysis": None,
        }
        try:
            result = await _sb_post("/rest/v1/conversation_analysis", row)
            if isinstance(result, list) and result:
                ca_id = str(result[0].get("analysis_id", ""))
            elif isinstance(result, dict):
                ca_id = str(result.get("analysis_id", ""))
        except Exception as exc:
            logger.error("Save transcript failed: %s", exc)
            raise HTTPException(status_code=500, detail=f"Failed to save transcript: {exc}")

    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="transcript_saved",
        concept_id="session_lifecycle",
        transcript_excerpt=f"Saved transcript with {len(req.messages)} messages",
    )

    logger.info(
        "Transcript saved: session_id=%s user_id=%s messages=%d ca_id=%s",
        session_id, user_id, len(req.messages), ca_id,
    )
    return {
        "status": "ok",
        "conversation_analysis_id": ca_id,
        "message_count": len(req.messages),
    }


# == POST /session/{session_id}/analyze =====================================

@router.post("/{session_id}/analyze")
async def analyze_session(
    session_id: str,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    from workflows.session_analyzer import run_session_analysis
    from workflows.progress_updater import (
        apply_analysis_to_user_item_state,
        recalculate_profile_scores,
    )

    user_id: str = user["id"]
    await _validate_session_ownership(session_id, user_id)

    p_rows = await _sb_get(
        "/rest/v1/user_profile",
        params={"select": "*", "user_id": f"eq.{user_id}", "limit": "1"},
    )
    profile = p_rows[0] if p_rows else {}

    ca_rows = await _sb_get(
        "/rest/v1/conversation_analysis",
        params={
            "select": "analysis_id,transcript,prompt_id,plan_id",
            "user_id": f"eq.{user_id}",
            "order": "created_at.desc",
            "limit": "20",
        },
    )
    ca_row: dict | None = None
    for row in ca_rows:
        t = row.get("transcript") or {}
        if isinstance(t, dict) and t.get("session_id") == session_id:
            ca_row = row
            break

    if not ca_row:
        raise HTTPException(
            status_code=400,
            detail="No transcript found for this session. Save a transcript first.",
        )

    transcript = ca_row.get("transcript") or {}
    messages: list[dict] = transcript.get("messages", []) if isinstance(transcript, dict) else []

    plan_items: list[dict] = []
    plan_id = ca_row.get("plan_id")
    if plan_id:
        try:
            pi_rows = await _sb_get(
                "/rest/v1/user_learning_plan_items",
                params={"select": "item_id,material_bucket", "plan_id": f"eq.{plan_id}"},
            )
            item_ids = [str(r["item_id"]) for r in pi_rows if r.get("item_id")]
            if item_ids:
                plan_items = await _sb_get(
                    "/rest/v1/vocab_all",
                    params={
                        "select": "item_id,msa,lev_syrian,en",
                        "item_id": f"in.({','.join(item_ids)})",
                    },
                )
        except Exception as exc:
            logger.info("Could not load plan items for analysis: %s", exc)

    analysis = await run_session_analysis(
        profile=profile,
        transcript_messages=messages,
        plan_items=plan_items,
    )

    level_score = float(analysis.get("overall_level_score") or 0.0)
    level_score_reason = str(analysis.get("level_score_reason") or "")
    ca_id = str(ca_row["analysis_id"])

    await _sb_patch(
        "/rest/v1/conversation_analysis",
        {
            "analysis": analysis,
            "level_score": level_score,
            "level_score_reason": level_score_reason,
        },
        params={"analysis_id": f"eq.{ca_id}"},
    )

    progress_updates: dict = {}
    try:
        progress_updates = await apply_analysis_to_user_item_state(user_id, analysis)
        await recalculate_profile_scores(user_id)
    except Exception as exc:
        logger.error("Progress update failed: %s", exc)
        progress_updates = {"error": str(exc)}

    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="session_analyzed",
        concept_id="session_analysis",
        transcript_excerpt=(
            f"Analysis complete. level_score={level_score:.2f}. "
            f"Summary: {analysis.get('summary','')[:120]}"
        ),
    )

    logger.info(
        "Session analyzed: session_id=%s user_id=%s level_score=%.2f",
        session_id, user_id, level_score,
    )
    return {
        "conversation_analysis_id": ca_id,
        "analysis": analysis,
        "level_score": level_score,
        "progress_updates": progress_updates,
    }


# == POST /session/{session_id}/complete ====================================

@router.post("/{session_id}/complete")
async def complete_session(
    session_id: str,
    req: CompleteSessionRequest,
    user: dict = Depends(get_authenticated_user),
) -> dict:
    user_id: str = user["id"]
    await _validate_session_ownership(session_id, user_id)

    transcript_result = await save_transcript(
        session_id,
        SaveTranscriptRequest(
            prompt_id=req.prompt_id,
            plan_id=req.plan_id,
            messages=req.messages,
        ),
        user,
    )
    ca_id = transcript_result.get("conversation_analysis_id", "")

    await _insert_session_evidence(
        session_id=session_id,
        user_id=user_id,
        evidence_type="session_ended",
        transcript_excerpt=f"Session ended. Reason: {req.end_reason}",
    )

    analysis_result: dict = {"status": "skipped"}
    try:
        analysis_result = await analyze_session(session_id, user)
    except HTTPException as exc:
        logger.info("Analysis skipped for session %s: %s", session_id, exc.detail)
        analysis_result = {"status": "skipped", "reason": exc.detail}
    except Exception as exc:
        logger.error("Analysis failed for session %s: %s", session_id, exc)
        analysis_result = {"status": "error", "reason": str(exc)}

    return {
        "status": "ok",
        "session_id": session_id,
        "conversation_analysis_id": ca_id,
        "analysis": analysis_result.get("analysis"),
        "level_score": analysis_result.get("level_score"),
        "progress_updates": analysis_result.get("progress_updates"),
    }
