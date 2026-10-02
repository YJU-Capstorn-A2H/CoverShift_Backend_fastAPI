"""
schema_v6.sql / seed_dev.sql の「韓国語の値」を「英語コード」に書き換えるスクリプト。

使い方(db フォルダで実行):
    python patch_schema_codes.py schema_v6.sql
    python patch_schema_codes.py seed_dev.sql

- 元ファイルは <名前>.bak に退避してから上書きする
- 'シングルクォートで囲まれた、対応表にある値' だけを置き換える(他の文字は触らない)
- 置き換え後に、韓国語のクォート付き値が残っていれば警告する
"""
import re
import shutil
import sys

MAPPING = {
    # employees.employment_type
    "정직원": "full_time",
    "파트타이머": "part_time",
    "아르바이트": "arbeit",
    # employees.shift_end_mode
    "계약시간까지": "until_contract_hours",
    "폐점까지": "until_closing",
    # staff_skills.status / staff_skill_self_drafts.self_status / period_off_rules.applies_to
    "미확인": "unconfirmed",
    "지도필요": "needs_guidance",
    "단독대응가능": "solo_ok",
    # shift_assignments.source
    "희망반영": "from_availability",
    "agent제안": "agent_proposal",
    "관리자수정": "manager_edit",
    # shift_approvals.action
    "승인": "approved",
    "재조정요청": "rebalance_requested",
    # contact_rounds.status
    "진행중": "in_progress",
    "확정": "confirmed",
    "상한초과_관리자대기": "limit_exceeded_awaiting_manager",
    "취소": "cancelled",  # contact_attempts.status と共通
    # contact_attempts.status
    "대기": "pending",
    "발송됨": "sent",
    "가능": "available",
    "불가능": "unavailable",
    "불확실": "uncertain",
    "타임아웃": "timed_out",
    "수동넘김": "manually_skipped",
    # onboarding_imports.status
    "업로드됨": "uploaded",
    "해석중": "interpreting",
    "AI제안완료": "ai_proposed",
    "AI실패_수동지정": "ai_failed_manual",
    "점장확인완료": "manager_confirmed",
    "반영완료": "applied",
    "폐기": "discarded",
    # period_off_rules.applies_to
    "정직원만": "full_time_only",
    "전원": "all",
}

HANGUL_QUOTED = re.compile(r"'[^']*[가-힣][^']*'")


def main(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        text = f.read()

    count = 0
    for ko, code in MAPPING.items():
        text, n = re.subn("'" + re.escape(ko) + "'", "'" + code + "'", text)
        count += n

    shutil.copyfile(path, path + ".bak")
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)

    print(f"{path}: {count} 箇所を置き換えました(元ファイルは {path}.bak)")

    # コメント行(--)以降は無視して、残った韓国語のクォート付き値を探す
    left = []
    for i, line in enumerate(text.splitlines(), 1):
        code_part = line.split("--")[0]
        for m in HANGUL_QUOTED.findall(code_part):
            left.append((i, m))
    if left:
        print("警告: 対応表にない韓国語の値が残っています。")
        for i, m in left:
            print(f"  {i}行目: {m}")
    else:
        print("OK: 韓国語のクォート付き値は残っていません。")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("使い方: python patch_schema_codes.py <ファイル名>")
        sys.exit(1)
    main(sys.argv[1])
