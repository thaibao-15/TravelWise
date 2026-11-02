import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/livekit_voice_provider.dart';

class LiveKitVoiceScreen extends ConsumerWidget {
  final int? conversationId;

  const LiveKitVoiceScreen({super.key, this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveKitVoiceProvider);
    final notifier = ref.read(liveKitVoiceProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LiveKit Voice Agent'),
        actions: [
          if (state.state != LiveKitVoiceState.disconnected)
            IconButton(
              tooltip: 'Ngắt kết nối',
              onPressed: notifier.disconnect,
              icon: const Icon(Icons.call_end),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                state.state == LiveKitVoiceState.speaking
                    ? Icons.record_voice_over
                    : Icons.mic,
                size: 96,
                color: _stateColor(state.state),
              ),
              const SizedBox(height: 24),
              Text(
                _stateLabel(state.state),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              if (state.userTranscript.isNotEmpty)
                _TranscriptCard(label: 'Bạn', text: state.userTranscript),
              if (state.assistantTranscript.isNotEmpty)
                _TranscriptCard(
                  label: 'TravelWise AI',
                  text: state.assistantTranscript,
                ),
              const Spacer(),
              if (state.state == LiveKitVoiceState.disconnected ||
                  state.state == LiveKitVoiceState.error)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        notifier.connect(conversationId: conversationId),
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Bắt đầu LiveKit Voice'),
                  ),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: notifier.toggleMicrophone,
                    icon: Icon(
                      state.microphoneEnabled ? Icons.mic : Icons.mic_off,
                    ),
                    label: Text(
                      state.microphoneEnabled
                          ? 'Tắt microphone'
                          : 'Bật microphone',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: notifier.disconnect,
                  child: const Text('Kết thúc phiên'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _stateColor(LiveKitVoiceState state) {
    return switch (state) {
      LiveKitVoiceState.speaking => Colors.teal,
      LiveKitVoiceState.analyzing => Colors.orange,
      LiveKitVoiceState.error => Colors.red,
      LiveKitVoiceState.muted => Colors.grey,
      _ => Colors.blue,
    };
  }

  String _stateLabel(LiveKitVoiceState state) {
    return switch (state) {
      LiveKitVoiceState.disconnected => 'Chưa kết nối',
      LiveKitVoiceState.connecting => 'Đang kết nối LiveKit...',
      LiveKitVoiceState.ready => 'Sẵn sàng lắng nghe',
      LiveKitVoiceState.listening => 'Đang lắng nghe...',
      LiveKitVoiceState.analyzing => 'Đang suy nghĩ...',
      LiveKitVoiceState.speaking => 'TravelWise AI đang nói...',
      LiveKitVoiceState.muted => 'Microphone đang tắt',
      LiveKitVoiceState.reconnecting => 'Đang kết nối lại...',
      LiveKitVoiceState.error => 'Kết nối thất bại',
    };
  }
}

class _TranscriptCard extends StatelessWidget {
  final String label;
  final String text;

  const _TranscriptCard({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(title: Text(label), subtitle: Text(text)),
    );
  }
}
