import { apiFetch } from "@/services/api";
import {
  LoginRequest,
  RegisterRequest,
  TokenResponse,
  User,
} from "@/types/auth";

export const TOKEN_STORAGE_KEY = "travelwise_token";
export const USER_STORAGE_KEY = "travelwise_user";

export class AuthService {
  static getToken(): string | null {
    if (typeof window === "undefined") return null;
    try {
      return localStorage.getItem(TOKEN_STORAGE_KEY);
    } catch {
      return null;
    }
  }

  static setToken(token: string): void {
    if (typeof window === "undefined") return;
    try {
      localStorage.setItem(TOKEN_STORAGE_KEY, token);
    } catch (e) {
      console.error("Failed to save auth token to localStorage", e);
    }
  }

  static removeToken(): void {
    if (typeof window === "undefined") return;
    try {
      localStorage.removeItem(TOKEN_STORAGE_KEY);
    } catch (e) {
      console.error("Failed to remove auth token from localStorage", e);
    }
  }

  static getCachedUser(): User | null {
    if (typeof window === "undefined") return null;
    try {
      const data = localStorage.getItem(USER_STORAGE_KEY);
      return data ? (JSON.parse(data) as User) : null;
    } catch {
      return null;
    }
  }

  static setCachedUser(user: User): void {
    if (typeof window === "undefined") return;
    try {
      localStorage.setItem(USER_STORAGE_KEY, JSON.stringify(user));
    } catch (e) {
      console.error("Failed to save user to localStorage", e);
    }
  }

  static removeCachedUser(): void {
    if (typeof window === "undefined") return;
    try {
      localStorage.removeItem(USER_STORAGE_KEY);
    } catch (e) {
      console.error("Failed to remove user from localStorage", e);
    }
  }

  /**
   * Đăng ký tài khoản mới qua endpoint POST /api/v1/auth/register
   */
  static async register(data: RegisterRequest): Promise<User> {
    return apiFetch<User>("/api/v1/auth/register", {
      method: "POST",
      body: JSON.stringify({
        email: data.email.trim(),
        password: data.password,
        full_name: data.full_name?.trim() || null,
      }),
    });
  }

  /**
   * Đăng nhập lấy access_token qua endpoint POST /api/v1/auth/login
   * Sau đó tự động gọi /api/v1/auth/me để lấy thông tin user đầy đủ
   */
  static async login(
    data: LoginRequest
  ): Promise<{ token: TokenResponse; user: User }> {
    const tokenResponse = await apiFetch<TokenResponse>("/api/v1/auth/login", {
      method: "POST",
      body: JSON.stringify({
        email: data.email.trim(),
        password: data.password,
      }),
    });

    // Lưu token ngay để các request sau tự động gắn Bearer header
    AuthService.setToken(tokenResponse.access_token);

    try {
      const user = await AuthService.getMe(tokenResponse.access_token);
      AuthService.setCachedUser(user);
      return { token: tokenResponse, user };
    } catch {
      // Trường hợp không getMe được ngay thì fallback user cơ bản
      const fallbackUser: User = {
        id: 0,
        email: data.email,
        role: "USER",
        is_active: true,
      };
      return { token: tokenResponse, user: fallbackUser };
    }
  }

  /**
   * Lấy thông tin người dùng hiện tại qua endpoint GET /api/v1/auth/me
   */
  static async getMe(tokenOverride?: string): Promise<User> {
    const headers: Record<string, string> = {};
    if (tokenOverride) {
      headers["Authorization"] = `Bearer ${tokenOverride}`;
    }

    return apiFetch<User>("/api/v1/auth/me", {
      method: "GET",
      headers,
    });
  }

  /**
   * Đăng xuất, xóa token và user trong localStorage
   */
  static logout(): void {
    AuthService.removeToken();
    AuthService.removeCachedUser();
  }
}
