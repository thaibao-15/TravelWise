export interface User {
  id: number;
  email: string;
  full_name?: string | null;
  avatar_url?: string | null;
  role: string;
  is_active: boolean;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface RegisterRequest {
  email: string;
  password: string;
  full_name?: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface TokenResponse {
  access_token: string;
  token_type: string;
}

export interface UpdateUserRequest {
  full_name?: string | null;
  avatar_url?: string | null;
}

export interface UserConversation {
  id: number;
  user_id?: number | null;
  title?: string | null;
  created_at: string;
  updated_at: string;
}

export interface AuthState {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
}
