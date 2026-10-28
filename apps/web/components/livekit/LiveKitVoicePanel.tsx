"use client";

import React, { useState, useEffect, useRef, useCallback } from "react";
import {
  LiveKitRoom,
  RoomAudioRenderer,
  useConnectionState,
  useLocalParticipant,
  useRemoteParticipants,
  useRoomContext,
  useSpeakingParticipants,
} from "@livekit/components-react";
import { ConnectionState, RoomEvent } from "livekit-client";
import { livekitService } from "@/services/livekit.service";
import { LiveKitConnectionStatus, LiveKitTokenResponse } from "@/types/livekit";
import { ApiError } from "@/services/api";

export type VoiceCompanionState =
  | "connecting"
  | "listening"
  | "analyzing"
  | "speaking"
  | "ready"
  | "muted";

interface LiveKitVoicePanelProps {
  conversationId?: number | null;
  roomName?: string | null;
  autoConnect?: boolean;
  onSessionStarted?: (data: LiveKitTokenResponse) => void;
  onSessionEnded?: () => void;
  onSendMessage?: (text: string) => Promise<string | null | void>;
  latestUserText?: string;
  latestAssistantText?: string;
}

/**
 * Child controller component inside LiveKitRoom context
 * Pure WebRTC Voice Companion (Living Voice Orb, zero transcript/clutter)
 */
