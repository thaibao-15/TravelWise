import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/assistant/presentation/widgets/chat_message_bubble.dart';
import 'package:mobile/features/trips/models/trip_model.dart';
import 'package:mobile/features/trips/widgets/create_trip_sheet.dart';
import 'package:mobile/features/trips/widgets/trip_itinerary_card.dart';

void main() {
  final sampleTrip = Trip(
    id: 'trip_123',
    title: 'Khám phá Đà Nẵng 3 ngày',
    destination: 'Đà Nẵng, Việt Nam',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 3),
    daysCount: 3,
    totalStops: 6,
    estimatedBudget: '4.5M đ',
    days: [
      TripDay(
        dayIndex: 1,
        date: DateTime(2026, 11, 1),
        title: 'Khám phá bán đảo Sơn Trà',
        subtitle: 'Ngày 1 · 2 hoạt động',
        activities: [
          ItineraryActivity(
            id: 'act_1',
            startTime: '08:00',
            endTime: '11:00',
            title: 'Chùa Linh Ứng',
            category: 'Tham quan',
            duration: '3h',
            description: 'Viếng tượng Phật Bà Quan Âm cao 67m',
            placeAddress: 'Bán đảo Sơn Trà, Đà Nẵng',
            latitude: 16.1000,
            longitude: 108.2750,
          ),
          ItineraryActivity(
            id: 'act_2',
            startTime: '15:00',
            endTime: '18:00',
            title: 'Biển Mỹ Khê',
            category: 'Biển & Thư giãn',
            duration: '3h',
            description: 'Tắm biển và thư giãn',
            placeAddress: 'Võ Nguyên Giáp, Đà Nẵng',
            latitude: 16.0600,
            longitude: 108.2460,
          ),
        ],
      ),
    ],
  );

  group('TripItineraryCard Widget Tests', () {
    testWidgets('renders itinerary card title, destination, days and Xem lịch trình button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TripItineraryCard(trip: sampleTrip),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Khám phá Đà Nẵng 3 ngày'), findsOneWidget);
      expect(find.text('Đà Nẵng, Việt Nam'), findsOneWidget);
      expect(find.text('3 ngày'), findsWidgets);
      expect(find.text('6 điểm dừng'), findsOneWidget);
      expect(find.text('4.5M đ'), findsOneWidget);
      expect(find.text('Xem lịch trình'), findsOneWidget);
      expect(find.text('Chùa Linh Ứng · Biển Mỹ Khê'), findsOneWidget);
    });

    testWidgets('ChatMessageBubble renders embedded TripItineraryCard for AI messages',
        (tester) async {
      final messageWithTrip = ChatMessage(
        text: 'Mình đã tạo xong lịch trình Đà Nẵng 3 ngày cho bạn!',
        isUser: false,
        timestamp: DateTime(2026, 10, 21, 14, 30),
        tripItinerary: sampleTrip,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatMessageBubble(message: messageWithTrip),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Mình đã tạo xong lịch trình Đà Nẵng 3 ngày cho bạn!'), findsOneWidget);
      expect(find.byType(TripItineraryCard), findsOneWidget);
      expect(find.text('Xem lịch trình'), findsOneWidget);
    });
  });

  group('CreateTripSheet Widget Tests', () {
    testWidgets('shows validation error when destination city is empty and user clicks submit',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CreateTripSheet(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Find the city textfield and clear it
      final cityField = find.byType(TextField).first;
      await tester.enterText(cityField, '');
      await tester.pump();

      // Tap submit button
      final submitButton = find.text('Tạo lịch trình bằng AI ngay');
      await tester.tap(submitButton);
      await tester.pump();

      // Validation error message should be displayed
      expect(
        find.text('Vui lòng nhập điểm đến du lịch (ví dụ: Đà Nẵng, Phú Quốc...).'),
        findsOneWidget,
      );
    });

    testWidgets('day counter increments and decrements correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CreateTripSheet(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Initial day count is 3
      expect(find.text('3'), findsOneWidget);

      // Tap decrement
      final removeIcon = find.byIcon(Icons.remove);
      await tester.ensureVisible(removeIcon);
      await tester.tap(removeIcon);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      // Tap increment twice
      final addIcon = find.byIcon(Icons.add);
      await tester.ensureVisible(addIcon);
      await tester.tap(addIcon);
      await tester.pump();
      expect(find.text('3'), findsOneWidget);

      await tester.tap(addIcon);
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
    });
  });
}
