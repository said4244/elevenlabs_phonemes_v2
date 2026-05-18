"""
session_analyzer.py – AI-powered session analysis workflow.

Reads a conversation_analysis transcript, calls OpenAI (or compatible),
parses a strict JSON response, and stores the result back.

Env vars:
  OPENAI_API_KEY         – required for AI; omit to use deterministic fallback
  OPENAI_MODEL           – default: gpt-4o-mini
  AI_ANALYSIS_ENABLED    – "true" (default) / "false"
"""

import json
import logging
import os
from typing import Any

import httpx

logger = logging.getLogger(__name__)

OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
AI_ANALYSIS_ENABLED: bool = os.getenv("AI_ANALYSIS_ENABLED", "true").lower() == "true"

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

_SYSTEM_PROMPT = """\
You are an Arabic language learning assessment AI.
Analyze tutoring session transcripts and return ONLY a valid JSON object.
No markdown, no explanations, no extra text outside the JSON.
"""

_USER_TEMPLATE = """\
Analyze this Arabic tutoring session and return ONLY valid JSON.

## Learner Profile
{profile_summary}

## Session Transcript
{transcript}

## Vocabulary Items In This Session (use ONLY these item_ids)
{items_summary}

## Output Schema (return exactly this structure, all fields required)
{{
  "overall_level_score": <float 0.0-1.0>,
  "confidence": <float 0.0-1.0>,
  "level_score_reason": "<brief string>",
  "summary": "<2-3 sentence session summary>",
  "strengths": ["<string>"],
  "struggles": ["<string>"],
  "suggested_next_focus": ["<string>"],
  "level_recommendation": <integer 1-5>,
  "profile_observations": {{
    "interests_detected": [],
    "learning_style_notes": [],
    "confidence_notes": "<string>"
  }},
  "items": [
    {{
      "item_id": <integer — ONLY from the provided list>,
      "msa": "<word>",
      "lev_syrian": "<word>",
      "en": "<word>",
      "evidence_type": "<recognized|used_correctly|used_wrong|needed_prompt|pronunciation_issue|unknown>",
      "mastery_delta": <float -0.2 to 0.2>,
      "confidence_delta": <float -0.2 to 0.2>,
      "times_seen_delta": <0 or 1>,
      "times_correct_delta": <0 or 1>,
      "times_wrong_delta": <0 or 1>,
      "evidence": "<short excerpt or explanation>"
    }}
  ],
  "next_session_recommendations": {{
    "review_item_ids": [],
    "new_item_topics": [],
    "difficulty_adjustment": "<easier|same|slightly_harder|harder>",
    "prompt_notes": "<string>"
  }}
}}

Rules:
- level_score 0.0-1.0, level_recommendation 1-5.
- Use ONLY item_ids from the provided Vocabulary Items list.
- If no items identifiable, return "items": [].
- Return ONLY the JSON object.
"""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _fallback_analysis(reason: str) -> dict:
    return {
        "overall_level_score": 0.5,
        "confidence": 0.3,
        "level_score_reason": reason,
        "summary": "Automated analysis was not available for this session.",
        "strengths": [],
        "struggles": [],
        "suggested_next_focus": [],
        "level_recommendation": None,
        "profile_observations": {
            "interests_detected": [],
            "learning_style_notes": [],
            "confidence_notes": "",
        },
        "items": [],
        "next_session_recommendations": {
            "review_item_ids": [],
            "new_item_topics": [],
            "difficulty_adjustment": "same",
            "prompt_notes": "",
        },
        "_fallback": True,
        "_fallback_reason": reason,
    }


def _fmt_transcript(messages: list[dict]) -> str:
    lines = []
    for m in messages:
        role = m.get("role", "unknown")
        text = m.get("text", "")
        ts = m.get("timestamp", "")
        lines.append(f"[{role}]{' (' + ts + ')' if ts else ''}: {text}")
    return "\n".join(lines) or "(empty transcript)"


def _fmt_items(items: list[dict]) -> str:
    if not items:
        return "(none — do not reference any item_ids)"
    return "\n".join(
        f"  item_id={it.get('item_id')}  msa={it.get('msa','')}  "
        f"lev_syrian={it.get('lev_syrian','')}  en={it.get('en','')}"
        for it in items
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

async def run_session_analysis(
    *,
    profile: dict,
    transcript_messages: list[dict],
    plan_items: list[dict],
) -> dict:
    """
    Analyze a session transcript using OpenAI.

    Falls back to a deterministic stub when AI is unavailable.
    Never raises — always returns a dict.
    """
    if not AI_ANALYSIS_ENABLED:
        return _fallback_analysis("AI_ANALYSIS_ENABLED=false")
    if not OPENAI_API_KEY:
        return _fallback_analysis("OPENAI_API_KEY not configured")
    if not transcript_messages:
        return _fallback_analysis("Empty transcript — nothing to analyze")

    # Build profile summary
    prefs: dict = profile.get("learner_preferences") or {}
    profile_summary = (
        f"Name: {profile.get('learner_name') or profile.get('full_name') or 'Learner'}\n"
        f"Level: {profile.get('current_level', 1)}\n"
        f"Dialect: {profile.get('target_dialect_code', '')}\n"
        f"Interests: {prefs.get('interests', '')}\n"
        f"Style: {prefs.get('learning_style', '')}\n"
    )

    user_msg = _USER_TEMPLATE.format(
        profile_summary=profile_summary,
        transcript=_fmt_transcript(transcript_messages),
        items_summary=_fmt_items(plan_items),
    )

    try:
        async with httpx.AsyncClient(timeout=90.0) as client:
            resp = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {OPENAI_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": OPENAI_MODEL,
                    "messages": [
                        {"role": "system", "content": _SYSTEM_PROMPT.strip()},
                        {"role": "user", "content": user_msg.strip()},
                    ],
                    "temperature": 0.2,
                    "response_format": {"type": "json_object"},
                },
            )
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"]
        parsed: dict = json.loads(content)

        # Clamp numeric ranges
        ls = float(parsed.get("overall_level_score") or 0.5)
        parsed["overall_level_score"] = max(0.0, min(1.0, ls))
        lr = parsed.get("level_recommendation")
        if lr is not None:
            parsed["level_recommendation"] = max(1, min(5, int(lr)))

        logger.info("AI session analysis succeeded (level_score=%.2f)", parsed["overall_level_score"])
        return parsed

    except json.JSONDecodeError as exc:
        logger.warning("AI analysis returned invalid JSON: %s", exc)
        return _fallback_analysis(f"AI returned invalid JSON: {exc}")
    except Exception as exc:
        logger.error("AI analysis call failed: %s", exc)
        return _fallback_analysis(f"AI call failed: {exc}")
