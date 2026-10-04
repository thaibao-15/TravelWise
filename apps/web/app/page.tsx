"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";

export default function Home() {
  const router = useRouter();
  const [quickQuery, setQuickQuery] = useState("");

  const handleSearchSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (quickQuery.trim()) {
      router.push(`/chat?q=${encodeURIComponent(quickQuery.trim())}`);
    } else {
      router.push("/chat");
    }
  };

  const popularTopics = [
    { label: "⛩️ Chùa Linh Ứng", query: "Chùa Linh Ứng ở Đà Nẵng có gì đặc biệt?" },
    { label: "🍜 Ẩm thực Hội An", query: "Gợi ý các món ăn đặc sản không thể bỏ qua ở Hội An?" },
    { label: "🗺️ Lịch trình 3N2Đ", query: "Lên kế hoạch lịch trình du lịch Đà Nẵng 3 ngày 2 đêm tối ưu nhất?" },
    { label: "🎡 Bà Nà Hills", query: "Kinh nghiệm và giá vé du lịch tự túc Bà Nà Hills?" },
  ];

  const destinations = [
    {
      name: "Đà Nẵng",
      tagline: "Thành phố đáng sống bậc nhất",
      description: "Biển Mỹ Khê cát trắng, Cầu Rồng phun lửa và bán đảo Sơn Trà hoang sơ tuyệt đẹp.",
      gradient: "from-blue-600/30 to-teal-500/20",
      accent: "text-teal-400 border-teal-500/30",
      icon: "🌊",
    },
    {
      name: "Phố cổ Hội An",
      tagline: "Di sản văn hóa thế giới",
      description: "Phố đèn lồng cổ kính ven sông Hoài, chùa Cầu và nền ẩm thực cao lầu trứ danh.",
      gradient: "from-amber-600/30 to-rose-500/20",
      accent: "text-amber-400 border-amber-500/30",
      icon: "🏮",
    },
    {
      name: "Bà Nà Hills",
      tagline: "Đường lên tiên cảnh",
      description: "Cầu Vàng biểu tượng thế giới, Làng Pháp châu Âu thu nhỏ và khí hậu 4 mùa trong 1 ngày.",
      gradient: "from-emerald-600/30 to-cyan-500/20",
      accent: "text-emerald-400 border-emerald-500/30",
      icon: "🏰",
    },
  ];

  return (
    <div className="relative min-h-screen bg-slate-950 text-slate-100 flex flex-col overflow-x-hidden selection:bg-teal-500/30 selection:text-teal-200">
      {/* Background Ambient Glows */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[1000px] h-[450px] bg-gradient-to-b from-teal-500/15 via-cyan-500/10 to-transparent blur-3xl pointer-events-none -z-10" />
      <div className="absolute top-1/3 -left-64 w-96 h-96 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none -z-10" />
      <div className="absolute top-2/3 -right-64 w-96 h-96 bg-cyan-500/10 rounded-full blur-3xl pointer-events-none -z-10" />

      {/* Navigation Header */}
      <header className="sticky top-0 z-40 backdrop-blur-xl bg-slate-950/70 border-b border-slate-800/80">
        <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
          {/* Brand Logo */}
          <Link href="/" className="flex items-center gap-2.5 group">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-teal-500 to-emerald-400 flex items-center justify-center text-slate-950 font-bold shadow-lg shadow-teal-500/20 group-hover:scale-105 transition-transform duration-200">
              <svg className="w-6 h-6 text-slate-950" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.2" d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
              </svg>
            </div>
            <div>
              <span className="text-lg font-bold tracking-tight bg-gradient-to-r from-white via-slate-100 to-teal-300 bg-clip-text text-transparent">
                TravelWise
              </span>
              <span className="hidden sm:inline-block ml-2 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wider rounded bg-teal-500/10 text-teal-400 border border-teal-500/20">
                AI Travel
              </span>
            </div>
          </Link>

          {/* Navigation Links */}
          <nav className="hidden md:flex items-center gap-6 text-sm font-medium text-slate-300">
            <Link href="/" className="text-teal-400 transition-colors">
              Trang chủ
            </Link>
            <Link href="/places" className="hover:text-teal-400 transition-colors">
              Điểm đến
            </Link>
            <Link href="/chat" className="hover:text-teal-400 transition-colors">
              Trợ lý AI
            </Link>
          </nav>

          {/* Header Action Button */}
          <div className="flex items-center gap-3">
            <Link
              href="/chat"
              className="flex items-center gap-2 px-4 py-2 text-xs sm:text-sm font-semibold text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-300 hover:from-teal-300 hover:to-emerald-200 rounded-xl shadow-md shadow-teal-500/20 hover:scale-105 active:scale-95 transition-all duration-200"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
              </svg>
              <span>Vào phòng Chat AI</span>
            </Link>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <main className="flex-1">
        <section className="pt-16 pb-20 px-4 max-w-5xl mx-auto text-center">
          {/* Badge */}
          <div className="inline-flex items-center gap-2 px-3 py-1.5 mb-6 rounded-full bg-slate-900 border border-teal-500/30 text-teal-300 text-xs font-medium shadow-inner shadow-teal-500/10">
            <span className="flex h-2 w-2 rounded-full bg-teal-400 animate-pulse"></span>
            <span>Ứng dụng công nghệ RAG & Semantic Search thông minh</span>
          </div>

          {/* Main Headline */}
          <h1 className="text-4xl sm:text-5xl md:text-6xl font-extrabold tracking-tight text-white leading-tight mb-6">
            Du lịch thông minh hơn cùng <br className="hidden sm:inline" />
            <span className="bg-gradient-to-r from-teal-400 via-cyan-300 to-emerald-400 bg-clip-text text-transparent">
              Trợ lý AI TravelWise
            </span>
          </h1>

          <p className="max-w-2xl mx-auto text-base sm:text-lg text-slate-400 mb-10 leading-relaxed">
            Hỏi đáp mọi thắc mắc về điểm đến, khách sạn, ẩm thực và lên lịch trình du lịch tối ưu chỉ trong vài giây dựa trên cơ sở tri thức du lịch chuẩn xác.
          </p>

          {/* Interactive Search / Ask Box */}
          <div className="max-w-2xl mx-auto mb-6">
            <form
              onSubmit={handleSearchSubmit}
              className="relative flex items-center p-2 rounded-2xl bg-slate-900/90 border border-slate-800 hover:border-teal-500/40 focus-within:border-teal-500 focus-within:ring-4 focus-within:ring-teal-500/20 shadow-2xl backdrop-blur-xl transition-all duration-300"
            >
              <div className="pl-3 text-teal-400">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </div>

              <input
                type="text"
                value={quickQuery}
                onChange={(e) => setQuickQuery(e.target.value)}
                placeholder="Bạn muốn hỏi gì về du lịch? (VD: Khách sạn gần biển Mỹ Khê...)"
                className="w-full bg-transparent text-sm sm:text-base text-slate-100 placeholder-slate-500 px-3 py-2 outline-none"
              />

              <button
                type="submit"
                className="flex items-center gap-1.5 px-4 sm:px-6 py-2.5 rounded-xl font-semibold text-xs sm:text-sm text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-400 hover:from-teal-300 hover:to-emerald-300 shadow-md shadow-teal-500/20 hover:scale-105 active:scale-95 transition-all duration-200 cursor-pointer flex-shrink-0"
              >
                <span>Hỏi AI</span>
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.5" d="M14 5l7 7m0 0l-7 7m7-7H3" />
                </svg>
              </button>
            </form>
          </div>

          {/* Quick Popular Topic Pills */}
          <div className="flex flex-wrap items-center justify-center gap-2 max-w-2xl mx-auto">
            <span className="text-xs text-slate-500 font-medium">Gợi ý nhanh:</span>
            {popularTopics.map((topic, i) => (
              <button
                key={i}
                onClick={() => router.push(`/chat?q=${encodeURIComponent(topic.query)}`)}
                className="px-3 py-1 text-xs rounded-full bg-slate-900 hover:bg-slate-800 text-slate-300 hover:text-teal-300 border border-slate-800 hover:border-teal-500/40 transition-all duration-200 cursor-pointer"
              >
                {topic.label}
              </button>
            ))}
          </div>
        </section>

        {/* Feature Highlights Grid */}
        <section className="py-16 px-4 max-w-6xl mx-auto border-t border-slate-800/80">
          <div className="text-center max-w-xl mx-auto mb-12">
            <h2 className="text-2xl sm:text-3xl font-bold text-white mb-3">
              Tại sao chọn TravelWise AI?
            </h2>
            <p className="text-sm text-slate-400">
              Kết hợp sức mạnh giữa mô hình ngôn ngữ lớn (LLM) và cơ sở tri thức du lịch được lưu trữ dưới dạng Vector Embeddings.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="p-6 rounded-2xl bg-slate-900/60 border border-slate-800 hover:border-teal-500/40 transition-all duration-300 shadow-sm hover:shadow-teal-500/10">
              <div className="w-12 h-12 rounded-xl bg-teal-500/10 border border-teal-500/20 flex items-center justify-center text-teal-400 mb-4">
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Tri thức RAG chuẩn xác</h3>
              <p className="text-sm text-slate-400 leading-relaxed">
                Hệ thống truy vấn dữ liệu thực tế từ cơ sở dữ liệu vector, giảm thiểu triệt để hiện tượng bịa đặt thông tin của AI thông thường.
              </p>
            </div>

            <div className="p-6 rounded-2xl bg-slate-900/60 border border-slate-800 hover:border-cyan-500/40 transition-all duration-300 shadow-sm hover:shadow-cyan-500/10">
              <div className="w-12 h-12 rounded-xl bg-cyan-500/10 border border-cyan-500/20 flex items-center justify-center text-cyan-400 mb-4">
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Lịch trình tự động</h3>
              <p className="text-sm text-slate-400 leading-relaxed">
                Tối ưu hóa hành trình du lịch từ số ngày, sở thích nghỉ dưỡng hay trải nghiệm khám phá với các gợi ý thực tế.
              </p>
            </div>

            <div className="p-6 rounded-2xl bg-slate-900/60 border border-slate-800 hover:border-emerald-500/40 transition-all duration-300 shadow-sm hover:shadow-emerald-500/10">
              <div className="w-12 h-12 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400 mb-4">
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Phản hồi siêu tốc</h3>
              <p className="text-sm text-slate-400 leading-relaxed">
                Backend tối ưu hóa với FastAPI kết hợp ChromaDB mang lại thời gian phản hồi nhanh chóng, hỗ trợ 24/7 không gián đoạn.
              </p>
            </div>
          </div>
        </section>

        {/* Popular Destinations Cards */}
        <section className="py-16 px-4 max-w-6xl mx-auto border-t border-slate-800/80">
          <div className="flex flex-col sm:flex-row sm:items-end justify-between mb-10 gap-4">
            <div>
              <span className="text-xs font-semibold uppercase tracking-wider text-teal-400">
                Khám phá tiêu biểu
              </span>
              <h2 className="text-2xl sm:text-3xl font-bold text-white mt-1">
                Điểm đến hấp dẫn hàng đầu
              </h2>
            </div>
            <Link
              href="/places"
              className="text-sm font-semibold text-teal-400 hover:text-teal-300 flex items-center gap-1 group"
            >
              <span>Xem tất cả địa điểm</span>
              <svg className="w-4 h-4 group-hover:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 5l7 7-7 7" />
              </svg>
            </Link>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {destinations.map((dest, i) => (
              <div
                key={i}
                className="group relative p-6 rounded-2xl bg-slate-900/60 border border-slate-800 hover:border-slate-700 transition-all duration-300 overflow-hidden flex flex-col justify-between"
              >
                <div className={`absolute inset-0 bg-gradient-to-br ${dest.gradient} opacity-0 group-hover:opacity-100 transition-opacity duration-300 pointer-events-none`} />

                <div>
                  <div className="flex items-center justify-between mb-4">
                    <span className="text-3xl p-2.5 rounded-xl bg-slate-800/80 border border-slate-700/60">
                      {dest.icon}
                    </span>
                    <span className={`text-[11px] font-semibold px-2.5 py-1 rounded-full border ${dest.accent} bg-slate-950/60`}>
                      {dest.tagline}
                    </span>
                  </div>

                  <h3 className="text-xl font-bold text-white mb-2">{dest.name}</h3>
                  <p className="text-sm text-slate-400 leading-relaxed mb-6">
                    {dest.description}
                  </p>
                </div>

                <button
                  onClick={() => router.push(`/chat?q=${encodeURIComponent(`Hãy giới thiệu chi tiết về du lịch tại ${dest.name}`)}`)}
                  className="w-full py-2.5 px-4 rounded-xl text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-slate-200 hover:text-teal-300 border border-slate-700/60 hover:border-teal-500/40 transition-all duration-200 flex items-center justify-center gap-2 cursor-pointer"
                >
                  <svg className="w-4 h-4 text-teal-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                  </svg>
                  <span>Hỏi AI về {dest.name}</span>
                </button>
              </div>
            ))}
          </div>
        </section>
      </main>

      {/* Floating Chat Box Button (Fixed Bottom-Right) */}
      <div className="fixed bottom-6 right-6 z-50">
        <Link
          href="/chat"
          className="group relative flex items-center gap-3 px-5 py-3.5 rounded-full bg-gradient-to-r from-teal-500 via-emerald-400 to-teal-400 text-slate-950 font-bold shadow-2xl shadow-teal-500/40 hover:scale-105 active:scale-95 transition-all duration-300 border border-teal-300/40"
          title="Mở hộp thoại Trợ lý Du lịch AI"
        >
          {/* Pulsing Glow Effect */}
          <span className="absolute -top-1 -right-1 flex h-4 w-4">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-300 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-4 w-4 bg-emerald-500 border-2 border-slate-950"></span>
          </span>

          <div className="w-6 h-6 flex items-center justify-center">
            <svg className="w-6 h-6 text-slate-950" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
            </svg>
          </div>

          <span className="text-sm tracking-wide font-extrabold text-slate-950">
            Chat với AI
          </span>
        </Link>
      </div>

      {/* Footer */}
      <footer className="border-t border-slate-800/80 bg-slate-950/80 py-8 px-4 text-center text-xs text-slate-500">
        <div className="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <p>© {new Date().getFullYear()} TravelWise. Nền tảng Du lịch Thông minh hỗ trợ bởi AI RAG.</p>
          <div className="flex items-center gap-4">
            <Link href="/chat" className="hover:text-teal-400 transition-colors">
              Trợ lý AI
            </Link>
            <Link href="/places" className="hover:text-teal-400 transition-colors">
              Điểm đến
            </Link>
            <span>•</span>
            <span className="text-teal-400">FastAPI & Next.js</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
