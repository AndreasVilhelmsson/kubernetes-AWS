import type { Todo } from "../services/todoService";
import { TodoItem } from "./TodoItem";
import "./TodoList.scss";

interface TodoListProps {
  todos: Todo[];
  onToggle: (id: string, completed: boolean) => void;
  onDelete: (id: string) => void;
}

export const TodoList = ({ todos, onToggle, onDelete }: TodoListProps) => {
  if (!Array.isArray(todos) || todos.length === 0) {
    return (
      <div className="todo-list__empty">No todos yet. Add one above! </div>
    );
  }

  const activeTodos = todos.filter((t) => !t.completed);
  const completedTodos = todos.filter((t) => t.completed);

  return (
    <div className="todo-list">
      {activeTodos.map((todo) => (
        <TodoItem
          key={todo.id}
          todo={todo}
          onToggle={onToggle}
          onDelete={onDelete}
        />
      ))}

      {completedTodos.length > 0 && (
        <>
          <div className="todo-list__divider">Completed</div>
          {completedTodos.map((todo) => (
            <TodoItem
              key={todo.id}
              todo={todo}
              onToggle={onToggle}
              onDelete={onDelete}
            />
          ))}
        </>
      )}
    </div>
  );
};
