"""
Seed script — Phase 1 Foundation Data

Tạo dữ liệu mẫu cho TravelWise:
  - 5 Categories
  - 4 Places ở Đà Nẵng (với latitude/longitude thực)
  - 2–3 Knowledge articles mỗi place

Chạy:
    uv run python seed.py
    # hoặc
    .venv/Scripts/python.exe seed.py
"""

import sys
import os

# Force UTF-8 on Windows stdout to handle Vietnamese and emoji
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

sys.path.insert(0, os.path.dirname(__file__))

from sqlmodel import Session, select
from app.db.session import engine
from app.models.category import Category
from app.models.knowledge import Knowledge
from app.models.place import Place


# ─── Helpers ────────────────────────────────────────────────────────────────

def get_or_create_category(session: Session, name: str, description: str) -> Category:
    existing = session.exec(select(Category).where(Category.name == name)).first()
    if existing:
        return existing
    cat = Category(name=name, description=description)
    session.add(cat)
    session.flush()
    return cat


def get_or_create_place(session: Session, **kwargs) -> Place:
    existing = session.exec(select(Place).where(Place.name == kwargs["name"])).first()
    if existing:
        return existing
    place = Place(**kwargs)
    session.add(place)
    session.flush()
    return place


def add_knowledge(session: Session, place_id: int, title: str, content: str, source: str) -> None:
    existing = session.exec(
        select(Knowledge).where(Knowledge.place_id == place_id, Knowledge.title == title)
    ).first()
    if existing:
        return
    knowledge = Knowledge(place_id=place_id, title=title, content=content, source=source)
    session.add(knowledge)


# ─── Seed Data ───────────────────────────────────────────────────────────────

