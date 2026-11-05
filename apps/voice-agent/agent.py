import asyncio
import json
import logging
import math
import re
import struct
import time
from typing import AsyncGenerator, Dict, List, Optional

from livekit import rtc
from livekit.agents import JobContext, stt, vad
from livekit.plugins import silero

from blaze import BlazeSTT, BlazeTTS
from config import config
from coordinator import ConversationCoordinator
from services.rag_client import TravelWiseRAGClient

logger = logging.getLogger("travelwise.voice-agent")


def generate_test_tone_frames(
    frequency: float = 440.0,
    duration: float = 0.6,
    sample_rate: int = 24000,
    amplitude: float = 0.25,
) -> List[rtc.AudioFrame]:
    """Generate 20ms synthetic PCM audio frames for smoke-testing WebRTC audio transmission."""
    frame_duration = 0.02  # 20ms chunks standard for WebRTC
    samples_per_frame = int(sample_rate * frame_duration)
    total_frames = int(duration / frame_duration)

    frames: List[rtc.AudioFrame] = []
    total_samples = 0

    for _ in range(total_frames):
        pcm_bytes = bytearray()
        for _ in range(samples_per_frame):
            sample_val = int(amplitude * 32767 * math.sin(2 * math.pi * frequency * total_samples / sample_rate))
            pcm_bytes.extend(struct.pack("<h", sample_val))
            total_samples += 1

        frame = rtc.AudioFrame(
            data=bytes(pcm_bytes),
            sample_rate=sample_rate,
            num_channels=1,
            samples_per_channel=samples_per_frame,
        )
        frames.append(frame)

    return frames


def extract_conversation_id(room_name: str, metadata_str: Optional[str] = None) -> Optional[int]:
    """Extract conversation_id from participant metadata JSON or room name format."""
    if metadata_str:
        try:
            data = json.loads(metadata_str)
            if "conversation_id" in data and data["conversation_id"] is not None:
                return int(data["conversation_id"])
        except Exception:
            pass

    if room_name.startswith("travelwise_conv_"):
        suffix = room_name[len("travelwise_conv_") :]
        if suffix.isdigit():
            return int(suffix)

    return None


def extract_user_id(participant: rtc.RemoteParticipant) -> Optional[int]:
    """Extract user_id from participant metadata JSON or identity prefix."""
    if participant.metadata:
        try:
            data = json.loads(participant.metadata)
            if "user_id" in data and data["user_id"] is not None:
                return int(data["user_id"])
        except Exception:
            pass

    if participant.identity.startswith("user_"):
        suffix = participant.identity[len("user_") :]
        if suffix.isdigit():
            return int(suffix)

    return None


async def send_room_data(room: Optional[rtc.Room], payload: dict) -> None:
    """Send JSON data packet reliably to all room participants."""
    try:
        if room and room.local_participant:
            raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            await room.local_participant.publish_data(raw, reliable=True)
    except Exception as exc:
        logger.debug("Không thể gửi data packet đến phòng: %s", exc)


async def speak_sentence(
    sentence: str,
    blaze_tts: BlazeTTS,
    audio_source: rtc.AudioSource,
    coordinator: ConversationCoordinator,
    turn_id: int,
    room: Optional[rtc.Room] = None,
) -> bool:
    """Synthesize and push audio frames for one sentence. Returns False if interrupted."""
    clean_text = sentence.strip()
    if not clean_text:
        return True

    if not coordinator.is_turn_valid(turn_id):
        return False

    try:
        logger.debug("🔊 [Blaze TTS] Tổng hợp câu lượt %d: '%s'", turn_id, clean_text)
        chunked_stream = blaze_tts.synthesize(clean_text)

        first_audio_frame = True
        async for audio_event in chunked_stream:
            # Check turn validity on every audio frame to cancel instantaneously
            if not coordinator.is_turn_valid(turn_id):
                logger.info("🛑 [Turn %d Interrupted] Hủy phát câu giữa chừng: '%s'", turn_id, clean_text[:40])
                return False

            if first_audio_frame:
                first_audio_frame = False
                coordinator.record_tts_first_audio(turn_id)
                if room:
                    await send_room_data(room, {
                        "type": "state",
                        "state": "speaking",
                        "text": "Đang trả lời...",
                    })

            await audio_source.capture_frame(audio_event.frame)

        return True

    except asyncio.CancelledError:
        return False
    except Exception as exc:
        logger.error("❌ Lỗi khi phát câu TTS lượt %d: %s", turn_id, exc)
        return False


