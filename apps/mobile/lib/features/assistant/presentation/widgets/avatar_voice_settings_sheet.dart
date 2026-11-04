import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/network/dio_client.dart';
import '../providers/avatar_state_provider.dart';
import '../providers/voice_assistant_provider.dart';

/// Pre-configured regional TTS voices for TravelWise AI
class TtsVoiceOption {
  final String id;
  final String name;
  final String region;
  final String gender;
  final String description;
  final String sampleText;

  const TtsVoiceOption({
    required this.id,
    required this.name,
    required this.region,
    required this.gender,
    required this.description,
    this.sampleText = 'Xin chào bạn! Mình là trợ lý du lịch AI TravelWise.',
  });
}

/// Fallback offline voices if API is unavailable
const List<TtsVoiceOption> kAvailableVoices = [
  TtsVoiceOption(
    id: 'DaNang-Nu-1-BL',
    name: 'Nữ Đà Nẵng',
    region: 'Miền Trung',
    gender: 'Nữ',
    description: 'Trong trẻo, ngọt ngào (Giọng mặc định của Linh AI)',
    sampleText: 'Xin chào bạn! Mình là Linh, trợ lý du lịch Đà Nẵng của bạn nè!',
  ),
  TtsVoiceOption(
    id: 'HaNoi-Nu-1-BL',
    name: 'Nữ Hà Nội',
    region: 'Miền Bắc',
    gender: 'Nữ',
    description: 'Trang nhã, rõ ràng, phát âm chuẩn Thủ đô',
    sampleText: 'Chào bạn, mình rất vui được đồng hành cùng bạn trên chuyến đi này.',
  ),
  TtsVoiceOption(
    id: 'HaNoi-Nam-1-BL',
    name: 'Nam Hà Nội',
    region: 'Miền Bắc',
    gender: 'Nam',
    description: 'Trầm ấm, chững chạc, truyền cảm',
    sampleText: 'Chào bạn! Tôi là trợ lý du lịch thông minh của TravelWise.',
  ),
  TtsVoiceOption(
    id: 'SaiGon-Nu-1-BL',
    name: 'Nữ Sài Gòn',
    region: 'Miền Nam',
    gender: 'Nữ',
    description: 'Dễ thương, gần gũi, năng động hiện đại',
    sampleText: 'Hế lô bạn nha! Hôm nay tụi mình đi đâu chơi nè?',
  ),
  TtsVoiceOption(
    id: 'SaiGon-Nam-1-BL',
    name: 'Nam Sài Gòn',
    region: 'Miền Nam',
    gender: 'Nam',
    description: 'Nhiệt tình, ấm áp, thân thiện',
    sampleText: 'Chào bạn! Cùng TravelWise lên lịch trình khám phá nhé!',
  ),
  TtsVoiceOption(
    id: 'Hue-Nu-1-BL',
    name: 'Nữ Huế',
    region: 'Miền Trung',
    gender: 'Nữ',
    description: 'Dịu dàng, nhẹ nhàng, sâu lắng cố đô',
    sampleText: 'Dạ, em chào anh chị, mời anh chị cùng khám phá mảnh đất cố đô.',
  ),
];

