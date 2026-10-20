export type MessageRole = "user" | "assistant" | "system";

export type MessageStatus = "sending" | "success" | "error";

export interface ItineraryProposalData {
  destination: string;
  durationDays?: number;
  budget?: string;
  companions?: string;
  interests?: string[];
  tripId?: number;
}

export interface ActivityItemData {
  id?: number;
  order_index?: number;
  activity_type?: string;
  title: string;
  description?: string | null;
  start_time?: string | null;
  end_time?: string | null;
  duration_minutes?: number | null;
  estimated_cost?: number | null;
  note?: string | null;
  place?: {
    name: string;
    address?: string | null;
    category?: string | null;
  } | null;
}

export interface ItineraryDayData {
  day_number: number;
  title?: string | null;
  description?: string | null;
  activities?: ActivityItemData[];
}

export interface GeneratedItineraryData {
  trip_id: number;
  name?: string | null;
  destination?: string | null;
  destination_city?: string | null;
  duration_days: number;
  total_activities?: number;
  estimated_total_cost?: number | null;
  currency?: string;
  days?: ItineraryDayData[];
}

export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  timestamp: Date;
  status?: MessageStatus;
  errorMessage?: string;
  proposal?: ItineraryProposalData;
  itinerary?: GeneratedItineraryData;
}

export interface ChatAskRequest {
  message?: string;
  query?: string;
  conversation_id?: number | null;
  mode?: "chat" | "voice";
  current_location?: { latitude: number; longitude: number };
}

export type RAGAskRequest = ChatAskRequest;

export interface AIMessageResponse {
  id: number;
  sender: string;
  content: string;
  created_at: string;
  audio_url?: string | null;
}

export interface ChatAskResponse {
  conversation_id: number;
  message: AIMessageResponse;
  planning_context?: any;
  answer?: string;
}

export type RAGAskResponse = ChatAskResponse;

export interface SuggestedQuestion {
  id: string;
  category: string;
  title: string;
  prompt: string;
  icon: string;
}
