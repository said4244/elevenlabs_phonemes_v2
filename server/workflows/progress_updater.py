"""
progress_updater.py – Manages user_item_state and user_profile score fields.

All Supabase writes use the service-role key (bypasses RLS).
Flutter never writes these tables directly.
"""

import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx

logger = logging.getLogger(__name__)

SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

STARTER_ITEM_COUNT = 15  # rows bootstrapped on first session


# ---------------------------------------------------------------------------
# Supabase helpers (local copies so this module has no import cycle)
# ---------------------------------------------------------------------------

def _svc_headers(prefer: str = "return=representation") -> dict:
    return {
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "application/json",
        "Prefer": prefer,
    }


async def _get(path: str, params: dict | None = None) -> Any:
    async with httpx.AsyncClient(timeout=10.0) as c:
        r = await c.get(f"{SUPABASE_URL}{path}", headers=_svc_headers(), params=params)
    r.raise_for_status()
    return r.json()


async def _post(path: str, body: Any, prefer: str = "return=minimal") -> Any:
    async with httpx.AsyncClient(timeout=15.0) as c:
        r = await c.post(f"{SUPABASE_URL}{path}", headers=_svc_headers(prefer), json=body)
    if r.status_code not in (200, 201):
        logger.warning("POST %s → %s: %s", path, r.status_code, r.text[:200])
    return r.json() if r.content else {}


async def _patch(path: str, body: dict, params: dict | None = None) -> Any:
    async with httpx.AsyncClient(timeout=10.0) as c:
        r = await c.patch(
            f"{SUPABASE_URL}{path}",
            headers=_svc_headers("return=minimal"),
            json=body,
            params=params,
        )
    if r.status_code not in (200, 201, 204):
        logger.warning("PATCH %s → %s: %s", path, r.status_code, r.text[:200])
    return r.json() if r.content else {}


# ---------------------------------------------------------------------------
# Time helpers
# ---------------------------------------------------------------------------

def _now_utc() -> str:
    return datetime.now(tz=timezone.utc).isoformat()


def _utc_plus_hours(h: float) -> str:
    return (datetime.now(tz=timezone.utc) + timedelta(hours=h)).isoformat()


def _clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, float(v)))


# ---------------------------------------------------------------------------
# Status / scheduling helpers
# ---------------------------------------------------------------------------

def _derive_status(
    mastery: float,
    times_wrong: int,
    times_correct: int,
    times_seen: int,
    evidence_type: str,
) -> str:
    """Return a valid user_item_state.status enum value."""
    if mastery >= 0.85:
        return "mastered"
    if evidence_type in ("used_wrong", "pronunciation_issue"):
        return "review"
    if times_wrong > times_correct and times_seen > 1:
        return "review"
    if times_seen > 0:
        return "learning"
    return "unlocked"


def _next_review_at(status: str, evidence_type: str) -> str:
    if status == "mastered":
        return _utc_plus_hours(7 * 24)
    if evidence_type in ("used_wrong", "pronunciation_issue") or status == "review":
        return _utc_plus_hours(12)
    return _utc_plus_hours(24)


# ---------------------------------------------------------------------------
# 1. Initialize starter set
# ---------------------------------------------------------------------------

async def initialize_user_item_state_if_needed(
    user_id: str,
    current_level: int,
    target_dialect_code: str,
) -> int:
    """
    Bootstrap user_item_state with STARTER_ITEM_COUNT vocab items
    if the user has no rows yet.

    Returns number of rows created (0 if already initialized).
    """
    existing = await _get(
        "/rest/v1/user_item_state",
        params={"select": "item_id", "user_id": f"eq.{user_id}", "limit": "1"},
    )
    if existing:
        return 0  # Already seeded

    candidates = await _get(
        "/rest/v1/vocab_all",
        params={
            "select": "item_id,msa,lev_syrian,en,conversation_level",
            "conversation_level": f"eq.{current_level}",
            "order": "frequency.asc.nullslast,item_id.asc",
            "limit": str(STARTER_ITEM_COUNT),
        },
    )

    if not candidates:
        logger.warning(
            "initialize_user_item_state: no vocab_all rows for level=%s", current_level
        )
        return 0

    rows = [
        {
            "user_id": user_id,
            "item_id": item["item_id"],
            "item_level": item.get("conversation_level", current_level),
            "item_dialect_code": target_dialect_code,
            "status": "unlocked",
            "mastery_score": 0.0,
            "confidence_score": 0.0,
            "times_seen": 0,
            "times_correct": 0,
            "times_wrong": 0,
            "times_prompted": 0,
            "unlocked_at": _now_utc(),
            "metadata": {"source": "starter_initialization_v1"},
        }
        for item in candidates
    ]

    try:
        async with httpx.AsyncClient(timeout=20.0) as c:
            r = await c.post(
                f"{SUPABASE_URL}/rest/v1/user_item_state",
                headers=_svc_headers("return=minimal,resolution=ignore-duplicates"),
                json=rows,
            )
        if r.status_code not in (200, 201):
            logger.warning(
                "Batch insert user_item_state: %s %s", r.status_code, r.text[:200]
            )
    except Exception as exc:
        logger.error("initialize_user_item_state_if_needed error: %s", exc)
        return 0

    logger.info(
        "Initialized %d starter items for user=%s level=%s",
        len(rows), user_id, current_level,
    )
    return len(rows)


