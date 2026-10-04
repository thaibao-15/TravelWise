IF DB_ID('TravelWiseDB') IS NOT NULL
BEGIN
    ALTER DATABASE TravelWiseDB
    SET SINGLE_USER
    WITH ROLLBACK IMMEDIATE;

    DROP DATABASE TravelWiseDB;
END
GO

CREATE DATABASE TravelWiseDB;
GO

USE TravelWiseDB;
GO
-- =========================================
-- USERS
-- =========================================
CREATE TABLE users (
    id BIGINT IDENTITY PRIMARY KEY,
    email NVARCHAR(255) UNIQUE NOT NULL,
    password NVARCHAR(MAX),
    full_name NVARCHAR(255),
    avatar_url NVARCHAR(MAX),
    role NVARCHAR(20) DEFAULT 'USER',
    is_active BIT DEFAULT 1,
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE()
);

-- =========================================
-- CATEGORIES
-- =========================================
CREATE TABLE categories (
    id BIGINT IDENTITY PRIMARY KEY,
    name NVARCHAR(100),
    description NVARCHAR(MAX)
);

-- =========================================
-- PLACES (GPS + GEO)
-- =========================================
CREATE TABLE places (
    id BIGINT IDENTITY PRIMARY KEY,
    name NVARCHAR(255) NOT NULL,
    description NVARCHAR(MAX),
    address NVARCHAR(MAX),

    latitude FLOAT,
    longitude FLOAT,
    location GEOGRAPHY,

    category_id BIGINT,
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE(),
    is_deleted BIT DEFAULT 0,

    FOREIGN KEY (category_id) REFERENCES categories(id)
);

CREATE SPATIAL INDEX idx_places_location ON places(location);
CREATE INDEX idx_places_category ON places(category_id);

-- =========================================
-- PLACE DETAILS
-- =========================================
CREATE TABLE restaurant_details (
    place_id BIGINT PRIMARY KEY,
    cuisine_type NVARCHAR(100),
    price_range NVARCHAR(50),
    is_vegetarian BIT,
    FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE
);

CREATE TABLE hotel_details (
    place_id BIGINT PRIMARY KEY,
    star_rating INT,
    price_per_night DECIMAL(10,2),
    amenities NVARCHAR(MAX),
    FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE
);

-- =========================================
-- IMAGES
-- =========================================
CREATE TABLE place_images (
    id BIGINT IDENTITY PRIMARY KEY,
    place_id BIGINT,
    url NVARCHAR(MAX),
    description NVARCHAR(MAX),
    is_primary BIT DEFAULT 0,
    FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE
);

-- =========================================
-- OPENING HOURS
-- =========================================
CREATE TABLE opening_hours (
    id BIGINT IDENTITY PRIMARY KEY,
    place_id BIGINT,
    day_of_week INT,
    open_time TIME,
    close_time TIME,
    FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE
);

-- =========================================
-- KNOWLEDGE (RAG)
-- =========================================
CREATE TABLE knowledge (
    id BIGINT IDENTITY PRIMARY KEY,
    place_id BIGINT,
    title NVARCHAR(255),
    content NVARCHAR(MAX),
    source NVARCHAR(MAX),
    created_at DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE
);

CREATE TABLE knowledge_chunks (
    id BIGINT IDENTITY PRIMARY KEY,
    knowledge_id BIGINT,
    content NVARCHAR(MAX),
    embedding VARBINARY(MAX),
    created_at DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (knowledge_id) REFERENCES knowledge(id) ON DELETE CASCADE
);

CREATE INDEX idx_knowledge_place ON knowledge(place_id);

-- =========================================
-- USER PREFERENCES
-- =========================================
CREATE TABLE user_preferences (
    id BIGINT IDENTITY PRIMARY KEY,
    user_id BIGINT,
    category_id BIGINT,
    priority INT CHECK (priority BETWEEN 1 AND 5),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES categories(id)
);

