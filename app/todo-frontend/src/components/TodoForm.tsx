import { useState } from 'react';
import type { FormEvent } from 'react';
import './TodoForm.scss';

interface TodoFormProps {
  onAdd: (title: string) => Promise<void>;
}

export const TodoForm = ({ onAdd }: TodoFormProps) => {
  const [title, setTitle] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;

    setLoading(true);
    try {
      await onAdd(title);
      setTitle('');
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="todo-form">
      <input
        type="text"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="What needs to be done?"
        className="todo-form__input"
        disabled={loading}
      />
      <button type="submit" className="todo-form__button" disabled={loading}>
        {loading ? 'Adding...' : 'Add'}
      </button>
    </form>
  );
};
