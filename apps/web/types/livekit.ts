export interface LiveKitTokenRequest {
  conversation_id?: number | null;
  room_name?: string | null;
}

export interface LiveKitTokenResponse {
  server_url: string;
  token: string;
  room_name: string;
  identity: string;
  conversation_id: number;
}

export interface LiveKitStatusResponse {
  is_configured: boolean;
  server_url: string | null;
  agent_name: string;
}

export type LiveKitConnectionStatus =
  | "disconnected"
  | "connecting"
  | "connected"
  | "reconnecting"
  | "error";
