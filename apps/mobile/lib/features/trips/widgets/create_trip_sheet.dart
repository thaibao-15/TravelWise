import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../data/repositories/trip_repository.dart';
import '../models/trip_model.dart';
import '../providers/trip_provider.dart';
import '../screens/trip_detail_screen.dart';

/// Modal bottom sheet for manual and customized AI trip planning.
class CreateTripSheet extends ConsumerStatefulWidget {
  const CreateTripSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateTripSheet(),
    );
  }

  @override
  ConsumerState<CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends ConsumerState<CreateTripSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cityController = TextEditingController(text: 'Đà Nẵng');
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  int _daysCount = 3;
  String _selectedBudget = 'Tiêu chuẩn';
  String _selectedPace = 'Cân bằng';
  final Set<String> _selectedInterests = {'Ẩm thực', 'Biển'};
  bool _isSubmitting = false;
  String? _errorMessage;

  static const List<String> _popularCities = [
    'Đà Nẵng',
    'Hội An',
    'Phú Quốc',
    'Đà Lạt',
    'Hà Nội',
    'Sa Pa',
    'Nha Trang',
    'TP. Hồ Chí Minh',
  ];

  static const List<Map<String, String>> _availableInterests = [
    {'id': 'Ẩm thực', 'label': 'Ẩm thực & Đặc sản', 'icon': '🍲'},
    {'id': 'Biển', 'label': 'Biển & Nghỉ dưỡng', 'icon': '🏖️'},
    {'id': 'Văn hóa', 'label': 'Di tích & Văn hóa', 'icon': '🏛️'},
    {'id': 'Check-in', 'label': 'Check-in & Sống ảo', 'icon': '📸'},
    {'id': 'Thiên nhiên', 'label': 'Khám phá thiên nhiên', 'icon': '🌿'},
    {'id': 'Chợ đêm', 'label': 'Mua sắm & Chợ đêm', 'icon': '🛍️'},
    {'id': 'Cafe', 'label': 'Cà phê & Thư giãn', 'icon': '☕'},
  ];

  static const List<String> _budgets = [
    'Tiết kiệm',
    'Tiêu chuẩn',
    'Thoải mái',
    'Cao cấp',
  ];

  static const List<String> _paces = [
    'Thư thả, nhẹ nhàng',
    'Cân bằng',
    'Khám phá tối đa',
  ];

  @override
  void dispose() {
    _cityController.dispose();
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final city = _cityController.text.trim();
    if (city.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập điểm đến du lịch (ví dụ: Đà Nẵng, Phú Quốc...).';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(tripRepositoryProvider);

      // 1. Build trip name
      final rawName = _nameController.text.trim();
      final tripName = rawName.isNotEmpty ? rawName : 'Khám phá $city $_daysCount ngày';

      // 2. Build preferences prompt for AI itinerary generator
      final promptParts = <String>[];
      if (_selectedInterests.isNotEmpty) {
        promptParts.add('Sở thích: ${_selectedInterests.join(", ")}');
      }
      promptParts.add('Mức ngân sách: $_selectedBudget');
      promptParts.add('Nhịp độ: $_selectedPace');
      final note = _noteController.text.trim();
      if (note.isNotEmpty) {
        promptParts.add('Yêu cầu đặc biệt: $note');
      }
      final userPrompt = promptParts.join('. ');

      // 3. Create trip entity in SQL Server
      final created = await repo.createTrip(
        destinationCity: city,
        name: tripName,
        durationDays: _daysCount,
      );

      if (created == null) {
        throw Exception('Máy chủ không thể tạo bản ghi chuyến đi.');
      }

      // 4. Generate AI itinerary with real places and persistence
      Trip? detailedTrip;
      try {
        detailedTrip = await repo.generateItineraryForTrip(
          created.id,
          userPrompt: userPrompt,
          saveToDb: true,
        );
      } catch (genErr) {
        // Fallback to reload trip detail if generation finished but returned network anomaly
        detailedTrip = await repo.getTripItinerary(created.id) ?? created;
      }

      // 5. Invalidate trips list cache for immediate refresh
      ref.invalidate(tripsListProvider);

      if (!mounted) return;
      Navigator.of(context).pop();

      // 6. Navigate to detail screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TripDetailScreen(
            tripId: created.id,
            initialTrip: detailedTrip ?? created,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tạo lịch trình du lịch AI', style: AppTextStyles.h3),
                      const SizedBox(height: 2),
                      const Text(
                        'Điền thông tin để AI thiết kế lịch trình tối ưu thực tế',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Scrollable Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error message alert
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Field 1: Destination City ───────────────────────────
                    _buildSectionTitle('Điểm đến du lịch', isRequired: true),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        hintText: 'Nhập tên thành phố (ví dụ: Đà Nẵng, Phú Quốc...)',
                        prefixIcon: const Icon(LucideIcons.mapPin, color: AppColors.primary, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                    ),

                    const SizedBox(height: 8),

                    // Quick City Suggestion Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _popularCities.map((c) {
                        final isSelected = _cityController.text.trim().toLowerCase() == c.toLowerCase();
                        return ActionChip(
                          label: Text(c, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : AppColors.textPrimary)),
                          backgroundColor: isSelected ? AppColors.primary : AppColors.surface,
                          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          onPressed: () {
                            setState(() {
                              _cityController.text = c;
                              _errorMessage = null;
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // ── Field 2: Trip Name (Optional) ───────────────────────
                    _buildSectionTitle('Tên chuyến đi (Tùy chọn)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Ví dụ: Nghỉ dưỡng cuối tuần Đà Nẵng',
                        prefixIcon: const Icon(LucideIcons.tag, color: AppColors.textSecondary, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Field 3: Duration / Days count ──────────────────────
                    _buildSectionTitle('Thời gian chuyến đi', isRequired: true),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.calendarDays, color: AppColors.primary, size: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Số ngày du lịch', style: AppTextStyles.label),
                                Text(
                                  'Dự kiến $_daysCount ngày (${_daysCount - 1} đêm)',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: _daysCount > 1
                                ? () => setState(() => _daysCount--)
                                : null,
                            icon: const Icon(Icons.remove, size: 16),
                            style: IconButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.all(4),
                              minimumSize: const Size(32, 32),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '$_daysCount',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: _daysCount < 14
                                ? () => setState(() => _daysCount++)
                                : null,
                            icon: const Icon(Icons.add, size: 16),
                            style: IconButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.all(4),
                              minimumSize: const Size(32, 32),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Field 4: Interests & Travel Style ───────────────────
                    _buildSectionTitle('Sở thích & Phong cách trải nghiệm'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableInterests.map((item) {
                        final id = item['id']!;
                        final label = item['label']!;
                        final icon = item['icon']!;
                        final isSelected = _selectedInterests.contains(id);

                        return FilterChip(
                          selected: isSelected,
                          label: Text('$icon $label', style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                          selectedColor: AppColors.primary.withValues(alpha: 0.15),
                          checkmarkColor: AppColors.primary,
                          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedInterests.add(id);
                              } else {
                                _selectedInterests.remove(id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // ── Field 5: Budget Tier ────────────────────────────────
                    _buildSectionTitle('Mức ngân sách dự kiến'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _budgets.map((b) {
                        final isSelected = _selectedBudget == b;
                        return ChoiceChip(
                          label: Text(b, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppColors.textPrimary)),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                          onSelected: (_) => setState(() => _selectedBudget = b),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // ── Field 6: Schedule Pace ──────────────────────────────
                    _buildSectionTitle('Nhịp độ lịch trình'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _paces.map((p) {
                        final isSelected = _selectedPace == p;
                        return ChoiceChip(
                          label: Text(p, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppColors.textPrimary)),
                          selected: isSelected,
                          selectedColor: const Color(0xFF059669),
                          backgroundColor: AppColors.surface,
                          side: BorderSide(color: isSelected ? const Color(0xFF059669) : AppColors.border),
                          onSelected: (_) => setState(() => _selectedPace = p),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // ── Field 7: Notes / Special Requirements ───────────────
                    _buildSectionTitle('Ghi chú hoặc yêu cầu riêng (Tùy chọn)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Ví dụ: Có người lớn tuổi, ưu tiên hải sản tươi sống...',
                        hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),

                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Action Button ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _handleSubmit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  _isSubmitting
                      ? 'AI đang thiết kế lịch trình thực tế...'
                      : 'Tạo lịch trình bằng AI ngay',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {bool isRequired = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(title, style: AppTextStyles.label.copyWith(fontSize: 13.5)),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          const Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }
}
