# DBの値の対応表(V6 → V6.1)

DBには「言語に依存しない英語コード」を保存する。画面の言葉は、フロント(Vue)の翻訳ファイルで切り替える。
日本語表示は**案**(チームで確認して直してよい)。韓国語表示は、V6仕様書の元の値。

| テーブル.列 | 英語コード | 日本語表示(案) | 韓国語表示(元の値) |
|---|---|---|---|
| employees.employment_type | `full_time` | 正社員 | 정직원 |
| | `part_time` | パート | 파트타이머 |
| | `arbeit` | アルバイト | 아르바이트 |
| employees.shift_end_mode | `until_contract_hours` | 契約時間まで | 계약시간까지 |
| | `until_closing` | 閉店まで | 폐점까지 |
| staff_skills.status<br>staff_skill_self_drafts.self_status | `unconfirmed` | 未確認 | 미확인 |
| | `needs_guidance` | 指導必要 | 지도필요 |
| | `solo_ok` | 単独対応可 | 단독대응가능 |
| shift_assignments.source | `from_availability` | 希望反映 | 희망반영 |
| | `agent_proposal` | Agent提案 | agent제안 |
| | `manager_edit` | 管理者修正 | 관리자수정 |
| shift_approvals.action | `approved` | 承認 | 승인 |
| | `rebalance_requested` | 再調整依頼 | 재조정요청 |
| contact_rounds.status | `in_progress` | 進行中 | 진행중 |
| | `confirmed` | 確定 | 확정 |
| | `limit_exceeded_awaiting_manager` | 上限超過・管理者待ち | 상한초과_관리자대기 |
| | `cancelled` | 取消 | 취소 |
| contact_attempts.status | `pending` | 待機 | 대기 |
| | `sent` | 送信済み | 발송됨 |
| | `available` | 可能 | 가능 |
| | `unavailable` | 不可 | 불가능 |
| | `uncertain` | 不確実 | 불확실 |
| | `timed_out` | タイムアウト | 타임아웃 |
| | `manually_skipped` | 手動で次へ | 수동넘김 |
| | `cancelled` | 取消 | 취소 |
| onboarding_imports.status | `uploaded` | アップロード済み | 업로드됨 |
| | `interpreting` | 解釈中 | 해석중 |
| | `ai_proposed` | AI提案完了 | AI제안완료 |
| | `ai_failed_manual` | AI失敗・手動指定 | AI실패_수동지정 |
| | `manager_confirmed` | 店長確認完了 | 점장확인완료 |
| | `applied` | 反映完了 | 반영완료 |
| | `discarded` | 破棄 | 폐기 |
| period_off_rules.applies_to | `full_time_only` | 正社員のみ | 정직원만 |
| | `all` | 全員 | 전원 |
| | `unconfirmed` | 未確認 | 미확인 |

## 変えなかったもの
- `shift_drafts.created_by` の `'agent'` / `'manager'`:もともと英語。
- NULL の意味(例: `shift_end_mode` が NULL = 未確認):仕様書のまま。

## 注意
- 英語コードにしても、「AIが推測しない」ルール(`unconfirmed` は人数に数えない等)は変わらない。名前が変わっただけ。
- `arbeit` はアルバイトの意味(「パート」と区別するため、別のコードにしてある)。
