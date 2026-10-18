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

CREATE TABLE user_profiles (
    id BIGINT IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE,

    -- Thông tin cá nhân
    phone NVARCHAR(20),
    date_of_birth DATE,
    gender NVARCHAR(20),
    nationality NVARCHAR(100),
    preferred_language NVARCHAR(10) DEFAULT 'vi',

    -- Sở thích du lịch
    travel_style NVARCHAR(50),
    favorite_categories NVARCHAR(MAX),
    interests NVARCHAR(MAX),

    -- Ngân sách và di chuyển
    budget_min DECIMAL(12, 2),
    budget_max DECIMAL(12, 2),
    currency NVARCHAR(10) DEFAULT 'VND',
    preferred_transport NVARCHAR(50),

    -- Nhu cầu du lịch
    accommodation_type NVARCHAR(50),
    dietary_preferences NVARCHAR(MAX),
    accessibility_needs NVARCHAR(MAX),

    -- Cá nhân hóa AI
    preferred_travel_pace NVARCHAR(30),
    additional_preferences NVARCHAR(MAX),

    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE(),

    CONSTRAINT FK_user_profiles_users
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
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
CREATE TABLE user_memories (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id BIGINT NOT NULL,

    memory_type NVARCHAR(50) NOT NULL,
    content NVARCHAR(MAX) NOT NULL,

    importance FLOAT DEFAULT 0.5,

    source_conversation_id BIGINT NULL,
    source_message_id BIGINT NULL,

    created_at DATETIME2 DEFAULT SYSDATETIME(),
    updated_at DATETIME2 DEFAULT SYSDATETIME(),
    last_accessed_at DATETIME2 NULL,

    is_active BIT DEFAULT 1,

    FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE,

    FOREIGN KEY (source_conversation_id)
        REFERENCES conversations(id) ON DELETE NO ACTION,

    FOREIGN KEY (source_message_id)
        REFERENCES messages(id) ON DELETE NO ACTION
);

CREATE INDEX IX_user_memories_user_type
ON user_memories(user_id, memory_type, is_active);

CREATE TABLE conversation_summaries (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    conversation_id BIGINT NOT NULL,

    summary NVARCHAR(MAX) NOT NULL,
    last_summarized_message_id BIGINT NULL,

    updated_at DATETIME2 DEFAULT SYSDATETIME(),

    FOREIGN KEY (conversation_id)
        REFERENCES conversations(id) ON DELETE CASCADE,

    FOREIGN KEY (last_summarized_message_id)
        REFERENCES messages(id) ON DELETE NO ACTION,

    CONSTRAINT UQ_conversation_summaries_conversation
        UNIQUE (conversation_id)
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

CREATE TABLE trip_preferences (
    id BIGINT IDENTITY PRIMARY KEY,
    trip_id BIGINT NOT NULL UNIQUE,

    travelers INT,
    budget DECIMAL(12,2),
    transport NVARCHAR(50),
    travel_style NVARCHAR(50),
    interests NVARCHAR(MAX),
    special_requirements NVARCHAR(MAX),

    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (trip_id)
        REFERENCES trips(id) ON DELETE CASCADE
);

CREATE TABLE itinerary_days (
    id BIGINT IDENTITY PRIMARY KEY,
    trip_id BIGINT NOT NULL,
    day_number INT NOT NULL,
    date DATE,
    title NVARCHAR(255),
    description NVARCHAR(MAX),

    FOREIGN KEY (trip_id)
        REFERENCES trips(id) ON DELETE CASCADE,

    UNIQUE (trip_id, day_number)
);

CREATE TABLE itinerary_activities (
    id BIGINT IDENTITY PRIMARY KEY,
    itinerary_day_id BIGINT NOT NULL,
    place_id BIGINT NULL,

    activity_type NVARCHAR(30) DEFAULT 'VISIT',
    title NVARCHAR(255) NOT NULL,
    description NVARCHAR(MAX),

    start_time TIME,
    end_time TIME,
    duration_minutes INT,

    estimated_cost DECIMAL(12,2),
    travel_duration_minutes INT,
    travel_distance_km DECIMAL(10,2),

    order_index INT NOT NULL,
    note NVARCHAR(MAX),

    FOREIGN KEY (itinerary_day_id)
        REFERENCES itinerary_days(id) ON DELETE CASCADE,

    FOREIGN KEY (place_id)
        REFERENCES places(id),

    CHECK (duration_minutes IS NULL OR duration_minutes >= 0),
    CHECK (estimated_cost IS NULL OR estimated_cost >= 0),

    UNIQUE (itinerary_day_id, order_index)
);

CREATE INDEX idx_itinerary_activities_day
ON itinerary_activities(itinerary_day_id, order_index);



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
),

(
    N'Cầu Sông Hàn',
    N'Cầu Sông Hàn là cây cầu quay đầu tiên do các kỹ sư và công nhân Việt Nam tự thiết kế và thi công, biểu tượng cho sức sống và sự vươn lên của Đà Nẵng. Cầu nối liền hai bờ sông Hàn giữa quận Hải Châu và quận Sơn Trà. Điểm đặc biệt nhất là phần nhịp giữa cầu có thể quay 90 độ quanh trục theo lịch vận hành đêm để tàu thuyền lớn qua lại, thu hút đông đảo du khách chiêm ngưỡng.',
    N'Đường Lê Duẩn - Bạch Đằng, phường Hải Châu 1, quận Hải Châu, thành phố Đà Nẵng',
    16.0722,
    108.2275,
    geography::Point(16.0722, 108.2275, 4326),
    6,
    0
),

(
    N'Cầu Thuận Phước',
    N'Cầu Thuận Phước là cây cầu treo dây võng dài nhất Việt Nam, nằm ở vị trí đặc biệt nơi sông Hàn đổ ra vịnh Đà Nẵng. Cây cầu nối đường Nguyễn Tất Thành với bán đảo Sơn Trà. Với kiến trúc thanh thoát, hiện đại và tầm nhìn khoáng đạt hướng thẳng ra biển Đông và bán đảo Sơn Trà, Cầu Thuận Phước là điểm ngắm hoàng hôn và chụp ảnh phong cảnh rất được ưa chuộng.',
    N'Đường Nguyễn Tất Thành - Lê Đức Thọ, phường Thuận Phước, quận Hải Châu, thành phố Đà Nẵng',
    16.0967,
    108.2228,
    geography::Point(16.0967, 108.2228, 4326),
    6,
    0
),

(
    N'Cầu Trần Thị Lý',
    N'Cầu Trần Thị Lý là cây cầu dây văng hiện đại bắc qua sông Hàn, nổi bật với trụ tháp nghiêng cao 145 mét và hệ thống dây văng tỏa ra tựa như cánh buồm căng gió hướng ra đại dương. Cây cầu mang vẻ đẹp tạo hình độc đáo, đặc biệt rực rỡ vào ban đêm với hệ thống đèn đổi màu hiện đại soi bóng xuống mặt nước sông Hàn.',
    N'Đường Duy Tân - 2 Tháng 9, phường Hòa Cường Bắc, quận Hải Châu, thành phố Đà Nẵng',
    16.0503,
    108.2278,
    geography::Point(16.0503, 108.2278, 4326),
    6,
    0
),

(
    N'Bãi biển Non Nước',
    N'Bãi biển Non Nước nằm dọc theo cung đường Trường Sa, ngay dưới chân danh thắng Ngũ Hành Sơn. Nơi đây sở hữu bãi cát trắng mịn thoai thoải kéo dài khoảng 5km, làn nước trong xanh êm đềm và rặng phi lao xanh ngát. Bãi biển giữ được vẻ đẹp yên bình, ít xô bồ, rất thích hợp cho các hoạt động tắm biển, nghỉ dưỡng, thể thao bãi biển và thưởng thức hải sản tươi ngon.',
    N'Đường Trường Sa, phường Hòa Hải, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    16.0028,
    108.2678,
    geography::Point(16.0028, 108.2678, 4326),
    4,
    0
),

(
    N'Rạn Nam Ô',
    N'Rạn Nam Ô là dải đá ngầm tự nhiên nằm ven bờ biển làng chài cổ Nam Ô, quận Liên Chiểu. Vào mùa xuân từ khoảng tháng 1 đến tháng 3 âm lịch, những tảng đá ngầm và khối đá san hô phủ kín rêu xanh mướt tạo nên khung cảnh thiên nhiên kỳ ảo. Du khách đến đây không chỉ để chụp ảnh với thảm rêu mà còn có dịp khám phá làng nghề làm nước mắm Nam Ô truyền thống trứ danh.',
    N'Phường Hòa Hiệp Nam, quận Liên Chiểu, thành phố Đà Nẵng',
    16.1264,
    108.1258,
    geography::Point(16.1264, 108.1258, 4326),
    4,
    0
),

(
    N'Ghềnh Bàng',
    N'Ghềnh Bàng tọa lạc trên bán đảo Sơn Trà, cách trung tâm thành phố khoảng 20km. Nơi đây nổi tiếng với đường bờ biển dài khoảng 2km gồm vô số khối đá lớn nhỏ nhô ra biển, làn nước xanh ngọc bích nhìn thấy tận đáy và rạn san hô tự nhiên đa sắc. Đây là thiên đường dành cho những ai yêu thích du lịch trải nghiệm, cắm trại, câu cá và lặn ngắm san hô tự túc.',
    N'Bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1255,
    108.3188,
    geography::Point(16.1255, 108.3188, 4326),
    6,
    0
),

(
    N'Đỉnh Bàn Cờ',
    N'Đỉnh Bàn Cờ nằm ở độ cao gần 700 mét so với mực nước biển trên bán đảo Sơn Trà, là điểm cao nhất có thể tiếp cận bằng đường bộ tại đây. Nơi này gắn liền với truyền thuyết hai vị tiên ông đánh cờ, nổi bật với bức tượng Đế Thích bằng đá ngồi trầm ngâm bên bàn cờ dang dở. Từ đỉnh núi, du khách có thể phóng tầm mắt bao trọn toàn cảnh thành phố Đà Nẵng, biển Đông và đèo Hải Vân.',
    N'Đỉnh bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1219,
    108.2819,
    geography::Point(16.1219, 108.2819, 4326),
    6,
    0
),

(
    N'Chùa Quan Thế Âm',
    N'Chùa Quan Thế Âm tọa lạc dưới chân ngọn Kim Sơn thuộc quần thể Ngũ Hành Sơn. Chùa là trung tâm Phật giáo quan trọng gắn liền với động Quan Âm huyền bí và lễ hội Quán Thế Âm 19/2 âm lịch hàng năm - Di sản văn hóa phi vật thể quốc gia. Không gian chùa trang nghiêm, thanh tịnh với bảo tàng Phật giáo lưu giữ hàng trăm cổ vật tôn giáo quý giá.',
    N'48 Sư Vạn Hạnh, phường Hòa Hải, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    15.9961,
    108.2528,
    geography::Point(15.9961, 108.2528, 4326),
    9,
    0
),

(
    N'Nhà thờ Chính tòa Đà Nẵng',
    N'Nhà thờ Chính tòa Đà Nẵng (thường gọi là Nhà thờ Con Gà) được xây dựng từ năm 1923 thời Pháp thuộc. Nhà thờ mang phong cách kiến trúc Gothic cổ điển đặc trưng với các mái vòm nhọn, cửa kính màu rực rỡ và lớp sơn màu hồng pastel nổi bật giữa lòng đô thị. Trên đỉnh cột thu lôi của tháp chuông có tượng một con gà bằng đồng màu xám đặc trưng.',
    N'156 Trần Phú, phường Hải Châu 1, quận Hải Châu, thành phố Đà Nẵng',
    16.0667,
    108.2239,
    geography::Point(16.0667, 108.2239, 4326),
    9,
    0
),

(
    N'Chùa Tam Thai',
    N'Chùa Tam Thai là ngôi cổ tự linh thiêng được xây dựng từ năm 1630 thời Hậu Lê và được vua Minh Mạng ban sắc tứ Quốc tự vào năm 1825. Chùa tọa lạc trên ngọn Thủy Sơn thuộc danh thắng Ngũ Hành Sơn, nằm ẩn mình sau cổng tam quan rêu phong cổ kính giữa những rặng cây cổ thụ. Chùa là điểm hành hương tâm linh chiêm bái nổi tiếng của du khách thập phương.',
    N'Ngọn Thủy Sơn, phường Hòa Hải, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    16.0044,
    108.2631,
    geography::Point(16.0044, 108.2631, 4326),
    9,
    0
),

(
    N'Bảo tàng Đà Nẵng',
    N'Bảo tàng Đà Nẵng tọa lạc tại khuôn viên Di tích Quốc gia đặc biệt Thành Điện Hải - tiền đồn phòng thủ quân sự quan trọng chống thực dân Pháp xâm lược năm 1858. Bảo tàng lưu giữ và trưng bày hàng ngàn tài liệu, hiện vật phản ánh lịch sử hình thành, đấu tranh cách mạng, văn hóa dân gian và sự phát triển vượt bậc của thành phố Đà Nẵng qua các thời kỳ.',
    N'24 Trần Phú, phường Thạch Thang, quận Hải Châu, thành phố Đà Nẵng',
    16.0756,
    108.2231,
    geography::Point(16.0756, 108.2231, 4326),
    5,
    0
),

(
    N'Bảo tàng Mỹ thuật Đà Nẵng',
    N'Bảo tàng Mỹ thuật Đà Nẵng là bảo tàng mỹ thuật duy nhất tại khu vực miền Trung - Tây Nguyên, hiện lưu giữ và trưng bày hơn 1.000 tác phẩm hội họa, đồ họa, điêu khắc nghệ thuật hiện đại và mỹ thuật dân gian truyền thống. Không gian bảo tàng ba tầng được bài trí nghệ thuật, là điểm hẹn lý tưởng cho những du khách say mê sáng tạo nghệ thuật thị giác.',
    N'78 Lê Duẩn, phường Thạch Thang, quận Hải Châu, thành phố Đà Nẵng',
    16.0728,
    108.2197,
    geography::Point(16.0728, 108.2197, 4326),
    5,
    0
),

(
    N'Bảo tàng Tranh 3D Art in Paradise',
    N'Bảo tàng Tranh 3D Art in Paradise Đà Nẵng là khu giải trí nghệ thuật đánh lừa thị giác quy mô lớn với diện tích hơn 4.000m². Nơi đây sở hữu hàng trăm bức tranh 3D sống động được vẽ trực tiếp trên tường và sàn nhà bởi các nghệ sĩ tài năng đến từ Hàn Quốc, chia thành nhiều chủ đề hấp dẫn như Thế giới Ảo ảnh, Đại dương, Động vật hoang dã và Cổ tích.',
    N'Lô C2-10 Trần Nhân Tông, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.0911,
    108.2439,
    geography::Point(16.0911, 108.2439, 4326),
    5,
    0
),

(
    N'Chợ Cồn',
    N'Chợ Cồn là một trong hai khu chợ thương mại lâu đời và tấp nập bậc nhất tại Đà Nẵng, được mệnh danh là thiên đường ẩm thực đường phố của miền Trung. Chợ có hàng trăm gian hàng ẩm thực trong nhà và ngoài trời phục vụ đầy đủ các món đặc sản trứ danh như bánh tráng cuốn thịt heo, mì Quảng, ốc hút, bánh xèo, chè và đa dạng các loại hải sản khô đóng gói.',
    N'290 Hùng Vương, phường Vĩnh Trung, quận Hải Châu, thành phố Đà Nẵng',
    16.0683,
    108.2153,
    geography::Point(16.0683, 108.2153, 4326),
    10,
    0
),

(
    N'Chợ đêm Sơn Trà',
    N'Chợ đêm Sơn Trà nằm ngay gần bờ đông sông Hàn và đầu Cầu Rồng, là điểm vui chơi, mua sắm và thưởng thức ẩm thực đêm sôi động bậc nhất của Đà Nẵng. Chợ quy tụ hơn 150 gian hàng bày bán phong phú các món hải sản nướng tươi sống, đồ ăn vặt đường phố, quà lưu niệm thủ công mỹ nghệ và các chương trình nghệ thuật đường phố vào dịp cuối tuần.',
    N'Đường Mai Hắc Đế - Lý Nam Đế, phường An Hải Tây, quận Sơn Trà, thành phố Đà Nẵng',
    16.0617,
    108.2308,
    geography::Point(16.0617, 108.2308, 4326),
    10,
    0
),

(
    N'Chợ đêm Helio',
    N'Chợ đêm Helio nằm trong tổ hợp giải trí Helio Center, là không gian ẩm thực đêm ngoài trời quy mô lớn được thiết kế hiện đại, lung linh ánh đèn. Chợ nổi bật với hàng trăm món ăn vặt châu Á, hải sản tươi nướng tại chỗ, khu bia thủ công và sân khấu âm nhạc sống sôi động hàng đêm, thu hút đông đảo giới trẻ và khách du lịch trải nghiệm không khí náo nhiệt.',
    N'Đường 2 Tháng 9, phường Hòa Cường Bắc, quận Hải Châu, thành phố Đà Nẵng',
    16.0378,
    108.2236,
    geography::Point(16.0378, 108.2236, 4326),
    10,
    0
),

(
    N'Công viên Châu Á (Asia Park)',
    N'Công viên Châu Á (Asia Park - Da Nang Downtown) là công viên giải trí quy mô hàng đầu Đông Nam Á nằm bên bờ sông Hàn. Điểm nhấn nổi bật nhất là Vòng quay Mặt Trời Sun Wheel cao 115m lọt top 10 vòng quay cao nhất thế giới, cho phép du khách ngắm nhìn toàn cảnh thành phố rực rỡ về đêm. Công viên kết hợp các trò chơi cảm giác mạnh hiện đại và không gian kiến trúc mô phỏng nét văn hóa tiêu biểu của nhiều quốc gia châu Á.',
    N'01 Phan Đăng Lưu, phường Hòa Cường Bắc, quận Hải Châu, thành phố Đà Nẵng',
    16.0389,
    108.2272,
    geography::Point(16.0389, 108.2272, 4326),
    6,
    0
),

(
    N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài',
    N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài tọa lạc tại khu bảo tồn thiên nhiên Bà Nà Núi Chúa, cách trung tâm Đà Nẵng khoảng 30km về phía Tây. Nơi đây sở hữu nguồn khoáng nóng tự nhiên dồi dào bắt nguồn từ lòng đất, kết hợp mô hình tắm Onsen kiểu Nhật, công viên nước trên núi, hồ sục Jacuzzi và dịch vụ tắm bùn khoáng thư giãn giữa khung cảnh thiên nhiên rừng nguyên sinh trong lành.',
    N'Quốc lộ 14G, xã Hòa Phú, huyện Hòa Vang, thành phố Đà Nẵng',
    15.9733,
    108.0167,
    geography::Point(15.9733, 108.0167, 4326),
    6,
    0
),

(
    N'Làng đá mỹ nghệ Non Nước',
    N'Làng đá mỹ nghệ Non Nước là làng nghề thủ công truyền thống hình thành từ thế kỷ 17 dưới chân núi Ngũ Hành Sơn, đã được công nhận là Di sản văn hóa phi vật thể quốc gia. Các nghệ nhân điêu khắc tài hoa tại đây biến những khối đá cẩm thạch thô ráp thành các tác phẩm tượng Phật, linh vật, đồ trang sức và tượng nghệ thuật tinh xảo nức tiếng trong và ngoài nước.',
    N'Đường Huyền Trân Công Chúa, phường Hòa Hải, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    16.0053,
    108.2619,
    geography::Point(16.0053, 108.2619, 4326),
    8,
    0
),

(
    N'Hồ Xanh Sơn Trà',
    N'Hồ Xanh (còn gọi là Hồ Bãi Bụt) là hồ nước tự nhiên tuyệt đẹp nằm ẩn mình dưới chân bán đảo Sơn Trà. Hồ nổi bật với mặt nước trong vắt màu xanh ngọc bích phẳng lặng quanh năm, bao bọc bởi những vách đá sừng sững và cây rừng hoang sơ. Đây là địa điểm dã ngoại, chụp ảnh cưới và check-in yêu thích của nhiều bạn trẻ khi tìm kiếm sự bình yên gần gũi với thiên nhiên.',
    N'Đường Hoàng Sa, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1083,
    108.2736,
    geography::Point(16.1083, 108.2736, 4326),
    6,
    0
),

(
    N'Cây đa ngàn năm Sơn Trà',
    N'Cây đa ngàn năm Sơn Trà (còn được gọi là Bách niên đại thụ) tọa lạc tại tiểu khu 63 thuộc Khu bảo tồn thiên nhiên bán đảo Sơn Trà. Cây đa có tuổi thọ ước tính hơn 800 năm, cao khoảng 22m với chu vi thân chính lên tới 10m và hàng chục rễ phụ đâm sâu vào lòng đất tạo thành mạng lưới kỳ vĩ. Đây là điểm dừng chân nổi tiếng trên cung đường khám phá thiên nhiên hoang sơ của bán đảo Sơn Trà.',
    N'Bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1268,
    108.3182,
    geography::Point(16.1268, 108.3182, 4326),
    6,
    0
),

(
    N'Mũi Nghê Sơn Trà',
    N'Mũi Nghê nằm ở cực đông nam bán đảo Sơn Trà, nơi có mỏm đá tự nhiên mang hình dáng tựa con sư tử biển (nghê đá) đang quay đầu chầu về núi. Đây là địa điểm đón tia nắng bình minh đầu tiên của thành phố Đà Nẵng. Nơi đây hấp dẫn các tín đồ phượt và du lịch mạo hiểm bởi hồ bơi tự nhiên giữa lòng biển, làn nước trong vắt và rạn san hô hoang sơ.',
    N'Mũi Đông Nam bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1102,
    108.3283,
    geography::Point(16.1102, 108.3283, 4326),
    6,
    0
),

(
    N'Bãi Rạng Sơn Trà',
    N'Bãi Rạng là bãi biển hoang sơ tuyệt đẹp nằm ven cung đường biển Hoàng Sa trên bán đảo Sơn Trà, cách chùa Linh Ứng chỉ khoảng 2km. Nơi đây sở hữu dải cát vàng thoai thoải xen lẫn những tảng đá hoa cương nhấp nhô và rạn san hô tự nhiên ven bờ. Bãi Rạng là địa điểm cắm trại, tắm biển và thưởng thức hải sản tươi sống bên bờ biển quen thuộc của người dân bản địa.',
    N'Đường Hoàng Sa, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1042,
    108.2865,
    geography::Point(16.1042, 108.2865, 4326),
    4,
    0
),

(
    N'Bãi Bụt Sơn Trà',
    N'Bãi Bụt nằm ngay dưới chân ngôi cổ tự Linh Ứng Sơn Trà, tựa lưng vào cánh rừng nguyên sinh và ôm lấy một eo biển hình cánh cung phẳng lặng. Theo truyền thuyết dân gian, nơi đây từng được Phật Bà Quan Âm hiển linh cứu giúp ngư dân vượt qua bão tố nên được gọi là cõi Bụt (Bãi Bụt). Đây là điểm du lịch sinh thái biển kết hợp văn hóa tâm linh nổi tiếng bậc nhất của Đà Nẵng.',
    N'Đường Hoàng Sa, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1015,
    108.2758,
    geography::Point(16.1015, 108.2758, 4326),
    4,
    0
),

(
    N'Bãi biển Tiên Sa',
    N'Bãi biển Tiên Sa nằm ở phía bắc bán đảo Sơn Trà, cách trung tâm thành phố Đà Nẵng khoảng 9km. Nơi đây được bao bọc bởi cảnh quan núi rừng hoang sơ và gắn liền với truyền thuyết các nàng tiên giáng trần ngắm cảnh tắm mát. Với bãi cát trắng mịn thoai thoải, mặt nước phẳng lặng như gương và rặng cây xanh mát, Bãi biển Tiên Sa là điểm nghỉ dưỡng sinh thái biệt lập và yên tĩnh.',
    N'01 Yết Kiêu, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1235,
    108.2322,
    geography::Point(16.1235, 108.2322, 4326),
    4,
    0
),

(
    N'Hải đăng Tiên Sa',
    N'Hải đăng Tiên Sa (còn gọi là Hải đăng Sơn Trà) được người Pháp xây dựng vào năm 1902 tại độ cao khoảng 223m so với mực nước biển. Đây là một trong những ngọn hải đăng cổ kính và đẹp nhất Việt Nam, mang đậm dấu ấn kiến trúc kiểu Pháp với sắc sơn vàng rực rỡ và các ô cửa màu xanh lá cổ điển. Từ đây, du khách có thể phóng tầm mắt bao trọn biển Đông bao la và cảnh sắc núi non hùng vĩ.',
    N'Đỉnh bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1389,
    108.3142,
    geography::Point(16.1389, 108.3142, 4326),
    6,
    0
),

(
    N'Động Huyền Không',
    N'Động Huyền Không là hang động lộ thiên lớn và tráng lệ bậc nhất trong quần thể danh thắng Ngũ Hành Sơn, tọa lạc trên đỉnh Thủy Sơn. Động có vòm hình tròn độc đáo với năm vòm lộ thiên đón ánh sáng mặt trời rọi thẳng xuống lòng hang sâu, tạo nên luồng hào quang huyền ảo như chốn bồng lai. Bên trong động thờ tượng Phật Thích Ca bằng đá uy nghiêm cùng đền thờ Trang Nghiêm Tự cổ kính.',
    N'Ngọn Thủy Sơn, danh thắng Ngũ Hành Sơn, phường Hòa Hải, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    16.0042,
    108.2628,
    geography::Point(16.0042, 108.2628, 4326),
    9,
    0
),

(
    N'Động Âm Phủ',
    N'Động Âm Phủ nằm ngay dưới chân ngọn Thủy Sơn thuộc Ngũ Hành Sơn, là một trong những hang động tự nhiên dài và sâu nhất trong quần thể núi đá vôi này. Động được tạo dựng công phu nhằm tái hiện 18 tầng địa ngục và cõi thiên thai theo triết lý Phật giáo và giáo lý nhân quả, khuyên răn con người hướng thiện, từ bỏ điều ác để sống đời an lạc.',
    N'Đường Huyền Trân Công Chúa, phường Hòa Hải, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    16.0025,
    108.2615,
    geography::Point(16.0025, 108.2615, 4326),
    9,
    0
),

(
    N'Chùa Pháp Lâm',
    N'Chùa Pháp Lâm (tên cũ là Chùa Tỉnh Hội Đà Nẵng) được xây dựng từ năm 1934, tọa lạc tại vị trí trung tâm sầm uất trên đường Ông Ích Khiêm. Đây là trụ sở của Ban Trị sự Giáo hội Phật giáo Việt Nam thành phố Đà Nẵng và là trung tâm Phật giáo hàng đầu của thành phố. Chùa mang phong cách kiến trúc Á Đông thanh tịnh với pho tượng Đức Phật Thích Ca bằng đồng lớn bậc nhất miền Trung.',
    N'574 Ông Ích Khiêm, phường Nam Dương, quận Hải Châu, thành phố Đà Nẵng',
    16.0645,
    108.2162,
    geography::Point(16.0645, 108.2162, 4326),
    9,
    0
),

(
    N'Chùa Nam Sơn',
    N'Chùa Nam Sơn được thành lập từ năm 1962 bởi Đại đức Thích Từ Mẫn, tọa lạc tại vùng quê thanh bình Hòa Châu, huyện Hòa Vang. Chùa nổi tiếng khắp cả nước nhờ khuôn viên rộng lớn hơn 10.000m² mang kiến trúc cung đình cổ phong tuyệt mỹ, với các mái ngói cong son rực rỡ, hồ nước phóng sinh rộng lớn, cầu gỗ uốn lượn và hàng trăm chiếc lồng đèn đỏ rực rỡ.',
    N'Thôn Cẩm Nam, xã Hòa Châu, huyện Hòa Vang, thành phố Đà Nẵng',
    15.9868,
    108.2045,
    geography::Point(15.9868, 108.2045, 4326),
    9,
    0
),

(
    N'Bảo tàng Đồng Đình',
    N'Bảo tàng Đồng Đình (Khu nhà ký ức) nằm trên bán đảo Sơn Trà, do NSƯT Đoàn Huy Giao sáng lập và được cấp phép là bảo tàng tư nhân đầu tiên tại miền Trung. Bảo tàng ẩn mình dưới những tán cây rừng nguyên sinh và những rặng cây đồng đình đặc trưng của Sơn Trà, tái hiện sinh động không gian văn hóa nhà rường xứ Quảng, đồ gốm cổ hàng ngàn năm và các tác phẩm mỹ thuật đương đại độc đáo.',
    N'Đường Hoàng Sa, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1072,
    108.2785,
    geography::Point(16.1072, 108.2785, 4326),
    5,
    0
),

(
    N'Nhà trưng bày Hoàng Sa',
    N'Nhà trưng bày Hoàng Sa tọa lạc tại ngã ba đường Hoàng Sa và Phan Bá Phiến, bên bờ biển Sơn Trà thơ mộng. Công trình được khánh thành năm 2018 với kiến trúc độc đáo mô phỏng hình con dấu chủ quyền triều Nguyễn (Con dấu Hoàng đế ngự lãm). Nơi đây lưu giữ hàng trăm tư liệu, bản đồ cổ, hiện vật lịch sử và pháp lý khẳng định chủ quyền không thể chối cãi của Việt Nam đối với quần đảo Hoàng Sa.',
    N'Đường Hoàng Sa, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.0945,
    108.2422,
    geography::Point(16.0945, 108.2422, 4326),
    5,
    0
),

(
    N'Hải Vân Quan',
    N'Hải Vân Quan tọa lạc tại đỉnh đèo Hải Vân ở độ cao 496m so với mực nước biển, trên ranh giới địa phận giữa thành phố Đà Nẵng và tỉnh Thừa Thiên Huế. Được vua Minh Mạng cho xây dựng vào năm 1826 như một cửa ải quân sự hiểm yếu phòng thủ con đường thiên lý Bắc - Nam, nơi đây được vua Lê Thánh Tông xưng tặng là "Thiên hạ đệ nhất hùng quan". Di tích Quốc gia này vừa được phục hồi và đại trùng tu nguyên bản vô cùng bề thế.',
    N'Đỉnh đèo Hải Vân, phường Hòa Hiệp Bắc, quận Liên Chiểu, thành phố Đà Nẵng',
    16.1969,
    108.1311,
    geography::Point(16.1969, 108.1311, 4326),
    5,
    0
),

(
    N'Làng cổ Phong Nam',
    N'Làng cổ Phong Nam nằm ven bờ sông Tây Tịnh, thuộc xã Hòa Châu, huyện Hòa Vang, cách trung tâm Đà Nẵng khoảng 10km về phía Tây Nam. Đây là một trong số ít những ngôi làng cổ vẫn còn bảo lưu trọn vẹn nét đẹp mộc mạc của làng quê nông thôn Việt Nam truyền thống với cổng làng rêu phong, cây đa bến nước, lũy tre xanh ngát, đình làng cổ kính và những ngôi nhà rường trăm năm tuổi.',
    N'Thôn Phong Nam, xã Hòa Châu, huyện Hòa Vang, thành phố Đà Nẵng',
    15.9928,
    108.1925,
    geography::Point(15.9928, 108.1925, 4326),
    6,
    0
),

(
    N'Làng chiếu Cẩm Nê',
    N'Làng chiếu Cẩm Nê nằm bên dòng sông Yên hiền hòa thuộc xã Hòa Tiến, huyện Hòa Vang, cách trung tâm Đà Nẵng 14km. Đây là làng nghề dệt chiếu hoa truyền thống có lịch sử hơn 500 năm, từng là sản phẩm tiến vua danh tiếng dưới triều Nguyễn. Chiếu Cẩm Nê nổi tiếng khắp cả nước nhờ sợi cói bền chắc, hoa văn rực rỡ và đặc tính mùa hè nằm mát mẻ, mùa đông ấm áp.',
    N'Thôn Cẩm Nê, xã Hòa Tiến, huyện Hòa Vang, thành phố Đà Nẵng',
    15.9685,
    108.2018,
    geography::Point(15.9685, 108.2018, 4326),
    8,
    0
),

(
    N'Hồ Hòa Trung',
    N'Hồ Hòa Trung là hồ nước nhân tạo lớn phục vụ tưới tiêu nằm cách trung tâm Đà Nẵng khoảng 20km về phía Tây. Vào mùa cạn (khoảng từ tháng 9 đến tháng 10 hàng năm), lòng hồ cạn nước biến thành một thảo nguyên cỏ xanh mướt bao la nhấp nhô các gò đất, được mệnh danh là "Tây Tạng thu nhỏ" giữa lòng Đà Nẵng. Đây là địa điểm cắm trại dã ngoại, chèo thuyền kayak và chụp ảnh dã ngoại cực "hot" của giới trẻ.',
    N'Xã Hòa Liên và xã Hòa Sơn, huyện Hòa Vang, thành phố Đà Nẵng',
    16.0583,
    108.0815,
    geography::Point(16.0583, 108.0815, 4326),
    6,
    0
),

(
    N'Khu du lịch Suối Mơ',
    N'Khu du lịch sinh thái Suối Mơ tọa lạc ngay dưới chân núi Bà Nà, thuộc xã Hòa Ninh, huyện Hòa Vang, cách trung tâm thành phố Đà Nẵng khoảng 22km. Bắt nguồn từ những mạch nước ngầm thanh khiết trên đỉnh Bà Nà chảy tràn qua các vách đá hoa cương, Suối Mơ sở hữu dòng suối trong vắt mát lạnh, các thác nước bọt tung trắng xóa và những hồ tắm tự nhiên giữa rừng cây râm mát.',
    N'Xã Hòa Ninh, huyện Hòa Vang, thành phố Đà Nẵng',
    16.0275,
    108.0642,
    geography::Point(16.0275, 108.0642, 4326),
    6,
    0
),

(
    N'Khu du lịch sinh thái Yên Retreat',
    N'Yên Retreat là khu du lịch sinh thái và cắm trại cao cấp (glamping) nằm bên bờ dòng sông Cu Đê thơ mộng thuộc xã Hòa Bắc, huyện Hòa Vang, cách trung tâm Đà Nẵng khoảng 35km. Nơi đây gây ấn tượng với không gian thanh bình tuyệt đối, bãi cỏ xanh ngát trải dài thoai thoải sát mép nước, những căn lều trắng kiểu bohemian vintage và khung cảnh thung lũng sông nước lãng mạn như trời Âu.',
    N'Xã Hòa Bắc, huyện Hòa Vang, thành phố Đà Nẵng',
    16.1285,
    108.0532,
    geography::Point(16.1285, 108.0532, 4326),
    6,
    0
),

(
    N'Làng sinh thái Thái Lai',
    N'Làng sinh thái Thái Lai nằm bên bờ sông Túy Loan thuộc xã Hòa Nhơn, huyện Hòa Vang, cách trung tâm Đà Nẵng khoảng 20km. Ngôi làng lưu giữ hệ thống nhà rường cổ kính có tuổi đời hơn 200 năm cùng nếp sống văn hóa truyền thống mộc mạc của cư dân nông nghiệp xứ Quảng. Đây là mô hình du lịch sinh thái cộng đồng tiêu biểu của thành phố Đà Nẵng.',
    N'Thôn Thái Lai, xã Hòa Nhơn, huyện Hòa Vang, thành phố Đà Nẵng',
    15.9882,
    108.1482,
    geography::Point(15.9882, 108.1482, 4326),
    6,
    0
),

(
    N'Bãi biển Phạm Văn Đồng',
    N'Bãi biển Phạm Văn Đồng nằm ở điểm cuối của đại lộ Phạm Văn Đồng cắt đường Võ Nguyên Giáp, ngay cạnh Công viên Biển Đông. Đây là một trong những bãi tắm công cộng hiện đại và quy mô nhất của Đà Nẵng, sở hữu dải cát trắng mịn thoai thoải, rặng dừa xanh đung đưa trong gió và hệ thống cứu hộ đạt tiêu chuẩn quốc tế. Nơi đây là điểm tắm biển, thể thao biển và vui chơi ngoài trời tấp nập hàng đầu.',
    N'Đường Võ Nguyên Giáp - Phạm Văn Đồng, phường Phước Mỹ, quận Sơn Trà, thành phố Đà Nẵng',
    16.0712,
    108.2475,
    geography::Point(16.0712, 108.2475, 4326),
    4,
    0
),

(
    N'Bãi biển Bắc Mỹ An',
    N'Bãi biển Bắc Mỹ An nằm cách trung tâm Đà Nẵng khoảng 4km về phía Đông Nam, trải dài gần 4km bờ cát trắng muốt tuyệt đẹp nối liền Mỹ Khê và Non Nước. Nơi đây quy tụ chuỗi các khu nghỉ dưỡng đẳng cấp 5 sao quốc tế như Furama Resort, Pullman Danang. Với bãi cát mịn màng, sóng biển êm dịu và không gian sang trọng, Bắc Mỹ An là thiên đường nghỉ dưỡng biển cao cấp hàng đầu Việt Nam.',
    N'Đường Võ Nguyên Giáp, phường Khuê Mỹ, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
    16.0388,
    108.2492,
    geography::Point(16.0388, 108.2492, 4326),
    4,
    0
),

(
    N'Bãi biển Xuân Thiều',
    N'Bãi biển Xuân Thiều (từng được lính Mỹ gọi là Biển Đỏ - Red Beach) nằm dọc theo cung đường ven biển Nguyễn Tất Thành thuộc quận Liên Chiểu, ôm trọn lấy vòng cung vịnh Đà Nẵng. Nơi đây sở hữu bãi cát dài phẳng lặng, làn nước xanh êm đềm và góc nhìn ngoạn mục hướng thẳng về bán đảo Sơn Trà và dãy đèo Hải Vân. Đây là bãi biển lý tưởng để ngắm cảnh biển hoàng hôn rực rỡ và tận hưởng sự bình yên.',
    N'Đường Nguyễn Tất Thành, phường Hòa Hiệp Nam, quận Liên Chiểu, thành phố Đà Nẵng',
    16.0988,
    108.1565,
    geography::Point(16.0988, 108.1565, 4326),
    4,
    0
),

(
    N'Công viên APEC Đà Nẵng',
    N'Công viên Vườn tượng APEC mở rộng nằm bên bờ Tây sông Hàn, gần chân Cầu Rồng thuộc quận Hải Châu. Công viên có tổng diện tích hơn 8.600m², nổi bật với công trình mái vòm kiến trúc "Cánh diều bay cao" uốn lượn uốn khúc bằng thép độc đáo, tượng trưng cho sự phát triển vươn mình mạnh mẽ của thành phố Đà Nẵng. Đây là không gian công cộng xanh, tổ chức sự kiện văn hóa và điểm check-in kiến trúc hàng đầu của thành phố.',
    N'Đường 2 Tháng 9, phường Bình Hiên, quận Hải Châu, thành phố Đà Nẵng',
    16.0602,
    108.2248,
    geography::Point(16.0602, 108.2248, 4326),
    6,
    0
),

(
    N'Công viên Biển Đông',
    N'Công viên Biển Đông (còn được gọi là Công viên Hòa Bình hay Công viên Bồ Câu) nằm ngay mặt tiền ngã ba đại lộ Phạm Văn Đồng và đường ven biển Võ Nguyên Giáp. Đây là quảng trường công viên ven biển lớn nhất của Đà Nẵng, nổi bật với đàn chim bồ câu hàng ngàn con rợp bóng bay lượn và bức tượng Mẹ Âu Cơ thiêng liêng hướng ra biển Đông. Nơi đây là trung tâm tổ chức các lễ hội mùa hè, đại nhạc hội âm nhạc và sự kiện thể thao biển tầm cỡ.',
    N'Ngã ba đường Phạm Văn Đồng - Võ Nguyên Giáp, phường Phước Mỹ, quận Sơn Trà, thành phố Đà Nẵng',
    16.0705,
    108.2468,
    geography::Point(16.0705, 108.2468, 4326),
    6,
    0
),

(
    N'Cầu đi bộ Nguyễn Văn Trỗi',
    N'Cầu Nguyễn Văn Trỗi là cây cầu đường bộ đầu tiên bắc qua dòng sông Hàn, do hãng thầu RMK-BRJ của Mỹ xây dựng từ năm 1965 để phục vụ vận tải quân sự trong chiến tranh. Cầu có kết cấu vòm giàn thép Poni đặc trưng màu vàng nổi bật. Sau khi các cây cầu hiện đại được xây dựng, cầu Nguyễn Văn Trỗi được thành phố giữ lại và chuyển đổi thành cây cầu đi bộ đầu tiên của Đà Nẵng, trở thành chứng nhân lịch sử và điểm dạo mát ngắm sông Hàn yêu thích.',
    N'Nối đường Trần Hưng Đạo và đường 2 Tháng 9, thành phố Đà Nẵng',
    16.0512,
    108.2281,
    geography::Point(16.0512, 108.2281, 4326),
    6,
    0
),

(
    N'Phố ẩm thực Huỳnh Thúc Kháng',
    N'Phố ẩm thực Huỳnh Thúc Kháng nằm ngay trung tâm quận Hải Châu, được mệnh danh là con phố điểm tâm sáng và ẩm thực truyền thống lâu đời bậc nhất của Đà Nẵng. Tuyến phố dài gần 1km tập trung hàng chục quán ăn gia truyền nức tiếng phục vụ đầy đủ các món đặc sản xứ Quảng chuẩn vị, hấp dẫn đông đảo người dân địa phương và du khách sành ăn mỗi ngày.',
    N'Đường Huỳnh Thúc Kháng, phường Nam Dương, quận Hải Châu, thành phố Đà Nẵng',
    16.0592,
    108.2195,
    geography::Point(16.0592, 108.2195, 4326),
    10,
    0
),

(
    N'Chợ đầu mối Hòa Cường',
    N'Chợ đầu mối Hòa Cường là chợ đầu mối nông sản, rau củ quả và trái cây có quy mô lớn nhất thành phố Đà Nẵng và cả khu vực miền Trung, nằm trên địa bàn quận Hải Châu. Chợ hoạt động sầm uất thâu đêm suốt sáng, là nơi tập kết và phân phối hàng trăm tấn hàng nông sản mỗi ngày từ Đà Lạt, miền Tây, miền Bắc và các vùng ngoại thành Đà Nẵng. Đây là địa điểm độc đáo để khám phá nhịp sống lao động đêm sôi động của thành phố.',
    N'Đường Lê Nổ - Hồ Nguyên Trừng, phường Hòa Cường Nam, quận Hải Châu, thành phố Đà Nẵng',
    16.0355,
    108.2145,
    geography::Point(16.0355, 108.2145, 4326),
    10,
    0
),

(
    N'Đặc sản Quán Trần Đà Nẵng',
    N'Quán Trần là thương hiệu ẩm thực đặc sản cao cấp nổi tiếng bậc nhất Đà Nẵng với hơn 30 năm khẳng định thương hiệu. Quán tọa lạc tại số 4 đường Lê Duẩn ngay trung tâm thành phố. Món ăn làm nên tên tuổi lừng lẫy của Quán Trần là "Bánh tráng cuốn thịt heo hai đầu da" độc nhất vô nhị, ăn kèm mắm nêm cá cơm thượng hạng và đĩa rau sống xanh mướt hơn 20 loại rau vườn tươi non.',
    N'04 Lê Duẩn, phường Hải Châu 1, quận Hải Châu, thành phố Đà Nẵng',
    16.0675,
    108.2215,
    geography::Point(16.0675, 108.2215, 4326),
    1,
    0
),

(
    N'Mì Quảng Bà Mua Đà Nẵng',
    N'Mì Quảng Bà Mua là một trong những thương hiệu mì Quảng lâu đời và nổi tiếng hàng đầu tại Đà Nẵng với hệ thống nhiều chi nhánh phủ sóng khắp thành phố. Quán giữ trọn vẹn công thức nấu mì Quảng truyền thống xứ Quảng với sợi mì gạo dai mềm tự nhiên, nước nhưỡng sánh vàng béo ngậy nấu từ xương hầm và tôm thịt đậm đà, ăn kèm bánh tráng mè nướng giòn rụm và rau sống búp chuối tươi non.',
    N'95A Nguyễn Tri Phương, phường Chính Gián, quận Thanh Khê, thành phố Đà Nẵng',
    16.0588,
    108.2212,
    geography::Point(16.0588, 108.2212, 4326),
    1,
    0
),

(
    N'Cà phê Út Tịch Đà Nẵng',
    N'Cà phê Út Tịch tọa lạc tại vị trí đắc địa số 102 đường Bạch Đằng, nhìn thẳng ra dòng sông Hàn thơ mộng và cầu quay sông Hàn. Quán được thiết kế theo phong cách hoài niệm cổ điển tái hiện không gian nếp nhà phố thị Việt Nam thời kỳ bao cấp thập niên 1980. Với những bộ bàn ghế gỗ mộc xưa cũ, nền gạch hoa văn cổ điển và hương vị cà phê phin đậm đà, Út Tịch là điểm hẹn thư giãn và chụp ảnh check-in tuyệt đẹp bên sông Hàn.',
    N'102 Bạch Đằng, phường Hải Châu 1, quận Hải Châu, thành phố Đà Nẵng',
    16.0682,
    108.2242,
    geography::Point(16.0682, 108.2242, 4326),
    2,
    0
),

(
    N'Bãi Cát Vàng Sơn Trà',
    N'Bãi Cát Vàng tọa lạc trên bán đảo Sơn Trà, sở hữu diện tích khoảng 10.000m² với bãi cát vàng óng ả nép mình bên chân núi đá và cánh rừng nguyên sinh. Nơi đây có làn nước biển trong vắt như pha lê, hệ sinh thái san hô phong phú và dòng suối nước ngọt tự nhiên róc rách từ núi chảy thẳng ra biển. Bãi Cát Vàng là điểm du lịch sinh thái dã ngoại, chèo thuyền kayak và lặn ngắm san hô tuyệt vời.',
    N'Bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1215,
    108.3125,
    geography::Point(16.1215, 108.3125, 4326),
    4,
    0
),

(
    N'Vọng Cảnh Đài Sơn Trà',
    N'Vọng Cảnh Đài (Đài Vọng Cảnh) tọa lạc tại độ cao hơn 600m so với mực nước biển trên đỉnh bán đảo Sơn Trà. Nơi đây được đặt một trạm quan sát với kính viễn vọng và gắn liền với Trạm Radar Sơn Trà (trạm radar 29 được mệnh danh là "Mắt thần Đông Dương"). Từ vị trí vọng cảnh đài, du khách có thể phóng tầm mắt bao quát toàn cảnh đèo Hải Vân, vịnh Đà Nẵng, trạm radar quả cầu trắng và đảo Cù Lao Chàm phía xa.',
    N'Đỉnh bán đảo Sơn Trà, phường Thọ Quang, quận Sơn Trà, thành phố Đà Nẵng',
    16.1238,
    108.2715,
    geography::Point(16.1238, 108.2715, 4326),
    6,
    0
),

(
    N'Giếng Trời Đà Nẵng',
    N'Giếng Trời là thắng cảnh thiên nhiên hoang sơ ẩn mình sâu trong cánh rừng nguyên sinh Bà Nà - Núi Chúa thuộc xã Hòa Ninh, huyện Hòa Vang. Nơi đây nổi tiếng với thác nước lớn đổ thẳng từ vách đá dựng đứng xuống một hồ nước tự nhiên sâu thẳm, quanh năm có màu xanh ngọc bích phẳng lặng. Nằm giữa bốn bề rừng thiêng hoang dã, Giếng Trời là điểm trekking, cắm trại sinh tồn và chinh phục thử thách hàng đầu của giới trẻ đam mê mạo hiểm.',
    N'Xã Hòa Ninh, huyện Hòa Vang, thành phố Đà Nẵng',
    16.0125,
    107.9812,
    geography::Point(16.0125, 107.9812, 4326),
    6,
    0
),

(
    N'Khu du lịch sinh thái Suối Hoa',
    N'Khu du lịch sinh thái Suối Hoa tọa lạc tại thôn Phú Túc, xã Hòa Phú, huyện Hòa Vang, cách trung tâm Đà Nẵng khoảng 30km về phía Tây. Nơi đây được thiên nhiên kiến tạo với dòng suối hiền hòa uốn lượn quanh những thảm hoa rừng muôn sắc, các thác nước tự nhiên như Thác Rù Rì, Thác Hạ cùng những nhịp cầu treo bắc qua suối thơ mộng. Suối Hoa là điểm dã ngoại, tắm suối và nghỉ dưỡng xanh lý tưởng cho gia đình và nhóm bạn.',
    N'Thôn Phú Túc, xã Hòa Phú, huyện Hòa Vang, thành phố Đà Nẵng',
    15.9815,
    108.0315,
    geography::Point(15.9815, 108.0315, 4326),
    6,
    0
),

(
    N'Công viên 29 Tháng 3',
    N'Công viên 29 Tháng 3 được khánh thành nhân kỷ niệm ngày giải phóng thành phố Đà Nẵng (29/3/1975), tọa lạc tại vị trí trung tâm sầm uất với mặt tiền các trục đường huyết mạch Điện Biên Phủ, Nguyễn Tri Phương và Lê Duẩn. Với diện tích hơn 20ha bao gồm hồ nước trung tâm rộng lớn, hàng ngàn cây xanh cổ thụ rợp bóng mát và thảm cỏ xanh mướt, công viên được ví như "lá phổi xanh" điều hòa không khí của toàn thành phố Đà Nẵng.',
    N'Đường Điện Biên Phủ - Nguyễn Tri Phương, phường Thạc Gián, quận Thanh Khê, thành phố Đà Nẵng',
    16.0618,
    108.2045,
    geography::Point(16.0618, 108.2045, 4326),
    6,
    0
),

(
    N'Chùa Tam Bảo Đà Nẵng',
    N'Chùa Tam Bảo (Tam Bảo Tự) tọa lạc tại số 323 đường Phan Châu Trinh, quận Hải Châu, được thành lập từ năm 1953. Đây là ngôi chùa đầu tiên và là tổ đình của hệ phái Phật giáo Nam Tông (Phật giáo Nguyên thủy - Theravada) tại thành phố Đà Nẵng và toàn khu vực miền Trung. Ngôi chùa nổi bật với tòa bảo tháp xá lợi 5 tầng màu trắng vươn cao thanh thoát, mang đậm dấu ấn phong cách kiến trúc Phật giáo Đông Nam Á giao thoa Thái Lan, Campuchia và Myanmar.',
    N'323 Phan Châu Trinh, phường Bình Hiên, quận Hải Châu, thành phố Đà Nẵng',
    16.0585,
    108.2178,
    geography::Point(16.0585, 108.2178, 4326),
    9,
    0
),

(
    N'Cung Văn hóa Thiếu nhi Đà Nẵng',
    N'Cung Văn hóa Thiếu nhi Đà Nẵng tọa lạc trên đường Phan Đăng Lưu, kề cận Công viên Châu Á và Trung tâm Hội chợ Triển lãm. Công trình được thiết kế bởi công ty kiến trúc Jina Architects danh tiếng của Hàn Quốc, lấy cảm hứng từ trò chơi xếp hình trí uẩn Tangram của Nhật Bản. Với các khối hình học đa giác 3D rực rỡ sắc màu, không gian mở thông thoáng và các hình khối con thú cách điệu sinh động, nơi đây là công trình kiến trúc biểu tượng hiện đại và điểm check-in cực "chất" của giới trẻ.',
    N'02 Phan Đăng Lưu, phường Hòa Cường Bắc, quận Hải Châu, thành phố Đà Nẵng',
    16.0375,
    108.2255,
    geography::Point(16.0375, 108.2255, 4326),
    6,
    0
),

(
    N'Bún chả cá bà Lữ Đà Nẵng',
    N'Bún chả cá bà Lữ là quán bún chả cá gia truyền nổi tiếng và lâu đời bậc nhất tại thành phố Đà Nẵng, nằm trên đường Hùng Vương gần khu vực chợ Cồn. Quán có tuổi đời hơn 40 năm phục vụ thực khách món bún chả cá chuẩn vị miền Trung, nổi bật với chả cá làm từ cá thu, cá mối tươi rói đánh bắt trong ngày, nước dùng ngọt thanh ninh từ xương cá hầm cùng bí đỏ, dứa băm, cà chua và bắp cải giòn ngọt.',
    N'319 Hùng Vương, phường Vĩnh Trung, quận Hải Châu, thành phố Đà Nẵng',
    16.0688,
    108.2142,
    geography::Point(16.0688, 108.2142, 4326),
    1,
    0
),

(
    N'Bánh xèo Bà Dưỡng Đà Nẵng',
    N'Bánh xèo Bà Dưỡng nằm sâu trong một con ngõ nhỏ trên đường Hoàng Diệu, quận Hải Châu, là quán bánh xèo miền Trung nổi tiếng nhất Đà Nẵng với lịch sử hơn 30 năm. Nổi danh khắp cả nước và được nhiều tạp chí ẩm thực quốc tế vinh danh, bánh xèo tại đây có lớp vỏ vàng giòn rụm đúc từ bột gạo quê trên bếp than hồng, nhân tôm sông ngọt thịt và thịt ba chỉ béo ngậy, chấm cùng bát nước sốt đậu phộng gan heo đậm đà sánh mịn độc quyền.',
    N'K280/23 Hoàng Diệu, phường Bình Hiên, quận Hải Châu, thành phố Đà Nẵng',
    16.0598,
    108.2185,
    geography::Point(16.0598, 108.2185, 4326),
    10,
    0
),

(
    N'Cộng Cà Phê Bạch Đằng',
    N'Cộng Cà Phê nằm tại số 96-98 đường Bạch Đằng, ngay ngã tư đắc địa nhìn thẳng ra bờ sông Hàn và cầu quay Sông Hàn lộng gió. Quán mang phong cách kiến trúc thời kỳ bao cấp độc đáo với gam màu xanh bộ đội đặc trưng, bàn ghế gỗ cũ mộc mạc, rèm hoa văn con công và các vật dụng hoài niệm từ thập niên 1980. Với thức uống signature cà phê cốt dừa thơm béo nức tiếng cùng tầm nhìn ngắm cảnh sông Hàn tuyệt đẹp, đây là điểm dừng chân ưa thích của du khách quốc tế và giới trẻ.',
    N'96-98 Bạch Đằng, phường Hải Châu 1, quận Hải Châu, thành phố Đà Nẵng',
    16.0685,
    108.2245,
    geography::Point(16.0685, 108.2245, 4326),
    2,
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
-- 12. KNOWLEDGE - CẦU SÔNG HÀN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan và giá trị biểu tượng của Cầu Sông Hàn',
    N'Cầu Sông Hàn khánh thành năm 2000, là cây cầu quay đầu tiên tại Việt Nam do chính các kỹ sư và công nhân trong nước thiết kế và thi công, với sự đóng góp kinh phí to lớn của người dân Đà Nẵng. Cầu nối liền hai trục đường huyết mạch Lê Duẩn và Phạm Văn Đồng, biểu trưng cho khát vọng vươn mình mạnh mẽ và tinh thần đoàn kết của thành phố bên bờ biển Đông.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Sông Hàn';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cơ chế nhịp cầu quay độc đáo',
    N'Điểm đặc sắc nhất của Cầu Sông Hàn là phần nhịp giữa dài 122,7 mét có thể quay một góc 90 độ quanh trục thẳng đứng nằm dọc theo dòng chảy của sông. Cơ chế quay này ban đầu phục vụ cho tàu thuyền lớn lưu thông qua sông Hàn vào ban đêm. Hiện nay, hoạt động quay cầu chủ yếu phục vụ khách du lịch chiêm ngưỡng vào khung giờ cố định dịp cuối tuần.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Sông Hàn';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm ngắm cầu quay và dạo mát sông Hàn',
    N'Vào các tối thứ Bảy và Chủ nhật, Cầu Sông Hàn thường thực hiện lịch quay vào khoảng 23h00 kéo dài khoảng 30 phút. Du khách nên có mặt sớm trên tuyến đường Bạch Đằng hoặc chọn một quán cà phê ven sông có tầm nhìn thoáng đãng để ngắm trọn khoảnh khắc cây cầu chuyển động soi bóng xuống làn nước lung linh.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Sông Hàn';


-- =========================================================
-- 13. KNOWLEDGE - CẦU THUẬN PHƯỚC
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Cầu Thuận Phước',
    N'Cầu Thuận Phước là cây cầu treo dây võng dài nhất Việt Nam với tổng chiều dài 1.856 mét, bắc qua cửa biển nơi con sông Hàn đổ ra vịnh Đà Nẵng. Cầu đóng vai trò kết nối tuyến đường ven biển Nguyễn Tất Thành với đường Lê Đức Thọ dẫn lên bán đảo Sơn Trà, tạo nên mạch giao thông ven biển chiến lược của thành phố.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Thuận Phước';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc thanh thoát và hệ thống chiếu sáng',
    N'Cầu Thuận Phước sở hữu hai trụ tháp chính cao vút cùng hệ dây võng mềm mại tựa như dải lụa nối đôi bờ vịnh. Ban đêm, hệ thống đèn LED nghệ thuật hiện đại chiếu sáng rực rỡ biến cây cầu thành một điểm nhấn kiến trúc kỳ ảo soi bóng xuống mặt biển bao la.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Thuận Phước';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm ngắm hoàng hôn và gió biển vịnh Đà Nẵng',
    N'Khu vực chân Cầu Thuận Phước phía quận Hải Châu và bãi đá dưới chân cầu là nơi đón hoàng hôn tuyệt đẹp khi mặt trời lặn sau dãy núi Hải Vân xa xa. Khi di chuyển qua cầu vào buổi chiều lộng gió, du khách cần chú ý giảm tốc độ do sức gió tại khu vực cửa biển thường rất mạnh.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Thuận Phước';


-- =========================================================
-- 14. KNOWLEDGE - CẦU TRẦN THỊ LÝ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Cầu Trần Thị Lý',
    N'Cầu Trần Thị Lý được khánh thành năm 2013, thay thế cho cây cầu đường sắt De Lattre de Tassigny cổ kính thời Pháp. Cầu bắc qua sông Hàn, kết nối quận Hải Châu, Sơn Trà và Ngũ Hành Sơn, tạo thành trục giao thông đối ngoại quan trọng nối liền trung tâm với khu vực ven biển phía Nam.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Trần Thị Lý';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc hình cánh buồm vươn khơi độc đáo',
    N'Cầu mang kết cấu dây văng ba chiều độc đáo với một trụ tháp đơn nghiêng 12 độ về phía Tây cao tới 145 mét. Hệ thống dây văng tỏa ra theo hình cánh buồm căng tràn gió biển, mang thông điệp thành phố Đà Nẵng không ngừng đổi mới và hội nhập cùng thế giới.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Trần Thị Lý';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Chiêm ngưỡng Cầu Trần Thị Lý về đêm',
    N'Về đêm, Cầu Trần Thị Lý rực rỡ với hệ thống đèn nghệ thuật chuyển màu uyển chuyển từ cam, xanh, vàng sang tím. Khu vực công viên chân cầu và đường dạo bộ bờ sông là địa điểm yêu thích của người dân và du khách để hóng gió, tập thể dục và chụp những bức ảnh check-in kiến trúc ấn tượng.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu Trần Thị Lý';


-- =========================================================
-- 15. KNOWLEDGE - BÃI BIỂN NON NƯỚC
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bãi biển Non Nước',
    N'Bãi biển Non Nước trải dài khoảng 5km dọc theo cung đường Trường Sa thuộc quận Ngũ Hành Sơn. Bãi biển thoai thoải, bờ cát trắng mịn màng uốn lượn dưới chân danh thắng Ngũ Hành Sơn hùng vĩ, từng được tạp chí du lịch Forbes danh tiếng bình chọn là một trong những bãi biển hấp dẫn hàng đầu hành tinh.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Non Nước';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hoạt động nghỉ dưỡng và thể thao biển',
    N'Với làn nước trong xanh êm ả và không gian thanh bình, Bãi biển Non Nước là địa điểm lý tưởng cho các hoạt động tắm biển, lướt ván, bóng chuyền bãi biển và dù lượn. Xung quanh bãi biển tập trung nhiều khu nghỉ dưỡng cao cấp đạt chuẩn quốc tế cùng hệ thống nhà hàng hải sản tươi ngon.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Non Nước';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm kết hợp tham quan Non Nước',
    N'Du khách có thể dễ dàng kết hợp tham quan quần thể Ngũ Hành Sơn và làng đá mỹ nghệ Non Nước vào buổi sáng, sau đó dừng chân tắm biển và ngắm hoàng hôn tại Bãi biển Non Nước vào buổi chiều để có một hành trình trọn vẹn và thư thái.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Non Nước';


-- =========================================================
-- 16. KNOWLEDGE - RẠN NAM Ô
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Rạn Nam Ô',
    N'Rạn Nam Ô là dải đá ngầm tự nhiên dài hàng trăm mét nằm sát bờ biển phường Hòa Hiệp Nam, quận Liên Chiểu, cách trung tâm Đà Nẵng khoảng 17km về phía Bắc. Nơi đây gồm nhiều khối đá nhấp nhô đủ hình thù ôm lấy bờ cát thoải, giữ trọn nét hoang sơ mộc mạc của một vùng biển duyên hải miền Trung.',
    N'TravelWise'
FROM places
WHERE name = N'Rạn Nam Ô';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Mùa rêu xanh kỳ ảo trên rạn đá',
    N'Vào mỗi dịp đầu xuân sau Tết Nguyên đán (khoảng tháng Giêng đến tháng Ba âm lịch), các tảng đá ngầm tại Rạn Nam Ô được phủ kín bởi một lớp rêu nhung xanh ngát. Khi thủy triều rút xuống lúc bình minh, ánh nắng sớm phản chiếu mặt nước đọng lại trên phiến đá tạo nên khung cảnh thiên nhiên thơ mộng kỳ diệu.',
    N'TravelWise'
FROM places
WHERE name = N'Rạn Nam Ô';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Đặc sản gỏi cá và nước mắm Nam Ô truyền thống',
    N'Bên cạnh thắng cảnh rạn đá, Nam Ô nổi tiếng khắp cả nước với nghề làm nước mắm cá cơm than truyền thống và món gỏi cá Nam Ô trứ danh. Gỏi cá được chế biến từ cá trích tươi sống đánh bắt trong ngày ăn kèm nước chấm mè đậu phộng béo ngậy và đọt lá rừng tự nhiên trên đèo Hải Vân.',
    N'TravelWise'
FROM places
WHERE name = N'Rạn Nam Ô';


-- =========================================================
-- 17. KNOWLEDGE - GHỀNH BÀNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Ghềnh Bàng Sơn Trà',
    N'Ghềnh Bàng nằm trên bán đảo Sơn Trà, cách trung tâm thành phố khoảng 20km. Nơi đây sở hữu đường bờ biển dài 2km với vô số mỏm đá nhấp nhô đen bóng vươn ra biển lớn. Đây là điểm du lịch sinh thái hoang dã còn nguyên vẹn nét đẹp tự nhiên, chưa bị thương mại hóa nhiều.',
    N'TravelWise'
FROM places
WHERE name = N'Ghềnh Bàng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm lặn ngắm san hô và dã ngoại tự túc',
    N'Làn nước biển tại Ghềnh Bàng trong vắt quanh năm, du khách chỉ cần kính lặn thông thường là có thể chiêm ngưỡng những dải san hô tự nhiên đa màu sắc cùng các đàn cá biển bơi lội. Khu vực ven ghềnh đá bằng phẳng rất thích hợp để nhóm bạn dựng lều dã ngoại, cắm trại và câu cá biển.',
    N'TravelWise'
FROM places
WHERE name = N'Ghềnh Bàng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cẩm nang an toàn khi trekking Ghềnh Bàng',
    N'Để xuống được bãi biển Ghềnh Bàng, du khách phải đi bộ một đoạn đường mòn xuyên rừng dốc đá dài khoảng 1km. Cần trang bị giày thể thao ma sát tốt, chuẩn bị đủ nước uống và đồ ăn nhẹ. Đặc biệt chú ý cẩn thận đá trơn trượt có vỏ hà bám sắc nhọn và tuyệt đối không xả rác bừa bãi ra môi trường biển.',
    N'TravelWise'
FROM places
WHERE name = N'Ghềnh Bàng';


-- =========================================================
-- 18. KNOWLEDGE - ĐỈNH BÀN CỜ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Đỉnh Bàn Cờ',
    N'Đỉnh Bàn Cờ tọa lạc tại độ cao gần 700 mét so với mực nước biển trên đỉnh núi Sơn Trà. Nơi đây nổi tiếng với bức tượng tiên ông Đế Thích ngồi trầm ngâm trước bàn cờ đá dang dở giữa biển mây bồng bềnh, gắn liền với huyền tích các vị tiên hạ giới đọ cờ ngắm cảnh.',
    N'TravelWise'
FROM places
WHERE name = N'Đỉnh Bàn Cờ';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tầm nhìn toàn cảnh ngoạn mục bao trọn Đà Nẵng',
    N'Đứng tại Đỉnh Bàn Cờ vào những ngày thời tiết trong trẻo, du khách có thể phóng tầm mắt quan sát toàn cảnh vòng cung vịnh Đà Nẵng, những cây cầu bắc qua sông Hàn, bãi biển Mỹ Khê trải dài và dãy Hải Vân quan hùng vĩ. Khoảnh khắc sáng sớm đón bình minh hay ráng chiều tà từ đỉnh núi mang lại cảm giác khoáng đạt vô song.',
    N'TravelWise'
FROM places
WHERE name = N'Đỉnh Bàn Cờ';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lưu ý khi di chuyển lên Đỉnh Bàn Cờ',
    N'Tuyến đường lên Đỉnh Bàn Cờ có nhiều khúc cua dốc cao và quanh co. Theo quy định địa phương nhằm đảm bảo an toàn giao thông, du khách không được sử dụng xe máy tay ga để lên bán đảo Sơn Trà. Nên chọn xe số, xe côn tay có phanh đảm bảo hoặc thuê xe ô tô trung chuyển, đồng thời kiểm tra dự báo sương mù trước khi khởi hành.',
    N'TravelWise'
FROM places
WHERE name = N'Đỉnh Bàn Cờ';


-- =========================================================
-- 19. KNOWLEDGE - CHÙA QUAN THẾ ÂM
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Chùa Quán Thế Âm Ngũ Hành Sơn',
    N'Chùa Quán Thế Âm nằm dưới chân ngọn núi Kim Sơn thuộc danh thắng Ngũ Hành Sơn, được cố Hòa thượng Thích Pháp Nhãn khai sơn vào năm 1957 sau một giấc chiêm bao thấy Bồ Tát hiển linh nơi động đá. Chùa là một trong những trung tâm Phật giáo trọng điểm và chốn tùng lâm thanh tịnh bậc nhất tại Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Quan Thế Âm';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Động Quan Âm huyền bí và Bảo tàng Phật giáo',
    N'Phía sau khuôn viên chùa là Động Quan Âm tự nhiên dài gần 50 mét với vô số thạch nhũ lung linh, nổi bật là bức tượng Bồ Tát Quán Thế Âm bằng thạch nhũ tự nhiên cao gần 2 mét. Trong khuôn viên chùa còn có Bảo tàng Văn hóa Phật giáo đầu tiên tại Việt Nam, nơi trưng bày hàng trăm cổ vật tượng Phật, pháp khí và tranh thêu cổ quý hiếm.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Quan Thế Âm';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lễ hội Quán Thế Âm - Di sản văn hóa phi vật thể',
    N'Lễ hội Quán Thế Âm được tổ chức định kỳ vào ngày 19 tháng 2 âm lịch hàng năm tại chùa, đã được công nhận là Di sản văn hóa phi vật thể quốc gia. Lễ hội thu hút hàng vạn tăng ni, Phật tử và du khách thập phương tham gia các nghi thức rước tượng Quan Âm, lễ cầu quốc thái dân an, thả hoa đăng và các trò chơi dân gian truyền thống.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Quan Thế Âm';


-- =========================================================
-- 20. KNOWLEDGE - NHÀ THỜ CHÍNH TÒA ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Nhà thờ Chính tòa Đà Nẵng (Nhà thờ Con Gà)',
    N'Nhà thờ Chính tòa Đà Nẵng tọa lạc tại số 156 đường Trần Phú, do linh mục Vallet khởi công xây dựng vào tháng 2 năm 1923 thời Pháp thuộc. Đây là nhà thờ Công giáo duy nhất được xây dựng tại thành phố Đà Nẵng dưới thời kỳ thuộc địa Pháp, còn được người dân địa phương gọi thân mật là Nhà thờ Con Gà.',
    N'TravelWise'
FROM places
WHERE name = N'Nhà thờ Chính tòa Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc Gothic cổ điển và màu hồng đặc trưng',
    N'Nhà thờ cao gần 70 mét, mang đậm phong cách kiến trúc Gothic phương Tây với vòm cửa nhọn, các ô cửa sổ lắp kính màu mô tả các tích sự trong Kinh Thánh và lớp sơn ngoại thất màu hồng pastel ấm áp nổi bật. Trên đỉnh tháp chuông gắn biểu tượng con gà bằng đồng quay theo hướng gió, mang ý nghĩa nhắc nhở sự thức tỉnh và ăn năn trong giáo lý Kitô giáo.',
    N'TravelWise'
FROM places
WHERE name = N'Nhà thờ Chính tòa Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm tham quan và tham dự thánh lễ',
    N'Nhà thờ mở cửa tự do cho du khách tham quan khuôn viên và chụp ảnh vào ban ngày. Nếu muốn vào bên trong giáo đường chiêm bái hoặc dự thánh lễ, du khách cần lưu ý mặc trang phục lịch sự, giữ trật tự trang nghiêm và kiểm tra lịch lễ ngày Chúa nhật để không làm ảnh hưởng đến cộng đoàn phụng vụ.',
    N'TravelWise'
FROM places
WHERE name = N'Nhà thờ Chính tòa Đà Nẵng';


-- =========================================================
-- 21. KNOWLEDGE - CHÙA TAM THAI
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Quốc tự Tam Thai',
    N'Chùa Tam Thai nằm trên sườn phía tây của ngọn Thủy Sơn thuộc quần thể Ngũ Hành Sơn, được khởi dựng vào khoảng thế kỷ 17 dưới thời Hậu Lê. Năm 1825, vua Minh Mạng vi hành đến ngọn núi này và đã cho đại trùng tu ngôi chùa, đồng thời ban biển sắc tứ "Quốc Tự Tam Thai", phong làm ngôi quốc tự linh thiêng của triều Nguyễn.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Tam Thai';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc cổ tự và cảnh quan thung lũng đá',
    N'Chùa Tam Thai được xây dựng theo kiểu chữ Vương (王) gồm ba tầng tam giác cân hài hòa với triền núi. Du khách bước qua cổng tam quan rêu phong cổ kính bằng gạch cổ vồ sẽ bước vào sân chùa rợp bóng cây cổ thụ. Chính điện thờ Phật Di Lặc và Tam Thế Phật uy nghiêm, bên cạnh là tháp xá lợi và Huyền Không lữ quán tĩnh mịch.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Tam Thai';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hành hương chiêm bái và kết hợp tham quan Thủy Sơn',
    N'Để lên chùa Tam Thai, du khách leo 156 bậc đá theo lối cổng phía Tây hoặc sử dụng thang máy kính lên đài Vọng Giang Đài rồi đi bộ sang. Từ chùa Tam Thai, du khách có thể tiếp tục men theo các lối mòn đá rêu phong để khám phá động Huyền Không, động Tàng Chơn và chùa Linh Ứng Ngũ Hành Sơn.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Tam Thai';


-- =========================================================
-- 22. KNOWLEDGE - BẢO TÀNG ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bảo tàng Đà Nẵng và Di tích Thành Điện Hải',
    N'Bảo tàng Đà Nẵng được thành lập nhằm bảo tồn và phát huy các giá trị lịch sử văn hóa vùng đất xứ Quảng. Bảo tàng tọa lạc trong khuôn viên Di tích Quốc gia đặc biệt Thành Điện Hải - tòa thành phòng ngự quân sự kiên cố bằng gạch vồ được xây dựng từ thời Gia Long và Minh Mạng để trấn giữ cửa biển Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Dấu tích lịch sử kháng chiến hào hùng năm 1858',
    N'Thành Điện Hải là nơi danh tướng Nguyễn Tri Phương cùng quân dân Đà Nẵng đã kiên cường nổ phát súng đầu tiên kháng chiến chống liên quân Pháp - Tây Ban Nha vào năm 1858. Trong khuôn viên bảo tàng hiện vẫn bảo tồn hệ thống tường thành hình cánh hoa khế theo phong cách Vauban cổ, hào nước và hàng chục khẩu thần công bằng đồng còn nguyên vẹn.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian trưng bày tư liệu đa dạng',
    N'Bảo tàng chia thành ba tầng trưng bày hiện đại với hơn 2.500 tài liệu, hiện vật và hình ảnh quý giá về lịch sử tự nhiên, xã hội, các làng nghề truyền thống và tinh thần đấu tranh cách mạng bất khuất của nhân dân Đà Nẵng qua hai cuộc kháng chiến chống Pháp và chống Mỹ.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Đà Nẵng';


-- =========================================================
-- 23. KNOWLEDGE - BẢO TÀNG MỸ THUẬT ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bảo tàng Mỹ thuật Đà Nẵng',
    N'Bảo tàng Mỹ thuật Đà Nẵng tọa lạc tại số 78 Lê Duẩn, quận Hải Châu, là bảo tàng mỹ thuật công lập thứ ba tại Việt Nam (sau Hà Nội và TP. Hồ Chí Minh) và là thiết chế mỹ thuật tiêu biểu duy nhất của dải đất miền Trung - Tây Nguyên, khánh thành vào cuối năm 2016.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Mỹ thuật Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Bộ sưu tập tác phẩm nghệ thuật đặc sắc',
    N'Bảo tàng hiện lưu giữ hơn 1.000 tác phẩm mỹ thuật hiện đại, cận đại và mỹ thuật dân gian truyền thống. Các hiện vật phong phú về chất liệu như tranh sơn dầu, sơn mài, lụa, đồ họa in khắc, điêu khắc đá và gỗ, phản ánh đời sống tâm hồn, phong cảnh và con người miền Trung qua góc nhìn sáng tạo của nhiều thế hệ họa sĩ danh tiếng.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Mỹ thuật Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm không gian văn hóa nghệ thuật thị giác',
    N'Không gian bảo tàng ba tầng được thiết kế trang nhã, hệ thống chiếu sáng tiêu chuẩn nghệ thuật cao. Nơi đây thường xuyên tổ chức các buổi triển lãm chuyên đề, tọa đàm nghệ thuật và các hoạt động trải nghiệm in tranh dân gian, là điểm đến lý tưởng cho những người yêu cái đẹp và say mê hội họa.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Mỹ thuật Đà Nẵng';


-- =========================================================
-- 24. KNOWLEDGE - BẢO TÀNG TRANH 3D ART IN PARADISE
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bảo tàng Tranh 3D Art in Paradise',
    N'Art in Paradise Đà Nẵng là bảo tàng nghệ thuật tranh 3D quy mô lớn hàng đầu tại Việt Nam, tọa lạc tại phường Thọ Quang, quận Sơn Trà. Với diện tích sàn hơn 4.000m², bảo tàng sở hữu hàng trăm tác phẩm tranh tường 3D sống động do các họa sĩ chuyên nghiệp từ Hàn Quốc kỳ công thực hiện.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Tranh 3D Art in Paradise';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Các phân khu chủ đề tương tác ảo ảnh thị giác',
    N'Bảo tàng được phân chia thành 9 khu vực chủ đề riêng biệt: Ảo ảnh (Optical), Cổ điển (Classic), Đại dương (Aqua), Động vật hoang dã (Safari), Thế giới thần tiên (Fantasy) và Ai Cập cổ đại. Các tác phẩm ứng dụng kỹ thuật phối cảnh ba chiều khéo léo biến không gian phẳng thành thế giới nổi đa chiều sinh động.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Tranh 3D Art in Paradise';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Bí quyết chụp ảnh và check-in sống động',
    N'Tại mỗi bức tranh đều có đánh dấu vị trí đứng chụp chuẩn (Photo Point) để có góc nhìn 3D hoàn hảo nhất. Du khách nên đi cùng bạn bè hoặc người thân để hỗ trợ chụp ảnh và đừng ngần ngại tương tác biểu cảm hài hước, nhập vai thành nhân vật trong tranh để có những bức ảnh độc nhất vô nhị.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Tranh 3D Art in Paradise';


-- =========================================================
-- 25. KNOWLEDGE - CHỢ CỒN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Chợ Cồn - Thiên đường ẩm thực Đà Nẵng',
    N'Chợ Cồn (tên chính thức là Trung tâm Thương nghiệp Đà Nẵng) nằm ngay ngã tư đường Hùng Vương và Ông Ích Khiêm, được thành lập từ những năm 1940. Đây là khu chợ bán buôn và bán lẻ sầm uất bậc nhất miền Trung, nổi danh là biểu tượng văn hóa ẩm thực đường phố của thành phố Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ Cồn';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thiên đường món ngon đặc sản xứ Quảng',
    N'Khu ẩm thực trong nhà và phố ăn vặt ngoài trời tại Chợ Cồn quy tụ hàng trăm quầy hàng san sát nhau. Tại đây du khách có thể thưởng thức đủ món đặc sản chuẩn vị địa phương với mức giá bình dân như: mì Quảng, bún mắm nêm, bánh bèo chén, bánh bột lọc, ram cuốn cải, ốc hút nước dừa và chè xoa xoa hạt lựu thanh mát.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ Cồn';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm mua sắm quà đặc sản tại Chợ Cồn',
    N'Chợ Cồn mở cửa từ sáng sớm đến chiều tối (khu ẩm thực hoạt động sôi nổi nhất từ 15h00 đến 19h00). Khu vực tầng lửng và phía sau chợ chuyên bán các mặt hàng hải sản khô như mực một nắng, cá bò rim, chả bò Đà Nẵng và tré gia truyền, du khách nên tham khảo giá ở vài sạp và hỏi kỹ về hạn sử dụng.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ Cồn';


-- =========================================================
-- 26. KNOWLEDGE - CHỢ ĐÊM SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Chợ đêm Sơn Trà',
    N'Chợ đêm Sơn Trà nằm tại đoạn giao giữa đường Mai Hắc Đế và Lý Nam Đế, ngay sát đầu Cầu Rồng và Cầu Tình Yêu. Chợ hoạt động từ 18h00 đến nửa đêm hàng ngày, là điểm hẹn về đêm thu hút đông đảo du khách trong nước và quốc tế trải nghiệm không khí náo nhiệt của Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đêm Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Ẩm thực hải sản nướng và đặc sản đêm',
    N'Chợ đêm sở hữu hơn 150 gian hàng bày bán phong phú các loại hải sản tươi sống được chế biến nướng mỡ hành, sốt me tại chỗ như tôm hùm baby, hàu nướng phô mai, mực một nắng, bạch tuộc sa tế cùng các món đồ ăn vặt xiên que, trà trái cây và sinh tố nhiệt đới mát lạnh.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đêm Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Mua sắm đồ lưu niệm và kết hợp xem Cầu Rồng phun lửa',
    N'Bên cạnh ẩm thực, chợ còn có nhiều gian hàng quà lưu niệm như túi xách cói, nón lá trang trí, đồ thủ công mỹ nghệ đá Non Nước và quần áo đi biển. Vào tối thứ Bảy và Chủ nhật, du khách có thể ăn uống dạo chợ rồi bước sang đầu Cầu Rồng lúc 21h00 để ngắm màn trình diễn phun lửa và phun nước độc đáo.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đêm Sơn Trà';


-- =========================================================
-- 27. KNOWLEDGE - CHỢ ĐÊM HELIO
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Chợ đêm Helio',
    N'Chợ đêm Helio tọa lạc trên đường 2 Tháng 9, thuộc tổ hợp giải trí đa thế hệ Helio Center. Đây là một trong những chợ đêm quy mô lớn và được đầu tư bài bản nhất tại Đà Nẵng, nổi bật với không gian ngoài trời rộng rãi, thiết kế trẻ trung lung linh ánh đèn và phong cách phục vụ văn minh.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đêm Helio';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thiên đường ẩm thực đa dạng và không gian âm nhạc sống',
    N'Chợ đêm Helio quy tụ hàng trăm món ăn đường phố từ món ăn truyền thống Việt Nam đến các món ăn vặt Thái Lan, Hàn Quốc và Nhật Bản. Khu bia thủ công và nướng BBQ luôn tấp nập khách. Điểm đặc sắc là sân khấu ca nhạc ngoài trời Mechazone biểu diễn nhạc acoustic và nhạc sống sôi động hoàn toàn miễn phí mỗi đêm.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đêm Helio';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm vui chơi trọn vẹn tại Helio',
    N'Chợ đêm bắt đầu nhộn nhịp từ 17h30 đến 22h30 hàng ngày. Du khách có thể kết hợp vui chơi trong khu tổ hợp Helio Kids hoặc trung tâm game thùng hiện đại trước khi ra sân ngoài trời thưởng thức ẩm thực đêm và chụp ảnh check-in tại các cụm tiểu cảnh được đổi mới theo mùa lễ hội.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đêm Helio';


-- =========================================================
-- 28. KNOWLEDGE - CÔNG VIÊN CHÂU Á (ASIA PARK)
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Công viên Châu Á (Asia Park)',
    N'Asia Park (Da Nang Downtown) do Tập đoàn Sun Group đầu tư, nằm bên bờ Tây sông Hàn thuộc quận Hải Châu. Công viên trải rộng trên diện tích hơn 800.000m², tái hiện vẻ đẹp văn hóa, lịch sử và kiến trúc tiêu biểu của 10 quốc gia châu Á như Nhật Bản, Hàn Quốc, Trung Quốc, Ấn Độ, Thái Lan và Việt Nam.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên Châu Á (Asia Park)';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Vòng quay Mặt Trời Sun Wheel 115 mét',
    N'Biểu tượng nổi bật nhất của Asia Park là Vòng quay Mặt Trời Sun Wheel cao 115 mét, nằm trong top những vòng quay quan sát cao nhất thế giới. Với 64 cabin hiện đại, trong một lượt quay kéo dài 15 phút, Sun Wheel mang đến cho du khách trải nghiệm ngắm nhìn toàn cảnh thành phố Đà Nẵng rực rỡ muôn ngàn ánh đèn đêm từ trên cao.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên Châu Á (Asia Park)';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trò chơi cảm giác mạnh và không gian lễ hội',
    N'Công viên sở hữu hệ thống trò chơi mạo hiểm tiêu chuẩn quốc tế như tàu lượn siêu tốc Queen Cobra dạng treo lớn nhất Việt Nam, tháp rơi tự do Golden Sky Tower và tàu hỏa Monorail trên cao. Công viên mở cửa tự do vào khuôn viên dạo chơi và thưởng thức ẩm thực, du khách chỉ cần mua vé khi tham gia các trò chơi.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên Châu Á (Asia Park)';


-- =========================================================
-- 29. KNOWLEDGE - KHU DU LỊCH SUỐI KHOÁNG NÓNG NÚI THẦN TÀI
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Suối Khoáng Nóng Núi Thần Tài',
    N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài tọa lạc tại khu bảo tồn thiên nhiên Bà Nà Núi Chúa, xã Hòa Phú, huyện Hòa Vang, cách trung tâm thành phố khoảng 30km. Nơi đây sở hữu mỏ khoáng nóng tự nhiên phát lộ từ lòng mạch ngầm núi đá, hòa quyện giữa khí hậu bốn mùa mát lành của rừng nguyên sinh nhiệt đới.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm tắm khoáng Onsen và luộc trứng trường thọ',
    N'Núi Thần Tài là khu nghỉ dưỡng đầu tiên tại Việt Nam phát triển mô hình tắm khoáng nóng Onsen theo tiêu chuẩn khắt khe của Nhật Bản, giúp tái tạo năng lượng và chăm sóc sức khỏe. Hoạt động thú vị không thể bỏ qua là tự tay luộc trứng gà trong dòng suối khoáng nóng tự nhiên 75 độ C để thưởng thức món trứng trường thọ bổ dưỡng.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Công viên nước trên núi và hệ thống giải trí phong phú',
    N'Bên cạnh dịch vụ tắm khoáng, bùn khoáng và trà xanh, khu du lịch còn có công viên nước trên sườn núi độc đáo với hồ tạo sóng nhân tạo rộng lớn, dòng sông lười uốn lượn dưới tán rừng, máng trượt cầu vồng mạo hiểm và công viên khủng long kỷ Jura sinh động dành cho các gia đình có trẻ nhỏ.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài';


-- =========================================================
-- 30. KNOWLEDGE - LÀNG ĐÁ MỸ NGHỆ NON NƯỚC
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Làng đá mỹ nghệ Non Nước hơn 400 năm tuổi',
    N'Làng đá mỹ nghệ Non Nước hình thành từ cuối thế kỷ 17 dưới chân núi Ngũ Hành Sơn, do nghệ nhân Huỳnh Bá Quát người Thanh Hóa khởi dựng. Trải qua hơn 400 năm kế thừa và phát triển, làng nghề đã được Bộ Văn hóa, Thể thao và Du lịch công nhận là Di sản văn hóa phi vật thể quốc gia.',
    N'TravelWise'
FROM places
WHERE name = N'Làng đá mỹ nghệ Non Nước';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Nghệ thuật điêu khắc đá cẩm thạch thủ công tinh xảo',
    N'Dưới bàn tay tài hoa của các nghệ nhân Non Nước, những khối đá cẩm thạch thô cứng được đục đẽo tỉ mỉ thành các bức tượng Phật từ bi, các linh vật thần thú dũng mãnh, các bức tượng danh nhân nghệ thuật và đồ trang sức vòng đá phong thủy tinh xảo, nổi tiếng khắp các thị trường quốc tế.',
    N'TravelWise'
FROM places
WHERE name = N'Làng đá mỹ nghệ Non Nước';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm chọn mua quà lưu niệm đá mỹ nghệ',
    N'Khi tham quan các xưởng điêu khắc dọc đường Huyền Trân Công Chúa, du khách có thể tận mắt chứng kiến công đoạn tạc tượng của thợ đá. Để làm quà tặng nhỏ gọn, du khách có thể chọn vòng tay đá phong thủy, mặt dây chuyền ngọc hoặc tượng để bàn mini; nên hỏi rõ người bán về chất liệu đá tự nhiên và cách bảo quản.',
    N'TravelWise'
FROM places
WHERE name = N'Làng đá mỹ nghệ Non Nước';


-- =========================================================
-- 31. KNOWLEDGE - HỒ XANH SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Hồ Xanh bán đảo Sơn Trà',
    N'Hồ Xanh (hay còn gọi là Hồ Bãi Bụt) nằm ven cung đường biển Hoàng Sa trên bán đảo Sơn Trà, cách cầu Rồng khoảng 10km. Hồ được hình thành từ quá trình khai thác đá trước đây, qua thời gian được thiên nhiên bù đắp nước suối trong lành tạo nên một hồ nước ngọt tĩnh lặng giữa lòng thung lũng đá.',
    N'TravelWise'
FROM places
WHERE name = N'Hồ Xanh Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Mặt hồ xanh ngọc bích và điểm check-in chụp ảnh lý tưởng',
    N'Hồ Xanh gây ấn tượng với màu nước xanh ngắt như ngọc bích phẳng lặng in bóng vách núi đá dựng đứng và những tán cây rủ bóng. Nơi đây là điểm đến chụp ảnh cưới, chụp ảnh dã ngoại nổi tiếng bậc nhất Đà Nẵng, đặc biệt vào mùa cỏ may rực rỡ tạo nên khung cảnh lãng mạn nên thơ.',
    N'TravelWise'
FROM places
WHERE name = N'Hồ Xanh Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lưu ý an toàn khi dã ngoại tại Hồ Xanh',
    N'Hồ Xanh có độ sâu lớn và vách đá dốc đứng nên khu vực này nghiêm cấm việc tắm hồ hoặc bơi lội tự do nhằm đảm bảo an toàn tính mạng. Du khách khi đến dã ngoại, chụp ảnh cần đứng ở các mỏm đất an toàn trên bờ, chú ý giữ gìn vệ sinh chung và không xả rác xuống lòng hồ.',
    N'TravelWise'
FROM places
WHERE name = N'Hồ Xanh Sơn Trà';


-- =========================================================
-- 32. KNOWLEDGE - CÂY ĐA NGÀN NĂM SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Cây đa ngàn năm Sơn Trà',
    N'Cây đa ngàn năm nằm ở rìa phía đông bắc bán đảo Sơn Trà, được các nhà khoa học phát hiện vào năm 1771 và được công nhận là Cây Di sản Việt Nam vào năm 2014. Với tuổi đời hơn 8 thế kỷ, cây sừng sững giữa tán rừng nguyên sinh như một chứng nhân lịch sử của vùng đất Đà Nẵng. Hệ thống rễ phụ chằng chịt buông từ cành cao cắm chặt vào nền đá núi tạo nên vẻ đẹp kỳ bí và uy nghiêm.',
    N'TravelWise'
FROM places
WHERE name = N'Cây đa ngàn năm Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hệ sinh thái và cảnh quan rừng nguyên sinh Sơn Trà',
    N'Khu vực quanh cây đa ngàn năm sở hữu thảm thực vật phong phú và là sinh cảnh cư trú của nhiều loài động vật quý hiếm, đặc biệt là loài voọc chà vá chân nâu - "nữ hoàng linh trưởng" đặc hữu của bán đảo Sơn Trà. Du khách khi ghé thăm có cơ hội tận hưởng bầu không khí trong lành, lắng nghe tiếng chim hót và nếu may mắn sẽ được quan sát các đàn voọc chuyền cành kiếm ăn.',
    N'TravelWise'
FROM places
WHERE name = N'Cây đa ngàn năm Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm di chuyển và lưu ý an toàn tham quan',
    N'Tuyến đường từ ngã ba bãi Bắc đến cây đa ngàn năm có độ dốc cao và quanh co men theo triền núi nhìn ra biển. Để đảm bảo an toàn, du khách bắt buộc phải sử dụng xe số, xe côn tay hoặc xe ô tô trung chuyển theo quy định của ban quản lý. Du khách không được khắc chữ lên thân cây, không bẻ cành bứt lá và mang theo rác thải cá nhân về điểm tập kết.',
    N'TravelWise'
FROM places
WHERE name = N'Cây đa ngàn năm Sơn Trà';


-- =========================================================
-- 33. KNOWLEDGE - MŨI NGHÊ SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Mũi Nghê - Điểm đón bình minh sớm nhất Đà Nẵng',
    N'Mũi Nghê là điểm nhô ra xa nhất về phía biển Đông của bán đảo Sơn Trà. Do vị trí địa lý đắc địa ở cực đông, nơi đây là tọa độ đầu tiên đón ánh rạng đông mỗi sớm mai trên vùng biển Đà Nẵng. Mỏm đá bazan bị sóng biển bào mòn hàng triệu năm tạo nên hình tượng con nghê kiêu hãnh hướng ra đại dương, che chắn sóng gió cho ngư dân các làng chài ven biển.',
    N'TravelWise'
FROM places
WHERE name = N'Mũi Nghê Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hồ bơi tự nhiên và trải nghiệm lặn biển hoang sơ',
    N'Điểm nhấn kỳ thú nhất tại Mũi Nghê là một vùng nước biển trũng nằm lọt thỏm giữa các vách đá bao quanh, được ví như một "hồ bơi tự nhiên vô cực". Nước biển tại đây trong vắt đến mức có thể nhìn thấu tận đáy cát và những nhánh san hô sặc sỡ. Du khách đến đây thường tắm mát trong hồ đá, câu cá biển và lặn ngắm san hô bằng ống thở tự túc.',
    N'TravelWise'
FROM places
WHERE name = N'Mũi Nghê Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cẩm nang trekking và chinh phục Mũi Nghê',
    N'Hành trình trekking đến Mũi Nghê đòi hỏi thể lực khá tốt vì phải vượt qua đường mòn dốc đứng xuyên rừng khoảng 45 phút. Du khách nên đi cùng người có kinh nghiệm bản địa, mang giày leo núi chống trượt, mặc áo phao khi xuống nước và theo dõi sát lịch thủy triều. Không nên đến đây vào những ngày biển động hoặc có sóng lớn vì các đợt sóng va đập vào vách đá rất nguy hiểm.',
    N'TravelWise'
FROM places
WHERE name = N'Mũi Nghê Sơn Trà';


-- =========================================================
-- 34. KNOWLEDGE - BÃI RẠNG SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan vẻ đẹp tự nhiên của Bãi Rạng',
    N'Bãi Rạng nằm nép mình bên sườn đồi thoai thoải của bán đảo Sơn Trà, tách biệt khỏi sự nhộn nhịp của các bãi biển trung tâm. Bờ biển tại đây có sự giao thoa hài hòa giữa dải cát vàng mịn, những ghềnh đá nhiều hình thù và sóng biển rì rào vỗ bờ. Nước biển Bãi Rạng rất xanh và trong, tạo nên khung cảnh nguyên sơ lý tưởng cho các buổi nghỉ ngơi thư giãn cuối tuần.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Rạng Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hoạt động tắm biển, lướt mô tô nước và lặn ngắm san hô',
    N'Tại Bãi Rạng, du khách có thể thỏa thích đắm mình trong làn nước biển mát lạnh, tham gia các trò chơi thể thao mạo hiểm như lướt mô tô nước (jetski), chèo thuyền kayak hoặc đăng ký tour ca nô lặn ngắm các rạn san hô phong phú ngoài khơi. Buổi chiều tà cũng là lúc thủy triều rút để lộ những vũng nước đọng quanh bãi đá với nhiều loại ốc biển và cá nhỏ bơi lội sinh động.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Rạng Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Ẩm thực chòi lá ven biển và kinh nghiệm dã ngoại',
    N'Dọc bờ Bãi Rạng có các dãy chòi gỗ lợp lá cọ phục vụ du khách nghỉ ngơi và ăn uống. Tại đây phục vụ phong phú các món hải sản vừa đánh bắt từ biển như ghẹ hấp sả, tôm nướng muối ớt, mực một nắng nướng sa tế và cá nướng than hoa. Du khách nên thỏa thuận giá thuê chòi và giá hải sản trước khi sử dụng để có trải nghiệm thoải mái nhất.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Rạng Sơn Trà';


-- =========================================================
-- 35. KNOWLEDGE - BÃI BỤT SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan và truyền tích dân gian Bãi Bụt',
    N'Bãi Bụt gắn liền với giai thoại thời vua Minh Mạng, khi một pho tượng Phật trôi dạt vào bãi cát và được ngư dân lập am thờ tự, từ đó biển yên sóng lặng phù hộ cho làng chài quanh năm no ấm. Nằm ở vị trí đắc địa dưới chân Chùa Linh Ứng uy nghi, Bãi Bụt mang vẻ đẹp thoát tục hòa quyện giữa non cao, đại dương mênh mông và không khí thanh tịnh của chốn thiền môn.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Bụt Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hệ sinh thái biển và trải nghiệm lặn ngắm san hô',
    N'Vùng biển Bãi Bụt là nơi bảo tồn rạn san hô đa sắc màu cùng hệ sinh thái biển nguyên vẹn của bán đảo Sơn Trà. Nước biển êm ả quanh năm nhờ được bao bọc bởi dãy núi đá vươn dài chắn gió. Du khách có thể trải nghiệm chèo thuyền SUP trên mặt nước phẳng lặng, ngắm nhìn tượng Phật Quan Âm 67m từ góc nhìn ngoài biển và lặn chiêm ngưỡng thế giới san hô dưới làn nước ngọc bích.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Bụt Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Dịch vụ dã ngoại và du lịch sinh thái tại Bãi Bụt',
    N'Khu du lịch Bãi Bụt phát triển hệ thống nhà chòi ven biển phục vụ nhu cầu nghỉ dưỡng và ẩm thực hải sản tươi sống. Sau khi viếng Chùa Linh Ứng, du khách thường di chuyển xuống Bãi Bụt để tắm biển và dùng bữa trưa. Khi vui chơi tại đây, du khách cần lưu ý giữ gìn môi trường san hô, không dẫm đạp hay bẻ gãy san hô sống.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Bụt Sơn Trà';


-- =========================================================
-- 36. KNOWLEDGE - BÃI BIỂN TIÊN SA
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bãi biển Tiên Sa huyền thoại',
    N'Tên gọi Tiên Sa bắt nguồn từ huyền thoại xưa kể rằng vẻ đẹp hoang sơ, kiều diễm của bãi biển đã thu hút các tiên nữ trên trời bay xuống dạo chơi và thưởng ngoạn phong cảnh trần gian. Bãi biển nằm khép mình trong một eo vịnh êm đềm, được các dãy núi đá Sơn Trà ôm ấp che chắn gió mùa nên mặt biển luôn phẳng lặng, tạo nên bầu không khí an yên hiếm có.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Tiên Sa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Khu nghỉ dưỡng sinh thái và hoạt động cắm trại dã ngoại',
    N'Bãi Tiên Sa hiện được quy hoạch thành khu du lịch sinh thái với hệ thống phòng nghỉ bungalow hướng biển mộc mạc và khu cắm trại ngoài trời rộng rãi. Bãi biển rất thích hợp cho các hoạt động vui chơi tập thể, team-building bãi biển, dựng lều đốt lửa trại và tổ chức tiệc nướng BBQ hải sản bên bờ biển dưới bầu trời đêm lấp lánh ánh sao.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Tiên Sa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm khám phá Bãi biển Tiên Sa',
    N'Đường đến Bãi Tiên Sa chạy thẳng theo trục đường Yết Kiêu rất bằng phẳng và thuận tiện di chuyển bằng mọi phương tiện. Du khách có thể kết hợp tham quan Cảng Tiên Sa - một trong những cảng biển nước sâu và cảng du lịch quốc tế hiện đại đón các siêu tàu du lịch quốc tế cập bến thành phố Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Tiên Sa';


-- =========================================================
-- 37. KNOWLEDGE - HẢI ĐĂNG TIÊN SA
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lịch sử hình thành ngọn hải đăng hơn 120 năm tuổi',
    N'Hải đăng Tiên Sa được người Pháp khởi công xây dựng từ cuối thế kỷ 19 và chính thức đi vào hoạt động năm 1902 nhằm dẫn đường cho các tàu thuyền lưu thông qua vùng biển duyên hải miền Trung và định hướng cập cảng Đà Nẵng. Trải qua hơn một thế kỷ thăng trầm cùng lịch sử, ngọn hải đăng vẫn bền bỉ thắp sáng mỗi đêm với tầm chiếu sáng xa tới 14 hải lý.',
    N'TravelWise'
FROM places
WHERE name = N'Hải đăng Tiên Sa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc cổ điển Pháp và góc check-in hoài niệm',
    N'Ngọn hải đăng cao 15,6m hình trụ tròn vững chãi, được phủ lớp sơn vàng ấm áp kết hợp đường viền xanh rêu cổ kính mang đặc trưng phong cách kiến trúc thuộc địa Pháp. Khuôn viên trạm hải đăng rợp bóng cây sứ cổ thụ, các bậc thang đá phủ rêu phong và hành lang vọng cảnh mở ra đại dương mênh mông, tạo nên phông nền chụp ảnh hoài niệm cực kỳ lãng mạn.',
    N'TravelWise'
FROM places
WHERE name = N'Hải đăng Tiên Sa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hướng dẫn tham quan và lưu ý đường đi',
    N'Cung đường dẫn đến Hải đăng Tiên Sa men theo sườn núi phía Bắc Sơn Trà với nhiều cảnh quan tuyệt đẹp. Du khách mua vé tham quan tượng trưng tại cổng trạm hải đăng. Cần lưu ý đi lại cẩn thận ở khu vực lan can trên cao, không leo trèo lên ngọn đèn chính và tuân thủ các hướng dẫn an toàn của các nhân viên vận hành hải đăng.',
    N'TravelWise'
FROM places
WHERE name = N'Hải đăng Tiên Sa';


-- =========================================================
-- 38. KNOWLEDGE - ĐỘNG HUYỀN KHÔNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc thiên tạo kỳ vĩ của Động Huyền Không',
    N'Động Huyền Không được ví như một thánh đường thiên nhiên kỳ vĩ dưới lòng đá vôi Thủy Sơn. Động có dạng vòm tròn mở rộng, trên đỉnh có 5 lỗ thông trời thiên nhiên được gọi là Ngũ Cổng. Vào những ngày nắng đẹp, ánh sáng mặt trời xuyên thẳng qua các lỗ thông trần tạo thành những chùm sáng huyền bí chiếu rọi xuống nền đá, biến không gian hang động trở nên lung linh thoát tục.',
    N'TravelWise'
FROM places
WHERE name = N'Động Huyền Không';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian thờ tự linh thiêng và di tích Trang Nghiêm Tự',
    N'Bước qua cổng tam quan rêu phong của động là bức tượng Bồ Tát Địa Tạng uy nghi. Ở vị trí cao nhất trên vách đá chính diện là pho tượng Phật Thích Ca ngự đài sen được tạc tỉ mỉ bằng đá sa thạch vào năm 1960. Bên phải hang động là đền thờ Trang Nghiêm Tự cổ xây từ năm 1825 thời vua Minh Mạng thờ Phật Bà Quan Âm, bên trái là đền thờ các vị thánh chúa thượng ngàn.',
    N'TravelWise'
FROM places
WHERE name = N'Động Huyền Không';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Dấu ấn lịch sử kháng chiến và cẩm nang chiêm bái',
    N'Trong hai cuộc kháng chiến chống Pháp và chống Mỹ, Động Huyền Không từng là căn cứ địa bí mật, trạm phẫu thuật thương binh và căn cứ tiền phương kiên cường của quân dân cách mạng Đà Nẵng. Du khách khi vào hang động nên giữ im lặng, ăn mặc trang phục kín đáo lịch sự và cẩn thận nền đá ẩm ướt trơn trượt.',
    N'TravelWise'
FROM places
WHERE name = N'Động Huyền Không';


-- =========================================================
-- 39. KNOWLEDGE - ĐỘNG ÂM PHỦ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan và ý nghĩa triết lý của Động Âm Phủ',
    N'Động Âm Phủ là hang động tự nhiên có lòng hang sâu hun hút và hệ thống ngóc ngách kỳ bí. Tên gọi và các cảnh trí trong động dựa trên giáo lý Phật pháp về vòng luân hồi chuyển kiếp và luật nhân quả báo ứng. Không gian động chia thành hai ngả: ngả xuống địa ngục với các hình phạt dành cho kẻ gieo nghiệp ác và ngả vươn lên thiên đường đón ánh sáng cứu rỗi.',
    N'TravelWise'
FROM places
WHERE name = N'Động Âm Phủ';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc tái hiện 18 tầng địa ngục và cầu Nại Hà',
    N'Khi bước vào cửa động, du khách sẽ đi qua cây cầu Nại Hà bắc qua dòng suối tưởng tượng, diện kiến tượng Địa Tạng Vương Bồ Tát và Phán Quan xử tội. Đi sâu vào lòng hang là 12 cửa ải tương ứng với các tầng địa ngục, mô phỏng các hình phạt như vạc dầu sôi, núi dao, biển lửa bằng hệ thống tượng đắp sinh động, âm thanh rùng rợn và ánh đèn ma mị.',
    N'TravelWise'
FROM places
WHERE name = N'Động Âm Phủ';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hành trình vươn lên cõi Thiên Thai',
    N'Trái ngược với vẻ u tịch của các tầng ngục dưới sâu, lối rẽ bên phải hang động dẫn du khách men theo các bậc đá dốc đứng để bước lên đỉnh trời Thiên Thai. Tại cửa động trên cao mở ra ánh sáng chan hòa, gió mát rượi và tầm nhìn ngắm trọn vẻ đẹp làng quê Ngũ Hành Sơn, tượng trưng cho sự hướng thiện và niềm hy vọng giải thoát.',
    N'TravelWise'
FROM places
WHERE name = N'Động Âm Phủ';


-- =========================================================
-- 40. KNOWLEDGE - CHÙA PHÁP LÂM
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan và lịch sử hình thành Chùa Pháp Lâm',
    N'Chùa Pháp Lâm khởi công xây dựng vào năm 1934 và hoàn thành năm 1936 do Hội An Nam Phật học tỉnh Quảng Nam - Đà Nẵng sáng lập với tên ban đầu là Chùa Tỉnh Hội. Đến năm 1970, chùa được đại trùng tu và đổi tên thành Pháp Lâm Tự. Ngôi chùa là chiếc nôi phong trào chấn hưng Phật giáo miền Trung và gắn liền với nhiều sự kiện lịch sử đấu tranh vì hòa bình của tăng ni Phật tử Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Pháp Lâm';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc hai tầng thanh nhã và tượng Phật bằng đồng',
    N'Chùa được xây dựng theo lối kiến trúc Phật giáo truyền thống gồm hai tầng bề thế trong khuôn viên rợp bóng cây bồ đề cổ thụ. Tầng trên là chính điện trang nghiêm bài trí pho tượng Đức Bổn Sư Thích Ca Mâu Ni bằng đồng đúc tinh xảo cao 1,1m ngự trên tòa sen. Tầng dưới là giảng đường rộng rãi phục vụ các khóa tu tập, thuyết pháp và hội nghị Phật giáo quan trọng.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Pháp Lâm';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Điểm hành hương tâm linh giữa lòng đô thị Đà Nẵng',
    N'Nằm ngay trung tâm quận Hải Châu, Chùa Pháp Lâm là điểm đến chiêm bái, cầu an quen thuộc của người dân Đà Nẵng vào các ngày rằm, mùng một và đại lễ Phật Đản, Vu Lan. Không gian trong chùa yên tĩnh, tách biệt hoàn toàn với phố xá xe cộ ồn ào bên ngoài, mang lại cảm giác an lạc và tĩnh tâm cho du khách thập phương.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Pháp Lâm';


-- =========================================================
-- 41. KNOWLEDGE - CHÙA NAM SƠN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan vẻ đẹp Chùa Nam Sơn Đà Nẵng',
    N'Chùa Nam Sơn được ví như một chốn bồng lai tiên cảnh nơi ngoại ô Đà Nẵng. Trải qua các đợt trùng tu lớn do Thượng tọa Thích Huệ Phong trụ trì, ngôi chùa mang phong cách kiến trúc đặc sắc giao thoa giữa nghệ thuật cung đình Huế cổ điển và kiến trúc Phật giáo Á Đông. Không gian chùa xanh mát với vườn thượng uyển, hồ sen, suối róc rách và những nhịp cầu gỗ thơ mộng.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Nam Sơn';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Các công trình kiến trúc nổi bật trong khuôn viên',
    N'Bước qua cổng tam quan bề thế, du khách sẽ được chiêm ngưỡng Chính Điện nguy nga bằng gỗ lim chạm trổ rồng phụng cầu kỳ. Nổi bật giữa khuôn viên là Hồ Phóng Sinh rộng lớn với lối đi bộ bằng gỗ uốn quanh mặt nước, Cầu Phong Kiều sơn màu đỏ son rực rỡ treo lồng đèn lãng mạn, Tháp Vọng Cảnh và khu Vườn Ưu Đàm nở hoa thơm ngát quanh năm.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Nam Sơn';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Quy định trang phục và kinh nghiệm vãn cảnh chùa',
    N'Chùa Nam Sơn mở cửa miễn phí đón du khách tham quan từ sáng đến chiều tối. Ban quản lý chùa có quy định rất nghiêm ngặt về trang phục: du khách bắt buộc phải mặc quần dài, áo có tay kín đáo, không mặc váy ngắn hay đồ hở hang (chùa có chuẩn bị áo choàng lam miễn phí ở cổng). Cần giữ trật tự trang nghiêm, không nói to và không chụp ảnh bên trong các khu vực thờ tự chính điện.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Nam Sơn';


-- =========================================================
-- 42. KNOWLEDGE - BẢO TÀNG ĐỒNG ĐÌNH
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian văn hóa "Khu nhà ký ức" giữa rừng Sơn Trà',
    N'Bảo tàng Đồng Đình được đặt theo tên của cây đồng đình (một loài cây họ cau mọc hoang dã rất nhiều ở bán đảo Sơn Trà). Với diện tích gần 10.000m², bảo tàng được xây dựng hài hòa với địa hình sườn dốc tự nhiên của núi đá rừng xanh mà không làm thay đổi cảnh quan môi trường, tạo nên một không gian văn hóa nghệ thuật tĩnh lặng và đượm màu hoài niệm.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Đồng Đình';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Bộ sưu tập hiện vật gốm cổ và văn hóa Sa Huỳnh',
    N'Khu trưng bày cổ vật lưu giữ hàng trăm hiện vật gốm cổ có niên đại từ vài trăm đến hàng ngàn năm, bao gồm các dòng gốm quý của nền văn hóa Sa Huỳnh, gốm Champa, gốm Chu Đậu, gốm thời Lý - Trần và gốm sứ hoa lam triều Nguyễn. Ngoài ra còn có các bộ sưu tập công cụ lao động, đồ đồng cổ phản ánh đời sống sản xuất lâu đời của cư dân miền Trung.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Đồng Đình';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc nhà rường cổ xứ Quảng và trải nghiệm tham quan',
    N'Điểm nhấn kiến trúc là ngôi nhà rường cổ truyền thống bằng gỗ mít được phục dựng nguyên vẹn từ một ngôi nhà cổ Đại Lộc (Quảng Nam), cùng các gian trưng bày mỹ thuật đương đại bằng đá và kính hiện đại. Du khách dạo bước trên những lối đi lát đá tự nhiên rợp bóng mát, lắng nghe suối reo và hòa mình vào sự kết hợp tuyệt vời giữa nghệ thuật và thiên nhiên.',
    N'TravelWise'
FROM places
WHERE name = N'Bảo tàng Đồng Đình';


-- =========================================================
-- 43. KNOWLEDGE - NHÀ TRƯNG BÀY HOÀNG SA
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Ý nghĩa lịch sử và biểu tượng Con dấu Chủ quyền',
    N'Nhà trưng bày Hoàng Sa do Ủy ban Nhân dân huyện Hoàng Sa quản lý, là công trình văn hóa và lịch sử có ý nghĩa chính trị thiêng liêng. Tòa nhà được thiết kế theo ý tưởng "Con dấu phục hồi chủ quyền", nhìn từ trên cao tựa như một con dấu vuông vắn đóng dấu vào lòng đại dương, khẳng định chủ quyền lãnh thổ thiêng liêng của Tổ quốc Việt Nam đối với quần đảo Hoàng Sa từ nhiều thế kỷ qua.',
    N'TravelWise'
FROM places
WHERE name = N'Nhà trưng bày Hoàng Sa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hệ thống tư liệu, bản đồ cổ và hiện vật quý giá',
    N'Không gian trưng bày gồm 5 chủ đề chính: Vị trí địa lý và điều kiện tự nhiên Hoàng Sa; Hoàng Sa trong thư tịch cổ Việt Nam thời phong kiến; Chứng cứ chủ quyền của Việt Nam đối với Hoàng Sa từ năm 1858 đến 1975; và Bằng chứng chủ quyền của Việt Nam từ năm 1975 đến nay. Nơi đây trưng bày các châu bản triều Nguyễn, các bản đồ cổ phương Tây và Trung Quốc đều khẳng định Hoàng Sa thuộc chủ quyền Việt Nam.',
    N'TravelWise'
FROM places
WHERE name = N'Nhà trưng bày Hoàng Sa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm công nghệ tương tác hiện đại và giáo dục truyền thống',
    N'Nhà trưng bày ứng dụng nhiều công nghệ hiện đại như màn hình cảm ứng tương tác tra cứu dữ liệu, video tư liệu 3D và sa bàn mô phỏng thực địa quần đảo Hoàng Sa. Công trình mở cửa miễn phí hàng ngày, là điểm đến giáo dục truyền thống yêu nước sâu sắc cho thế hệ trẻ và điểm dừng chân ý nghĩa đối với du khách trong và ngoài nước khi đến Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Nhà trưng bày Hoàng Sa';


-- =========================================================
-- 44. KNOWLEDGE - HẢI VÂN QUAN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lịch sử hình thành "Thiên hạ đệ nhất hùng quan"',
    N'Năm 1826, vua Minh Mạng ban lệnh xây dựng cụm công trình phòng thủ kiên cố gồm cổng thành, tường đá thành lũy và nhà trú quân trên đỉnh đèo Hải Vân. Cổng hướng về phía kinh đô Huế khắc ba chữ Hán "Hải Vân Quan", còn cổng hướng về Quảng Nam - Đà Nẵng khắc sáu chữ "Thiên hạ đệ nhất hùng quan". Đây là yết hầu giao thông và là tiền đồn phòng thủ quân sự chiến lược của vương triều Nguyễn.',
    N'TravelWise'
FROM places
WHERE name = N'Hải Vân Quan';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc cổng thành cổ và tường thành đá vôi',
    N'Cửa ải Hải Vân Quan được xây bằng gạch vồ và đá núi kiên cố với mái vòm cuốn bán nguyệt đặc trưng thời Nguyễn. Di tích bao gồm hệ thống cổng thành Đông, cổng Tây, tường thành lũy bao quanh, pháo đài ngắm bắn thần công và dấu tích các lô cốt thời chiến tranh hiện đại. Đứng trên vọng lâu cửa ải, du khách có thể ngắm nhìn toàn cảnh dãy núi Trường Sơn hùng vĩ, vịnh Lăng Cô và vịnh Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Hải Vân Quan';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm tham quan di tích sau đại trùng tu',
    N'Sau dự án hợp tác bảo tồn và trùng tu quy mô lớn giữa Đà Nẵng và Thừa Thiên Huế hoàn thành năm 2024, Hải Vân Quan đã lấy lại diện mạo nguyên bản uy nghiêm thời Nguyễn. Du khách vượt đèo Hải Vân có thể dừng chân tại đỉnh đèo, dạo bước trên những bậc thềm đá cổ xưa, tìm hiểu lịch sử hào hùng và chụp những bức ảnh ngoạn mục giữa làn mây trắng bồng bềnh.',
    N'TravelWise'
FROM places
WHERE name = N'Hải Vân Quan';


-- =========================================================
-- 45. KNOWLEDGE - LÀNG CỔ PHONG NAM
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lịch sử và nguồn gốc ngôi làng cổ xứ Quảng',
    N'Làng Phong Nam xưa vốn là một phần của làng cổ Phong Lệ trứ danh được khai phá từ thời Champa và các bậc tiền nhân thời vua Lê Thánh Tông thế kỷ 15. Nơi đây là quê hương của nhiều danh nhân chí sĩ yêu nước như cụ Ông Ích Khiêm. Ngôi làng lưu giữ hệ thống văn chỉ, nhà thờ tộc họ và đình làng được xây dựng từ thế kỷ 18, phản ánh truyền thống hiếu học và trọng đạo của người dân đất Quảng.',
    N'TravelWise'
FROM places
WHERE name = N'Làng cổ Phong Nam';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian làng quê Bắc bộ thu nhỏ giữa lòng miền Trung',
    N'Đặt chân đến Phong Nam, du khách như bước vào một bức tranh phong cảnh đồng quê thanh bình với cổng làng bằng gạch cổ vồ rêu phong in bóng cây đa trăm tuổi. Những con đường làng quanh co rợp bóng tre, những bờ giậu chè tàu cắt tỉa ngay ngắn và các nếp nhà rường gỗ lim truyền thống với sân gạch phơi lúa mang lại cảm giác bình yên sâu lắng.',
    N'TravelWise'
FROM places
WHERE name = N'Làng cổ Phong Nam';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lễ hội mục đồng và trải nghiệm du lịch văn hóa làng quê',
    N'Làng Phong Nam còn nổi tiếng với Lễ hội Mục đồng độc nhất vô nhị ở Việt Nam - ngày hội tôn vinh trẻ chăn trâu và cầu chúc mùa màng bội thu tổ chức định kỳ 3 năm một lần. Du khách đến Phong Nam có thể đạp xe quanh đường làng, ghé thăm nhà thờ cụ Ông Ích Khiêm, thưởng thức bánh tráng nướng mắm ruốc và lắng nghe các cụ cao niên kể chuyện tích làng xưa.',
    N'TravelWise'
FROM places
WHERE name = N'Làng cổ Phong Nam';


-- =========================================================
-- 46. KNOWLEDGE - LÀNG CHIẾU CẨM NÊ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lịch sử hơn 5 thế kỷ dệt chiếu tiến vua Cẩm Nê',
    N'Nghề dệt chiếu hoa Cẩm Nê bắt nguồn từ thế kỷ 15 khi các di dân từ Thanh Hóa theo chân vua Lê Thánh Tông vào Nam khai hoang lập nghiệp mang theo bí quyết dệt chiếu cói truyền thống. Dưới triều nhà Nguyễn, chiếu hoa Cẩm Nê tinh xảo được triều đình chọn làm sản vật tiến vua ngự dụng và ban thưởng sắc phong cho các nghệ nhân xuất sắc của làng.',
    N'TravelWise'
FROM places
WHERE name = N'Làng chiếu Cẩm Nê';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Quy trình thủ công tỉ mỉ tạo nên đôi chiếu hoa trứ danh',
    N'Để làm ra một chiếc chiếu Cẩm Nê bền đẹp, người thợ phải trải qua nhiều công đoạn công phu: từ khâu chọn cây cói phơi khô, nhuộm màu tự nhiên bằng lá cây rừng và phẩm màu rực rỡ, đến khâu dệt chiếu trên khung cửi đôi đòi hỏi sự phối hợp nhịp nhàng giữa hai người thợ. Chiếu dệt xong dày dặn, các nan khít chặt, hoa văn chữ thọ, rồng phụng sống động và không bị ẩm mốc.',
    N'TravelWise'
FROM places
WHERE name = N'Làng chiếu Cẩm Nê';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm văn hóa làng nghề và mua quà lưu niệm',
    N'Đến với làng chiếu Cẩm Nê, du khách được trực tiếp quan sát bàn tay thoăn thoắt của các nghệ nhân bên khung cửi kẽo kẹt và có thể tự tay trải nghiệm luồn cói dệt nên sản phẩm. Du khách có thể đặt mua những chiếc chiếu hoa mini làm lót chén trà, thảm cói trang trí thủ công độc đáo mang đậm giá trị văn hóa dân gian đất Quảng.',
    N'TravelWise'
FROM places
WHERE name = N'Làng chiếu Cẩm Nê';


-- =========================================================
-- 47. KNOWLEDGE - HỒ HÒA TRUNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan thảo nguyên xanh Hồ Hòa Trung',
    N'Hồ Hòa Trung vốn là hồ thủy lợi được bao bọc bởi những dãy núi trập trùng của huyện Hòa Vang. Điểm kỳ thú nhất ở đây là chu kỳ nước thay đổi theo mùa: mùa nước đầy hồ tựa như một tấm gương khổng lồ in bóng mây trời non nước; khi mùa khô đến, nước rút để lộ đáy hồ rộng mênh mông phủ kín thảm cỏ xanh rì tựa như thảo nguyên du mục bát ngát.',
    N'TravelWise'
FROM places
WHERE name = N'Hồ Hòa Trung';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm cắm trại qua đêm và chèo thuyền kayak',
    N'Hồ Hòa Trung là tọa độ cắm trại qua đêm (camping) lý tưởng dành cho những ai muốn "trốn" khỏi phố thị ồn ào. Du khách có thể dựng lều trên thảm cỏ bằng phẳng, tổ chức tiệc nướng BBQ, ngắm hoàng hôn đỏ rực buông xuống lòng hồ và thức giấc đón sương sớm giăng mờ ảo trên mặt nước. Vào mùa nước lớn, trải nghiệm chèo thuyền kayak hay thuyền độc mộc lướt trên mặt hồ phẳng lặng vô cùng thú vị.',
    N'TravelWise'
FROM places
WHERE name = N'Hồ Hòa Trung';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lưu ý quan trọng khi dã ngoại tại Hồ Hòa Trung',
    N'Khu vực Hồ Hòa Trung vẫn còn rất hoang sơ và chưa có nhiều dịch vụ thương mại du lịch, vì vậy du khách cần tự chuẩn bị đầy đủ lều trại, đồ ăn, nước uống và thuốc xịt côn trùng. Tuyệt đối không được xả rác, dọn dẹp sạch sẽ tàn tro lửa trại trước khi rời đi để bảo vệ vẻ đẹp nguyên sơ của cảnh quan sinh thái thiên nhiên.',
    N'TravelWise'
FROM places
WHERE name = N'Hồ Hòa Trung';


-- =========================================================
-- 48. KNOWLEDGE - KHU DU LỊCH SUỐI MƠ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan vẻ đẹp thiên nhiên Suối Mơ Hòa Vang',
    N'Suối Mơ sở hữu khung cảnh thiên nhiên thơ mộng hữu tình đúng như tên gọi của mình. Dòng suối uốn lượn quanh co qua các ghềnh đá lớn nhỏ, hai bên bờ rợp bóng cây cổ thụ và những khóm hoa dại khoe sắc. Khí hậu tại Suối Mơ quanh năm mát mẻ nhờ thừa hưởng luồng không khí trong lành từ cánh rừng nguyên sinh Bà Nà - Núi Chúa.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch Suối Mơ';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tắm suối mát lạnh và các hoạt động thư giãn dã ngoại',
    N'Điểm hấp dẫn nhất ở Suối Mơ là những hồ tắm tự nhiên được tạo nên bởi các đập tràn và vách đá chặn dòng nước chảy. Nước suối trong vắt nhìn thấy từng viên sỏi dưới đáy và đàn cá tung tăng bơi lội. Du khách có thể thỏa thích ngâm mình dưới dòng nước suối mát rượi, nằm nghỉ trên những phiến đá bằng phẳng râm mát và lắng nghe tiếng chim rừng ríu rít.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch Suối Mơ';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Ẩm thực núi rừng và kinh nghiệm tham quan Suối Mơ',
    N'Khu du lịch có hệ thống chòi tre mộc mạc dựng dọc bờ suối phục vụ ăn uống và nghỉ ngơi. Du khách có thể thưởng thức các món đặc sản đồng quê như gà đồi nướng mọi, cá suối chiên giòn chấm mắm gừng, ốc đá xào sả ớt và rau rừng luộc. Thời điểm lý tưởng nhất để đến Suối Mơ là vào mùa hè từ tháng 4 đến tháng 8 khi thời tiết nắng ráo.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch Suối Mơ';


-- =========================================================
-- 49. KNOWLEDGE - KHU DU LỊCH SINH THÁI YÊN RETREAT
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian "bỏ phố về quê" tại Yên Retreat Hòa Bắc',
    N'Đúng như tên gọi "Yên", nơi đây mang lại sự an yên và tĩnh lặng tuyệt đối cho tâm hồn sau những ngày làm việc căng thẳng nơi phố thị. Tọa lạc bên khúc quanh êm đềm của dòng sông Cu Đê, Yên Retreat được bao bọc bởi những rặng đồi xanh mướt trập trùng, mặt sông phẳng lặng in bóng mây trời và bầu không khí nguyên sơ trong trẻo.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch sinh thái Yên Retreat';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm cắm trại phong cách Glamping và chèo thuyền sông Cu Đê',
    N'Khu nghỉ dưỡng cung cấp dịch vụ cắm trại tiện nghi với những căn lều vải canvas trắng tinh tế trang bị đầy đủ đệm ấm, quạt và đèn led lung linh. Du khách có thể trải nghiệm chèo thuyền gỗ hoặc thuyền kayak xuôi dòng Cu Đê ngắm cảnh đôi bờ, tham gia tiệc nướng BBQ ngoài trời bên ánh lửa bập bùng và ngắm hàng ngàn vì sao đêm.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch sinh thái Yên Retreat';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tọa độ check-in nghệ thuật và thời điểm đẹp nhất',
    N'Yên Retreat được chăm chút từng góc nhỏ với lối đi lát sỏi, cầu gỗ vươn ra bờ sông, xích đu dưới tán cây và những bụi hoa dại rực rỡ, là thiên đường chụp ảnh kỷ yếu, ảnh cưới và sống ảo phong cách vintage. Thời điểm lý tưởng nhất để trải nghiệm là từ tháng 2 đến tháng 9 vào những ngày nắng đẹp không có mưa lũ.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch sinh thái Yên Retreat';


-- =========================================================
-- 50. KNOWLEDGE - LÀNG SINH THÁI THÁI LAI
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan ngôi làng sinh thái ven sông Túy Loan',
    N'Thái Lai được bao bọc bởi dải phù sa màu mỡ ven sông Túy Loan với những vườn cây ăn trái sum suê trĩu quả quanh năm. Ngôi làng vẫn giữ được vẻ đẹp yên bình nguyên sơ với những rặng tre xanh ngát ven sông, bến nước mộc mạc và những nếp nhà ngói phủ rêu phong, phản ánh bức tranh làng quê thuần Việt đậm đà bản sắc.',
    N'TravelWise'
FROM places
WHERE name = N'Làng sinh thái Thái Lai';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc nhà rường cổ 200 năm tuổi của cụ Đỗ Thần',
    N'Điểm nhấn nổi bật nhất tại Thái Lai là ngôi nhà rường cổ của gia tộc họ Đỗ có tuổi đời hơn 200 năm còn nguyên vẹn. Ngôi nhà được xây dựng hoàn toàn bằng các loại gỗ quý như kiền kiền, mít ròng với hệ thống cột kèo trạm trổ hoa văn tinh xảo theo lối kiến trúc ba gian hai chái truyền thống miền Trung, lưu giữ nhiều hoành phi, câu đối và nông cụ cổ.',
    N'TravelWise'
FROM places
WHERE name = N'Làng sinh thái Thái Lai';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm văn hóa ẩm thực và du lịch miệt vườn',
    N'Đến với Thái Lai, du khách được thưởng thức các món ăn dân dã nức tiếng như bánh tráng Túy Loan nướng giòn rụm, cá bống sông nướng nghệ, canh cua đồng rau tập tàng và mì Quảng gà ta thả vườn. Du khách còn có thể chèo thuyền trên sông Túy Loan, tự tay thu hoạch rau củ trong vườn và tìm hiểu văn hóa nông thôn đặc sắc.',
    N'TravelWise'
FROM places
WHERE name = N'Làng sinh thái Thái Lai';


-- =========================================================
-- 51. KNOWLEDGE - BÃI BIỂN PHẠM VĂN ĐỒNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan bãi tắm công cộng Phạm Văn Đồng',
    N'Bãi biển Phạm Văn Đồng được đầu tư hạ tầng đồng bộ và hiện đại bậc nhất thành phố, gồm bãi cát rộng, hệ thống tráng nước ngọt tiện nghi, nhà vệ sinh sạch sẽ và đội ngũ cứu hộ thường trực chuyên nghiệp. Bãi cát trắng trải dài thoai thoải ra mép sóng với làn nước trong vắt màu ngọc bích, thích hợp cho mọi lứa tuổi từ trẻ em đến người lớn tuổi tắm biển thư giãn.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Phạm Văn Đồng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Các hoạt động thể thao biển và giải trí sôi động',
    N'Bãi biển là trung tâm của các hoạt động thể thao mạo hiểm dưới nước như dù lượn cano kéo ngắm thành phố từ trên cao, lướt mô tô nước tốc độ cao, chèo ván đứng SUP và bóng chuyền bãi biển. Vào sáng sớm hoặc hoàng hôn, bãi biển luôn rộn ràng không khí tập thể dục, chạy bộ và yoga ven bờ sóng rì rào.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Phạm Văn Đồng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm kết hợp tham quan và ẩm thực ven biển',
    N'Nằm liền kề Công viên Biển Đông, du khách có thể cho chim bồ câu ăn và chụp ảnh vào buổi sáng sớm, sau đó tắm biển và thưởng thức bữa tối hải sản tươi sống tại các nhà hàng danh tiếng dọc đường Võ Nguyên Giáp. Tuyệt đối tuân thủ cờ hiệu cứu hộ và phao giới hạn khi tắm biển để đảm bảo an toàn tuyệt đối.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Phạm Văn Đồng';


-- =========================================================
-- 52. KNOWLEDGE - BÃI BIỂN BẮC MỸ AN
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan Bãi biển nghỉ dưỡng cao cấp Bắc Mỹ An',
    N'Bắc Mỹ An nổi danh là "thủ phủ nghỉ dưỡng" ven biển của miền Trung kể từ khi khu nghỉ dưỡng Furama Resort đầu tiên được xây dựng tại đây vào năm 1997. Bãi biển sở hữu bờ cát trắng muốt, làn nước biển trong xanh màu ngọc bích quanh năm và nhiệt độ nước ấm áp ôn hòa, tạo nên không gian thư giãn sang trọng bậc nhất bên bờ biển Đông.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Bắc Mỹ An';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Hệ thống bãi tắm T20, Mỹ Đa Đông và dịch vụ quốc tế',
    N'Dọc bờ biển Bắc Mỹ An gồm nhiều cụm bãi tắm nổi tiếng như bãi T20, bãi Mỹ Đa Đông và các bãi tắm resort cao cấp. Du khách có thể thư giãn trên những chiếc ghế dài dưới tán dừa xanh, nhâm nhi ly cocktail mát lạnh tại các quầy bar bãi biển, trải nghiệm dịch vụ spa massage ven biển và tham gia các khóa học lướt sóng chuyên nghiệp.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Bắc Mỹ An';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm ẩm thực hải sản và ngắm hoàng hôn biển',
    N'Khu vực lân cận bãi biển Bắc Mỹ An có mật độ nhà hàng hải sản cao cấp và phố Tây ẩm thực sầm uất An Thượng. Du khách có thể thưởng thức các bữa tiệc nướng hải sản cao cấp hoặc hải sản dân dã tươi rói ngay sau một ngày dạo biển thư thái ngắm ánh hoàng hôn buông đỏ rực nơi chân trời.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Bắc Mỹ An';


-- =========================================================
-- 53. KNOWLEDGE - BÃI BIỂN XUÂN THIỀU
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lịch sử tên gọi "Biển Đỏ" và vẻ đẹp vịnh Đà Nẵng',
    N'Năm 1965, lữ đoàn lính thủy đánh bộ Mỹ đầu tiên đổ bộ vào bờ biển này và đặt tên là "Red Beach" (Biển Đỏ), bởi vào những buổi bình minh hay hoàng hôn, ánh mặt trời phản chiếu xuống mặt nước vịnh làm cả bầu trời và làn sóng biển ánh lên màu đỏ rực kỳ ảo. Ngày nay, Xuân Thiều là một bãi biển du lịch yên bình và mang vẻ đẹp hoang sơ duyên dáng.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Xuân Thiều';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cảnh quan vòng cung vịnh và tầm nhìn kỳ vĩ',
    N'Khác với các bãi biển nhìn thẳng ra đại dương bên phía Sơn Trà, Bãi biển Xuân Thiều nằm lọt trong eo vịnh Đà Nẵng nên sóng biển thường êm dịu hơn. Đứng từ bờ biển, du khách có thể phóng tầm mắt bao quát toàn cảnh một bên là dãy núi Hải Vân sừng sững tựa bức tường thành xanh ngắt, một bên là bán đảo Sơn Trà vươn mình ra biển lớn.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Xuân Thiều';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Khu tổ hợp công viên nước nóng kiểu Nhật Da Nang Mikazuki',
    N'Điểm nhấn hiện đại bên bờ biển Xuân Thiều là Khu nghỉ dưỡng phức hợp Da Nang Mikazuki Japanese Resorts & Spa chuẩn Nhật Bản với công viên nước trong nhà 365, suối khoáng nóng Onsen và núi Phú Sĩ nhân tạo khổng lồ. Du khách có thể kết hợp tắm biển Xuân Thiều và trải nghiệm dịch vụ thư giãn phong cách Nhật Bản độc đáo.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi biển Xuân Thiều';


-- =========================================================
-- 54. KNOWLEDGE - CÔNG VIÊN APEC ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Ý nghĩa biểu tượng kiến trúc "Cánh diều bay cao"',
    N'Công trình mái vòm vòm cong của Công viên APEC mở rộng được tạo hình cách điệu như một cánh diều khổng lồ đang căng gió bay vút lên bầu trời. Cánh diều là biểu tượng của tuổi thơ thanh bình và khát vọng vươn tầm hội nhập quốc tế của thành phố biển Đà Nẵng năng động. Mái vòm được kết cấu từ hàng trăm tấn thép uốn lượn uốn sóng nhịp nhàng tạo hiệu ứng thị giác ấn tượng.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên APEC Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổ hợp không gian ba tầng đa chức năng hiện đại',
    N'Công viên được thiết kế thông minh gồm ba tầng: tầng hầm bố trí khu vực đỗ xe và khu kỹ thuật; tầng 1 là không gian nghỉ chân, cà phê, quầy thông tin du lịch và khu bán hàng lưu niệm; tầng 2 là sàn cảnh quan ngoài trời với hồ nước tràn, vườn hoa, đài phun nước nghệ thuật và lối đi bộ uốn lượn dưới vòm cánh diều.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên APEC Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Vườn tượng điêu khắc quốc tế của 21 nền kinh tế APEC',
    N'Phía Nam công viên là khu vườn tượng điêu khắc ngoài trời lưu giữ các tác phẩm nghệ thuật đặc sắc do 21 nền kinh tế thành viên Diễn đàn Hợp tác Kinh tế Châu Á - Thái Bình Dương (APEC) gửi tặng nhân Hội nghị Cấp cao APEC 2017 tại Đà Nẵng. Về đêm, hệ thống đèn led nghệ thuật đổi màu làm nổi bật cánh diều lung linh soi bóng bên dòng sông Hàn.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên APEC Đà Nẵng';


-- =========================================================
-- 55. KNOWLEDGE - CÔNG VIÊN BIỂN ĐÔNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Quảng trường đàn bồ câu hòa bình bên bờ biển Đông',
    N'Điểm đặc trưng nhất làm nên thương hiệu của Công viên Biển Đông là đàn chim bồ câu hòa bình với số lượng hàng ngàn con được chăm sóc cẩn thận. Vào mỗi buổi sáng sớm lúc 6h30 và buổi chiều lúc 16h30, khi tiếng còi của người nuôi vang lên, đàn bồ câu đồng loạt sà xuống sân quảng trường đón ăn, tạo nên khung cảnh thanh bình tuyệt đẹp thu hút đông đảo du khách cho ăn và chụp ảnh.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên Biển Đông';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tượng Mẹ Âu Cơ và biểu tượng tình yêu biển đảo',
    N'Tại trung tâm quảng trường công viên sừng sững bức tượng đá điêu khắc "Mẹ Âu Cơ và bọc trăm trứng", mang thông điệp cội nguồn dân tộc và ý chí kiên cường giữ gìn chủ quyền biển đảo thiêng liêng của Tổ quốc. Không gian công viên rợp bóng dừa xanh, thảm cỏ mượt mà và các tác phẩm điêu khắc nghệ thuật đương đại ngoài trời.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên Biển Đông';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trung tâm của các lễ hội văn hóa và đại nhạc hội biển',
    N'Công viên Biển Đông là sân khấu chính diễn ra chuỗi sự kiện lễ hội "Khai trương mùa du lịch biển Đà Nẵng" hàng năm, các lễ hội ẩm thực đường phố, ngày hội thả diều nghệ thuật khổng lồ và các đêm đại nhạc hội Countdown đón năm mới rực rỡ thu hút hàng chục vạn người dân và du khách tham gia.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên Biển Đông';


-- =========================================================
-- 56. KNOWLEDGE - CẦU ĐI BỘ NGUYỄN VĂN TRỖI
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Lịch sử cây cầu đầu tiên vượt sông Hàn năm 1965',
    N'Cầu Nguyễn Văn Trỗi gồm 14 nhịp giàn thép Poni có tổng chiều dài hơn 500m, được hoàn thành năm 1965 để chuyên chở khí tài quân sự qua bán đảo Sơn Trà. Sau ngày giải phóng năm 1975, cầu được đặt theo tên người anh hùng liệt sĩ thanh niên Nguyễn Văn Trỗi. Cây cầu đã gắn bó máu thịt với biết bao thế hệ người dân Đà Nẵng trong những năm tháng gian khó và tái thiết thành phố.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu đi bộ Nguyễn Văn Trỗi';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cầu đi bộ và công viên trên sông Hàn độc nhất vô nhị',
    N'Thay vì dỡ bỏ, chính quyền thành phố Đà Nẵng đã quyết định bảo tồn cây cầu như một kỷ vật lịch sử sống động và cải tạo thành cầu đi bộ dành riêng cho người dân và khách du lịch. Mặt cầu được lát gỗ thông thoáng, lan can sơn màu vàng vintage rực rỡ, lắp đặt ghế ngồi nghỉ ngơi và hệ thống chiếu sáng nghệ thuật ấm cúng.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu đi bộ Nguyễn Văn Trỗi';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Góc ngắm hoàng hôn và view toàn cảnh sông Hàn',
    N'Nằm kề bên Cầu Trần Thị Lý hiện đại, cầu đi bộ Nguyễn Văn Trỗi là vị trí hoàn hảo để ngắm trọn vẹn vẻ đẹp của sông Hàn lúc hoàng hôn buông xuống. Rất nhiều bạn trẻ và các cặp đôi chọn cây cầu này làm địa điểm chụp ảnh cưới phong cách hoài niệm và tận hưởng làn gió mát lành thổi từ biển vào lòng sông.',
    N'TravelWise'
FROM places
WHERE name = N'Cầu đi bộ Nguyễn Văn Trỗi';


-- =========================================================
-- 57. KNOWLEDGE - PHỐ ẨM THỰC HUỲNH THÚC KHÁNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan tuyến phố điểm tâm sáng trứ danh Đà Nẵng',
    N'Đường Huỳnh Thúc Kháng từ lâu đã trở thành địa chỉ quen thuộc của người Đà Nẵng khi muốn tìm một bữa sáng chất lượng. Không gian phố rợp bóng cây xanh với những dãy quán ăn san sát nhau, bàn ghế tinh tươm và mùi thơm ngào ngạt của nước dùng bánh canh, phở bò, bún bò bốc khói nghi ngút từ tờ mờ sáng.',
    N'TravelWise'
FROM places
WHERE name = N'Phố ẩm thực Huỳnh Thúc Kháng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thực đơn món ngon đặc sản phong phú chuẩn vị xứ Quảng',
    N'Tại phố Huỳnh Thúc Kháng, thực khách có thể thưởng thức đủ các món ngon tinh túy: bánh canh cá lóc đồng nước dùng ngọt thanh, bún mắm nêm thịt quay giòn rụm đậm đà mắm cái, bánh bèo nậm lọc chén nóng hổi, xôi gà xé béo ngậy, bún chả cá Đà Nẵng gia truyền và bánh cuốn nóng hổi ăn kèm chả chiên giòn.',
    N'TravelWise'
FROM places
WHERE name = N'Phố ẩm thực Huỳnh Thúc Kháng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm thưởng thức ẩm thực tại phố Huỳnh Thúc Kháng',
    N'Các quán ăn trên phố hoạt động nhộn nhịp nhất từ 6h00 đến 10h00 sáng, một số quán tiếp tục bán xuyên trưa và buổi tối. Giá cả các món ăn ở đây rất bình dân và được niêm yết rõ ràng. Du khách nên đi dạo bộ dọc con phố để lựa chọn món ăn ưa thích và kết thúc bữa sáng bằng một ly cà phê phin vỉa hè đậm chất Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Phố ẩm thực Huỳnh Thúc Kháng';


-- =========================================================
-- 58. KNOWLEDGE - CHỢ ĐẦU MỐI HÒA CƯỜNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổng quan chợ đầu mối nông sản lớn nhất Đà Nẵng',
    N'Chợ đầu mối Hòa Cường được khánh thành nhằm thay thế cho các chợ đầu mối cũ trong nội đô, có diện tích rộng hàng vạn mét vuông với hàng trăm ô sạp kiên cố. Chợ đóng vai trò là "dạ dày" cung cấp toàn bộ nguồn rau xanh, hoa quả tươi ngon và thực phẩm thiết yếu cho hệ thống siêu thị, chợ dân sinh và các nhà hàng trên toàn thành phố Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đầu mối Hòa Cường';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Nhịp sống giao thương xuyên đêm hối hả',
    N'Thời điểm chợ Hòa Cường sôi động nhất là từ 23h00 đêm đến 5h00 sáng hôm sau. Hàng trăm xe tải lớn nhỏ chở đầy ắp rau củ, trái cây nhiệt đới nối đuôi nhau vào bến bãi. Tiếng cười nói của tiểu thương, tiếng bốc dỡ hàng thoăn thoắt và ánh đèn sáng rực tạo nên bức tranh lao động tràn trề sức sống của thành phố về đêm.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đầu mối Hòa Cường';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm mua sắm trái cây giá sỉ tươi ngon',
    N'Du khách có thể ghé chợ vào sáng sớm để mua các loại trái cây đặc sản ba miền như bưởi da xanh, xoài cát Hòa Lộc, sầu riêng, thanh long, dâu tây Đà Lạt với mức giá sỉ rẻ bất ngờ và độ tươi ngon vừa hái. Quanh khu vực chợ cũng có nhiều quán cháo đêm, bánh mì và cà phê cóc phục vụ người lao động với hương vị mộc mạc thơm ngon.',
    N'TravelWise'
FROM places
WHERE name = N'Chợ đầu mối Hòa Cường';


-- =========================================================
-- 59. KNOWLEDGE - ĐẶC SẢN QUÁN TRẦN ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thương hiệu bánh tráng cuốn thịt heo hai đầu da trứ danh',
    N'Quán Trần nổi tiếng khắp trong và ngoài nước nhờ bí quyết thái miếng thịt heo luộc với hai đầu mỡ da giòn mềm đều đặn mà phần thịt nạc ở giữa vẫn giữ được độ ngọt mềm mọng nước. Từng lát thịt được xếp đều tăm tắp, cuốn cùng bánh tráng Đại Lộc dẻo thơm, bánh ướt mỏng mịn và lá rau xanh tươi mang lại hương vị thơm ngon khó cưỡng.',
    N'TravelWise'
FROM places
WHERE name = N'Đặc sản Quán Trần Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Bí quyết chén mắm nêm cá cơm đậm đà và khay rau rừng',
    N'Linh hồn của món bánh tráng cuốn thịt heo tại Quán Trần chính là chén mắm nêm gia truyền được ủ từ cá cơm than vùng biển miền Trung, pha chế cùng ớt đỏ băm nhuyễn, tỏi thơm, dứa băm ngọt dịu và chanh tươi. Đĩa rau sống ăn kèm gồm hơn 20 loại rau rừng, lá cóc, lá xoài non, chuối chát, khế chua và dưa leo giòn rụm.',
    N'TravelWise'
FROM places
WHERE name = N'Đặc sản Quán Trần Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian nhà hàng sang trọng và các món đặc sản khác',
    N'Quán Trần sở hữu không gian máy lạnh rộng rãi, bài trí nhã nhặn đậm chất Việt Nam và cung cách phục vụ chuyên nghiệp. Ngoài bánh tráng thịt heo, nhà hàng còn phục vụ nhiều món đặc sản hấp dẫn khác như mì Quảng tôm thịt, bún mắm nêm giò lụa, chả bò Đà Nẵng đặc biệt và bánh bèo chén tôm cháy thơm lừng.',
    N'TravelWise'
FROM places
WHERE name = N'Đặc sản Quán Trần Đà Nẵng';


-- =========================================================
-- 60. KNOWLEDGE - MÌ QUẢNG BÀ MUA ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thương hiệu Mì Quảng truyền thống lâu đời',
    N'Mì Quảng Bà Mua từ một quán ăn gia đình mộc mạc đã phát triển thành biểu tượng ẩm thực không thể bỏ qua đối với bất kỳ du khách nào đến Đà Nẵng. Bí quyết tạo nên tô mì Quảng đậm vị ở đây là sợi mì được tráng thủ công từ gạo quê nguyên chất, nước nhưỡng nấu cô đặc thơm lừng hương củ nén phi dầu đậu phộng béo ngậy đặc trưng xứ Quảng.',
    N'TravelWise'
FROM places
WHERE name = N'Mì Quảng Bà Mua Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thực đơn mì Quảng đa dạng chuẩn phong vị đất Quảng',
    N'Quán phục vụ phong phú các loại mì Quảng đáp ứng mọi khẩu vị: Mì Quảng gà ta thịt săn chắc ngấm gia vị, Mì Quảng tôm thịt ba chỉ đậm đà, Mì Quảng ếch đồng um cay nồng, Mì Quảng cá lóc đồng ngọt thịt và Mì Quảng thập cẩm đầy đặn. Tô mì được rắc đậu phộng rang giã dập, hành hoa thái nhỏ và ớt xanh cay nồng ăn kèm đĩa rau sống tươi roi rói.',
    N'TravelWise'
FROM places
WHERE name = N'Mì Quảng Bà Mua Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm thưởng thức mì Quảng đúng điệu',
    N'Để thưởng thức tô mì Quảng chuẩn vị người bản địa, thực khách bóp nhỏ bánh tráng nướng mè vào tô, thêm một thìa ớt chưng sa tế cay nồng, vắt miếng chanh tươi rồi trộn đều với rau sống hoa chuối thái mỏng. Quán Bà Mua mở cửa phục vụ từ 6h30 sáng đến 22h00 đêm với giá cả bình dân và phục vụ nhanh nhẹn.',
    N'TravelWise'
FROM places
WHERE name = N'Mì Quảng Bà Mua Đà Nẵng';


-- =========================================================
-- 61. KNOWLEDGE - CÀ PHÊ ÚT TỊCH ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian hoài niệm bao cấp giữa phố thị hiện đại',
    N'Bước chân vào Cà phê Út Tịch, thực khách như được quay ngược thời gian trở về những năm tháng bình dị của thế kỷ trước. Từng góc nhỏ trong quán được bài trí tỉ mỉ với những kỷ vật xưa cũ như chiếc tivi đen trắng cũ kỹ, máy phát đĩa than, chiếc quạt tai voi, xe đạp phượng hoàng và những mảng tường vàng cổ kính treo tranh cổ động.',
    N'TravelWise'
FROM places
WHERE name = N'Cà phê Út Tịch Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tầm nhìn ngắm sông Hàn và cầu quay tuyệt đẹp',
    N'Tọa lạc ngay mặt tiền tuyến đường ven sông Bạch Đằng sầm uất bậc nhất Đà Nẵng, tầng 2 của Út Tịch sở hữu ban công thoáng đãng nhìn thẳng ra mặt nước sông Hàn lấp lánh và Cầu Sông Hàn. Ngồi nhâm nhi tách cà phê tại ban công vào buổi chiều đón hoàng hôn buông xuống hoặc ngắm nhìn phố xá lên đèn rực rỡ là trải nghiệm vô cùng thi vị.',
    N'TravelWise'
FROM places
WHERE name = N'Cà phê Út Tịch Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thực đơn đồ uống truyền thống và cà phê pha phin',
    N'Thực đơn của Út Tịch tôn vinh các thức uống truyền thống của người Việt: Cà phê phin truyền thống thơm nồng đượm, cà phê muối béo ngậy mặn mà, cà phê cốt dừa thơm lừng, trà hoa quả nhiệt đới tươi mát và các món chè sắn, chè đậu truyền thống. Quán mở cửa từ 6h30 sáng đến 23h00 đêm, là chốn dừng chân lý tưởng sau những giờ dạo bộ quanh sông Hàn.',
    N'TravelWise'
FROM places
WHERE name = N'Cà phê Út Tịch Đà Nẵng';


-- =========================================================
-- 62. KNOWLEDGE - BÃI CÁT VÀNG SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Vẻ đẹp hoang sơ của bãi biển cát vàng bên sườn Sơn Trà',
    N'Bãi Cát Vàng được thiên nhiên ưu ái ban tặng một dải cát vàng mịn màng đặc trưng, uốn lượn bên bờ sóng xanh ngọc bích. Được bao bọc kín đáo bởi các dãy núi đá hoa cương cao vút và thảm rừng nguyên sinh nhiệt đới, bãi biển luôn kín gió, sóng êm đềm phẳng lặng quanh năm, đem lại cảm giác hòa mình trọn vẹn vào thiên nhiên biển đảo nguyên sơ.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Cát Vàng Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm lặn ngắm san hô và chèo thuyền Kayak',
    N'Vùng biển Bãi Cát Vàng là nơi sinh sống của nhiều loài san hô tự nhiên đa màu sắc, cá bướm, ốc biển và nhím biển. Du khách có thể tự do trải nghiệm lặn biển với kính lặn ống thở, chèo thuyền kayak lướt trên làn nước trong thấu đáy, thử tài bắn cá hoặc câu cá biển đêm cùng người dân địa phương.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Cát Vàng Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Dịch vụ lều trại dã ngoại và ẩm thực suối - biển',
    N'Tại Bãi Cát Vàng có các khu nhà chòi tre mộc mạc và bãi cỏ cắm trại qua đêm. Điểm thú vị là có dòng suối nước ngọt tự nhiên trong mát chảy từ vách núi để du khách tắm tráng nước ngọt sau khi tắm biển. Du khách có thể thưởng thức các món hải sản nướng than hoa tươi ngon như bào ngư nướng mỡ hành, ốc vú nàng và cá mú hấp xì dầu.',
    N'TravelWise'
FROM places
WHERE name = N'Bãi Cát Vàng Sơn Trà';


-- =========================================================
-- 63. KNOWLEDGE - VỌNG CẢNH ĐÀI SƠN TRÀ
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Đài quan sát trên đỉnh mây ngàn Sơn Trà',
    N'Vọng Cảnh Đài được xây dựng trên một mỏm đá nhô cao hướng về phía biển Tây Bắc của bán đảo Sơn Trà. Với độ cao hơn 600m so với mực nước biển, nơi đây quanh năm lộng gió và thường xuyên đón mây mù bảng lảng bay qua. Đài quan sát trang bị hệ thống kính viễn vọng hiện đại giúp du khách ngắm nhìn cận cảnh bờ biển và phố thị Đà Nẵng từ góc nhìn trên cao.',
    N'TravelWise'
FROM places
WHERE name = N'Vọng Cảnh Đài Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Di tích "Mắt thần Đông Dương" - Trạm Radar Sơn Trà',
    N'Nằm liền kề Vọng Cảnh Đài là Trạm Radar Sơn Trà với những vòm cầu trắng khổng lồ nổi bật giữa màu xanh của rừng núi. Trạm radar được quân đội Mỹ xây dựng từ thập niên 1960 để kiểm soát vùng trời và vùng biển Đông Dương, từng được mệnh danh là "Mắt thần Đông Dương". Ngày nay trạm vẫn giữ nhiệm vụ chiến lược bảo vệ an ninh vùng trời Tổ quốc.',
    N'TravelWise'
FROM places
WHERE name = N'Vọng Cảnh Đài Sơn Trà';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm ngắm cảnh và chụp ảnh toàn cảnh vịnh',
    N'Thời điểm lý tưởng nhất để đến Vọng Cảnh Đài là vào những ngày trời trong xanh từ 8h00 đến 10h00 sáng hoặc từ 15h30 đến 17h00 chiều. Đứng từ đài vọng cảnh, du khách sẽ bắt trọn khoảnh khắc vịnh Đà Nẵng phẳng lặng như tấm gương xanh khổng lồ ôm lấy cung đường biển uốn lượn tuyệt đẹp dưới chân đèo Hải Vân.',
    N'TravelWise'
FROM places
WHERE name = N'Vọng Cảnh Đài Sơn Trà';


-- =========================================================
-- 64. KNOWLEDGE - GIẾNG TRỜI ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kỳ quan thiên tạo giữa lòng rừng nguyên sinh Bà Nà',
    N'Tên gọi Giếng Trời xuất phát từ cấu trúc địa hình độc đáo: một hồ nước ngọt tự nhiên hình tròn lọt thỏm giữa bốn bề vách núi đá hoa cương dựng đứng và vòm trời mở rộng phía trên. Từ độ cao hơn 25m, một dòng thác lớn tuôn trào bọt tung trắng xóa quanh năm đổ xuống lòng hồ nước sâu xanh biếc tạo nên khung cảnh nguyên sơ kỳ vĩ tựa chốn bồng lai.',
    N'TravelWise'
FROM places
WHERE name = N'Giếng Trời Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Trải nghiệm chèo bè chuối, tắm hồ và cắm trại hoang dã',
    N'Đến với Giếng Trời, du khách được tận hưởng cảm giác đắm mình trong làn nước mát lạnh như băng của hồ đá tự nhiên, trải nghiệm tự kết bè chuối bơi giữa lòng hồ, trượt thác trên các phiến đá phủ rêu nhẵn thín và câu cá suối. Đêm về, cắm trại bên bờ suối róc rách, đốt lửa trại nướng gà đồi và ngắm bầu trời sao giữa rừng già mang lại trải nghiệm sinh tồn khó quên.',
    N'TravelWise'
FROM places
WHERE name = N'Giếng Trời Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cẩm nang trekking và an toàn cung đường Giếng Trời',
    N'Cung đường trekking Giếng Trời dài khoảng 7,5km đường rừng với nhiều đoạn dốc đá, lội suối và đồi dốc trơn trượt, mất khoảng 3–4 tiếng đi bộ. Du khách bắt buộc phải trang bị giày leo núi chống trượt, mặc áo phao khi xuống hồ nước sâu, mang theo thuốc chống vắt và đồ sơ cứu y tế. Tuyệt đối không đi vào mùa mưa lũ từ tháng 9 đến tháng 12 vì nguy cơ lũ quét rất cao.',
    N'TravelWise'
FROM places
WHERE name = N'Giếng Trời Đà Nẵng';


-- =========================================================
-- 65. KNOWLEDGE - KHU DU LỊCH SINH THÁI SUỐI HOA
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian ngập tràn sắc hoa và suối mát Hòa Phú',
    N'Đúng như tên gọi Suối Hoa, nơi đây kết hợp hài hòa giữa cảnh sắc suối thác tự nhiên và những vườn hoa nhiệt đới rực rỡ sắc màu được chăm sóc tỉ mỉ như hoa đào rừng, hoa trang rừng, hoa cúc vạn thọ và sen súng quanh năm khoe sắc. Khí hậu tại Suối Hoa luôn trong lành, mát mẻ dễ chịu nhờ thảm rừng tự nhiên bao bọc xung quanh.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch sinh thái Suối Hoa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thác Rù Rì, hồ bơi tự nhiên và cầu treo mộc mạc',
    N'Điểm nhấn của Suối Hoa là Thác Rù Rì đổ bọt trắng xóa xuống một hồ tắm tự nhiên rộng lớn có mực nước thoai thoải an toàn cho cả người lớn và trẻ nhỏ. Cây cầu treo bằng tre gỗ bắc qua lòng suối rợp bóng cây cổ thụ là góc chụp ảnh check-in mang đậm phong cách miền sơn cước được du khách đặc biệt yêu thích.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch sinh thái Suối Hoa';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Văn hóa nhà rông Cơ Tu và ẩm thực đặc sản vùng cao',
    N'Trong khuôn viên khu du lịch có nhà rông truyền thống của đồng bào dân tộc thiểu số Cơ Tu, nơi du khách có thể tìm hiểu về văn hóa cồng chiêng, nghề dệt thổ cẩm và trang phục truyền thống. Khu du lịch phục vụ các món ngon đặc sản núi rừng như cơm lam ống tre, gà nướng mật ong rừng, ốc đá xào lá lốt và rượu cần Cơ Tu nồng ấm.',
    N'TravelWise'
FROM places
WHERE name = N'Khu du lịch sinh thái Suối Hoa';


-- =========================================================
-- 66. KNOWLEDGE - CÔNG VIÊN 29 THÁNG 3
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'"Lá phổi xanh" lịch sử của thành phố biển Đà Nẵng',
    N'Công viên 29 Tháng 3 nguyên xưa là một khu vực bãi trũng đầm lầy ô nhiễm, sau ngày giải phóng năm 1975 đã được hàng vạn thanh niên, công nhân và người dân Đà Nẵng đồng lòng lao động công ích cải tạo thành công viên trung tâm kiểu mẫu. Công viên mang tên ngày giải phóng thành phố, là biểu tượng cho tinh thần lao động cần cù và khát vọng hồi sinh của người dân Đà Nẵng sau chiến tranh.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên 29 Tháng 3';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian sinh thái hồ nước và cây xanh rợp bóng',
    N'Trái tim của công viên là một hồ nước tự nhiên rộng hơn 10ha đóng vai trò hồ điều hòa sinh thái cho khu vực trung tâm đô thị. Ven bờ hồ là những hàng liễu rủ bóng thướt tha, rặng dừa xanh mát và những lối đi bộ uốn lượn dưới tán phi lao cổ thụ. Công viên có khu nuôi thả thú nhỏ, vườn chim cảnh và khu vui chơi đu quay, xe lửa dành cho trẻ em.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên 29 Tháng 3';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Điểm hẹn rèn luyện sức khỏe và tổ chức hội hoa xuân',
    N'Hàng ngày từ sáng sớm đến chiều muộn, công viên luôn tấp nập người dân địa phương đến đi bộ, tập thể dục dưỡng sinh, chơi cờ tướng và khiêu vũ thể thao. Vào mỗi dịp Tết Nguyên Đán, Công viên 29 Tháng 3 là địa điểm tổ chức Hội hoa xuân truyền thống quy mô lớn nhất thành phố, quy tụ hàng vạn chậu hoa mai, cúc vàng rực rỡ và các tiểu cảnh nghệ thuật độc đáo.',
    N'TravelWise'
FROM places
WHERE name = N'Công viên 29 Tháng 3';


-- =========================================================
-- 67. KNOWLEDGE - CHÙA TAM BẢO ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổ đình Phật giáo Nam Tông đầu tiên tại miền Trung',
    N'Chùa Tam Bảo khởi công xây dựng vào năm 1953 do các cư sĩ Phật giáo khởi xướng và được Hòa thượng Giới Nghiêm cung thỉnh xá lợi Phật về an vị. Đây là ngôi tổ đình đánh dấu sự truyền bá của Phật giáo Nam Tông vào vùng đất miền Trung Việt Nam. Khác với Phật giáo Bắc Tông thờ nhiều chư Phật và Bồ Tát, chùa Nam Tông chỉ thờ duy nhất Đức Phật Thích Ca Mâu Ni lịch sử.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Tam Bảo Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc bảo tháp 5 tầng lưu giữ Xá lợi Phật',
    N'Điểm nhấn kiến trúc nổi bật nhất của Chùa Tam Bảo là ngọn bảo tháp cao vút gồm 5 tầng sơn màu trắng tinh khôi, tượng trưng cho 5 giai đoạn tu tập của Đức Phật. Đỉnh tháp dát vàng lấp lánh dưới nắng mặt trời. Tầng cao nhất của bảo tháp là nơi tôn nghiêm lưu giữ ngọc Xá lợi Phật và Xá lợi của các vị Đại Thánh đệ tử được Giáo hội Phật giáo Hoàng gia Thái Lan trao tặng.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Tam Bảo Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Cây bồ đề quý từ Bồ Đề Đạo Tràng Ấn Độ',
    N'Trong sân chùa có một cây bồ đề đại thụ xum xuê cành lá, được chiết nhánh trực tiếp từ cây bồ đề gốc tại Bồ Đề Đạo Tràng (Bodh Gaya, Ấn Độ) - nơi Đức Phật thành đạo dưới cội bồ đề hơn 2.500 năm trước. Không gian chùa thanh tịnh, trang nghiêm, là nơi diễn ra các nghi lễ quan trọng của Phật giáo Nam Tông như lễ dâng y Kathina và đại lễ Phật Đản Vesak.',
    N'TravelWise'
FROM places
WHERE name = N'Chùa Tam Bảo Đà Nẵng';


-- =========================================================
-- 68. KNOWLEDGE - CUNG VĂN HÓA THIẾU NHI ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kiến trúc hình học Tangram độc đáo lấy cảm hứng từ trò chơi trí tuệ',
    N'Cung Văn hóa Thiếu nhi Đà Nẵng được xây dựng trên khu đất rộng hơn 33.000m² với tổng vốn đầu tư gần 250 tỷ đồng. Ý tưởng thiết kế công trình dựa trên trò chơi ghép hình Tangram cổ điển, ghép nối các khối đa diện cơ bản thành các hình thù phong phú, tượng trưng cho sự sáng tạo vô tận, tư duy linh hoạt và trí tưởng tượng bay bổng của trẻ thơ.',
    N'TravelWise'
FROM places
WHERE name = N'Cung Văn hóa Thiếu nhi Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian nghệ thuật rực rỡ sắc màu và con đường hoa anh đào',
    N'Mặt ngoài của tòa nhà được phủ các mảng màu color-block tươi sáng, nổi bật với các mô hình động vật cách điệu khổng lồ được ghép từ các khối hình học phẳng như hình con thỏ, con chim, con cá voi và chuồn chuồn. Khuôn viên ngoài trời trồng nhiều cây xanh, hồ nước cảnh quan và đặc biệt là con đường rợp bóng cây phong và hoa anh đào thu hút hàng ngàn bạn trẻ chụp ảnh nghệ thuật.',
    N'TravelWise'
FROM places
WHERE name = N'Cung Văn hóa Thiếu nhi Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tổ hợp giáo dục kỹ năng và vui chơi cho thiếu nhi',
    N'Bên trong công trình gồm 3 tầng chia thành nhiều phân khu chức năng hiện đại: nhà hát biểu diễn 500 chỗ ngồi, thư viện sách thông minh, phòng tập khiêu vũ, phòng học âm nhạc họa họa, phòng thể dục thể thao và khu trò chơi vận động ngoài trời. Cung Thiếu nhi mở cửa tự do khuôn viên cảnh quan bên ngoài cho du khách tham quan và chụp ảnh lưu niệm.',
    N'TravelWise'
FROM places
WHERE name = N'Cung Văn hóa Thiếu nhi Đà Nẵng';


-- =========================================================
-- 69. KNOWLEDGE - BÚN CHẢ CÁ BÀ LỮ ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Thương hiệu bún chả cá gia truyền hơn 40 năm tuổi',
    N'Bún chả cá bà Lữ được khai sinh từ những năm 1980 và nhanh chóng trở thành thương hiệu ẩm thực danh tiếng của người Đà Nẵng. Bí quyết giữ chân thực khách suốt bốn thập kỷ là nguồn cá biển nguyên liệu tươi rói được tuyển chọn trực tiếp từ các thuyền đánh cá cập bến sáng sớm, giã nhuyễn bằng tay cùng hạt tiêu sọ cay nồng và thì là thơm phức tạo độ dai giòn tự nhiên không hàn the.',
    N'TravelWise'
FROM places
WHERE name = N'Bún chả cá bà Lữ Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Nước dùng ngọt thanh từ rau củ và chả cá nguyên chất',
    N'Nồi nước dùng của quán bà Lữ có màu đỏ cam tự nhiên hấp dẫn nấu từ cà chua, dứa chín, măng tươi và đặc biệt là những miếng bí đỏ và bắp cải ninh mềm tạo vị ngọt thanh tự nhiên mà không cần nhiều mì chính. Tô bún được kết hợp giữa chả cá chiên vàng ươm giòn rụm và chả cá hấp mềm ngọt, ăn kèm lát cá ngừ hoặc cá thu tươi đậm đà.',
    N'TravelWise'
FROM places
WHERE name = N'Bún chả cá bà Lữ Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Kinh nghiệm thưởng thức bún chả cá chuẩn người Đà Nẵng',
    N'Khi ăn bún chả cá bà Lữ, thực khách nên cho thêm một muỗng mắm ruốc thơm lừng, một thìa ớt băm sa tế cay xé lưỡi, tép tỏi Lý Sơn giòn và dĩa rau sống hoa chuối xắt ghém non mịn. Quán mở cửa từ 6h00 sáng đến 23h00 đêm mỗi ngày với giá cả rất bình dân, luôn tấp nập du khách và người dân địa phương ghé thưởng thức.',
    N'TravelWise'
FROM places
WHERE name = N'Bún chả cá bà Lữ Đà Nẵng';


-- =========================================================
-- 70. KNOWLEDGE - BÁNH XÈO BÀ DƯỠNG ĐÀ NẴNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Huyền thoại quán ăn trong hẻm nhỏ Hoàng Diệu',
    N'Dù nằm sâu trong con hẻm quanh co K280 Hoàng Diệu, Bánh xèo Bà Dưỡng lúc nào cũng tấp nập khách ra vào từ trưa đến khuya. Từ một quán ăn vỉa hè mộc mạc của bà Dưỡng khởi nghiệp từ năm 1989, quán đã phát triển thành điểm hẹn ẩm thực đường phố không thể bỏ qua của mọi du khách trong và ngoài nước khi đặt chân đến Đà Nẵng.',
    N'TravelWise'
FROM places
WHERE name = N'Bánh xèo Bà Dưỡng Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Vỏ bánh đúc than hồng giòn tan và nhân tôm thịt tươi ngon',
    N'Bánh xèo Bà Dưỡng được đổ trong những chiếc chảo gang nhỏ trên bếp than hoa rực lửa. Bột bánh xay từ gạo quê pha chút bột nghệ vàng óng và nước cốt dừa béo bùi. Khi lớp vỏ ngoài vừa đạt độ giòn rụm hoàn hảo, đầu bếp nhanh tay cho nhân tôm đất tươi sống, thịt ba chỉ áp chảo và giá đỗ giòn ngọt rồi gập đôi bánh lại nóng hổi bốc khói.',
    N'TravelWise'
FROM places
WHERE name = N'Bánh xèo Bà Dưỡng Đà Nẵng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Nước chấm gan heo đậu phộng "thần thánh" và nem lụi nướng',
    N'Bí quyết làm nên thương hiệu Bà Dưỡng chính là bát nước chấm "thần thánh" màu nâu sánh đặc, được ninh nhuyễn từ gan heo, thịt nạc băm, mè rang và đậu phộng béo bùi tạo hương vị đậm đà không nơi nào có được. Du khách cuốn bánh xèo cùng bánh tráng mỏng, nem lụi nướng than hoa, rau cải con, chuối chát và dưa leo giòn mát rồi chấm đẫm vào bát sốt.',
    N'TravelWise'
FROM places
WHERE name = N'Bánh xèo Bà Dưỡng Đà Nẵng';


-- =========================================================
-- 71. KNOWLEDGE - CỘNG CÀ PHÊ BẠCH ĐẰNG
-- =========================================================

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Không gian retro thời bao cấp độc đáo ven sông Hàn',
    N'Cộng Cà Phê đường Bạch Đằng gây ấn tượng với không gian 2 tầng rộng rãi được thiết kế tỉ mỉ theo concept bao cấp hoài niệm. Từng chi tiết nhỏ như ly tráng men xanh, bình tông quân đội, máy chữ cơ, chiếc đài cát-sét cũ và giá sách gỗ phủ màu thời gian tạo nên bầu không khí ấm cúng, đậm chất văn hóa Việt Nam của những năm tháng kháng chiến gian lao mà hào hùng.',
    N'TravelWise'
FROM places
WHERE name = N'Cộng Cà Phê Bạch Đằng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Món cà phê cốt dừa trứ danh làm say lòng du khách quốc tế',
    N'Đến Cộng Cà Phê, thức uống mà bất kỳ thực khách nào cũng phải thử một lần là Cà phê cốt dừa đá xay. Sự kết hợp hoàn hảo giữa vị đắng đậm đà của cà phê phin nguyên chất Việt Nam và vị ngọt béo ngậy, mát lạnh của cốt dừa xay mịn tạo nên hương vị bùng nổ vị giác, được du khách Hàn Quốc và phương Tây đặc biệt say mê.',
    N'TravelWise'
FROM places
WHERE name = N'Cộng Cà Phê Bạch Đằng';

INSERT INTO knowledge
(place_id, title, content, source)
SELECT
    id,
    N'Tầm nhìn ngắm toàn cảnh sông Hàn và phố đi bộ về đêm',
    N'Vị trí của quán trên đường Bạch Đằng - tuyến phố đi bộ ven sông Hàn đẹp nhất Đà Nẵng - mang lại góc ngắm cảnh tuyệt đỉnh từ ban công tầng 2. Thực khách có thể nhâm nhi ly cà phê thơm nồng trong tiếng nhạc Trịnh Công Sơn êm dịu, ngắm nhìn dòng thuyền rồng du lịch lướt nhẹ trên sông và đón trọn làn gió mát rượi từ cửa vịnh thổi vào.',
    N'TravelWise'
FROM places
WHERE name = N'Cộng Cà Phê Bạch Đằng';


-- =========================================================
-- PLACE IMAGES (2 HÌNH ẢNH THỰC TẾ CHO MỖI ĐỊA ĐIỂM)
-- =========================================================

-- 1. Chùa Linh Ứng Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Lady_Buddha_Da_Nang_5.jpg?width=1200', N'Tượng Phật Quan Âm cao 67m hướng ra biển tại Chùa Linh Ứng', 1
FROM places WHERE name = N'Chùa Linh Ứng Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/2024-12-07_Linh_Ung_Pagoda_4.jpg?width=1200', N'Toàn cảnh khuôn viên Chùa Linh Ứng và Bán đảo Sơn Trà', 0
FROM places WHERE name = N'Chùa Linh Ứng Sơn Trà';


-- 2. Bà Nà Hills
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/The_Golden_Bridge,_Ba_Na_Hills,_Vietnam.jpg?width=1200', N'Cầu Vàng Bà Nà Hills với đôi bàn tay khổng lồ nâng đỡ', 1
FROM places WHERE name = N'Bà Nà Hills';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Ba_Na_Hills_French_Village.jpg?width=1200', N'Khu Làng Pháp mang phong cách kiến trúc Châu Âu tại Bà Nà Hills', 0
FROM places WHERE name = N'Bà Nà Hills';


-- 3. Ngũ Hành Sơn
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Marble_Mountains_2020_IMG_4008.jpg?width=1200', N'Quần thể danh thắng Ngũ Hành Sơn kỳ vĩ giữa lòng Đà Nẵng', 1
FROM places WHERE name = N'Ngũ Hành Sơn';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hiking_at_Marble_Mountains,_Da_Nang,_Vietnam.jpg?width=1200', N'Khám phá các hang động tự nhiên và chùa cổ tại Thủy Sơn', 0
FROM places WHERE name = N'Ngũ Hành Sơn';


-- 4. Cầu Rồng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Dragon_Bridge_(I).jpg?width=1200', N'Cầu Rồng phun lửa rực rỡ bên dòng sông Hàn về đêm', 1
FROM places WHERE name = N'Cầu Rồng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Dragon_Bridge_Da_Nang_1.jpg?width=1200', N'Kiến trúc rồng vàng uốn lượn vươn ra biển lớn của Cầu Rồng', 0
FROM places WHERE name = N'Cầu Rồng';


-- 5. Bãi biển Mỹ Khê
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/My_Khe_Beach,_Da_Nang,_Vietnam.jpg?width=1200', N'Bãi biển Mỹ Khê với bãi cát trắng mịn và làn nước trong xanh', 1
FROM places WHERE name = N'Bãi biển Mỹ Khê';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/My_Khe_Beach_18.jpg?width=1200', N'Khung cảnh nắng vàng và hàng dừa thơ mộng ven biển Mỹ Khê', 0
FROM places WHERE name = N'Bãi biển Mỹ Khê';


-- 6. Chợ Hàn
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Han_Market_-_Da_Nang,_Vietnam_-_DSC02375.JPG?width=1200', N'Không gian buôn bán tấp nập các gian hàng đặc sản tại Chợ Hàn', 1
FROM places WHERE name = N'Chợ Hàn';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Fabric_in_Han_Market_-_Da_Nang,_Vietnam_-_DSC02377.JPG?width=1200', N'Gian hàng vải vóc may áo dài và đồ lưu niệm tại Chợ Hàn', 0
FROM places WHERE name = N'Chợ Hàn';


-- 7. Bảo tàng Điêu khắc Chăm Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/0040223_Brahma,_Cham_Hindu_deity,_Museum_of_Cham_Sculpture,_Da_Nang_Vietnam.jpg?width=1200', N'Tác phẩm tượng thần Brahma điêu khắc Chăm Pa cổ tại bảo tàng', 1
FROM places WHERE name = N'Bảo tàng Điêu khắc Chăm Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/0040223_Ganesha,_Cham_Hindu_deity,_Museum_of_Cham_Sculpture,_Da_Nang_Vietnam.jpg?width=1200', N'Tượng thần Ganesha - hiện vật nghệ thuật điêu khắc Chăm độc bản', 0
FROM places WHERE name = N'Bảo tàng Điêu khắc Chăm Đà Nẵng';


-- 8. Bán đảo Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son-Tra-Peninsula_Da-Nang_Vietnam_Linh-Ung-Pagoda-01.jpg?width=1200', N'Cung đường ven biển uốn lượn ôm trọn Bán đảo Sơn Trà', 1
FROM places WHERE name = N'Bán đảo Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son-Tra-Peninsula_Da-Nang_Vietnam_Linh-Ung-Pagoda-02.jpg?width=1200', N'Khung cảnh thiên nhiên hoang sơ và làn nước biển trong vắt tại Sơn Trà', 0
FROM places WHERE name = N'Bán đảo Sơn Trà';


-- 9. Cầu Tình Yêu Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Love_Lock_Bridge_Da_Nang_05.19.jpg?width=1200', N'Cầu Tình Yêu lung linh với những cột đèn lồng trái tim lãng mạn', 1
FROM places WHERE name = N'Cầu Tình Yêu Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Dragon_Carp,_Da_Nang_05.19.jpg?width=1200', N'Tượng Cá Chép Hóa Rồng phun nước uy nghi bên bờ sông Hàn', 0
FROM places WHERE name = N'Cầu Tình Yêu Đà Nẵng';


-- 10. Đèo Hải Vân
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/L%C4%83ng_C%C3%B4,_H%E1%BA%A3i_V%C3%A2n_Pass,_2020-01_CN-01.jpg?width=1200', N'Cung đường Đèo Hải Vân quanh co hùng vĩ nhìn xuống vịnh biển', 1
FROM places WHERE name = N'Đèo Hải Vân';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/L%C4%83ng_C%C3%B4,_H%E1%BA%A3i_V%C3%A2n_Pass,_2020-01_CN-02.jpg?width=1200', N'Toàn cảnh núi non và biển trời bao la nhìn từ đỉnh Đèo Hải Vân', 0
FROM places WHERE name = N'Đèo Hải Vân';


-- 11. Cầu Sông Hàn
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Han_River_Bridge,_Da_Nang,_20241209,_Ansicht01.jpeg?width=1200', N'Toàn cảnh Cầu Sông Hàn nối liền hai bờ trung tâm thành phố Đà Nẵng', 1
FROM places WHERE name = N'Cầu Sông Hàn';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Han_River_Bridge,_Da_Nang,_20241209,_Ansicht02.jpeg?width=1200', N'Cầu quay Sông Hàn lung linh rực rỡ ánh đèn màu về đêm', 0
FROM places WHERE name = N'Cầu Sông Hàn';


-- 12. Cầu Thuận Phước
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/2024-12-08_Thuan_Phuoc_Bridge_in_Da_Nang.jpg?width=1200', N'Cầu Thuận Phước - cây cầu treo dây võng dài nhất Việt Nam', 1
FROM places WHERE name = N'Cầu Thuận Phước';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Thuan_Phuoc_Bridge-2.jpg?width=1200', N'Kiến trúc thanh thoát của Cầu Thuận Phước nơi cửa biển sông Hàn', 0
FROM places WHERE name = N'Cầu Thuận Phước';


-- 13. Cầu Trần Thị Lý
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Tr%E1%BA%A7n_Th%E1%BB%8B_L%C3%BD_Bridge.jpg?width=1200', N'Kiến trúc trụ tháp nghiêng và dây văng hình cánh buồm Cầu Trần Thị Lý', 1
FROM places WHERE name = N'Cầu Trần Thị Lý';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Red_Night_at_Tran_Thi_Ly_Bridge_(Unsplash).jpg?width=1200', N'Hệ thống ánh sáng đổi màu rực rỡ của Cầu Trần Thị Lý về đêm', 0
FROM places WHERE name = N'Cầu Trần Thị Lý';


-- 14. Bãi biển Non Nước
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Palm_trees_beach_Da_Nang.jpg?width=1200', N'Bãi biển Non Nước hoang sơ với hàng dừa và bờ cát trắng mịn', 1
FROM places WHERE name = N'Bãi biển Non Nước';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Resort_development_at_Non_Nuoc.jpg?width=1200', N'Bờ biển Non Nước yên bình và làn nước trong xanh dưới chân Ngũ Hành Sơn', 0
FROM places WHERE name = N'Bãi biển Non Nước';


-- 15. Rạn Nam Ô
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Nam_%C3%94%2C_%C4%90%C3%A0_N%E1%BA%B5ng.jpg?width=1200', N'Vẻ đẹp kỳ ảo của các khối đá phủ rêu xanh mướt tại Rạn Nam Ô', 1
FROM places WHERE name = N'Rạn Nam Ô';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da-Nang_Vietnam_Coracles-01.jpg?width=1200', N'Thuyền thúng truyền thống bên bờ biển làng chài cổ Nam Ô', 0
FROM places WHERE name = N'Rạn Nam Ô';


-- 16. Ghềnh Bàng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bai_Bien_Tai_Quan_Son_Tra.jpg?width=1200', N'Bãi đá tự nhiên hoang sơ và làn nước biển trong vắt tại Ghềnh Bàng', 1
FROM places WHERE name = N'Ghềnh Bàng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/B%C3%A1n_%C4%91%E1%BA%A3o_S%C6%A1n_Tr%C3%A0_th10n2023_(b%C3%A3i_bi%E1%BB%83n%2C_c%C3%A1t)_(10).jpg?width=1200', N'Khung cảnh thiên nhiên kỳ vĩ hoang sơ của bán đảo Sơn Trà', 0
FROM places WHERE name = N'Ghềnh Bàng';


-- 17. Đỉnh Bàn Cờ
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Chessboard_statue_in_Ban_Co_peak.jpg?width=1200', N'Tượng Đế Thích ngồi trầm ngâm bên bàn cờ trên đỉnh núi Sơn Trà', 1
FROM places WHERE name = N'Đỉnh Bàn Cờ';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/View_of_Da_Nang_from_Son_Tra_(44851087882).jpg?width=1200', N'Tầm nhìn bao quát trọn vẹn thành phố biển Đà Nẵng từ Đỉnh Bàn Cờ', 0
FROM places WHERE name = N'Đỉnh Bàn Cờ';


-- 18. Chùa Quan Thế Âm
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Quan_Am_(montagne_de_marbre,_Danang)_(4325094896).jpg?width=1200', N'Tượng Phật Quan Thế Âm linh thiêng tại Ngũ Hành Sơn', 1
FROM places WHERE name = N'Chùa Quan Thế Âm';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Quan_Am_(montagne_de_marbre,_Danang)_(4414490074).jpg?width=1200', N'Không gian tâm linh thanh tịnh dưới chân ngọn Kim Sơn', 0
FROM places WHERE name = N'Chùa Quan Thế Âm';


-- 19. Nhà thờ Chính tòa Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Cathedral_-_Da_Nang,_Vietnam_-_DSC02464.JPG?width=1200', N'Kiến trúc Gothic màu hồng pastel đặc trưng của Nhà thờ Con Gà', 1
FROM places WHERE name = N'Nhà thờ Chính tòa Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Nha_Tho_Con_Ga_Da_Nang.JPG?width=1200', N'Mặt tiền cổ kính và tháp chuông Nhà thờ Chính tòa Đà Nẵng', 0
FROM places WHERE name = N'Nhà thờ Chính tòa Đà Nẵng';


-- 20. Chùa Tam Thai
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Ch%C3%B9a_Tam_Thai,_Th%E1%BB%A7y_S%C6%A1n,_%C4%90%C3%A0_N%E1%BA%B5ng_(Tam_Thai_Pagoda,_Thuy_Son_Marble_Mountain)_-_img_001.jpg?width=1200', N'Cổng tam quan rêu phong cổ kính của Quốc tự Tam Thai', 1
FROM places WHERE name = N'Chùa Tam Thai';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Ch%C3%B9a_Tam_Thai,_Th%E1%BB%A7y_S%C6%A1n,_%C4%90%C3%A0_N%E1%BA%B5ng_(Tam_Thai_Pagoda,_Thuy_Son_Marble_Mountain)_-_img_01.jpg?width=1200', N'Chính điện Chùa Tam Thai uy nghiêm giữa thung lũng đá Thủy Sơn', 0
FROM places WHERE name = N'Chùa Tam Thai';


-- 21. Bảo tàng Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Dien_Hai_Citadel_South_Gate.jpg?width=1200', N'Cổng thành phía Nam Di tích Quốc gia đặc biệt Thành Điện Hải', 1
FROM places WHERE name = N'Bảo tàng Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Dien_Hai_Citadel_Moat_1.jpg?width=1200', N'Hào thành Điện Hải và khuôn viên trưng bày Bảo tàng Đà Nẵng', 0
FROM places WHERE name = N'Bảo tàng Đà Nẵng';


-- 22. Bảo tàng Mỹ thuật Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/B%E1%BA%A3o_t%C3%A0ng_M%E1%BB%B9_thu%E1%BA%ADt_%C4%90%C3%A0_N%E1%BA%B5ng.jpeg?width=1200', N'Mặt tiền kiến trúc hiện đại và không gian trưng bày Bảo tàng Mỹ thuật Đà Nẵng', 1
FROM places WHERE name = N'Bảo tàng Mỹ thuật Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Vietnam_National_Museum_of_Fine_Arts_01.JPG?width=1200', N'Không gian trưng bày các tác phẩm hội họa và điêu khắc nghệ thuật', 0
FROM places WHERE name = N'Bảo tàng Mỹ thuật Đà Nẵng';


-- 23. Bảo tàng Tranh 3D Art in Paradise
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Trick_Art_Museum_(9407354543).jpg?width=1200', N'Không gian nghệ thuật tranh 3D đánh lừa thị giác sống động và vui nhộn', 1
FROM places WHERE name = N'Bảo tàng Tranh 3D Art in Paradise';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Trick_Art_Museum_(9410118210).jpg?width=1200', N'Trải nghiệm chụp ảnh tương tác cùng các tác phẩm 3D độc đáo tại Art in Paradise', 0
FROM places WHERE name = N'Bảo tàng Tranh 3D Art in Paradise';


-- 24. Chợ Cồn
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Cho_Con_DN_corner.JPG?width=1200', N'Cổng chợ và khu ẩm thực sầm uất nhộn nhịp tại Chợ Cồn', 1
FROM places WHERE name = N'Chợ Cồn';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Con_Market_at_sunset.jpg?width=1200', N'Không khí nhộn nhịp tại thiên đường ẩm thực Chợ Cồn lúc hoàng hôn', 0
FROM places WHERE name = N'Chợ Cồn';


-- 25. Chợ đêm Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/DZ6_0930_Skewers_of_sizzling_street_food_glow_under_neon_lights_as_a_bustling_night_market_hums_in_the_background.jpg?width=1200', N'Các gian hàng hải sản xiên nướng rực rỡ tại Chợ đêm Sơn Trà', 1
FROM places WHERE name = N'Chợ đêm Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/DFC_2092_Night_market_food_stalls_lit_up_under_a_glowing_billboard_motorcycles_parked_in_front_as_customers_dine_late_into_the_evening.jpg?width=1200', N'Không khí ẩm thực đường phố sôi động về đêm gần Cầu Rồng', 0
FROM places WHERE name = N'Chợ đêm Sơn Trà';


-- 26. Chợ đêm Helio
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Helio_Center,_Da_Nang_(49373166151).jpg?width=1200', N'Khu chợ đêm Helio rực rỡ ánh đèn và không gian mở hiện đại', 1
FROM places WHERE name = N'Chợ đêm Helio';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Food_court_at_Helio_Center,_Da_Nang_(49358206972).jpg?width=1200', N'Thiên đường ẩm thực đêm đa dạng các món ăn vặt tại Helio Center', 0
FROM places WHERE name = N'Chợ đêm Helio';


-- 27. Công viên Châu Á (Asia Park)
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Sun_Wheel_at_night.jpg?width=1200', N'Vòng quay Mặt Trời Sun Wheel rực sáng lung linh giữa bầu trời đêm', 1
FROM places WHERE name = N'Công viên Châu Á (Asia Park)';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Sun_Wheel_by_day.jpg?width=1200', N'Toàn cảnh tổ hợp vui chơi giải trí Asia Park bên bờ sông Hàn', 0
FROM places WHERE name = N'Công viên Châu Á (Asia Park)';


-- 28. Khu du lịch Suối Khoáng Nóng Núi Thần Tài
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/C%C3%B4ng_Vi%C3%AAn_Su%E1%BB%91i_Kho%C3%A1ng_N%C3%B3ng_N%C3%BAi_Th%E1%BA%A7n_T%C3%A0i.jpg?width=1200', N'Khu du lịch suối khoáng nóng Núi Thần Tài giữa thiên nhiên núi rừng', 1
FROM places WHERE name = N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/CVKSN_N%C3%BAi_Th%E1%BA%A7n_T%C3%A0i.jpg?width=1200', N'Hồ khoáng nóng thư giãn Onsen và công viên nước trên núi', 0
FROM places WHERE name = N'Khu du lịch Suối Khoáng Nóng Núi Thần Tài';


-- 29. Làng đá mỹ nghệ Non Nước
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Non_Nuoc_Pagoda_Da_Nang_1.jpg?width=1200', N'Tác phẩm điêu khắc đá cẩm thạch tinh xảo tại làng nghề Non Nước', 1
FROM places WHERE name = N'Làng đá mỹ nghệ Non Nước';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Non_Nuoc_Pagoda_Da_Nang_2.jpg?width=1200', N'Nghệ thuật tạc tượng đá thủ công truyền thống hàng trăm năm tuổi', 0
FROM places WHERE name = N'Làng đá mỹ nghệ Non Nước';


-- 30. Hồ Xanh Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Chua_Linh_Ung_Bai_But_DN.jpg?width=1200', N'Vẻ đẹp hồ nước xanh ngọc bích và rừng cây dưới chân Bãi Bụt', 1
FROM places WHERE name = N'Hồ Xanh Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son-Tra-Peninsula_Da-Nang_Vietnam_Linh-Ung-Pagoda-03.jpg?width=1200', N'Khung cảnh thiên nhiên hữu tình và mặt hồ phẳng lặng tại Hồ Xanh', 0
FROM places WHERE name = N'Hồ Xanh Sơn Trà';


-- 31. Cây đa ngàn năm Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Giant_Banyan_Tree_on_Son_Tra_Peninsula.jpg?width=1200', N'Cây đa ngàn năm kỳ vĩ giữa rừng nguyên sinh bán đảo Sơn Trà', 1
FROM places WHERE name = N'Cây đa ngàn năm Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Cay_da_Son_Tra.jpg?width=1200', N'Hệ thống rễ phụ khổng lồ cắm sâu vào lòng đất của Bách niên đại thụ', 0
FROM places WHERE name = N'Cây đa ngàn năm Sơn Trà';


-- 32. Mũi Nghê Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Cape_Nghe_Son_Tra_Peninsula.jpg?width=1200', N'Toàn cảnh Mũi Nghê vươn mình ra biển lớn đón ánh bình minh', 1
FROM places WHERE name = N'Mũi Nghê Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son_Tra_Peninsula_coastline.jpg?width=1200', N'Hồ bơi đá tự nhiên với làn nước trong vắt tại khu vực Mũi Nghê', 0
FROM places WHERE name = N'Mũi Nghê Sơn Trà';


-- 33. Bãi Rạng Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bai_Rang_Son_Tra.jpg?width=1200', N'Bãi cát thoai thoải và những ghềnh đá tự nhiên tại Bãi Rạng Sơn Trà', 1
FROM places WHERE name = N'Bãi Rạng Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Son_Tra_coastal_rocks.jpg?width=1200', N'Trải nghiệm tắm biển và thư giãn dưới những chòi lá mát rượi ven bờ', 0
FROM places WHERE name = N'Bãi Rạng Sơn Trà';


-- 34. Bãi Bụt Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bai_But_Son_Tra_Da_Nang.jpg?width=1200', N'Vịnh biển Bãi Bụt xanh ngọc bích dưới chân Chùa Linh Ứng', 1
FROM places WHERE name = N'Bãi Bụt Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son_Tra_Ocean_View.jpg?width=1200', N'Bờ cát trắng và các cụm chòi lá nghỉ dưỡng bình yên tại Bãi Bụt', 0
FROM places WHERE name = N'Bãi Bụt Sơn Trà';


-- 35. Bãi biển Tiên Sa
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Tien_Sa_Port_and_Beach_Da_Nang.jpg?width=1200', N'Bãi biển Tiên Sa với bờ cát mịn và bờ vịnh êm đềm phẳng lặng', 1
FROM places WHERE name = N'Bãi biển Tiên Sa';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Tien_Sa_Lighthouse_road.jpg?width=1200', N'Cung đường ven biển dẫn vào khu du lịch sinh thái Tiên Sa', 0
FROM places WHERE name = N'Bãi biển Tiên Sa';


-- 36. Hải đăng Tiên Sa
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Tien_Sa_Lighthouse_Da_Nang.jpg?width=1200', N'Hải đăng Tiên Sa cổ kính mang phong cách kiến trúc Pháp xây từ năm 1902', 1
FROM places WHERE name = N'Hải đăng Tiên Sa';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son_Tra_Lighthouse_view.jpg?width=1200', N'Tầm nhìn khoáng đạt hướng thẳng ra biển Đông từ đài quan sát ngọn hải đăng', 0
FROM places WHERE name = N'Hải đăng Tiên Sa';


-- 37. Động Huyền Không
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Huyen_Khong_Cave,_Marble_Mountains,_Da_Nang.jpg?width=1200', N'Không gian tráng lệ và luồng ánh sáng mặt trời chiếu rọi trong Động Huyền Không', 1
FROM places WHERE name = N'Động Huyền Không';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Sunlight_in_Huyen_Khong_Cave.jpg?width=1200', N'Tượng Phật Thích Ca ngự trên vách đá uy nghiêm giữa lòng hang động', 0
FROM places WHERE name = N'Động Huyền Không';


-- 38. Động Âm Phủ
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Am_Phu_Cave,_Marble_Mountains.jpg?width=1200', N'Cổng vào kỳ bí và không gian rộng lớn của Động Âm Phủ dưới chân Thủy Sơn', 1
FROM places WHERE name = N'Động Âm Phủ';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hell_Cave_Marble_Mountains_Da_Nang.jpg?width=1200', N'Các cảnh tượng mô phỏng giáo lý nhân quả và đường lên cõi Thiên Thai', 0
FROM places WHERE name = N'Động Âm Phủ';


-- 39. Chùa Pháp Lâm
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Phap_Lam_Pagoda_Da_Nang.jpg?width=1200', N'Chính điện trang nghiêm và kiến trúc truyền thống của Chùa Pháp Lâm', 1
FROM places WHERE name = N'Chùa Pháp Lâm';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Phap_Lam_Buddha_Statue.jpg?width=1200', N'Khuôn viên thanh tịnh rợp bóng mát cây xanh giữa lòng thành phố Đà Nẵng', 0
FROM places WHERE name = N'Chùa Pháp Lâm';


-- 40. Chùa Nam Sơn
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Nam_Son_Pagoda_Da_Nang_architecture.jpg?width=1200', N'Kiến trúc cung đình cổ kính và hồ nước thanh tịnh tại Chùa Nam Sơn', 1
FROM places WHERE name = N'Chùa Nam Sơn';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Nam_Son_Pagoda_garden_and_bridge.jpg?width=1200', N'Cầu gỗ uốn lượn treo lồng đèn đỏ rực rỡ giữa cảnh sắc thanh bình', 0
FROM places WHERE name = N'Chùa Nam Sơn';


-- 41. Bảo tàng Đồng Đình
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Dong_Dinh_Museum_Son_Tra.jpg?width=1200', N'Kiến trúc nhà rường cổ kính ẩn mình dưới tán rừng tự nhiên tại Bảo tàng Đồng Đình', 1
FROM places WHERE name = N'Bảo tàng Đồng Đình';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Dong_Dinh_Museum_traditional_house.jpg?width=1200', N'Không gian trưng bày cổ vật gốm sứ và mỹ thuật đương đại độc đáo', 0
FROM places WHERE name = N'Bảo tàng Đồng Đình';


-- 42. Nhà trưng bày Hoàng Sa
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hoang_Sa_Exhibition_House_Da_Nang.jpg?width=1200', N'Kiến trúc biểu tượng Con dấu Chủ quyền của Nhà trưng bày Hoàng Sa', 1
FROM places WHERE name = N'Nhà trưng bày Hoàng Sa';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hoang_Sa_Gallery_Architecture.jpg?width=1200', N'Không gian trưng bày tư liệu lịch sử và bản đồ cổ khẳng định chủ quyền biển đảo', 0
FROM places WHERE name = N'Nhà trưng bày Hoàng Sa';


-- 43. Hải Vân Quan
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hai_Van_Quan_Gate_Relic.jpg?width=1200', N'Cổng vòm đá cổ kính khắc chữ "Thiên hạ đệ nhất hùng quan" trên đỉnh đèo Hải Vân', 1
FROM places WHERE name = N'Hải Vân Quan';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hai_Van_Pass_Summit_Fortress.jpg?width=1200', N'Toàn cảnh cụm pháo đài và tường thành phòng thủ kiên cố giữa mây núi trập trùng', 0
FROM places WHERE name = N'Hải Vân Quan';


-- 44. Làng cổ Phong Nam
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Phong_Nam_Ancient_Village_Gate.jpg?width=1200', N'Cổng làng cổ rêu phong và cây đa rợp bóng bình yên tại Làng Phong Nam', 1
FROM places WHERE name = N'Làng cổ Phong Nam';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Phong_Nam_Communal_House_Da_Nang.jpg?width=1200', N'Đình làng cổ kính và nếp sống mộc mạc đậm chất thôn quê Việt Nam', 0
FROM places WHERE name = N'Làng cổ Phong Nam';


-- 45. Làng chiếu Cẩm Nê
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Cam_Ne_Traditional_Mat_Weaving.jpg?width=1200', N'Nghệ nhân làng Cẩm Nê thoăn thoắt bên khung dệt chiếu hoa truyền thống', 1
FROM places WHERE name = N'Làng chiếu Cẩm Nê';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Cam_Ne_Village_Da_Nang.jpg?width=1200', N'Những sợi cói nhuộm ngũ sắc rực rỡ phơi dưới nắng ấm làng quê Cẩm Nê', 0
FROM places WHERE name = N'Làng chiếu Cẩm Nê';


-- 46. Hồ Hòa Trung
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hoa_Trung_Lake_Da_Nang_grassland.jpg?width=1200', N'Thảo nguyên cỏ xanh mướt trải dài ngút ngàn vào mùa cạn tại Hồ Hòa Trung', 1
FROM places WHERE name = N'Hồ Hòa Trung';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Camping_at_Hoa_Trung_Lake.jpg?width=1200', N'Trải nghiệm cắm trại dã ngoại và đón hoàng hôn thơ mộng bên bờ hồ', 0
FROM places WHERE name = N'Hồ Hòa Trung';


-- 47. Khu du lịch Suối Mơ
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Suoi_Mo_Eco_Tourism_Da_Nang.jpg?width=1200', N'Dòng suối trong vắt và các tầng thác bọt tung trắng xóa tại Suối Mơ', 1
FROM places WHERE name = N'Khu du lịch Suối Mơ';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Suoi_Mo_waterfall_and_stream.jpg?width=1200', N'Khu vực chòi tre nghỉ ngơi và tắm suối dã ngoại giữa rừng nguyên sinh', 0
FROM places WHERE name = N'Khu du lịch Suối Mơ';


-- 48. Khu du lịch sinh thái Yên Retreat
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Yen_Retreat_Hoa_Bac_camping.jpg?width=1200', N'Khu cắm trại lều trắng thơ mộng bên bãi cỏ xanh ngát tại Yên Retreat', 1
FROM places WHERE name = N'Khu du lịch sinh thái Yên Retreat';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Cu_De_River_at_Hoa_Bac.jpg?width=1200', N'Khung cảnh sông Cu Đê hiền hòa và núi đồi trập trùng bao bọc Hòa Bắc', 0
FROM places WHERE name = N'Khu du lịch sinh thái Yên Retreat';


-- 49. Làng sinh thái Thái Lai
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Thai_Lai_Eco_Village_Hoa_Vang.jpg?width=1200', N'Khung cảnh thanh bình và vườn cây xanh mát tại Làng sinh thái Thái Lai', 1
FROM places WHERE name = N'Làng sinh thái Thái Lai';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Thai_Lai_Ancient_House_Da_Nang.jpg?width=1200', N'Kiến trúc nhà rường cổ ba gian hai chái hơn 200 năm tuổi tại thôn Thái Lai', 0
FROM places WHERE name = N'Làng sinh thái Thái Lai';


-- 50. Bãi biển Phạm Văn Đồng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Pham_Van_Dong_Beach_Da_Nang.jpg?width=1200', N'Bãi biển Phạm Văn Đồng với bờ cát trắng thoai thoải và làn nước xanh trong', 1
FROM places WHERE name = N'Bãi biển Phạm Văn Đồng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/East_Sea_Park_Beachfront.jpg?width=1200', N'Hàng dừa thơ mộng và các hoạt động tắm biển sôi động lúc bình minh', 0
FROM places WHERE name = N'Bãi biển Phạm Văn Đồng';


-- 51. Bãi biển Bắc Mỹ An
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bac_My_An_Beach_Resort_Coast.jpg?width=1200', N'Bờ cát trắng mịn màng và không gian nghỉ dưỡng cao cấp tại Bãi biển Bắc Mỹ An', 1
FROM places WHERE name = N'Bãi biển Bắc Mỹ An';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bac_My_An_White_Sands.jpg?width=1200', N'Làn nước trong xanh êm đềm và hàng dừa nghiêng soi bóng ven bờ biển', 0
FROM places WHERE name = N'Bãi biển Bắc Mỹ An';


-- 52. Bãi biển Xuân Thiều
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Xuan_Thieu_Red_Beach_Da_Nang.jpg?width=1200', N'Bãi biển Xuân Thiều êm đềm ôm trọn vòng cung vịnh Đà Nẵng', 1
FROM places WHERE name = N'Bãi biển Xuân Thiều';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Bay_view_from_Xuan_Thieu.jpg?width=1200', N'Khoảnh khắc hoàng hôn nhuộm đỏ rực mặt biển vịnh Đà Nẵng', 0
FROM places WHERE name = N'Bãi biển Xuân Thiều';


-- 53. Công viên APEC Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/APEC_Park_Da_Nang_Kite_Dome.jpg?width=1200', N'Mái vòm kiến trúc "Cánh diều bay cao" độc đáo của Công viên APEC Đà Nẵng', 1
FROM places WHERE name = N'Công viên APEC Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/APEC_Park_Night_Lighting.jpg?width=1200', N'Hệ thống chiếu sáng nghệ thuật rực rỡ soi bóng bên sông Hàn lúc lên đèn', 0
FROM places WHERE name = N'Công viên APEC Đà Nẵng';


-- 54. Công viên Biển Đông
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bien_Dong_Park_pigeons_Da_Nang.jpg?width=1200', N'Đàn chim bồ câu hòa bình tung cánh rợp bóng trên quảng trường Công viên Biển Đông', 1
FROM places WHERE name = N'Công viên Biển Đông';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/East_Sea_Park_Square_Da_Nang.jpg?width=1200', N'Toàn cảnh công viên rợp bóng dừa và bãi biển xanh ngắt ngút ngàn', 0
FROM places WHERE name = N'Công viên Biển Đông';


-- 55. Cầu đi bộ Nguyễn Văn Trỗi
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Nguyen_Van_Troi_Pedestrian_Bridge.jpg?width=1200', N'Cầu đi bộ Nguyễn Văn Trỗi với kết cấu vòm thép màu vàng vintage độc đáo', 1
FROM places WHERE name = N'Cầu đi bộ Nguyễn Văn Trỗi';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Nguyen_Van_Troi_Bridge_Sunset.jpg?width=1200', N'Khung cảnh hoàng hôn thanh bình và lãng mạn trên dòng sông Hàn từ cầu đi bộ', 0
FROM places WHERE name = N'Cầu đi bộ Nguyễn Văn Trỗi';


-- 56. Phố ẩm thực Huỳnh Thúc Kháng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Huynh_Thuc_Khang_Food_Street.jpg?width=1200', N'Không khí tấp nập của con phố điểm tâm sáng trứ danh Huỳnh Thúc Kháng', 1
FROM places WHERE name = N'Phố ẩm thực Huỳnh Thúc Kháng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Morning_Street_Food.jpg?width=1200', N'Các món ngon đặc sản thơm nức chuẩn vị truyền thống xứ Quảng', 0
FROM places WHERE name = N'Phố ẩm thực Huỳnh Thúc Kháng';


-- 57. Chợ đầu mối Hòa Cường
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Hoa_Cuong_Wholesale_Market_Da_Nang.jpg?width=1200', N'Cảnh tượng tấp nập hàng hóa nông sản tại Chợ đầu mối Hòa Cường', 1
FROM places WHERE name = N'Chợ đầu mối Hòa Cường';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Fruit_market_stalls_Hoa_Cuong.jpg?width=1200', N'Các sạp hoa quả tươi ngon đa dạng từ khắp ba miền hội tụ tại chợ', 0
FROM places WHERE name = N'Chợ đầu mối Hòa Cường';


-- 58. Đặc sản Quán Trần Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Banh_trang_cuon_thit_heo_Da_Nang.jpg?width=1200', N'Món Bánh tráng cuốn thịt heo hai đầu da trứ danh tại Đặc sản Quán Trần', 1
FROM places WHERE name = N'Đặc sản Quán Trần Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Quan_Tran_Da_Nang_Specialty.jpg?width=1200', N'Không gian ẩm thực sang trọng và mâm đặc sản truyền thống xứ Quảng', 0
FROM places WHERE name = N'Đặc sản Quán Trần Đà Nẵng';


-- 59. Mì Quảng Bà Mua Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Mi_Quang_Ba_Mua_traditional_bowl.jpg?width=1200', N'Tô Mì Quảng Bà Mua đậm đà chuẩn vị ăn kèm bánh tráng mè nướng giòn', 1
FROM places WHERE name = N'Mì Quảng Bà Mua Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Mi_Quang_Da_Nang_Specialty_Dish.jpg?width=1200', N'Sợi mì gạo truyền thống và nước nhưỡng sánh vàng thơm lừng củ nén', 0
FROM places WHERE name = N'Mì Quảng Bà Mua Đà Nẵng';


-- 60. Cà phê Út Tịch Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Ut_Tich_Cafe_Bach_Dang_Da_Nang.jpg?width=1200', N'Không gian hoài niệm cổ điển ấm cúng tại Cà phê Út Tịch đường Bạch Đằng', 1
FROM places WHERE name = N'Cà phê Út Tịch Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Vintage_Vietnamese_Coffee_Shop_Interior.jpg?width=1200', N'Góc ban công nhìn ra sông Hàn thơ mộng và các kỷ vật thời bao cấp', 0
FROM places WHERE name = N'Cà phê Út Tịch Đà Nẵng';


-- 61. Bãi Cát Vàng Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bai_Cat_Vang_Son_Tra_Da_Nang.jpg?width=1200', N'Bãi Cát Vàng hoang sơ với làn nước trong vắt nép mình bên vách núi', 1
FROM places WHERE name = N'Bãi Cát Vàng Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son_Tra_golden_sand_beach.jpg?width=1200', N'Trải nghiệm chèo thuyền kayak và lặn biển ngắm san hô tại Bãi Cát Vàng', 0
FROM places WHERE name = N'Bãi Cát Vàng Sơn Trà';


-- 62. Vọng Cảnh Đài Sơn Trà
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Vong_Canh_Dai_Son_Tra_View.jpg?width=1200', N'Tầm nhìn ngoạn mục bao quát toàn cảnh vịnh Đà Nẵng từ Vọng Cảnh Đài', 1
FROM places WHERE name = N'Vọng Cảnh Đài Sơn Trà';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Son_Tra_Radar_Station_dome.jpg?width=1200', N'Vòm cầu trạm radar "Mắt thần Đông Dương" sừng sững trên đỉnh núi', 0
FROM places WHERE name = N'Vọng Cảnh Đài Sơn Trà';


-- 63. Giếng Trời Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Gieng_Troi_Waterfall_Da_Nang.jpg?width=1200', N'Thác nước Giếng Trời đổ thẳng xuống lòng hồ ngọc bích giữa rừng già', 1
FROM places WHERE name = N'Giếng Trời Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Gieng_Troi_Trekking_Path.jpg?width=1200', N'Cung đường trekking nguyên sơ và hồ tắm tự nhiên kỳ vĩ tại Giếng Trời', 0
FROM places WHERE name = N'Giếng Trời Đà Nẵng';


-- 64. Khu du lịch sinh thái Suối Hoa
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Suoi_Hoa_Eco_Resort_Da_Nang.jpg?width=1200', N'Cầu treo thơ mộng bắc qua dòng suối và ngập tràn sắc hoa rừng tại Suối Hoa', 1
FROM places WHERE name = N'Khu du lịch sinh thái Suối Hoa';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Suoi_Hoa_Waterfall_Stream.jpg?width=1200', N'Thác Rù Rì và hồ bơi thiên nhiên trong mát giữa tán cây cổ thụ', 0
FROM places WHERE name = N'Khu du lịch sinh thái Suối Hoa';


-- 65. Công viên 29 Tháng 3
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/29_Thang_3_Park_Da_Nang_Lake.jpg?width=1200', N'Hồ nước trung tâm và không gian cây xanh rợp bóng mát tại Công viên 29 Tháng 3', 1
FROM places WHERE name = N'Công viên 29 Tháng 3';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_City_Park_Walking_Path.jpg?width=1200', N'Lối đi dạo bộ rợp bóng liễu rủ thanh bình giữa lòng thành phố Đà Nẵng', 0
FROM places WHERE name = N'Công viên 29 Tháng 3';


-- 66. Chùa Tam Bảo Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Tam_Bao_Pagoda_Da_Nang_Stupa.jpg?width=1200', N'Tòa bảo tháp 5 tầng uy nghiêm mang phong cách kiến trúc Nam Tông tại Chùa Tam Bảo', 1
FROM places WHERE name = N'Chùa Tam Bảo Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Theravada_Pagoda_Interior_Da_Nang.jpg?width=1200', N'Chính điện thanh tịnh tôn thờ duy nhất Đức Phật Bổn Sư Thích Ca Mâu Ni', 0
FROM places WHERE name = N'Chùa Tam Bảo Đà Nẵng';


-- 67. Cung Văn hóa Thiếu nhi Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Children_Cultural_Center.jpg?width=1200', N'Kiến trúc hình học Tangram rực rỡ sắc màu tại Cung Văn hóa Thiếu nhi Đà Nẵng', 1
FROM places WHERE name = N'Cung Văn hóa Thiếu nhi Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Children_Center_Da_Nang_Courtyard.jpg?width=1200', N'Các mảng khối đa giác nghệ thuật và không gian mở hiện đại', 0
FROM places WHERE name = N'Cung Văn hóa Thiếu nhi Đà Nẵng';


-- 68. Bún chả cá bà Lữ Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Bun_Cha_Ca_Da_Nang_Traditional_Bowl.jpg?width=1200', N'Tô bún chả cá bà Lữ đậm đà với chả cá vàng ươm và nước dùng ngọt thanh', 1
FROM places WHERE name = N'Bún chả cá bà Lữ Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Da_Nang_Fish_Cake_Noodle_Soup.jpg?width=1200', N'Các loại chả cá tươi chiên giòn và chả cá hấp gia truyền nức tiếng', 0
FROM places WHERE name = N'Bún chả cá bà Lữ Đà Nẵng';


-- 69. Bánh xèo Bà Dưỡng Đà Nẵng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Banh_Xeo_Ba_Duong_Da_Nang.jpg?width=1200', N'Đĩa bánh xèo vàng ươm giòn rụm và bát nước chấm gan heo béo bùi tại Bà Dưỡng', 1
FROM places WHERE name = N'Bánh xèo Bà Dưỡng Đà Nẵng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Nem_Lui_Banh_Xeo_Da_Nang_Platter.jpg?width=1200', N'Mẹt bánh xèo, nem lụi nướng than hoa ăn kèm rau sống cuốn bánh tráng', 0
FROM places WHERE name = N'Bánh xèo Bà Dưỡng Đà Nẵng';


-- 70. Cộng Cà Phê Bạch Đằng
INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Cong_Caphe_Bach_Dang_Da_Nang.jpg?width=1200', N'Không gian phong cách thời bao cấp đặc trưng của Cộng Cà Phê đường Bạch Đằng', 1
FROM places WHERE name = N'Cộng Cà Phê Bạch Đằng';

INSERT INTO place_images (place_id, url, description, is_primary)
SELECT id, N'https://commons.wikimedia.org/wiki/Special:FilePath/Coconut_Coffee_Vietnamese_Drink.jpg?width=1200', N'Món Cà phê cốt dừa trứ danh và góc ban công nhìn thẳng ra dòng sông Hàn', 0
FROM places WHERE name = N'Cộng Cà Phê Bạch Đằng';


-- =========================================================
-- 12. KIỂM TRA DỮ LIỆU
-- =========================================================

SELECT
    p.id,
    p.name,
    COUNT(k.id) AS knowledge_count,
    COUNT(pi.id) AS image_count
FROM places p
LEFT JOIN knowledge k
    ON p.id = k.place_id
LEFT JOIN place_images pi
    ON p.id = pi.place_id
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


SELECT
    pi.id,
    p.name AS place_name,
    pi.is_primary,
    pi.description,
    pi.url
FROM place_images pi
INNER JOIN places p
    ON pi.place_id = p.id
ORDER BY p.name, pi.is_primary DESC;

GO

select * from users 
select * from places 
select * from place_images
select * from knowledge
select * from conversations where id =15
select * from messages where conversation_id = 15
select * from trips
select * from trip_items
select * from trip_preferences 
select * from itinerary_days 
select * from itinerary_activities 
select * from conversation_summaries 