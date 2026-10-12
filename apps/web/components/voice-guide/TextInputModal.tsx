"use client";

import React, { useState, useRef, useEffect } from "react";

interface TextInputModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSendMessage: (text: string) => void;
  isLoading: boolean;
}

export function TextInputModal({
  isOpen,
  onClose,
  onSendMessage,
  isLoading,
}: TextInputModalProps) {
  const [text, setText] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (isOpen) {
      setTimeout(() => {
        textareaRef.current?.focus();
      }, 100);
    } else {
      setText("");
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const handleSubmit = (e?: React.FormEvent) => {
    e?.preventDefault();
    const trimmed = text.trim();
    if (!trimmed || isLoading) return;
    onSendMessage(trimmed);
    setText("");
    onClose();
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    } else if (e.key === "Escape") {
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md animate-in fade-in">
      <div
        className="fixed inset-0"
        onClick={onClose}
        aria-hidden="true"
      />

      <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-2xl z-10 animate-in zoom-in-95">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800">
          <div className="flex items-center gap-2.5">
            <span className="text-xl">⌨️</span>
            <div>
              <h3 className="text-sm font-bold text-slate-100">
                Nhập câu hỏi dự phòng
              </h3>
              <p className="text-[11px] text-slate-400">
                Dành cho lúc bạn ở nơi ồn ào hoặc không tiện nói
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition-colors cursor-pointer text-xs"
            title="Đóng"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          <textarea
            ref={textareaRef}
            rows={4}
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Hỏi TravelWise về địa điểm, giá vé, ăn uống, lịch trình du lịch..."
            className="w-full rounded-xl bg-slate-950 border border-slate-800 focus:border-teal-500/60 focus:ring-2 focus:ring-teal-500/20 text-sm text-slate-100 placeholder-slate-500 p-3 outline-none resize-none leading-relaxed custom-scrollbar"
            disabled={isLoading}
          />

          <div className="flex items-center justify-between pt-1">
            <span className="text-[11px] text-slate-500">
              Nhấn <kbd className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 text-[10px]">Enter</kbd> để gửi, <kbd className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 text-[10px]">Shift+Enter</kbd> xuống dòng
            </span>

            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={onClose}
                className="px-3.5 py-1.5 text-xs text-slate-400 hover:text-slate-200 hover:bg-slate-800 rounded-lg transition-colors cursor-pointer"
              >
                Hủy
              </button>

              <button
                type="submit"
                disabled={!text.trim() || isLoading}
                className={`px-4 py-1.5 text-xs font-semibold rounded-lg shadow-md transition-all flex items-center gap-1.5 ${
                  text.trim() && !isLoading
                    ? "bg-gradient-to-r from-teal-400 to-emerald-400 text-slate-950 hover:opacity-90 active:scale-95 cursor-pointer shadow-teal-500/25"
                    : "bg-slate-800 text-slate-500 cursor-not-allowed"
                }`}
              >
                <span>Gửi câu hỏi</span>
                <span>➔</span>
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}
