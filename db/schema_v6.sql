-- =====================================================================
-- CoverShift DB schema V6 (AI 재배치안 반영 — 2차 개정 2026-09-30, 리더 승인 대기)
-- source: CoverShift_통합백엔드API및DB스키마명세서_V6.md PART 2
-- (SQL 본문은 명세서 그대로. 이 파일에서 추가한 것은 "[역할]/[연결]" 설명과 용어집뿐)
--
-- ⚠ 상태: 제안 반영 초안(미확정). 리더의 정식 승인 전에는 현행 스키마가 schema_v5.sql(V5.1)이다.
--         이 파일은 승인 후에 적용한다.
--
-- V5.1 → V6 에서 바뀐 것 (이 파일에서 `** V6 ... **` 로 표시):
--   ① employees             : shift_end_mode, contract_hours 열 추가 (** V6 2차 **)
--   ② shift_drafts          : objective_weights 열 추가 (솔버에 넘긴 5축 값의 기록)
--   ③ validation_violations : 위반 코드 2종 추가 (DUPLICATE_ASSIGNMENT, OUTSIDE_AVAILABILITY)
--   ④ contact_attempts      : 상태 「수동넘김」 추가
--   ⑤ 새 표 6개             : objective_weight_presets / draft_edit_log /
--                              onboarding_imports / historical_shifts   (1차, 맨 아래 「7.」)
--                              period_off_rules / paid_leave_records    (** V6 2차 **, 맨 아래 「7.」)
--   → 표는 21개에서 27개가 된다.
--
-- ** V6 2차(2026-09-30)의 요점 **
--   ・T2(목적함수 조정 대화)는 폐지하지 않고 유지한다 (1차의 「폐지」를 철회). 프리셋 버튼은 시작값,
--     최종 확정은 슬라이더. 5축과 목적함수는 코드에 그대로 있다.
--   ・도입 시 Excel 해석은 「고정된 LLM 1회 호출」이다 (Agent가 아님). 범례를 입력에 넣는다.
--   ・지정휴일・유급 관리를 새로 넣는다 (period_off_rules, paid_leave_records).
--
-- run (처음부터 새 DB에 만들 때):
--   docker compose cp db/schema_v6.sql db:/tmp/schema_v6.sql
--   docker compose exec db psql -U covershift -d covershift -v ON_ERROR_STOP=1 -f /tmp/schema_v6.sql
--
-- ⚠ 이미 V5.1(schema_v5.sql)로 만든 DB에는 이 파일을 다시 실행하지 않는다.
--   (CREATE TABLE이 「이미 있음」 에러가 난다.) 그 경우는 migration_v5_to_v6.sql 을 쓴다.
--   ⚠ 다만 현재의 migration_v5_to_v6.sql 은 1차분(새 표 4개, 25개)까지만 들어 있다.
--     이 파일의 2차 변경(employees 열 2개, 새 표 2개, onboarding_imports.manager_legend)은
--     아직 반영되어 있지 않다 → 마이그레이션 갱신 필요.
--
-- [읽는 순서] ① 아래 용어집 → ② 각 표의 [역할]/[연결] → ③ 표 정의
-- =====================================================================


-- =====================================================================
-- [읽는 법] SQL 용어집
-- =====================================================================
-- 열 한 줄의 형태 : 열 이름  타입  규칙
--   예) name  TEXT  NOT NULL   → "name이라는 열. 문자. 빈칸 금지"
--
-- ---------------------------------------------------------------------
-- [타입] 그 열에 넣을 수 있는 값의 종류
-- ---------------------------------------------------------------------
--   UUID         세상에 겹치지 않는 긴 랜덤 문자열 (ID용)
--   TEXT         문자
--   INT          정수
--   SMALLINT     ** V6 2차 ** 작은 정수 (INT보다 좁은 범위. 지정휴일 수처럼 작은 수에 쓴다)
--   NUMERIC(3,1) ** V6 2차 ** 소수를 정확하게 저장하는 숫자. (3,1) = 전체 3자리 중 소수점 아래 1자리.
--                예) 5.0, 7.5 (계약 근무 시간에 사용)
--   BOOLEAN      TRUE / FALSE 중 하나
--   DATE         날짜만 (예: 2026-09-28)
--   TIME         시각만 (예: 09:00)
--   TIMESTAMPTZ  날짜 + 시각. 시간대가 달라도 같은 순간으로 취급된다
--   JSONB        JSON 형식({"키": "값"})으로 저장하는 타입.
--                항목 수나 내용이 그때그때 달라지는 부가 정보를 넣을 때 쓴다.
--                (validation_violations.context에서 사용.
--                 ** V6 ** 프리셋의 5축 값, 도입 해석의 표・범례・AI 제안에서도 사용)
--   tsrange      날짜+시각의 "폭"을 하나의 값으로 가지는 타입.
--                예) [2000-01-01 09:00, 2000-01-01 12:00)
--                     [ = 시작을 포함 / ) = 끝을 포함하지 않음
--                     → "9시 이상 12시 미만". 그래서 9~12와 12~15는 겹치지 않는다.
--                (time_bands.time_range에서 사용)
--
-- ---------------------------------------------------------------------
-- [열에 붙는 규칙]
-- ---------------------------------------------------------------------
--   PRIMARY KEY         한 행을 특정하는 이름표. 중복·빈칸 금지
--   PRIMARY KEY (A, B)  두 열의 "조합"으로 한 행을 특정한다 (복합 키)
--                       예) staff_skills: 직원 + 업무의 조합이 한 행
--   NOT NULL            빈칸(NULL) 금지
--   UNIQUE              같은 값을 두 번 넣을 수 없다
--   UNIQUE (A, B)       A와 B의 "조합"이 같은 행을 두 번 넣을 수 없다
--   DEFAULT x           값을 안 주면 x를 자동으로 넣는다
--   CHECK (조건)        조건에 맞는 값만 허용한다
--   REFERENCES 표(열)   다른 표에 실제로 있는 ID만 넣을 수 있다
--                       (외래 키. 표와 표를 잇는 선)
--   ON DELETE CASCADE   연결된 원본 행을 지우면, 이 행도 함께 지운다
--   CONSTRAINT 이름 ... 규칙에 이름을 붙인다. 위반하면 에러에 이 이름이 나온다
--
-- ---------------------------------------------------------------------
-- [조건에 쓰는 말]
-- ---------------------------------------------------------------------
--   IN ('A', 'B')       A나 B 중 하나
--   NOT IN ('A', 'B')   ** V6 ** A도 B도 아니다
--   BETWEEN 1 AND 5     1 이상 5 이하 (양 끝 포함)
--   IS NULL             빈칸이다
--   IS NOT NULL         빈칸이 아니다
--   AND / OR            그리고 / 또는
--   >= / >              이상 / 초과
--   (A IS NULL) = (B IS NULL)
--                       ** V6 ** "A가 빈칸인지"와 "B가 빈칸인지"가 같아야 한다.
--                       즉 A와 B가 「둘 다 빈칸」이거나 「둘 다 값이 있음」이어야 하고,
--                       한쪽만 빈칸인 행은 거부한다.
--   X IS NULL OR X > 0  ** V6 2차 ** 「빈칸이거나, 값이 있으면 0보다 커야 한다」.
--                       빈칸(미확인)은 허용하되, 값을 넣을 거라면 0 이하는 거부한다.
--
-- ---------------------------------------------------------------------
-- [함수와 변환]
-- ---------------------------------------------------------------------
--   now()                현재 날짜+시각을 돌려주는 함수.
--                        DEFAULT now() = "입력한 순간의 시각을 자동으로 넣는다"
--   gen_random_uuid()    새 랜덤 UUID를 만들어 돌려주는 함수
--   jsonb_typeof(열)     ** V6 ** JSONB 값이 어떤 종류인지 글자로 돌려준다.
--                        'object'는 {"키": 값} 모양, 'array'는 [1, 2] 모양.
--                        (objective_weight_presets.weights가 {"키": 값} 모양인지 확인하는 데 사용)
--   값::타입             값을 다른 타입으로 바꾼다 (형 변환)
--                        예) '2000-01-01'::date → 글자 "2000-01-01"을 날짜로 바꾼다
--                        (time_bands에서 시각에 임시 날짜를 더하기 위해 사용)
--
-- ---------------------------------------------------------------------
-- [표를 만들고 바꾸는 명령]
-- ---------------------------------------------------------------------
--   CREATE TABLE 표 (...)     표를 새로 만든다
--   ALTER TABLE 표 ...        이미 만든 표를 나중에 바꾼다
--                             예) ADD CONSTRAINT = 규칙을 추가한다
--   CREATE EXTENSION x        PostgreSQL에 추가 부품(확장 기능) x를 설치한다
--   IF NOT EXISTS             이미 있으면 에러 없이 넘어간다
--                             (같은 파일을 두 번 실행해도 망가지지 않게 하는 안전장치)
--
-- ---------------------------------------------------------------------
-- [계산해서 자동으로 채우는 열 / 겹침 금지 규칙]
-- ---------------------------------------------------------------------
--   GENERATED ALWAYS AS (식) STORED
--       다른 열의 값으로 자동 계산되는 열. 직접 입력할 수 없다.
--       STORED = 계산 결과를 실제로 저장해 둔다.
--       (time_bands.time_range: 시작·종료 시각으로 "시간의 폭"을 자동으로 만든다)
--
--   EXCLUDE USING gist (열 WITH &&)
--       "이 열의 값이 서로 && (겹치는) 행 쌍은 등록시키지 않는다"는 규칙.
--       && 는 "겹친다"는 뜻의 기호이다.
--       예) 09:00~12:00이 이미 있으면, 11:00~13:00은 DB가 거부한다.
--       gist는 이 규칙을 검사하기 위한 내부 색인의 종류이다.
--       (time_bands의 no_overlapping_bands에서 사용)
--
--   btree_gist
--       위 EXCLUDE 규칙에서, 시간의 폭 외에 "같은 값이면(=)" 같은 일반 비교를
--       함께 쓸 때 필요해지는 추가 부품이다.
--       이 파일의 EXCLUDE는 시간의 폭(time_range)만 사용한다.
--       명세서가 설치를 지정했으므로 그대로 두지만, 지금 정의에서 꼭 필요한지는
--       명세서에 설명이 없다 → 팀 확인 필요.


