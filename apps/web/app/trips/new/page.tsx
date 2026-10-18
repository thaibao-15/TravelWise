"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { apiFetch } from "@/services/api";
import { CreateTripInput, useTrips } from "@/hooks/useTrips";

export default function NewTripPage() {
  const router = useRouter();
  const { createTrip } = useTrips(1);
  const [form, setForm] = useState<CreateTripInput>({
    name: "",
    destination_city: "",
    destination_country: "Việt Nam",
    duration_days: 3,
    start_date: "",
    end_date: "",
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const updateField = (field: keyof CreateTripInput, value: string | number) =>
    setForm((current) => ({ ...current, [field]: value }));

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!form.destination_city.trim()) {
      setError("Vui lòng nhập điểm đến.");
      return;
    }

    setIsSubmitting(true);
    setError(null);
    try {
      const trip = await createTrip({
        ...form,
        name: form.name?.trim() || undefined,
        destination_city: form.destination_city.trim(),
        destination_country: form.destination_country?.trim() || "Việt Nam",
        start_date: form.start_date || undefined,
        end_date: form.end_date || undefined,
      });

      await apiFetch(`/api/v1/trips/${trip.id}/itinerary/generate`, {
        method: "POST",
        body: JSON.stringify({ save_to_db: true }),
      });
      router.push(`/trips/${trip.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Không thể tạo lịch trình");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100 px-4 py-10">
      <div className="max-w-2xl mx-auto">
        <Link href="/trips" className="text-sm text-teal-300 hover:text-teal-200">
          ← Quay lại lịch trình
        </Link>
        <div className="mt-6 rounded-3xl bg-slate-900 border border-slate-800 p-6 sm:p-8">
          <h1 className="text-2xl font-black">Tạo lịch trình mới</h1>
          <p className="text-sm text-slate-400 mt-2">
            Nhập thông tin chuyến đi, TravelWise sẽ tạo lịch trình bằng AI.
          </p>
          {error && <p className="mt-4 rounded-xl bg-rose-500/10 border border-rose-500/30 p-3 text-sm text-rose-300">{error}</p>}
          <form onSubmit={handleSubmit} className="mt-6 space-y-4">
            <label className="block text-sm font-medium">Tên chuyến đi
              <input value={form.name} onChange={(e) => updateField("name", e.target.value)} placeholder="Ví dụ: Đà Nẵng mùa hè" className="mt-1 w-full rounded-xl bg-slate-800 border border-slate-700 px-3 py-2.5 text-sm" />
            </label>
            <div className="grid sm:grid-cols-2 gap-4">
              <label className="block text-sm font-medium">Thành phố
                <input required value={form.destination_city} onChange={(e) => updateField("destination_city", e.target.value)} placeholder="Đà Nẵng" className="mt-1 w-full rounded-xl bg-slate-800 border border-slate-700 px-3 py-2.5 text-sm" />
              </label>
              <label className="block text-sm font-medium">Quốc gia
                <input value={form.destination_country} onChange={(e) => updateField("destination_country", e.target.value)} className="mt-1 w-full rounded-xl bg-slate-800 border border-slate-700 px-3 py-2.5 text-sm" />
              </label>
            </div>
            <label className="block text-sm font-medium">Số ngày
              <input type="number" min={1} max={30} value={form.duration_days} onChange={(e) => updateField("duration_days", Number(e.target.value))} className="mt-1 w-full rounded-xl bg-slate-800 border border-slate-700 px-3 py-2.5 text-sm" />
            </label>
            <div className="grid sm:grid-cols-2 gap-4">
              <label className="block text-sm font-medium">Ngày bắt đầu
                <input type="date" value={form.start_date} onChange={(e) => updateField("start_date", e.target.value)} className="mt-1 w-full rounded-xl bg-slate-800 border border-slate-700 px-3 py-2.5 text-sm" />
              </label>
              <label className="block text-sm font-medium">Ngày kết thúc
                <input type="date" value={form.end_date} onChange={(e) => updateField("end_date", e.target.value)} className="mt-1 w-full rounded-xl bg-slate-800 border border-slate-700 px-3 py-2.5 text-sm" />
              </label>
            </div>
            <button disabled={isSubmitting} className="w-full rounded-xl bg-gradient-to-r from-teal-500 to-cyan-500 py-3 text-sm font-bold text-slate-950 disabled:opacity-50">
              {isSubmitting ? "Đang tạo lịch trình..." : "Tạo lịch trình bằng AI"}
            </button>
          </form>
        </div>
      </div>
    </main>
  );
}