async def stream_and_speak_rag_response(
    question: str,
    turn_id: int,
    coordinator: ConversationCoordinator,
    rag_client: TravelWiseRAGClient,
    blaze_tts: BlazeTTS,
    audio_source: rtc.AudioSource,
    room: Optional[rtc.Room] = None,
    user_id: Optional[int] = None,
) -> None:
    """Stream LLM response tokens, split into grammatical sentences, and stream to Blaze TTS with minimal latency."""
    logger.info(
        "🧠 [RAG Stream] Bắt đầu stream câu hỏi lượt %d: '%s' (conv_id=%s, user_id=%s)",
        turn_id,
        question,
        coordinator.conversation_id,
        user_id,
    )

    # 1. Notify room that AI is analyzing / thinking
    if room:
        await send_room_data(room, {
            "type": "state",
            "state": "analyzing",
            "text": "Đang suy nghĩ câu trả lời...",
        })

    delimiters = re.compile(r"([.!?\n]+(?:\s+|$))")
    early_tts_word_limit = 5
    buffer = ""
    full_answer_parts: List[str] = []
    first_chunk_recorded = False
    sentence_queue: asyncio.Queue[Optional[asyncio.Queue[Optional[rtc.AudioFrame]]]] = asyncio.Queue()
    sentence_idx = 0
    stream_failed = False

    def enqueue_sentence(s_text: str) -> None:
        nonlocal sentence_idx
        clean_s = s_text.strip()
        if not clean_s or not coordinator.is_turn_valid(turn_id):
            return

        sentence_idx += 1
        curr_idx = sentence_idx
        s_audio_q: asyncio.Queue[Optional[rtc.AudioFrame]] = asyncio.Queue()
        sentence_queue.put_nowait(s_audio_q)

        async def synthesize_worker():
            try:
                if not coordinator.is_turn_valid(turn_id):
                    await s_audio_q.put(None)
                    return
                logger.debug("🔊 [Blaze TTS Pipelined] Pre-synthesizing sentence #%d: '%s'", curr_idx, clean_s[:40])
                chunked_stream = blaze_tts.synthesize(clean_s)
                async for audio_event in chunked_stream:
                    if not coordinator.is_turn_valid(turn_id):
                        break
                    await s_audio_q.put(audio_event.frame)
            except asyncio.CancelledError:
                pass
            except Exception as exc:
                logger.error("❌ Lỗi pre-synthesis câu #%d: %s", curr_idx, exc)
            finally:
                await s_audio_q.put(None)

        producer_task = asyncio.create_task(synthesize_worker(), name=f"TTS.Producer.Turn-{turn_id}.S-{curr_idx}")
        coordinator.register_task(producer_task)

    # Background worker that plays synthesized audio frames sequentially with ZERO inter-sentence gap
    async def tts_playback_worker() -> None:
        first_audio_frame = True
        while True:
            s_audio_q = await sentence_queue.get()
            if s_audio_q is None:
                sentence_queue.task_done()
                break

            if not coordinator.is_turn_valid(turn_id):
                sentence_queue.task_done()
                break

            while True:
                frame = await s_audio_q.get()
                if frame is None:
                    s_audio_q.task_done()
                    break

                if not coordinator.is_turn_valid(turn_id):
                    s_audio_q.task_done()
                    break

                if first_audio_frame:
                    first_audio_frame = False
                    coordinator.record_tts_first_audio(turn_id)
                    if room:
                        await send_room_data(room, {
                            "type": "state",
                            "state": "speaking",
                            "text": "Đang trả lời...",
                        })

                await audio_source.capture_frame(frame)
                s_audio_q.task_done()

            sentence_queue.task_done()
            if not coordinator.is_turn_valid(turn_id):
                break

    tts_task = asyncio.create_task(tts_playback_worker(), name=f"TTS.Playback.Turn-{turn_id}")
    coordinator.register_task(tts_task)

    try:
        token_stream = rag_client.ask_stream(
            question=question,
            conversation_id=coordinator.conversation_id,
            user_id=user_id,
            mode="voice",
            timeout=25.0,
        )

        async for ev in token_stream:
            if not coordinator.is_turn_valid(turn_id):
                logger.info("🛑 [Turn %d] Bị ngắt trong lúc nhận stream từ LLM.", turn_id)
                break

            ev_type = ev.get("type")
            if ev_type == "init":
                new_conv_id = ev.get("conversation_id")
                coordinator.update_conversation_id(new_conv_id)

            elif ev_type == "token":
                if not first_chunk_recorded:
                    first_chunk_recorded = True
                    coordinator.record_llm_first_chunk(turn_id)

                token = ev.get("token", "")
                buffer += token
                parts = delimiters.split(buffer)

                if len(parts) > 1:
                    sentence = (parts[0] + parts[1]).strip()
                    buffer = "".join(parts[2:])

                    if sentence:
                        full_answer_parts.append(sentence)
                        if room:
                            await send_room_data(room, {
                                "type": "transcript",
                                "role": "assistant",
                                "text": " ".join(full_answer_parts),
                                "is_final": False,
                            })
                        # Push to queue for playback worker
                        enqueue_sentence(sentence)
                elif len(buffer.split()) >= early_tts_word_limit:
                    # Start speaking a short phrase before punctuation arrives,
                    # while avoiding one TTS request per generated token.
                    words = buffer.split()
                    sentence = " ".join(words[:early_tts_word_limit]).strip()
                    buffer = " ".join(words[early_tts_word_limit:])
                    if sentence:
                        full_answer_parts.append(sentence)
                        if room:
                            await send_room_data(room, {
                                "type": "transcript",
                                "role": "assistant",
                                "text": " ".join(full_answer_parts),
                                "is_final": False,
                            })
                        enqueue_sentence(sentence)

            elif ev_type == "done":
                new_conv_id = ev.get("conversation_id")
                coordinator.update_conversation_id(new_conv_id)
                if room:
                    await send_room_data(room, {
                        "type": "conversation",
                        "conversation_id": new_conv_id,
                    })
                    await send_room_data(room, {
                        "type": "metadata",
                        "conversation_id": new_conv_id,
                        "planning_context": ev.get("planning_context"),
                        "planning_status": ev.get("planning_status"),
                        "is_ready_to_generate": ev.get("is_ready_to_generate"),
                        "planning_action": ev.get("planning_action"),
                        "media": ev.get("media", []),
                    })

            elif ev_type == "error":
                logger.error("Lỗi từ RAG stream event: %s", ev.get("message"))
                stream_failed = True
                if room:
                    await send_room_data(room, {
                        "type": "error",
                        "message": "Không thể kết nối dịch vụ AI. Vui lòng thử lại.",
                    })
                break

        # Push any remaining sentence in buffer
        remaining = buffer.strip()
        if remaining and coordinator.is_turn_valid(turn_id):
            full_answer_parts.append(remaining)
            if room:
                await send_room_data(room, {
                    "type": "transcript",
                    "role": "assistant",
                    "text": " ".join(full_answer_parts),
                    "is_final": False,
                })
            enqueue_sentence(remaining)

    except asyncio.CancelledError:
        logger.debug("Luồng stream RAG lượt %d bị hủy.", turn_id)
    except Exception as exc:
        logger.error("❌ Lỗi trong stream RAG lượt %d: %s. Thử gọi API fallback.", turn_id, exc)
        if coordinator.is_turn_valid(turn_id) and not first_chunk_recorded:
            try:
                rag_result = await rag_client.ask(
                    question=question,
                    conversation_id=coordinator.conversation_id,
                    user_id=user_id,
                    mode="voice",
                )
                coordinator.record_llm_first_chunk(turn_id)
                answer_text = rag_result.get("answer", "")
                coordinator.update_conversation_id(rag_result.get("conversation_id"))
                if answer_text:
                    full_answer_parts.append(answer_text)
                    enqueue_sentence(answer_text)
            except Exception as fb_err:
                logger.error("❌ Lỗi cả fallback RAG: %s", fb_err)
    finally:
        # Signal queue termination and wait for audio completion
        await sentence_queue.put(None)
        await tts_task

        if coordinator.is_turn_valid(turn_id) and not stream_failed:
            full_answer = " ".join(full_answer_parts).strip()
            coordinator.record_tts_complete(turn_id, full_answer)

            # Publish final complete transcript and ready state to room
            if room:
                await send_room_data(room, {
                    "type": "transcript",
                    "role": "assistant",
                    "text": full_answer,
                    "is_final": True,
                })
                await send_room_data(room, {
                    "type": "state",
                    "state": "ready",
                    "text": None,
                })
        elif coordinator.is_turn_valid(turn_id):
            if room:
                await send_room_data(room, {
                    "type": "state",
                    "state": "ready",
                    "text": None,
                })


