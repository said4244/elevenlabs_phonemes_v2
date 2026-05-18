"""
item_chooser.py – Deterministic rule-based vocabulary item chooser.

Selects items for the next session and creates user_learning_plans /
user_learning_plan_items rows.

Selection mix (approximate, subject to availability):
  review    20-30%   items due for review or with low mastery
  current   40-60%   foundation/current-level items
  new       10-25%   never-seen items at current level
  preview    0-10%   items at current_level + 1

Env vars:
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (shared)
"""

import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any

import httpx

logger = logging.getLogger(__name__)

SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

ALGORITHM_VERSION = "item_chooser_v1"

# Configurable session size
DEFAULT_SESSION_ITEMS = 10
MAX_NEW_ITEMS = 3
MAX_PREVIEW_ITEMS = 1


# ---------------------------------------------------------------------------
# Supabase helpers
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


async def _post(path: str, body: Any) -> Any:
    async with httpx.AsyncClient(timeout=15.0) as c:
        r = await c.post(f"{SUPABASE_URL}{path}", headers=_svc_headers(), json=body)
    if r.status_code not in (200, 201):
        logger.warning("POST %s → %s: %s", path, r.status_code, r.text[:300])
        r.raise_for_status()
    return r.json()


def _now_utc() -> str:
    return datetime.now(tz=timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Candidate queries
# ---------------------------------------------------------------------------

async def _review_candidates(user_id: str, limit: int) -> list[dict]:
    """Items due for review (status=review/learning or past next_review_at)."""
    rows = await _get(
        "/rest/v1/user_item_state",
        params={
            "select": "item_id,mastery_score,confidence_score,times_seen,times_correct,"
                      "times_wrong,status,next_review_at,item_level,item_dialect_code",
            "user_id": f"eq.{user_id}",
            "status": "in.(review,learning)",
            "order": "mastery_score.asc,next_review_at.asc.nullsfirst",
            "limit": str(limit),
        },
    )
    return rows


async def _unlocked_candidates(user_id: str, current_level: int, limit: int) -> list[dict]:
    """Unlocked items at current level not yet introduced."""
    rows = await _get(
        "/rest/v1/user_item_state",
        params={
            "select": "item_id,mastery_score,confidence_score,times_seen,status,item_level",
            "user_id": f"eq.{user_id}",
            "status": "in.(unlocked,introduced)",
            "item_level": f"eq.{current_level}",
            "order": "item_id.asc",
            "limit": str(limit),
        },
    )
    return rows


async def _new_vocab_candidates(
    user_id: str, current_level: int, limit: int
) -> list[dict]:
    """Vocab items not yet in user_item_state for this user/level."""
    # Fetch known item_ids for this user
    known_rows = await _get(
        "/rest/v1/user_item_state",
        params={"select": "item_id", "user_id": f"eq.{user_id}"},
    )
    known_ids: set[int] = {int(r["item_id"]) for r in known_rows}

    # Fetch vocab candidates
    candidates = await _get(
        "/rest/v1/vocab_all",
        params={
            "select": "item_id,msa,lev_syrian,en,conversation_level",
            "conversation_level": f"eq.{current_level}",
            "order": "frequency.asc.nullslast,item_id.asc",
            "limit": str(limit + len(known_ids)),  # over-fetch then filter
        },
    )
    return [c for c in candidates if int(c["item_id"]) not in known_ids][:limit]


async def _preview_vocab_candidates(
    user_id: str, current_level: int, limit: int
) -> list[dict]:
    """Vocab items at level+1 not yet in user_item_state."""
    preview_level = current_level + 1
    if preview_level > 5:
        return []

    known_rows = await _get(
        "/rest/v1/user_item_state",
        params={"select": "item_id", "user_id": f"eq.{user_id}"},
    )
    known_ids: set[int] = {int(r["item_id"]) for r in known_rows}

    candidates = await _get(
        "/rest/v1/vocab_all",
        params={
            "select": "item_id,msa,lev_syrian,en,conversation_level",
            "conversation_level": f"eq.{preview_level}",
            "order": "frequency.asc.nullslast,item_id.asc",
            "limit": str(limit + 10),
        },
    )
    return [c for c in candidates if int(c["item_id"]) not in known_ids][:limit]


async def _enrich_item_ids(item_ids: list[int]) -> dict[int, dict]:
    """Fetch vocab_all rows for a list of item_ids, keyed by item_id."""
    if not item_ids:
        return {}
    id_str = ",".join(str(i) for i in item_ids)
    rows = await _get(
        "/rest/v1/vocab_all",
        params={
            "select": "item_id,msa,lev_syrian,en,conversation_level",
            "item_id": f"in.({id_str})",
        },
    )
    return {int(r["item_id"]): r for r in rows}


# ---------------------------------------------------------------------------
# Plan creation helpers
# ---------------------------------------------------------------------------

def _plan_item_row(
    plan_id: str,
    item_id: int,
    item_level: int,
    bucket: str,
    priority: float,
    reason_code: str,
    is_new: bool,
    is_due_review: bool,
    display_order: int,
    selected_by: str = "rule_engine",
) -> dict:
    return {
        "plan_id": plan_id,
        "item_id": item_id,
        "item_level": item_level,
        "material_bucket": bucket,  # foundation|current|preview|review
        "priority_score": round(priority, 4),
        "reason_code": reason_code,
        "is_new_item": is_new,
        "is_due_review": is_due_review,
        "selected_by": selected_by,
        "display_order": display_order,
        "notes": {},
    }


# ---------------------------------------------------------------------------
# Public: choose_items
# ---------------------------------------------------------------------------

async def choose_items(
    *,
    user_id: str,
    profile: dict,
    current_level: int,
    target_dialect_code: str,
    session_id: str,
) -> dict:
    """
    Run the deterministic item chooser.

    Returns:
      {
        "plan_id":    str,
        "plan_row":   dict,
        "items":      list[dict]   # selected item details for prompt/response
        "item_rows":  list[dict]   # user_learning_plan_items rows (already inserted)
      }
    """
    total = DEFAULT_SESSION_ITEMS

    # --- Fetch candidates -------------------------------------------------
    review_limit = max(1, round(total * 0.30))
    new_limit = min(MAX_NEW_ITEMS, max(1, round(total * 0.20)))
    preview_limit = MAX_PREVIEW_ITEMS
    foundation_limit = total  # will be trimmed after other buckets are filled

    review_rows = []
    unlocked_rows = []
    new_rows = []
    preview_rows = []

    try:
        review_rows = await _review_candidates(user_id, review_limit)
    except Exception as exc:
        logger.warning("review_candidates failed: %s", exc)

    try:
        unlocked_rows = await _unlocked_candidates(user_id, current_level, foundation_limit)
    except Exception as exc:
        logger.warning("unlocked_candidates failed: %s", exc)

    try:
        new_rows = await _new_vocab_candidates(user_id, current_level, new_limit)
    except Exception as exc:
        logger.warning("new_vocab_candidates failed: %s", exc)

    try:
        preview_rows = await _preview_vocab_candidates(user_id, current_level, preview_limit)
    except Exception as exc:
        logger.warning("preview_vocab_candidates failed: %s", exc)

    # --- Deduplicate and cap by bucket ------------------------------------
    seen_ids: set[int] = set()
    selected: list[tuple[str, dict, str, bool, bool]] = []
    # (bucket, raw_row, reason_code, is_new, is_due_review)

    # 1. Review items (due or struggling)
    for r in review_rows:
        iid = int(r["item_id"])
        if iid not in seen_ids and len([x for x in selected if x[0] == "review"]) < review_limit:
            seen_ids.add(iid)
            selected.append(("review", r, "due_review", False, True))

    # 2. Foundation/unlocked current-level items
    for r in unlocked_rows:
        iid = int(r["item_id"])
        if iid not in seen_ids:
            seen_ids.add(iid)
            selected.append(("current", r, "foundation_current", False, False))

    # 3. New items
    for r in new_rows[:new_limit]:
        iid = int(r["item_id"])
        if iid not in seen_ids:
            seen_ids.add(iid)
            selected.append(("current", r, "new_item", True, False))

    # 4. Preview items
    for r in preview_rows[:preview_limit]:
        iid = int(r["item_id"])
        if iid not in seen_ids:
            seen_ids.add(iid)
            selected.append(("preview", r, "preview_item", True, False))

    # Trim to total
    selected = selected[:total]

    # --- Enrich with vocab_all data where needed --------------------------
    item_ids_needing_vocab = [
        int(r["item_id"])
        for _, r, _, _, _ in selected
        if "msa" not in r  # user_item_state rows don't have msa
    ]
    vocab_map = {}
    if item_ids_needing_vocab:
        try:
            vocab_map = await _enrich_item_ids(item_ids_needing_vocab)
        except Exception as exc:
            logger.warning("enrich_item_ids failed: %s", exc)

    # --- Build item detail list --------------------------------------------
    item_details: list[dict] = []
    plan_item_rows: list[dict] = []
    plan_id = str(uuid.uuid4())

    for display_order, (bucket, raw, reason, is_new, is_review) in enumerate(selected):
        iid = int(raw["item_id"])
        voc = vocab_map.get(iid, raw)  # prefer vocab_all data if available
        item_level = int(raw.get("item_level") or voc.get("conversation_level") or current_level)
        mastery = float(raw.get("mastery_score") or 0.0)
        priority = (1.0 - mastery) if is_review else (0.8 if is_new else 0.6)

        item_details.append({
            "item_id": iid,
            "msa": voc.get("msa", ""),
            "lev_syrian": voc.get("lev_syrian", ""),
            "en": voc.get("en", ""),
            "bucket": bucket,
            "reason_code": reason,
            "priority_score": round(priority, 4),
            "item_level": item_level,
        })
        plan_item_rows.append(
            _plan_item_row(
                plan_id=plan_id,
                item_id=iid,
                item_level=item_level,
                bucket=bucket,
                priority=priority,
                reason_code=reason,
                is_new=is_new,
                is_due_review=is_review,
                display_order=display_order,
            )
        )

    # If nothing was selected, return empty plan without DB writes.
    # Return plan_id="" so callers treat it as no-plan (avoids FK violations).
    if not item_details:
        logger.warning("choose_items: no items selected for user=%s level=%s", user_id, current_level)
        return {"plan_id": "", "plan_row": {}, "items": [], "item_rows": []}

    # --- Compute bucket shares --------------------------------------------
    review_count = sum(1 for b, *_ in selected if b == "review")
    current_count = sum(1 for b, *_ in selected if b == "current")
    preview_count = sum(1 for b, *_ in selected if b == "preview")
    n = len(selected) or 1

    # --- Create user_learning_plans row -----------------------------------
    plan_row = {
        "plan_id": plan_id,
        "user_id": user_id,
        "current_level": current_level,
        "plan_status": "active",
        "foundation_share": round(current_count / n, 4),
        "review_share": round(review_count / n, 4),
        "new_share": round(
            sum(1 for _, _, _, is_new, _ in selected if is_new) / n, 4
        ),
        "preview_share": round(preview_count / n, 4),
        "max_new_items": MAX_NEW_ITEMS,
        "max_preview_items": MAX_PREVIEW_ITEMS,
        "algorithm_version": ALGORITHM_VERSION,
        "generated_by": "rule_engine",
        "notes": {
            "session_id": session_id,
            "total_items": len(selected),
            "chooser_version": ALGORITHM_VERSION,
        },
        "created_at": _now_utc(),
    }

    try:
        await _post("/rest/v1/user_learning_plans", plan_row)
    except Exception as exc:
        logger.error("create user_learning_plans failed: %s", exc)
        # Return items even if plan creation failed
        return {"plan_id": plan_id, "plan_row": plan_row, "items": item_details, "item_rows": []}

    # --- Create user_learning_plan_items rows -----------------------------
    if plan_item_rows:
        try:
            await _post("/rest/v1/user_learning_plan_items", plan_item_rows)
        except Exception as exc:
            logger.error("create user_learning_plan_items failed: %s", exc)

    logger.info(
        "Item chooser: plan=%s user=%s items=%d (review=%d current=%d new=%d preview=%d)",
        plan_id, user_id, len(selected), review_count, current_count,
        sum(1 for _, _, _, n_, _ in selected if n_), preview_count,
    )

    return {
        "plan_id": plan_id,
        "plan_row": plan_row,
        "items": item_details,
        "item_rows": plan_item_rows,
    }
