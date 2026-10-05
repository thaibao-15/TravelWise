"use client";

import React, { useState, useRef, useEffect } from "react";
import { ChatMessage as ChatMessageType } from "@/types/chat";
import { formatTime } from "@/lib/utils";
import { ttsService } from "@/services/tts.service";

interface ChatMessageProps {
  message: ChatMessageType;
  onRetry?: (id: string) => void;
}

type TTSState = "idle" | "loading" | "playing";

export function ChatMessage({ message, onRetry }: ChatMessageProps) {
  const [copied, setCopied] = useState(false);
  const [ttsState, setTtsState] = useState<TTSState>("idle");
  const [ttsError, setTtsError] = useState<string | null>(null);

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const audioUrlRef = useRef<string | null>(null);

  const isUser = message.role === "user";
  const isSending = message.status === "sending";
  const isError = message.status === "error";

  // Stop audio on unmount
  useEffect(() => {
    return () => {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }
    };
  }, []);

  const handleCopy = async () => {
    if (!message.content) return;
    try {
      await navigator.clipboard.writeText(message.content);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
    }
  };

  const handleToggleTts = async () => {
    // 1. If currently playing, stop playback
    if (ttsState === "playing") {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.currentTime = 0;
      }
      setTtsState("idle");
      return;
    }

    setTtsError(null);

    // 2. If audio was already fetched, replay directly
    if (audioUrlRef.current && audioRef.current) {
      try {
        audioRef.current.currentTime = 0;
        await audioRef.current.play();
        setTtsState("playing");
      } catch (err) {
        console.error("Audio playback error:", err);
        setTtsState("idle");
      }
      return;
    }

    // 3. Request TTS synthesis from backend
    setTtsState("loading");
    try {
      const audioUrl = await ttsService.synthesize(message.content);
      audioUrlRef.current = audioUrl;

      const audio = new Audio(audioUrl);
      audioRef.current = audio;

      audio.onended = () => {
        setTtsState("idle");
      };

      audio.onerror = () => {
        setTtsState("idle");
        setTtsError("Lỗi khi phát âm thanh.");
      };

      await audio.play();
      setTtsState("playing");
    } catch (err: unknown) {
      console.error("TTS synthesis error:", err);
      setTtsState("idle");
      setTtsError(err instanceof Error ? err.message : "Không thể tạo giọng đọc.");
      setTimeout(() => setTtsError(null), 4000);
    }
  };

  /**
   * Simple markdown content formatter for bold text, line breaks, bullet points
   */
  const renderFormattedContent = (content: string) => {
    if (!content) return null;

    const lines = content.split("\n");

    return lines.map((line, idx) => {
      // Process bold formatting **text**
      const parts = line.split(/(\*\*.*?\*\*)/g);
      const formattedLine = parts.map((part, pIdx) => {
        if (part.startsWith("**") && part.endsWith("**")) {
          return (
            <strong key={pIdx} className="font-semibold text-teal-300">
              {part.slice(2, -2)}
            </strong>
          );
        }
        return part;
      });

      // Check if bullet point
      const isBullet = line.trim().startsWith("- ") || line.trim().startsWith("* ");
      const isNumbered = /^\d+\.\s/.test(line.trim());

      if (isBullet) {
        return (
          <div key={idx} className="flex items-start gap-2 my-1 pl-1">
            <span className="text-teal-400 font-bold mt-1">•</span>
            <span className="flex-1">{formattedLine}</span>
          </div>
        );
      }

      if (isNumbered) {
        return (
          <div key={idx} className="flex items-start gap-2 my-1 pl-1">
            <span className="text-teal-400 font-bold">{line.match(/^\d+\./)?.[0]}</span>
            <span className="flex-1">
              {line.replace(/^\d+\.\s/, "").split(/(\*\*.*?\*\*)/g).map((part, pIdx) => {
                if (part.startsWith("**") && part.endsWith("**")) {
                  return (
                    <strong key={pIdx} className="font-semibold text-teal-300">
                      {part.slice(2, -2)}
                    </strong>
                  );
                }
                return part;
              })}
            </span>
          </div>
        );
      }

      return (
        <p key={idx} className={line.trim() === "" ? "h-2" : "my-0.5 leading-relaxed"}>
          {formattedLine}
        </p>
      );
    });
  };

  return (
    <div
      className={`flex items-start gap-3 my-4 max-w-3xl mx-auto px-4 ${
        isUser ? "flex-row-reverse" : "flex-row"
      }`}
    >
      {/* Avatar */}
      <div
        className={`flex-shrink-0 w-9 h-9 rounded-xl flex items-center justify-center text-sm font-semibold shadow-md ${
          isUser
            ? "bg-gradient-to-tr from-cyan-600 to-teal-500 text-slate-950"
            : "bg-slate-800 text-teal-400 border border-slate-700/80"
        }`}
      >
        {isUser ? (
          <svg className="w-5 h-5 text-slate-950" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
          </svg>
        ) : (
          <svg className="w-5 h-5 text-teal-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
          </svg>
        )}
      </div>

      {/* Message Bubble Container */}
      <div className={`flex flex-col max-w-[85%] sm:max-w-[78%] ${isUser ? "items-end" : "items-start"}`}>
        {/* Sender Name & Timestamp */}
        <div className="flex items-center gap-2 mb-1 px-1 text-[11px] text-slate-400">
          <span className="font-medium">{isUser ? "Bạn" : "TravelWise AI"}</span>
          <span>•</span>
          <span suppressHydrationWarning>{formatTime(message.timestamp)}</span>
        </div>

        {/* Bubble */}
        <div
          className={`relative px-4 py-3 text-sm rounded-2xl transition-all duration-200 ${
            isUser
              ? "bg-gradient-to-r from-teal-600 to-cyan-600 text-white rounded-tr-xs shadow-md shadow-teal-900/20"
              : "bg-slate-900/90 border border-slate-800 text-slate-200 rounded-tl-xs shadow-lg backdrop-blur-md"
          }`}
        >
          {isSending ? (
            <div className="flex items-center gap-3 py-1 text-slate-400">
              <div className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-teal-400 animate-bounce [animation-delay:-0.3s]"></span>
                <span className="w-2 h-2 rounded-full bg-teal-400 animate-bounce [animation-delay:-0.15s]"></span>
                <span className="w-2 h-2 rounded-full bg-teal-400 animate-bounce"></span>
              </div>
              <span className="text-xs text-slate-400 italic">
                Đang tra cứu dữ liệu & tổng hợp câu trả lời...
              </span>
            </div>
          ) : isError ? (
            <div className="flex flex-col gap-2">
              <div className="flex items-center gap-2 text-rose-400 font-medium">
                <svg className="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <span>{message.content}</span>
              </div>
              {message.errorMessage && (
                <p className="text-xs text-rose-300/80 bg-rose-950/40 p-2 rounded border border-rose-900/40">
                  {message.errorMessage}
                </p>
              )}
              {onRetry && (
                <button
                  onClick={() => onRetry(message.id)}
                  className="self-start mt-1 px-3 py-1 text-xs font-medium text-rose-300 bg-rose-900/30 hover:bg-rose-900/50 border border-rose-700/50 rounded-lg transition-colors flex items-center gap-1.5"
                >
                  <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                  Thử lại
                </button>
              )}
            </div>
          ) : (
            <div>{renderFormattedContent(message.content)}</div>
          )}

          {/* Action Toolbar on Assistant Message */}
          {!isUser && !isSending && !isError && (
            <div className="flex items-center justify-end gap-2 mt-2 pt-2 border-t border-slate-800/60 text-slate-500">
              {/* TTS Error Toast */}
              {ttsError && (
                <span className="text-[11px] text-amber-400 mr-auto animate-in fade-in">
                  ⚠️ {ttsError}
                </span>
              )}

              {/* TTS Speaker Button */}
              {ttsState === "loading" ? (
                <button
                  type="button"
                  disabled
                  className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] rounded-lg bg-teal-500/10 text-teal-400 border border-teal-500/30 cursor-wait animate-pulse"
                >
                  <svg className="w-3.5 h-3.5 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                  <span>⏳ Đang tạo audio...</span>
                </button>
              ) : ttsState === "playing" ? (
                <button
                  type="button"
                  onClick={handleToggleTts}
                  className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-medium rounded-lg bg-red-500/20 text-red-300 border border-red-500/40 hover:bg-red-500/30 active:scale-95 transition-all cursor-pointer shadow-sm shadow-red-500/20"
                  title="Dừng phát giọng đọc"
                >
                  <span className="w-2 h-2 rounded-sm bg-red-400"></span>
                  <span>⏹ Dừng</span>
                </button>
              ) : (
                <button
                  type="button"
                  onClick={handleToggleTts}
                  className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] rounded-lg hover:bg-slate-800 hover:text-teal-300 transition-colors cursor-pointer"
                  title="Nghe câu trả lời bằng giọng nói (Text-to-Speech)"
                >
                  <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"
                    />
                  </svg>
                  <span>🔊 Đọc</span>
                </button>
              )}

              {/* Copy Button */}
              <button
                type="button"
                onClick={handleCopy}
                className="flex items-center gap-1 px-2 py-1 text-[11px] rounded-lg hover:bg-slate-800 hover:text-slate-300 transition-colors"
                title="Sao chép câu trả lời"
              >
                {copied ? (
                  <>
                    <svg className="w-3.5 h-3.5 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7" />
                    </svg>
                    <span className="text-emerald-400 font-medium">Đã sao chép</span>
                  </>
                ) : (
                  <>
                    <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                    </svg>
                    <span>Sao chép</span>
                  </>
                )}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