function RoomController({
  onDisconnect,
}: {
  onDisconnect: () => void;
  onSendMessage?: (text: string) => Promise<string | null | void>;
  latestUserText?: string;
  latestAssistantText?: string;
}) {
  const room = useRoomContext();
  const connectionState = useConnectionState();
  const { localParticipant, isMicrophoneEnabled } = useLocalParticipant();
  const remoteParticipants = useRemoteParticipants();

  const [isTogglingMic, setIsTogglingMic] = useState(false);
  const [isDisconnecting, setIsDisconnecting] = useState(false);
  const [micError, setMicError] = useState<string | null>(null);

  // Check speech activity directly from WebRTC audio tracks
  const isAgentSpeaking = remoteParticipants.some((p) => p.isSpeaking);
  const isUserSpeaking = Boolean(localParticipant?.isSpeaking);

  // Explicitly disconnect room and turn off microphone hardware
  const handleDisconnectClick = useCallback(async () => {
    setIsDisconnecting(true);
    try {
      if (localParticipant) {
        await localParticipant.setMicrophoneEnabled(false);
      }
      if (room) {
        await room.disconnect();
      }
    } catch (err) {
      console.warn("Lỗi khi ngắt kết nối LiveKit room:", err);
    } finally {
      onDisconnect();
    }
  }, [localParticipant, room, onDisconnect]);

  // Handle toggle microphone with browser permission error handling
  const handleToggleMic = useCallback(async () => {
    if (!localParticipant) return;
    setIsTogglingMic(true);
    setMicError(null);

    const targetState = !isMicrophoneEnabled;
    try {
      await localParticipant.setMicrophoneEnabled(targetState);
    } catch (err: unknown) {
      let errMsg = "Không thể truy cập microphone.";
      if (err instanceof DOMException) {
        if (err.name === "NotAllowedError" || err.name === "PermissionDeniedError") {
          errMsg = "Quyền truy cập microphone bị từ chối. Hãy cho phép micro trong cài đặt trình duyệt.";
        } else if (err.name === "NotFoundError" || err.name === "DevicesNotFoundError") {
          errMsg = "Không tìm thấy thiết bị microphone nào trên máy của bạn.";
        } else if (err.name === "NotReadableError" || err.name === "TrackStartError") {
          errMsg = "Microphone đang bị chiếm dụng bởi ứng dụng khác.";
        }
      }
      setMicError(errMsg);
    } finally {
      setIsTogglingMic(false);
    }
  }, [localParticipant, isMicrophoneEnabled]);

  const isConnected = connectionState === ConnectionState.Connected;

  // Real-time Voice State based strictly on WebRTC audio stream status
  const voiceState: VoiceCompanionState = !isConnected
    ? "connecting"
    : isAgentSpeaking
    ? "speaking"
    : isUserSpeaking
    ? "listening"
    : !isMicrophoneEnabled
    ? "muted"
    : "ready";

  return (
    <div className="flex flex-col items-center text-center w-full max-w-md mx-auto pt-4 pb-8 animate-in fade-in duration-300">
      {/* Realtime Status Pill */}
      <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-slate-900/80 border border-slate-800 backdrop-blur-md shadow-lg mb-8">
        <span className="relative flex h-2.5 w-2.5">
          {voiceState === "speaking" ? (
            <>
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-cyan-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-cyan-500"></span>
            </>
          ) : voiceState === "listening" ? (
            <>
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-500"></span>
            </>
          ) : voiceState === "muted" ? (
            <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-slate-500"></span>
          ) : (
            <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-teal-400"></span>
          )}
        </span>
        <span className="text-xs font-semibold text-slate-200">
          {voiceState === "speaking"
            ? "TravelWise AI đang nói..."
            : voiceState === "listening"
            ? "Đang lắng nghe bạn..."
            : voiceState === "muted"
            ? "Microphone đang tắt tiếng"
            : "LiveKit Audio • Sẵn sàng trò chuyện"}
        </span>
      </div>

      {/* Living Voice Orb (Centerpiece) */}
      <div className="relative flex items-center justify-center my-6">
        {/* Ripple Wave Rings when Speaking or Listening */}
        {voiceState === "listening" && (
          <>
            <div className="absolute w-64 h-64 sm:w-72 sm:h-72 rounded-full border border-emerald-500/30 animate-ping opacity-50 pointer-events-none" />
            <div className="absolute w-80 h-80 sm:w-96 sm:h-96 rounded-full border border-teal-500/20 animate-pulse opacity-60 pointer-events-none" />
          </>
        )}

        {voiceState === "speaking" && (
          <>
            <div className="absolute w-72 h-72 sm:w-88 sm:h-88 rounded-full bg-cyan-500/20 blur-3xl animate-pulse pointer-events-none" />
            <div className="absolute w-88 h-88 sm:w-[420px] sm:h-[420px] rounded-full border border-cyan-400/30 animate-ping opacity-40 pointer-events-none" />
          </>
        )}

        {voiceState === "ready" && (
          <div className="absolute w-64 h-64 rounded-full bg-teal-500/15 blur-2xl animate-pulse pointer-events-none" />
        )}

        {/* Central Living Sphere (Click to toggle Mic) */}
        <button
          type="button"
          onClick={handleToggleMic}
          className={`relative flex items-center justify-center w-44 h-44 sm:w-56 sm:h-56 rounded-full shadow-2xl transition-all duration-700 cursor-pointer select-none group active:scale-95 ${
            voiceState === "speaking"
              ? "bg-gradient-to-tr from-cyan-500 via-teal-400 to-emerald-400 shadow-cyan-500/50 scale-105"
              : voiceState === "listening"
              ? "bg-gradient-to-tr from-emerald-400 via-teal-400 to-cyan-500 shadow-emerald-500/60 scale-100 ring-4 ring-emerald-500/25"
              : voiceState === "muted"
              ? "bg-slate-800 text-slate-500 border border-slate-700 shadow-slate-900/50 scale-95"
              : "bg-gradient-to-tr from-teal-500 via-teal-400 to-emerald-500 shadow-teal-500/50 hover:scale-102"
          }`}
          title={isMicrophoneEnabled ? "Nhấn để tắt micro" : "Nhấn để bật micro"}
        >
          {voiceState === "speaking" ? (
            /* Equalizer Sound Waves when AI speaks */
            <div className="flex items-center gap-1.5 h-12">
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.4s] h-6" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.2s] h-10" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce h-12" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.1s] h-9" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.3s] h-7" />
            </div>
          ) : voiceState === "listening" ? (
            /* Active Microphone icon with pulse */
            <svg className="w-14 h-14 sm:w-16 sm:h-16 text-slate-950 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          ) : voiceState === "muted" ? (
            /* Muted Mic Icon */
            <svg className="w-12 h-12 sm:w-14 sm:h-14 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              <line x1="3" y1="3" x2="21" y2="21" stroke="currentColor" strokeWidth="2" />
            </svg>
          ) : (
            /* Standby Friendly Mic Icon */
            <svg className="w-14 h-14 sm:w-16 sm:h-16 text-slate-950 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          )}
        </button>
      </div>

      {/* Mic Permission Warning */}
      {micError && (
        <div className="mt-4 p-3 bg-rose-500/10 border border-rose-500/30 rounded-2xl text-rose-300 text-xs flex items-center justify-between max-w-sm w-full">
          <span>⚠️ {micError}</span>
          <button
            onClick={() => setMicError(null)}
            className="text-rose-400 hover:text-rose-200 ml-2 font-bold cursor-pointer"
          >
            ✕
          </button>
        </div>
      )}

      {/* Floating Action Buttons */}
      <div className="flex items-center justify-center gap-5 mt-6">
        {/* Toggle Mic Button */}
        <button
          type="button"
          onClick={handleToggleMic}
          disabled={!isConnected || isTogglingMic}
          className={`flex items-center justify-center w-14 h-14 rounded-2xl shadow-xl transition-all duration-200 active:scale-95 cursor-pointer ${
            !isMicrophoneEnabled
              ? "bg-slate-800 text-slate-400 border border-slate-700 hover:text-white"
              : "bg-teal-500/20 text-teal-300 border border-teal-500/50 shadow-teal-500/20 hover:bg-teal-500/30 ring-2 ring-teal-500/20"
          } disabled:opacity-50`}
          title={isMicrophoneEnabled ? "Tắt microphone" : "Bật microphone"}
        >
          {isMicrophoneEnabled ? (
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          ) : (
            <svg className="w-6 h-6 text-rose-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              <line x1="3" y1="3" x2="21" y2="21" stroke="currentColor" strokeWidth="2" />
            </svg>
          )}
        </button>

        {/* End Call Button */}
        <button
          type="button"
          onClick={handleDisconnectClick}
          disabled={isDisconnecting}
          className="flex items-center justify-center w-14 h-14 rounded-2xl bg-rose-600/90 hover:bg-rose-500 text-white shadow-xl shadow-rose-600/30 transition-all duration-200 active:scale-95 cursor-pointer disabled:opacity-50"
          title="Kết thúc cuộc gọi thoại"
        >
          <svg className="w-6 h-6 rotate-[135deg]" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6.62 10.79a15.053 15.053 0 006.59 6.59l2.2-2.2a1 1 0 011.01-.24c1.12.37 2.33.57 3.58.57a1 1 0 011 1V20a1 1 0 01-1 1A17 17 0 013 4a1 1 0 011-1h3.5a1 1 0 011 1c0 1.25.2 2.46.57 3.58a1 1 0 01-.24 1.01l-2.21 2.2z" />
          </svg>
        </button>
      </div>
    </div>
  );
}