-- Extension 설치 (시간대 중복 방지 제약용)
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- -----------------------------------------------------
-- 1. 마스터 데이터 (Master Data)
-- -----------------------------------------------------

-- 직원 마스터
-- [역할] 매장 직원 명단.
-- [연결] 계정·스킬·희망 제출·배치·승인·연락 등 많은 표가 staff_id로 이 표를 참조한다.
-- [메모] is_active(재직 여부)를 퇴사 처리에 어떻게 쓰는지는 명세서에 설명 없음 → 팀 확인 필요
-- [메모] ** V6 ** 도입 시 Excel 해석(onboarding_imports)에서 직원을 등록할 때는 name만 채우고
--        employment_type은 NULL(=미확인)로 둔다. 고용 구분은 관리자가 나중에 정한다.
-- [메모] ** V6 2차 ** shift_end_mode / contract_hours = 시프트표에 「시작 시각만」 적힌 기호
--        (예: 「17」)의 끝 시각을 정하는 재료. 시프트표만 봐서는 끝 시각을 알 수 없고,
--        AI가 지어내면 안 되기 때문에(실험: 같은 입력에서 8:00~17:00이 되기도, 17:00~22:00이 되기도 했다)
--        직원마다 「끝나는 방식」을 미리 등록해 둔다.
--          'until_contract_hours' → 끝 시각 = 시작 + contract_hours   (예: 시작 9:00, 5.0시간 → 14:00)
--          'until_closing'     → 끝 시각 = 폐점 시각
--          NULL(미확인)   → 점장이 확인하기 전에는 그 기호의 근무를 저장하지 않는다
--        같은 사람이 날마다 끝나는 방식이 다른지는 미확인이라서, 직원 단위로 충분한지는
--        팀 확인 필요(PART 8.5 #16).
CREATE TABLE employees (
    staff_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    employment_type TEXT CHECK (employment_type IN ('full_time', 'part_time', 'arbeit')),
    hired_at        DATE,
    shift_end_mode  TEXT CHECK (shift_end_mode IN ('until_contract_hours', 'until_closing')),  -- ** V6 2차 신규(제안) ** 시작 시각만 적힌 기호의 끝 시각을 정하는 방식. NULL = 미확인. 같은 사람이 날마다 다른지는 미확인(PART 8.5 #16)
    contract_hours  NUMERIC(3,1) CHECK (contract_hours IS NULL OR contract_hours > 0),   -- ** V6 2차 신규(제안) ** 계약 근무 시간(예: 5.0). shift_end_mode = 'until_contract_hours'일 때 끝 시각 = 시작 + contract_hours
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

-- 자격증 마스터
-- [역할] 자격증 목록 (예: 약사면허).
-- [연결] tasks가 "이 업무에 필요한 자격증"으로 참조한다.
CREATE TABLE qualifications (
    qualification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name              TEXT NOT NULL UNIQUE   -- 예: 약사면허
);

-- 업무 마스터 (v6 개정: requires_solo 반영. requires_solo=false인 업무는 스킬 입력 스킵)
-- [역할] 매장의 업무 목록 (예: 레지, 품출).
-- [핵심] requires_solo = TRUE  → 혼자 맡길 수 있는 사람이 필요한 업무
--        requires_solo = FALSE → 신입도 처음부터 거들 수 있는 업무 (예: 상품 보충)
-- [연결] qualifications를 참조. 필요 인원·혼잡도·스킬·검증 위반 표가 이 표를 참조한다.
CREATE TABLE tasks (
    task_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    TEXT NOT NULL,          -- 예: 레지, 품출
    requires_qualification_id UUID REFERENCES qualifications(qualification_id),
    requires_solo           BOOLEAN NOT NULL DEFAULT TRUE  -- TRUE인 경우 단독 대응 필요
);

-- 시간대 마스터 (v6 개정: congestion_weight 삭제 및 DB 레벨 중복 방지 제약 반영)
-- [역할] 하루를 나눈 시간대 목록 (예: 개점~점심). 서로 겹칠 수 없다.
-- [연결] 필요 인원·혼잡도·검증 위반 표가 이 표를 참조한다.
CREATE TABLE time_bands (
    band_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,         -- 예: 개점~점심
    start_time  TIME NOT NULL,
    end_time    TIME NOT NULL,
    sort_order  INT NOT NULL,
    time_range  tsrange GENERATED ALWAYS AS (
        tsrange('2000-01-01'::date + start_time, '2000-01-01'::date + end_time)
    ) STORED,
    -- ** V5 신규 ** 길이 0 또는 역전된 시간대 방지 / 표시 순서 중복 방지
    CONSTRAINT band_start_before_end CHECK (end_time > start_time),
    CONSTRAINT band_sort_unique UNIQUE (sort_order)
);

-- 표를 만든 뒤 규칙을 추가한다 (ALTER TABLE).
-- 시간대끼리 겹치면 등록을 거부한다. 예: 09:00~12:00이 있으면 11:00~13:00은 거부, 12:00~15:00은 허용.
ALTER TABLE time_bands
    ADD CONSTRAINT no_overlapping_bands EXCLUDE USING gist (time_range WITH &&);


-- -----------------------------------------------------
-- 2. 계정 / 인증 (매직링크 & 관리자 로그인)
-- -----------------------------------------------------

-- ** V5.1 ** accounts(LINE Login 겸용)와 invite_tokens는 삭제했다.
--   아르바이트의 PWA 접근은 매직링크(magic_link_tokens). shift_periods를 참조하므로 shift_periods 뒤에 있다.
--   관리자(Web) 로그인은 manager_accounts(이메일/비밀번호).
--   (** V6 ** 「PWA」라는 호칭은 「직원용 웹 페이지(스마트폰)」로 바꾸는 제안이 있다.
--    링크로 여는 화면의 내용은 그대로이며, 표의 구조는 변하지 않는다.)

-- 관리자 계정 (소수 인원 간이 인증. 최초 1명은 DB 시드 스크립트로 생성)
-- [역할] 관리자(Web 화면) 로그인용 계정. 이메일/비밀번호 방식. 관리자는 소수라서 간단한 인증으로 충분하다.
-- [핵심] 최초 관리자 1명은 시드 스크립트로 넣는다. password_hash에는 비밀번호 원문이 아니라 해시값을 저장한다.
-- [연결] employees를 참조. 직원 1명당 관리자 계정은 최대 1개(staff_id가 UNIQUE).
CREATE TABLE manager_accounts (
    manager_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id       UUID NOT NULL UNIQUE REFERENCES employees(staff_id),
    email          TEXT NOT NULL UNIQUE,
    password_hash  TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- LINE 연동 계정 매칭 테이블 (Webhook/수동 매칭용)
-- [역할] LINE Webhook으로 들어온 LINE 사용자를 직원과 매칭하는 표.
-- [핵심] staff_id가 NULL이면 아직 매칭되지 않은 사용자.
-- [연결] employees를 참조 (매칭된 직원, 매칭한 관리자).
-- [메모] ** V6 ** 매칭이 끝나지 않은 직원에게는 매직링크도, 조율 루프의 연락도 보낼 수 없다.
--        연락 루프가 1차의 핵심이 되므로, 「매칭이 안 된 직원」 목록이 더 중요해진다.
CREATE TABLE line_contact_registry (
    line_user_id   TEXT PRIMARY KEY,          -- LINE Webhook userId
    first_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    staff_id       UUID REFERENCES employees(staff_id),   -- NULL = 미매칭
    matched_by     UUID REFERENCES employees(staff_id),
    matched_at     TIMESTAMPTZ
);


-- -----------------------------------------------------
-- 3. 배치 기준 및 관리자 수동 설정
-- -----------------------------------------------------

-- 시간대별 업무 필요 인원
-- [역할] 시간대 × 업무별 "총 필요 인원" (명세서 PART 8의 표현: 총 인원).
-- [연결] time_bands, tasks, employees(확인자)를 참조. required_solo와 짝으로 쓴다.
-- [메모] ** V6 ** 과거 실적(historical_shifts)의 집계로 이 값의 「자동 제안」을 보여 줄 수 있다
--        (코드의 집계이며 AI가 아니다). 제안은 회색 참고 표시이고, 이 표의 초기값으로 넣지 않는다.
CREATE TABLE staffing_requirements (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id        UUID NOT NULL REFERENCES time_bands(band_id),
    task_id        UUID NOT NULL REFERENCES tasks(task_id),
    required_count INT NOT NULL DEFAULT 1 CHECK (required_count >= 0),  -- ** V5: 음수 방지 **
    verified_by    UUID REFERENCES employees(staff_id),
    verified_date  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(band_id, task_id)
);

-- 핵심 판정 근거 (band × task 단독 대응 인원)
-- [역할] 시간대 × 업무별 "단독 대응 가능한 사람의 필요 인원" (명세서의 표현: 단독 대응 인원).
-- [핵심] staffing_requirements가 총 인원이라면, 이 표는 그중 혼자 맡길 수 있는 숙련 인원의 수.
-- [연결] time_bands, tasks, employees(확인자)를 참조.
CREATE TABLE required_solo (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id        UUID NOT NULL REFERENCES time_bands(band_id),
    task_id        UUID NOT NULL REFERENCES tasks(task_id),
    required_count INT NOT NULL DEFAULT 1 CHECK (required_count >= 0),  -- ** V5: 음수 방지 **
    verified_by    UUID REFERENCES employees(staff_id),
    verified_date  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(band_id, task_id)
);

-- 관리자 수동 혼잡도 승인 (v5/v6 개정: 계산식 폐지 후 수동 입력 전환)
-- [역할] 판촉 등 특별한 날에 관리자가 수동으로 승인한 혼잡 표시.
-- [핵심] 승인 단위 = 날짜 × 시간대 × 업무. 승인된 (날짜, 시간대, 업무)의 required_solo에 +1이 적용된다.
-- [연결] time_bands, tasks, employees(확인자)를 참조.
CREATE TABLE congestion_manual (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date               DATE NOT NULL,
    band_id            UUID NOT NULL REFERENCES time_bands(band_id),
    task_id            UUID NOT NULL REFERENCES tasks(task_id),   -- ** V5 신규 **
    is_manual_override BOOLEAN NOT NULL DEFAULT TRUE,  -- 관리자 특일 승인 여부 (+1 필요 인원 적용)
    -- ** V5 확정: 승인 단위 = 날짜 × 시간대(band) × 업무(task).
    --    band는 평시 구조이고, 판촉이 어느 band의 어느 업무에 얹히는지가 판촉마다 다르기 때문.
    --    +1은 해당 (날짜, band, task)의 required_solo에만 적용된다.
    --    (requires_solo=false 업무에 대한 행은 의미가 없으므로 서비스 레이어에서 거부한다) **
    note               TEXT,
    verified_by        UUID REFERENCES employees(staff_id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(date, band_id, task_id)
);

-- ** V4 신규: 시프트 대상 기간 및 제출 마감 관리 **
-- 관리자가 새 시프트를 짜기 전에 먼저 등록한다 (congestion_manual과 같은 설계 철학:
-- AI가 추측하지 않고 관리자가 사실을 입력한다). 제출 마감은 기간마다 관리자가 수동으로 설정한다.
-- [역할] 시프트를 짜는 대상 기간과 희망 제출 마감 시각. 관리자가 시프트를 짜기 전에 먼저 등록한다.
-- [핵심] max_revision = 재조정을 최대 몇 번까지 허용하는지 (1~5)
--        notify_at = 매직링크를 자동으로 보내는 예정 일시 (스케줄러가 감시). 
--        notified_at = 실제로 보낸 일시 (NULL이면 미발송).
-- [연결] 희망 제출·시프트 초안·매직링크 토큰이 period_id로 이 표를 참조한다.
--        ** V6 2차 ** period_off_rules(지정휴일 수)와 paid_leave_records(유급 사용)도 참조한다.
CREATE TABLE shift_periods (
    period_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_start         DATE NOT NULL,
    period_end           DATE NOT NULL,
    submission_deadline  TIMESTAMPTZ NOT NULL,   -- 이 시각 이후의 제출은 "변경 리퀘스트"로 분류
    notify_at            TIMESTAMPTZ NOT NULL,   -- 매직링크 자동 발송 예정 일시 (관리자 입력. 스케줄러가 감시)
    notified_at          TIMESTAMPTZ,            -- 실제로 일괄 발송한 일시. NULL = 미발송 (중복 발송 방지)
    max_revision         INT NOT NULL DEFAULT 2 CHECK (max_revision BETWEEN 1 AND 5),  -- 관리자 슬라이더 값
    created_by           UUID REFERENCES employees(staff_id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (period_end >= period_start)
);


-- 매직링크 토큰 (아르바이트의 PWA 접근용)
-- [역할] 아르바이트가 LINE에서 받은 링크로 PWA(희망 시프트 제출 화면)를 여는 데 쓰는 토큰. 로그인 대신이다.
-- [핵심] expires_at = 발급 시 shift_periods.submission_deadline과 같은 값 (마감 = 링크 실효, 서비스 레이어 규칙).
--        유효기간 내에는 같은 링크를 다시 열 수 있다. used_at은 최초 접근 시각을 남기는 참고값이다.
--        LINE 매칭(line_contact_registry)이 끝난 직원에게만 발급한다 (서비스 레이어에서 강제).
-- [연결] employees(받는 직원), shift_periods(어느 제출 기간의 링크인지)를 참조한다.
-- [메모] ** V6 ** 마감 후 변경은 링크로 받지 않고, 점장이 관리자 화면에서 직접 수정한다(draft_edit_log에 기록).
CREATE TABLE magic_link_tokens (
    token       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id    UUID NOT NULL REFERENCES employees(staff_id),
    purpose     TEXT NOT NULL,                 -- 예: 'shift_submission'
    period_id   UUID REFERENCES shift_periods(period_id),
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    CONSTRAINT magic_link_expiry_after_issue CHECK (expires_at > issued_at)
);


-- -----------------------------------------------------
-- 4. 스킬시트 & 희망 시프트
-- -----------------------------------------------------

-- 스킬시트 확정 판정값
-- [역할] 직원 × 업무별 "관리자가 확인한" 스킬 판정 (미확인 / 지도필요 / 단독대응가능).
-- [핵심] 검증 로직은 이 표의 값을 쓴다. (직원의 자기평가는 staff_skill_self_drafts)
-- [연결] employees, tasks를 참조. 복합 키(staff_id + task_id)로 한 행을 특정.
-- [메모] ** V6 ** 도입 시 Excel 해석은 이 표를 채우지 않는다. 스킬은 시프트표에서 읽을 수 없고,
--        AI는 자격・스킬을 추측하지 않는 원칙이 있다. 관리자가 확인한 값만 들어간다.
--        (** V6 2차 ** 시프트표의 「研」 표시는 행 이름과 칸 안에서 뜻이 다르다. 스킬시트의 「지도필요」와의
--         대응은 팀 확인 전이므로 자동으로 이 표에 옮기지 않는다 → PART 8.5 #17)
CREATE TABLE staff_skills (
    staff_id      UUID NOT NULL REFERENCES employees(staff_id),
    task_id       UUID NOT NULL REFERENCES tasks(task_id),
    status        TEXT NOT NULL CHECK (status IN ('unconfirmed', 'needs_guidance', 'solo_ok')),
    verified_by   UUID REFERENCES employees(staff_id),
    verified_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (staff_id, task_id)
);

-- 스킬시트 자기평가 초안 (참고표시 전용 - AI 검증/MCP 로직에 절대 미반영)
-- [역할] 직원이 스스로 매긴 스킬 평가. 참고 표시 전용이며 검증 로직에는 쓰지 않는다.
-- [연결] employees, tasks를 참조. staff_skills와 같은 모양.
CREATE TABLE staff_skill_self_drafts (
    staff_id        UUID NOT NULL REFERENCES employees(staff_id),
    task_id         UUID NOT NULL REFERENCES tasks(task_id),
    self_status     TEXT NOT NULL CHECK (self_status IN ('unconfirmed', 'needs_guidance', 'solo_ok')),
    self_draft_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (staff_id, task_id)
);

-- 희망 시프트 제출
-- ** V4 변경: is_late_submission은 저장 컬럼이 아니라, submitted_at과
--    shift_periods.submission_deadline을 비교해 조회 시점에 판정한다 (계산값이므로 별도 컬럼 불필요) **
-- [역할] 직원이 제출한 희망 시프트. start_time/end_time이 둘 다 NULL이면 "휴무 희망".
-- [핵심] superseded_by = 같은 날을 다시 제출하면, 이전 행이 새 행으로 대체된 이력을 남긴다.
-- [연결] employees, shift_periods를 참조. 자기 자신(superseded_by)도 참조한다.
-- [메모] ** V6 ** 비고・희망 사유 열은 만들지 않는다(9/24 결정: 어떤 처리도 이 문장을 읽어 쓰지 않음).
-- [메모] ** V6 2차 ** 「희망 휴일」은 이 표의 휴무 희망(start_time IS NULL)으로 구분한다.
--        「희망이 통과된 휴일」= 휴무 희망을 낸 날 중 최종 배치가 없는 날로, 코드가 계산한다.
CREATE TABLE availability_submissions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id      UUID NOT NULL REFERENCES employees(staff_id),
    period_id     UUID REFERENCES shift_periods(period_id),  -- ** V4 신규: 어느 기간에 대한 제출인지 명시 **
    date          DATE NOT NULL,
    start_time    TIME,               -- NULL인 경우 "휴무 희망"
    end_time      TIME,
    submitted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    superseded_by UUID REFERENCES availability_submissions(id),  -- 이력 추적용
    -- ** V5 신규 ** 시작·종료는 둘 다 NULL(휴무 희망)이거나 둘 다 있고 종료>시작
    CONSTRAINT avail_time_pair CHECK (
        (start_time IS NULL AND end_time IS NULL)
        OR (start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)
    )
);


-- -----------------------------------------------------
-- 5. 시프트 Draft & 검증
-- -----------------------------------------------------

-- [역할] 시프트 초안 1건. revision 0 = 최초 초안, 1~N = 재조정본.
-- [연결] shift_periods를 참조. 배치·검증·승인·연락 표가 draft_id로 이 표를 참조한다.
-- [메모] ** V6 ** created_by = 'agent'는 「솔버·시스템이 만든 초안」이라는 뜻이다.
--        AI(LLM)가 만드는 것이 아니다. (초안 생성은 CP-SAT 솔버, 즉 코드가 한다.)
CREATE TABLE shift_drafts (
    draft_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id    UUID REFERENCES shift_periods(period_id),  -- ** V4 신규: shift_periods와 연결 **
    period_start DATE NOT NULL,
    period_end   DATE NOT NULL,
    revision     INT NOT NULL DEFAULT 0,   -- 0=초안, 1~N=재조정 (상한은 shift_periods.max_revision 참조)
    created_by   TEXT NOT NULL CHECK (created_by IN ('agent', 'manager')),
    -- ** V6 신규(제안) ** 솔버에 실제로 넘긴 5축 값의 기록.
    --   {"respect_wishes": ., "min_staffing": ., "prioritize_experienced": ., "education_placement": ., "fairness": .}
    --   NULL = 기본값으로 만들었다.
    --   ** V6 2차 ** T2 제안을 점장이 확정한 값이든, 프리셋을 골랐든, 슬라이더로 직접 정했든
    --   「그때의 값」을 그대로 남긴다.
    --   (값의 범위 검사 — 각 0.0~1.0, 합계 1.0±0.01 — 는 서비스 레이어가 한다.)
    objective_weights JSONB,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 시프트 배치 (사람 × 날짜 × 실제 근무 시각)
-- ** V5 변경: task_id 컬럼 삭제. 1차는 월간 시프트표까지이며, 업무 충족 여부(band × task)는
--    저장하지 않고 검증 시점에 코드가 계산한다(v15 §16-1 카버 판정형).
--    업무 배정(워크스케줄)은 다음 라운드에서 별도 테이블로 추가한다. **
-- [역할] 초안 안의 배치 1행 = "누가, 어느 날, 몇 시부터 몇 시까지".
-- [핵심] source = 이 배치가 어디서 왔는지 (희망반영 / agent제안 / 관리자수정)
-- [연결] shift_drafts, employees를 참조. 초안을 지우면 배치도 함께 지워진다.
-- [메모] ** V6 ** 점장이 화면에서 직접 고친 행은 source = 'manager_edit'. 고친 내용은 draft_edit_log에 남는다.
--        'agent_proposal'은 솔버의 제안을 뜻한다(AI가 아님).
CREATE TABLE shift_assignments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id   UUID NOT NULL REFERENCES shift_drafts(draft_id) ON DELETE CASCADE,
    staff_id   UUID NOT NULL REFERENCES employees(staff_id),
    date       DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time   TIME NOT NULL,
    source     TEXT NOT NULL CHECK (source IN ('from_availability', 'agent_proposal', 'manager_edit')),
    CONSTRAINT assign_start_before_end CHECK (end_time > start_time)   -- ** V5 신규 **
);
-- ※ 같은 사람의 시간 겹침 배정은 DB에서 막지 않는다: requires_solo=false 업무는 겸무가 허용되며
--    (v15 §18), 겹침 판정은 validate_draft(EXCLUSIVE_GROUP_SHORTAGE)가 담당한다.
-- ※ ** V6 ** 1차는 task_id가 없으므로, 같은 사람의 시간이 겹치는 행은 「중복 배치」로 본다.
--    이것도 DB가 막지 않고 validate_draft(DUPLICATE_ASSIGNMENT)가 잡는다.

-- [역할] 초안을 검증한 결과 1회분. ok = 통과 여부, violation_count = 위반 수.
-- [연결] shift_drafts를 참조. 위반 상세는 validation_violations가 이 표를 참조한다.
CREATE TABLE validation_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id        UUID NOT NULL REFERENCES shift_drafts(draft_id),
    revision        INT NOT NULL,
    ok              BOOLEAN NOT NULL,
    violation_count INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 검증 위반 상세 (v6 개정: EXCLUSIVE_GROUP_SHORTAGE 위반 코드 추가)
-- [역할] 검증에서 발견된 위반 1건의 상세 (어느 날·시간대·업무가 몇 명 부족한지 등).
-- [핵심] code = 위반 종류 (아래 CHECK 목록 참고). violation_key = 같은 위반을 식별하는 문자열.
-- [연결] validation_results, time_bands, tasks를 참조. 결과를 지우면 함께 지워진다.
-- [메모] ** V6 ** 위반 코드가 8종에서 10종이 된다. 두 코드는 점장의 직접 수정을 다시 검증하기 위한 것이다
--        (V16 p.36: validate_draft에 중복 배치·희망 시간 외 검사가 아직 없음).
--        OUTSIDE_AVAILABILITY를 「경고」로 다룰지 「위반」으로 다룰지는 팀 확인 필요(PART 8.5 #5).
--        ※ 「경고」로 하려면 이 표에 위반/경고를 구분하는 열이 없다 → 결정 후 열 추가가 필요할 수 있다(추측입니다).
CREATE TABLE validation_violations (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    validation_result_id UUID NOT NULL REFERENCES validation_results(id) ON DELETE CASCADE,
    code                 TEXT NOT NULL CHECK (code IN (
        'SKILL_SHORTAGE',          -- 특정 업무 단독 대응 인원 부족
        'EXCLUSIVE_GROUP_SHORTAGE',-- 단독 업무 간 겸무 불가로 인한 인원 부족
        'QUAL_MISSING',           -- 필수 자격증 미보유
        'HEADCOUNT_SHORTAGE',     -- 총원 부족
        'HEADCOUNT_EXCESS',       -- 총원 초과
        'NEWCOMER_RATIO',         -- 신입 비율 초과
        'UNVERIFIED_SKILL',       -- 스킬 미검증
        'TRAINEE_UNSUPERVISED',   -- ** V4 신규: 지도필요 인원에 대응하는 멘토(단독대응가능)가 같은 시간대에 없음 **
        'DUPLICATE_ASSIGNMENT',   -- ** V6 신규(제안) ** 같은 사람의 시간이 겹치는 배정 (1차는 task_id가 없으므로 겹침 = 중복 배치)
        'OUTSIDE_AVAILABILITY'    -- ** V6 신규(제안) ** 제출한 희망 시간 밖의 배치
    )),
    violation_key        TEXT NOT NULL,   -- 예: "SKILL_SHORTAGE|2026-08-18|14-18|레지"
    date                 DATE,
    band_id              UUID REFERENCES time_bands(band_id),
    task_id              UUID REFERENCES tasks(task_id),
    required_count       INT,
    actual_count          INT,
    context              JSONB,           -- 상세 부가 정보
    CONSTRAINT violation_key_unique UNIQUE (validation_result_id, violation_key)   -- ** V5 신규 **
);

-- [역할] 관리자가 초안을 승인했는지, 재조정을 요청했는지의 기록.
-- [연결] shift_drafts, employees(승인자)를 참조.
CREATE TABLE shift_approvals (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id     UUID NOT NULL REFERENCES shift_drafts(draft_id),
    approved_by  UUID NOT NULL REFERENCES employees(staff_id),
    action       TEXT NOT NULL CHECK (action IN ('approved', 'rebalance_requested')),
    approved_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- -----------------------------------------------------
-- 6. §20 조율 루프 (Contact Round & Attempts)
-- -----------------------------------------------------

-- 조율 루프 라운드 (부족 상황별 순차 연락 관리)
-- [역할] 인원 부족 1건을 채우기 위해, 직원에게 순서대로 연락하는 "라운드" 1회분.
-- [핵심] max_contacts = 최대 몇 명까지 순차 연락할지 (기본 3). status = 진행 상태.
-- [연결] shift_drafts를 참조. violation_key는 validation_violations의 값과 "문자열로" 맞춘다
--        (외래 키가 아니므로 DB가 일치를 보장하지 않는다).
-- [메모] ** V6 ** 조율 루프는 AI가 아니라 코드의 일이다. 연락 순서도 코드(propose_contact_order)가 정하고,
--        직원의 답은 LINE 버튼(가능/거절/불확실)으로만 받는다. 1차는 한 명씩 순서대로 연락한다.
CREATE TABLE contact_rounds (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id       UUID NOT NULL REFERENCES shift_drafts(draft_id),
    violation_key  TEXT NOT NULL,     -- validation_violations.violation_key와 매핑
    max_contacts   INT NOT NULL DEFAULT 3,   -- 관리자 설정 최대 순차 연락 인원 (기본값 3)
    status         TEXT NOT NULL CHECK (status IN ('in_progress', 'confirmed', 'limit_exceeded_awaiting_manager', 'cancelled')) DEFAULT 'in_progress',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 개별 직원 연락 시도 및 Quick Reply 상태 관리
-- ** V4 변경: timeout_at은 서비스 레이어에서 sent_at + 2시간(고정)으로 계산해 저장한다 **
-- [역할] 라운드 안에서 "직원 1명에게 연락한 기록" (보냄 → 가능/불가능/타임아웃 등).
-- [핵심] contact_order = 연락 우선순위. timeout_at = 보낸 시각 + 2시간 (서비스 코드가 계산해 넣는다).
-- [연결] contact_rounds, employees를 참조. 라운드를 지우면 함께 지워진다.
-- [메모] ** V6 신규(제안) ** status에 「수동넘김」이 추가된다. 점장이 화면에서 「응답 없음, 다음 사람에게」를
--        눌러 2시간을 기다리지 않고 넘긴 경우다. 「타임아웃」은 2시간이 지나 자동으로 넘어간 경우다.
CREATE TABLE contact_attempts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_round_id UUID NOT NULL REFERENCES contact_rounds(id) ON DELETE CASCADE,
    staff_id         UUID NOT NULL REFERENCES employees(staff_id),
    contact_order    INT NOT NULL,     -- 연락 우선순위 (1, 2, 3...)
    status           TEXT NOT NULL CHECK (status IN (
        'pending', 'sent', 'available', 'unavailable', 'uncertain', 'timed_out', 'manually_skipped', 'cancelled'   -- ** V6 신규(제안): 'manually_skipped' **
    )) DEFAULT 'pending',
    sent_at          TIMESTAMPTZ,
    responded_at     TIMESTAMPTZ,
    response_raw     TEXT,             -- LINE 원본 응답 텍스트 (참고용)
    timeout_at       TIMESTAMPTZ,      -- sent_at + 2시간 (고정값, V4 결정)
    -- ** V5 신규 ** 같은 순위·같은 사람의 이중 등록 방지
    CONSTRAINT attempt_order_unique  UNIQUE (contact_round_id, contact_order),
    CONSTRAINT attempt_person_unique UNIQUE (contact_round_id, staff_id)
);


-- -----------------------------------------------------
-- 7. ** V6 신규(제안) ** 목적함수 프리셋 / 점장 직접 수정 이력 / 도입 시 시프트표 해석 / 지정휴일・유급 관리
-- -----------------------------------------------------
-- 이 절의 표 6개가 V6에서 새로 생긴다 (21개 → 27개). 1차 4개 + 2차 2개.
-- 배경: ④(LINE 자연어 파싱)를 폐지하고, AI를 「T2(Agent)・도입 시 해석(고정 호출)・②(설명문만, 재검토)」로
--       정리하는 제안이다. Agent(반복해서 시험하고 고치는 AI)는 T2 하나다.
--       폐지한 기능이 하던 일과, 새로 생긴 일은 아래처럼 표가 받는다.
--         T2 → (유지) 5축의 시작값을 프리셋으로 주고, 최종 확정은 슬라이더   (objective_weight_presets)
--         ④  → 점장이 화면에서 직접 수정                                     (draft_edit_log)
--         도입 시 설정의 부담 경감                                           (onboarding_imports, historical_shifts)
--         ** V6 2차 ** 지정휴일・유급 관리                                   (period_off_rules, paid_leave_records)

-- 목적함수 5축 프리셋
-- [역할] 「바쁜 달」「교육 중시」「균등 중시」 같은 버튼에 대응하는 5축 가중치 세트.
--        ** V6 2차 ** T2(대화)는 유지한다. 프리셋 버튼은 「시작값」이고, 판촉의 종류가 많아 프리셋으로
--        다 적을 수 없는 부분을 T2가 점장과의 대화로 채운다. 최종 확정은 슬라이더.
-- [핵심] weights는 {"키": 값} 모양의 JSON. 5개 키(respect_wishes, min_staffing, prioritize_experienced,
--        education_placement, fairness), 각 값은 0.0~1.0이고 합계는 1.0±0.01이어야 한다.
--        이 범위 검사는 DB가 아니라 서비스 레이어(objective_weights.py)가 한다. DB가 확인하는 것은
--        weights가 {"키": 값} 모양인지(배열이 아닌지)뿐이다.
-- [연결] 다른 표가 참조하지 않는다. 솔버에 실제로 넘긴 값은 shift_drafts.objective_weights에 기록된다.
-- [메모] ⚠ 이 표의 시드(초기 데이터) 값에는 근거가 없다 (V16 p.35: 실측 기준 미확인).
--        팀이 값을 정하기 전까지는 코드의 DEFAULT_WEIGHTS 기반 잠정값이다(PART 8.5 #3).
--        값이 정해지면 시드는 별도 파일로 넣는다 (이 파일은 표의 구조만 만든다).
CREATE TABLE objective_weight_presets (
    preset_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    preset_key  TEXT NOT NULL UNIQUE,   -- 예: 'busy_month' | 'training_focus' | 'equity_focus'
    label       TEXT NOT NULL,          -- 화면에 보이는 이름 (「바쁜 달」「교육 중시」「균등 중시」)
    weights     JSONB NOT NULL,
    is_builtin  BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT weights_is_object CHECK (jsonb_typeof(weights) = 'object')
);

-- 점장의 직접 수정 이력
-- [역할] 점장이 관리자 화면에서 시프트를 직접 고친 기록. 「누가·언제·무엇을 어떻게」를 남긴다.
--        ④(LINE 자연어 파싱)를 폐지하면 마감 후 변경은 점장이 화면에서 직접 고치게 되는데,
--        전화로만 처리하고 시스템에 기록이 남지 않는 위험이 있다. 이 표가 그 위험을 줄인다.
-- [핵심] before_* = 수정 전의 근무 시각, after_* = 수정 후의 근무 시각.
--        NULL의 의미: before가 NULL = 원래 배정이 없었다 / after가 NULL = 배정을 지웠다(휴무).
--        start와 end는 「둘 다 값이 있거나 둘 다 NULL」이어야 한다 (한쪽만 있는 행은 거부).
-- [연결] shift_drafts(어느 초안), employees(수정 대상 직원, 수정한 관리자)를 참조.
-- [메모] 확정 후의 운영 시점 재검증(당일 결근 등, H-4)은 다음 라운드라서 이 표의 대상이 아니다.
--        명세서 PART 8.2 #1(수정 1회 = 새 초안 행 + parent_draft_id)이 채택되면
--        이 표는 그 방식으로 대체할 수 있다.
CREATE TABLE draft_edit_log (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id      UUID NOT NULL REFERENCES shift_drafts(draft_id),
    staff_id      UUID NOT NULL REFERENCES employees(staff_id),   -- 수정 대상 직원
    date          DATE NOT NULL,
    before_start  TIME,      -- 수정 전 (NULL = 배정 없음)
    before_end    TIME,
    after_start   TIME,      -- 수정 후 (NULL = 배정 삭제/휴무)
    after_end     TIME,
    edited_by     UUID NOT NULL REFERENCES employees(staff_id),   -- 수정한 관리자
    edited_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT edit_before_pair CHECK ((before_start IS NULL) = (before_end IS NULL)),
    CONSTRAINT edit_after_pair  CHECK ((after_start  IS NULL) = (after_end  IS NULL))
);

-- 도입 시 시프트표 해석 (Excel 한정, 도입 시 1회)
-- [역할] 기존 Excel 시프트표를 올려서 초기 설정(직원·시간대)을 만들 때의 작업 기록 1건.
--        AI는 「해석」(표 구조·기호의 뜻·시간대 구분의 제안)만 하고,
--        「옮겨 담기」(직원 등록·DB 저장)는 코드가 한다.
--        ** V6 2차 ** 이 해석은 「고정된 LLM 1회 호출」이다. Agent(반복해서 시험하고 고치는 AI)가 아니다.
--        (팀 내 실험, 2026-09-30, 4월 시트 기호 29종: 범례를 입력에 넣고 「근거 없으면 불명」을 지시하니
--         29/29, 지시 없음은 22/29. 시험한 범위에서의 결과이며 1개 점포의 시트 기준이다 → PART 8.5 #18)
-- [핵심] ① 이름을 AI에 넘기지 않는다. AI에는 「가린 표」만 보낸다.
--           같은 글자는 같은 기호(TEXT_1, TEXT_2 …)로 바꿔서 보내고, 대응표(token_map)는 이 DB에만 둔다.
--        ② raw_grid(원문·이름 포함)와 token_map은 임시 보관용이다.
--           status가 「반영완료」나 「폐기」가 되면 반드시 NULL이어야 한다 (아래 CHECK가 강제).
--           반영·폐기하지 않은 채 만료된 것은 스케줄러(purge_onboarding_imports)가 지운다.
--        ③ 점장이 확인하기 전에는 아무것도 반영되지 않는다. AI의 제안(ai_proposal)은 초안일 뿐이고,
--           코드가 믿는 것은 점장이 확인·수정한 해석(confirmed)뿐이다.
--        ④ 스킬과 필요 인원(required_solo 등)은 읽지 않는다. AI는 자격·스킬을 추측하지 않는다.
--        ⑤ ** V6 2차 ** 범례(기호→시간)를 별도 항목(manager_legend)으로 AI에 넣는다.
--           근거가 없는 값은 AI가 「불명」으로 답하게 한다 (지어내지 않게 하기 위해).
--        ⑥ ** V6 2차 ** 색・표시의 뜻(예: 청색 = 정직원)은 점포마다 다르므로 코드에 고정하지 않는다.
--           AI는 후보만 내고, 점포별 대응표를 점장이 도입 시 확인해 confirmed에 담는다.
--           (대응표를 confirmed에 둘지 별도 표로 할지, 셀 서식(배경색·글자색)을 읽는 처리가
--            설계에 있는지는 미정 → PART 8.5 #15)
-- [status의 흐름] 업로드됨 → 해석중 → AI제안완료 → 점장확인완료 → 반영완료
--                 AI가 실패하면 AI실패_수동지정 (점장이 열과 기호를 직접 지정하는 화면으로 넘어감)
--                 어느 단계에서든 폐기 가능
-- [연결] manager_accounts(올린 관리자)를 참조. historical_shifts가 이 표를 참조한다.
-- [메모] 이 표는 LangGraph 밖의 독립 서비스가 쓴다 (교수님의 LangGraph 지정 범위가 미확인이므로 확인 필요).
--        만료 기간(제안: 7일)과 동명이인·기존 직원과의 병합 규칙은 아직 정해지지 않았다.
CREATE TABLE onboarding_imports (
    import_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uploaded_by   UUID NOT NULL REFERENCES manager_accounts(manager_id),
    file_name     TEXT NOT NULL,
    status        TEXT NOT NULL CHECK (status IN (
        'uploaded', 'interpreting', 'ai_proposed', 'ai_failed_manual', 'manager_confirmed', 'applied', 'discarded'
    )) DEFAULT 'uploaded',
    raw_grid      JSONB,     -- 업로드한 표의 원문(이름 포함). 삭제 후 NULL. AI에는 절대 전달하지 않는다
    token_map     JSONB,     -- 치환 대응표(TEXT_n → 원문). 서버에만 보관. 삭제 후 NULL
    manager_legend JSONB,    -- ** V6 2차 신규 ** 범례(기호→시간). 표 하단의 범례 칸에서 코드가 뽑거나 점장이 입력한다. 이름 검사를 통과한 것만 AI에 전달한다. 범례가 없는 월(원본의 7월 등)은 점장 입력
    ai_proposal   JSONB,     -- AI 제안: ①표 구조 ②기호→시간 ③시간대 구분 ④확인이 필요한 칸 ⑤색・표시의 의미 후보. 근거가 없는 값은 「불명」 (기호는 치환 토큰 기준)
    confirmed     JSONB,     -- 점장이 확인・수정한 해석(기호→시간, 시간대, 색・표시의 의미 = 점포별 대응표). 코드는 이것만 신뢰한다
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at  TIMESTAMPTZ,
    applied_at    TIMESTAMPTZ,
    purged_at     TIMESTAMPTZ,   -- raw_grid / token_map을 지운 시각
    -- 반영 완료 또는 폐기된 작업에는 원문(이름)을 남기지 않는다
    CONSTRAINT import_purged_when_done CHECK (
        status NOT IN ('applied', 'discarded') OR (raw_grid IS NULL AND token_map IS NULL)
    )
);

-- 도입 시 읽어 들인 과거 시프트 실적
-- [역할] 기존 시프트표에서 읽은 「누가, 어느 날, 몇 시부터 몇 시까지 일했는지」의 기록.
-- [핵심] 이 표는 필요 인원의 「자동 제안」에 쓴다. 시간대별로 평소 몇 명이 일했는지를 코드가 세어서
--        staffing_requirements의 참고값으로 보여 준다 (AI가 아니라 코드의 집계이다).
--        참고값은 회색 표시일 뿐, 입력란의 초기값으로 넣지 않는다 (참고값이 판단을 끌어당기는 위험이 있기 때문).
-- [연결] onboarding_imports(어느 도입 작업에서 읽었는지), employees를 참조.
-- [메모] 「확정된 초안」을 가리키는 표시가 아직 없다는 문제(명세서 PART 8.1 #6)를,
--        이 표가 도입 데이터에 한해 우회한다.
-- ※ ** V6 2차 ** end_time이 NOT NULL이므로, 끝 시각이 정해지지 않은 행
--    (시작 시각만 있는 기호 + employees.shift_end_mode가 NULL)은 점장이 끝나는 방식을
--    확인하기 전까지 저장하지 않는다.
CREATE TABLE historical_shifts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_id   UUID NOT NULL REFERENCES onboarding_imports(import_id),
    staff_id    UUID NOT NULL REFERENCES employees(staff_id),
    date        DATE NOT NULL,
    start_time  TIME NOT NULL,
    end_time    TIME NOT NULL,
    raw_symbol  TEXT,        -- 표에 적혀 있던 근무 기호 (예: 早)
    CONSTRAINT hist_start_before_end CHECK (end_time > start_time)
);

-- ** V6 2차 신규(제안) ** 지정휴일 수의 월초 설정
-- [역할] 그 달의 「매장이 정한 지정휴일 수」. 달마다 다르다(원본 시트에서 9~11일).
--        점장이 기간(shift_periods)을 만들 때 「이번 달 지정휴일 ○일」을 함께 등록한다.
--        직원별 휴일 수의 집계는 코드가 한다(AI 아님).
-- [핵심] designated_off_days = 0~31의 정수. applies_to = 누구에게 적용되는지
--        ('full_time_only' / 'all' / 'unconfirmed'). 기본값은 'unconfirmed'(PART 8.5 #14).
--        ※ 법정 휴일 수가 아니라 「매장이 정한 지정휴일 수」로 한정한다. 노무 규제 판정은 보류 항목이다(V16 §15).
-- [연결] shift_periods(기간당 1행, period_id가 곧 기본 키), manager_accounts(설정한 관리자)를 참조.
-- [메모] 수가 맞지 않을 때 위반 코드로 할지 표시만 할지는 미정(PART 8.5 #14).
CREATE TABLE period_off_rules (
    period_id           UUID PRIMARY KEY REFERENCES shift_periods(period_id),
    designated_off_days SMALLINT NOT NULL CHECK (designated_off_days BETWEEN 0 AND 31),
    applies_to          TEXT NOT NULL DEFAULT 'unconfirmed' CHECK (applies_to IN ('full_time_only', 'all', 'unconfirmed')),  -- 누구에게 적용되는지 미확인(PART 8.5 #14)
    set_by              UUID REFERENCES manager_accounts(manager_id),
    set_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ** V6 2차 신규(제안) ** 유급 사용 기록
-- [역할] 「누가, 어느 날, 유급을 썼는지」를 점장이 기록하는 표.
-- [핵심] 「희망 휴일」은 기존 availability_submissions(start_time IS NULL)로 구분하고,
--        「희망이 통과된 휴일」= 휴무 희망을 낸 날 중 최종 배치가 없는 날로 코드가 계산한다.
--        이 표에 저장하는 것은 유급 사용뿐이다. 같은 직원의 같은 날은 1건만 넣을 수 있다.
-- [연결] employees, shift_periods, manager_accounts(기록한 관리자)를 참조.
CREATE TABLE paid_leave_records (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id    UUID NOT NULL REFERENCES employees(staff_id),
    period_id   UUID NOT NULL REFERENCES shift_periods(period_id),
    date        DATE NOT NULL,
    recorded_by UUID REFERENCES manager_accounts(manager_id),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (staff_id, date)
);