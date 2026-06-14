import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { authAPI } from '../services/api';
import type { User, LoginResponse } from '../types';
import { isTokenExpired, tokenExpiresWithin } from '../utils/jwt';

const REFRESH_WITHIN_MS = 30 * 60 * 1000;
const REFRESH_CHECK_MS = 10 * 60 * 1000;

interface AuthContextType {
  user: User | null;
  token: string | null;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
  isAuthenticated: boolean;
  loading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const restoreSession = async () => {
      const storedToken = localStorage.getItem('token');
      const storedUser = localStorage.getItem('user');

      if (storedToken) {
        if (isTokenExpired(storedToken) || tokenExpiresWithin(storedToken, REFRESH_WITHIN_MS)) {
          const refreshed = await authAPI.refresh();
          if (refreshed) {
            setToken(refreshed);
            const userJson = localStorage.getItem('user');
            if (userJson) setUser(JSON.parse(userJson));
            setLoading(false);
            return;
          }
          if (isTokenExpired(storedToken)) {
            localStorage.removeItem('token');
            localStorage.removeItem('user');
            setLoading(false);
            return;
          }
        }
        setToken(storedToken);
        if (storedUser) setUser(JSON.parse(storedUser));
      }
      setLoading(false);
    };

    void restoreSession();
  }, []);

  useEffect(() => {
    const onTokenRefreshed = (event: Event) => {
      const detail = (event as CustomEvent<{ token: string; user?: User }>).detail;
      if (!detail?.token) return;
      setToken(detail.token);
      if (detail.user) setUser(detail.user);
    };
    window.addEventListener('auth:token-refreshed', onTokenRefreshed);
    return () => window.removeEventListener('auth:token-refreshed', onTokenRefreshed);
  }, []);

  useEffect(() => {
    if (!token) return undefined;
    const timer = window.setInterval(() => {
      const current = localStorage.getItem('token');
      if (current && tokenExpiresWithin(current, REFRESH_WITHIN_MS)) {
        void authAPI.refresh();
      }
    }, REFRESH_CHECK_MS);
    return () => window.clearInterval(timer);
  }, [token]);

  const login = async (username: string, password: string) => {
    const response: LoginResponse = await authAPI.login(username, password);
    setToken(response.token);
    setUser(response.user);
    localStorage.setItem('token', response.token);
    localStorage.setItem('user', JSON.stringify(response.user));
  };

  const logout = () => {
    setToken(null);
    setUser(null);
    localStorage.removeItem('token');
    localStorage.removeItem('user');
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        token,
        login,
        logout,
        isAuthenticated: !!token,
        loading,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

