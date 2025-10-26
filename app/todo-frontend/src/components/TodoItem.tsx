import type { Todo } from '../services/todoService';
import './TodoItem.scss';

interface TodoItemProps {
  todo: Todo;
  onToggle: (id: string, completed: boolean) => void;
  onDelete: (id: string) => void;
}

export const TodoItem = ({ todo, onToggle, onDelete }: TodoItemProps) => {
  return (
    <div className={`todo-item ${todo.completed ? 'todo-item--completed' : ''}`}>
      <input
        type="checkbox"
        checked={todo.completed}
        onChange={() => onToggle(todo.id, todo.completed)}
        className="todo-item__checkbox"
      />
      <span className="todo-item__title">{todo.title}</span>
      <button onClick={() => onDelete(todo.id)} className="todo-item__delete">
        ×
      </button>
    </div>
  );
};
