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
