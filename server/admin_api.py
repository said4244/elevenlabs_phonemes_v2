"""
admin_api.py – FastAPI router for admin-only user management.

Security model:
  - Flutter sends its Supabase JWT as Authorization: Bearer <token>.
  - This backend validates the token via Supabase's /auth/v1/user endpoint
    using the SERVICE_ROLE_KEY (never exposed to Flutter).
  - If the token's email is in ADMIN_EMAILS, the request proceeds.

⚠️  The DELETE endpoint is intentionally test-only and permanently removes
    all data for a user. It is NOT safe for production use without
    additional rate-limiting and audit logging.
"""

import os
import logging
from typing import Any

import httpx
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

# Load .env so the module works whether imported or run directly.
load_dotenv()

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Config (loaded from environment – never hard-coded)
# ---------------------------------------------------------------------------

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
ADMIN_EMAILS: set[str] = {
    e.strip().lower()
    for e in os.getenv("ADMIN_EMAILS", "").split(",")
    if e.strip()
}

if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
    logger.warning(
        "SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set – "
        "admin endpoints will be disabled."
    )

# ---------------------------------------------------------------------------
# Auth dependency
# ---------------------------------------------------------------------------

_bearer = HTTPBearer()


async def _require_admin(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> str:
    """Validate the Supabase JWT and assert the user is an admin.

    Returns the verified user's email on success.
    Raises HTTP 401 / 403 on failure.
    """
    token = credentials.credentials

    # Ask Supabase to validate the token and return user info.
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{SUPABASE_URL}/auth/v1/user",
            headers={
                "Authorization": f"Bearer {token}",
                "apikey": SUPABASE_SERVICE_ROLE_KEY,
            },
        )

    if resp.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid or expired token.")

    user_data = resp.json()
    email: str = (user_data.get("email") or "").lower()

    if email not in ADMIN_EMAILS:
        raise HTTPException(status_code=403, detail="Admin access required.")

    return email


# ---------------------------------------------------------------------------
# Supabase service-role helpers
# ---------------------------------------------------------------------------

def _service_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


async def _supabase_get(path: str) -> Any:
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{SUPABASE_URL}{path}",
            headers=_service_headers(),
        )
    resp.raise_for_status()
    return resp.json()


async def _supabase_delete(path: str, params: dict | None = None) -> None:
    """Delete rows; idempotent – 404 is treated as success."""
    async with httpx.AsyncClient() as client:
        resp = await client.delete(
            f"{SUPABASE_URL}{path}",
            headers=_service_headers(),
            params=params,
        )
    if resp.status_code not in (200, 204, 404):
        logger.warning(
            "Supabase delete %s returned %s: %s",
            path,
            resp.status_code,
            resp.text,
        )


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users")
async def list_users(admin_email: str = Depends(_require_admin)) -> list[dict]:
    """Return all auth users with their public.user_profile (if any).

    Response shape:
        [{"id": "...", "email": "...", "created_at": "...", "profile": {...} | null}]
    """
    # Fetch auth users via Supabase Admin API.
    auth_data = await _supabase_get("/auth/v1/admin/users")
    auth_users: list[dict] = auth_data.get("users", [])

    # Fetch all user_profile rows.
    profiles_raw = await _supabase_get(
        "/rest/v1/user_profile?select=*"
    )
    profiles: dict[str, dict] = {p["user_id"]: p for p in profiles_raw}

    result = []
    for u in auth_users:
        uid = u.get("id", "")
        result.append(
            {
                "id": uid,
                "email": u.get("email", ""),
                "created_at": u.get("created_at", ""),
                "profile": profiles.get(uid),
            }
        )

    return result


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: str,
    admin_email: str = Depends(_require_admin),
) -> dict:
    """
    ⚠️  TEST-ONLY: Permanently deletes ALL data for user_id.

    Deletion order (child → parent to satisfy FK constraints):
      1. session_evidence
      2. conversation_analysis
      3. user_cached_prompts
      4. user_learning_plan_items  (linked via user_learning_plans)
      5. user_learning_plans
      6. user_item_state
      7. user_profile
      8. auth user (Supabase Admin API)
    """
    logger.warning(
        "⚠️  ADMIN TEST DELETE: %s is deleting user %s",
        admin_email,
        user_id,
    )

    base = "/rest/v1"
    uid_filter = f"user_id=eq.{user_id}"

    # 1. session_evidence
    await _supabase_delete(f"{base}/session_evidence?{uid_filter}")

    # 2. conversation_analysis
    await _supabase_delete(f"{base}/conversation_analysis?{uid_filter}")

    # 3. user_cached_prompts
    await _supabase_delete(f"{base}/user_cached_prompts?{uid_filter}")

    # 4. user_learning_plan_items – delete via plan ids owned by this user.
    #    First fetch plan ids, then delete items.
    try:
        plans = await _supabase_get(
            f"{base}/user_learning_plans?user_id=eq.{user_id}&select=id"
        )
        if plans:
            plan_ids = ",".join(str(p["id"]) for p in plans)
            await _supabase_delete(
                f"{base}/user_learning_plan_items?plan_id=in.({plan_ids})"
            )
    except Exception as exc:
        logger.warning("Could not delete plan items for %s: %s", user_id, exc)

    # 5. user_learning_plans
    await _supabase_delete(f"{base}/user_learning_plans?{uid_filter}")

    # 6. user_item_state
    await _supabase_delete(f"{base}/user_item_state?{uid_filter}")

    # 7. user_profile
    await _supabase_delete(f"{base}/user_profile?{uid_filter}")

    # 8. Delete the auth user via Supabase Admin API.
    async with httpx.AsyncClient() as client:
        resp = await client.delete(
            f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
            headers=_service_headers(),
        )
    if resp.status_code not in (200, 204, 404):
        raise HTTPException(
            status_code=500,
            detail=f"Failed to delete auth user: {resp.status_code} {resp.text}",
        )

    logger.info("Deleted user %s and all associated data.", user_id)
    return {"detail": f"User {user_id} and all associated data deleted."}


