"use client";

import React, {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
} from "react";
import { User, LoginRequest, RegisterRequest } from "@/types/auth";
import { AuthService } from "@/services/auth.service";

interface AuthContextType {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: (data: LoginRequest) => Promise<User>;
  register: (data: RegisterRequest) => Promise<User>;
  logout: () => void;
  refreshUser: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  // Khởi tạo trạng thái đăng nhập từ localStorage khi component mount (Hydration-safe)
  useEffect(() => {
    const savedToken = AuthService.getToken();
    const savedUser = AuthService.getCachedUser();

    if (savedToken) {
      setToken(savedToken);
      if (savedUser) {
        setUser(savedUser);
      }
      // Kiểm tra lại tính hợp lệ của token và cập nhật thông tin user mới nhất
      AuthService.getMe(savedToken)
        .then((freshUser) => {
          setUser(freshUser);
          AuthService.setCachedUser(freshUser);
        })
        .catch(() => {
          // Token đã hết hạn hoặc không hợp lệ -> tự động logout
          AuthService.logout();
          setToken(null);
          setUser(null);
        })
        .finally(() => {
          setIsLoading(false);
        });
    } else {
      setIsLoading(false);
    }
  }, []);

  const login = useCallback(async (data: LoginRequest): Promise<User> => {
    setIsLoading(true);
    try {
      const res = await AuthService.login(data);
      setToken(res.token.access_token);
      setUser(res.user);
      return res.user;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const register = useCallback(async (data: RegisterRequest): Promise<User> => {
    setIsLoading(true);
    try {
      const newUser = await AuthService.register(data);
      // Tự động đăng nhập ngay sau khi đăng ký thành công
      try {
        const loginRes = await AuthService.login({
          email: data.email,
          password: data.password,
        });
        setToken(loginRes.token.access_token);
        setUser(loginRes.user);
      } catch (loginErr) {
        console.warn("Auto login after register failed", loginErr);
      }
      return newUser;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const logout = useCallback(() => {
    AuthService.logout();
    setToken(null);
    setUser(null);
  }, []);

  const refreshUser = useCallback(async () => {
    const currentToken = AuthService.getToken();
    if (!currentToken) return;
    try {
      const freshUser = await AuthService.getMe(currentToken);
      setUser(freshUser);
      AuthService.setCachedUser(freshUser);
    } catch {
      logout();
    }
  }, [logout]);

  return (
    <AuthContext.Provider
      value={{
        user,
        token,
        isLoading,
        isAuthenticated: !!token && !!user,
        login,
        register,
        logout,
        refreshUser,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuthContext(): AuthContextType {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuthContext must be used within an AuthProvider");
  }
  return context;
}
