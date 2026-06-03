"""
partner_restaurants.json에 주소 기반 좌표를 추가하는 스크립트.
이미 lat/lng가 있는 항목은 건너뜁니다.
"""
import json
import random

random.seed(42)  # 재현 가능한 결과

JSON_PATH = r"C:\Users\tom07\Desktop\sharap-flutter\assets\data\partner_restaurants.json"


def get_base_coords(address: str):
    """주소 키워드 → (lat, lng) 기준 좌표. 매칭 안 되면 None."""
    if not address:
        return None

    # 온라인/앱/전국 서비스 → 좌표 없음
    skip = ["플랫폼", "앱/온라인", "전국", "카카오채널", "카카오톡 채널"]
    if any(k in address for k in skip):
        return None

    # ── 잠실 / 롯데월드타워 ────────────────────────────────────────────
    if any(k in address for k in ["잠실", "롯데월드타워", "롯데타워"]):
        return (37.5130, 127.1025)

    # ── 연건캠퍼스 / 대학로 / 혜화 (종로구) ──────────────────────────
    if any(k in address for k in ["창경궁", "성균관로", "동숭길", "혜화", "대학로", "종로구"]):
        return (37.5808, 126.9990)

    # ── 강남구 ───────────────────────────────────────────────────────
    if "강남구" in address or ("강남" in address and "개포" in address):
        return (37.5150, 127.0470)

    # ── 서초구 / 반포 ────────────────────────────────────────────────
    if any(k in address for k in ["서초구", "반포"]):
        return (37.5045, 127.0245)

    # ── 강북 (이훈 헤어) ─────────────────────────────────────────────
    if "강북" in address:
        return (37.6388, 127.0259)

    # ── 신림 / 녹두 ──────────────────────────────────────────────────
    if any(k in address for k in ["신림", "녹두"]):
        return (37.4845, 126.9296)

    # ── 낙성대 ───────────────────────────────────────────────────────
    if any(k in address for k in ["낙성대역", "낙성대로", "낙성대", "봉천로62길"]):
        return (37.4762, 126.9636)

    # ── 봉천동 (음대 인근) ────────────────────────────────────────────
    if "봉천" in address:
        return (37.4804, 126.9400)

    # ── 대학동 ───────────────────────────────────────────────────────
    if "대학동" in address:
        return (37.4869, 126.9601)

    # ── 관악구 세부 거리 ──────────────────────────────────────────────
    if "남부순환로230길" in address:
        return (37.4801, 126.9499)
    if "남부순환로224길" in address:
        return (37.4791, 126.9494)
    if "남부순환로234길" in address:
        return (37.4796, 126.9493)
    if "관악로14길" in address:
        return (37.4813, 126.9513)
    if "관악로16길" in address:
        return (37.4815, 126.9508)
    if "관악로 174" in address:
        return (37.4808, 126.9529)
    if "관악로 168" in address:
        return (37.4811, 126.9527)
    if "남부순환로 1846" in address:
        return (37.4811, 126.9529)

    # ── 샤로수길 ─────────────────────────────────────────────────────
    if "샤로수길" in address:
        return (37.4804, 126.9513)

    # ── 관악 / 서울대입구역 (일반) ─────────────────────────────────────
    if any(k in address for k in ["관악", "서울대입구"]):
        return (37.4811, 126.9527)

    return None


def jitter(val, scale=0.0008):
    """좌표 약간 흔들기 — 같은 지점 마커가 겹치지 않도록."""
    return round(val + random.uniform(-scale, scale), 6)


with open(JSON_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

added = 0
skipped_online = 0
already_has = 0

for item in data:
    if item.get("lat") is not None:
        already_has += 1
        continue

    coords = get_base_coords(item.get("address", ""))
    if coords:
        item["lat"] = jitter(coords[0])
        item["lng"] = jitter(coords[1])
        added += 1
    else:
        skipped_online += 1
        print(f"  [좌표 없음] {item['name']} | {item.get('address', '')}")

with open(JSON_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"\n완료: 좌표 추가 {added}개 | 이미 있음 {already_has}개 | 온라인/좌표불명 {skipped_online}개")