# ---------------------------------------------------------------------------
# 2. Apply analysis deltas
# ---------------------------------------------------------------------------

async def apply_analysis_to_user_item_state(user_id: str, analysis: dict) -> dict:
    """
    Apply AI-analysis item deltas to user_item_state rows.

    Returns {"updated": N, "created": M}.
    """
    items: list[dict] = analysis.get("items") or []
    updated = created = 0

    for item_data in items:
        item_id = item_data.get("item_id")
        if not item_id:
            continue

        ev_type = item_data.get("evidence_type", "unknown")
        mastery_d = _clamp(float(item_data.get("mastery_delta", 0.0)), -0.5, 0.5)
        conf_d = _clamp(float(item_data.get("confidence_delta", 0.0)), -0.5, 0.5)
        ts_d = max(0, int(item_data.get("times_seen_delta", 0)))
        tc_d = max(0, int(item_data.get("times_correct_delta", 0)))
        tw_d = max(0, int(item_data.get("times_wrong_delta", 0)))

        existing_rows = await _get(
            "/rest/v1/user_item_state",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "item_id": f"eq.{item_id}",
                "limit": "1",
            },
        )

        if existing_rows:
            row = existing_rows[0]
            nm = _clamp(float(row.get("mastery_score") or 0) + mastery_d)
            nc = _clamp(float(row.get("confidence_score") or 0) + conf_d)
            nts = int(row.get("times_seen") or 0) + ts_d
            ntc = int(row.get("times_correct") or 0) + tc_d
            ntw = int(row.get("times_wrong") or 0) + tw_d
            new_status = _derive_status(nm, ntw, ntc, nts, ev_type)

            await _patch(
                "/rest/v1/user_item_state",
                {
                    "mastery_score": nm,
                    "confidence_score": nc,
                    "times_seen": nts,
                    "times_correct": ntc,
                    "times_wrong": ntw,
                    "status": new_status,
                    "last_seen_at": _now_utc(),
                    "next_review_at": _next_review_at(new_status, ev_type),
                },
                params={"user_id": f"eq.{user_id}", "item_id": f"eq.{item_id}"},
            )
            updated += 1
        else:
            nm = _clamp(mastery_d)
            nc = _clamp(conf_d)
            new_status = _derive_status(nm, tw_d, tc_d, ts_d, ev_type)
            try:
                async with httpx.AsyncClient(timeout=10.0) as c:
                    r = await c.post(
                        f"{SUPABASE_URL}/rest/v1/user_item_state",
                        headers=_svc_headers("return=minimal,resolution=ignore-duplicates"),
                        json={
                            "user_id": user_id,
                            "item_id": item_id,
                            "item_level": item_data.get("item_level"),
                            "item_dialect_code": "",
                            "status": new_status,
                            "mastery_score": nm,
                            "confidence_score": nc,
                            "times_seen": ts_d,
                            "times_correct": tc_d,
                            "times_wrong": tw_d,
                            "times_prompted": 0,
                            "last_seen_at": _now_utc(),
                            "next_review_at": _next_review_at(new_status, ev_type),
                            "unlocked_at": _now_utc(),
                            "metadata": {"source": "analysis_update_v1"},
                        },
                    )
                if r.status_code in (200, 201):
                    created += 1
            except Exception as exc:
                logger.warning("create user_item_state item_id=%s: %s", item_id, exc)

    return {"updated": updated, "created": created}


# ---------------------------------------------------------------------------
# 3. Recalculate profile scores
# ---------------------------------------------------------------------------

async def recalculate_profile_scores(user_id: str) -> dict:
    """
    Recompute score_l1..score_l5 and total_weighted_score from user_item_state,
    then PATCH user_profile.

    Returns the fields that were written.
    """
    rows = await _get(
        "/rest/v1/user_item_state",
        params={"select": "item_level,mastery_score,status", "user_id": f"eq.{user_id}"},
    )

    buckets: dict[int, list[float]] = {i: [] for i in range(1, 6)}
    for item in rows:
        lv = int(item.get("item_level") or 1)
        ms = float(item.get("mastery_score") or 0.0)
        if 1 <= lv <= 5:
            buckets[lv].append(ms)

    score_fields: dict[str, Any] = {}
    total = 0.0
    for lv in range(1, 6):
        lst = buckets[lv]
        avg = sum(lst) / len(lst) if lst else 0.0
        score_fields[f"score_l{lv}"] = round(avg, 4)
        total += avg * lv  # weight by level

    score_fields["total_weighted_score"] = round(total, 4)
    score_fields["last_analyzed_at"] = _now_utc()

    await _patch(
        "/rest/v1/user_profile",
        score_fields,
        params={"user_id": f"eq.{user_id}"},
    )
    logger.info("Recalculated profile scores for user=%s: %s", user_id, score_fields)
    return score_fields
