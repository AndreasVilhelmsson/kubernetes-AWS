import { useState, useEffect } from "react";
import { todoService } from "./services/todoService";
import type { Todo } from "./services/todoService";
import { TodoForm } from "./components/TodoForm";
import { TodoStats } from "./components/TodoStats";
import { TodoList } from "./components/TodoList";
import "./App.scss";

function App() {
  const [todos, setTodos] = useState<Todo[]>([]);

  useEffect(() => {
    loadTodos();
  }, []);

  const loadTodos = async () => {
    try {
      const data = await todoService.getAll();
      setTodos(data);
    } catch (error) {
      console.error("Failed to load todos:", error);
    }
  };

  const handleAdd = async (title: string) => {
    await todoService.create(title);
    await loadTodos();
  };

  const handleToggle = async (id: string, completed: boolean) => {
    await todoService.toggle(id, completed);
    await loadTodos();
  };

  const handleDelete = async (id: string) => {
    await todoService.delete(id);
    await loadTodos();
  };

  return (
    <div className="app">
      <div className="app__container">
        <h1 className="app__title">Todo List</h1>
        <TodoForm onAdd={handleAdd} />
        <TodoStats todos={todos} />
        <TodoList
          todos={todos}
          onToggle={handleToggle}
          onDelete={handleDelete}
        />
      </div>
    </div>
  );
}

export default App;