def seed() -> None:
    with Session(engine) as session:
        print("🌱 Seeding categories...")

        tam_linh = get_or_create_category(
            session,
            name="Địa điểm tâm linh",
            description="Chùa, đền, miếu và các địa điểm tín ngưỡng tâm linh",
        )
        am_thuc = get_or_create_category(
            session,
            name="Ẩm thực",
            description="Nhà hàng, quán ăn, đặc sản địa phương",
        )
        khach_san = get_or_create_category(
            session,
            name="Khách sạn",
            description="Khách sạn, resort, homestay",
        )
        di_tich = get_or_create_category(
            session,
            name="Di tích - Danh thắng",
            description="Di tích lịch sử, thắng cảnh thiên nhiên",
        )
        du_lich = get_or_create_category(
            session,
            name="Du lịch",
            description="Khu du lịch, điểm tham quan",
        )

        session.flush()
        print(f"  ✓ {tam_linh.name} (id={tam_linh.id})")
        print(f"  ✓ {am_thuc.name} (id={am_thuc.id})")
        print(f"  ✓ {khach_san.name} (id={khach_san.id})")
        print(f"  ✓ {di_tich.name} (id={di_tich.id})")
        print(f"  ✓ {du_lich.name} (id={du_lich.id})")

        print("\n🌱 Seeding places...")

        # Chùa Linh Ứng — Sơn Trà
        chua_linh_ung = get_or_create_place(
            session,
            name="Chùa Linh Ứng - Bãi Bụt",
            description=(
                "Chùa Linh Ứng tọa lạc trên Bán đảo Sơn Trà, Đà Nẵng, "
                "nổi tiếng với tượng Phật Quan Thế Âm cao 67m — cao nhất Việt Nam. "
                "Từ chùa có thể ngắm toàn cảnh thành phố Đà Nẵng và biển Đông tuyệt đẹp."
            ),
            address="Bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, Đà Nẵng",
            latitude=16.1025,
            longitude=108.2772,
            category_id=tam_linh.id,
        )

        # Ngũ Hành Sơn
        ngu_hanh_son = get_or_create_place(
            session,
            name="Ngũ Hành Sơn",
            description=(
                "Ngũ Hành Sơn (Non Nước) là cụm 5 ngọn núi đá cẩm thạch và vôi "
                "nằm ở phía Nam Đà Nẵng. Bên trong có nhiều hang động, chùa cổ và "
                "tượng Phật điêu khắc tinh xảo."
            ),
            address="52 Huyền Trân Công Chúa, Hoà Hải, Ngũ Hành Sơn, Đà Nẵng",
            latitude=15.9731,
            longitude=108.2630,
            category_id=di_tich.id,
        )

        # Cầu Rồng
        cau_rong = get_or_create_place(
            session,
            name="Cầu Rồng Đà Nẵng",
            description=(
                "Cầu Rồng là cây cầu biểu tượng của thành phố Đà Nẵng, "
                "bắc qua sông Hàn. Vào tối cuối tuần, rồng phun lửa và nước "
                "thu hút hàng nghìn du khách. Cầu dài 666m, có hình dáng con rồng đang bay."
            ),
            address="Trần Hưng Đạo, Phước Ninh, Hải Châu, Đà Nẵng",
            latitude=16.0610,
            longitude=108.2277,
            category_id=du_lich.id,
        )

        # Bà Nà Hills
        ba_na_hills = get_or_create_place(
            session,
            name="Khu du lịch Bà Nà Hills",
            description=(
                "Bà Nà Hills là khu du lịch núi nổi tiếng ở Đà Nẵng với cáp treo "
                "dài nhất thế giới và cầu Vàng độc đáo được đỡ bởi hai bàn tay khổng lồ. "
                "Nằm ở độ cao 1.487m, khí hậu mát mẻ quanh năm."
            ),
            address="Thôn An Sơn, xã Hoà Ninh, huyện Hoà Vang, Đà Nẵng",
            latitude=15.9973,
            longitude=107.9887,
            category_id=du_lich.id,
        )

        session.flush()

        for p in [chua_linh_ung, ngu_hanh_son, cau_rong, ba_na_hills]:
            print(f"  ✓ {p.name} (id={p.id})")

        print("\n🌱 Seeding knowledge articles...")

        # ── Chùa Linh Ứng ─────────────────────────────────────────────────────
        add_knowledge(
            session,
            place_id=chua_linh_ung.id,
            title="Lịch sử Chùa Linh Ứng Sơn Trà",
            content=(
                "Chùa Linh Ứng trên bán đảo Sơn Trà được xây dựng vào năm 2004 và "
                "khánh thành vào năm 2010. Chùa tọa lạc ở độ cao 693m so với mực nước biển, "
                "là một trong ba ngôi chùa Linh Ứng tại Đà Nẵng (hai ngôi còn lại ở Ngũ Hành Sơn "
                "và Bãi Bụt). Pho tượng Bồ Tát Quan Thế Âm cao 67m, đường kính tòa sen 35m, "
                "là tượng Phật cao nhất Việt Nam tính đến thời điểm khánh thành."
            ),
            source="https://vi.wikipedia.org/wiki/Chùa_Linh_Ứng,_bán_đảo_Sơn_Trà",
        )
        add_knowledge(
            session,
            place_id=chua_linh_ung.id,
            title="Điểm đặc biệt của Chùa Linh Ứng",
            content=(
                "Điểm nổi bật nhất của Chùa Linh Ứng là tượng Phật Quan Thế Âm cao 67m "
                "với 17 tầng, mỗi tầng có bàn thờ và tượng Phật được điêu khắc tinh xảo. "
                "Từ chân tượng có thể ngắm toàn cảnh thành phố Đà Nẵng, bán đảo Sơn Trà, "
                "vịnh Đà Nẵng và bờ biển dài hút tầm mắt. Chùa mở cửa miễn phí mỗi ngày."
            ),
            source="https://danang.gov.vn/",
        )
        add_knowledge(
            session,
            place_id=chua_linh_ung.id,
            title="Thông tin tham quan Chùa Linh Ứng",
            content=(
                "Giờ mở cửa: 7:00 – 18:00 hàng ngày. Vào cửa miễn phí. "
                "Cách trung tâm Đà Nẵng khoảng 10km, di chuyển bằng xe máy hoặc ô tô mất "
                "khoảng 30 phút leo núi. Khuyến khích mặc trang phục lịch sự khi vào chùa. "
                "Bãi đỗ xe rộng rãi, có nhà vệ sinh công cộng."
            ),
            source="Tổng hợp",
        )

        # ── Ngũ Hành Sơn ──────────────────────────────────────────────────────
        add_knowledge(
            session,
            place_id=ngu_hanh_son.id,
            title="Lịch sử Ngũ Hành Sơn",
            content=(
                "Ngũ Hành Sơn gồm 6 ngọn núi đá vôi và cẩm thạch mang tên Ngũ Hành: "
                "Kim, Mộc, Thủy, Hỏa, Thổ. Đây là di tích lịch sử và thắng cảnh quốc gia "
                "từ thế kỷ 17. Trong kháng chiến, Ngũ Hành Sơn từng là căn cứ cách mạng "
                "và nơi trú ẩn của quân dân Đà Nẵng."
            ),
            source="https://vi.wikipedia.org/wiki/Ngũ_Hành_Sơn",
        )
        add_knowledge(
            session,
            place_id=ngu_hanh_son.id,
            title="Các hang động và chùa tại Ngũ Hành Sơn",
            content=(
                "Ngũ Hành Sơn có nhiều hang động tự nhiên nổi tiếng như hang Âm Phủ, "
                "động Huyền Không, động Tàng Chơn. Trong các hang động có nhiều tượng Phật "
                "và bàn thờ được điêu khắc từ đá cẩm thạch địa phương. "
                "Đặc biệt, làng nghề điêu khắc đá Non Nước bên cạnh là nơi sản xuất "
                "tượng đá và đồ lưu niệm nổi tiếng cả nước."
            ),
            source="https://nongnghiep.vn/",
        )

        # ── Cầu Rồng ──────────────────────────────────────────────────────────
        add_knowledge(
            session,
            place_id=cau_rong.id,
            title="Thiết kế và xây dựng Cầu Rồng",
            content=(
                "Cầu Rồng được thiết kế bởi công ty Louis Berger Group (Mỹ) và xây dựng "
                "từ năm 2009, khánh thành ngày 29/3/2013 nhân kỷ niệm 38 năm giải phóng Đà Nẵng. "
                "Cầu dài 666m, rộng 37,5m với 6 làn xe. Hình tượng rồng được thiết kế dựa trên "
                "truyền thuyết rồng của người Việt — biểu tượng của sức mạnh và thịnh vượng."
            ),
            source="https://vi.wikipedia.org/wiki/Cầu_Rồng_(Đà_Nẵng)",
        )
        add_knowledge(
            session,
            place_id=cau_rong.id,
            title="Show phun lửa và nước Cầu Rồng",
            content=(
                "Mỗi tối thứ Bảy và Chủ Nhật (21:00 – 21:15), Cầu Rồng tổ chức show "
                "phun lửa và phun nước đặc sắc. Lưỡng long phun lửa kéo dài 15 phút, "
                "thu hút hàng chục nghìn du khách và người dân đến xem mỗi cuối tuần. "
                "Khu vực hai đầu cầu có bãi đậu xe và nhiều quán ăn, cà phê phục vụ du khách."
            ),
            source="https://danangfantasticity.com/",
        )

        # ── Bà Nà Hills ───────────────────────────────────────────────────────
        add_knowledge(
            session,
            place_id=ba_na_hills.id,
            title="Cáp treo Bà Nà Hills — Kỷ lục thế giới",
            content=(
                "Cáp treo Bà Nà Hills do Sun Group đầu tư, lập nhiều kỷ lục thế giới được "
                "Guinness công nhận: tuyến cáp treo một dây dài nhất (5.801m), "
                "độ cao chênh lệch lớn nhất (1.291m), và cabin nặng nhất (đoạn 3). "
                "Cáp treo vận hành từ năm 2009, đưa du khách lên đỉnh núi trong 20 phút."
            ),
            source="https://banahills.sunworld.vn/",
        )
        add_knowledge(
            session,
            place_id=ba_na_hills.id,
            title="Cầu Vàng Bà Nà Hills",
            content=(
                "Cầu Vàng (Golden Bridge) khánh thành tháng 6/2018, dài 150m ở độ cao 1.400m, "
                "được đỡ bởi hai bàn tay khổng lồ làm từ thép bọc lưới sợi thủy tinh. "
                "Cầu Vàng trở thành biểu tượng du lịch Đà Nẵng, xuất hiện trên hàng trăm "
                "tạp chí quốc tế và là một trong những cây cầu đẹp nhất thế giới."
            ),
            source="https://banahills.sunworld.vn/cau-vang/",
        )
        add_knowledge(
            session,
            place_id=ba_na_hills.id,
            title="Thông tin vé và tham quan Bà Nà Hills",
            content=(
                "Giá vé cáp treo Bà Nà Hills: người lớn khoảng 750.000–850.000 VNĐ, "
                "trẻ em cao dưới 1m miễn phí. Vé bao gồm cáp treo khứ hồi và vào tất cả "
                "khu vui chơi trên đỉnh núi. Nên đặt vé trực tuyến sớm để tránh xếp hàng. "
                "Thời gian tham quan lý tưởng: 8:00 – 17:00. Nhiệt độ trên đỉnh mát hơn "
                "thành phố 5–7°C."
            ),
            source="https://banahills.sunworld.vn/gia-ve/",
        )

        session.commit()
        print("\n✅ Seed hoàn tất!")
        print(f"   Categories : 5")
        print(f"   Places     : 4 (Đà Nẵng)")
        print(f"   Knowledge  : {3 + 2 + 2 + 3} articles")


if __name__ == "__main__":
    seed()
