import axios from 'axios';

export type Todo = {
  id: string;
  title: string;
  completed: boolean;
  createdAt: string;
}

const API_BASE = import.meta.env.VITE_API_BASE_URL || '/api';

export const todoService = {
  getAll: async (): Promise<Todo[]> => {
    const response = await axios.get<Todo[]>(`${API_BASE}/todos`);
    return response.data || [];
  },

  create: async (title: string): Promise<Todo> => {
    const response = await axios.post<Todo>(`${API_BASE}/todos`, { title });
    return response.data;
  },

  toggle: async (id: string, completed: boolean): Promise<void> => {
    await axios.put(`${API_BASE}/todos/${id}`, { completed: !completed });
  },

  delete: async (id: string): Promise<void> => {
    await axios.delete(`${API_BASE}/todos/${id}`);
  },
};