# ---------------------------------------------------------------------------
# Session viewer endpoints
# ---------------------------------------------------------------------------


async def _sb_get_admin(path: str, params: dict | None = None) -> Any:
    """GET with service-role headers (with explicit params dict)."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            f"{SUPABASE_URL}{path}", headers=_service_headers(), params=params
        )
    resp.raise_for_status()
    return resp.json()


async def _sb_post_admin(path: str, body: Any) -> Any:
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            f"{SUPABASE_URL}{path}", headers=_service_headers(), json=body
        )
    if resp.status_code not in (200, 201):
        resp.raise_for_status()
    return resp.json()


@router.get("/users/{user_id}/sessions")
async def get_user_sessions(
    user_id: str,
    admin_email: str = Depends(_require_admin),
) -> list[dict]:
    """
    Return sessions for a user, grouped by session_id from session_evidence.
    Each session entry includes: session_id, started_at, ended_at, status,
    evidence_count, prompt_id, dialect_code.
    """
    rows = await _sb_get_admin(
        "/rest/v1/session_evidence",
        params={
            "select": "session_id,evidence_type,dialect_code,created_at,transcript_excerpt",
            "user_id": f"eq.{user_id}",
            "order": "created_at.asc",
        },
    )

    sessions: dict[str, dict] = {}
    for row in rows:
        sid = row["session_id"]
        if sid not in sessions:
            sessions[sid] = {
                "session_id": sid,
                "started_at": None,
                "ended_at": None,
                "prepared_at": None,
                "status": "unknown",
                "evidence_count": 0,
                "prompt_id": None,
                "dialect_code": row.get("dialect_code", ""),
                "latest_event": None,
            }
        s = sessions[sid]
        s["evidence_count"] += 1
        s["latest_event"] = row["evidence_type"]
        et = row["evidence_type"]
        ts = row["created_at"]
        if et == "session_prepared":
            s["prepared_at"] = ts
            s["status"] = "prepared"
            excerpt = row.get("transcript_excerpt", "")
            for part in excerpt.split(","):
                if "prompt_id=" in part:
                    s["prompt_id"] = part.split("=", 1)[1].strip()
                    break
        elif et == "session_started":
            s["started_at"] = ts
            s["status"] = "started"
        elif et == "session_ended":
            s["ended_at"] = ts
            s["status"] = "ended"
        elif et == "session_analyzed":
            s["status"] = "analyzed"

    return sorted(sessions.values(), key=lambda x: x.get("prepared_at") or "", reverse=True)


@router.get("/sessions/{session_id}")
async def get_session_detail(
    session_id: str,
    admin_email: str = Depends(_require_admin),
) -> dict:
    """
    Full session detail: evidence, prompt, transcript, analysis, learning plan + items.
    """
    # Evidence rows
    evidence = await _sb_get_admin(
        "/rest/v1/session_evidence",
        params={
            "select": "*",
            "session_id": f"eq.{session_id}",
            "order": "created_at.asc",
        },
    )

    if not evidence:
        raise HTTPException(status_code=404, detail="Session not found.")

    user_id: str = evidence[0]["user_id"]

    # User profile
    profile_rows = await _sb_get_admin(
        "/rest/v1/user_profile",
        params={"select": "*", "user_id": f"eq.{user_id}", "limit": "1"},
    )
    profile = profile_rows[0] if profile_rows else {}

    # Auth user info (email)
    auth_email = ""
    try:
        auth_rows = await _sb_get_admin(
            "/auth/v1/admin/users",
            params={"page": "1", "per_page": "1000"},
        )
        for u in auth_rows.get("users", []):
            if u.get("id") == user_id:
                auth_email = u.get("email", "")
                break
    except Exception:
        pass

    # Prompt: look for prompt_id in evidence excerpt
    prompt_id: str | None = None
    for e in evidence:
        if e.get("evidence_type") == "session_prepared":
            excerpt = e.get("transcript_excerpt", "")
            for part in excerpt.split(","):
                if "prompt_id=" in part:
                    prompt_id = part.split("=", 1)[1].strip()
                    break
        if prompt_id:
            break

    prompt_row: dict | None = None
    if prompt_id:
        try:
            p_rows = await _sb_get_admin(
                "/rest/v1/user_cached_prompts",
                params={"select": "*", "prompt_id": f"eq.{prompt_id}", "limit": "1"},
            )
            prompt_row = p_rows[0] if p_rows else None
        except Exception as exc:
            logger.info("Could not load prompt %s: %s", prompt_id, exc)

    # Conversation analysis (transcript + analysis)
    ca_row: dict | None = None
    ca_rows = await _sb_get_admin(
        "/rest/v1/conversation_analysis",
        params={
            "select": "*",
            "user_id": f"eq.{user_id}",
            "order": "created_at.desc",
            "limit": "20",
        },
    )
    for row in ca_rows:
        t = row.get("transcript") or {}
        if isinstance(t, dict) and t.get("session_id") == session_id:
            ca_row = row
            break

    # Learning plan
    plan_row: dict | None = None
    plan_items: list[dict] = []
    if ca_row and ca_row.get("plan_id"):
        plan_id = ca_row["plan_id"]
        try:
            pl_rows = await _sb_get_admin(
                "/rest/v1/user_learning_plans",
                params={"select": "*", "plan_id": f"eq.{plan_id}", "limit": "1"},
            )
            plan_row = pl_rows[0] if pl_rows else None
            plan_items = await _sb_get_admin(
                "/rest/v1/user_learning_plan_items",
                params={"select": "*", "plan_id": f"eq.{plan_id}"},
            )
        except Exception as exc:
            logger.info("Could not load plan for session %s: %s", session_id, exc)

    return {
        "session_id": session_id,
        "user": {"id": user_id, "email": auth_email, "profile": profile},
        "evidence": evidence,
        "prompt": prompt_row,
        "transcript": ca_row.get("transcript") if ca_row else None,
        "analysis": ca_row.get("analysis") if ca_row else None,
        "conversation_analysis_id": str(ca_row["analysis_id"]) if ca_row else None,
        "learning_plan": plan_row,
        "learning_plan_items": plan_items,
    }


@router.get("/prompts/{prompt_id}")
async def get_prompt(
    prompt_id: str,
    admin_email: str = Depends(_require_admin),
) -> dict:
    rows = await _sb_get_admin(
        "/rest/v1/user_cached_prompts",
        params={"select": "*", "prompt_id": f"eq.{prompt_id}", "limit": "1"},
    )
    if not rows:
        raise HTTPException(status_code=404, detail="Prompt not found.")
    return rows[0]


@router.get("/users/{user_id}/learning-state")
async def get_learning_state(
    user_id: str,
    admin_email: str = Depends(_require_admin),
) -> dict:
    """Return user_item_state summary + all item rows."""
    item_rows = await _sb_get_admin(
        "/rest/v1/user_item_state",
        params={
            "select": "*",
            "user_id": f"eq.{user_id}",
            "order": "last_seen_at.desc",
        },
    )

    summary: dict[str, int] = {
        "total": len(item_rows),
        "mastered": 0,
        "learning": 0,
        "review": 0,
        "unlocked": 0,
        "other": 0,
    }
    for r in item_rows:
        status = r.get("status", "other")
        if status in summary:
            summary[status] += 1
        else:
            summary["other"] += 1

    profile_rows = await _sb_get_admin(
        "/rest/v1/user_profile",
        params={"select": "total_weighted_score,score_l1,score_l2,score_l3,score_l4,score_l5,current_level", "user_id": f"eq.{user_id}", "limit": "1"},
    )
    profile_scores = profile_rows[0] if profile_rows else {}

    return {
        "user_id": user_id,
        "item_state_summary": summary,
        "profile_scores": profile_scores,
        "items": item_rows,
    }


@router.post("/sessions/{session_id}/analyze")
async def admin_analyze_session(
    session_id: str,
    admin_email: str = Depends(_require_admin),
) -> dict:
    """Trigger AI analysis for any session (admin-initiated, re-runs if already analyzed)."""
    from workflows.session_analyzer import run_session_analysis
    from workflows.progress_updater import (
        apply_analysis_to_user_item_state,
        recalculate_profile_scores,
    )

    evidence = await _sb_get_admin(
        "/rest/v1/session_evidence",
        params={
            "select": "user_id",
            "session_id": f"eq.{session_id}",
            "limit": "1",
        },
    )
    if not evidence:
        raise HTTPException(status_code=404, detail="Session not found.")
    user_id = evidence[0]["user_id"]

    # Load profile
    p_rows = await _sb_get_admin(
        "/rest/v1/user_profile",
        params={"select": "*", "user_id": f"eq.{user_id}", "limit": "1"},
    )
    profile = p_rows[0] if p_rows else {}

    # Find conversation_analysis row
    ca_rows = await _sb_get_admin(
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
            detail="No transcript found for this session.",
        )

    transcript = ca_row.get("transcript") or {}
    messages: list[dict] = transcript.get("messages", []) if isinstance(transcript, dict) else []

    # Load plan items
    plan_items: list[dict] = []
    plan_id = ca_row.get("plan_id")
    if plan_id:
        try:
            pi_rows = await _sb_get_admin(
                "/rest/v1/user_learning_plan_items",
                params={"select": "item_id", "plan_id": f"eq.{plan_id}"},
            )
            item_ids = [str(r["item_id"]) for r in pi_rows if r.get("item_id")]
            if item_ids:
                plan_items = await _sb_get_admin(
                    "/rest/v1/vocab_all",
                    params={
                        "select": "item_id,msa,lev_syrian,en",
                        "item_id": f"in.({','.join(item_ids)})",
                    },
                )
        except Exception as exc:
            logger.info("Could not load plan items: %s", exc)

    analysis = await run_session_analysis(
        profile=profile,
        transcript_messages=messages,
        plan_items=plan_items,
    )

    level_score = float(analysis.get("overall_level_score") or 0.0)
    level_score_reason = str(analysis.get("level_score_reason") or "")
    ca_id = str(ca_row["analysis_id"])

    async with httpx.AsyncClient(timeout=10.0) as client:
        await client.patch(
            f"{SUPABASE_URL}/rest/v1/conversation_analysis",
            headers=_service_headers(),
            json={
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

    return {
        "conversation_analysis_id": ca_id,
        "analysis": analysis,
        "level_score": level_score,
        "progress_updates": progress_updates,
    }


@router.delete("/users/{user_id}/learning-progress")
async def reset_learning_progress(
    user_id: str,
    admin_email: str = Depends(_require_admin),
) -> dict:
    """
    Delete all learning progress for a user without deleting their account.
    Removes: user_item_state, user_learning_plans, user_learning_plan_items,
             user_cached_prompts, conversation_analysis, session_evidence.
    Keeps: auth user + user_profile.
    """
    logger.warning(
        "ADMIN: %s is resetting learning progress for user %s", admin_email, user_id
    )
    base = "/rest/v1"
    uid_filter = f"user_id=eq.{user_id}"

    await _supabase_delete(f"{base}/session_evidence?{uid_filter}")
    await _supabase_delete(f"{base}/conversation_analysis?{uid_filter}")
    await _supabase_delete(f"{base}/user_cached_prompts?{uid_filter}")

    try:
        plans = await _sb_get_admin(
            f"{base}/user_learning_plans",
            params={"select": "plan_id", "user_id": f"eq.{user_id}"},
        )
        if plans:
            plan_ids = ",".join(str(p["plan_id"]) for p in plans if p.get("plan_id"))
            if plan_ids:
                await _supabase_delete(
                    f"{base}/user_learning_plan_items?plan_id=in.({plan_ids})"
                )
    except Exception as exc:
        logger.warning("Could not delete plan items for %s: %s", user_id, exc)

    await _supabase_delete(f"{base}/user_learning_plans?{uid_filter}")
    await _supabase_delete(f"{base}/user_item_state?{uid_filter}")

    logger.info("Reset learning progress for user %s", user_id)
    return {"detail": f"Learning progress reset for user {user_id}. Profile and auth kept."}