/// FutureProvider that fetches the dynamic voices list from Backend /api/v1/tts/voices
/// (which integrates directly with https://api.blaze.vn/v1/audio/voices).
final apiTtsVoicesProvider = FutureProvider<List<TtsVoiceOption>>((ref) async {
  try {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final response = await dio.get('/api/v1/tts/voices?language=vi');
    if (response.statusCode == 200 && response.data is List) {
      final list = response.data as List;
      final parsed = <TtsVoiceOption>[];

      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final voiceId = item['voice_id']?.toString() ?? '';
          if (voiceId.isEmpty) continue;

          final name = item['name']?.toString() ?? voiceId;
          final genderRaw = item['gender']?.toString().toLowerCase() ?? '';
          final gender = (genderRaw == 'male' || genderRaw == 'nam') ? 'Nam' : 'Nữ';
          final province = item['province']?.toString() ?? '';

          String region = 'Miền Trung';
          if (province.contains('Hà Nội') ||
              province.contains('Bắc') ||
              province.contains('Hải Phòng') ||
              province.contains('Quảng Ninh')) {
            region = 'Miền Bắc';
          } else if (province.contains('Hồ Chí Minh') ||
              province.contains('Sài Gòn') ||
              province.contains('Nam') ||
              province.contains('Cần Thơ') ||
              province.contains('Đồng Nai') ||
              province.contains('Bình Dương')) {
            region = 'Miền Nam';
          } else if (province.contains('Đà Nẵng') ||
              province.contains('Huế') ||
              province.contains('Quảng') ||
              province.contains('Khánh Hòa') ||
              province.contains('Nha Trang')) {
            region = 'Miền Trung';
          }

          final desc = item['description']?.toString() ??
              (province.isNotEmpty ? 'Giọng $gender ($province)' : 'Giọng $name');

          parsed.add(
            TtsVoiceOption(
              id: voiceId,
              name: name,
              region: region,
              gender: gender,
              description: desc,
              sampleText: 'Xin chào bạn! Mình là $name, trợ lý du lịch của bạn.',
            ),
          );
        }
      }

      if (parsed.isNotEmpty) {
        return parsed;
      }
    }
  } catch (_) {
    // Gracefully fallback to static list
  }
  return kAvailableVoices;
});

/// Bottom sheet dialog to customize 3D AI Avatar model & TTS voice
class AvatarVoiceSettingsSheet extends ConsumerStatefulWidget {
  const AvatarVoiceSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AvatarVoiceSettingsSheet(),
    );
  }

  @override
  ConsumerState<AvatarVoiceSettingsSheet> createState() =>
      _AvatarVoiceSettingsSheetState();
}