/**
 * Main LiveKitVoicePanel Component
 */
export function LiveKitVoicePanel({
  conversationId,
  roomName,
  autoConnect = true,
  onSessionStarted,
  onSessionEnded,
  onSendMessage,
  latestUserText,
  latestAssistantText,
}: LiveKitVoicePanelProps) {
  const [status, setStatus] = useState<LiveKitConnectionStatus>("disconnected");
  const [tokenData, setTokenData] = useState<LiveKitTokenResponse | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const isUnmountedRef = useRef(false);
  const hasAutoConnectedRef = useRef(false);

  useEffect(() => {
    isUnmountedRef.current = false;
    return () => {
      isUnmountedRef.current = true;
    };
  }, []);

  // Connect to LiveKit Room
  const handleConnect = useCallback(async () => {
    hasAutoConnectedRef.current = true;
    setErrorMessage(null);
    setStatus("connecting");

    try {
      let data;
      try {
        data = await livekitService.getRoomToken(conversationId, roomName);
      } catch (tokenErr: unknown) {
        // If 403 Forbidden because this conversation belongs to another user,
        // fallback gracefully by requesting a fresh conversation for current user!
        if (
          tokenErr instanceof ApiError &&
          tokenErr.status === 403 &&
          conversationId !== null
        ) {
          console.warn(
            `Conversation ${conversationId} is forbidden for current user. Creating a new conversation session.`
          );
          data = await livekitService.getRoomToken(null, roomName);
          if (typeof window !== "undefined" && data.conversation_id) {
            const currentUrl = new URL(window.location.href);
            currentUrl.searchParams.set("conversation_id", String(data.conversation_id));
            window.history.replaceState(null, "", currentUrl.toString());
          }
        } else {
          throw tokenErr;
        }
      }

      if (isUnmountedRef.current) return;

      setTokenData(data);
      setStatus("connected");
      onSessionStarted?.(data);
    } catch (err: unknown) {
      if (isUnmountedRef.current) return;
      setStatus("error");
      let msg = "Không thể kết nối máy chủ LiveKit thoại.";
      if (err instanceof ApiError) {
        msg = err.message;
      } else if (err instanceof Error) {
        msg = err.message;
      }
      setErrorMessage(msg);
    }
  }, [conversationId, roomName, onSessionStarted]);

  // Disconnect and Leave Room (explicitly stops auto-connect from firing again)
  const handleDisconnect = useCallback(() => {
    hasAutoConnectedRef.current = true;
    setTokenData(null);
    setStatus("disconnected");
    onSessionEnded?.();
  }, [onSessionEnded]);

  // Auto connect ONLY ONCE on mount if autoConnect is enabled
  useEffect(() => {
    if (autoConnect && !hasAutoConnectedRef.current && status === "disconnected" && !tokenData) {
      hasAutoConnectedRef.current = true;
      handleConnect();
    }
  }, [autoConnect, handleConnect, status, tokenData]);

  return (
    <div className="w-full flex flex-col items-center justify-center">
      {/* Error Alert */}
      {errorMessage && (
        <div className="mb-4 p-4 bg-rose-500/10 border border-rose-500/30 rounded-2xl text-rose-300 text-xs flex items-center justify-between max-w-md w-full">
          <span>❌ {errorMessage}</span>
          <button
            type="button"
            onClick={handleConnect}
            className="px-2.5 py-1 bg-rose-500/20 hover:bg-rose-500/30 rounded-lg text-rose-200 font-semibold cursor-pointer"
          >
            Thử lại
          </button>
        </div>
      )}

      {/* Main Connection View */}
      {tokenData && status === "connected" ? (
        <LiveKitRoom
          serverUrl={tokenData.server_url}
          token={tokenData.token}
          connect={true}
          audio={true}
          video={false}
          onDisconnected={handleDisconnect}
          onError={(err) => {
            setErrorMessage(`Lỗi WebRTC: ${err.message}`);
            setStatus("error");
          }}
        >
          {/* Native browser audio output from remote tracks */}
          <RoomAudioRenderer />

          <RoomController
            onDisconnect={handleDisconnect}
            onSendMessage={onSendMessage}
            latestUserText={latestUserText}
            latestAssistantText={latestAssistantText}
          />
        </LiveKitRoom>
      ) : (
        /* Standby Welcome / Connecting View (Full Screen Living Orb, No Boxy Card) */
        <div className="flex flex-col items-center justify-center text-center py-6 px-4 max-w-md w-full animate-in fade-in">
          {/* Animated Glowing Orb Standby */}
          <div className="relative flex items-center justify-center my-6">
            <div className="absolute w-60 h-60 rounded-full bg-teal-500/20 blur-3xl animate-pulse pointer-events-none" />
            <div className="relative flex items-center justify-center w-40 h-40 sm:w-48 sm:h-48 rounded-full bg-gradient-to-tr from-teal-500 to-emerald-400 shadow-2xl shadow-teal-500/30">
              {status === "connecting" ? (
                <div className="w-12 h-12 border-3 border-slate-950/30 border-t-slate-950 rounded-full animate-spin" />
              ) : (
                <span className="text-5xl sm:text-6xl select-none">🌴</span>
              )}
            </div>
          </div>

          <h3 className="text-lg font-bold text-slate-100">
            {status === "connecting"
              ? "Đang kết nối LiveKit Voice..."
              : "Trò chuyện trực tiếp cùng TravelWise AI"}
          </h3>
          <p className="text-xs sm:text-sm text-slate-400 mt-2 max-w-sm leading-relaxed">
            {status === "connecting"
              ? "Đang thiết lập kênh âm thanh hai chiều độ trễ siêu thấp..."
              : "Trải nghiệm đàm thoại tự nhiên như gọi điện cho hướng dẫn viên bản địa."}
          </p>

          <button
            type="button"
            onClick={handleConnect}
            disabled={status === "connecting"}
            className="mt-6 px-8 py-3.5 bg-gradient-to-r from-teal-500 via-teal-400 to-emerald-400 hover:brightness-110 text-slate-950 font-bold text-sm sm:text-base rounded-2xl transition-all shadow-xl shadow-teal-500/30 active:scale-95 disabled:opacity-50 cursor-pointer flex items-center gap-2.5"
          >
            {status === "connecting" ? (
              <span>Đang kết nối...</span>
            ) : (
              <>
                <span>⚡ Bắt đầu đàm thoại</span>
              </>
            )}
          </button>
        </div>
      )}
    </div>
  );
}