-- =========================================
-- 🔥 CONVERSATION SYSTEM (CORE AI)
-- =========================================
CREATE TABLE conversations (
    id BIGINT IDENTITY PRIMARY KEY,
    user_id BIGINT,
    title NVARCHAR(255),
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE messages (
    id BIGINT IDENTITY PRIMARY KEY,
    conversation_id BIGINT,
    sender NVARCHAR(10), -- USER / AI
    content NVARCHAR(MAX),
    audio_url NVARCHAR(MAX),
    created_at DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id);

-- =========================================
-- AI CONTEXT (MEMORY)
-- =========================================
CREATE TABLE ai_context (
    id BIGINT IDENTITY PRIMARY KEY,
    conversation_id BIGINT,
    summary NVARCHAR(MAX),
    updated_at DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

-- =========================================
-- TRIPS (AI GENERATED)
-- =========================================
CREATE TABLE trips (
    id BIGINT IDENTITY PRIMARY KEY,
    user_id BIGINT,
    name NVARCHAR(255),
    start_date DATE,
    end_date DATE,
    created_at DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE trip_items (
    id BIGINT IDENTITY PRIMARY KEY,
    trip_id BIGINT,
    place_id BIGINT,
    order_index INT,
    planned_time DATETIME,
    note NVARCHAR(MAX),
    FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE,
    FOREIGN KEY (place_id) REFERENCES places(id)
);

CREATE INDEX idx_trip_user ON trips(user_id);

-- CATEGORIES
INSERT INTO categories (name) VALUES
('Restaurant'),('Cafe'),('Hotel'),('Beach'),('Museum'),
('Park'),('Bar'),('Mall'),('Temple'),('Street Food');






-- =========================================================
-- TRAVELWISE - DA NANG TOURISM SEED DATA
-- places + knowledge
-- =========================================================

-- =========================================================
-- 1. PLACES
-- =========================================================

INSERT INTO places
(
    name,
    description,
    address,
    latitude,
    longitude,
    location,
    category_id,
    is_deleted
)
VALUES

(
    N'Chùa Linh Ứng Sơn Trà',
    N'Chùa Linh Ứng Sơn Trà là một trong những điểm tham quan nổi tiếng của Đà Nẵng, nằm trên bán đảo Sơn Trà. Địa điểm nổi bật với tượng Phật Quan Âm hướng ra biển, không gian chùa rộng và vị trí có tầm nhìn đẹp ra biển, thành phố Đà Nẵng và bán đảo Sơn Trà. Đây là điểm đến kết hợp giữa tham quan cảnh quan, tìm hiểu văn hóa Phật giáo và trải nghiệm thiên nhiên.',
    N'Hoàng Sa, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.0998,
    108.2770,
    geography::Point(16.0998, 108.2770, 4326),
    1,
    0
),

(
    N'Bà Nà Hills',
    N'Bà Nà Hills là khu du lịch nổi tiếng nằm trên khu vực núi Chúa, huyện Hòa Vang, Đà Nẵng. Nơi đây nổi bật với khí hậu vùng núi, hệ thống cáp treo, Cầu Vàng, Làng Pháp, các khu vui chơi và nhiều công trình phục vụ du lịch. Bà Nà Hills thường được lựa chọn cho chuyến tham quan kéo dài gần một ngày.',
    N'An Sơn, xã Hòa Ninh, huyện Hòa Vang, thành phố Đà Nẵng',
    15.9959,
    107.9967,
    geography::Point(15.9959, 107.9967, 4326),
    2,
    0
),

(
    N'Ngũ Hành Sơn',
    N'Ngũ Hành Sơn là quần thể núi đá vôi nằm ở phía đông nam Đà Nẵng. Quần thể gồm năm ngọn núi Kim, Mộc, Thủy, Hỏa và Thổ. Nơi đây có nhiều hang động, chùa, công trình tâm linh và điểm quan sát cảnh quan. Ngũ Hành Sơn phù hợp với những du khách muốn kết hợp tham quan thiên nhiên, kiến trúc và văn hóa.',
    N'81 Huyền Trân Công Chúa, phường Hòa Hải, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    16.0039,
    108.2635,
    geography::Point(16.0039, 108.2635, 4326),
    3,
    0
),

(
    N'Cầu Rồng',
    N'Cầu Rồng là một trong những công trình kiến trúc hiện đại nổi bật của Đà Nẵng. Cây cầu bắc qua sông Hàn và được thiết kế mô phỏng hình dáng một con rồng. Vào một số thời điểm theo lịch vận hành, cầu có chương trình phun lửa và phun nước thu hút nhiều người dân và khách du lịch.',
    N'Đường Nguyễn Văn Linh - Bạch Đằng, thành phố Đà Nẵng',
    16.0614,
    108.2272,
    geography::Point(16.0614, 108.2272, 4326),
    4,
    0
),

(
    N'Bãi biển Mỹ Khê',
    N'Bãi biển Mỹ Khê nằm ở phía đông thành phố Đà Nẵng và là một trong những bãi biển được nhiều du khách lựa chọn. Bãi biển có bờ cát dài, không gian rộng và nằm gần nhiều khách sạn, nhà hàng và tuyến đường ven biển. Du khách có thể kết hợp nghỉ dưỡng, đi dạo, ngắm biển và tham gia các hoạt động biển khi điều kiện thời tiết phù hợp.',
    N'Đường Võ Nguyên Giáp, quận Sơn Trà, thành phố Đà Nẵng',
    16.0599,
    108.2456,
    geography::Point(16.0599, 108.2456, 4326),
    5,
    0
),

(
    N'Chợ Hàn',
    N'Chợ Hàn là khu chợ truyền thống nằm tại trung tâm Đà Nẵng. Chợ có nhiều gian hàng bán đặc sản địa phương, thực phẩm khô, đồ ăn, quà lưu niệm, quần áo và các sản phẩm phục vụ khách du lịch. Đây là địa điểm phù hợp để tìm hiểu hoạt động mua bán và lựa chọn đặc sản Đà Nẵng làm quà.',
    N'119 Trần Phú, phường Hải Châu, quận Hải Châu, thành phố Đà Nẵng',
    16.0698,
    108.2235,
    geography::Point(16.0698, 108.2235, 4326),
    6,
    0
),

(
    N'Bảo tàng Điêu khắc Chăm Đà Nẵng',
    N'Bảo tàng Điêu khắc Chăm Đà Nẵng là nơi lưu giữ và trưng bày nhiều hiện vật điêu khắc Chăm. Bảo tàng nằm gần khu vực trung tâm thành phố và là địa điểm phù hợp cho du khách muốn tìm hiểu lịch sử, nghệ thuật và văn hóa Chăm.',
    N'02 Đường 2 Tháng 9, phường Bình Hiên, quận Hải Châu, thành phố Đà Nẵng',
    16.0620,
    108.2232,
    geography::Point(16.0620, 108.2232, 4326),
    7,
    0
),

(
    N'Bán đảo Sơn Trà',
    N'Bán đảo Sơn Trà là khu vực có giá trị về cảnh quan thiên nhiên, rừng và biển nằm ở phía đông bắc Đà Nẵng. Đây là nơi có nhiều điểm tham quan như Chùa Linh Ứng Sơn Trà, các tuyến đường ven núi và nhiều vị trí quan sát biển. Sơn Trà phù hợp với những chuyến đi kết hợp khám phá thiên nhiên và tham quan văn hóa.',
    N'Bán đảo Sơn Trà, thành phố Đà Nẵng',
    16.1167,
    108.2833,
    geography::Point(16.1167, 108.2833, 4326),
    8,
    0
),

(
    N'Cầu Tình Yêu Đà Nẵng',
    N'Cầu Tình Yêu nằm bên sông Hàn, gần khu vực trung tâm thành phố. Đây là một địa điểm thường được du khách ghé qua để ngắm sông Hàn, chụp ảnh và kết hợp tham quan các công trình lân cận như tượng Cá Chép Hóa Rồng và các cây cầu trên sông Hàn.',
    N'Đường Trần Hưng Đạo, quận Sơn Trà, thành phố Đà Nẵng',
    16.0628,
    108.2295,
    geography::Point(16.0628, 108.2295, 4326),
    9,
    0
),

(
    N'Đèo Hải Vân',
    N'Đèo Hải Vân là cung đường đèo nổi tiếng nằm giữa Đà Nẵng và Thừa Thiên Huế. Tuyến đường đi qua địa hình núi và có nhiều vị trí nhìn ra biển. Đèo Hải Vân thường được lựa chọn cho các chuyến đi bằng xe máy hoặc ô tô nhằm trải nghiệm cảnh quan núi và biển.',
    N'Đèo Hải Vân, khu vực giáp ranh Đà Nẵng và Thừa Thiên Huế',
    16.2017,
    108.1272,
    geography::Point(16.2017, 108.1272, 4326),
    10,
    0
);

GO


-- =========================================================
-- 2. KNOWLEDGE - CHÙA LINH ỨNG SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan về Chùa Linh Ứng Sơn Trà',
    N'Chùa Linh Ứng Sơn Trà là một trong những địa điểm du lịch và tâm linh nổi tiếng của Đà Nẵng. Chùa nằm trên bán đảo Sơn Trà, ở vị trí cao và hướng ra biển. Khi đứng tại khu vực chùa, du khách có thể quan sát cảnh quan biển, thành phố Đà Nẵng và nhiều khu vực của bán đảo Sơn Trà. Không gian tại đây kết hợp giữa kiến trúc Phật giáo, cây xanh, núi và biển nên tạo ra trải nghiệm khác với những điểm tham quan nằm hoàn toàn trong khu vực đô thị. Chùa thường được đưa vào lịch trình tham quan Sơn Trà cùng với các điểm cảnh quan khác.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Linh Ứng Sơn Trà';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tượng Phật Quan Âm tại Chùa Linh Ứng',
    N'Điểm nổi bật nhất khi nhắc đến Chùa Linh Ứng Sơn Trà là tượng Phật Quan Âm cao khoảng 67 mét, đặt trong khuôn viên chùa và hướng ra biển. Tượng nằm ở vị trí cao nên có thể nhìn thấy từ nhiều khu vực xung quanh bán đảo Sơn Trà. Công trình tạo nên hình ảnh đặc trưng của khu vực và thường xuất hiện trong các hình ảnh giới thiệu về du lịch Đà Nẵng. Khi tham quan, du khách có thể quan sát tượng từ sân chùa đồng thời ngắm cảnh biển phía trước.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Linh Ứng Sơn Trà';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cảnh quan từ Chùa Linh Ứng',
    N'Chùa Linh Ứng có vị trí trên bán đảo Sơn Trà nên không gian xung quanh có sự kết hợp giữa núi, rừng và biển. Từ khu vực chùa có thể nhìn về phía biển Đà Nẵng và khu vực đô thị. Vào những ngày thời tiết thuận lợi, tầm nhìn có thể khá rộng. Đây là một trong những lý do nhiều du khách không chỉ đến chùa vì mục đích tham quan tâm linh mà còn muốn trải nghiệm cảnh quan thiên nhiên và chụp ảnh.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Linh Ứng Sơn Trà';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Văn hóa và không gian tâm linh',
    N'Chùa Linh Ứng là địa điểm mang yếu tố Phật giáo và có không gian thờ tự. Khi tham quan, du khách nên giữ thái độ tôn trọng, nói chuyện vừa phải, không làm ảnh hưởng đến người đang thực hiện hoạt động tín ngưỡng và tuân thủ quy định tại khu vực chùa. Trang phục lịch sự cũng là điều nên chú ý khi đến các khu vực thờ tự.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Linh Ứng Sơn Trà';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kết hợp Chùa Linh Ứng với lịch trình Sơn Trà',
    N'Chùa Linh Ứng có thể được kết hợp với một chuyến khám phá bán đảo Sơn Trà. Du khách có thể dành thời gian tham quan chùa, sau đó tiếp tục khám phá các tuyến đường ven núi, điểm quan sát cảnh quan hoặc các khu vực khác theo điều kiện giao thông và quy định bảo vệ môi trường. Một lịch trình Sơn Trà thường phù hợp với những người muốn kết hợp tham quan văn hóa, ngắm biển và trải nghiệm thiên nhiên trong cùng một chuyến đi.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Linh Ứng Sơn Trà';


-- =========================================================
-- 3. KNOWLEDGE - BÀ NÀ HILLS
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan về Bà Nà Hills',
    N'Bà Nà Hills là khu du lịch nằm trên khu vực núi Chúa thuộc huyện Hòa Vang, thành phố Đà Nẵng. Đây là điểm đến kết hợp giữa cảnh quan núi, hệ thống cáp treo, các công trình kiến trúc theo chủ đề, khu vui chơi và nhiều dịch vụ du lịch. Vì có nhiều khu vực tham quan, du khách thường dành phần lớn một ngày để khám phá Bà Nà Hills thay vì chỉ ghé qua trong thời gian ngắn.',
    N'TravelWise'
FROM places
WHERE name = N'Bà Nà Hills';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cầu Vàng tại Bà Nà Hills',
    N'Cầu Vàng là một công trình nổi bật của Bà Nà Hills. Cầu có phần lan can màu vàng và thiết kế nổi bật với hình ảnh đôi bàn tay đá nâng đỡ thân cầu. Công trình nằm trên khu vực núi cao nên xung quanh có cảnh quan núi và mây trong những điều kiện thời tiết nhất định. Cầu Vàng thường là một trong những điểm đầu tiên du khách muốn ghé thăm khi đến Bà Nà Hills.',
    N'TravelWise'
FROM places
WHERE name = N'Bà Nà Hills';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Làng Pháp tại Bà Nà Hills',
    N'Làng Pháp là khu vực được xây dựng theo phong cách kiến trúc châu Âu, với nhiều công trình, quảng trường và không gian mang chủ đề châu Âu. Khu vực này thường được sử dụng để tham quan, chụp ảnh, ăn uống và nghỉ chân. Kiến trúc của Làng Pháp tạo ra sự khác biệt rõ rệt so với cảnh quan núi tự nhiên của Bà Nà Hills.',
    N'TravelWise'
FROM places
WHERE name = N'Bà Nà Hills';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Khí hậu tại Bà Nà Hills',
    N'Bà Nà Hills nằm trên khu vực núi cao nên nhiệt độ và thời tiết thường khác với khu vực trung tâm Đà Nẵng. Trong cùng một ngày, thời tiết có thể thay đổi và có thể xuất hiện mây, sương hoặc mưa tùy thời điểm. Du khách nên kiểm tra dự báo thời tiết trước chuyến đi và chuẩn bị áo khoác hoặc trang phục phù hợp với điều kiện vùng núi.',
    N'TravelWise'
FROM places
WHERE name = N'Bà Nà Hills';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Các hoạt động tại Bà Nà Hills',
    N'Các hoạt động phổ biến tại Bà Nà Hills gồm di chuyển bằng hệ thống cáp treo, tham quan Cầu Vàng, khám phá Làng Pháp, tham gia các trò chơi và hoạt động giải trí, chụp ảnh và thưởng thức đồ ăn. Do khu du lịch có nhiều khu vực, du khách nên xác định trước những điểm muốn tham quan để sử dụng thời gian hiệu quả.',
    N'TravelWise'
FROM places
WHERE name = N'Bà Nà Hills';


-- =========================================================
-- 4. KNOWLEDGE - NGŨ HÀNH SƠN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan về Ngũ Hành Sơn',
    N'Ngũ Hành Sơn là quần thể núi đá vôi nằm ở phía đông nam thành phố Đà Nẵng. Quần thể gồm năm ngọn núi mang tên Kim Sơn, Mộc Sơn, Thủy Sơn, Hỏa Sơn và Thổ Sơn. Khu vực này nổi bật với địa hình núi đá, hang động, chùa và các công trình tín ngưỡng. Đây là điểm tham quan phù hợp cho du khách muốn tìm hiểu sự kết hợp giữa thiên nhiên, văn hóa và tín ngưỡng tại Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Ngũ Hành Sơn';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Năm ngọn núi của Ngũ Hành Sơn',
    N'Tên gọi Ngũ Hành Sơn bắt nguồn từ năm yếu tố Kim, Mộc, Thủy, Hỏa và Thổ. Năm ngọn núi tạo thành quần thể địa hình đặc trưng ở phía nam Đà Nẵng. Trong số đó, Thủy Sơn thường được nhiều du khách quan tâm vì có nhiều điểm tham quan, chùa và hang động. Việc tìm hiểu tên gọi của từng ngọn núi giúp du khách hiểu thêm về văn hóa và cách hình thành tên gọi của danh thắng.',
    N'TravelWise'
FROM places
WHERE name = N'Ngũ Hành Sơn';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hang động tại Ngũ Hành Sơn',
    N'Ngũ Hành Sơn có nhiều hang động hình thành trong các khối núi đá vôi. Một số hang động có không gian thờ tự và gắn với các câu chuyện văn hóa, tín ngưỡng của địa phương. Khi đi vào hang động, du khách có thể quan sát cấu trúc đá tự nhiên kết hợp với các công trình tôn giáo. Đây là điểm tạo nên sự khác biệt của Ngũ Hành Sơn so với các khu du lịch núi thông thường.',
    N'TravelWise'
FROM places
WHERE name = N'Ngũ Hành Sơn';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc và chùa tại Ngũ Hành Sơn',
    N'Khu vực Ngũ Hành Sơn có nhiều công trình Phật giáo và tín ngưỡng được xây dựng trong không gian núi đá. Chùa, tượng và các khu vực thờ tự nằm xen kẽ với hang động và cây xanh. Sự kết hợp giữa kiến trúc tôn giáo và địa hình tự nhiên tạo ra đặc trưng riêng cho danh thắng này.',
    N'TravelWise'
FROM places
WHERE name = N'Ngũ Hành Sơn';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm tham quan Ngũ Hành Sơn',
    N'Khi tham quan Ngũ Hành Sơn, du khách nên mang giày dép có độ bám tốt vì một số khu vực có bậc đá, đường dốc và địa hình không bằng phẳng. Nên dành đủ thời gian để khám phá từng khu vực thay vì chỉ ghé nhanh. Vì có nhiều địa điểm mang tính tâm linh, du khách cũng nên mặc trang phục lịch sự và tuân thủ quy định tại các khu vực thờ tự.',
    N'TravelWise'
FROM places
WHERE name = N'Ngũ Hành Sơn';


-- =========================================================
-- 5. KNOWLEDGE - CẦU RỒNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan về Cầu Rồng',
    N'Cầu Rồng là một trong những công trình giao thông và kiến trúc nổi bật của Đà Nẵng. Cầu bắc qua sông Hàn và kết nối khu vực trung tâm thành phố với khu vực phía đông. Thiết kế của cầu mô phỏng hình dáng một con rồng, tạo nên một biểu tượng kiến trúc dễ nhận biết của thành phố.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Rồng';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thiết kế đặc biệt của Cầu Rồng',
    N'Cầu Rồng có phần thân cầu được thiết kế theo hình ảnh một con rồng đang vươn qua sông. Thiết kế kết hợp giữa yêu cầu của một công trình giao thông và yếu tố biểu tượng. Vào ban đêm, hệ thống chiếu sáng làm nổi bật hình dáng của cầu và tạo ra cảnh quan đẹp khi nhìn từ hai bên bờ sông Hàn.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Rồng';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Phun lửa và phun nước tại Cầu Rồng',
    N'Cầu Rồng có chương trình phun lửa và phun nước theo lịch vận hành vào một số thời điểm. Hoạt động này thu hút đông người dân và khách du lịch, đặc biệt vào buổi tối. Nếu muốn xem chương trình, du khách nên kiểm tra lịch biểu diễn và các thông báo chính thức gần thời điểm tham quan vì lịch có thể thay đổi theo từng thời gian hoặc sự kiện.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Rồng';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Ngắm Cầu Rồng vào ban đêm',
    N'Buổi tối là thời điểm phổ biến để ngắm Cầu Rồng vì hệ thống chiếu sáng làm nổi bật hình dáng cây cầu. Du khách có thể đứng ở các khu vực ven sông Hàn hoặc những cây cầu lân cận để quan sát. Khu vực xung quanh Cầu Rồng cũng có nhiều nhà hàng, quán ăn và địa điểm vui chơi nên có thể kết hợp thành một lịch trình buổi tối.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Rồng';


-- =========================================================
-- 6. KNOWLEDGE - MỸ KHÊ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bãi biển Mỹ Khê',
    N'Bãi biển Mỹ Khê nằm ở phía đông Đà Nẵng và gần khu vực trung tâm thành phố. Bãi biển có không gian rộng, bờ cát dài và nằm dọc theo khu vực có nhiều khách sạn, nhà hàng và dịch vụ du lịch. Vị trí thuận tiện khiến Mỹ Khê thường xuất hiện trong lịch trình nghỉ dưỡng của du khách khi đến Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Mỹ Khê';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hoạt động tại Bãi biển Mỹ Khê',
    N'Các hoạt động thường thấy tại Mỹ Khê gồm đi dạo trên bãi biển, ngắm bình minh hoặc hoàng hôn, chụp ảnh, thư giãn và tắm biển khi điều kiện thời tiết và an toàn cho phép. Khu vực ven biển cũng có nhiều cơ sở lưu trú và ăn uống nên du khách có thể dễ dàng kết hợp nghỉ biển với khám phá thành phố.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Mỹ Khê';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Bình minh và hoàng hôn tại Mỹ Khê',
    N'Bãi biển Mỹ Khê là địa điểm phù hợp để trải nghiệm không gian biển vào sáng sớm hoặc chiều tối. Buổi sáng thường có không khí yên tĩnh hơn so với những thời điểm đông khách. Vào chiều tối, du khách có thể đi dạo ven biển và quan sát sự thay đổi của ánh sáng trên mặt biển. Thời điểm mặt trời mọc và lặn thay đổi theo ngày nên nếu muốn chụp ảnh cụ thể, du khách nên kiểm tra trước.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Mỹ Khê';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lưu ý an toàn khi tắm biển Mỹ Khê',
    N'Khi tắm biển, du khách nên lựa chọn khu vực được phép tắm và tuân thủ hướng dẫn của lực lượng cứu hộ. Không nên xuống biển khi có cảnh báo thời tiết hoặc biển động. Trẻ em cần được người lớn giám sát. Các hoạt động dưới nước cũng cần được thực hiện theo hướng dẫn của đơn vị cung cấp dịch vụ và điều kiện an toàn tại thời điểm đó.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Mỹ Khê';


-- =========================================================
-- 7. KNOWLEDGE - CHỢ HÀN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan về Chợ Hàn',
    N'Chợ Hàn là một khu chợ truyền thống nằm ở trung tâm Đà Nẵng. Chợ có nhiều gian hàng bán thực phẩm, đặc sản địa phương, đồ khô, quần áo, phụ kiện và quà lưu niệm. Đây là địa điểm phù hợp với du khách muốn trải nghiệm không khí mua bán truyền thống và tìm sản phẩm mang về sau chuyến đi.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ Hàn';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Đặc sản có thể tìm thấy tại Chợ Hàn',
    N'Các gian hàng trong chợ có nhiều loại đặc sản và thực phẩm địa phương như các loại đồ khô, gia vị, mắm, bánh và sản phẩm đóng gói. Khi mua thực phẩm làm quà, du khách nên kiểm tra kỹ bao bì, nguồn gốc, hạn sử dụng và điều kiện bảo quản. Nếu di chuyển bằng máy bay, nên chú ý các quy định về hành lý và loại thực phẩm được phép mang theo.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ Hàn';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm mua sắm tại Chợ Hàn',
    N'Khi mua sắm tại chợ, du khách nên tham khảo giá ở nhiều gian hàng và kiểm tra kỹ sản phẩm trước khi thanh toán. Với các sản phẩm đóng gói, nên xem thông tin sản phẩm và hạn sử dụng. Nếu mua số lượng lớn để làm quà, nên tính trước cách đóng gói và vận chuyển để tránh hư hỏng trong quá trình di chuyển.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ Hàn';


-- =========================================================
-- 8. KNOWLEDGE - BẢO TÀNG ĐIÊU KHẮC CHĂM
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bảo tàng Điêu khắc Chăm',
    N'Bảo tàng Điêu khắc Chăm Đà Nẵng là địa điểm văn hóa nằm gần trung tâm thành phố. Bảo tàng lưu giữ và trưng bày nhiều tác phẩm điêu khắc liên quan đến văn hóa Chăm. Không gian trưng bày giúp du khách tìm hiểu thêm về nghệ thuật, tôn giáo và lịch sử của nền văn hóa Chăm thông qua các hiện vật.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Điêu khắc Chăm Đà Nẵng';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Giá trị văn hóa của bảo tàng',
    N'Các hiện vật tại Bảo tàng Điêu khắc Chăm giúp người xem tiếp cận nghệ thuật điêu khắc Chăm thông qua tượng, phù điêu và các tác phẩm trang trí. Nhiều tác phẩm thể hiện hình ảnh liên quan đến tín ngưỡng và đời sống văn hóa. Đối với du khách yêu thích lịch sử và văn hóa, đây là một điểm tham quan có thể bổ sung cho lịch trình khám phá Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Điêu khắc Chăm Đà Nẵng';


-- =========================================================
-- 9. KNOWLEDGE - BÁN ĐẢO SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan bán đảo Sơn Trà',
    N'Bán đảo Sơn Trà nằm ở phía đông bắc Đà Nẵng và là khu vực có sự kết hợp giữa rừng, núi và biển. Sơn Trà có nhiều điểm tham quan và tuyến đường cảnh quan. Đây là một trong những khu vực phù hợp để du khách rời khỏi không gian đô thị và trải nghiệm thiên nhiên trong phạm vi thành phố.',
    N'TravelWise'
FROM places
WHERE name = N'Bán đảo Sơn Trà';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thiên nhiên Sơn Trà',
    N'Sơn Trà có hệ sinh thái rừng và cảnh quan ven biển. Khu vực này được biết đến với hệ động thực vật phong phú và có giá trị sinh thái. Khi tham quan, du khách nên hạn chế gây tiếng ồn, không xả rác, không tự ý cho động vật ăn và tuân thủ các quy định nhằm bảo vệ môi trường tự nhiên.',
    N'TravelWise'
FROM places
WHERE name = N'Bán đảo Sơn Trà';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Khám phá Sơn Trà bằng xe máy',
    N'Một số du khách lựa chọn xe máy để khám phá các tuyến đường trên bán đảo Sơn Trà vì có thể chủ động dừng lại tại các điểm quan sát cảnh quan. Tuy nhiên, địa hình có đoạn dốc và đường quanh núi nên người lái cần kiểm soát tốc độ, sử dụng phương tiện phù hợp và tuân thủ các khu vực được phép lưu thông.',
    N'TravelWise'
FROM places
WHERE name = N'Bán đảo Sơn Trà';


-- =========================================================
-- 10. KNOWLEDGE - CẦU TÌNH YÊU
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Cầu Tình Yêu',
    N'Cầu Tình Yêu nằm bên sông Hàn, thuộc khu vực trung tâm Đà Nẵng. Đây là một địa điểm thường được du khách ghé thăm để đi dạo, chụp ảnh và ngắm cảnh sông Hàn. Vị trí của cầu cũng thuận tiện để kết hợp với các điểm tham quan khác nằm gần khu vực bờ đông sông Hàn.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Tình Yêu Đà Nẵng';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian ven sông Hàn',
    N'Khu vực Cầu Tình Yêu có không gian ven sông và tầm nhìn về các công trình phía bên kia sông. Buổi tối, hệ thống ánh sáng của thành phố và các cây cầu tạo ra cảnh quan phù hợp để đi dạo và chụp ảnh. Du khách có thể kết hợp địa điểm này với việc khám phá các khu vực ăn uống và vui chơi gần trung tâm.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Tình Yêu Đà Nẵng';


-- =========================================================
-- 11. KNOWLEDGE - ĐÈO HẢI VÂN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan về Đèo Hải Vân',
    N'Đèo Hải Vân là cung đường đèo nổi tiếng nằm trên dãy núi Hải Vân, giữa khu vực Đà Nẵng và Thừa Thiên Huế. Cung đường có địa hình núi và nhiều đoạn nhìn ra biển. Đây là địa điểm được nhiều người lựa chọn khi muốn trải nghiệm cảnh quan núi biển và một chuyến đi bằng xe máy hoặc ô tô.',
    N'TravelWise'
FROM places
WHERE name = N'Đèo Hải Vân';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cảnh quan Đèo Hải Vân',
    N'Đèo Hải Vân có sự kết hợp giữa địa hình núi, rừng và biển. Từ một số vị trí trên cung đường có thể quan sát biển và cảnh quan ven bờ. Thời tiết có ảnh hưởng lớn đến tầm nhìn, vì vậy trải nghiệm cảnh quan có thể khác nhau giữa những ngày nắng, nhiều mây hoặc có mưa.',
    N'TravelWise'
FROM places
WHERE name = N'Đèo Hải Vân';


INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lưu ý khi đi Đèo Hải Vân',
    N'Khi di chuyển qua Đèo Hải Vân, người lái cần chú ý địa hình quanh co, độ dốc và điều kiện thời tiết. Nên kiểm tra phương tiện trước khi đi, đặc biệt là phanh, lốp và nhiên liệu. Khi trời mưa hoặc có sương mù, cần giảm tốc độ và tăng khoảng cách an toàn. Du khách nên dừng xe tại những vị trí được phép thay vì dừng giữa đường để chụp ảnh.',
    N'TravelWise'
FROM places
WHERE name = N'Đèo Hải Vân';


-- =========================================================
-- 12. KIỂM TRA DỮ LIỆU
-- =========================================================

SELECT
    p.id,
    p.name,
    COUNT(k.id) AS knowledge_count
FROM places p
LEFT JOIN knowledge k
    ON p.id = k.place_id
GROUP BY
    p.id,
    p.name
ORDER BY p.id;


SELECT
    k.id,
    p.name AS place_name,
    k.title,
    LEN(k.content) AS content_length,
    k.content
FROM knowledge k
INNER JOIN places p
    ON k.place_id = p.id
ORDER BY p.name, k.id;

GO

select * from users 
select * from places 
select * from knowledge