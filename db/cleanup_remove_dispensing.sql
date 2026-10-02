-- 開発DBに入っている「調剤」「薬剤師免許(ダミー)」のシードデータだけを消す
-- (seed_dev.sql 由来の固定IDの行だけが対象。他のデータには触れない)
BEGIN;
DELETE FROM staff_skills            WHERE task_id = '00000000-0000-0000-0000-000000000c02';
DELETE FROM staff_skill_self_drafts WHERE task_id = '00000000-0000-0000-0000-000000000c02';
DELETE FROM tasks                   WHERE task_id = '00000000-0000-0000-0000-000000000c02';
DELETE FROM qualifications          WHERE qualification_id = '00000000-0000-0000-0000-000000000b01';
COMMIT;
