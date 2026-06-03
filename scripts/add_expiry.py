"""
expiresAt, couponCode 필드를 partner_restaurants.json에 추가하는 스크립트.
"""
import json

JSON_PATH = r"C:\Users\tom07\Desktop\sharap-flutter\assets\data\partner_restaurants.json"

with open(JSON_PATH, encoding="utf-8") as f:
    data = json.load(f)

# 만료일 규칙
# 수의대 샤로수길 제휴 (2026.11.31 → 2026-11-30)
VET_SHAROSU_IDS = {
    "vet_donggyeong_sanchaek", "vet_gran_ppiatti", "vet_sadam",
    "vet_redbutton", "vet_ssukgogae", "vet_onyu",
}
# 동경산책 3~6월 한정
DONGGYEONG_ID = "vet_donggyeong_sanchaek"

# 약대 샤로수길 제휴 (2026.11.30)
PHARM_IDS = {
    "pharm_julis_pizza", "pharm_bokdoni", "pharm_kkokko_dakgalbi",
    "pharm_chungcheong_samgyeop", "pharm_manseok_gopchang", "pharm_shabro21",
    "pharm_deogoegi", "pharm_ssukgogae", "pharm_osio", "pharm_syaro_fish",
    "pharm_onyu", "pharm_cafe_pol", "pharm_tipe", "pharm_waroom",
    "pharm_holmes_lupin", "pharm_redbutton", "pharm_hive_studio",
    "pharm_hegemony_gym",
}

# 의과대학 관악캠퍼스 제휴 (2026.11.30 기준)
MED_GWANAK_IDS = {
    "med_bokdoni", "med_jeongtong", "med_katsu_shoshin",
    "med_chili_dosakmyeon", "med_rohyang_yangkkochi", "med_shabu1988",
    "med_syaro_fish", "med_record_pizza", "med_sowooju", "med_sui",
    "med_yeeinchon", "med_baekgeumdang", "med_wondonut", "med_bultoon",
}

# 쿠폰코드
COUPON_MAP = {
    "vet_nail_preview": "26SNUVETER",
    "pharm_nail_preview": "2026SNUMED",
}

updated = 0
for item in data:
    item_id = item.get("id", "")

    # expiresAt
    if item_id == DONGGYEONG_ID:
        item["expiresAt"] = "2026-06-30"
        updated += 1
    elif item_id in VET_SHAROSU_IDS:
        item["expiresAt"] = "2026-11-30"
        updated += 1
    elif item_id in PHARM_IDS:
        item["expiresAt"] = "2026-11-30"
        updated += 1
    elif item_id in MED_GWANAK_IDS:
        item["expiresAt"] = "2026-11-30"
        updated += 1

    # 수의대 네일프리뷰
    if item_id == "vet_nail_preview":
        item["expiresAt"] = "2026-12-31"
        updated += 1
    # 약대 네일프리뷰
    if item_id == "pharm_nail_preview":
        item["expiresAt"] = "2026-12-31"
        updated += 1

    # couponCode
    if item_id in COUPON_MAP:
        item["couponCode"] = COUPON_MAP[item_id]

with open(JSON_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"Updated {updated} items with expiresAt/couponCode")