class _AvatarVoiceSettingsSheetState
    extends ConsumerState<AvatarVoiceSettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedRegionFilter = 'Tất cả';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _previewingSpeakerId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarState = ref.watch(avatar3dStateProvider);
    final voiceState = ref.watch(voiceAssistantProvider);
    final avatarNotifier = ref.read(avatar3dStateProvider.notifier);
    final voiceNotifier = ref.read(voiceAssistantProvider.notifier);
    final voicesAsync = ref.watch(apiTtsVoicesProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cài đặt Trợ lý AI',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Chọn nhân vật 3D và giọng nói du lịch Blaze AI',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey[600],
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.view_in_ar_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Nhân vật 3D'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.record_voice_over_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Giọng nói & Tốc độ'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: 3D AVATAR SELECTION
                _buildAvatarTab(avatarState, avatarNotifier),

                // TAB 2: VOICE & SPEED SELECTION
                _buildVoiceTab(voiceState, voiceNotifier, voicesAsync),
              ],
            ),
          ),

          // Footer
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    final voicesList = voicesAsync.asData?.value ?? kAvailableVoices;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Đã áp dụng: ${avatarState.modelName} • ${_getVoiceName(voiceState.speakerId, voicesList)} (${voiceState.ttsSpeed}x)',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.primary,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Hoàn tất',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarTab(
    Avatar3dState avatarState,
    Avatar3dNotifier avatarNotifier,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
      children: [
        Text(
          'Chọn hình mẫu nhân vật hướng dẫn viên 3D:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        ...kAvailableAvatars.map((avatar) {
          final isSelected = avatarState.selectedModelPath == avatar.assetPath;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () {
                avatarNotifier.selectAvatarModel(
                  avatar.assetPath,
                  modelName: avatar.name,
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.grey[250] ?? const Color(0xFFE2E8F0),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isSelected ? 0.06 : 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar Icon Box
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [AppColors.primary, AppColors.secondary]
                              : [Colors.grey[200]!, Colors.grey[300]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        avatar.iconEmoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                avatar.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.12)
                                      : Colors.grey[150] ?? const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  avatar.tag,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? AppColors.primary : Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            avatar.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.radio_button_off,
                      color: isSelected ? AppColors.primary : Colors.grey[400],
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tất cả nhân vật 3D đều được render trực tiếp offline với 60fps kèm cử động nhép môi đồng bộ theo âm thanh.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceTab(
    VoiceAssistantState voiceState,
    VoiceAssistantNotifier voiceNotifier,
    AsyncValue<List<TtsVoiceOption>> voicesAsync,
  ) {
    final regions = ['Tất cả', 'Miền Bắc', 'Miền Trung', 'Miền Nam'];
    final allVoices = voicesAsync.value ?? kAvailableVoices;

    var filteredVoices = _selectedRegionFilter == 'Tất cả'
        ? allVoices
        : allVoices.where((v) => v.region == _selectedRegionFilter).toList();

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filteredVoices = filteredVoices
          .where(
            (v) =>
                v.name.toLowerCase().contains(q) ||
                v.id.toLowerCase().contains(q) ||
                v.description.toLowerCase().contains(q) ||
                v.region.toLowerCase().contains(q),
          )
          .toList();
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
      children: [
        // 1. SPEED SELECTOR
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tốc độ giọng nói AI:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            Row(
              children: ['1.0', '1.2', '1.5'].map((spd) {
                final isSelected = voiceState.ttsSpeed == spd;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text('${spd}x'),
                    selected: isSelected,
                    onSelected: (_) => voiceNotifier.setTtsSpeed(spd),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppColors.primary : Colors.grey[700],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        const Divider(height: 20),

        // 2. SEARCH BOX
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Tìm giọng theo tên (Thúy Vy, Đà Nẵng, Hà Nội)...',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : (voicesAsync.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // 3. REGION FILTER & COUNT
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Wrap(
              spacing: 6,
              children: regions.map((region) {
                final isSelected = _selectedRegionFilter == region;
                return ChoiceChip(
                  label: Text(region),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedRegionFilter = region;
                    });
                  },
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey[700],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
            Text(
              '${filteredVoices.length} giọng',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 4. VOICE LIST
        if (filteredVoices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Không tìm thấy giọng nói phù hợp với "$_searchQuery"',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
          )
        else
          ...filteredVoices.map((voice) {
            final isSelected = voiceState.speakerId == voice.id;
            final isPreviewing = _previewingSpeakerId == voice.id;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () {
                  voiceNotifier.setSpeakerId(voice.id);
                },
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isSelected ? 0.06 : 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Voice Mic Icon Box
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          voice.gender == 'Nữ' ? Icons.face : Icons.face_6,
                          color: isSelected ? AppColors.primary : Colors.grey[600],
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    voice.name,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: voice.gender == 'Nữ'
                                        ? const Color(0xFFFCE7F3)
                                        : const Color(0xFFE0E7FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${voice.gender} • ${voice.region}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: voice.gender == 'Nữ'
                                          ? const Color(0xFFBE185D)
                                          : const Color(0xFF4338CA),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              voice.description,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Preview Button
                      IconButton(
                        tooltip: 'Nghe thử giọng',
                        icon: isPreviewing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.volume_up_rounded,
                                color: isSelected ? AppColors.primary : Colors.grey[500],
                                size: 22,
                              ),
                        onPressed: () async {
                          setState(() {
                            _previewingSpeakerId = voice.id;
                          });
                          try {
                            await voiceNotifier.previewVoiceSample(
                              voice.id,
                              sampleText: voice.sampleText,
                            );
                          } finally {
                            if (mounted) {
                              setState(() {
                                _previewingSpeakerId = null;
                              });
                            }
                          }
                        },
                      ),

                      // Selection radio icon
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_off,
                        color: isSelected ? AppColors.primary : Colors.grey[400],
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  String _getVoiceName(String speakerId, List<TtsVoiceOption> list) {
    final match = list.firstWhere(
      (v) => v.id == speakerId,
      orElse: () => list.isNotEmpty ? list.first : kAvailableVoices.first,
    );
    return match.name;
  }
}
