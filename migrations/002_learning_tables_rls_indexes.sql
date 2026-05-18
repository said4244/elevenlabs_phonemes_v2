-- =============================================================================
-- Migration 002: RLS policies and indexes for learning tables
-- =============================================================================
-- Security model:
--   - Users can SELECT their own rows (read-only via app).
--   - Backend service-role key handles all INSERT/UPDATE/DELETE (bypasses RLS).
--   - Authenticated users can SELECT vocab/reference tables.
--   - Admin emails access data via backend service-role (no direct DB admin needed).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- user_item_state
-- ---------------------------------------------------------------------------

ALTER TABLE public.user_item_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_item_state_select_own" ON public.user_item_state;
CREATE POLICY "user_item_state_select_own"
  ON public.user_item_state
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- No direct INSERT/UPDATE/DELETE policies: backend uses service-role key.

-- ---------------------------------------------------------------------------
-- user_learning_plans
-- ---------------------------------------------------------------------------

ALTER TABLE public.user_learning_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_learning_plans_select_own" ON public.user_learning_plans;
CREATE POLICY "user_learning_plans_select_own"
  ON public.user_learning_plans
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- user_learning_plan_items
-- ---------------------------------------------------------------------------

ALTER TABLE public.user_learning_plan_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_learning_plan_items_select_own" ON public.user_learning_plan_items;
CREATE POLICY "user_learning_plan_items_select_own"
  ON public.user_learning_plan_items
  FOR SELECT
  TO authenticated
  USING (
    plan_id IN (
      SELECT plan_id
      FROM public.user_learning_plans
      WHERE user_id = (SELECT auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- conversation_analysis
-- ---------------------------------------------------------------------------

ALTER TABLE public.conversation_analysis ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conversation_analysis_select_own" ON public.conversation_analysis;
CREATE POLICY "conversation_analysis_select_own"
  ON public.conversation_analysis
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- vocab_all  (read-only for all authenticated users)
-- ---------------------------------------------------------------------------

ALTER TABLE public.vocab_all ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vocab_all_select_authenticated" ON public.vocab_all;
CREATE POLICY "vocab_all_select_authenticated"
  ON public.vocab_all
  FOR SELECT
  TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- algorithm_rules  (read-only for all authenticated users)
-- ---------------------------------------------------------------------------

ALTER TABLE public.algorithm_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "algorithm_rules_select_authenticated" ON public.algorithm_rules;
CREATE POLICY "algorithm_rules_select_authenticated"
  ON public.algorithm_rules
  FOR SELECT
  TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- user_item_state
CREATE INDEX IF NOT EXISTS idx_user_item_state_user_id
  ON public.user_item_state (user_id);

CREATE INDEX IF NOT EXISTS idx_user_item_state_user_item
  ON public.user_item_state (user_id, item_id);

-- user_learning_plans
CREATE INDEX IF NOT EXISTS idx_user_learning_plans_user_id
  ON public.user_learning_plans (user_id);

-- user_learning_plan_items
CREATE INDEX IF NOT EXISTS idx_user_learning_plan_items_plan_id
  ON public.user_learning_plan_items (plan_id);

CREATE INDEX IF NOT EXISTS idx_user_learning_plan_items_plan_item
  ON public.user_learning_plan_items (plan_id, item_id);

-- conversation_analysis
CREATE INDEX IF NOT EXISTS idx_conversation_analysis_user_id
  ON public.conversation_analysis (user_id);

CREATE INDEX IF NOT EXISTS idx_conversation_analysis_prompt_id
  ON public.conversation_analysis (prompt_id);

CREATE INDEX IF NOT EXISTS idx_conversation_analysis_plan_id
  ON public.conversation_analysis (plan_id);

CREATE INDEX IF NOT EXISTS idx_conversation_analysis_user_created
  ON public.conversation_analysis (user_id, created_at DESC);

-- vocab_all: support item chooser queries by level and frequency
CREATE INDEX IF NOT EXISTS idx_vocab_all_conversation_level
  ON public.vocab_all (conversation_level);

CREATE INDEX IF NOT EXISTS idx_vocab_all_level_freq
  ON public.vocab_all (conversation_level, frequency);