async def process_user_audio_with_rag(
    track: rtc.Track,
    participant: rtc.RemoteParticipant,
    room: rtc.Room,
    blaze_stt: BlazeSTT,
    blaze_tts: BlazeTTS,
    rag_client: TravelWiseRAGClient,
    audio_source: rtc.AudioSource,
    initial_conversation_id: Optional[int],
    user_id: Optional[int],
) -> None:
    """End-to-end voice loop with real-time VAD interruption, turn coordination, and streaming sentence TTS."""
    logger.info(
        "🎙️ Bắt đầu luồng hội thoại giọng nói cho người dùng: %s (conv_id=%s, user_id=%s)",
        participant.identity,
        initial_conversation_id,
        user_id,
    )

    coordinator = ConversationCoordinator(
        conversation_id=initial_conversation_id,
        user_id=user_id,
    )
    event_loop = asyncio.get_running_loop()
    control_tasks: set[asyncio.Task] = set()

    def schedule_control_task(coro) -> None:
        if event_loop.is_closed():
            coro.close()
            return
        task = event_loop.create_task(coro)
        control_tasks.add(task)
        task.add_done_callback(control_tasks.discard)

    @room.on("data_received")
    def on_control_data(*args) -> None:
        if not args:
            return
        packet = args[0]
        raw_data = getattr(packet, "data", packet)
        if not isinstance(raw_data, bytes):
            return
        try:
            payload = json.loads(raw_data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return
        if (
            isinstance(payload, dict)
            and payload.get("type") == "command"
            and payload.get("command") == "stop_speaking"
        ):
            logger.info("🛑 Nhận lệnh dừng đọc vật lý từ %s.", participant.identity)
            interrupt_agent_audio("Physical stop button")
            schedule_control_task(
                send_room_data(room, {"type": "state", "state": "ready"})
            )
    audio_stream = rtc.AudioStream(track)
    stt_stream = blaze_stt.stream()

    def interrupt_agent_audio(reason: str) -> None:
        coordinator.handle_interruption(reason=reason)
        audio_source.clear_queue()

    # Keep the start-of-speech window short so barge-in stops TTS at the first
    # detected speech instead of waiting for a complete word.
    vad_model = silero.VAD.load(
        min_speech_duration=0.05,
        min_silence_duration=0.3,
        activation_threshold=0.5,
    )
    vad_stream = vad_model.stream()

    async def forward_audio_to_stt_and_vad() -> None:
        """Push WebRTC audio frames simultaneously into Blaze STT and Silero VAD."""
        try:
            async for event in audio_stream:
                stt_stream.push_frame(event.frame)
                vad_stream.push_frame(event.frame)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error("Lỗi khi chuyển tiếp audio sang STT/VAD: %s", e)
        finally:
            stt_stream.end_input()
            vad_stream.end_input()

    async def monitor_vad_interruption() -> None:
        """Monitor Silero VAD events for end-of-speech and instant user interruptions."""
        try:
            async for vad_event in vad_stream:
                if vad_event.type == vad.VADEventType.START_OF_SPEECH:
                    # Interrupt on the first reliable speech signal while the
                    # agent is speaking; do not wait for a final STT transcript.
                    probability = getattr(vad_event, "probability", 1.0)
                    if coordinator.is_agent_speaking and probability >= 0.5:
                        logger.info(
                            "🛑 [VAD Interruption Detected] Phát hiện tiếng nói người dùng khi Agent đang nói (prob=%.2f)!",
                            probability,
                        )
                        interrupt_agent_audio(
                            f"User started speaking (prob={probability:.2f})"
                        )
                        # Notify frontend that AI was interrupted and is listening again
                        await send_room_data(room, {"type": "state", "state": "ready"})

                elif vad_event.type == vad.VADEventType.END_OF_SPEECH:
                    # User stopped speaking. Record timestamp for latency tracking
                    coordinator.record_user_speech_end(coordinator.current_turn_id)

        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error("Lỗi trong luồng giám sát VAD: %s", e)

    async def consume_stt_and_query_rag() -> None:
        """Receive transcripts from Blaze STT, query streaming Gemini/RAG, and respond via Blaze TTS."""
        try:
            async for speech_event in stt_stream:
                if speech_event.type == stt.SpeechEventType.INTERIM_TRANSCRIPT:
                    transcript = speech_event.alternatives[0].text
                    logger.debug("⏳ [Blaze STT Interim] %s: %s", participant.identity, transcript)
                    if transcript.strip():
                        await send_room_data(room, {
                            "type": "transcript",
                            "role": "user",
                            "text": transcript,
                            "is_final": False,
                        })

                elif speech_event.type == stt.SpeechEventType.FINAL_TRANSCRIPT:
                    transcript = speech_event.alternatives[0].text.strip()
                    if not transcript:
                        continue

                    logger.info("🗣️ [Blaze STT Final] %s: '%s'", participant.identity, transcript)

                    # Publish user transcript to frontend room for live caption display
                    await send_room_data(room, {
                        "type": "transcript",
                        "role": "user",
                        "text": transcript,
                        "is_final": True,
                    })

                    # Start new conversational turn and record STT timing
                    turn_id = coordinator.start_new_turn(question=transcript)
                    coordinator.record_stt_done(turn_id, transcript)

                    # Launch streaming RAG + sentence TTS as a cancellable task
                    turn_task = asyncio.create_task(
                        stream_and_speak_rag_response(
                            question=transcript,
                            turn_id=turn_id,
                            coordinator=coordinator,
                            rag_client=rag_client,
                            blaze_tts=blaze_tts,
                            audio_source=audio_source,
                            room=room,
                            user_id=coordinator.user_id,
                        ),
                        name=f"Turn-{turn_id}.Response",
                    )
                    coordinator.register_task(turn_task)

        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error("Lỗi trong luồng xử lý STT: %s", e)
            await send_room_data(room, {
                "type": "state",
                "state": "error",
                "error": "Kết nối nhận diện giọng nói bị gián đoạn. Vui lòng thử kết nối lại.",
            })

    tasks = [
        asyncio.create_task(forward_audio_to_stt_and_vad(), name="Audio.forward"),
        asyncio.create_task(monitor_vad_interruption(), name="Audio.vad_monitor"),
        asyncio.create_task(consume_stt_and_query_rag(), name="Audio.stt_consume"),
    ]

    try:
        await asyncio.gather(*tasks)
    finally:
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for t in list(control_tasks):
            t.cancel()
        await asyncio.gather(*control_tasks, return_exceptions=True)
        await stt_stream.aclose()
        await vad_stream.aclose()
        logger.info("🛑 Đã đóng phiên hội thoại giọng nói cho: %s", participant.identity)


async def entrypoint(ctx: JobContext) -> None:
    """Entry point when LiveKit Server dispatches a job for this agent."""
    logger.info("==================================================")
    logger.info("🚀 TravelWise Voice Agent nhận job ID: %s", ctx.job.id)
    logger.info("📍 Phòng WebRTC: %s", ctx.room.name)
    logger.info("==================================================")

    # 1. Connect to the LiveKit Room
    await ctx.connect()
    logger.info("✅ Agent đã tham gia phòng '%s' thành công.", ctx.room.name)

    # 2. Register graceful shutdown hook
    async def on_shutdown():
        logger.info("🛑 Đang đóng kết nối Agent cho phòng %s...", ctx.room.name)

    ctx.add_shutdown_callback(on_shutdown)

    # 3. Initialize Services (Blaze STT, Blaze TTS, TravelWise RAG Client)
    blaze_stt = BlazeSTT(
        api_key=config.BLAZE_API_KEY,
        ws_url=config.BLAZE_STT_WS_URL,
        model=config.BLAZE_STT_MODEL,
        language=config.BLAZE_STT_LANGUAGE,
        sample_rate=config.BLAZE_STT_SAMPLE_RATE,
    )

    blaze_tts = BlazeTTS(
        api_key=config.BLAZE_API_KEY,
        ws_url=config.BLAZE_TTS_WS_URL,
        speaker_id=config.BLAZE_TTS_SPEAKER_ID,
        model=config.BLAZE_TTS_MODEL,
        speed=config.BLAZE_TTS_SPEED,
        audio_quality=config.BLAZE_TTS_AUDIO_QUALITY,
        audio_format=config.BLAZE_TTS_AUDIO_FORMAT,
        normalization=config.BLAZE_TTS_NORMALIZATION,
        sample_rate=24000,
        num_channels=1,
    )

    @ctx.room.on("data_received")
    def on_voice_settings_data(*args) -> None:
        if not args:
            return
        packet = args[0]
        raw_data = getattr(packet, "data", packet)
        if not isinstance(raw_data, bytes):
            return
        try:
            payload = json.loads(raw_data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return
        if (
            not isinstance(payload, dict)
            or payload.get("type") != "command"
            or payload.get("command") != "set_voice_settings"
        ):
            return

        try:
            speaker_id = payload.get("speaker_id")
            speed = payload.get("speed")
            if not isinstance(speaker_id, str) or not isinstance(speed, str):
                raise ValueError("Invalid voice settings payload.")
            blaze_tts.update_voice_settings(speaker_id=speaker_id, speed=speed)
            logger.info(
                "Cập nhật giọng TTS: speaker=%s, speed=%s",
                blaze_tts.speaker_id,
                blaze_tts.speed,
            )
            response = {
                "type": "voice_settings",
                "status": "applied",
                "speaker_id": blaze_tts.speaker_id,
                "speed": blaze_tts.speed,
            }
        except ValueError as exc:
            logger.warning("Từ chối cài đặt giọng TTS: %s", exc)
            response = {
                "type": "voice_settings",
                "status": "rejected",
            }
        asyncio.create_task(send_room_data(ctx.room, response))

    rag_client = TravelWiseRAGClient(
        base_url=config.BACKEND_API_URL,
        jwt_secret=config.JWT_SECRET,
        jwt_algorithm=config.JWT_ALGORITHM,
    )

    # 4. Create and publish WebRTC audio track (24kHz Mono)
    sample_rate = 24000
    audio_source = rtc.AudioSource(sample_rate=sample_rate, num_channels=1)
    audio_track = rtc.LocalAudioTrack.create_audio_track("travelwise-agent-audio", audio_source)

    publish_options = rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE)
    publication = await ctx.room.local_participant.publish_track(audio_track, publish_options)
    logger.info("🎙️ Agent đã publish Audio Track vào phòng: %s", publication.sid)

    # 5. Extract room-level initial conversation_id
    initial_conversation_id = extract_conversation_id(ctx.room.name)

    # 6. Listen for user audio tracks and attach RAG pipeline
    user_audio_tasks = []
    handled_track_ids: set[str] = set()
    participant_left = asyncio.Event()

    @ctx.room.on("participant_disconnected")
    def on_participant_disconnected(participant: rtc.RemoteParticipant):
        if not ctx.room.remote_participants:
            logger.info(
                "👋 Người dùng đã rời phòng '%s'; kết thúc job để phiên mới được tạo sạch.",
                ctx.room.name,
            )
            participant_left.set()

    def attach_user_audio(
        track: rtc.Track,
        participant: rtc.RemoteParticipant,
    ) -> None:
        if track.kind != rtc.TrackKind.KIND_AUDIO or track.sid in handled_track_ids:
            return

        handled_track_ids.add(track.sid)
        logger.info(
            "🎵 Nhận được Audio Track từ %s (Track ID: %s)",
            participant.identity,
            track.sid,
        )
        user_id = extract_user_id(participant)
        conv_id = extract_conversation_id(
            ctx.room.name,
            participant.metadata,
        ) or initial_conversation_id
        task = asyncio.create_task(
            process_user_audio_with_rag(
                track=track,
                participant=participant,
                room=ctx.room,
                blaze_stt=blaze_stt,
                blaze_tts=blaze_tts,
                rag_client=rag_client,
                audio_source=audio_source,
                initial_conversation_id=conv_id,
                user_id=user_id,
            )
        )
        user_audio_tasks.append(task)

    @ctx.room.on("track_subscribed")
    def on_track_subscribed(
        track: rtc.Track,
        pub: rtc.TrackPublication,
        participant: rtc.RemoteParticipant,
    ):
        attach_user_audio(track, participant)

    # The user may have published before the handler above was registered.
    # Attach already-subscribed audio tracks so the first utterance is not lost.
    for participant in ctx.room.remote_participants.values():
        for publication in participant.track_publications.values():
            if publication.kind != rtc.TrackKind.KIND_AUDIO:
                continue
            if publication.track is not None:
                attach_user_audio(publication.track, participant)
            elif not publication.subscribed:
                await publication.set_subscribed(True)

    # 7. Play welcome voice and publish greeting transcript
    async def play_welcome_voice():
        await asyncio.sleep(0.5)  # Wait briefly for participants to subscribe
        welcome_text = "Chào bạn! Tôi là TravelWise AI. Bạn muốn khám phá địa điểm hay lên lịch trình du lịch nào hôm nay?"
        await send_room_data(ctx.room, {
            "type": "transcript",
            "role": "assistant",
            "text": welcome_text,
            "is_final": True,
        })
        if config.BLAZE_API_KEY:
            try:
                dummy_coordinator = ConversationCoordinator()
                dummy_turn_id = dummy_coordinator.start_new_turn(welcome_text)
                await speak_sentence(
                    sentence=welcome_text,
                    blaze_tts=blaze_tts,
                    audio_source=audio_source,
                    coordinator=dummy_coordinator,
                    turn_id=dummy_turn_id,
                    room=ctx.room,
                )
            except Exception as e:
                logger.error("Lỗi phát giọng chào: %s", e)
        else:
            logger.warning("BLAZE_API_KEY chưa có, phát âm thanh thử nghiệm 440Hz thay thế.")
            tone_frames = generate_test_tone_frames(frequency=440.0, duration=0.6, sample_rate=sample_rate)
            for frame in tone_frames:
                await audio_source.capture_frame(frame)
                await asyncio.sleep(0.02)

    welcome_task = asyncio.create_task(play_welcome_voice(), name="Welcome.voice")

    # 8. Wait for participant and keep room alive
    try:
        participant = await ctx.wait_for_participant()
        logger.info("👤 Người dùng đã kết nối vào phòng: %s (%s)", participant.identity, participant.name)
        while ctx.room.isconnected() and not participant_left.is_set():
            await asyncio.sleep(1.0)
    except asyncio.CancelledError:
        logger.info("Job bị hủy hoặc phòng đã đóng.")
    finally:
        welcome_task.cancel()
        await asyncio.gather(welcome_task, return_exceptions=True)
        for t in user_audio_tasks:
            t.cancel()
        await asyncio.gather(*user_audio_tasks, return_exceptions=True)
        logger.info("🏁 Phiên làm việc phòng '%s' kết thúc.", ctx.room.name)
