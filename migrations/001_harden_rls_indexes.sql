-- ============================================================
-- Migration 001: Harden RLS & add performance indexes
-- ============================================================

-- ── user_profile ──────────────────────────────────────────

ALTER TABLE IF EXISTS public.user_profile ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_profile: users can select own row" ON public.user_profile;
CREATE POLICY "user_profile: users can select own row"
  ON public.user_profile
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_profile: users can insert own row" ON public.user_profile;
CREATE POLICY "user_profile: users can insert own row"
  ON public.user_profile
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_profile: users can update own row" ON public.user_profile;
CREATE POLICY "user_profile: users can update own row"
  ON public.user_profile
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_profile: deny direct delete" ON public.user_profile;
CREATE POLICY "user_profile: deny direct delete"
  ON public.user_profile
  FOR DELETE
  USING (false);

-- ── session_evidence ─────────────────────────────────────

ALTER TABLE IF EXISTS public.session_evidence ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "session_evidence: users can select own rows" ON public.session_evidence;
CREATE POLICY "session_evidence: users can select own rows"
  ON public.session_evidence
  FOR SELECT
  USING (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "session_evidence: deny direct insert" ON public.session_evidence;
CREATE POLICY "session_evidence: deny direct insert"
  ON public.session_evidence
  FOR INSERT
  WITH CHECK (false);

DROP POLICY IF EXISTS "session_evidence: deny direct update" ON public.session_evidence;
CREATE POLICY "session_evidence: deny direct update"
  ON public.session_evidence
  FOR UPDATE
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS "session_evidence: deny direct delete" ON public.session_evidence;
CREATE POLICY "session_evidence: deny direct delete"
  ON public.session_evidence
  FOR DELETE
  USING (false);

-- ── user_cached_prompts ──────────────────────────────────

ALTER TABLE IF EXISTS public.user_cached_prompts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_cached_prompts: users can select own rows" ON public.user_cached_prompts;
CREATE POLICY "user_cached_prompts: users can select own rows"
  ON public.user_cached_prompts
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_cached_prompts: deny direct insert" ON public.user_cached_prompts;
CREATE POLICY "user_cached_prompts: deny direct insert"
  ON public.user_cached_prompts
  FOR INSERT
  WITH CHECK (false);

DROP POLICY IF EXISTS "user_cached_prompts: deny direct update" ON public.user_cached_prompts;
CREATE POLICY "user_cached_prompts: deny direct update"
  ON public.user_cached_prompts
  FOR UPDATE
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS "user_cached_prompts: deny direct delete" ON public.user_cached_prompts;
CREATE POLICY "user_cached_prompts: deny direct delete"
  ON public.user_cached_prompts
  FOR DELETE
  USING (false);

-- ── level_prompt_templates ───────────────────────────────

ALTER TABLE IF EXISTS public.level_prompt_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "level_prompt_templates: authenticated read" ON public.level_prompt_templates;
CREATE POLICY "level_prompt_templates: authenticated read"
  ON public.level_prompt_templates
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- ── Performance indexes ──────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_session_evidence_user_id
  ON public.session_evidence (user_id);

CREATE INDEX IF NOT EXISTS idx_session_evidence_session_id
  ON public.session_evidence (session_id);

CREATE INDEX IF NOT EXISTS idx_user_cached_prompts_user_id
  ON public.user_cached_prompts (user_id);
