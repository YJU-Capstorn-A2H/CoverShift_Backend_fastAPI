-- =====================================================
-- 移行: 韓国語の値 → 英語コード (V6 → V6.1)
-- 目的: DBの値を言語に依存させない(画面の言葉はフロントの翻訳ファイルで切り替える)
-- 対象: すでに schema_v6.sql(旧)を流してあるDB
-- 特徴:
--   ・DBに無い表や列は、自動で飛ばす(schema_v6.sql が古くても動く)
--   ・何度流しても同じ結果になる(やり直し可能)
--   ・全体が1つのトランザクション(途中で失敗したら、全部取り消し)
-- 対応表は CODE_MAPPING.md を参照
-- =====================================================
BEGIN;

-- ---------- 変換表(表, 列, 旧い値, 新しいコード) ----------
CREATE TEMP TABLE _code_map (tbl text, col text, old_code text, new_code text) ON COMMIT DROP;
INSERT INTO _code_map VALUES
 ('employees','employment_type','정직원','full_time'),
 ('employees','employment_type','파트타이머','part_time'),
 ('employees','employment_type','아르바이트','arbeit'),
 ('employees','shift_end_mode','계약시간까지','until_contract_hours'),
 ('employees','shift_end_mode','폐점까지','until_closing'),
 ('staff_skills','status','미확인','unconfirmed'),
 ('staff_skills','status','지도필요','needs_guidance'),
 ('staff_skills','status','단독대응가능','solo_ok'),
 ('staff_skill_self_drafts','self_status','미확인','unconfirmed'),
 ('staff_skill_self_drafts','self_status','지도필요','needs_guidance'),
 ('staff_skill_self_drafts','self_status','단독대응가능','solo_ok'),
 ('shift_assignments','source','희망반영','from_availability'),
 ('shift_assignments','source','agent제안','agent_proposal'),
 ('shift_assignments','source','관리자수정','manager_edit'),
 ('shift_approvals','action','승인','approved'),
 ('shift_approvals','action','재조정요청','rebalance_requested'),
 ('contact_rounds','status','진행중','in_progress'),
 ('contact_rounds','status','확정','confirmed'),
 ('contact_rounds','status','상한초과_관리자대기','limit_exceeded_awaiting_manager'),
 ('contact_rounds','status','취소','cancelled'),
 ('contact_attempts','status','대기','pending'),
 ('contact_attempts','status','발송됨','sent'),
 ('contact_attempts','status','가능','available'),
 ('contact_attempts','status','불가능','unavailable'),
 ('contact_attempts','status','불확실','uncertain'),
 ('contact_attempts','status','타임아웃','timed_out'),
 ('contact_attempts','status','수동넘김','manually_skipped'),
 ('contact_attempts','status','취소','cancelled'),
 ('onboarding_imports','status','업로드됨','uploaded'),
 ('onboarding_imports','status','해석중','interpreting'),
 ('onboarding_imports','status','AI제안완료','ai_proposed'),
 ('onboarding_imports','status','AI실패_수동지정','ai_failed_manual'),
 ('onboarding_imports','status','점장확인완료','manager_confirmed'),
 ('onboarding_imports','status','반영완료','applied'),
 ('onboarding_imports','status','폐기','discarded'),
 ('period_off_rules','applies_to','정직원만','full_time_only'),
 ('period_off_rules','applies_to','전원','all'),
 ('period_off_rules','applies_to','미확인','unconfirmed');

-- 初期値(DEFAULT)を変える列
CREATE TEMP TABLE _code_default (tbl text, col text, new_default text) ON COMMIT DROP;
INSERT INTO _code_default VALUES
 ('contact_rounds','status','in_progress'),
 ('contact_attempts','status','pending'),
 ('onboarding_imports','status','uploaded'),
 ('period_off_rules','applies_to','unconfirmed');

-- ---------- 本体 ----------
DO $$
DECLARE
  r record;
  allowed text;
BEGIN
  -- 1. DBに実在する(表, 列)だけを対象にする
  FOR r IN
    SELECT DISTINCT m.tbl, m.col
    FROM _code_map m
    JOIN information_schema.columns c
      ON c.table_schema = 'public' AND c.table_name = m.tbl AND c.column_name = m.col
  LOOP
    -- 1-1. その列だけにかかっている古いCHECK制約を外す
    DECLARE c record;
    BEGIN
      FOR c IN
        SELECT con.conname
        FROM pg_constraint con
        JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
        WHERE con.contype = 'c'
          AND con.conrelid = format('public.%I', r.tbl)::regclass
          AND array_length(con.conkey, 1) = 1
          AND a.attname = r.col
      LOOP
        EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', r.tbl, c.conname);
      END LOOP;
    END;

    -- 1-2. 既存データの値を変換
    EXECUTE format(
      'UPDATE %I t SET %I = m.new_code FROM _code_map m WHERE m.tbl = %L AND m.col = %L AND t.%I = m.old_code',
      r.tbl, r.col, r.tbl, r.col, r.col);

    -- 1-3. 新しいCHECK制約(許可する値 = 新しいコードの一覧)
    SELECT string_agg(quote_literal(x.new_code), ', ' ORDER BY x.new_code) INTO allowed
    FROM (SELECT DISTINCT new_code FROM _code_map WHERE tbl = r.tbl AND col = r.col) x;
    EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I CHECK (%I IN (%s))',
                   r.tbl, 'chk_' || r.tbl || '_' || r.col, r.col, allowed);
  END LOOP;

  -- 2. 初期値(DEFAULT)
  FOR r IN
    SELECT d.* FROM _code_default d
    JOIN information_schema.columns c
      ON c.table_schema = 'public' AND c.table_name = d.tbl AND c.column_name = d.col
  LOOP
    EXECUTE format('ALTER TABLE %I ALTER COLUMN %I SET DEFAULT %L', r.tbl, r.col, r.new_default);
  END LOOP;

  -- 3. status を含む制約の作り直し(onboarding_imports がある場合だけ)
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='onboarding_imports' AND column_name='raw_grid')
     AND EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='onboarding_imports' AND column_name='token_map') THEN
    ALTER TABLE onboarding_imports DROP CONSTRAINT IF EXISTS import_purged_when_done;
    ALTER TABLE onboarding_imports ADD CONSTRAINT import_purged_when_done CHECK (
      status NOT IN ('applied', 'discarded') OR (raw_grid IS NULL AND token_map IS NULL));
  END IF;
END $$;

COMMIT;
