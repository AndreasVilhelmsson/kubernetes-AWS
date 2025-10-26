import type { Todo } from '../services/todoService';
import './TodoStats.scss';

interface TodoStatsProps {
  todos: Todo[];
}

export const TodoStats = ({ todos }: TodoStatsProps) => {
  const active = Array.isArray(todos) ? todos.filter(t => !t.completed).length : 0;
  const completed = Array.isArray(todos) ? todos.filter(t => t.completed).length : 0;

  return (
    <div className="todo-stats">
      <span>{active} active</span>
      <span>{completed} completed</span>
    </div>
  );
};
