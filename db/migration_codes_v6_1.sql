-- =====================================================
-- 移行: 韓国語の値 → 英語コード (V6 → V6.1)
-- 目的: DBの値を言語に依存させない(画面の言葉はフロントの翻訳ファイルで切り替える)
-- 対象: すでに schema_v6.sql(旧)を流してあるDB
-- 何度流しても同じ結果になる(やり直し可能)。全体が1つのトランザクション。
-- 対応表は CODE_MAPPING.md を参照
-- =====================================================
BEGIN;

-- ---------- 1. 古いCHECK制約をすべて外す ----------
-- 対象の列にかかっているCHECK制約を、名前を調べて自動で外す
-- (import_purged_when_done は status を含むので、ここで外れる → 手順5で作り直す)
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT c.conrelid::regclass::text AS tbl, c.conname
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.contype = 'c'
      AND (c.conrelid::regclass::text, a.attname) IN (VALUES
        ('employees','employment_type'),
        ('employees','shift_end_mode'),
        ('staff_skills','status'),
        ('staff_skill_self_drafts','self_status'),
        ('shift_assignments','source'),
        ('shift_approvals','action'),
        ('contact_rounds','status'),
        ('contact_attempts','status'),
        ('onboarding_imports','status'),
        ('period_off_rules','applies_to'))
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
  END LOOP;
END $$;

-- ---------- 2. 既存データの値を変換 ----------
UPDATE employees SET employment_type = CASE employment_type
    WHEN '정직원' THEN 'full_time' WHEN '파트타이머' THEN 'part_time' WHEN '아르바이트' THEN 'arbeit'
    ELSE employment_type END;
UPDATE employees SET shift_end_mode = CASE shift_end_mode
    WHEN '계약시간까지' THEN 'until_contract_hours' WHEN '폐점까지' THEN 'until_closing'
    ELSE shift_end_mode END;

UPDATE staff_skills SET status = CASE status
    WHEN '미확인' THEN 'unconfirmed' WHEN '지도필요' THEN 'needs_guidance' WHEN '단독대응가능' THEN 'solo_ok'
    ELSE status END;
UPDATE staff_skill_self_drafts SET self_status = CASE self_status
    WHEN '미확인' THEN 'unconfirmed' WHEN '지도필요' THEN 'needs_guidance' WHEN '단독대응가능' THEN 'solo_ok'
    ELSE self_status END;

UPDATE shift_assignments SET source = CASE source
    WHEN '희망반영' THEN 'from_availability' WHEN 'agent제안' THEN 'agent_proposal' WHEN '관리자수정' THEN 'manager_edit'
    ELSE source END;
UPDATE shift_approvals SET action = CASE action
    WHEN '승인' THEN 'approved' WHEN '재조정요청' THEN 'rebalance_requested'
    ELSE action END;

UPDATE contact_rounds SET status = CASE status
    WHEN '진행중' THEN 'in_progress' WHEN '확정' THEN 'confirmed'
    WHEN '상한초과_관리자대기' THEN 'limit_exceeded_awaiting_manager' WHEN '취소' THEN 'cancelled'
    ELSE status END;
UPDATE contact_attempts SET status = CASE status
    WHEN '대기' THEN 'pending' WHEN '발송됨' THEN 'sent' WHEN '가능' THEN 'available'
    WHEN '불가능' THEN 'unavailable' WHEN '불확실' THEN 'uncertain' WHEN '타임아웃' THEN 'timed_out'
    WHEN '수동넘김' THEN 'manually_skipped' WHEN '취소' THEN 'cancelled'
    ELSE status END;

UPDATE onboarding_imports SET status = CASE status
    WHEN '업로드됨' THEN 'uploaded' WHEN '해석중' THEN 'interpreting' WHEN 'AI제안완료' THEN 'ai_proposed'
    WHEN 'AI실패_수동지정' THEN 'ai_failed_manual' WHEN '점장확인완료' THEN 'manager_confirmed'
    WHEN '반영완료' THEN 'applied' WHEN '폐기' THEN 'discarded'
    ELSE status END;
UPDATE period_off_rules SET applies_to = CASE applies_to
    WHEN '정직원만' THEN 'full_time_only' WHEN '전원' THEN 'all' WHEN '미확인' THEN 'unconfirmed'
    ELSE applies_to END;

-- ---------- 3. 初期値(DEFAULT)を英語コードに ----------
ALTER TABLE contact_rounds     ALTER COLUMN status     SET DEFAULT 'in_progress';
ALTER TABLE contact_attempts   ALTER COLUMN status     SET DEFAULT 'pending';
ALTER TABLE onboarding_imports ALTER COLUMN status     SET DEFAULT 'uploaded';
ALTER TABLE period_off_rules   ALTER COLUMN applies_to SET DEFAULT 'unconfirmed';

-- ---------- 4. 新しいCHECK制約(名前つき) ----------
ALTER TABLE employees ADD CONSTRAINT chk_employees_employment_type
    CHECK (employment_type IN ('full_time', 'part_time', 'arbeit'));
ALTER TABLE employees ADD CONSTRAINT chk_employees_shift_end_mode
    CHECK (shift_end_mode IN ('until_contract_hours', 'until_closing'));
ALTER TABLE staff_skills ADD CONSTRAINT chk_staff_skills_status
    CHECK (status IN ('unconfirmed', 'needs_guidance', 'solo_ok'));
ALTER TABLE staff_skill_self_drafts ADD CONSTRAINT chk_self_drafts_self_status
    CHECK (self_status IN ('unconfirmed', 'needs_guidance', 'solo_ok'));
ALTER TABLE shift_assignments ADD CONSTRAINT chk_assignments_source
    CHECK (source IN ('from_availability', 'agent_proposal', 'manager_edit'));
ALTER TABLE shift_approvals ADD CONSTRAINT chk_approvals_action
    CHECK (action IN ('approved', 'rebalance_requested'));
ALTER TABLE contact_rounds ADD CONSTRAINT chk_contact_rounds_status
    CHECK (status IN ('in_progress', 'confirmed', 'limit_exceeded_awaiting_manager', 'cancelled'));
ALTER TABLE contact_attempts ADD CONSTRAINT chk_contact_attempts_status
    CHECK (status IN ('pending', 'sent', 'available', 'unavailable', 'uncertain',
                      'timed_out', 'manually_skipped', 'cancelled'));
ALTER TABLE onboarding_imports ADD CONSTRAINT chk_onboarding_imports_status
    CHECK (status IN ('uploaded', 'interpreting', 'ai_proposed', 'ai_failed_manual',
                      'manager_confirmed', 'applied', 'discarded'));
ALTER TABLE period_off_rules ADD CONSTRAINT chk_period_off_rules_applies_to
    CHECK (applies_to IN ('full_time_only', 'all', 'unconfirmed'));

-- ---------- 5. status を含む制約の作り直し ----------
ALTER TABLE onboarding_imports ADD CONSTRAINT import_purged_when_done CHECK (
    status NOT IN ('applied', 'discarded') OR (raw_grid IS NULL AND token_map IS NULL)
);

COMMIT;
