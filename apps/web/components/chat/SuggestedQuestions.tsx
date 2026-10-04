"use client";

import React from "react";
import { DEFAULT_SUGGESTED_QUESTIONS } from "@/lib/constants";
import { SuggestedQuestion } from "@/types/chat";

interface SuggestedQuestionsProps {
  onSelectQuestion: (prompt: string) => void;
}

export function SuggestedQuestions({ onSelectQuestion }: SuggestedQuestionsProps) {
  return (
    <div className="w-full max-w-3xl mx-auto px-4 my-6">
      <div className="flex items-center gap-2 mb-3">
        <span className="text-xs font-semibold uppercase tracking-wider text-teal-400">
          💡 Gợi ý câu hỏi phổ biến
        </span>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {DEFAULT_SUGGESTED_QUESTIONS.map((item: SuggestedQuestion) => (
          <button
            key={item.id}
            onClick={() => onSelectQuestion(item.prompt)}
            className="group flex items-start gap-3 p-3.5 text-left rounded-xl bg-slate-900/60 hover:bg-slate-900 border border-slate-800 hover:border-teal-500/40 transition-all duration-200 shadow-sm hover:shadow-teal-500/10 cursor-pointer"
          >
            <span className="text-2xl p-2 rounded-lg bg-slate-800 group-hover:scale-110 transition-transform duration-200">
              {item.icon}
            </span>
            <div className="flex-1 min-w-0">
              <span className="inline-block px-2 py-0.5 mb-1 text-[10px] font-medium rounded-full bg-slate-800 text-slate-400 group-hover:text-teal-300 group-hover:bg-teal-950/40 transition-colors">
                {item.category}
              </span>
              <h3 className="text-xs font-semibold text-slate-200 group-hover:text-teal-400 truncate">
                {item.title}
              </h3>
              <p className="text-xs text-slate-400 line-clamp-2 mt-0.5 leading-normal">
                {item.prompt}
              </p>
            </div>
            <svg
              className="w-4 h-4 text-slate-600 group-hover:text-teal-400 group-hover:translate-x-0.5 transition-all self-center flex-shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 5l7 7-7 7" />
            </svg>
          </button>
        ))}
      </div>
    </div>
  );
}
