-- =====================================================================
-- CoverShift DB schema V5.1
-- source: CoverShift_통합백엔드API및DB스키마명세서_V5.1_FullVersion.md PART 2
-- (SQL 본문은 명세서 그대로. 이 파일에서 추가한 것은 "[역할]/[연결]" 설명과 용어집뿐)
--
-- run:
--   docker compose cp db/schema_v5.sql db:/tmp/schema_v5.sql
--   docker compose exec db psql -U covershift -d covershift -v ON_ERROR_STOP=1 -f /tmp/schema_v5.sql
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
--   BOOLEAN      TRUE / FALSE 중 하나
--   DATE         날짜만 (예: 2026-09-28)
--   TIME         시각만 (예: 09:00)
--   TIMESTAMPTZ  날짜 + 시각. 시간대가 달라도 같은 순간으로 취급된다
--   JSONB        JSON 형식({"키": "값"})으로 저장하는 타입.
--                항목 수나 내용이 그때그때 달라지는 부가 정보를 넣을 때 쓴다.
--                (validation_violations.context에서 사용)
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
--   BETWEEN 1 AND 5     1 이상 5 이하 (양 끝 포함)
--   IS NULL             빈칸이다
--   IS NOT NULL         빈칸이 아니다
--   AND / OR            그리고 / 또는
--   >= / >              이상 / 초과
--
-- ---------------------------------------------------------------------
-- [함수와 변환]
-- ---------------------------------------------------------------------
--   now()                현재 날짜+시각을 돌려주는 함수.
--                        DEFAULT now() = "입력한 순간의 시각을 자동으로 넣는다"
--   gen_random_uuid()    새 랜덤 UUID를 만들어 돌려주는 함수
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
CREATE TABLE employees (
    staff_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    employment_type TEXT CHECK (employment_type IN ('정직원', '파트타이머', '아르바이트')),
    hired_at        DATE,
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
CREATE TABLE staff_skills (
    staff_id      UUID NOT NULL REFERENCES employees(staff_id),
    task_id       UUID NOT NULL REFERENCES tasks(task_id),
    status        TEXT NOT NULL CHECK (status IN ('미확인', '지도필요', '단독대응가능')),
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
    self_status     TEXT NOT NULL CHECK (self_status IN ('미확인', '지도필요', '단독대응가능')),
    self_draft_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (staff_id, task_id)
);

-- 희망 시프트 제출
-- ** V4 변경: is_late_submission은 저장 컬럼이 아니라, submitted_at과
--    shift_periods.submission_deadline을 비교해 조회 시점에 판정한다 (계산값이므로 별도 컬럼 불필요) **
-- [역할] 직원이 제출한 희망 시프트. start_time/end_time이 둘 다 NULL이면 "휴무 희망".
-- [핵심] superseded_by = 같은 날을 다시 제출하면, 이전 행이 새 행으로 대체된 이력을 남긴다.
-- [연결] employees, shift_periods를 참조. 자기 자신(superseded_by)도 참조한다.
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
CREATE TABLE shift_drafts (
    draft_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id    UUID REFERENCES shift_periods(period_id),  -- ** V4 신규: shift_periods와 연결 **
    period_start DATE NOT NULL,
    period_end   DATE NOT NULL,
    revision     INT NOT NULL DEFAULT 0,   -- 0=초안, 1~N=재조정 (상한은 shift_periods.max_revision 참조)
    created_by   TEXT NOT NULL CHECK (created_by IN ('agent', 'manager')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 시프트 배치 (사람 × 날짜 × 실제 근무 시각)
-- ** V5 변경: task_id 컬럼 삭제. 1차는 월간 시프트표까지이며, 업무 충족 여부(band × task)는
--    저장하지 않고 검증 시점에 코드가 계산한다(v15 §16-1 카버 판정형).
--    업무 배정(워크스케줄)은 다음 라운드에서 별도 테이블로 추가한다. **
-- [역할] 초안 안의 배치 1행 = "누가, 어느 날, 몇 시부터 몇 시까지".
-- [핵심] source = 이 배치가 어디서 왔는지 (희망반영 / agent제안 / 관리자수정)
-- [연결] shift_drafts, employees를 참조. 초안을 지우면 배치도 함께 지워진다.
CREATE TABLE shift_assignments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id   UUID NOT NULL REFERENCES shift_drafts(draft_id) ON DELETE CASCADE,
    staff_id   UUID NOT NULL REFERENCES employees(staff_id),
    date       DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time   TIME NOT NULL,
    source     TEXT NOT NULL CHECK (source IN ('희망반영', 'agent제안', '관리자수정')),
    CONSTRAINT assign_start_before_end CHECK (end_time > start_time)   -- ** V5 신규 **
);
-- ※ 같은 사람의 시간 겹침 배정은 DB에서 막지 않는다: requires_solo=false 업무는 겸무가 허용되며
--    (v15 §18), 겹침 판정은 validate_draft(EXCLUSIVE_GROUP_SHORTAGE)가 담당한다.

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
        'TRAINEE_UNSUPERVISED'    -- ** V4 신규: 지도필요 인원에 대응하는 멘토(단독대응가능)가 같은 시간대에 없음 **
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
    action       TEXT NOT NULL CHECK (action IN ('승인', '재조정요청')),
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
CREATE TABLE contact_rounds (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id       UUID NOT NULL REFERENCES shift_drafts(draft_id),
    violation_key  TEXT NOT NULL,     -- validation_violations.violation_key와 매핑
    max_contacts   INT NOT NULL DEFAULT 3,   -- 관리자 설정 최대 순차 연락 인원 (기본값 3)
    status         TEXT NOT NULL CHECK (status IN ('진행중', '확정', '상한초과_관리자대기', '취소')) DEFAULT '진행중',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 개별 직원 연락 시도 및 Quick Reply 상태 관리
-- ** V4 변경: timeout_at은 서비스 레이어에서 sent_at + 2시간(고정)으로 계산해 저장한다 **
-- [역할] 라운드 안에서 "직원 1명에게 연락한 기록" (보냄 → 가능/불가능/타임아웃 등).
-- [핵심] contact_order = 연락 우선순위. timeout_at = 보낸 시각 + 2시간 (서비스 코드가 계산해 넣는다).
-- [연결] contact_rounds, employees를 참조. 라운드를 지우면 함께 지워진다.
CREATE TABLE contact_attempts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_round_id UUID NOT NULL REFERENCES contact_rounds(id) ON DELETE CASCADE,
    staff_id         UUID NOT NULL REFERENCES employees(staff_id),
    contact_order    INT NOT NULL,     -- 연락 우선순위 (1, 2, 3...)
    status           TEXT NOT NULL CHECK (status IN (
        '대기', '발송됨', '가능', '불가능', '불확실', '타임아웃', '취소'
    )) DEFAULT '대기',
    sent_at          TIMESTAMPTZ,
    responded_at     TIMESTAMPTZ,
    response_raw     TEXT,             -- LINE 원본 응답 텍스트 (참고용)
    timeout_at       TIMESTAMPTZ,      -- sent_at + 2시간 (고정값, V4 결정)
    -- ** V5 신규 ** 같은 순위·같은 사람의 이중 등록 방지
    CONSTRAINT attempt_order_unique  UNIQUE (contact_round_id, contact_order),
    CONSTRAINT attempt_person_unique UNIQUE (contact_round_id, staff_id)
);